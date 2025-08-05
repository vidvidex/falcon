`timescale 1ns / 1ps
`include "common_definitions.vh"

module instruction_dispatch_tb;

  localparam int N = 512;

  logic clk;
  logic rst_n;
  logic start;
  logic algorithm_select; // 0 = signing, 1 = verification
  logic done;

  instruction_dispatch #(
                         .N(N)
                       ) instruction_dispatch (
                         .clk(clk),
                         .rst_n(rst_n),
                         .start(start),
                         .algorithm_select(algorithm_select),
                         .done(done)
                       );


  always #5 clk = ~clk;

  initial begin
    clk = 1;

    rst_n = 0;
    #10;
    rst_n = 1;

    #10;

    algorithm_select = 1;
    start = 1;
    #10;
    start = 0;

  end
endmodule
