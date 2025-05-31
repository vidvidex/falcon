`timescale 1ns / 1ps

module fft_tb;

  parameter int N = 512;

  logic clk,rst;
  logic mode;
  logic start;
  logic done;

  logic [$clog2(N)-1:0] bram1_addr_a, bram1_addr_b;
  logic [127:0] bram1_din_a, bram1_din_b;
  logic [127:0] bram1_dout_a, bram1_dout_b;
  logic bram1_we_a, bram1_we_b;
  fft_bram_512 fft_bram_512_1 (
                 .addra(bram1_addr_a),
                 .clka(clk),
                 .dina(bram1_din_a),
                 .douta(bram1_dout_a),
                 .wea(bram1_we_a),

                 .addrb(bram1_addr_b),
                 .clkb(clk),
                 .dinb(bram1_din_b),
                 .doutb(bram1_dout_b),
                 .web(bram1_we_b)
               );

  logic [$clog2(N)-1:0] bram2_addr_a, bram2_addr_b;
  logic [127:0] bram2_din_a, bram2_din_b;
  logic [127:0] bram2_dout_a, bram2_dout_b;
  logic bram2_we_a, bram2_we_b;
  fft_bram_512 fft_bram_512_2 (
                 .addra(bram2_addr_a),
                 .clka(clk),
                 .dina(bram2_din_a),
                 .douta(bram2_dout_a),
                 .wea(bram2_we_a),

                 .addrb(bram2_addr_b),
                 .clkb(clk),
                 .dinb(bram2_din_b),
                 .doutb(bram2_dout_b),
                 .web(bram2_we_b)
               );

  fft #(
        .N(N)
      )fft(
        .clk(clk),
        .rst(rst),
        .mode(mode),
        .start(start),

        .bram1_addr_a(bram1_addr_a),
        .bram1_din_a(bram1_din_a),
        .bram1_dout_a(bram1_dout_a),
        .bram1_we_a(bram1_we_a),
        .bram1_addr_b(bram1_addr_b),
        .bram1_din_b(bram1_din_b),
        .bram1_dout_b(bram1_dout_b),
        .bram1_we_b(bram1_we_b),

        .bram2_addr_a(bram2_addr_a),
        .bram2_din_a(bram2_din_a),
        .bram2_dout_a(bram2_dout_a),
        .bram2_we_a(bram2_we_a),
        .bram2_addr_b(bram2_addr_b),
        .bram2_din_b(bram2_din_b),
        .bram2_dout_b(bram2_dout_b),
        .bram2_we_b(bram2_we_b),

        .done(done)
      );

  always #5 clk = ~clk;

  initial begin
    clk = 0;
    mode = 0;
    rst = 1;
    start = 0;
    #10;

    rst = 0;
    #30;

    start = 1;
    #10;
    start = 0;

    // Wait for done signal
    while(!done)
      #10;

  end

endmodule
