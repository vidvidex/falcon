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

  logic bram_en;

  logic bram_toggle;  // 0 = bi_samplerz has access, 1 = tb has access
  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_a_samp;
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_a_samp, bram_dout_a_samp;
  logic bram_we_a_samp;
  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_b_samp;
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_b_samp, bram_dout_b_samp;
  logic bram_we_b_samp;

  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_a_tb;
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_a_tb, bram_dout_a_tb;
  logic bram_we_a_tb;
  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_b_tb;
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_b_tb, bram_dout_b_tb;
  logic bram_we_b_tb;

  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_a;
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_a, bram_dout_a;
  logic bram_we_a;
  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_b, bram_dout_b;
  logic bram_we_b;
  bram_6144x128 bram (
                  .clka(clk),
                  .addra(bram_addr_a),
                  .dina(bram_din_a),
                  .wea(bram_we_a),
                  .douta(bram_dout_a),

                  .clkb(clk),
                  .addrb(bram_addr_b),
                  .dinb(bram_din_b),
                  .web(bram_we_b),
                  .doutb(bram_dout_b)
                );

  Bi_samplerz #(.N(N))samplerz (
                .clk(clk),
                .reset(rst_n),
                .start(start),
                .restart(restart),
                .mem_rd(mem_rd),

                .bram_en(bram_en),

                .bram_addr_a(bram_addr_a_samp),
                .bram_din_a(bram_din_a_samp),
                .bram_we_a(bram_we_a_samp),
                .bram_dout_a(bram_dout_a_samp),

                .bram_addr_b(bram_addr_b_samp),
                .bram_din_b(bram_din_b_samp),
                .bram_we_b(bram_we_b_samp),
                .bram_dout_b(bram_dout_b_samp),

                .sampled1(sampled1),
                .sampled2(sampled2),
                .sampled_valid(sampled_valid),

                .isigma_addr(isigma_addr),
                .mu_addr(mu_addr),
                .seed_addr(seed_addr)
              );

  bram_model bram_inst (
               .clk(clk),
               .rst_n(rst_n),
               .mem_rd(mem_rd.slave_rd)
             );

  always_comb begin
    if(bram_toggle == 1'b0) begin
      bram_addr_a = bram_en ? bram_addr_a_samp: bram_addr_a;
      bram_din_a = bram_din_a_samp;
      bram_we_a = bram_we_a_samp;
      bram_dout_a_samp = bram_dout_a;
      bram_addr_b = bram_en ? bram_addr_b_samp : bram_addr_b;
      bram_din_b = bram_din_b_samp;
      bram_we_b = bram_we_b_samp;
      bram_dout_b_samp = bram_dout_b;
    end
    else begin
      bram_addr_a = bram_addr_a_tb;
      bram_din_a = bram_din_a_tb;
      bram_we_a = bram_we_a_tb;
      bram_dout_a_tb = bram_dout_a;
      bram_addr_b = bram_addr_b_tb;
      bram_din_b = bram_din_b_tb;
      bram_we_b = bram_we_b_tb;
      bram_dout_b_tb = bram_dout_b;
    end
  end

  initial begin
    bram_toggle = 0;
    clk = 1;

    rst_n = 0;
    #20;
    rst_n = 1;

    mu_addr = 13'd0;
    isigma_addr = 13'd1;
    seed_addr = 13'd130;
    #30;

    // Populate BRAM
    bram_toggle = 1;
    bram_addr_a_tb <= 0; // Mu
    bram_din_a_tb <= {$realtobits(33.198144682236155), $realtobits(2.4235343345)};
    bram_we_a_tb <= 1;
    bram_addr_b_tb <= 1; // Inverse sigma
    bram_din_b_tb <= {64'b0, $realtobits(1/1.724965058508814)};
    bram_we_b_tb <= 1;
    #10;

    bram_addr_a_tb <= seed_addr + 0; // Seed
    bram_din_a_tb <= 128'h0000000011111111_2222222233333333;
    bram_we_a_tb <= 1;
    bram_addr_b_tb <= seed_addr + 2;
    bram_din_b_tb <= 128'h4444444455555555_6666666677777777;
    bram_we_b_tb <= 1;
    #10;

    bram_addr_a_tb <= seed_addr + 1; // Seed
    bram_din_a_tb <= 128'h8888888899999999_aaaaaaaabbbbbbbb;
    bram_we_a_tb <= 1;
    bram_addr_b_tb <= seed_addr + 3;
    bram_din_b_tb <= 128'hccccccccdddddddd_eeeeeeeeffffffff;
    bram_we_b_tb <= 1;
    #10;

    bram_we_a_tb <= 0;
    bram_we_b_tb <= 0;
    #10;
    bram_toggle = 0;
    // End populate BRAM

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
  logic [255:0] data_i;

  initial begin
    mem[0] = { 128'b0, $realtobits(33.198144682236155), $realtobits(2.4235343345)};  // mu
    mem[1] = $realtobits(1/1.724965058508814);  // inverse sigma (I guess so we can use multiplication instead of division)

    for (int i = 2; i < BANK_DEPTH; i++) begin
      mem[i] = i;
    end
  end

  // Read logic
  always_ff @(posedge clk) begin
    if (mem_rd.en)
      data_i <= mem[mem_rd.addr];
  end

  always_ff @(posedge clk) begin
      mem_rd.data <= data_i;
  end
endmodule
