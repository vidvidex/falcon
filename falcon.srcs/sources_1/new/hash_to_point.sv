`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Hashes arbitrary length message to a polynomial
//
// In the specification the function has two parameters: message and salt, which are both hashed into a polynomial
// Since the specification simply adds first salt and then the message to the shake256 context, we will pass both
// values in the "message" parameter. First 40 bytes will be the salt, the rest will be the message.
// Parent module is responsible for first sending the salt and then immediately after the message.
//
//////////////////////////////////////////////////////////////////////////////////


module hash_to_point#(
    parameter int N
  )(
    input logic clk,
    input logic rst_n,
    input logic start,

    input logic [15:0] message_len_bytes, //! Length of the message in bytes.
    input logic [63:0] message, //! every clock cycle the next 64 bits of the message should be provided
    input logic message_valid, //! Is message valid
    input logic message_last, //! Is this the last block of message

    output logic ready, //! Are we ready to receive the next message?
    output logic signed [14:0] coefficient, //! Next coefficient coefficient
    output logic [$clog2(N)-1:0] coefficient_index, //! Index of the coefficient
    output logic coefficient_valid, //! Is the coefficient valid?
    output logic done //! Are we done hashing the message to a polynomial?
  );

  typedef enum logic[2:0] {
            IDLE,
            ABSORB,
            WAIT_FOR_SQUEEZE,
            WAIT_FOR_SQUEEZE_END
          } state_t;
  state_t state, next_state;

  logic [63:0] data_in;
  logic data_in_valid;
  logic shake256_ready;
  logic [15:0] data_out;
  logic data_out_valid, data_out_valid_i;
  logic shake256_reset; // Reset signal for shake256 module, active high
  logic [$clog2(N):0] coefficient_index_i;
  logic [15:0] t; // 16 bits of hash that we are currently processing into a coefficient of a polynomial
  logic [14:0] coefficient;

  logic unsigned [15:0] k_times_q; // k*q. k = floor(2^16 / q), q = 12289
  assign k_times_q = 16'd61445; // floor(2^16 / 12289) * 12289 = 61445

  assign done = coefficient_index_i == N;

  shake256 shake256(
             .clk(clk),
             .rst(shake256_reset),
             .input_len_bytes(message_len_bytes),
             .ready_in(shake256_ready),
             .data_in(data_in),
             .data_in_valid(data_in_valid),
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

  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin   // Waiting for start signal, delayed by 1 cycle
        if (start == 1'b1)
          next_state = ABSORB;
      end
      ABSORB: begin // Input other blocks of the message to the shake256
        if (message_last == 1'b1)  // If the message is done, then squeeze out the hash
          next_state = WAIT_FOR_SQUEEZE;
      end
      WAIT_FOR_SQUEEZE: begin  // Wait for the shake256 to start outputting the hash
        if (data_out_valid)
          next_state = WAIT_FOR_SQUEEZE_END;
      end
      WAIT_FOR_SQUEEZE_END: begin  // Wait for the shake256 to finish outputting the hash (valid goes low). If we have all coefficients we can go back to IDLE, otherwise we go to WAIT_FOR_SQUEEZE and wait for more data
        if (!data_out_valid)
          if (coefficient_index_i < N)
            next_state = WAIT_FOR_SQUEEZE;
          else
            next_state = IDLE;
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  always_comb begin
    case(state)
      IDLE: begin
        data_in = 0;
        data_in_valid = 0;

        // In IDLE shake256_reset is set high, except for the cycle when we start (we have to stop resetting one cycle early so the module is ready for data by the time we switch states)
        if(start == 1'b1)
          shake256_reset = 0;
        else
          shake256_reset = 1;
      end
      ABSORB: begin
        data_in = message;
        data_in_valid = message_valid;
        shake256_reset = 0;
      end
      WAIT_FOR_SQUEEZE: begin
        data_in = 0;
        data_in_valid = 0;
        shake256_reset = 0;
      end
      WAIT_FOR_SQUEEZE_END: begin
        data_in = 0;
        data_in_valid = 0;
        shake256_reset = 0;
      end
      default: begin
        data_in = 0;
        data_in_valid = 0;
        shake256_reset = 1;
      end
    endcase
  end

  assign ready = (state == ABSORB) ? 1 : 0;

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

  // State 2 of converting hash output to coefficient: Check if the coefficient is less than k*q and compute the modulo 12289
  always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
      coefficient_index_i <= 0;
      coefficient_valid <= 0;
    end
    else if (data_out_valid_i == 1'b1 && t < k_times_q) begin
      coefficient <= mod_12289(t);
      coefficient_index_i++;
      coefficient_valid <= 1'b1;
    end
    else
      coefficient_valid <= 0;
  end

  // coefficient_index is coefficient_index_i without the top bit and decremented by 1
  assign coefficient_index = coefficient_index_i - 1;

endmodule

