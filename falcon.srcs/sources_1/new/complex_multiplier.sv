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
    input valid_in,
    input [63:0] a_real,
    input [63:0] a_imag,
    input [63:0] b_real,
    input [63:0] b_imag,
    input signed [4:0] scale_factor, // Scale (multiply) the result by 2^scale_factor. Used for scaling IFFT results. If 0 has no effect

    output [63:0] a_x_b_real,
    output [63:0] a_x_b_imag,

    output valid_out
  );

  logic mult_done;
  logic [63:0] ar_x_br, ar_x_bi, ai_x_br, ai_x_bi;

  fp_multiplier mult_ar_x_br(
                  .clk(clk),
                  .valid_in(valid_in),
                  .a(a_real),
                  .b(b_real),
                  .scale_factor(scale_factor),
                  .result(ar_x_br),
                  .valid_out(mult_done)
                );
  fp_multiplier mult_ar_x_bi(
                  .clk(clk),
                  .a(a_real),
                  .b(b_imag),
                  .scale_factor(scale_factor),
                  .result(ar_x_bi),
                  .valid_in(),
                  .valid_out()
                );
  fp_multiplier mult_ai_x_br(
                  .clk(clk),
                  .a(a_imag),
                  .b(b_real),
                  .scale_factor(scale_factor),
                  .result(ai_x_br),
                  .valid_in(),
                  .valid_out()
                );
  fp_multiplier mult_ai_x_bi(
                  .clk(clk),
                  .a(a_imag),
                  .b(b_imag),
                  .scale_factor(scale_factor),
                  .result(ai_x_bi),
                  .valid_in(),
                  .valid_out()
                );

  fp_adder #(.DO_SUBSTRACTION(1)) adder_real_result(
             .clk(clk),
             .valid_in(mult_done),
             .a(ar_x_br),
             .b(ai_x_bi),
             .result(a_x_b_real),
             .valid_out(valid_out)
           );

  fp_adder #(.DO_SUBSTRACTION(0)) adder_imag_result(
             .clk(clk),
             .a(ar_x_bi),
             .b(ai_x_br),
             .result(a_x_b_imag),
             .valid_in(),
             .valid_out()
           );

endmodule
