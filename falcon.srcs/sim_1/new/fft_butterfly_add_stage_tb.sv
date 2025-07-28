`timescale 1ns / 1ps
`include "common_definitions.vh"

module fft_butterfly_add_stage_tb;

  logic clk;
  logic valid_in, valid_out;
  logic [63:0] a_real;
  logic [63:0] a_imag;
  logic [63:0] b_real;
  logic [63:0] b_imag;

  logic [63:0] a_p_b_real;
  logic [63:0] a_p_b_imag;
  logic [63:0] a_m_b_real;
  logic [63:0] a_m_b_imag;


  always #5 clk = ~clk;

  fft_butterfly_add_stage fft_butterfly_add_stage(
                 .clk(clk),
                 .valid_in(valid_in),

                 .a_real(a_real),
                 .a_imag(a_imag),
                 .b_real(b_real),
                 .b_imag(b_imag),

                 .a_p_b_real(a_p_b_real),
                 .a_p_b_imag(a_p_b_imag),
                 .a_m_b_real(a_m_b_real),
                 .a_m_b_imag(a_m_b_imag),

                 .valid_out(valid_out)
               );

  initial begin

    clk = 1;

    valid_in = 0;
    a_real = 0;
    a_imag = 0;
    b_real = 0;
    b_imag = 0;
    #10;

    valid_in = 1;
    a_real = $realtobits(1.0);
    a_imag = $realtobits(1.0);
    b_real = $realtobits(2.0);
    b_imag = $realtobits(2.0);
    #10;    

    valid_in = 1;
    a_real = $realtobits(5.0);
    a_imag = $realtobits(6.0);
    b_real = $realtobits(7.0);
    b_imag = $realtobits(8.0);
    #10;    

    valid_in = 0;

  end

endmodule
