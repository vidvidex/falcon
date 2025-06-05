`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

module FFTButterflyAddStage_tb;

  logic clk;
  logic in_valid, out_valid;
  logic [63:0] a_real;
  logic [63:0] a_imag;
  logic [63:0] b_real;
  logic [63:0] b_imag;

  logic [63:0] a_p_b_real;
  logic [63:0] a_p_b_imag;
  logic [63:0] a_m_b_real;
  logic [63:0] a_m_b_imag;


  always #5 clk = ~clk;

  FFTButterflyAddStage FFTButterflyAddStage(
                 .clk(clk),
                 .in_valid(in_valid),

                 .a_real(a_real),
                 .a_imag(a_imag),
                 .b_real(b_real),
                 .b_imag(b_imag),

                 .a_p_b_real(a_p_b_real),
                 .a_p_b_imag(a_p_b_imag),
                 .a_m_b_real(a_m_b_real),
                 .a_m_b_imag(a_m_b_imag),

                 .out_valid(out_valid)
               );

  initial begin

    clk = 1;

    in_valid = 0;
    a_real = 0;
    a_imag = 0;
    b_real = 0;
    b_imag = 0;
    #10;

    in_valid = 1;
    a_real = $realtobits(1.0);
    a_imag = $realtobits(1.0);
    b_real = $realtobits(2.0);
    b_imag = $realtobits(2.0);
    #10;    

    in_valid = 1;
    a_real = $realtobits(5.0);
    a_imag = $realtobits(6.0);
    b_real = $realtobits(7.0);
    b_imag = $realtobits(8.0);
    #10;    

    in_valid = 0;

  end

endmodule
