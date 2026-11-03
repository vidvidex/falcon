`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Decodes one Falcon coefficient from the start of the compressed signature.
//
// The encoding: sign bit, the 7 low bits of |s| and |s| >> 7 in unary (that many zeros and a one).
// compressed_signature holds the next bits (from the left), of which valid_bits are valid.
//
// Errors: 
//  - invalid_bits_used_error if the coefficient needs more than valid_bits bits
//  - invalid_zero_representation_error for "-0"
//
//////////////////////////////////////////////////////////////////////////////////


module decompress_coefficient(
    input logic [23:0] compressed_signature, //! Compressed signature
    input logic [4:0] valid_bits, //! Number of valid bits in compressed signature (from the left)

    output logic [14:0] coefficient, //! Decompressed coefficient
    output logic [4:0] bits_used, //! Number of bits used to decompress the current coefficient
    output logic coefficient_valid,
    output logic invalid_bits_used_error,   // Did we have to use invalid bits to decompress the coefficient?
    output logic invalid_zero_representation_error // We found invalid encoding of zero
  );

  logic sign;
  logic [6:0] low;
  logic [3:0] high;
  logic terminated;  // The unary high part ends with a one within 16 bits

  assign sign = compressed_signature[23];
  assign low = compressed_signature[22:16];

  always_comb begin
    high = 0;
    terminated = 0;
    for (int i = 0; i < 16; i++)
      if (!terminated && compressed_signature[15 - i]) begin
        high = 4'(i);
        terminated = 1;
      end
  end

  assign coefficient = sign ? -{4'b0, high, low} : {4'b0, high, low};
  assign bits_used = 1 + 7 + high + 1;  // 1 sign bit + 7 low bits + high bits (zeros) + 1 high bit (one)
  assign invalid_zero_representation_error = sign && high == 0 && low == 0;
  assign invalid_bits_used_error = valid_bits != 0 && (!terminated || bits_used > valid_bits);
  assign coefficient_valid = valid_bits != 0 && !invalid_bits_used_error && !invalid_zero_representation_error;

endmodule
