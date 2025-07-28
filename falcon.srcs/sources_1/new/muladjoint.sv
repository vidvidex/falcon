`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Multiply complex number a with adjoint of complex number b.
// Both complex numbers are supplied as a 128 bit vector. Top 64 bits are real part, bottom 64 bits are imag part
//
// Example calculation: a = 1+2i, b = 2+3i
//      result = (1+2i)*conjugate(2+3i) = (1+2i)*(2-3i) = 8 + i
//////////////////////////////////////////////////////////////////////////////////


module muladjoint(
    input clk,

    input logic [`FFT_BRAM_DATA_WIDTH-1:0] a_in,
    input logic [`FFT_BRAM_DATA_WIDTH-1:0] b_in,
    input logic valid_in,
    input logic [`FFT_BRAM_ADDR_WIDTH-1:0] address_in,

    output logic [`FFT_BRAM_DATA_WIDTH-1:0] data_out,
    output logic valid_out,
    output logic [`FFT_BRAM_ADDR_WIDTH-1:0] address_out
  );

  logic [63:0] a_real, a_imag;
  logic [63:0] b_real, b_imag_conj;
  logic [63:0] prod_real, prod_imag;

  assign a_real = a_in[127:64];
  assign a_imag = a_in[63:0];
  assign b_real = b_in[127:64];
  assign b_imag_conj = {~b_in[63], b_in[62:0]};


  complex_multiplier complex_multiplier(
                       .clk(clk),
                       .valid_in(valid_in),
                       .a_real(a_real),
                       .a_imag(a_imag),
                       .b_real(b_real),
                       .b_imag(b_imag_conj),
                       .scale_factor(5'b0),

                       .a_x_b_real(prod_real),
                       .a_x_b_imag(prod_imag),

                       .valid_out(valid_out)
                     );

  assign data_out = {prod_real, prod_imag};

  delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(14)) address_delay(.clk(clk), .in(address_in), .out(address_out));

endmodule
