`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

module FFTButterfly_tb;

  logic clk;
  logic start, done, use_ct;
  logic [`OVERALL_BITS-1:0] a_in_real;
  logic [`OVERALL_BITS-1:0] a_in_imag;
  logic [`OVERALL_BITS-1:0] b_in_real;
  logic [`OVERALL_BITS-1:0] b_in_imag;

  logic [`OVERALL_BITS-1:0] tw_real;
  logic [`OVERALL_BITS-1:0] tw_imag;

  logic [`OVERALL_BITS-1:0] a_out_real;
  logic [`OVERALL_BITS-1:0] a_out_imag;
  logic [`OVERALL_BITS-1:0] b_out_real;
  logic [`OVERALL_BITS-1:0] b_out_imag;

  logic signed [4:0] scale_factor;

  always #5 clk = ~clk;

  FFTButterfly FFTButterfly(
                 .clk(clk),
                 .start(start),
                 .use_ct(use_ct),

                 .a_in_real(a_in_real),
                 .a_in_imag(a_in_imag),
                 .b_in_real(b_in_real),
                 .b_in_imag(b_in_imag),

                 .tw_real(tw_real),
                 .tw_imag(tw_imag),
                 .scale_factor(scale_factor),

                 .a_out_real(a_out_real),
                 .a_out_imag(a_out_imag),
                 .b_out_real(b_out_real),
                 .b_out_imag(b_out_imag),
                 .done(done)
               );

  initial begin

    clk = 1;
    start = 0;
    use_ct = 0;
    a_in_real = 0;
    a_in_imag = 0;
    b_in_real = 0;
    b_in_imag = 0;
    tw_real = 0;
    tw_imag = 0;
    scale_factor = 0;
    #10;

    start = 1;
    scale_factor = 0;
    use_ct = 1; // FFT
    a_in_real = $realtobits(1.0);
    a_in_imag = $realtobits(1.0);
    b_in_real = $realtobits(2.0);
    b_in_imag = $realtobits(2.0);
    tw_real = $realtobits(1.0);
    tw_imag = $realtobits(0.0);
    #10;    // output: 3+3i, -1-1i

    start = 1;
    scale_factor = 0;
    use_ct = 1; // FFT
    a_in_real = $realtobits(12.5);
    a_in_imag = $realtobits(2.7);
    b_in_real = $realtobits(1.5);
    b_in_imag = $realtobits(-4.2);
    tw_real = $realtobits(1.0);
    tw_imag = $realtobits(0.0);
    #10;    // output: 14.0-1.5i, 11.0+6.9i

    start = 1;
    scale_factor = 0;
    use_ct = 1; // FFT
    a_in_real = $realtobits(2.0);
    a_in_imag = $realtobits(2.0);
    b_in_real = $realtobits(4.0);
    b_in_imag = $realtobits(4.0);
    tw_real = $realtobits(1.0);
    tw_imag = $realtobits(0.0);
    #10;    // output: 6+6i, -2-2i

    // start = 1;
    // scale_factor = -1;
    // use_ct = 0; // IFFT
    // a_in_real = $realtobits(1.0);
    // a_in_imag = $realtobits(1.0);
    // b_in_real = $realtobits(2.0);
    // b_in_imag = $realtobits(2.0);
    // tw_real = $realtobits(1.0);
    // tw_imag = $realtobits(0.0);
    // #10;    // output: 1.5+1.5i, -0.5-0.5i

    // start = 1;
    // scale_factor = -1;
    // use_ct = 0; // IFFT
    // a_in_real = $realtobits(1.0);
    // a_in_imag = $realtobits(2.3);
    // b_in_real = $realtobits(4.5);
    // b_in_imag = $realtobits(5.0);
    // tw_real = $realtobits(1.0);
    // tw_imag = $realtobits(0.0);
    // #10;    // output: 2.75+3.65i, -1.75-1.35i

    // start = 1;
    // scale_factor = -1;
    // use_ct = 0; // IFFT
    // a_in_real = $realtobits(5.0);
    // a_in_imag = $realtobits(5.0);
    // b_in_real = $realtobits(4.0);
    // b_in_imag = $realtobits(4.0);
    // tw_real = $realtobits(1.0);
    // tw_imag = $realtobits(0.0);
    // #10;    // output: 4.5+4.5i, 0.5+0.5i

    start = 0;


  end

endmodule
