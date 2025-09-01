`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements compression of Falcon coefficient to a compressed representation
//
// Since compressed representation is variable length, only the top "compressed_coefficient_length" bits
// of "compressed_coefficient" are valid.
//
//////////////////////////////////////////////////////////////////////////////////


module compress_coefficient(
    input logic clk,

    input signed [14:0] coefficient, //! Coefficient to compress
    input logic coefficient_valid,

    output logic [104:0] compressed_coefficient, //! Compressed coefficient. Only "compressed_coefficient_length" leftmost bits are valid
    output logic [6:0] compressed_coefficient_length //! Number of valid bits in "compressed_coefficient"
  );

  logic sign;
  logic [6:0] low;
  logic [96:0] high;
  logic [14:0] abs_coefficient;  // If coefficient is negative, we need to negate it before compressing

  assign abs_coefficient = (coefficient < 0) ? -coefficient : coefficient;
  assign sign = (coefficient < 0) ? 1'b1 : 1'b0;
  assign high = 97'b1 << (96 - abs_coefficient[13:7]);
  assign low = abs_coefficient[6:0];

  // Register the output
  always_ff @(posedge clk) begin
    if(coefficient_valid == 1'b1) begin
      compressed_coefficient <= {sign, low, high};
      compressed_coefficient_length <= 1 + 7 + abs_coefficient[13:7] + 1; // 1 sign bit + 7 low bits + high bits (zeros) + 1 high bit (one)
    end
    else begin
      compressed_coefficient <= 0;
      compressed_coefficient_length <= 0;
    end
  end

endmodule
