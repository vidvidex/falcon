`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements compression of Falcon coefficients to a compressed string
//
// Module can compress one coefficient per clock cycle. The compressed representation
// of the coefficient is appended to the compressed signature.
// After all coefficients have been compressed, the "valid" signal should be deasserted
// and the "finalize" signal should be asserted for one clock cycle. This will pad the
// compressed signature with zeros to the expected length.
//
// In case the compressed signature is longer than the expected length, the "error" signal
// will be asserted.
//
//////////////////////////////////////////////////////////////////////////////////


module compress#(
    parameter integer SIGNATURE_LENGTH               //! Expected length of the compressed signature in bytes (slen in reference code)
  )(
    input logic clk,
    input logic rst,

    input signed [11:0] coefficient, //! Next coefficient to compress, compressed representation will be appended to "compressed_signature"
    input logic valid, //! Indicates that "coefficient" is valid and should be compressed
    input logic finalize, //! Indicates that all coefficient have been compressed and that the padding should be added

    output logic [SIGNATURE_LENGTH*8-1:0] compressed_signature, //! Compressed signature containing all compressed coefficients (when done)
    output logic error //! Error signal, something went wrong while compressing
  );

  logic [$clog2(SIGNATURE_LENGTH)-1+3:0] compressed_so_far; //! Number of bits (not bytes!) of compressed signature processed so far.
  logic [23:0] compressed_coefficient; //! Compressed representation of the current coefficient. Some of the bottom bits of this can be undefined, since they are rarely all used.
  logic [4:0] compressed_coefficient_length; //! Number of bits used to compress the current coefficient

  compress_coefficient compress_coefficient (
                         .coefficient(coefficient),
                         .compressed_coefficient(compressed_coefficient),
                         .compressed_coefficient_length(compressed_coefficient_length)
                       );

  always_ff @(posedge clk) begin
    if (rst == 1'b0) begin
      error <= 1'b0;
    end
    else begin

      if (valid) begin
        if (compressed_so_far > SIGNATURE_LENGTH*8)
          // Processed more bits than expected
          error <= 1'b1;
      end
    end
  end

  // Most of the processing in this module is done on a negative edge of the clock
  // This is because on a positive edge the coefficients are changed and we cannot append them to the compressed signature and shift it immediately
  always_ff @(negedge clk) begin
    if (rst == 1'b0) begin
      compressed_signature <= 0;
      compressed_so_far <= 0;
    end
    else if(valid) begin
      // Update the number of bits processed so far
      compressed_so_far <= compressed_so_far + compressed_coefficient_length;

      // Append the compressed coefficient to the compressed signature
      // This is done by shifting the compressed signature to the left by the number of bits used to compress the coefficient
      // and then appending the compressed coefficient, which is shifted all the way to the right, because only the top "compressed_coefficient_length" bits of
      // "compressed_coefficient" are valid
      compressed_signature <= (compressed_signature << compressed_coefficient_length) | (compressed_coefficient >> 24-compressed_coefficient_length);
    end
    else if (finalize)
      // After all coefficients have been compressed, pad the compressed signature with zeros
      compressed_signature <= compressed_signature << (SIGNATURE_LENGTH*8 - compressed_so_far);
  end

endmodule

