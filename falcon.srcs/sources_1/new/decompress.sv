`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements decompression of Falcon coefficients from compressed string.
//
//////////////////////////////////////////////////////////////////////////////////


module decompress #(
    parameter int N,
    parameter int SLEN  //! Expected length of the compressed signature in bytes
  )(
    input logic clk,
    input logic rst_n,

    input logic start, //! Start decompression

    input logic [104:0] compressed_signature, //! Compressed signature
    input logic [6:0] valid_bits, //! Number of valid bits in compressed signature (from the left)

    output logic ready, //! Ready to decompress the next coefficient
    output logic [6:0] shift_by, //! Instruction to the parent module on how much to shift the compressed signature to the left
    output logic signed [14:0] polynomial [N], //! Decompressed polynomial
    output logic decompression_done,      //! Is decompression finished? When this is high the decompression is done. The parent should also check if the signature_error is high to see if there was an error in the signature.
    output logic signature_error    //! Was an error detected in the signature?
  );

  logic signed [14:0] coefficient; //! Decompressed coefficient
  logic [$clog2(N):0] decompressed_count; //! Number of coefficients decompressed so far

  logic [6:0] bits_used; //! Number of bits used to decompress the current coefficient
  logic [$clog2(SLEN*8):0] total_bits_used; //! Total number of bits used to decompress the signature

  logic invalid_bits_used_error;  // Bits that are not valid were used to decompress a coefficient
  logic cannot_find_high_error;  // We could not find the high bit in the compressed signature
  logic used_bit_count_error; // We did not use the expected number of bits to decompress the signature
  logic remaining_bits_not_zeros_error; // Once we are done decompressing the signature the remaining bits are not all zeros
  logic invalid_zero_representation_error; // We found a zero representation that is not valid

  logic decompress_coefficient_rst_n;
  logic [6:0] decompress_coefficient_valid_bits;
  logic coefficient_valid;

  decompress_coefficient decompress_coefficient (
                           .clk(clk),
                           .rst_n(decompress_coefficient_rst_n),

                           .compressed_signature(compressed_signature),
                           .valid_bits(decompress_coefficient_valid_bits),

                           .coefficient(coefficient),
                           .bits_used(bits_used),
                           .coefficient_valid(coefficient_valid),
                           .invalid_bits_used_error(invalid_bits_used_error),
                           .cannot_find_high_error(cannot_find_high_error),
                           .invalid_zero_representation_error(invalid_zero_representation_error)
                         );


  typedef enum logic [2:0] {
            IDLE,   // Waiting for start signal
            DECOMPRESS_START,  // Waiting for valid bits of the compressed signature and start decompression
            DECOMPRESSING,  // Decompressing the current coefficient
            DONE  // Output "done" pulse
          } state_t;
  state_t state, next_state;

  // Reset decompress_coefficient module when when we are done decompressing the current coefficient or when we are done decompressing the entire signature
  assign decompress_coefficient_rst_n = rst_n && !(state == DONE || state == DECOMPRESSING && coefficient_valid == 1'b1);
  assign decompress_coefficient_valid_bits = state == DECOMPRESS_START || (state == DECOMPRESSING && coefficient_valid == 1'b1) ? valid_bits : 0;

  // State machine state changes
  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start == 1'b1)  // When we get a start signal
          next_state = DECOMPRESS_START;
      end
      DECOMPRESS_START: begin
        if(decompressed_count == N) // If we decompressed all coefficients
          next_state = DONE;
        else if(valid_bits > 0)  // Wait for valid bits
          next_state = DECOMPRESSING;
      end
      DECOMPRESSING: begin
        if(coefficient_valid == 1'b1)  // Wait for valid coefficient
          next_state = DECOMPRESS_START;
        else if(invalid_bits_used_error == 1'b1 || cannot_find_high_error == 1'b1)  // If we detected an error go to done
          next_state = DONE;
      end
      DONE: begin
        next_state = DONE;
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst_n == 1'b0)
      state <= IDLE;
    else
      state <= next_state;
  end

  always_ff @(posedge clk) begin

    case (state)
      IDLE: begin
        for(int i = 0; i < N; i = i + 1)
          polynomial[i] <= 0;
        total_bits_used <= 0;
        decompressed_count <= 0;
        used_bit_count_error <= 0;
      end
      DECOMPRESSING: begin
        if(coefficient_valid == 1'b1) begin
          // Store the decompressed coefficient
          polynomial[decompressed_count] <= coefficient;
          decompressed_count <= decompressed_count + 1;

          // Check if we already used too many bits to decompress the signature
          total_bits_used <= total_bits_used + bits_used;
          if(total_bits_used > SLEN*8)
            used_bit_count_error <= 1;
        end
      end
    endcase
  end

  assign remaining_bits_not_zeros_error = (state == DONE && compressed_signature[104:98] != 0);
  assign shift_by = (state == DECOMPRESSING && coefficient_valid == 1'b1) ? bits_used : 0;
  assign ready = state == DECOMPRESS_START;
  assign decompression_done = state == DONE;
  assign signature_error = invalid_bits_used_error || cannot_find_high_error || used_bit_count_error || remaining_bits_not_zeros_error || invalid_zero_representation_error;

endmodule
