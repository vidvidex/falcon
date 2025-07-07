`timescale 1ns / 1ps
`include "common_definitions.vh"

// Changes: removed interfaces for shared external multiplier

// performs a complex multiplication
// i.e.: (a_real + j*a_imag) * (b_real + j*b_imag) =
//       = (a_real*b_real - a_imag*b_imag) + j(a_imag*b_real + a_real*b_imag)
// input: unbuffered
// output: buffered
(* keep_hierarchy = `KEEP_HIERARCHY *)
module complex_multiplier(
    input clk,
    input in_valid,
    input [63:0] a_real,
    input [63:0] a_imag,
    input [63:0] b_real,
    input [63:0] b_imag,
    input signed [4:0] scale_factor, // Scale (multiply) the result by 2^scale_factor. Used for scaling IFFT results. If 0 has no effect

    output [63:0] a_x_b_real,
    output [63:0] a_x_b_imag,

    output out_valid
  );

  logic mult_done;
  logic [63:0] ar_x_br, ar_x_bi, ai_x_br, ai_x_bi;

  flp_multiplier mult_ar_x_br(
                  .clk(clk),
                  .in_valid(in_valid),
                  .a(a_real),
                  .b(b_real),
                  .scale_factor(scale_factor),
                  .result(ar_x_br),
                  .out_valid(mult_done)
                );
  flp_multiplier mult_ar_x_bi(
                  .clk(clk),
                  .a(a_real),
                  .b(b_imag),
                  .scale_factor(scale_factor),
                  .result(ar_x_bi),
                  .in_valid(),
                  .out_valid()
                );
  flp_multiplier mult_ai_x_br(
                  .clk(clk),
                  .a(a_imag),
                  .b(b_real),
                  .scale_factor(scale_factor),
                  .result(ai_x_br),
                  .in_valid(),
                  .out_valid()
                );
  flp_multiplier mult_ai_x_bi(
                  .clk(clk),
                  .a(a_imag),
                  .b(b_imag),
                  .scale_factor(scale_factor),
                  .result(ai_x_bi),
                  .in_valid(),
                  .out_valid()
                );

  flp_adder #(.DO_SUBSTRACTION(1)) adder_real_result(
             .clk(clk),
             .in_valid(mult_done),
             .a(ar_x_br),
             .b(ai_x_bi),
             .result(a_x_b_real),
             .out_valid(out_valid)
           );

  flp_adder #(.DO_SUBSTRACTION(0)) adder_imag_result(
             .clk(clk),
             .a(ar_x_bi),
             .b(ai_x_br),
             .result(a_x_b_imag),
             .in_valid(),
             .out_valid()
           );

endmodule
