`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements decompression of Falcon coefficients from compressed string.
//
// Decompression is finished when decompression_done signal is set high.
// If at any point during decompression the signal signature_error is set high then an error was detected in the signature.
//
// To check if the signature is not too long (algorithm 18, line 1), we compare the number of bits processed with the expected length of the compressed signature.
//
//////////////////////////////////////////////////////////////////////////////////


module decompress #(
    parameter int N,
    parameter int SIGNATURE_LENGTH
  )(
    input logic clk,
    input logic rst_n,

    input logic [104:0] compressed_signature, //! Compressed signature
    input logic [6:0] compressed_signature_valid_bits, //! Number of valid bits in compressed signature (from the left)
    input logic [$clog2(SIGNATURE_LENGTH)-1:0] expected_signature_length_bytes, //! Expected length of the compressed signature in bytes (slen in reference code)

    output logic [14:0] coefficient, //! Decompressed coefficient
    output logic coefficient_valid, //! Is the current coefficient valid?
    output logic [6:0] compressed_coef_length, //! Number of bits used to compress the current coefficient. Parent module should shift "compressed_signature" to the left by "compressed_coef_length" bits to get the next compressed coefficient
    output logic signature_error,    //! Was an error detected in the signature?
    output logic decompression_done      //! Is decompression finished?
  );

  logic [$clog2(SIGNATURE_LENGTH)-1+3:0] bits_processed; //! Number of bits (not bytes!) of compressed signature processed so far.

  logic coefficient_error_i;  //! Was an error detected while decompressing current coefficient?
  logic coefficient_error; //! Was an error detected while decompressing any coefficient?
  logic signature_length_error; //! Was the signature not of the expected length?
  logic [14:0] coefficient_i; //! Internal version of the coefficient
  logic [$clog2(N):0] decompressed_count; //! Number of coefficients decompressed so far

  decompress_coefficient decompress_coefficient (
                           .compressed_signature(compressed_signature),
                           .coefficient(coefficient_i),
                           .compressed_coef_length(compressed_coef_length),
                           .coefficient_error(coefficient_error_i)
                         );

  always_ff @(posedge clk) begin
    if (rst_n  == 1'b0) begin
      coefficient_error <= 1'b0;
      signature_length_error <= 1'b0;
      bits_processed <= 0;
      decompression_done <= 0;
      decompressed_count <= 0;
    end
    else begin

      // Do nothing if we have no valid data
      if(compressed_signature_valid_bits > 0) begin

        if(coefficient_valid) begin
          // Update the number of bits processed
          bits_processed = bits_processed + compressed_coef_length;

          decompressed_count = decompressed_count + 1;

          // If there was an error in the coefficient, set the error flag
          coefficient_error <= coefficient_error || coefficient_error_i;
        end
        else begin
          // Check if the number of bits processed is less or equal to the expected length of the compressed signature
          // In case it is less than the expected length also check if the remaining bits are all zeros (there can be up to 7 bits of padding)
          if (bits_processed <= expected_signature_length_bytes*8 && compressed_signature[104:98] == 7'b0)
            decompression_done <= 1'b1;  // We processed all the bits of the compressed signature
          else
            signature_length_error <= 1'b1;  // Signature is not of the expected length, set the error flag (algorithm 18, line 1)
        end

        if (bits_processed > expected_signature_length_bytes*8)
          signature_length_error <= 1'b1;  // Signature is not of the expected length, set the error flag (algorithm 18, line 1)
      end
    end

  end

  // Check if coefficient is valid by checking if all bits that were used to decompress the coefficient are valid
  assign coefficient_valid = compressed_coef_length <= compressed_signature_valid_bits && decompressed_count < N;

  assign coefficient = coefficient_valid ? coefficient_i : 0;

  assign signature_error = coefficient_error || signature_length_error;

endmodule
