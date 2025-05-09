`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

module mul_tb;

  logic clk;
  logic start, done;
  logic [`OVERALL_BITS-1:0] a;
  logic [`OVERALL_BITS-1:0] b;
  logic [`OVERALL_BITS-1:0] result;

  always #5 clk = ~clk;

  FLPMultiplier multiplier(
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
    a = $realtobits(-5.0);
    b = $realtobits(2.0);
    #10;
    start = 0;
  end

endmodule
