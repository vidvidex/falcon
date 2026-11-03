`timescale 1ns / 1ps
`include "common_definitions.vh"

// Runs the IFFT on mem/tb/fft_1024.hex and compares the result with mem/tb/ifft_1024_tb_expected.hex,
// which scripts/fft_reference.py computes with Falcon's reference IFFT.
module ifft_1024_tb;

  parameter int N = 1024;

  logic clk,rst;
  logic mode;
  logic start;
  logic done;

  logic [`BRAM_ADDR_WIDTH-1:0] bram1_addr_a;
  logic [`BRAM_DATA_WIDTH-1:0] bram1_din_a, bram1_dout_a;
  logic bram1_we_a;
  logic [`BRAM_ADDR_WIDTH-1:0] bram1_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram1_din_b, bram1_dout_b;
  logic bram1_we_b;
  bram #(.DATA_WIDTH(`BRAM_DATA_WIDTH), .ADDR_WIDTH(`BRAM_ADDR_WIDTH), .INIT_FILE({`FALCON_MEM_DIR, "/tb/fft_1024.hex"})) bram_6144x128_preinit_for_fft_tb_1 (
                                .addra(bram1_addr_a),
                                .clk(clk),
                                .dina(bram1_din_a),
                                .douta(bram1_dout_a),
                                .wea(bram1_we_a),

                                .addrb(bram1_addr_b),
                                .dinb(bram1_din_b),
                                .doutb(bram1_dout_b),
                                .web(bram1_we_b)
                              );

  logic [`BRAM_ADDR_WIDTH-1:0] bram2_addr_a;
  logic [`BRAM_DATA_WIDTH-1:0] bram2_din_a, bram2_dout_a;
  logic bram2_we_a;
  logic [`BRAM_ADDR_WIDTH-1:0] bram2_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram2_din_b, bram2_dout_b;
  logic bram2_we_b;
  bram #(.DATA_WIDTH(`BRAM_DATA_WIDTH), .ADDR_WIDTH(`BRAM_ADDR_WIDTH), .INIT_FILE({`FALCON_MEM_DIR, "/tb/fft_1024.hex"})) bram_6144x128_preinit_for_fft_tb_2 (
                                .addra(bram2_addr_a),
                                .clk(clk),
                                .dina(bram2_din_a),
                                .douta(bram2_dout_a),
                                .wea(bram2_we_a),

                                .addrb(bram2_addr_b),
                                .dinb(bram2_din_b),
                                .doutb(bram2_dout_b),
                                .web(bram2_we_b)
                              );

  logic [63:0] btf_a_in_real, btf_a_in_imag, btf_b_in_real, btf_b_in_imag;
  logic [63:0] btf_a_out_real, btf_a_out_imag, btf_b_out_real, btf_b_out_imag;
  logic btf_mode;
  logic signed [4:0] btf_scale_factor;
  logic [9:0] btf_tw_addr;
  logic btf_valid_in, btf_valid_out;
  fft_butterfly fft_butterfly(
                 .clk(clk),
                 .mode(btf_mode),
                 .valid_in(btf_valid_in),

                 .a_in_real(btf_a_in_real),
                 .a_in_imag(btf_a_in_imag),
                 .b_in_real(btf_b_in_real),
                 .b_in_imag(btf_b_in_imag),

                 .tw_addr(btf_tw_addr),

                 .scale_factor(btf_scale_factor),

                 .a_out_real(btf_a_out_real),
                 .a_out_imag(btf_a_out_imag),
                 .b_out_real(btf_b_out_real),
                 .b_out_imag(btf_b_out_imag),

                 .valid_out(btf_valid_out),

                 .ext_mul(1'b0)
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

        .done(done),

        .btf_mode(btf_mode),
        .btf_valid_in(btf_valid_in),
        .btf_a_in_real(btf_a_in_real),
        .btf_a_in_imag(btf_a_in_imag),
        .btf_b_in_real(btf_b_in_real),
        .btf_b_in_imag(btf_b_in_imag),
        .btf_scale_factor(btf_scale_factor),
        .btf_tw_addr(btf_tw_addr),
        .btf_a_out_real(btf_a_out_real),
        .btf_a_out_imag(btf_a_out_imag),
        .btf_b_out_real(btf_b_out_real),
        .btf_b_out_imag(btf_b_out_imag),
        .btf_valid_out(btf_valid_out)
      );

  logic [`BRAM_DATA_WIDTH-1:0] expected_output [N/2];

  always #5 clk = ~clk;

  initial begin
    clk = 0;
    mode = 1;
    rst = 1;
    start = 0;
    #15;

    rst = 0;
    #30;

    start = 1;
    #10;
    start = 0;

    // Wait for done signal
    while(!done)
      #10;

    repeat (5) @(posedge clk);

    // The result is in BRAM2. It is read directly from the memory array because the FFT module drives the BRAM ports.
    $readmemh({`FALCON_MEM_DIR, "/tb/ifft_1024_tb_expected.hex"}, expected_output);
    for (int i = 0; i < N/2; i++)
      if (bram_6144x128_preinit_for_fft_tb_2.mem[i] !== expected_output[i])
        $fatal(1, "Output word %0d differs from ifft_1024_tb_expected.hex: expected %h, got %h", i, expected_output[i],
               bram_6144x128_preinit_for_fft_tb_2.mem[i]);

    $display("All tests for ifft_1024 passed!");
    $finish;
  end

endmodule
