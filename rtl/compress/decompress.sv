`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Implements decompression of Falcon coefficients from compressed string, one coefficient per cycle.
//
// Reads compressed string from BRAM and writes decompressed coefficients back to BRAM.
//
// The resulting decompressed coefficients are written to output BRAM in the following way
//
//      64 bit (15 used)    64 bit (15 used)
//     <-----------------> <----------------->
//    |-------------------|-------------------|
//    | coefficient 0     | coefficient N/2   |
//    | coefficient 1     | coefficient N/2+1 |
//    | coefficient 2     | coefficient N/2+2 |
//    | ...               | ...               |
//    | coefficient N/2-1 | coefficient N-1   |
//    |-------------------|-------------------|
//
// Because we only write half of a memory cell at a time, but we don't want to override the other half,
// we first read the memory location and then only override the half that we need to write to.
// This is what output_bram2 signals are used for.
//
//////////////////////////////////////////////////////////////////////////////////

module decompress #(
    parameter int N = 512
  )(
    input logic clk,
    input logic rst_n,

    input logic start,

    output logic [`BRAM_ADDR_WIDTH-1:0] input_bram_addr,
    input logic [`BRAM_DATA_WIDTH-1:0] input_bram_data,

    output logic [`BRAM_ADDR_WIDTH-1:0] output_bram1_addr,
    output logic [`BRAM_DATA_WIDTH-1:0] output_bram1_data,
    output logic output_bram1_we,

    output logic [`BRAM_ADDR_WIDTH-1:0] output_bram2_addr, //! Used to read the other half of the memory cell that we are writing the output to
    input logic [`BRAM_DATA_WIDTH-1:0] output_bram2_data,

    output logic signature_error,    //! Was an error detected in the signature
    output logic done //! Decompression done, parent should also check if signature_error is set
  );

  // Expected signature length, sbytelen(depends on N) - HEAD_LEN(1) - SALT_LEN(40)
  localparam int slen = N == 8 ? 52-1-40 :
             N == 512 ? 666-1-40 :
             N == 1024 ? 1280-1-40 : 0;

  localparam int BUFFER_BITS = 256;

  typedef enum logic [1:0] {IDLE, DECOMPRESSING, FINISH, DONE} state_t;
  state_t state;

  logic [BUFFER_BITS-1:0] buffer;
  logic [8:0] buffer_valid_bits;
  logic read_pending, read_pending_1, read_data_valid;  // A block was requested and arrives 2 cycles later
  logic [$clog2(N):0] coefficient_index;
  logic [$clog2(slen*8):0] total_bits_used;
  logic [1:0] finish_count;

  // Decode the coefficient at the start of the buffer
  logic [14:0] coefficient;
  logic [4:0] bits_used;
  logic coefficient_valid, invalid_bits_used_error, invalid_zero_representation_error;
  decompress_coefficient decompress_coefficient (
                           .compressed_signature(buffer[BUFFER_BITS-1 -: 24]),
                           .valid_bits(buffer_valid_bits >= 24 ? 5'd24 : 5'(buffer_valid_bits)),
                           .coefficient(coefficient),
                           .bits_used(bits_used),
                           .coefficient_valid(coefficient_valid),
                           .invalid_bits_used_error(invalid_bits_used_error),
                           .invalid_zero_representation_error(invalid_zero_representation_error)
                         );

  // Only decode when the buffer holds a whole coefficient, so a short buffer is not mistaken for an error
  logic decode;
  assign decode = state == DECOMPRESSING && buffer_valid_bits >= 24;

  logic decode_error, used_bit_count_error, remaining_bits_not_zeros_error;

  // Buffer: append arriving blocks after the valid bits, remove the bits of decoded coefficients
  logic [BUFFER_BITS-1:0] buffer_appended;
  logic [8:0] valid_bits_appended;
  always_comb begin
    buffer_appended = buffer;
    valid_bits_appended = buffer_valid_bits;
    if (read_data_valid) begin
      buffer_appended = buffer | ({input_bram_data, 128'b0} >> buffer_valid_bits);
      valid_bits_appended = buffer_valid_bits + 128;
    end
  end

  logic consume;
  assign consume = decode && coefficient_valid;

  always_ff @(posedge clk) begin
    if (!rst_n || state == IDLE) begin
      buffer <= 0;
      buffer_valid_bits <= 0;
      read_pending <= 0;
      read_pending_1 <= 0;
      read_data_valid <= 0;
      input_bram_addr <= 0;
    end
    else begin
      buffer <= consume ? buffer_appended << bits_used : buffer_appended;
      buffer_valid_bits <= consume ? valid_bits_appended - bits_used : valid_bits_appended;

      // Request the next block when there is room for it
      read_pending_1 <= read_pending;
      read_data_valid <= read_pending_1;
      if (!read_pending && !read_pending_1 && !read_data_valid && buffer_valid_bits <= BUFFER_BITS - 128) begin
        read_pending <= 1;
      end
      else
        read_pending <= 0;
      if (read_data_valid)
        input_bram_addr <= input_bram_addr + 1;
    end
  end

  // State, coefficient counter and error checks
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= IDLE;
    end
    else begin
      case (state)
        IDLE: begin
          coefficient_index <= 0;
          total_bits_used <= 0;
          decode_error <= 0;
          used_bit_count_error <= 0;
          remaining_bits_not_zeros_error <= 0;
          finish_count <= 0;
          if (start)
            state <= DECOMPRESSING;
        end
        DECOMPRESSING: begin
          if (decode) begin
            if (!coefficient_valid) begin
              decode_error <= 1;
              state <= FINISH;
            end
            else begin
              coefficient_index <= coefficient_index + 1;
              total_bits_used <= total_bits_used + bits_used;
              if (total_bits_used + bits_used > slen*8)
                used_bit_count_error <= 1;
              if (coefficient_index == N - 1)
                state <= FINISH;
            end
          end
        end
        FINISH: begin  // Wait for the last coefficient to be written and check the remaining bits of the last byte
          finish_count <= finish_count + 1;
          if (finish_count == 0)
            remaining_bits_not_zeros_error <= buffer[BUFFER_BITS-1 -: 7] != 0;
          if (finish_count == 2)
            state <= DONE;
        end
        default: ;
      endcase
    end
  end

  // Output: read the other half of the output word, then write the coefficient into its half (2 cycles later)
  logic write_valid_1, write_valid_3;
  logic second_half_1, second_half_3;
  logic [`BRAM_ADDR_WIDTH-1:0] output_addr_1;
  logic signed [14:0] coefficient_1, coefficient_3;
  always_ff @(posedge clk) begin
    write_valid_1 <= consume;
    second_half_1 <= coefficient_index >= N/2;
    output_addr_1 <= `BRAM_ADDR_WIDTH'(coefficient_index % (N/2));
    coefficient_1 <= coefficient;
  end
  assign output_bram2_addr = output_addr_1;

  delay_register #(.BITWIDTH(1 + 1 + 15 + `BRAM_ADDR_WIDTH), .CYCLE_COUNT(2)) write_delay(
                   .clk(clk),
                   .in({write_valid_1, second_half_1, coefficient_1, output_addr_1}),
                   .out({write_valid_3, second_half_3, coefficient_3, output_bram1_addr}));

  always_comb begin
    // First half of coefficients goes to the high part of the memory cell, second half goes to the low part
    if (second_half_3)
      output_bram1_data = {output_bram2_data[127:64], 49'b0, coefficient_3};
    else
      output_bram1_data = {49'b0, coefficient_3, 64'b0};
    output_bram1_we = write_valid_3;
  end

  assign done = state == DONE;
  assign signature_error = decode_error || used_bit_count_error || remaining_bits_not_zeros_error;

endmodule
