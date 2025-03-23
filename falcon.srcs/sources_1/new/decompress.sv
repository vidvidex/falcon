`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements decompression of Falcon coefficients from compressed string.
//
// Each clock cycle this module uses up 9 to 105 bits of "compressed_signature" to decompress a coefficient.
// The number of bits actually used to decompress it is output in "shift_by". Parent module should
// shift "compressed_signature" to the left by "shift_by" bits to prepare it for decompression of the next coefficient.
//
// The module will start working as soon as "valid_bits" is set to a non-zero value.
//
// Once all coefficients are decompressed the "decompression_done" signal is set high,
// along with "signature_error" if an error was detected in the signature.
// "signature_error" can be set high even before decompression is finished.
//
// Each coefficient is compressed as follows:
// 1. The first bit is the sign of the coefficient
// 2. The next 7 bits are the low part of the coefficient
// 3. The next 1-97 bits are the high part of the coefficient, encoded in unary (value=number of zeros, followed by a one), so we have to convert it to binary before outputting it.
//
//     [104] - sign, [103:97] - low, [96:0] - high
//
//
//////////////////////////////////////////////////////////////////////////////////


module decompress #(
    parameter int N,
    parameter int SLEN  //! Expected length of the compressed signature in bytes
  )(
    input logic clk,
    input logic rst_n,

    input logic [104:0] compressed_signature, //! Compressed signature
    input logic [6:0] valid_bits, //! Number of valid bits in compressed signature (from the left)

    output logic [6:0] shift_by, //! Instruction to the parent module on how much to shift the compressed signature to the left
    output logic signed [14:0] polynomial [N], //! Decompressed polynomial
    output logic decompression_done,      //! Is decompression finished? When this is high the decompression is done. The parent should also check if the signature_error is high to see if there was an error in the signature.
    output logic signature_error    //! Was an error detected in the signature?
  );

  logic signed [14:0] coefficient; //! Decompressed coefficient
  logic [$clog2(N):0] decompressed_count; //! Number of coefficients decompressed so far

  logic [6:0] bits_used; //! Number of bits used to decompress the current coefficient
  logic [$clog2(SLEN*8):0] total_bits_used; //! Total number of bits used to decompress the signature

  // Parts of the polynomial
  logic sign;
  logic [6:0] low;
  logic [6:0] high;

  logic invalid_bits_used_error;  // Bits that are not valid were used to decompress a coefficient
  logic used_bit_count_error; // We did not use the expected number of bits to decompress the signature
  logic remaining_bits_not_zeros_error; // Once we are done decompressing the signature the remaining bits are not all zeros

  //! Priority encoder for the high part of the coefficient
  always_comb begin
    high = 5'b00000;

    // Go over the encoded high bits and find the first 1, hopefully this gets synthesized to an efficient priority encoder
    for (int i = 0; i <= 96; i++) begin
      if (compressed_signature[96-i]) begin
        high = i;
        break;
      end
    end
  end
  assign sign = compressed_signature[104];
  assign low = compressed_signature[103:97];

  // Stage 1: Decompress coefficient and compute number of bits used
  always_ff @(posedge clk) begin
    if (rst_n == 1'b0 || valid_bits == 0 || decompressed_count > N) begin
      bits_used <= 0;
      coefficient <= 0;
    end
    else begin
      // Create coefficient as signed decimals. If it's positive (sign == 0) then it's just {0, high, low}, if it's negative have to compute two's complement
      if (sign)
        coefficient = -{1'b0, high, low}; // Negate the magnitude
      else
        coefficient = {1'b0, high, low};  // Keep magnitude unchanged

      // Compute number of bits used to compress the current coefficient
      bits_used <= 1 + 7 + high + 1;  // 1 sign bit + 7 low bits + high bits (zeros) + 1 high bit (one)
    end
  end

  // Output shift_by in the same clock cycle as it was computed, so that the parent module can use it to prepare data for the next cycle
  assign shift_by = valid_bits > 0 ?  1 + 7 + high + 1 : 0;

  // Stage 2: Save coefficient to polynomial, check for errors and control decompression_done
  always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
      for(int i = 0; i < N; i = i + 1)
        polynomial[i] <= 0;
      decompressed_count <= 0;
      used_bit_count_error <= 0;
      invalid_bits_used_error <= 0;
      remaining_bits_not_zeros_error <= 0;
      decompression_done <= 0;
      total_bits_used <= 0;
    end
    else if(valid_bits > 0) begin

      // Check if we already used too many bits to decompress the signature
      if(total_bits_used > SLEN*8)
        used_bit_count_error <= 1;

      if(decompressed_count < N) begin
        // Check if we decompressed invalid bits
        if(bits_used <= valid_bits) begin
          polynomial[decompressed_count] <= coefficient;
          decompressed_count <= decompressed_count + 1;
          total_bits_used <= total_bits_used + bits_used;
        end
        else begin
          invalid_bits_used_error <= 1;
        end
      end

      // When we decompressed all coefficient we have to check that any remaining bits are zeros
      if(decompressed_count == N)
        if(compressed_signature[104:98] != 0)
          remaining_bits_not_zeros_error <= 1;
        else
          decompression_done <= 1;
    end
  end

  assign signature_error = invalid_bits_used_error || used_bit_count_error || remaining_bits_not_zeros_error;

endmodule
