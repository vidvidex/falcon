`timescale 1ns / 1ps
`include "CommonDefinitions.vh"
//////////////////////////////////////////////////////////////////////////////////
//
// FFT butterfly unit for both FFT and IFFT
//
// This module and it's submodules were originally developed for Aloha-HE
// (https://github.com/flokrieger/Aloha-HE; https://ieeexplore.ieee.org/document/10546608)
// and were adapted for Falcon. Most notable changes:
// - added support for fully pipelined operation
// - twiddle factor ROM is part of the fft_butterfly module
//
//////////////////////////////////////////////////////////////////////////////////

(* keep_hierarchy = `KEEP_HIERARCHY *)
module fft_butterfly(
    input clk,
    input in_valid, // Are inputs valid
    input mode, // 0  = FFT; 1 = IFFT
    input [63:0] a_in_real,
    input [63:0] a_in_imag,
    input [63:0] b_in_real,
    input [63:0] b_in_imag,

    input [9:0] tw_addr, // Address for the twiddle factor ROM

    input signed [4:0] scale_factor, // Scale (multiply) the result by 2^scale_factor. Used for scaling IFFT results. If 0 has no effect

    output [63:0] a_out_real,
    output [63:0] a_out_imag,
    output [63:0] b_out_real,
    output [63:0] b_out_imag,

    output out_valid
  );

  /////////////////////// Add stage //////////////////////
  logic [63:0] a_m_b_real_1DP, a_m_b_imag_1DP, mul_out_real_1DP, mul_out_imag_1DP;
  logic [63:0] a_m_b_real, a_m_b_imag;
  logic add_done;

  // For FFT we have to delay a_in_real and a_in_imag before it enters the add stage (pipelining doesn't work without it)
  logic [63:0] a_real, a_imag;
  logic [63:0] a_in_real_15D, a_in_imag_15D;
  delay_register #(.BITWIDTH(64), .CYCLE_COUNT(1+15)) a_in_real_delay(.clk(clk), .in(a_in_real), .out(a_in_real_15D));
  delay_register #(.BITWIDTH(64), .CYCLE_COUNT(1+15)) a_in_imag_delay(.clk(clk), .in(a_in_imag), .out(a_in_imag_15D));

  assign a_real = mode ?  a_in_real: a_in_real_15D;
  assign a_imag = mode ? a_in_imag : a_in_imag_15D;

  // For IFFT we have to delay a_p_b_real and a_p_b_imag before outputting the final result (pipelining doesn't work without it)
  logic [63:0] a_p_b_real, a_p_b_imag;
  logic [63:0] a_p_b_real_15D, a_p_b_imag_15D;
  delay_register #(.BITWIDTH(64), .CYCLE_COUNT(1+15)) a_p_b_real_delay(.clk(clk), .in(a_p_b_real), .out(a_p_b_real_15D));
  delay_register #(.BITWIDTH(64), .CYCLE_COUNT(1+15)) a_p_b_imag_delay(.clk(clk), .in(a_p_b_imag), .out(a_p_b_imag_15D));

  assign a_out_real = mode ? a_p_b_real_15D : a_p_b_real;
  assign a_out_imag = mode ? a_p_b_imag_15D : a_p_b_imag;

  logic [63:0] b_real, b_imag;
  assign b_real = mode ? b_in_real : mul_out_real_1DP;
  assign b_imag = mode ?  b_in_imag : mul_out_imag_1DP;

  fft_butterfly_add_stage add_stage(
                         .clk(clk),
                         .in_valid(in_valid),

                         .a_real(a_real),
                         .a_imag(a_imag),
                         .b_real(b_real),
                         .b_imag(b_imag),
                         .scale_factor(scale_factor),

                         .a_p_b_real(a_p_b_real),
                         .a_p_b_imag(a_p_b_imag),
                         .a_m_b_real(a_m_b_real),
                         .a_m_b_imag(a_m_b_imag),

                         .out_valid(add_done)
                       );

  // For IFFT we need to delay the twiddle factor address
  logic [9:0] tw_addr_delayed;
  delay_register #(.BITWIDTH(10), .CYCLE_COUNT(7)) tw_addr_delay(.clk(clk), .in(tw_addr), .out(tw_addr_delayed));

  logic [63:0] tw_real, tw_imag;
  fft_twiddle_factor_rom fft_twiddle_factor_rom (
                           .clk(clk),
                           .mode(mode),
                           .tw_addr(mode == 1'b0 ? tw_addr : tw_addr_delayed),
                           .tw_real(tw_real),
                           .tw_imag(tw_imag)
                         );

  ///////////////////// Mult stage ///////////////////////////
  logic [63:0] mul_out_real, mul_out_imag;
  logic add_done_1DP, add_done_2DP;
  always_ff @(posedge clk) begin
    a_m_b_real_1DP <= mode ? a_m_b_real : b_in_real;
    a_m_b_imag_1DP <= mode ? a_m_b_imag : b_in_imag;
    mul_out_real_1DP <= mul_out_real;
    mul_out_imag_1DP <= mul_out_imag;
    add_done_1DP <= add_done;
    add_done_2DP <= add_done_1DP;
  end

  ComplexMultiplier tw_factor_mult(
                      .clk(clk),
                      .in_valid(add_done_2DP),
                      .a_real(a_m_b_real_1DP),
                      .a_imag(a_m_b_imag_1DP),
                      .b_real(tw_real),
                      .b_imag(tw_imag),
                      .scale_factor(scale_factor),

                      .a_x_b_real(mul_out_real),
                      .a_x_b_imag(mul_out_imag),

                      .out_valid(out_valid)
                    );

  logic [63:0] b_out_real_0DP, b_out_imag_0DP;
  assign b_out_real_0DP = mode ? mul_out_real : a_m_b_real;
  assign b_out_imag_0DP = mode ? mul_out_imag : a_m_b_imag;

  logic [63:0] b_out_real_1DP, b_out_imag_1DP;
  delay_register #(.BITWIDTH(64), .CYCLE_COUNT(1+0)) b_out_real_delay(.clk(clk), .in(b_out_real_0DP), .out(b_out_real_1DP));
  delay_register #(.BITWIDTH(64), .CYCLE_COUNT(1+0)) b_out_imag_delay(.clk(clk), .in(b_out_imag_0DP), .out(b_out_imag_1DP));
  assign b_out_real = mode ? b_out_real_1DP : b_out_real_0DP;
  assign b_out_imag = mode ? b_out_imag_1DP : b_out_imag_0DP;

endmodule
