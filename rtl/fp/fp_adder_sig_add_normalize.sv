`timescale 1ns / 1ps
`include "common_definitions.vh"

// performs the second half of FlP addition: significand addition, normalization and rounding to nearest even
// input: buffered outputs of fp_adder_denormalization
// output: buffered (3 cycles)
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

  // b is the larger operand, so the difference is never negative
  logic [W:0] significants_added;
  assign significants_added = signs_equal_2DP ? {significant_b_2DP, 3'b000} + aligned_significant_a_2DP
         : {significant_b_2DP, 3'b000} - aligned_significant_a_2DP;

  ////////////// Pipeline stage /////////////////////////
  logic sign_result_3DP, data_valid_3DP, signs_equal_3DP;
  logic [`EXPONENT_BITS-1:0] exponent_b_3DP;
  logic [W:0] significants_added_3DP;
  always_ff @(posedge clk) begin
    data_valid_3DP <= data_valid_2DP;
    sign_result_3DP <= sign_result_2DP;
    signs_equal_3DP <= signs_equal_2DP;

    exponent_b_3DP <= exponent_b_2DP;
    significants_added_3DP <= significants_added;
  end

  logic [$clog2(W)-1:0] leading_zeros;
  logic lower_bits_zero, significant_is_zero;
  leading_zero_count #(.BITWIDTH(W)) leading_zero_cnt(.in(significants_added_3DP[W-1:0]),
                     .out(leading_zeros),
                     .input_is_zero(lower_bits_zero));
  assign significant_is_zero = lower_bits_zero && !significants_added_3DP[W];

  // Normalize to {1.significand, guard, round, sticky}. On a carry the result is shifted right by one and the bit
  // shifted out goes into the sticky bit. A left shift by more than one bit only happens when the exponents differ by
  // at most one, in which case the round and sticky bits are zero and the shift is exact.
  logic carry_bit;
  assign carry_bit = significants_added_3DP[W];

  logic [W-1:0] significant_normalized;
  assign significant_normalized = carry_bit ? {significants_added_3DP[W:2], |significants_added_3DP[1:0]}
         : significants_added_3DP[W-1:0] << leading_zeros;

  logic signed [`EXPONENT_BITS+1:0] exponent_normalized;
  assign exponent_normalized = carry_bit ? $signed({2'b00, exponent_b_3DP}) + 1
         : $signed({2'b00, exponent_b_3DP}) - $signed({7'd0, leading_zeros});

  ////////////// Pipeline stage /////////////////////////
  logic sign_result_4DP, data_valid_4DP, zero_result_4DP;
  logic [W-1:0] significant_normalized_4DP;
  logic [`EXPONENT_BITS-1:0] exponent_normalized_4DP;
  always_ff @(posedge clk) begin
    data_valid_4DP <= data_valid_3DP;
    // An exact zero is +0 unless both operands are zeros with the same sign. Underflow is flushed to zero.
    sign_result_4DP <= significant_is_zero ? sign_result_3DP && signs_equal_3DP : sign_result_3DP;
    zero_result_4DP <= significant_is_zero || exponent_normalized <= 0;

    significant_normalized_4DP <= significant_normalized;
    exponent_normalized_4DP <= exponent_normalized[`EXPONENT_BITS-1:0];
  end

  // Round to nearest, ties to even. A carry out of the significand increments the exponent.
  logic guard, round_or_sticky, round_up;
  assign guard = significant_normalized_4DP[2];
  assign round_or_sticky = |significant_normalized_4DP[1:0];
  assign round_up = guard && (round_or_sticky || significant_normalized_4DP[3]);

  logic [62:0] magnitude_rounded;
  assign magnitude_rounded = {exponent_normalized_4DP, significant_normalized_4DP[W-2:3]} + round_up;

  ////////////// final pipeline stage /////////////////////////
  logic sign_result_5DP, data_valid_5DP;
  logic [62:0] magnitude_5DP;
  always_ff @(posedge clk) begin
    data_valid_5DP <= data_valid_4DP;
    sign_result_5DP <= sign_result_4DP;
    magnitude_5DP <= zero_result_4DP ? 63'd0 : magnitude_rounded;
  end

  assign result = {sign_result_5DP, magnitude_5DP};
  assign valid_out = data_valid_5DP;
endmodule
