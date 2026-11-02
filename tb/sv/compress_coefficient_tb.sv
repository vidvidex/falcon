`timescale 1ns / 1ps

// Checks compress_coefficient: sign, 7 low bits and the high bits in unary (at most 24 bits), and too_large for
// coefficients that cannot be compressed (|coefficient| > 2047)
module compress_coefficient_tb;

  logic clk;
  logic signed [14:0] coefficient;
  logic coefficient_valid;
  logic [23:0] compressed_coefficient;
  logic [4:0] compressed_coefficient_length;
  logic too_large;

  compress_coefficient uut (
                         .clk(clk),
                         .coefficient(coefficient),
                         .coefficient_valid(coefficient_valid),
                         .compressed_coefficient(compressed_coefficient),
                         .compressed_coefficient_length(compressed_coefficient_length),
                         .too_large(too_large)
                       );

  always #5 clk = ~clk;

  task automatic check(input logic signed [14:0] value, input logic [23:0] expected, input int expected_length);
    logic [23:0] shifted;
    coefficient = value;
    coefficient_valid = 1;
    @(posedge clk);
    #1;
    if (too_large !== 1'b0)
      $fatal(1, "Coefficient %0d: too_large set", value);
    // Only the top compressed_coefficient_length bits are valid; shift them down for comparison
    shifted = compressed_coefficient >> (24 - compressed_coefficient_length);
    if (compressed_coefficient_length !== expected_length)
      $fatal(1, "Coefficient %0d: expected length %0d, got %0d", value, expected_length, compressed_coefficient_length);
    if (shifted !== expected)
      $fatal(1, "Coefficient %0d: expected compressed coefficient %b, got %b", value, expected, shifted);
    if (24'(compressed_coefficient << compressed_coefficient_length) !== 0)
      $fatal(1, "Coefficient %0d: bits after the valid part are not zero", value);
  endtask

  task automatic check_too_large(input logic signed [14:0] value);
    coefficient = value;
    coefficient_valid = 1;
    @(posedge clk);
    #1;
    if (too_large !== 1'b1 || compressed_coefficient_length !== 0)
      $fatal(1, "Coefficient %0d: expected too_large and length 0, got too_large=%b, length %0d", value, too_large,
             compressed_coefficient_length);
  endtask

  initial begin
    clk = 0;
    coefficient_valid = 0;
    coefficient = 0;
    @(posedge clk);

    check(113, 24'b011100011, 9);
    check(-137, 24'b1000100101, 10);
    check(0, 24'b000000001, 9);
    check(-1, 24'b100000011, 9);
    check(127, 24'b011111111, 9);
    check(128, 24'b0000000001, 10);
    check(-255, 24'b1111111101, 10);
    check(1000, 24'b0110100000000001, 16);
    check(-2047, 24'b111111110000000000000001, 24);
    check(2047, 24'b011111110000000000000001, 24);

    check_too_large(2048);
    check_too_large(-2048);
    check_too_large(16383);
    check_too_large(-16384);

    // No valid input: output must be cleared
    coefficient_valid = 0;
    @(posedge clk);
    #1;
    if (compressed_coefficient !== 0 || compressed_coefficient_length !== 0 || too_large !== 0)
      $fatal(1, "Output not cleared when coefficient_valid is low");

    $display("All tests for compress_coefficient passed!");
    $finish;
  end

endmodule
