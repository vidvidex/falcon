`timescale 1ns/1ps

module samplerz_tb;

import falconsoar_pkg::*;

  parameter int N = 512;

  logic clk;
  logic rst_n;

  logic restart;

  logic start;

  logic [63:0] sampled1;
  logic [63:0] sampled2;
  logic sampled_valid;

  logic [MEM_ADDR_BITS - 1:0] isigma_addr;
  logic [MEM_ADDR_BITS - 1:0] mu_addr;
  logic [MEM_ADDR_BITS - 1:0] seed_addr;

  always #5 clk = ~clk;

  mem_inst_if mem_rd();

  Bi_samplerz #(.N(N))samplerz (
                .clk(clk),
                .reset(rst_n),
                .start(start),
                .restart(restart),
                .mem_rd(mem_rd),
                .sampled1(sampled1),
                .sampled2(sampled2),
                .isigma_addr(isigma_addr),
                .mu_addr(mu_addr),
                .seed_addr(seed_addr),
                .sampled_valid(sampled_valid)
              );

  bram_model bram_inst (
               .clk(clk),
               .rst_n(rst_n),
               .mem_rd(mem_rd.slave_rd)
             );

  initial begin

    clk = 1;

    rst_n = 0;
    #20;
    rst_n = 1;

    mu_addr = 13'd0;
    isigma_addr = 13'd1;
    seed_addr = 13'd130;
    #20;

    restart <= 1;
    start <= 1;
    #10;
    restart <= 0;
    start <= 0;

    #1000;

    start <= 1;
    restart <= 1;
    #10;
    restart <= 0;
    start <= 0;

    while(sampled_valid !== 1)
      #10;

    start <= 1;
    #10;
    start <= 0;

    while(sampled_valid !== 1)
      #10;

    start <= 1;
    #10;
    start <= 0;

    while(sampled_valid !== 1)
      #10;

    start <= 1;
    #10;
    start <= 0;

  end

endmodule

module bram_model 
import falconsoar_pkg::*;
 (
    input logic clk,
    input logic rst_n,
    mem_inst_if.slave_rd mem_rd
  );

  logic [255:0] mem [BANK_DEPTH];

  initial begin
    mem[0] = { 128'b0, $realtobits(33.198144682236155), $realtobits(2.4235343345)};  // mu
    mem[1] = $realtobits(1/1.724965058508814);  // inverse sigma (I guess so we can use multiplication instead of division)

    for (int i = 2; i < BANK_DEPTH; i++) begin
      mem[i] = i;
    end

    // Seed is 384 bits (256 + top 128 of second part). We'll read read this via 2 ports in our 128 bit BRAM
    mem[130] = 256'h0000000011111111_2222222233333333_4444444455555555_6666666677777777;
    mem[131] = 256'h8888888899999999_aaaaaaaabbbbbbbb_ccccccccdddddddd_eeeeeeeeffffffff;
  end

  // Read logic
  always_ff @(posedge clk) begin
    if (mem_rd.en)
      mem_rd.data <= mem[mem_rd.addr];
  end
endmodule
