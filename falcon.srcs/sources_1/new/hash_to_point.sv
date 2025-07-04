`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// THE COMMENTED VERSION IS THE VERSION THAT WORKS WITH VERIFY MODULE. THE UNCOMMENTED VERSION IS THE ONE THAT IS ADJUSTED
// FOR SIGNING (READS DIRECTLY FROM MEMORY). AT THE END BOTH SIGNING AND VERIFYING SHOULD USE THE SAME IMPLEMENTATION.
//
// Hashes arbitrary length message to a polynomial
//
// In the specification the function has two parameters: message and salt, which are both hashed into a polynomial
// Since the specification simply adds first salt and then the message to the shake256 context, we will input them
// to the module as if they are the same thing (we just concatenate them in memory)
//
// Module will read "message_len_bytes" from the first location of input BRAM.
// Following that it will read message_len_bytes bytes of the message and salt from memory, starting at address 1. Currently it only reads bottom 64 bits of each memory location
//
// The resulting polynomial coefficients is written to output BRAM in the following way, which is tailored to be used as input for the FFT module
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
//
//////////////////////////////////////////////////////////////////////////////////

module hash_to_point#(
    parameter int N
  )(
    input logic clk,
    input logic rst_n,
    input logic start,

    output logic [`BRAM_ADDR_WIDTH-1:0] input_bram_addr, //! Used to read input for the hash_to_point module
    input logic [`BRAM_DATA_WIDTH-1:0] input_bram_data,

    output logic [`BRAM_ADDR_WIDTH-1:0] output_bram1_addr, //! Address for output BRAM
    output logic [`BRAM_DATA_WIDTH-1:0] output_bram1_data, //! Data that is written to output_bram[output_bram1_addr]
    output logic output_bram1_we, //! Write enable for output BRAM

    output logic [`BRAM_ADDR_WIDTH-1:0] output_bram2_addr, //! Used to read the other half of the memory cell that we are writing the output to
    input logic [`BRAM_DATA_WIDTH-1:0] output_bram2_data,

    output logic done //! Are we done hashing the message to a polynomial?
  );

  typedef enum logic[2:0] {
            IDLE,
            READ_MESSAGE_LENGTH, // Read message length from memory
            ABSORB,
            WAIT_FOR_SQUEEZE,
            WAIT_FOR_SQUEEZE_END,
            FINISH
          } state_t;
  state_t state, next_state;

  logic [15:0] message_len_bytes;
  logic [63:0] data_in;
  logic [15:0] data_out;
  logic data_out_valid, data_out_valid_i;
  logic shake256_reset; // Reset signal for shake256 module, active high
  logic [$clog2(N):0] coefficient_index;
  logic [15:0] t; // 16 bits of hash that we are currently processing into a coefficient of a polynomial
  logic [15:0] bytes_processed;
  logic [1:0] read_message_length_counter; // Counter for how many cycles we've been in the READ_MESSAGE_LENGTH state
  logic data_in_valid, data_in_valid_i;

  logic second_half, second_half_delayed; // 1 = we've processed the first half of coefficients
  DelayRegister #(.BITWIDTH(1), .CYCLE_COUNT(3)) second_half_delay(.clk(clk), .in(second_half), .out(second_half_delayed));

  logic signed [14:0] coefficient, coefficient_delayed;
  DelayRegister #(.BITWIDTH(15), .CYCLE_COUNT(2)) coefficient_delay(.clk(clk), .in(coefficient), .out(coefficient_delayed));

  logic output_we;
  DelayRegister #(.BITWIDTH(1), .CYCLE_COUNT(2)) output_we_delay(.clk(clk), .in(output_we), .out(output_bram1_we));

  DelayRegister #(.BITWIDTH(`BRAM_ADDR_WIDTH), .CYCLE_COUNT(2)) output_bram_addr_delay(.clk(clk), .in(output_bram2_addr), .out(output_bram1_addr));

  logic unsigned [15:0] k_times_q; // k*q. k = floor(2^16 / q), q = 12289
  assign k_times_q = 16'd61445; // floor(2^16 / 12289) * 12289 = 61445

  shake256 shake256(
             .clk(clk),
             .rst(shake256_reset),
             .input_len_bytes(message_len_bytes),
             .data_in(data_in),
             .data_in_valid(data_in_valid_i),
             .data_out(data_out),
             .data_out_valid(data_out_valid)
           );

  // Compute a % 12289 for a up to 5*12289 = 61445
  function [14:0] mod_12289(input [15:0] a);
    begin
      if(a < 1*12289)
        mod_12289 = a;
      else if(a < 2*12289)
        mod_12289 = a - 12289;
      else if(a < 3*12289)
        mod_12289 = a - 2*12289;
      else if(a < 4*12289)
        mod_12289 = a - 3*12289;
      else
        mod_12289 = a - 4*12289;
    end
  endfunction

  always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
      state <= IDLE;
    end
    else
      state <= next_state;
  end

  // Reading from input BRAM
  always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
      bytes_processed <= 0;
      input_bram_addr <= 0;
    end
    else if (state == READ_MESSAGE_LENGTH || state == ABSORB) begin
      bytes_processed <= bytes_processed + 8; // 8 bytes per cycle
      input_bram_addr <= input_bram_addr + 1; // Increment address to read next 8 bytes
    end
  end

  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin   // Waiting for start signal, delayed by 1 cycle
        if (start == 1'b1)
          next_state = READ_MESSAGE_LENGTH;
      end
      READ_MESSAGE_LENGTH: begin
        if(read_message_length_counter == 2)
          next_state = ABSORB;
      end
      ABSORB: begin // Input other blocks of the message to the shake256
        if (bytes_processed >= message_len_bytes + 16)  // If the message is done, then squeeze out the hash
          next_state = WAIT_FOR_SQUEEZE;
      end
      WAIT_FOR_SQUEEZE: begin  // Wait for the shake256 to start outputting the hash
        if (data_out_valid)
          next_state = WAIT_FOR_SQUEEZE_END;
      end
      WAIT_FOR_SQUEEZE_END: begin  // Wait for the shake256 to finish outputting the hash (valid goes low) or to output all coefficients.
        if(coefficient_index == N-1) // If we have all coefficients we can go to FINISH
          next_state = FINISH;
        else if (!data_out_valid)  // Go to WAIT_FOR_SQUEEZE and wait for more data
          next_state = WAIT_FOR_SQUEEZE;
      end
      FINISH: begin  // Wait forever
        next_state = FINISH;
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  always_comb begin
    case(state)
      IDLE: begin
        data_in_valid = 0;
        shake256_reset = 1;
      end
      READ_MESSAGE_LENGTH: begin
        data_in_valid = 0;

        // For the first few cycles we hold reset high, but for the last cycle we set it low so that the shake256 module is ready to accept data
        if (read_message_length_counter == 2)
          shake256_reset = 0;
        else
          shake256_reset = 1;
      end
      ABSORB: begin
        data_in_valid = 1;
        shake256_reset = 0;
      end
      WAIT_FOR_SQUEEZE: begin
        data_in_valid = 0;
        shake256_reset = 0;
      end
      WAIT_FOR_SQUEEZE_END: begin
        data_in_valid = 0;
        shake256_reset = 0;
      end
      FINISH: begin
        data_in_valid = 0;
        shake256_reset = 1;
      end
      default: begin
        data_in_valid = 0;
        shake256_reset = 1;
      end
    endcase
  end

  // Read message length, message from BRAM
  always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
      read_message_length_counter <= 0;
      message_len_bytes <= 0;
      output_we <= 0;
    end
    else begin
      if(state == READ_MESSAGE_LENGTH)
        read_message_length_counter <= read_message_length_counter + 1;

      if (read_message_length_counter == 2)
        message_len_bytes <= input_bram_data[15:0];
    end

    data_in <= data_in_valid ? input_bram_data : 64'b0;
    data_in_valid_i <= data_in_valid;
  end

  assign done = state == FINISH;
  assign ready = state == ABSORB;

  // State 1 of converting hash output to coefficient: Read and swap the bytes of the hash output
  always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
      data_out_valid_i <= 0;
    end
    else if(data_out_valid == 1'b1) begin
      // The bytes of the returned hash have different endianness than what we need, therefore we read them in opposite order
      t <= {data_out[7:0], data_out[15:8]};
    end
    data_out_valid_i <= data_out_valid;
  end

  always_comb begin
    // First half of coefficients goes to the high part of the memory cell, second half goes to the low part
    if(second_half_delayed)
      output_bram1_data = {output_bram2_data[127:64], 49'b0, coefficient_delayed};
    else
      output_bram1_data = {49'b0, coefficient_delayed, 64'b0};
  end

  // State 2 of converting hash output to coefficient: Check if the coefficient is less than k*q and compute the modulo 12289
  always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
      coefficient <= 0;
      coefficient_index <= 0;
      second_half <= 0;
    end
    else if (data_out_valid_i == 1'b1 && t < k_times_q && done != 1) begin

      coefficient <= mod_12289(t);

      if(coefficient_index == N/2 - 1)
        second_half <= 1;

      output_bram2_addr <= coefficient_index++ % (N/2); // Write to the first half of the memory cell, then to the second half
      output_we <= 1;
    end
    else
      output_we <= 1'b0;
  end

endmodule

// module hash_to_point#(
//     parameter int N
//   )(
//     input logic clk,
//     input logic rst_n,
//     input logic start,

//     input logic [15:0] message_len_bytes, //! Length of the message in bytes.
//     input logic [63:0] message, //! every clock cycle the next 64 bits of the message should be provided
//     input logic message_valid, //! Is message valid
//     input logic message_last, //! Is this the last block of message

//     output logic ready, //! Are we ready to receive the next message?
//     output logic signed [14:0] coefficient, //! Next coefficient coefficient
//     output logic [$clog2(N)-1:0] coefficient_index, //! Index of the coefficient
//     output logic coefficient_valid, //! Is the coefficient valid?
//     output logic done //! Are we done hashing the message to a polynomial?
//   );

//   typedef enum logic[2:0] {
//             IDLE,
//             ABSORB,
//             WAIT_FOR_SQUEEZE,
//             WAIT_FOR_SQUEEZE_END,
//             FINISH
//           } state_t;
//   state_t state, next_state;

//   logic [63:0] data_in;
//   logic data_in_valid;
//   logic [15:0] data_out;
//   logic data_out_valid, data_out_valid_i;
//   logic shake256_reset; // Reset signal for shake256 module, active high
//   logic [$clog2(N):0] coefficient_index_i;
//   logic [15:0] t; // 16 bits of hash that we are currently processing into a coefficient of a polynomial
//   logic coefficient_valid_internal;

//   logic unsigned [15:0] k_times_q; // k*q. k = floor(2^16 / q), q = 12289
//   assign k_times_q = 16'd61445; // floor(2^16 / 12289) * 12289 = 61445

//   assign done = coefficient_index_i == N || state == FINISH;

//   shake256 shake256(
//              .clk(clk),
//              .rst(shake256_reset),
//              .input_len_bytes(message_len_bytes),
//              .data_in(data_in),
//              .data_in_valid(data_in_valid),
//              .data_out(data_out),
//              .data_out_valid(data_out_valid)
//            );

//   // Compute a % 12289 for a up to 5*12289 = 61445
//   function [14:0] mod_12289(input [15:0] a);
//     begin
//       if(a < 1*12289)
//         mod_12289 = a;
//       else if(a < 2*12289)
//         mod_12289 = a - 12289;
//       else if(a < 3*12289)
//         mod_12289 = a - 2*12289;
//       else if(a < 4*12289)
//         mod_12289 = a - 3*12289;
//       else
//         mod_12289 = a - 4*12289;
//     end
//   endfunction

//   always_ff @(posedge clk) begin
//     if (rst_n == 1'b0) begin
//       state <= IDLE;
//     end
//     else
//       state <= next_state;
//   end

//   always_comb begin
//     next_state = state;

//     case (state)
//       IDLE: begin   // Waiting for start signal, delayed by 1 cycle
//         if (start == 1'b1)
//           next_state = ABSORB;
//       end
//       ABSORB: begin // Input other blocks of the message to the shake256
//         if (message_last == 1'b1)  // If the message is done, then squeeze out the hash
//           next_state = WAIT_FOR_SQUEEZE;
//       end
//       WAIT_FOR_SQUEEZE: begin  // Wait for the shake256 to start outputting the hash
//         if (data_out_valid)
//           next_state = WAIT_FOR_SQUEEZE_END;
//       end
//       WAIT_FOR_SQUEEZE_END: begin  // Wait for the shake256 to finish outputting the hash (valid goes low) or to output all coefficients.
//         if(done) // If we have all coefficients we can go to FINISH
//           next_state = FINISH;
//         else if (!data_out_valid)  // Go to WAIT_FOR_SQUEEZE and wait for more data
//           next_state = WAIT_FOR_SQUEEZE;
//       end
//       FINISH: begin  // Wait forever
//         next_state = FINISH;
//       end
//       default: begin
//         next_state = IDLE;
//       end
//     endcase
//   end

//   always_comb begin
//     case(state)
//       IDLE: begin
//         data_in = 0;
//         data_in_valid = 0;

//         // In IDLE shake256_reset is set high, except for the cycle when we start (we have to stop resetting one cycle early so the module is ready for data by the time we switch states)
//         if(start == 1'b1)
//           shake256_reset = 0;
//         else
//           shake256_reset = 1;
//       end
//       ABSORB: begin
//         data_in = message;
//         data_in_valid = message_valid;
//         shake256_reset = 0;
//       end
//       WAIT_FOR_SQUEEZE: begin
//         data_in = 0;
//         data_in_valid = 0;
//         shake256_reset = 0;
//       end
//       WAIT_FOR_SQUEEZE_END: begin
//         data_in = 0;
//         data_in_valid = 0;
//         shake256_reset = 0;
//       end
//       FINISH: begin
//         data_in = 0;
//         data_in_valid = 0;
//         shake256_reset = 1;
//       end
//       default: begin
//         data_in = 0;
//         data_in_valid = 0;
//         shake256_reset = 1;
//       end
//     endcase
//   end

//   assign ready = (state == ABSORB) ? 1 : 0;

//   // State 1 of converting hash output to coefficient: Read and swap the bytes of the hash output
//   always_ff @(posedge clk) begin
//     if (rst_n == 1'b0) begin
//       data_out_valid_i <= 0;
//     end
//     else if(data_out_valid == 1'b1) begin
//       // The bytes of the returned hash have different endianness than what we need, therefore we read them in opposite order
//       t <= {data_out[7:0], data_out[15:8]};
//     end
//     data_out_valid_i <= data_out_valid;
//   end

//   // State 2 of converting hash output to coefficient: Check if the coefficient is less than k*q and compute the modulo 12289
//   always_ff @(posedge clk) begin
//     if (rst_n == 1'b0) begin
//       coefficient_index_i <= 0;
//       coefficient_valid_internal <= 0;
//     end
//     else if (data_out_valid_i == 1'b1 && t < k_times_q) begin
//       coefficient <= mod_12289(t);
//       coefficient_index_i++;
//       coefficient_valid_internal <= 1'b1;
//     end
//     else
//       coefficient_valid_internal <= 0;
//   end

//   // coefficient_index is coefficient_index_i without the top bit and decremented by 1
//   assign coefficient_index = coefficient_index_i - 1;
//   assign coefficient_valid = coefficient_valid_internal && (coefficient_index_i <= N);

// endmodule

