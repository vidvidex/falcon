`timescale 1ns / 1ps
`include "common_definitions.vh"

// This is the implementation of the IEEE-754 adder without subnormal
// number support
// input: unbuffered
// output: buffered
(* keep_hierarchy = `KEEP_HIERARCHY *)
module flp_adder #(
    DO_SUBSTRACTION = 0 // 0 for addition, 1 for subtraction
  ) (
    input clk,
    input in_valid,
    input [63:0] a,
    input [63:0] b,
    output [63:0] result,
    output out_valid
  );

  logic sign_result_2DP, data_valid_2DP, bit_shifted_out_2DP, denorm_underflow_2DP, signs_equal_2DP;
  logic [`EXPONENT_BITS-1:0] exponent_b_2DP;
  logic [`SIGNIFICANT_BITS:0] significant_b_2DP;
  logic signed [`SIGNIFICANT_BITS:0] denorm_significant_a_2DP;
  flp_adder_denormalization #(.DO_SUBSTRACTION(DO_SUBSTRACTION)) denormalize (
                            .clk(clk),
                            .in_valid(in_valid),
                            .a(a),
                            .b(b),
                            .sign_result_2DP(sign_result_2DP),
                            .data_valid_2DP(data_valid_2DP),
                            .bit_shifted_out_2DP(bit_shifted_out_2DP),
                            .denorm_underflow_2DP(denorm_underflow_2DP),
                            .signs_equal_2DP(signs_equal_2DP),
                            .exponent_b_2DP(exponent_b_2DP),
                            .significant_b_2DP(significant_b_2DP),
                            .denorm_significant_a_2DP(denorm_significant_a_2DP),
                            .switched_operands_2DP()
                          );

  flp_adder_sig_add_normalize add_and_normalize(
                            .clk(clk),
                            .sign_result_2DP(sign_result_2DP),
                            .data_valid_2DP(data_valid_2DP),
                            .bit_shifted_out_2DP(bit_shifted_out_2DP),
                            .denorm_underflow_2DP(denorm_underflow_2DP),
                            .signs_equal_2DP(signs_equal_2DP),
                            .exponent_b_2DP(exponent_b_2DP),
                            .significant_b_2DP(significant_b_2DP),
                            .denorm_significant_a_2DP(denorm_significant_a_2DP),

                            .result(result),
                            .out_valid(out_valid)
                          );

endmodule

