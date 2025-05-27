`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

//  a_in_real + j*a_in_imag ----\-/|+|-- a_out_real + j*a_out_imag
//                               X
//  b_in_real + j*b_in_imag ----/-\|-|--|x|- b_out_real + j*b_out_imag
// load and store logic needs to make sure to deliver inputs / twiddle factors and consume results in right point in time
// input: unbuffered
// output: buffered
(* keep_hierarchy = `KEEP_HIERARCHY *)
module FFTButterfly(
    input clk,
    input start,
    input use_ct, // 0 = DIT = IFFT; 1 = DIF = FFT
    input [`OVERALL_BITS-1:0] a_in_real,
    input [`OVERALL_BITS-1:0] a_in_imag,
    input [`OVERALL_BITS-1:0] b_in_real,
    input [`OVERALL_BITS-1:0] b_in_imag,

    input [`OVERALL_BITS-1:0] tw_real,  // Should be supplied 1 cycle later than a_in_real, a_in_imag, b_in_real, b_in_imag for FFT and 8 cycles later for IFFT.
    input [`OVERALL_BITS-1:0] tw_imag,  // TODO: these two should probably not be external signals, ROM for constants should be managed by this module so we don't have this "strange" delayed signals going out

    input signed [4:0] scale_factor, // Scale (multiply) the result by 2^scale_factor. Used for scaling IFFT results. If 0 has no effect

    output [`OVERALL_BITS-1:0] a_out_real,
    output [`OVERALL_BITS-1:0] a_out_imag,
    output [`OVERALL_BITS-1:0] b_out_real,
    output [`OVERALL_BITS-1:0] b_out_imag,

    output done
  );

  /////////////////////// Add stage //////////////////////
  logic [`OVERALL_BITS-1:0] a_m_b_real_1DP, a_m_b_imag_1DP, mul_out_real_1DP, mul_out_imag_1DP;
  logic [`OVERALL_BITS-1:0] a_m_b_real, a_m_b_imag;
  logic add_done;

  // For FFT we have to delay a_in_real and a_in_imag before it enters the add stage (pipelining doesn't work without it)
  logic [`OVERALL_BITS-1:0] a_real, a_imag;
  logic [`OVERALL_BITS-1:0] a_in_real_15D, a_in_imag_15D;
  DelayRegister #(.BITWIDTH(`OVERALL_BITS), .CYCLE_COUNT(1+15)) a_in_real_delay(.clk(clk), .in(a_in_real), .out(a_in_real_15D));
  DelayRegister #(.BITWIDTH(`OVERALL_BITS), .CYCLE_COUNT(1+15)) a_in_imag_delay(.clk(clk), .in(a_in_imag), .out(a_in_imag_15D));

  assign a_real = use_ct ? a_in_real_15D : a_in_real;
  assign a_imag = use_ct ? a_in_imag_15D : a_in_imag;

  // For IFFT we have to delay a_p_b_real and a_p_b_imag before outputting the final result (pipelining doesn't work without it)
  logic [`OVERALL_BITS-1:0] a_p_b_real, a_p_b_imag;
  logic [`OVERALL_BITS-1:0] a_p_b_real_15D, a_p_b_imag_15D;
  DelayRegister #(.BITWIDTH(`OVERALL_BITS), .CYCLE_COUNT(1+15)) a_p_b_real_delay(.clk(clk), .in(a_p_b_real), .out(a_p_b_real_15D));
  DelayRegister #(.BITWIDTH(`OVERALL_BITS), .CYCLE_COUNT(1+15)) a_p_b_imag_delay(.clk(clk), .in(a_p_b_imag), .out(a_p_b_imag_15D));

  assign a_out_real = use_ct ? a_p_b_real : a_p_b_real_15D;
  assign a_out_imag = use_ct ? a_p_b_imag : a_p_b_imag_15D;

  logic [`OVERALL_BITS-1:0] b_real, b_imag;
  assign b_real = use_ct ? mul_out_real_1DP : b_in_real;
  assign b_imag = use_ct ? mul_out_imag_1DP : b_in_imag;

  FFTButterflyAddStage add_stage(
                         .clk(clk),
                         .start(start),

                         .a_real(a_real),
                         .a_imag(a_imag),
                         .b_real(b_real),
                         .b_imag(b_imag),
                         .scale_factor(scale_factor),

                         .a_p_b_real(a_p_b_real),
                         .a_p_b_imag(a_p_b_imag),
                         .a_m_b_real(a_m_b_real),
                         .a_m_b_imag(a_m_b_imag),

                         .done(add_done)
                       );

  ///////////////////// Mult stage ///////////////////////////
  logic [`OVERALL_BITS-1:0] mul_out_real, mul_out_imag;
  logic add_done_1DP, add_done_2DP;
  always_ff @(posedge clk) begin
    a_m_b_real_1DP <= use_ct ? b_in_real : a_m_b_real;
    a_m_b_imag_1DP <= use_ct ? b_in_imag : a_m_b_imag;
    mul_out_real_1DP <= mul_out_real;
    mul_out_imag_1DP <= mul_out_imag;
    add_done_1DP <= add_done;
    add_done_2DP <= add_done_1DP;
  end

  ComplexMultiplier tw_factor_mult(
                      .clk(clk),
                      .start(add_done_2DP),
                      .a_real(a_m_b_real_1DP),
                      .a_imag(a_m_b_imag_1DP),
                      .b_real(tw_real),
                      .b_imag(tw_imag),
                      .scale_factor(scale_factor),

                      .a_x_b_real(mul_out_real),
                      .a_x_b_imag(mul_out_imag),

                      .done(done)
                    );

  logic [`OVERALL_BITS-1:0] b_out_real_0DP, b_out_imag_0DP;
  assign b_out_real_0DP = use_ct ? a_m_b_real : mul_out_real;
  assign b_out_imag_0DP = use_ct ? a_m_b_imag : mul_out_imag;

  logic [`OVERALL_BITS-1:0] b_out_real_1DP, b_out_imag_1DP;
  DelayRegister #(.BITWIDTH(`OVERALL_BITS), .CYCLE_COUNT(1+0)) b_out_real_delay(.clk(clk), .in(b_out_real_0DP), .out(b_out_real_1DP));
  DelayRegister #(.BITWIDTH(`OVERALL_BITS), .CYCLE_COUNT(1+0)) b_out_imag_delay(.clk(clk), .in(b_out_imag_0DP), .out(b_out_imag_1DP));
  assign b_out_real = use_ct ? b_out_real_0DP : b_out_real_1DP;
  assign b_out_imag = use_ct ? b_out_imag_0DP : b_out_imag_1DP;

endmodule
