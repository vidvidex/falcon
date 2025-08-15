`timescale 1ns / 1ps

module instruction_dispatch_tb;

  parameter N = 512;

  logic clk, rst_n;

  logic ext_bram_en;
  logic [19:0] ext_bram_addr;
  logic [15:0] ext_bram_we;
  logic [127:0] ext_bram_din;
  logic [127:0] ext_bram_dout;

  logic start;
  logic done;
  logic signature_accepted;
  logic signature_rejected;

  logic algorithm_select;

  instruction_dispatch #(
                         .N(N)
                       ) instruction_dispatch (
                         .clk(clk),
                         .rst_n(rst_n),
                         .start(start),
                         .algorithm_select(algorithm_select),

                         .done(done),
                         .signature_accepted(signature_accepted),
                         .signature_rejected(signature_rejected),

                         .ext_bram_en(ext_bram_en),
                         .ext_bram_addr(ext_bram_addr),
                         .ext_bram_din(ext_bram_din),
                         .ext_bram_dout(ext_bram_dout),
                         .ext_bram_we(ext_bram_we)
                       );


  always #5 clk = ~clk;

  initial begin

    ext_bram_en = 0;

    clk = 1;

    rst_n = 0;
    #10;
    rst_n = 1;

    #20;

    algorithm_select = 0;
    start = 1;
    #10;
    start = 0;

  end
endmodule
