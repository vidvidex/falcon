`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

module fft_butterfly_tb;

  logic clk;
  logic in_valid, out_valid, mode;
  logic [63:0] a_in_real;
  logic [63:0] a_in_imag;
  logic [63:0] b_in_real;
  logic [63:0] b_in_imag;

  logic [9:0] tw_addr;

  logic [63:0] a_out_real;
  logic [63:0] a_out_imag;
  logic [63:0] b_out_real;
  logic [63:0] b_out_imag;

  logic signed [4:0] scale_factor;

  always #5 clk = ~clk;

  fft_butterfly fft_butterfly(
                 .clk(clk),
                 .in_valid(in_valid),
                 .mode(mode),

                 .a_in_real(a_in_real),
                 .a_in_imag(a_in_imag),
                 .b_in_real(b_in_real),
                 .b_in_imag(b_in_imag),

                 .tw_addr(tw_addr),

                 .scale_factor(scale_factor),

                 .a_out_real(a_out_real),
                 .a_out_imag(a_out_imag),
                 .b_out_real(b_out_real),
                 .b_out_imag(b_out_imag),
                 .out_valid(out_valid)
               );

  initial begin

    clk = 1;
    in_valid = 0;
    mode = 0;
    a_in_real = 0;
    a_in_imag = 0;
    b_in_real = 0;
    b_in_imag = 0;
    scale_factor = 0;
    #10;

    in_valid = 1;
    scale_factor = 0;
    mode = 0; // FFT
    a_in_real = $realtobits(1.0);
    a_in_imag = $realtobits(2.0);
    b_in_real = $realtobits(3.0);
    b_in_imag = $realtobits(4.0);
    tw_addr = 2;  // Output: 0.29289+6.94974i, 1.70710-2.9497i
    #10;

    in_valid = 1;
    scale_factor = 0;
    mode = 0; // FFT
    a_in_real = $realtobits(12.5);
    a_in_imag = $realtobits(2.7);
    b_in_real = $realtobits(1.5);
    b_in_imag = $realtobits(-4.2);
    tw_addr = 4;  // Output: 15.49308-0.60626i, 9.50691+6.00626i
    #10;

    in_valid = 1;
    scale_factor = 0;
    mode = 0; // FFT
    a_in_real = $realtobits(3.0);
    a_in_imag = $realtobits(2.0);
    b_in_real = $realtobits(1.0);
    b_in_imag = $realtobits(0.0);
    tw_addr = 2;  // Output: 3.70710+2.70710i, 2.29289+1.29289i
    #10;

    in_valid = 0;


    // Wait for out_valid from FFT before starting IFFT
    while(out_valid !== 1'b1)
      #10;
    #50;  // Wait for FFT results to be outputted (fft_butterfly does not like changing the mode during processing)

    in_valid = 1;
    scale_factor = -1;
    mode = 1; // IFFT
    a_in_real = $realtobits(1.0);
    a_in_imag = $realtobits(2.0);
    b_in_real = $realtobits(3.0);
    b_in_imag = $realtobits(4.0);
    tw_addr = 2;  // Output: 2 + 3i, -1.41421i + 0
    #10;

    in_valid = 1;
    scale_factor = -1;
    mode = 1; // IFFT
    a_in_real = $realtobits(12.5);
    a_in_imag = $realtobits(2.7);
    b_in_real = $realtobits(1.5);
    b_in_imag = $realtobits(-4.2);
    tw_addr = 4;  // Output: 7 - 0.75i, 6.401595 + 1.08262i
    #10;

    in_valid = 1;
    scale_factor = -1;
    mode = 1; // IFFT
    a_in_real = $realtobits(3.0);
    a_in_imag = $realtobits(2.0);
    b_in_real = $realtobits(1.0);
    b_in_imag = $realtobits(0.0);
    tw_addr = 2;  // Output: 2 + 1i, 1.41421i - 0 
    #10;

    in_valid = 0;


  end

endmodule
