`timescale 1ns / 1ps
`include "common_definitions.vh"

// This is the implementation of the IEEE-754 adder without subnormal
// number support
// input: unbuffered
// output: buffered
module fp_adder (
    input clk,
    input logic mode, // 0 = add, 1 = subtract
    input valid_in,
    input [63:0] a,
    input [63:0] b,
    output [63:0] result,
    output valid_out
  );

  logic sign_result_2DP, data_valid_2DP, bit_shifted_out_2DP, denorm_underflow_2DP, signs_equal_2DP;
  logic [`EXPONENT_BITS-1:0] exponent_b_2DP;
  logic [`SIGNIFICANT_BITS:0] significant_b_2DP;
  logic signed [`SIGNIFICANT_BITS:0] denorm_significant_a_2DP;
  fp_adder_denormalization denormalize (
                            .clk(clk),
                            .mode(mode),
                            .valid_in(valid_in),
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

  fp_adder_sig_add_normalize add_and_normalize(
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
                            .valid_out(valid_out)
                          );

endmodule

