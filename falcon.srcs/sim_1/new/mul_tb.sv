`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

module mul_tb;

  logic clk;
  logic start, done;
  logic [`OVERALL_BITS-1:0] a;
  logic [`OVERALL_BITS-1:0] b;
  logic [`OVERALL_BITS-1:0] result;

  always #5 clk = ~clk;

  FLPMultiplier FLPMultiplier(
                  .clk(clk),
                  .start(start),
                  .a(a),
                  .b(b),
                  .result(result),
                  .done(done)
                );

  initial begin

    clk = 1;

    start = 1;
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

    start = 0;

  end

endmodule
