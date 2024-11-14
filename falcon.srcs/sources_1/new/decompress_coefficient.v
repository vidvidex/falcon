`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements decompression of Falcon coefficient from compressed string.
//
// Each coefficient is compressed as follows:
// 1. The first bit is the sign of the coefficient
// 2. The next 7 bits are the low part of the coefficient
// 3. The next 1-16 bits are the high part of the coefficient, encoded in unary (value=number of zeros), so we have to convert it to binary before outputting it.
//
//     [23] - sign, [22:16] - low, [15:0] - high
//
// We enforce only one possible reprensentation of coefficient 0 (algorithm 18, line 9)
//
// If we decide more than one coefficient should be decoded at the same time, we use a longer input
// and decode multiple coefficients in parallel. We can use the compressed_coef_length of coefficient n to figure out where
// to start decompressing coefficient n+1.
//
//////////////////////////////////////////////////////////////////////////////////



module decompress_coefficient (
    input wire [23:0] compressed_signature, //! Compressed signature

    output wire [11:0] coefficient,   //! Decompressed coefficient
    output wire [4:0] compressed_coef_length, //! Number of bits used to compress the current coefficient. Parent module should shift "compressed_signature" to the left by "compressed_coef_length" bits to get the next compressed coefficient
    output wire coefficient_error  //! Was an error detected in the compressed string?
  );

  wire sign = compressed_signature[23];
  wire [6:0] low;
  reg [3:0] high;

  //! Priority encoder for the high part of the coefficient
  always @(compressed_signature[15:0])
  begin
    casex(compressed_signature[15:0])
      16'b1xxx_xxxx_xxxx_xxxx:
        high = 4'b0000;
      16'b01xx_xxxx_xxxx_xxxx:
        high = 4'b0001;
      16'b001x_xxxx_xxxx_xxxx:
        high = 4'b0010;
      16'b0001_xxxx_xxxx_xxxx:
        high = 4'b0011;
      16'b0000_1xxx_xxxx_xxxx:
        high = 4'b0100;
      16'b0000_01xx_xxxx_xxxx:
        high = 4'b0101;
      16'b0000_001x_xxxx_xxxx:
        high = 4'b0110;
      16'b0000_0001_xxxx_xxxx:
        high = 4'b0111;
      16'b0000_0000_1xxx_xxxx:
        high = 4'b1000;
      16'b0000_0000_01xx_xxxx:
        high = 4'b1001;
      16'b0000_0000_001x_xxxx:
        high = 4'b1010;
      16'b0000_0000_0001_xxxx:
        high = 4'b1011;
      16'b0000_0000_0000_1xxx:
        high = 4'b1100;
      16'b0000_0000_0000_01xx:
        high = 4'b1101;
      16'b0000_0000_0000_001x:
        high = 4'b1110;
      16'b0000_0000_0000_0001:
        high = 4'b1111;
      default:
        // Should never happen
        high = 4'b0000;
    endcase
  end

  assign low = compressed_signature[22:16];
  assign coefficient = {sign, high, low};
  assign compressed_coef_length = 9 + high;  // 1 sign bit + 7 low bits + 1 high bit (one) + high bits (zeros)

  // If coefficient is 0 and sign bit is 1 (-), we have an error (only sign + is allowed with coefficient 0) (algorithm 18, line 9)
  assign coefficient_error = (coefficient == 12'b100000000000 && sign == 1) ? 1'b1 : 1'b0;

endmodule
