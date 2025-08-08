`timescale 1ns / 1ps
`include "common_definitions.vh"

module instruction_dispatch_tb;

  localparam int N = 512;

  logic clk;
  logic rst_n;
  logic start;
  logic algorithm_select; // 0 = signing, 1 = verification
  logic done;

  logic dma_bram_en;
  logic [19:0] dma_bram_addr;
  logic [15:0] dma_bram_byte_we;
  logic[127:0] dma_bram_din;
  logic [127:0] dma_bram_dout;

  instruction_dispatch #(
                         .N(N)
                       ) instruction_dispatch (
                         .clk(clk),
                         .rst_n(rst_n),
                         .start(start),
                         .algorithm_select(algorithm_select),
                         .done(done),

                         .dma_bram_en(dma_bram_en),
                         .dma_bram_addr(dma_bram_addr),
                         .dma_bram_din(dma_bram_din),
                         .dma_bram_dout(dma_bram_dout),
                         .dma_bram_byte_we(dma_bram_byte_we)
                       );


  always #5 clk = ~clk;

  initial begin
    dma_bram_en = 0;
    dma_bram_addr = 0;
    dma_bram_byte_we = 0;
    dma_bram_din = 0;

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
