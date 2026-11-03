`timescale 1ns / 1ps

// Checks decompress_coefficient (combinational): coefficient, bits used and error flags for single encodings
module decompress_coefficient_tb;

  logic [23:0] compressed_signature;
  logic [4:0] valid_bits;

  logic [14:0] coefficient;
  logic [4:0] bits_used;
  logic coefficient_valid;
  logic invalid_bits_used_error;
  logic invalid_zero_representation_error;

  decompress_coefficient uut (
                           .compressed_signature(compressed_signature),
                           .valid_bits(valid_bits),

                           .coefficient(coefficient),
                           .bits_used(bits_used),
                           .coefficient_valid(coefficient_valid),
                           .invalid_bits_used_error(invalid_bits_used_error),
                           .invalid_zero_representation_error(invalid_zero_representation_error)
                         );

  // Checks a valid encoding
  task automatic check(input logic [23:0] bits, input int valid, input logic signed [14:0] expected, input int expected_bits_used);
    compressed_signature = bits;
    valid_bits = valid;
    #1;
    if (coefficient_valid !== 1'b1 || invalid_bits_used_error !== 1'b0 || invalid_zero_representation_error !== 1'b0)
      $fatal(1, "%b: expected a valid coefficient, got valid=%b, invalid_bits_used=%b, invalid_zero=%b", bits,
             coefficient_valid, invalid_bits_used_error, invalid_zero_representation_error);
    if ($signed(coefficient) !== expected || bits_used !== expected_bits_used)
      $fatal(1, "%b: expected %0d (%0d bits), got %0d (%0d bits)", bits, expected, expected_bits_used, $signed(coefficient), bits_used);
  endtask

  // Checks an invalid encoding
  task automatic check_error(input logic [23:0] bits, input int valid, input logic bits_error, input logic zero_error);
    compressed_signature = bits;
    valid_bits = valid;
    #1;
    if (coefficient_valid !== 1'b0 || invalid_bits_used_error !== bits_error || invalid_zero_representation_error !== zero_error)
      $fatal(1, "%b: expected valid=0, invalid_bits_used=%b, invalid_zero=%b, got valid=%b, invalid_bits_used=%b, invalid_zero=%b",
             bits, bits_error, zero_error, coefficient_valid, invalid_bits_used_error, invalid_zero_representation_error);
  endtask

  initial begin
    check(24'b0_0010111_0100000000000000, 10, 151, 10);    // positive
    check(24'b1_0011100_0100000000000000, 10, -156, 10);   // negative
    check(24'b0_0000000_1000000000000000, 9, 0, 9);        // zero
    check(24'b0_1111111_0000000000000001, 24, 2047, 24);   // largest
    check(24'b1_1111111_0000000000000001, 24, -2047, 24);  // smallest

    check_error(24'b1_0011100_0100000000000000, 5, 1, 0);   // needs 10 bits, only 5 valid
    check_error(24'b1_0000000_1000000000000000, 9, 0, 1);   // "-0"
    check_error(24'b0_0000011_0000000000000000, 24, 1, 0);  // no terminating one: |s| > 2047

    // No valid bits: nothing is decoded
    valid_bits = 0;
    #1;
    if (coefficient_valid !== 1'b0 || invalid_bits_used_error !== 1'b0)
      $fatal(1, "Coefficient decoded without valid bits");

    $display("All tests for decompress_coefficient passed!");
    $finish;
  end

endmodule
