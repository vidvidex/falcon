`timescale 1ns / 1ps

module merge_fft_tb;

  parameter int N = 1024;

  logic clk, rst;
  logic mode;
  logic start;
  logic done;
  logic [$clog2(N):0] size;

  logic [$clog2(N)-2:0] bram1_addr_a, bram1_addr_b;
  logic [127:0] bram1_din_a, bram1_din_b;
  logic [127:0] bram1_dout_a, bram1_dout_b;
  logic bram1_we_a, bram1_we_b;
  fft_bram_1024 fft_bram_1024_1 (
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
  fft_bram_1024 fft_bram_1024_2 (
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
  logic btf_in_valid, btf_out_valid;
  FFTButterfly FFTButterfly(
                 .clk(clk),
                 .mode(btf_mode),
                 .in_valid(btf_in_valid),

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

                 .done(btf_out_valid)
               );

  merge_fft #(
              .N(N)
            )merge_fft(
              .clk(clk),
              .rst(rst),
              .size(size),
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
              .btf_in_valid(btf_in_valid),
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
              .btf_out_valid(btf_out_valid)
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

    ////// Start BRAM 1 initialization for size 16 //////
    size = 16;
    bram1_we_a <= 1;
    bram1_we_b <= 1;
    for(int i = 0; i < (size>>2); i++) begin
      real i_real = real'(i);
      bram1_addr_a <= i;
      bram1_din_a <= {$realtobits(i_real), $realtobits(i_real+(size>>2))};

      bram1_addr_b <= i + (size>>2);
      bram1_din_b <= {$realtobits(i_real+size/2), $realtobits(i_real + (size>>2) + (size>>1))};
      #10;
    end
    bram1_we_a <= 0;
    bram1_we_b <= 0;
    ////// Finish BRAM 1 initialization //////

    ////// Test for size 16 (8 real, 8 imaginary numbers) //////
    start = 1;
    #10;
    start = 0;


    // Wait for done signal
    while(!done)
      #10;

    // Check if first and last value of f are correct
    bram2_addr_a = 0;
    bram2_addr_b = size/2-1;
    #30;
    a_real_double = $bitstoreal(bram2_out_a_real);
    if(!double_equal(a_real_double, 5.505198))
      $fatal(1, "merge_fft size 16: Expected first real part to be 5.505198, got %f", a_real_double);

    a_imag_double = $bitstoreal(bram2_out_a_imag);
    if(!double_equal(a_imag_double, 17.330145))
      $fatal(1, "merge_fft size 16: Expected first imag part to be 17.330145, got %f", a_imag_double);

    b_real_double = $bitstoreal(bram2_out_b_real);
    if(!double_equal(b_real_double, 2.187387))
      $fatal(1, "merge_fft size 16: Expected last real part to be 2.187387, got %f", b_real_double);

    b_imag_double = $bitstoreal(bram2_out_b_imag);
    if(!double_equal(b_imag_double, -11.583316))
      $fatal(1, "merge_fft size 16: Expected last imag part to be -11.583316, got %f", b_imag_double);

    $display("All tests for merge_fft with size 16 passed!");
    ////// Finish test for size = 16 //////

    rst = 1;
    #10;
    rst = 0;

    ////// Start BRAM 1 initialization for size 1024 //////
    size = 1024;

    bram1_we_a <= 1;
    bram1_we_b <= 1;
    for(int i = 0; i < (size>>2); i++) begin
      real i_real = real'(i);
      bram1_addr_a <= i;
      bram1_din_a <= {$realtobits(i_real), $realtobits(i_real+(size>>2))};

      bram1_addr_b <= i + (size>>2);
      bram1_din_b <= {$realtobits(i_real+size/2), $realtobits(i_real + (size>>2) + (size>>1))};
      #10;
    end
    bram1_we_a <= 0;
    bram1_we_b <= 0;
    ////// Finish BRAM 1 initialization //////

    ////// Test for size 1024 (512 real, 512 imaginary numbers) //////
    size = 1024;
    start = 1;
    #10;
    start = 0;


    // Wait for done signal
    while(!done)
      #10;

    // Check if first and last value of f are correct
    bram2_addr_a = 0;
    bram2_addr_b = size/2-1;
    #30;
    a_real_double = $bitstoreal(bram2_out_a_real);
    if(!double_equal(a_real_double, 509.641399))
      $fatal(1, "merge_fft size 1024: Expected first real part to be 509.641399, got %f", a_real_double);

    a_imag_double = $bitstoreal(bram2_out_a_imag);
    if(!double_equal(a_imag_double, 1025.567179))
      $fatal(1, "merge_fft size 1024: Expected first imag part to be 1025.567179, got %f", a_imag_double);

    b_real_double = $bitstoreal(bram2_out_b_real);
    if(!double_equal(b_real_double, -502.552072))
      $fatal(1, "merge_fft size 1024: Expected last real part to be -502.552072, got %f", b_real_double);

    b_imag_double = $bitstoreal(bram2_out_b_imag);
    if(!double_equal(b_imag_double, -519.015950))
      $fatal(1, "merge_fft size 1024: Expected last imag part to be -519.015950, got %f", b_imag_double);

    $display("All tests for merge_fft with size 1024 passed!");
    $finish;

  end

endmodule
