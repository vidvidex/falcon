`timescale 1ns / 1ps

module compress_coefficient_tb;

  logic clk;
  logic signed [14:0] coefficient;
  logic coefficient_valid;
  logic [104:0] compressed_coefficient;
  logic [6:0] compressed_coefficient_length;

  compress_coefficient uut (
                         .clk(clk),
                         .coefficient(coefficient),
                         .coefficient_valid(coefficient_valid),
                         .compressed_coefficient(compressed_coefficient),
                         .compressed_coefficient_length(compressed_coefficient_length)
                       );

  always #5 clk = ~clk;

  task automatic check(input logic signed [14:0] value, input logic [104:0] expected, input int expected_length);
    logic [104:0] shifted;
    coefficient = value;
    coefficient_valid = 1;
    @(posedge clk);
    #1;
    // Only the top compressed_coefficient_length bits are valid; shift them down for comparison
    shifted = compressed_coefficient >> (105 - compressed_coefficient_length);
    if (compressed_coefficient_length !== expected_length)
      $fatal(1, "Coefficient %0d: expected length %0d, got %0d", value, expected_length, compressed_coefficient_length);
    if (shifted !== expected)
      $fatal(1, "Coefficient %0d: expected compressed coefficient %b, got %b", value, expected, shifted);
    if ((compressed_coefficient << compressed_coefficient_length) !== 0)
      $fatal(1, "Coefficient %0d: bits after the valid part are not zero", value);
  endtask

  initial begin
    clk = 0;
    coefficient_valid = 0;
    coefficient = 0;
    @(posedge clk);

    check(113, 105'b011100011, 9);
    check(-137, 105'b1000100101, 10);
    check(0, 105'b000000001, 9);
    check(-1, 105'b100000011, 9);
    check(127, 105'b011111111, 9);
    check(128, 105'b0000000001, 10);
    check(-255, 105'b1111111101, 10);
    check(1000, 105'b0110100000000001, 16);
    check(-2047, 105'b111111110000000000000001, 24);

    // No valid input: output must be cleared
    coefficient_valid = 0;
    @(posedge clk);
    #1;
    if (compressed_coefficient !== 0 || compressed_coefficient_length !== 0)
      $fatal(1, "Output not cleared when coefficient_valid is low");

    $display("All tests for compress_coefficient passed!");
    $finish;
  end

endmodule
