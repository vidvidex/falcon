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
    output logic signed [14:0] polynomial[0:N-1], //! Output polynomial, defined as an array of coefficients
    output logic polynomial_valid //! Is polynomial valid
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
  logic [63:0] data_out;
  logic data_out_valid, data_out_valid_i, data_out_valid_ii;
  logic shake256_reset; // Reset signal for shake256 module, active high
  logic unsigned [$clog2(N):0] polynomial_index; // Index of the polynomial that we are currently writing to
  logic [15:0] t1, t2, t3, t4; // 16 bits of hash that we are currently processing into a polynomial
  logic [14:0] t1_i, t2_i, t3_i, t4_i; // Same as above, but further in the pipeline

  logic t1_i_ok, t2_i_ok, t3_i_ok, t4_i_ok; // Are the coefficients less than k*q?

  logic unsigned [15:0] k_times_q; // k*q. k = floor(2^16 / q), q = 12289
  assign k_times_q = 16'd61445; // floor(2^16 / 12289) * 12289 = 61445

  assign polynomial_valid = polynomial_index == N; // Polynomial is valid when we have filled all the coefficients

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
          if (polynomial_index < N)
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
        ready = 0;

        // In IDLE shake256_reset is set high, except for the cycle when we start (we have to stop resetting one cycle early so the module is ready for data by the time we switch states)
        if(start == 1'b1)
          shake256_reset = 0;
        else
          shake256_reset = 1;
      end
      ABSORB: begin
        data_in = message;
        data_in_valid = message_valid;
        ready = 1;
        shake256_reset = 0;
      end
      WAIT_FOR_SQUEEZE: begin
        data_in = 0;
        data_in_valid = 0;
        ready = 0;
        shake256_reset = 0;
      end
      WAIT_FOR_SQUEEZE_END: begin
        data_in = 0;
        data_in_valid = 0;
        ready = 0;
        shake256_reset = 0;
      end
    endcase
  end

  // State 1 of converting hash output to polynomial: Create 4 16-bit values from the 64-bit hash
  always_ff @(posedge clk) begin

    if (rst_n == 1'b0) begin
      t1 <= 0;
      t2 <= 0;
      t3 <= 0;
      t4 <= 0;
      data_out_valid_i <= 0;
    end
    else if(data_out_valid == 1'b1) begin
      // The bytes of the returned hash have different endianness than what we need, therefore we read them in opposite order
      t1 <= {data_out[7:0], data_out[15:8]};
      t2 <= {data_out[23:16], data_out[31:24]};
      t3 <= {data_out[39:32], data_out[47:40]};
      t4 <= {data_out[55:48], data_out[63:56]};
    end
    data_out_valid_i <= data_out_valid;
  end

  // State 2 of converting hash output to polynomial: Check if the coefficients are less than k*q and compute the modulo 12289
  always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
      t1_i_ok <= 0;
      t2_i_ok <= 0;
      t3_i_ok <= 0;
      t4_i_ok <= 0;
      t1_i <= 0;
      t2_i <= 0;
      t3_i <= 0;
      t4_i <= 0;
    end
    else if (data_out_valid_i == 1'b1) begin
      t1_i_ok <= t1 < k_times_q;
      t2_i_ok <= t2 < k_times_q;
      t3_i_ok <= t3 < k_times_q;
      t4_i_ok <= t4 < k_times_q;
      t1_i <= t1 % 12289;
      t2_i <= t2 % 12289;
      t3_i <= t3 % 12289;
      t4_i <= t4 % 12289;
    end
    data_out_valid_ii <= data_out_valid_i;
  end

  // State 3 of converting hash output to polynomial: Write the coefficients to the polynomial
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      for(int i = 0; i < N; i++)
        polynomial[i] <= 0;
      polynomial_index <= 0;
    end
    else if(data_out_valid_ii == 1'b1) begin
      if(t1_i_ok == 1 && polynomial_index < N) begin
        polynomial[polynomial_index] <= t1_i;
        polynomial_index = polynomial_index + 1;
      end

      if(t2_i_ok == 1 && polynomial_index < N) begin
        polynomial[polynomial_index] <= t2_i;
        polynomial_index = polynomial_index + 1;
      end

      if(t3_i_ok == 1 && polynomial_index < N) begin
        polynomial[polynomial_index] <= t3_i;
        polynomial_index = polynomial_index + 1;
      end

      if(t4_i_ok == 1 && polynomial_index < N) begin
        polynomial[polynomial_index] <= t4_i;
        polynomial_index = polynomial_index + 1;
      end
    end
  end

endmodule

