`timescale 1ns / 1ps
`include "common_definitions.vh"

// performs the first half of FlP addition: operand switch and alignment of the smaller operand
// input: unbuffered
// output: buffered
//
// The smaller operand is shifted right by the exponent difference. Below its LSB it keeps a guard bit, a round bit
// and a sticky bit (OR of all bits shifted further out), which is enough for round to nearest even after the addition.
module fp_adder_denormalization (
    input clk,
    input logic mode, // 0 = add, 1 = subtract

    input valid_in,
    input [63:0] a,
    input [63:0] b,

    output logic sign_result_2DP, data_valid_2DP, signs_equal_2DP,
    output logic [`EXPONENT_BITS-1:0] exponent_b_2DP,
    output logic [`SIGNIFICANT_BITS:0] significant_b_2DP,
    output logic [`SIGNIFICANT_BITS+3:0] aligned_significant_a_2DP, // {significant, guard, round, sticky}
    output logic switched_operands_2DP
  );

  logic sign_a, sign_b;
  assign sign_a = a[63];
  assign sign_b = mode ? ~b[63] : b[63];

  logic [`EXPONENT_BITS-1:0] exponent_a, exponent_b;
  assign exponent_a = a[`SIGNIFICANT_BITS+`EXPONENT_BITS-1:`SIGNIFICANT_BITS];
  assign exponent_b = b[`SIGNIFICANT_BITS+`EXPONENT_BITS-1:`SIGNIFICANT_BITS];

  logic [`SIGNIFICANT_BITS:0] significant_a, significant_b;
  logic implicit_bit_a, implicit_bit_b;
  assign implicit_bit_a = exponent_a != `EXPONENT_BITS'd0;
  assign implicit_bit_b = exponent_b != `EXPONENT_BITS'd0;
  assign significant_a = {implicit_bit_a, a[`SIGNIFICANT_BITS-1:0]};
  assign significant_b = {implicit_bit_b, b[`SIGNIFICANT_BITS-1:0]};

  logic signs_equal;
  assign signs_equal = sign_a == sign_b;

  // swap operands if necessary s.t. a is always the smaller operand
  logic a_smaller_b, switched_operands;
  assign a_smaller_b = a[62:0] < b[62:0];
  assign switched_operands = ~a_smaller_b;

  logic [`EXPONENT_BITS:0] diff_exponent;
  assign diff_exponent = exponent_b - exponent_a;

  ////////////// Pipeline stage /////////////////////////
  logic sign_result_1DP, signs_equal_1DP, data_valid_1DP, switched_operands_1DP;
  logic [`EXPONENT_BITS-1:0] diff_exponent_1DP, exponent_b_1DP;
  logic [`SIGNIFICANT_BITS:0] significant_a_1DP, significant_b_1DP;
  always_ff @(posedge clk) begin
    data_valid_1DP <= valid_in;
    signs_equal_1DP <= signs_equal;
    switched_operands_1DP <= switched_operands;

    sign_result_1DP   <= switched_operands ? sign_a : sign_b;
    diff_exponent_1DP <= switched_operands ? -diff_exponent : diff_exponent[`EXPONENT_BITS-1:0];
    exponent_b_1DP    <= switched_operands ? exponent_a : exponent_b;
    significant_a_1DP <= switched_operands ? significant_b : significant_a;
    significant_b_1DP <= switched_operands ? significant_a : significant_b;
  end

  // Shifts of 55 or more move the whole significand into the sticky bit
  logic [5:0] shift;
  assign shift = diff_exponent_1DP > 63 ? 6'd63 : diff_exponent_1DP[5:0];

  localparam int EXTENDED_BITS = `SIGNIFICANT_BITS + 3;  // significand with hidden bit, guard and round bits
  logic [EXTENDED_BITS-1:0] significant_a_extended, aligned, shifted_out_mask;
  assign significant_a_extended = {significant_a_1DP, 2'b00};
  assign aligned = significant_a_extended >> shift;
  assign shifted_out_mask = (EXTENDED_BITS'(1) << shift) - 1'b1;

  logic sticky;
  assign sticky = |(significant_a_extended & shifted_out_mask);


  ////////////// Pipeline stage /////////////////////////
  always_ff @(posedge clk) begin
    data_valid_2DP <= data_valid_1DP;
    sign_result_2DP <= sign_result_1DP;
    signs_equal_2DP <= signs_equal_1DP;
    switched_operands_2DP <= switched_operands_1DP;

    exponent_b_2DP <= exponent_b_1DP;
    aligned_significant_a_2DP <= {aligned, sticky};
    significant_b_2DP <= significant_b_1DP;
  end

endmodule
