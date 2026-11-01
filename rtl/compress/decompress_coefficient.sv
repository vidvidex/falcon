`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements decompression of falcon coefficient from compressed string.
//
// The module will use up to 24 bits from compressed string to decompress a coefficient.
//
// If the module uses bits that are not valid it'll set the "invalid_bits_used_error" flag high.
//
// After every decompression the parent module should shift the compressed signature to the left by "bits_used" bits
// and reset this module using the rst_n signal.
//
// Each coefficient is compressed as follows:
// 1. The first bit is the sign of the coefficient
// 2. The next 7 bits are the low part of the coefficient
// 3. The next 1-16 bits are the high part of the coefficient, encoded in unary (value=number of zeros, followed by a one), so we have to convert it to binary before outputting it.
//
//     [23] - sign, [22:16] - low, [15:0] - high
//
//////////////////////////////////////////////////////////////////////////////////


module decompress_coefficient(
    input logic clk,
    input logic rst_n,

    input logic [23:0] compressed_signature, //! Compressed signature
    input logic [4:0] valid_bits, //! Number of valid bits in compressed signature (from the left)

    output logic [14:0] coefficient, //! Decompressed coefficient
    output logic [4:0] bits_used, //! Number of bits used to decompress the current coefficient
    output logic coefficient_valid,
    output logic invalid_bits_used_error,   // Did we have to use invalid bits to decompress the coefficient?
    output logic invalid_zero_representation_error // We found invalid encoding of zero
  );

  logic [4:0] valid_bits_i;
  logic sign;
  logic [6:0] low;
  logic [6:0] high;

  // Stage 1: Compute sign, low and high parts of the coefficient
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || valid_bits == 0) begin
      sign <= 0;
      low <= 0;
      high <= 0;
      valid_bits_i <= 0;
    end
    else begin

      sign <= compressed_signature[23];
      low <= compressed_signature[22:16];

      casez (compressed_signature[15:0])
        16'b0000_0000_0000_0001:
          high <= 7'd15;
        16'b0000_0000_0000_001?:
          high <= 7'd14;
        16'b0000_0000_0000_01??:
          high <= 7'd13;
        16'b0000_0000_0000_1???:
          high <= 7'd12;
        16'b0000_0000_0001_????:
          high <= 7'd11;
        16'b0000_0000_001?_????:
          high <= 7'd10;
        16'b0000_0000_01??_????:
          high <= 7'd9;
        16'b0000_0000_1???_????:
          high <= 7'd8;
        16'b0000_0001_????_????:
          high <= 7'd7;
        16'b0000_001?_????_????:
          high <= 7'd6;
        16'b0000_01??_????_????:
          high <= 7'd5;
        16'b0000_1???_????_????:
          high <= 7'd4;
        16'b0001_????_????_????:
          high <= 7'd3;
        16'b001?_????_????_????:
          high <= 7'd2;
        16'b01??_????_????_????:
          high <= 7'd1;
        16'b1???_????_????_????:
          high <= 7'd0;
        default:
          high <= 7'd0; // Should not happen
      endcase

      valid_bits_i <= valid_bits;
    end
  end

  // Stage 2: Compute the coefficient and bits used
  always_ff @(posedge clk) begin

    if(rst_n == 1'b0 || valid_bits_i == 0) begin
      invalid_bits_used_error <= 0;
      invalid_zero_representation_error <= 0;
      coefficient_valid <= 0;
      coefficient <= 0;
      bits_used <= 0;
    end
    else begin

      // Create coefficient as signed decimals. If it's positive (sign == 0) then it's just {0, high, low}, if it's negative have to compute two's complement
      if (sign)
        coefficient <= -{1'b0, high, low}; // Negate the magnitude
      else
        coefficient <= {1'b0, high, low};  // Keep magnitude unchanged

      bits_used <= 1 + 7 + high + 1;  // 1 sign bit + 7 low bits + high bits (zeros) + 1 high bit (one)

      invalid_zero_representation_error <= {sign, high, low} == 15'b100000000000000;
      invalid_bits_used_error <= (1 + 7 + high + 1 > valid_bits_i);         // Check if we used more bits than available in the compressed signature
      coefficient_valid <= (1 + 7 + high + 1 <= valid_bits_i) && {sign, high, low} != 15'b100000000000000;
    end
  end

endmodule
