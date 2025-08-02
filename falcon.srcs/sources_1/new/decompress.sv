`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Implements decompression of Falcon coefficients from compressed string.
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
// This is what input_bram2 signals are used for.

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

  logic [$clog2(N):0] coefficient_index;

  logic [6:0] bits_used; //! Number of bits used to decompress the current coefficient
  logic [$clog2(slen*8):0] total_bits_used; //! Total number of bits used to decompress the signature

  logic invalid_bits_used_error;  // Bits that are not valid were used to decompress a coefficient
  logic cannot_find_high_error;  // We could not find the high bit in the compressed signature
  logic used_bit_count_error; // We did not use the expected number of bits to decompress the signature
  logic remaining_bits_not_zeros_error; // Once we are done decompressing the signature the remaining bits are not all zeros
  logic invalid_zero_representation_error; // We found a zero representation that is not valid

  logic decompress_coefficient_rst_n;

  logic [1:0] read_signature_length_counter; // Counter for how many cycles we've been in the READ_SIGNATURE_LENGTH state
  logic [13:0] signature_length_bits;

  logic input_bram_data_valid, input_bram_data_valid_delayed;
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) input_bram_data_valid_delay(.clk(clk), .in(input_bram_data_valid), .out(input_bram_data_valid_delayed));

  logic second_half, second_half_delayed; // 1 = we've processed the first half of coefficients
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(3)) second_half_delay(.clk(clk), .in(second_half), .out(second_half_delayed));

  logic signed [14:0] coefficient, coefficient_delayed;
  delay_register #(.BITWIDTH(15), .CYCLE_COUNT(2)) coefficient_delay(.clk(clk), .in(coefficient), .out(coefficient_delayed));

  logic output_we;
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) output_we_delay(.clk(clk), .in(output_we), .out(output_bram1_we));

  delay_register #(.BITWIDTH(`BRAM_ADDR_WIDTH), .CYCLE_COUNT(2)) output_bram_addr_delay(.clk(clk), .in(output_bram2_addr), .out(output_bram1_addr));

  logic [2*128-1:0] buffer, buffer_tmp; // Buffer of compressed signature bits
  logic [8:0] buffer_valid_bits;  // How many bits in the buffer are valid (counting from the left)

  logic [7:0] valid_bits;
  logic waiting_for_input_data; // Did we already issue a read and we're waiting for BRAM

  decompress_coefficient decompress_coefficient (
                           .clk(clk),
                           .rst_n(decompress_coefficient_rst_n),

                           .compressed_signature(buffer[2*128-1 -: 105]), // Pass top 105 bits of the buffer
                           .valid_bits(valid_bits),

                           .coefficient(coefficient),
                           .bits_used(bits_used),
                           .coefficient_valid(coefficient_valid),
                           .invalid_bits_used_error(invalid_bits_used_error),
                           .cannot_find_high_error(cannot_find_high_error),
                           .invalid_zero_representation_error(invalid_zero_representation_error)
                         );


  typedef enum logic [2:0] {
            IDLE,   // Waiting for start signal
            READ_SIGNATURE_LENGTH, // Reading signature length from the first BRAM cell
            DECOMPRESS_START,  // Waiting for valid bits of the compressed signature and start decompression
            DECOMPRESSING,  // Decompressing the current coefficient
            DONE  // Output "done" pulse
          } state_t;
  state_t state, next_state;

  assign decompress_coefficient_rst_n = rst_n && !(state == READ_SIGNATURE_LENGTH || state == DECOMPRESS_START || state == DONE || state == DECOMPRESSING && coefficient_valid == 1'b1);

  // State machine state changes
  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start == 1'b1)
          next_state = READ_SIGNATURE_LENGTH;
      end
      READ_SIGNATURE_LENGTH: begin
        if(read_signature_length_counter == 2)
          next_state = DECOMPRESS_START;
      end
      DECOMPRESS_START: begin
        if(coefficient_index == N) // If we decompressed all coefficients
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
        total_bits_used <= 0;
        coefficient_index <= 0;
        used_bit_count_error <= 0;
        second_half <= 0;
      end
      DECOMPRESSING: begin
        if(coefficient_valid == 1'b1) begin

          coefficient_index++;

          if(coefficient_index == N/2)
            second_half <= 1;

          // Check if we already used too many bits to decompress the signature
          total_bits_used <= total_bits_used + bits_used;
          if(total_bits_used > slen*8)
            used_bit_count_error <= 1;
        end
      end
    endcase
  end

  assign output_bram2_addr = coefficient_index % (N/2);

  // Reading from BRAM
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || state == IDLE) begin
      input_bram_addr <= 0;
      input_bram_data_valid <= 1'b0;
      read_signature_length_counter <= 0;
      buffer_valid_bits <= 0;
      buffer <= 0;
      waiting_for_input_data <= 1'b0;
    end
    else begin

      if(state == READ_SIGNATURE_LENGTH)
        read_signature_length_counter <= read_signature_length_counter + 1;

      if(read_signature_length_counter == 2)
        signature_length_bits <= input_bram_data;

      if(input_bram_data_valid_delayed == 1'b1 && coefficient_valid == 1'b1) begin
        // We read next block of data and we have a valid coefficient.

        buffer_tmp = buffer;
        buffer_tmp[2*128-1-buffer_valid_bits -: 128] = input_bram_data;
        buffer <= buffer_tmp << bits_used;

        buffer_valid_bits = buffer_valid_bits + 128 - bits_used;
        waiting_for_input_data <= 1'b0;
      end
      else if(input_bram_data_valid_delayed == 1'b1) begin
        // We read next block of data
        buffer[2*128-1-buffer_valid_bits -: 128] = input_bram_data;
        buffer_valid_bits = buffer_valid_bits + 128;
        waiting_for_input_data <= 1'b0;
      end
      else if(coefficient_valid == 1'b1) begin
        // We have a valid coefficient
        buffer_valid_bits <= buffer_valid_bits - bits_used;
        buffer <= buffer << bits_used;
      end

      // When there is space for a block of 128 bits in the buffer and we're not waiting for data we issue a BRAM read
      if(buffer_valid_bits <= 128 && waiting_for_input_data == 1'b0) begin
        input_bram_addr <= input_bram_addr + 1;
        input_bram_data_valid <= 1'b1;
        waiting_for_input_data <= 1'b1;
      end
      else
        input_bram_data_valid <= 1'b0;
    end
  end

  always_comb begin
    // First half of coefficients goes to the high part of the memory cell, second half goes to the low part
    if(second_half_delayed)
      output_bram1_data = {output_bram2_data[127:64], 49'b0, coefficient_delayed};
    else
      output_bram1_data = {49'b0, coefficient_delayed, 64'b0};

    output_we = coefficient_valid; // Write only when we have a valid coefficient
  end

  assign valid_bits = (signature_length_bits < 105) ? signature_length_bits : 105;

  assign remaining_bits_not_zeros_error = (state == DONE && buffer[2*128-1:2*128-7] != 0);
  assign done = state == DONE;
  assign signature_error = invalid_bits_used_error || cannot_find_high_error || used_bit_count_error || remaining_bits_not_zeros_error || invalid_zero_representation_error;

endmodule
