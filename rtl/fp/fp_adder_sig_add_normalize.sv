`timescale 1ns / 1ps
`include "common_definitions.vh"

// performs the second half of FlP addition: significand addition, normalization and rounding to nearest even
// input: unbuffered
// output: buffered
//
// Results that would be subnormal are flushed to zero. An exact zero result of operands with different signs is +0.
module fp_adder_sig_add_normalize(
    input logic clk,
    input logic sign_result_2DP, data_valid_2DP, signs_equal_2DP,
    input logic [`EXPONENT_BITS-1:0] exponent_b_2DP,
    input logic [`SIGNIFICANT_BITS:0] significant_b_2DP,
    input logic [`SIGNIFICANT_BITS+3:0] aligned_significant_a_2DP, // {significant, guard, round, sticky}

    output logic [63:0] result,
    output logic valid_out
  );

  localparam int W = `SIGNIFICANT_BITS + 4;  // significand with hidden bit, guard, round and sticky bits

  ////////////// Pipeline stage /////////////////////////
  logic sign_result_2aDP, data_valid_2aDP, signs_equal_2aDP;
  logic [`EXPONENT_BITS-1:0] exponent_b_2aDP;
  logic [W-1:0] significant_a_2aDP, significant_b_2aDP;
  always_ff @(posedge clk) begin
    data_valid_2aDP <= data_valid_2DP;
    sign_result_2aDP <= sign_result_2DP;
    signs_equal_2aDP <= signs_equal_2DP;

    exponent_b_2aDP <= exponent_b_2DP;
    significant_a_2aDP <= aligned_significant_a_2DP;
    significant_b_2aDP <= {significant_b_2DP, 3'b000};
  end

  // b is the larger operand, so the difference is never negative
  logic [W:0] significants_added;
  assign significants_added = signs_equal_2aDP ? significant_b_2aDP + significant_a_2aDP
         : significant_b_2aDP - significant_a_2aDP;

  ////////////// Pipeline stage /////////////////////////
  logic sign_result_3DP, data_valid_3DP, signs_equal_3DP;
  logic [`EXPONENT_BITS-1:0] exponent_b_3DP;
  logic [W:0] significants_added_3DP;
  always_ff @(posedge clk) begin
    data_valid_3DP <= data_valid_2aDP;
    sign_result_3DP <= sign_result_2aDP;
    signs_equal_3DP <= signs_equal_2aDP;

    exponent_b_3DP <= exponent_b_2aDP;
    significants_added_3DP <= significants_added;
  end

  logic [$clog2(W)-1:0] leading_zeros;
  logic significant_is_zero;
  leading_zero_count #(.BITWIDTH(W)) leading_zero_cnt(.in(significants_added_3DP[W-1:0]),
                     .out(leading_zeros),
                     .input_is_zero(significant_is_zero));

  ////////////// Pipeline stage /////////////////////////
  logic sign_result_4DP, data_valid_4DP, signs_equal_4DP, significant_is_zero_4DP;
  logic [`EXPONENT_BITS-1:0] exponent_b_4DP;
  logic [W:0] significants_added_4DP;
  logic [$clog2(W)-1:0] leading_zeros_4DP;
  always_ff @(posedge clk) begin
    data_valid_4DP <= data_valid_3DP;
    sign_result_4DP <= sign_result_3DP;
    signs_equal_4DP <= signs_equal_3DP;
    significant_is_zero_4DP <= significant_is_zero && !significants_added_3DP[W];

    exponent_b_4DP <= exponent_b_3DP;
    significants_added_4DP <= significants_added_3DP;
    leading_zeros_4DP <= leading_zeros;
  end

  logic carry_bit;
  assign carry_bit = significants_added_4DP[W];

  logic [W-1:0] significant_normalized;
  assign significant_normalized = carry_bit ? {significants_added_4DP[W:2], |significants_added_4DP[1:0]}
         : significants_added_4DP[W-1:0] << leading_zeros_4DP;

  logic signed [`EXPONENT_BITS+1:0] exponent_normalized;
  assign exponent_normalized = carry_bit ? $signed({2'b00, exponent_b_4DP}) + 1
         : $signed({2'b00, exponent_b_4DP}) - $signed({7'd0, leading_zeros_4DP});

  ////////////// Pipeline stage /////////////////////////
  logic sign_result_5DP, data_valid_5DP, zero_result_5DP;
  logic [W-1:0] significant_normalized_5DP;
  logic [`EXPONENT_BITS-1:0] exponent_normalized_5DP;
  always_ff @(posedge clk) begin
    data_valid_5DP <= data_valid_4DP;
    // An exact zero is +0 unless both operands are zeros with the same sign. Underflow is flushed to zero.
    sign_result_5DP <= significant_is_zero_4DP ? sign_result_4DP && signs_equal_4DP : sign_result_4DP;
    zero_result_5DP <= significant_is_zero_4DP || exponent_normalized <= 0;

    significant_normalized_5DP <= significant_normalized;
    exponent_normalized_5DP <= exponent_normalized[`EXPONENT_BITS-1:0];
  end

  // Round to nearest, ties to even. A carry out of the significand increments the exponent.
  logic guard, round_or_sticky, round_up;
  assign guard = significant_normalized_5DP[2];
  assign round_or_sticky = |significant_normalized_5DP[1:0];
  assign round_up = guard && (round_or_sticky || significant_normalized_5DP[3]);

  logic [62:0] magnitude_rounded;
  assign magnitude_rounded = {exponent_normalized_5DP, significant_normalized_5DP[W-2:3]} + round_up;

  ////////////// final pipeline stage /////////////////////////
  logic sign_result_6DP, data_valid_6DP;
  logic [62:0] magnitude_6DP;
  always_ff @(posedge clk) begin
    data_valid_6DP <= data_valid_5DP;
    sign_result_6DP <= sign_result_5DP;
    magnitude_6DP <= zero_result_5DP ? 63'd0 : magnitude_rounded;
  end

  assign result = {sign_result_6DP, magnitude_6DP};
  assign valid_out = data_valid_6DP;
endmodule
