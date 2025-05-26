`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

// Changes: removed interfaces for shared external multiplier

// performs a complex multiplication
// i.e.: (a_real + j*a_imag) * (b_real + j*b_imag) =
//       = (a_real*b_real - a_imag*b_imag) + j(a_imag*b_real + a_real*b_imag)
// input: unbuffered
// output: buffered
(* keep_hierarchy = `KEEP_HIERARCHY *)
module ComplexMultiplier(
    input clk,
    input start,
    input [`OVERALL_BITS-1:0] a_real,
    input [`OVERALL_BITS-1:0] a_imag,
    input [`OVERALL_BITS-1:0] b_real,
    input [`OVERALL_BITS-1:0] b_imag,
    input signed [4:0] scale_factor, // Scale (multiply) the result by 2^scale_factor. Used for scaling IFFT results. If 0 has no effect

    output [`OVERALL_BITS-1:0] a_x_b_real,
    output [`OVERALL_BITS-1:0] a_x_b_imag,

    output done
  );

  logic mult_done;
  logic [`OVERALL_BITS-1:0] ar_x_br, ar_x_bi, ai_x_br, ai_x_bi;

  FLPMultiplier mult_ar_x_br(
                  .clk(clk),
                  .start(start),
                  .a(a_real),
                  .b(b_real),
                  .scale_factor(scale_factor),
                  .result(ar_x_br),
                  .done(mult_done)
                );
  FLPMultiplier mult_ar_x_bi(
                  .clk(clk),
                  .a(a_real),
                  .b(b_imag),
                  .scale_factor(scale_factor),
                  .result(ar_x_bi),
                  .start(),
                  .done()
                );
  FLPMultiplier mult_ai_x_br(
                  .clk(clk),
                  .a(a_imag),
                  .b(b_real),
                  .scale_factor(scale_factor),
                  .result(ai_x_br),
                  .start(),
                  .done()
                );
  FLPMultiplier mult_ai_x_bi(
                  .clk(clk),
                  .a(a_imag),
                  .b(b_imag),
                  .scale_factor(scale_factor),
                  .result(ai_x_bi),
                  .start(),
                  .done()
                );

  FLPAdder #(.DO_SUBSTRACTION(1)) adder_real_result(
             .clk(clk),
             .start(mult_done),
             .a(ar_x_br),
             .b(ai_x_bi),
             .result(a_x_b_real),
             .done(done)
           );

  FLPAdder #(.DO_SUBSTRACTION(0)) adder_imag_result(
             .clk(clk),
             .a(ar_x_bi),
             .b(ai_x_br),
             .result(a_x_b_imag),
             .start(),
             .done()
           );

endmodule
