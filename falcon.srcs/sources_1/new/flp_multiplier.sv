`timescale 1ns / 1ps

// Changes compared to the original code:
// - removed external integer multiplication option. Instead we instantiate dedicated multipliers in this module (because we don't need to share them with anything else)
// - fixed delay of multiplied_significants_shifted so that the whole module can work as a pipeline

// This is the implementation of the IEEE-754 multiplier without subnormal
// number support
// input: unbuffered
// output: buffered
(* keep_hierarchy = `KEEP_HIERARCHY *)
module flp_multiplier(
    input clk,
    input valid_in,
    input [63:0] a,
    input [63:0] b,
    input signed [4:0] scale_factor, // Scale (multiply) the result by 2^scale_factor. Used for scaling IFFT results. If 0 has no effect
    output [63:0] result,
    output valid_out
  );

  logic sign_a, sign_b;
  assign sign_a = a[63];
  assign sign_b = b[63];

  logic [`EXPONENT_BITS:0] exponent_a, exponent_b;
  assign exponent_a = a[`SIGNIFICANT_BITS+`EXPONENT_BITS-1:`SIGNIFICANT_BITS];
  assign exponent_b = b[`SIGNIFICANT_BITS+`EXPONENT_BITS-1:`SIGNIFICANT_BITS];

  logic [`SIGNIFICANT_BITS:0] significant_a, significant_b;
  logic implicit_bit_a, implicit_bit_b;
  assign implicit_bit_a = exponent_a != `EXPONENT_BITS'd0;
  assign implicit_bit_b = exponent_b != `EXPONENT_BITS'd0;
  assign significant_a = {implicit_bit_a, a[`SIGNIFICANT_BITS-1:0]};
  assign significant_b = {implicit_bit_b, b[`SIGNIFICANT_BITS-1:0]};

  logic sign_result;
  assign sign_result = sign_a ^ sign_b;

  logic [`EXPONENT_BITS:0] exponent_sum;
  assign exponent_sum = signed'(exponent_a) + signed'(exponent_b) + scale_factor;

  logic [`SIGNIFICANT_BITS+1:0] multiplied_significants_shifted;

  logic [107:0] a_times_b;
  assign a_times_b = {1'd0, significant_a} * {1'd0, significant_b};
  assign multiplied_significants_shifted = a_times_b[2*`SIGNIFICANT_BITS+1:`SIGNIFICANT_BITS];


  ////////////////////////// Pipeline stage ///////////////////
  logic sign_result_1DP, data_valid_1DP;
  logic [`EXPONENT_BITS:0] exponent_sum_1DP;
  logic [`SIGNIFICANT_BITS+1:0] multiplied_significants_shifted_3DP;

  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(1+2)) data_valid_delay(.clk(clk), .in(valid_in), .out(data_valid_1DP));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(1+2)) sign_result_delay(.clk(clk), .in(sign_result), .out(sign_result_1DP));
  delay_register #(.BITWIDTH(`EXPONENT_BITS+1), .CYCLE_COUNT(1+2)) exponent_sum_delay(.clk(clk), .in(exponent_sum), .out(exponent_sum_1DP));

  logic [`EXPONENT_BITS+1:0] exponent_uncorrected;
  assign exponent_uncorrected = {1'b0, exponent_sum_1DP} - 11'd1023;

  delay_register #(.BITWIDTH(`SIGNIFICANT_BITS+2), .CYCLE_COUNT(1+4)) multiplied_significants_shifted_delay(.clk(clk), .in(multiplied_significants_shifted), .out(multiplied_significants_shifted_3DP));

  ////////////////////////// Pipeline stage ///////////////////
  logic sign_result_2DP, data_valid_2DP;
  logic [`EXPONENT_BITS+1:0] exponent_uncorrected_2DP;
  always_ff @(posedge clk) begin
    data_valid_2DP <= data_valid_1DP;
    sign_result_2DP <= sign_result_1DP;
    exponent_uncorrected_2DP <= exponent_uncorrected;
  end

  logic [`EXPONENT_BITS+1:0] exponent_corrected;
  assign exponent_corrected = exponent_uncorrected_2DP + `EXPONENT_BITS'd1;

  logic exponent_is_negative;
  assign exponent_is_negative = exponent_uncorrected_2DP[`EXPONENT_BITS+1];

  ////////////////////////// Pipeline stage ///////////////////
  logic sign_result_3DP, data_valid_3DP, exponent_is_negative_3DP;
  logic [`EXPONENT_BITS-1:0] exponent_uncorrected_3DP, exponent_corrected_3DP;
  always_ff @(posedge clk) begin
    data_valid_3DP <= data_valid_2DP;
    sign_result_3DP <= sign_result_2DP;
    exponent_is_negative_3DP <= exponent_is_negative;
    exponent_uncorrected_3DP <= (exponent_is_negative ? `EXPONENT_BITS'b0 : exponent_uncorrected_2DP[`EXPONENT_BITS-1:0]);
    exponent_corrected_3DP   <= (exponent_is_negative ? `EXPONENT_BITS'b0 : exponent_corrected[`EXPONENT_BITS-1:0]);
  end

  logic carry_bit;
  assign carry_bit = multiplied_significants_shifted_3DP[`SIGNIFICANT_BITS+1];

  logic [`EXPONENT_BITS-1:0] exponent_tmp;
  assign exponent_tmp = carry_bit ? exponent_corrected_3DP : exponent_uncorrected_3DP;

  logic significant_is_zero;
  assign significant_is_zero = multiplied_significants_shifted_3DP == {2'd0, `SIGNIFICANT_BITS'd0};

  logic zero_result;
  assign zero_result = exponent_is_negative_3DP || significant_is_zero || exponent_tmp == `EXPONENT_BITS'd0;

  logic [`SIGNIFICANT_BITS-1:0] significant_result;
  assign significant_result = carry_bit ? multiplied_significants_shifted_3DP[`SIGNIFICANT_BITS:1] : multiplied_significants_shifted_3DP[`SIGNIFICANT_BITS-1:0];


  ////////////////////////// Pipeline stage ///////////////////
  logic sign_result_4DP, data_valid_4DP, zero_result_4DP;
  logic [`EXPONENT_BITS-1:0] exponent_tmp_4DP;
  logic [`SIGNIFICANT_BITS-1:0] significant_result_4DP;
  always_ff @(posedge clk) begin
    data_valid_4DP <= data_valid_3DP;
    sign_result_4DP <= sign_result_3DP;
    zero_result_4DP <= zero_result;
    exponent_tmp_4DP <= exponent_tmp;
    significant_result_4DP <= significant_result;
  end

  ////////////////////////// final Pipeline stage ///////////////////
  logic sign_result_5DP, data_valid_5DP;
  logic [`EXPONENT_BITS-1:0] exponent_result_5DP;
  logic [`SIGNIFICANT_BITS-1:0] significant_result_5DP;
  always_ff @(posedge clk) begin
    data_valid_5DP <= data_valid_4DP;
    sign_result_5DP <= sign_result_4DP;
    exponent_result_5DP <= zero_result_4DP ? `EXPONENT_BITS'd0 : exponent_tmp_4DP;
    significant_result_5DP <= zero_result_4DP ? `SIGNIFICANT_BITS'd0 : significant_result_4DP;
  end

  assign result = {sign_result_5DP, exponent_result_5DP, significant_result_5DP};
  assign valid_out = data_valid_5DP;

endmodule
