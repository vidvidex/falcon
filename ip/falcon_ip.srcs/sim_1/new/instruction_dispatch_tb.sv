`timescale 1ns / 1ps

module instruction_dispatch_tb;

  parameter N = 1024;

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
    algorithm_select = 2'b00; // sign
    // algorithm_select = 2'b01; // verify

    #20;

    start = 1;
    #10;
    start = 0;

    while (done === 1'b0)
      #10;

    if(signature_accepted == 1'b1 && signature_rejected == 1'b0)
      $display("Signature accepted");
    else if(signature_accepted == 1'b0 && signature_rejected == 1'b1)
      $display("Signature rejected");
    else
      $display("Unknown status");
    $finish;

  end
endmodule
