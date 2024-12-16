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
    parameter integer SIGNATURE_LENGTH
  )(
    input logic clk,
    input logic rst_n,

    input logic [104:0] compressed_signature, //! Compressed signature
    input logic [104:0] compressed_signature_valid, //! Is the compressed signature valid. Bitwise.
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

  logic [104:0] shifted_compressed_signature_valid; //! Shifted compressed signature valid, used to check if the coefficient is valid

  decompress_coefficient decompress_coefficient (
                           .compressed_signature(compressed_signature),
                           .coefficient(coefficient),
                           .compressed_coef_length(compressed_coef_length),
                           .coefficient_error(coefficient_error_i)
                         );

  always_ff @(posedge clk) begin
    if (rst_n  == 1'b0) begin
      coefficient_error <= 1'b0;
      signature_length_error <= 1'b0;
      bits_processed <= 0;
      decompression_done <= 0;
    end
    else begin
      if(coefficient_valid) begin
        // Update the number of bits processed
        bits_processed <= bits_processed + compressed_coef_length;

        // If there was an error in the coefficient, set the error flag
        coefficient_error <= coefficient_error || coefficient_error_i;
      end

      if (bits_processed > expected_signature_length_bytes*8)
        signature_length_error <= 1'b1;  // Signature is not of the expected length, set the error flag (algorithm 18, line 1)
    end
  end

  // Check if we processed all the bits of the compressed signature
  always_ff @(negedge coefficient_valid) begin
    // Check if the number of bits processed is less or equal to the expected length of the compressed signature
    // In case it is less than the expected length also check if the remaining bits are all zeros (there can be up to 7 bits of padding)
    if (bits_processed <= expected_signature_length_bytes*8 && compressed_signature[104:98] == 7'b0)
      decompression_done <= 1'b1;  // We processed all the bits of the compressed signature
    else
      signature_length_error <= 1'b1;  // Signature is not of the expected length, set the error flag (algorithm 18, line 1)
  end

  // We check if the coefficient is valid by checking if all bits of the compressed signature are valid
  // We do that by checking if the rightmost big of compressed_signature_valid is 1, in that case all bits of the coefficient are valid
  assign shifted_compressed_signature_valid = compressed_signature_valid << compressed_coef_length-1;
  assign coefficient_valid = shifted_compressed_signature_valid[104];

  assign signature_error = coefficient_error || signature_length_error;

endmodule
