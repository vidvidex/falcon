`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

module FLPMultiplier_tb;

  logic clk;
  logic in_valid, out_valid;
  logic [63:0] a;
  logic [63:0] b;
  logic [63:0] result;
  logic signed [4:0] scale_factor;

  always #5 clk = ~clk;

  FLPMultiplier FLPMultiplier(
                  .clk(clk),
                  .in_valid(in_valid),
                  .a(a),
                  .b(b),
                  .scale_factor(scale_factor),
                  .result(result),
                  .out_valid(out_valid)
                );

  initial begin

    clk = 1;
    scale_factor = 0;

    in_valid = 1;
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

    in_valid = 0;

  end

endmodule
