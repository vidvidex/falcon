`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements decompression of falcon coefficient from compressed string.
//
// The module will use up to 105 from compressed string to decompress a coefficient.
// It will take a variable number of clock cycles due to the fact that we use a multi-stage priority decoder to decode the high part of the coefficient.
// In most cases the high bit will be found in the first 7 bits of high part, but it can happen that it is in any of the 14 7-bit chunks (last chunk is smaller).
//
// If the module uses bits that are not valid it'll set the "invalid_bits_used_error" flag high.
// If the module cannot find the high bit in the compressed signature it'll set the "cannot_find_high_error" flag high.
//
// After every decompression the parent module should shift the compressed signature to the left by "bits_used" bits
// and reset this module using the rst_n signal.
//
// Each coefficient is compressed as follows:
// 1. The first bit is the sign of the coefficient
// 2. The next 7 bits are the low part of the coefficient
// 3. The next 1-97 bits are the high part of the coefficient, encoded in unary (value=number of zeros, followed by a one), so we have to convert it to binary before outputting it.
//
//     [104] - sign, [103:97] - low, [96:0] - high
//
//////////////////////////////////////////////////////////////////////////////////


module decompress_coefficient(
    input logic clk,
    input logic rst_n,

    input logic [104:0] compressed_signature, //! Compressed signature
    input logic [6:0] valid_bits, //! Number of valid bits in compressed signature (from the left)

    output logic [14:0] coefficient, //! Decompressed coefficient
    output logic [6:0] bits_used, //! Number of bits used to decompress the current coefficient
    output logic coefficient_valid,
    output logic invalid_bits_used_error,   // Did we have to use invalid bits to decompress the coefficient?
    output logic cannot_find_high_error, // We could not find the high bit in the compressed signature
    output logic invalid_zero_representation_error // We found invalid encoding of zero
  );

  logic [104:0] compressed_signature_i;
  logic [6:0] valid_bits_i;

  logic sign;
  logic [6:0] low;
  logic [6:0] high;

  logic [6:0] scan_index; // Index of the 7-bit block we are currently searching for high bit
  logic found_high; // Did we find the high bit?

  assign sign = compressed_signature_i[104];
  assign low = compressed_signature_i[103:97];

  // Copy the compressed signature and valid bits to internal state, so that parent can only pulse them for one cycle and then let us do our thing for as long as we need
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || coefficient_valid == 1'b1) begin    // When parent request reset or we decompressed a coefficient we can clear the internal stateL
      compressed_signature_i = 0;
      valid_bits_i = 0;
    end
    else if(valid_bits > 0) begin
      compressed_signature_i = compressed_signature;
      valid_bits_i = valid_bits;
    end
  end

  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      scan_index <= 0;
      found_high <= 0;
      cannot_find_high_error <= 0;
      invalid_bits_used_error <= 0;
      invalid_zero_representation_error <= 0;
      coefficient_valid <= 0;
      coefficient <= 0;
      bits_used <= 0;
    end
    else if(valid_bits_i > 0) begin   // If we have valid bits to decompress

      // Check the current 7-bit block for the high bit
      for (int i = 0; i < 7; i++) begin
        if (compressed_signature_i[96 - scan_index - i]) begin
          high <= scan_index + i;
          found_high <= 1'b1;
          break;
        end
      end

      if (found_high == 1'b0) begin // Move to the next 7-bit block if no 1 is found

        scan_index <= scan_index + 7;

        // If we checked all blocks and did not find the high bit, set error flag
        if (scan_index >= 97)
          cannot_find_high_error <= 1'b1;
      end
      else begin    // Otherwise output decompressed coefficient

        // Create coefficient as signed decimals. If it's positive (sign == 0) then it's just {0, high, low}, if it's negative have to compute two's complement
        if (sign)
          coefficient <= -{1'b0, high, low}; // Negate the magnitude
        else
          coefficient <= {1'b0, high, low};  // Keep magnitude unchanged

        // Compute number of bits used to compress the current coefficient
        bits_used <= 1 + 7 + high + 1;  // 1 sign bit + 7 low bits + high bits (zeros) + 1 high bit (one)

        // Check if we used more bits than available in the compressed signature
        invalid_bits_used_error <= (1 + 7 + high + 1 > valid_bits_i);

        invalid_zero_representation_error <= {sign, high, low} == 15'b100000000000000;

        // Set coefficient valid flag
        coefficient_valid <= (1 + 7 + high + 1 <= valid_bits_i) && {sign, high, low} != 15'b100000000000000;
      end

    end
  end


endmodule
