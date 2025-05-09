`timescale 1ns / 1ps
`include "CommonDefinitions.vh"


(* keep_hierarchy = `KEEP_HIERARCHY *)
module int_to_double
  (
    input  logic clk,
    input  logic signed [14:0] int_in,
    output logic [63:0] double_out
  );

  logic        sign;
  logic [14:0] abs_val;
  logic [10:0] exponent;
  logic [51:0] mantissa;
  logic [14:0] normalized;
  logic [5:0]  shift;
  integer i;
  logic [63:0] double_out_i;

  always_comb begin
    sign = int_in[14];
    abs_val = sign ? -int_in : int_in;

    if (abs_val != 0) begin
      // Find MSB position
      shift = 0;
      for (i = 14; i >= 0; i = i - 1) begin
        if (abs_val[i]) begin
          shift = i;
          break;
        end
      end

      // Exponent = bias + MSB position
      exponent = 11'd1023 + shift;

      // Normalize the input so the MSB is at bit 14
      normalized = abs_val << (14 - shift);

      // Drop the leading 1 (implicit), align to 52-bit mantissa
      mantissa = {normalized[13:0], 38'd0};

      // Assemble the double: sign | exponent | mantissa
      double_out_i = {sign, exponent, mantissa};
    end
    else begin
      // Zero case
      double_out_i = 64'd0;
    end
  end

  // Register the output
  always_ff @(posedge clk) begin
    double_out <= double_out_i;
  end
endmodule
