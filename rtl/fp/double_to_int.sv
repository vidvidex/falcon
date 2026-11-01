`timescale 1ns / 1ps

// Implements conversion from double to an int.
// Before conversion the double is rounded to the nearest integer.
module double_to_int (
    input logic clk,
    input logic [63:0] double_in,
    input logic valid_in,
    output logic signed [14:0] int_out,
    output logic valid_out
  );

  logic sign;
  logic [10:0] exponent;
  logic [51:0] fraction;
  logic signed [14:0] int_out_i;

  logic [52:0] mantissa_with_hidden_bit;
  logic [63:0] shifted_mantissa;
  logic signed [11:0] exponent_unbiased;

  always_comb begin
    sign = double_in[63];
    exponent = double_in[62:52];
    fraction = double_in[51:0];

    // Add hidden bit for normalized numbers
    mantissa_with_hidden_bit = (exponent == 0) ? {1'b0, fraction} : {1'b1, fraction};

    // Unbias exponent (bias = 1023)
    exponent_unbiased = $signed(exponent) - 12'd1023;

    shifted_mantissa = 64'd0;

    if (exponent_unbiased < 52) begin
      // Right shift — add rounding before shift
      automatic int shift_amount = 52 - exponent_unbiased;

      if (shift_amount < 64 && shift_amount > 0) begin
        automatic logic [63:0] extended_mantissa = {11'b0, mantissa_with_hidden_bit};
        automatic logic [63:0] rounding_add = 64'd1 << (shift_amount - 1);
        automatic logic [63:0] rounded_mantissa = extended_mantissa + rounding_add;
        shifted_mantissa = rounded_mantissa >> shift_amount;
      end
      else if (shift_amount <= 0) begin
        // No shift needed or left shift needed
        shifted_mantissa = mantissa_with_hidden_bit;
      end
      else begin
        shifted_mantissa = 0; // too small, rounds to zero
      end
    end
    else begin
      // Left shift for large exponent (no rounding needed)
      shifted_mantissa = mantissa_with_hidden_bit << (exponent_unbiased - 52);
    end

    // Apply sign and truncate to 15 bits
    int_out_i = sign ? -$signed(shifted_mantissa[14:0]) : $signed(shifted_mantissa[14:0]);
  end

  // Register the output
  always_ff @(posedge clk) begin
    int_out <= int_out_i;
    valid_out <= valid_in;
  end

endmodule
