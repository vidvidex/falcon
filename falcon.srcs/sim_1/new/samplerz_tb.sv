`timescale 1ns/1ps

module samplerz_tb;

import falconsoar_pkg::*;

  parameter int N = 512;

  logic clk;
  logic rst_n;

  mem_addr_t src0;
  mem_addr_t src1;
  mem_addr_t dst;
  logic restart;

  logic start;
  logic done;

  always #5 clk = ~clk;


  exec_operator_if task_itf();
  mem_inst_if mem_rd();
  mem_inst_if mem_wr();

  Bi_samplerz #(.N(N))samplerz (
                .clk(clk),
                .reset(rst_n),
                .start(start),
                .restart(restart),
                .task_itf(task_itf),
                .mem_rd(mem_rd),
                .mem_wr(mem_wr),
                .done(done)
              );

  bram_model bram_inst (
               .clk(clk),
               .rst_n(rst_n),
               .mem_rd(mem_rd.slave_rd),
               .mem_wr(mem_wr.slave_wr)
             );

  initial begin

    clk = 1;

    rst_n = 0;
    #20;
    rst_n = 1;

    src0 = 32'h00000000; // Source 0 address (mu)
    src1 = 32'h00000001; // Source 1 address (inverse sigma)
    dst = 32'h00000002; // Destination address

    #20;

    restart <= 1;
    start <= 1;
    task_itf.master.input_task <= {src0, src1, dst, 13'b0, 1'b0, 4'b0, 11'b0};
    #10;
    restart <= 0;
    start <= 0;
    task_itf.master.input_task <= {src0, src1, dst, 13'b0, 1'b0, 4'b0, 11'b0};

    #1000;

    start <= 1;
    restart <= 1;
    task_itf.master.input_task <= {src0, src1, dst, 13'b0, 1'b0, 4'b0, 11'b0};
    #10;
    restart <= 0;
    start <= 0;
    task_itf.master.input_task <= {src0, src1, dst, 13'b0, 1'b0, 4'b0, 11'b0};

    while(done !== 1)
      #10;

  end

endmodule

module bram_model 
import falconsoar_pkg::*;
 (
    input logic clk,
    input logic rst_n,
    mem_inst_if.slave_rd mem_rd,
    mem_inst_if.slave_wr mem_wr
  );

  logic [255:0] mem [BANK_DEPTH];

  initial begin
    mem[0] = { 128'b0, $realtobits(33.198144682236155), $realtobits(2.4235343345)};  // mu
    mem[1] = $realtobits(1/1.724965058508814);  // inverse sigma (I guess so we can use multiplication instead of division)

    for (int i = 2; i < BANK_DEPTH; i++) begin
      mem[i] = i;
    end
  end

  // Write logic
  always_ff @(posedge clk) begin
    if (mem_wr.en)
      mem[mem_wr.addr] <= mem_wr.data;
  end

  // Read logic
  always_ff @(posedge clk) begin
    if (mem_rd.en)
      mem_rd.data <= mem[mem_rd.addr];
  end
endmodule
