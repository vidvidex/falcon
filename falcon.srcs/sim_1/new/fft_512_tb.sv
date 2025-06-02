`timescale 1ns / 1ps

module fft_512_tb;

  parameter int N = 512;

  logic clk,rst;
  logic mode;
  logic start;
  logic done;

  logic [$clog2(N)-2:0] bram1_addr_a, bram1_addr_b;
  logic [127:0] bram1_din_a, bram1_din_b;
  logic [127:0] bram1_dout_a, bram1_dout_b;
  logic bram1_we_a, bram1_we_b;
  fft_bram_512_preinit_for_tb fft_bram_512_preinit_for_tb_1 (
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

  logic [$clog2(N)-2:0] bram2_addr_a, bram2_addr_b;
  logic [127:0] bram2_din_a, bram2_din_b;
  logic [127:0] bram2_dout_a, bram2_dout_b;
  logic bram2_we_a, bram2_we_b;
  fft_bram_512_preinit_for_tb fft_bram_512_preinit_for_tb_2 (
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

  // Signals that split 128 bit BRAM line into real and imag part, used mostly for debugging
  logic [63:0] bram1_out_a_real, bram1_out_a_imag;
  logic [63:0] bram1_out_b_real, bram1_out_b_imag;
  logic [63:0] bram2_out_a_real, bram2_out_a_imag;
  logic [63:0] bram2_out_b_real, bram2_out_b_imag;
  assign {bram1_out_a_real, bram1_out_a_imag} = bram1_dout_a;
  assign {bram1_out_b_real, bram1_out_b_imag} = bram1_dout_b;
  assign {bram2_out_a_real, bram2_out_a_imag} = bram2_dout_a;
  assign {bram2_out_b_real, bram2_out_b_imag} = bram2_dout_b;
  logic [63:0] bram1_in_a_real, bram1_in_a_imag;
  logic [63:0] bram1_in_b_real, bram1_in_b_imag;
  logic [63:0] bram2_in_a_real, bram2_in_a_imag;
  logic [63:0] bram2_in_b_real, bram2_in_b_imag;
  assign {bram1_in_a_real, bram1_in_a_imag} = bram1_din_a;
  assign {bram1_in_b_real, bram1_in_b_imag} = bram1_din_b;
  assign {bram2_in_a_real, bram2_in_a_imag} = bram2_din_a;
  assign {bram2_in_b_real, bram2_in_b_imag} = bram2_din_b;

  // For result verification
  real a_real_double, a_imag_double, b_real_double, b_imag_double;

  function bit double_equal(real a, real b, real epsilon = 1e-6);
    real diff;
    diff = a - b;
    if (diff < 0.0)
      diff = -diff;
    return (diff < epsilon);
  endfunction

  always #5 clk = ~clk;

  initial begin
    clk = 0;
    mode = 0;
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

    // Check if first and last values are as expected (for N=512 the results will be in BRAM1)
    bram1_addr_a = 0;
    bram1_addr_b = 255;
    #20;

    a_real_double = $bitstoreal(bram1_out_a_real);
    if(!double_equal(a_real_double, -52865.647396))
      $fatal(1, "FFT 512: Expected first real part to be -52865.647396, got %f", a_real_double);

    a_imag_double = $bitstoreal(bram1_out_a_imag);
    if(!double_equal(a_imag_double, 83442.765004))
      $fatal(1, "FFT 512: Expected first imag part to be 83442.765004, got %f", a_imag_double);

    b_real_double = $bitstoreal(bram1_out_b_real);
    if(!double_equal(b_real_double, 0.000158))
      $fatal(1, "FFT 512: Expected last real part to be 0.000158, got %f", b_real_double);

    b_imag_double = $bitstoreal(bram1_out_b_imag);
    if(!double_equal(b_imag_double, 0.000694))
      $fatal(1, "FFT 512: Expected last imag part to be 0.000694, got %f", b_imag_double);

    $display("All tests for fft_512 passed!");
    $finish;

  end

endmodule
