`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

module FLPAdder_tb;

  logic clk;
  logic start, done;
  logic [`OVERALL_BITS-1:0] a;
  logic [`OVERALL_BITS-1:0] b;
  logic [`OVERALL_BITS-1:0] result;

  always #5 clk = ~clk;

  FLPAdder #(
             .DO_SUBSTRACTION(0)  // 0 for addition, 1 for subtraction
           ) FLPAdder(
             .clk(clk),
             .start(start),
             .a(a),
             .b(b),
             .result(result),
             .done(done)
           );

  initial begin

    clk = 1;

    a = $realtobits(1.0);
    b = $realtobits(2.0);
    start = 1;
    #10;

    a = $realtobits(10.5);
    b = $realtobits(20.5);
    start = 1;
    #10;

    a = $realtobits(4.5);
    b = $realtobits(8.5);
    start = 1;
    #10;
    start = 0;

  end

endmodule
