`timescale 1ns / 1ps
`include "common_definitions.vh"

module flp_adder_tb;

  logic clk;
  logic in_valid, out_valid;
  logic [63:0] a;
  logic [63:0] b;
  logic [63:0] result;

  always #5 clk = ~clk;

  flp_adder #(
             .DO_SUBSTRACTION(0)  // 0 for addition, 1 for subtraction
           ) flp_adder(
             .clk(clk),
             .in_valid(in_valid),
             .a(a),
             .b(b),
             .result(result),
             .out_valid(out_valid)
           );

  initial begin

    clk = 1;

    a = $realtobits(1.0);
    b = $realtobits(2.0);
    in_valid = 1;
    #10;

    a = $realtobits(10.5);
    b = $realtobits(20.5);
    in_valid = 1;
    #10;

    a = $realtobits(4.5);
    b = $realtobits(8.5);
    in_valid = 1;
    #10;
    in_valid = 0;

  end

endmodule
