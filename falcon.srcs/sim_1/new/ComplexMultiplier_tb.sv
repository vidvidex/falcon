`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

module ComplexMultiplier_tb;

  logic clk;
  logic start, done;
  logic [`OVERALL_BITS-1:0] a_real, a_imag;
  logic [`OVERALL_BITS-1:0] b_real, b_imag;
  logic [`OVERALL_BITS-1:0] result_real, result_imag;
  logic signed [4:0] scale_factor;

  always #5 clk = ~clk;

  ComplexMultiplier ComplexMultiplier(
                      .clk(clk),
                      .start(start),
                      .a_real(a_real),
                      .a_imag(a_imag),
                      .b_real(b_real),
                      .b_imag(b_imag),
                      .scale_factor(scale_factor),
                      .a_x_b_real(result_real),
                      .a_x_b_imag(result_imag),
                      .done(done)
                    );

  initial begin

    clk = 1;
    scale_factor = -1;

    start = 1;
    a_real = $realtobits(1.5);
    a_imag = $realtobits(2.5);
    b_real = $realtobits(3.5);
    b_imag = $realtobits(4.5);
    #10;

    a_real = $realtobits(2.5);
    a_imag = $realtobits(4.5);
    b_real = $realtobits(8.5);
    b_imag = $realtobits(16.5);
    #10;

    start = 0;

  end

endmodule
