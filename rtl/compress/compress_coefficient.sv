`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements compression of Falcon coefficient to a compressed representation
//
// The compressed coefficient is the sign bit, the 7 low bits of |coefficient| and the high bits |coefficient| >> 7 in
// unary (that many zeros followed by a one). Falcon only allows |coefficient| <= 2047, so it is at most 24 bits long.
// Since the representation is variable length, only the top "compressed_coefficient_length" bits of
// "compressed_coefficient" are valid.
//
//////////////////////////////////////////////////////////////////////////////////


module compress_coefficient(
    input logic clk,

    input signed [14:0] coefficient, //! Coefficient to compress
    input logic coefficient_valid,

    output logic [23:0] compressed_coefficient, //! Compressed coefficient. Only "compressed_coefficient_length" leftmost bits are valid
    output logic [4:0] compressed_coefficient_length, //! Number of valid bits in "compressed_coefficient"
    output logic too_large //! |coefficient| > 2047, the coefficient cannot be compressed
  );

  logic sign;
  logic [6:0] low;
  logic [15:0] high;
  logic [14:0] abs_coefficient;  // If coefficient is negative, we need to negate it before compressing
  logic out_of_range;

  assign abs_coefficient = (coefficient < 0) ? -coefficient : coefficient;
  assign sign = (coefficient < 0) ? 1'b1 : 1'b0;
  assign out_of_range = abs_coefficient[14:11] != 0;
  assign high = 16'h8000 >> abs_coefficient[10:7];
  assign low = abs_coefficient[6:0];

  // Register the output
  always_ff @(posedge clk) begin
    if(coefficient_valid == 1'b1 && !out_of_range) begin
      compressed_coefficient <= {sign, low, high};
      compressed_coefficient_length <= 1 + 7 + abs_coefficient[10:7] + 1; // 1 sign bit + 7 low bits + high bits (zeros) + 1 high bit (one)
    end
    else begin
      compressed_coefficient <= 0;
      compressed_coefficient_length <= 0;
    end
    too_large <= coefficient_valid && out_of_range;
  end

endmodule
