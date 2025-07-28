`timescale 1ns / 1ps
`include "common_definitions.vh"

module fp_multiplier_tb;

  logic clk;
  logic valid_in, valid_out;
  logic [63:0] a;
  logic [63:0] b;
  logic [63:0] result;
  logic signed [4:0] scale_factor;

  always #5 clk = ~clk;

  fp_multiplier fp_multiplier(
                  .clk(clk),
                  .valid_in(valid_in),
                  .a(a),
                  .b(b),
                  .scale_factor(scale_factor),
                  .result(result),
                  .valid_out(valid_out)
                );

  initial begin

    clk = 1;
    scale_factor = 0;

    valid_in = 1;
    a = $realtobits(2.0);
    b = $realtobits(-4.5);
    #10;

    a = $realtobits(1.0);
    b = $realtobits(1.5);
    #10;

    a = $realtobits(-12.1);
    b = $realtobits(-3.0);
    #10;

    a = $realtobits(0.0);
    b = $realtobits(0.0);
    #10;

    valid_in = 0;

  end

endmodule
