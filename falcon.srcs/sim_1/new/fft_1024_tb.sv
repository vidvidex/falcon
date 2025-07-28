`timescale 1ns / 1ps

module fft_1024_tb;

  parameter int N = 1024;

  logic clk,rst;
  logic mode;
  logic start;
  logic done;

  logic [$clog2(N)-2:0] bram1_addr_a, bram1_addr_b;
  logic [127:0] bram1_din_a, bram1_din_b;
  logic [127:0] bram1_dout_a, bram1_dout_b;
  logic bram1_we_a, bram1_we_b;
  bram_512x128_preinit_for_fft_tb bram_512x128_preinit_for_fft_tb_1 (
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
  bram_512x128_preinit_for_fft_tb bram_512x128_preinit_for_fft_tb_2 (
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

                 .valid_out(btf_valid_out)
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

    // Check if first and last values are as expected (for N=1024 the results will be in BRAM2)
    bram2_addr_a = 0;
    bram2_addr_b = 511;
    #20;

    a_real_double = $bitstoreal(bram2_out_a_real);
    if(!double_equal(a_real_double, -211974.089585))
      $fatal(1, "FFT 1024: Expected first real part to be -211974.089585, got %f", a_real_double);

    a_imag_double = $bitstoreal(bram2_out_a_imag);
    if(!double_equal(a_imag_double, 333771.845416))
      $fatal(1, "FFT 1024: Expected first imag part to be 333771.845416, got %f", a_imag_double);

    b_real_double = $bitstoreal(bram2_out_b_real);
    if(!double_equal(b_real_double, 0.000014))
      $fatal(1, "FFT 1024: Expected last real part to be 0.000014, got %f", b_real_double);

    b_imag_double = $bitstoreal(bram2_out_b_imag);
    if(!double_equal(b_imag_double, -0.000004))
      $fatal(1, "FFT 1024: Expected last imag part to be -0.000004, got %f", b_imag_double);

    $display("All tests for fft_1024 passed!");
    $finish;

  end

endmodule
