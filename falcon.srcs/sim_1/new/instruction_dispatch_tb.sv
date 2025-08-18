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

  logic [1:0] algorithm_select;

  logic enable_manual_instruction_index_incr;
  logic [15:0] manual_instruction_index;
  logic manual_instruction_index_valid;
  logic [15:0] current_instruction_index;

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

                         .enable_manual_instruction_index_incr(enable_manual_instruction_index_incr),
                         .manual_instruction_index(manual_instruction_index),
                         .manual_instruction_index_valid(manual_instruction_index_valid),
                         .current_instruction_index(current_instruction_index),

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
    algorithm_select = 2'b00;
    enable_manual_instruction_index_incr = 0;
    manual_instruction_index = 0;
    manual_instruction_index_valid = 0;

    #20;

    start = 1;
    #10;
    start = 0;

  end
endmodule
