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
    input signed [11:0] coefficient, //! Coefficient to compress

    output logic [23:0] compressed_coefficient, //! Compressed coefficient. Only "compressed_coefficient_length" leftmost bits from "compressed_coefficient" are valid
    output logic [4:0] compressed_coefficient_length //! Number of bits used to compress the coefficient.
  );

  logic sign;
  logic [6:0] low;
  logic [15:0] high;
  logic [11:0] abs_coefficient;  // If coefficient is negative, we need to negate it before compressing

  always_comb begin

    case(abs_coefficient[10:7])
      4'b0000:
        high = 16'b1xxx_xxxx_xxxx_xxxx;
      4'b0001:
        high = 16'b01xx_xxxx_xxxx_xxxx;
      4'b0010:
        high = 16'b001x_xxxx_xxxx_xxxx;
      4'b0011:
        high = 16'b0001_xxxx_xxxx_xxxx;
      4'b0100:
        high = 16'b0000_1xxx_xxxx_xxxx;
      4'b0101:
        high = 16'b0000_01xx_xxxx_xxxx;
      4'b0110:
        high = 16'b0000_001x_xxxx_xxxx;
      4'b0111:
        high = 16'b0000_0001_xxxx_xxxx;
      4'b1000:
        high = 16'b0000_0000_1xxx_xxxx;
      4'b1001:
        high = 16'b0000_0000_01xx_xxxx;
      4'b1010:
        high = 16'b0000_0000_001x_xxxx;
      4'b1011:
        high = 16'b0000_0000_0001_xxxx;
      4'b1100:
        high = 16'b0000_0000_0000_1xxx;
      4'b1101:
        high = 16'b0000_0000_0000_01xx;
      4'b1110:
        high = 16'b0000_0000_0000_001x;
      4'b1111:
        high = 16'b0000_0000_0000_0001;
      default:
        // Should never happen
        high = 16'b0000_0000_0000_0000;
    endcase
  end

  assign abs_coefficient = (coefficient < 0) ? -coefficient : coefficient;
  assign sign = (coefficient < 0) ? 1'b1 : 1'b0;
  assign low = abs_coefficient[6:0];
  assign compressed_coefficient = {sign, low, high};
  assign compressed_coefficient_length = 9 + abs_coefficient[10:7]; // 1 sign bit + 7 low bits + 1 high bit (one) + high bits (zeros)

endmodule
