`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements decompression of Falcon coefficient from compressed string.
//
// Each coefficient is compressed as follows:
// 1. The first bit is the sign of the coefficient
// 2. The next 7 bits are the low part of the coefficient
// 3. The next 1-97 bits are the high part of the coefficient, encoded in unary (value=number of zeros, followed by a one), so we have to convert it to binary before outputting it.
//
//     [104] - sign, [103:97] - low, [96:0] - high
//
// We enforce only one possible representation of coefficient 0 (algorithm 18, line 9)
//
// If we decide more than one coefficient should be decoded at the same time, we use a longer input
// and decode multiple coefficients in parallel. We can use the compressed_coef_length of coefficient n to figure out where
// to start decompressing coefficient n+1.
//
// The output of this module is coefficient in "signed decimal" representation
//
//////////////////////////////////////////////////////////////////////////////////

module decompress_coefficient (
    input logic [104:0] compressed_signature, //! Compressed signature

    output logic signed [14:0] coefficient,   //! Decompressed coefficient
    output logic [6:0] compressed_coef_length, //! Number of bits used to compress the current coefficient. Parent module should shift "compressed_signature" to the left by "compressed_coef_length" bits to get the next compressed coefficient
    output logic coefficient_error  //! Was an error detected in the compressed string?
  );

  logic sign;
  logic [6:0] low;
  logic [6:0] high;

  //! Priority encoder for the high part of the coefficient
  always_comb begin
    high = 5'b00000;

    // Go over the encoded high bits and find the first 1
    for (logic [6:0] i = 0; i < 17; i++) begin
      if (compressed_signature[96-i]) begin
        high = i;
        break;
      end
    end
  end

  assign sign = compressed_signature[104];
  assign low = compressed_signature[103:97];


  // Create final coefficient as signed decimal. If it's positive (sign == 0) then it's just {0, high, low}, if it's negative we also compute two's complement
  always_comb begin
    if (sign) begin
      coefficient = -{1'b0, high, low}; // Negate the magnitude
    end
    else begin
      coefficient = {1'b0, high, low};  // Keep magnitude unchanged
    end
  end

  assign compressed_coef_length = 1 + 7 + high + 1;  // 1 sign bit + 7 low bits + high bits (zeros) + 1 high bit (one)

  // If {high, low} is 0 and sign bit is 1 (-), we have an error (only sign + is allowed with coefficient 0) (algorithm 18, line 9)
  assign coefficient_error = ({sign, high, low} == 15'b100000000000000) ? 1'b1 : 1'b0;

endmodule
