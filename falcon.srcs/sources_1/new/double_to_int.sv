`timescale 1ns / 1ps

// Implements conversion from double to an int.
// Before conversion the double is rounded to the nearest integer.
module double_to_int (
    input  logic clk,
    input  logic [63:0] double_in,
    output logic signed [14:0] int_out
);

  logic sign;
  logic [10:0] exponent;
  logic [51:0] fraction;
  logic signed [31:0] int_out_i;

  logic [52:0] mantissa_with_hidden_bit;
  logic [63:0] shifted_mantissa;
  logic [11:0] exponent_unbiased;
  logic [31:0] result_unsigned;

  always_comb begin
    sign = double_in[63];
    exponent = double_in[62:52];
    fraction = double_in[51:0];

    // Add hidden bit for normalized numbers
    mantissa_with_hidden_bit = (exponent == 0) ? {1'b0, fraction} : {1'b1, fraction};

    // Unbias exponent (bias = 1023)
    exponent_unbiased = exponent - 11'd1023;

    // Default output
    result_unsigned = 32'd0;
    shifted_mantissa = 64'd0;

    if (exponent_unbiased < 52) begin
      // Right shift — add rounding before shift
      int shift_amount = 52 - exponent_unbiased;

      if (shift_amount < 64) begin
        // Round to nearest (add 1 at bit position shift_amount-1)
        logic [63:0] rounding_add = 64'd1 << (shift_amount - 1);
        shifted_mantissa = mantissa_with_hidden_bit + rounding_add;
        shifted_mantissa = shifted_mantissa >> shift_amount;
      end else begin
        shifted_mantissa = 0; // too small, rounds to zero
      end
    end
    else begin
      // Left shift for large exponent (no rounding needed)
      shifted_mantissa = mantissa_with_hidden_bit << (exponent_unbiased - 52);
    end

    // Truncate to 14 bits
    result_unsigned = shifted_mantissa[14:0];

    // Apply sign
    int_out_i = sign ? -result_unsigned : result_unsigned;
  end

  // Register the output
  always_ff @(posedge clk) begin
    int_out <= int_out_i;
  end

endmodule
