`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Verifies that "signature" is a correct signature for "message" using the public key defined as (r, s)
//
// Communication with this module aims to roughly follow the AXI-stream protocol way of communication.
// 1. The module is started by setting the "start" signal high for one clock cycle
// 2. The module can request new data by setting the "_ready" signal high for the respective data
// 3. The module provides the data by setting the "_valid" signal high for the respective data
// 4. While both "_ready" and "_valid" signals are high the module is receiving new data and processing it. When either of the two signals is low the module is not receiving new data
//      (either because the parent cannot provide the data fast enough for the parent is providing the data too fast)
// 5. The module signals that it has finished processing the data by setting the "accept" or "reject" signal high
//
// The module is composed out of multiple parts, which work in parallel:
//  - hash_to_point: Converts the message to a polynomial
//  - decompress: Decompresses the signature
//  - NTT: This is the "main" part of the module, which has most of the control logic
// Due to there being multiple parts there are also multiple state machines that control the whole module.
//
// Parent of this module should provide both salt from signature and the message via the "message" signal.
// The first 40B (5 blocks of 64 bit) should be the salt and everything else the message.
// Size of salt should not be included in "message_len_bytes" (it is added by this module)
//
//////////////////////////////////////////////////////////////////////////////////

module verify#(
    parameter int N,
    parameter int SBYTELEN,
    parameter int MULT_MOD_Q_OPS_PER_CYCLE = 4, //! The number of operations per cycle for the MULT_MOD_Q module. N should be divisible by this number.
    parameter int SUB_AND_NORMALIZE_OPS_PER_CYCLE = 4, //! The number of operations per cycle for the SUB_AND_NORMALIZE module. N should be divisible by this number.
    parameter int SQUARED_NORM_OPS_PER_CYCLE = 4 //! The number of operations per cycle for the SQUARED_NORM module. N should be divisible by this number.
  )(
    input logic clk,
    input logic rst_n,

    input logic start, //! Start signal for the module

    input logic signed [14:0] public_key[0:N-1], //! Public key in coefficient form
    input logic public_key_valid, //! Is public key valid

    input logic [15:0] message_len_bytes, //! Length of the message in bytes. This does not take into account the size of the salt, which will also be inputed as "message"
    input logic [63:0] message, //! every clock cycle the next 64 bits of the message should be provided
    input logic message_valid, //! Is message valid
    input logic message_last, //! Is this the last block of message
    output logic message_ready, //! Is ready to receive the next message

    input logic [63:0] signature,
    input logic [6:0] signature_valid, //! Is signature valid, bitwise from the left
    output logic signature_ready, //! Is ready to receive the next signature block

    output logic accept, //! Set to true if signature is valid
    output logic reject //! Set to true if signature is invalid
  );

  /////////////////////////// Start hash_to_point ///////////////////////////

  logic signed [14:0] htp_polynomial[0:N-1]; // Output polynomial from hash_to_point
  logic htp_polynomial_valid; // Is htp_polynomial from hash_to_point valid

  hash_to_point #(
                  .N(N)
                )hash_to_point(
                  .clk(clk),
                  .rst_n(rst_n),
                  .start(start),
                  .message_len_bytes(message_len_bytes+40), // +40 because we first send 40B of salt and only then we start sending the message
                  .message(message),
                  .message_valid(message_valid),
                  .message_last(message_last),
                  .ready(message_ready),
                  .polynomial(htp_polynomial),
                  .polynomial_valid(htp_polynomial_valid)
                );

  /////////////////////////// End hash_to_point ///////////////////////////

  /////////////////////////// Start decompress ///////////////////////////

  //! Buffer to store 3 64-bit words of compressed signature.
  // We need 3 because decompress module can potentially require 105 bits at once,
  // but this module only receives 64 bits at once.
  // By using 3 blocks of 64 we can ensure that we can provide all 105 bits at once
  // and also have enough space to load new 64 bit block.
  // With only 2x64 bits we would have a problem when decompression only used for example 65 bits,
  // so we couldn't load a new block in.
  logic [3*64-1:0] compressed_signature_buffer;
  logic [6:0] compressed_signature_buffer_valid; //! Number of valid bits in compressed_signature_buffer. Only leftmost bits are valid.

  logic signed [14:0] decompressed_polynomial [N];
  logic [6:0] shift_by; //! Number of bits that were used to compress the coefficient, we need to shift the buffer by this amount
  logic signature_error; //! Set to true if the signature is invalid
  logic decompression_done; //! Set to true if the decompression is done

  decompress #(
               .N(N),
               .SLEN(8 * SBYTELEN - 328)  // 328 = 8 * (40 + 1), 40 bytes of salt and 1 byte of header
             ) decompress(
               .clk(clk),
               .rst_n(rst_n),
               .compressed_signature(compressed_signature_buffer[3*64-1 -: 105]), // Provide top 105 bits of the buffer to decompress module
               .valid_bits(compressed_signature_buffer_valid),
               .shift_by(shift_by),
               .polynomial(decompressed_polynomial),
               .decompression_done(decompression_done),
               .signature_error(signature_error)
             );

  typedef enum logic [2:0] {
            DECOMPRESS_IDLE, // Waiting for the start signal
            READY_FOR_SIGNATURE, // Ready to receive the next 64 bits of the signature. If we have any existing compressed data we are also decompressing it in this state.
            DECOMPRESSING, // Decompressing coefficients, don't need new signature data
            DECOMPRESSION_DONE // Decompression is done
          } decompress_state_t;
  decompress_state_t decompress_state, decompress_next_state;

  // State machine state changes
  always_comb begin
    decompress_next_state = decompress_state;

    case (decompress_state)
      DECOMPRESS_IDLE: begin   // Waiting for the start signal
        if (start == 1'b1)
          decompress_next_state = READY_FOR_SIGNATURE;
      end
      READY_FOR_SIGNATURE: begin  // Wait for signature buffer to be full
        if(decompression_done == 1'b1 || signature_error == 1'b1) // Decompression is done or there was an error
          decompress_next_state = DECOMPRESSION_DONE;
        else if (compressed_signature_buffer_valid > 128)  // Buffer is full if we have more than 128 valid bits in it (we cannot add another 64 bit block to it)
          decompress_next_state = DECOMPRESSING;
      end
      DECOMPRESSING: begin  // Go to DECOMPRESSION_DONE if we're done or READY_FOR_SIGNATURE if we have space for more data
        if(decompression_done == 1'b1 || signature_error == 1'b1) // Decompression is done or there was an error
          decompress_next_state = DECOMPRESSION_DONE;
        else if (compressed_signature_buffer_valid < 128) // We have space for more data
          decompress_next_state = READY_FOR_SIGNATURE;
      end
      DECOMPRESSION_DONE: begin // Stay here forever
        decompress_next_state = DECOMPRESSION_DONE;
      end
      default: begin
        decompress_next_state = DECOMPRESS_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst_n == 1'b0)
      decompress_state <= DECOMPRESS_IDLE;
    else
      decompress_state <= decompress_next_state;
  end

  always_ff @(posedge clk) begin

    case (decompress_state)
      DECOMPRESS_IDLE: begin
        signature_ready <= 1'b0;
        compressed_signature_buffer <= 0;
        compressed_signature_buffer_valid <= 0;
      end
      READY_FOR_SIGNATURE: begin
        signature_ready <= 1'b1; // We can receive the next 64 bits of the signature
      end
      DECOMPRESSING: begin
        signature_ready <= 1'b0;
      end
      DECOMPRESSION_DONE: begin
        signature_ready <= 1'b0;
      end
    endcase

    // Logic for loading new signature data and storing decompressed coefficients
    if(decompress_state == DECOMPRESSING || decompress_state == READY_FOR_SIGNATURE) begin

      // Load new block of signature data
      if(signature_valid) begin
        compressed_signature_buffer[3*64-1-compressed_signature_buffer_valid -: 64] = signature;
        compressed_signature_buffer_valid = compressed_signature_buffer_valid + signature_valid;
      end

      // We have to shift the buffer to the left by "shift_by" bits to provide the next compressed coefficient to the decompression module.
      compressed_signature_buffer <= compressed_signature_buffer << shift_by;
      compressed_signature_buffer_valid <= compressed_signature_buffer_valid - shift_by;
    end
  end

  /////////////////////////// End decompress ///////////////////////////

  /////////////////////////// Start NTT and general control logic //////

  logic signed [14:0] ntt_input[0:N-1];
  logic signed [14:0] ntt_output[0:N-1];

  logic signed [14:0] ntt_buffer1[0:N-1]; // Buffer for NTT module, here we store the result of NTT(public key), NTT(public key) * NTT(decompressed signature) = product, INTT(product), htp_polynomial - INTT(product)
  logic signed [14:0] ntt_buffer2[0:N-1]; // Buffer for NTT module, here we store the result of NTT(decompressed signature)

  logic ntt_start; //! Start signal for NTT module
  logic ntt_mode; //! 0 - NTT, 1 - INTT
  logic ntt_done; //! Set high when NTT module is done and ntt_output is valid
  logic [$clog2(N):0] mult_mod_q_index, sub_and_normalize_index, squared_norm_index; //! Indices used for iterating over the buffer arrays. Need to be large enough to store N.

  logic signed [14:0] mod_mult_a [MULT_MOD_Q_OPS_PER_CYCLE], mod_mult_b [MULT_MOD_Q_OPS_PER_CYCLE], mod_mult_result [MULT_MOD_Q_OPS_PER_CYCLE];
  logic mod_mult_valid_in, mod_mult_valid_out, mod_mult_last;
  logic [$clog2(N):0] mod_mult_index_in, mod_mult_index_out;

  logic signed [14:0] squared_norm_a [MULT_MOD_Q_OPS_PER_CYCLE], squared_norm_b [MULT_MOD_Q_OPS_PER_CYCLE];
  logic squared_norm_valid_in, squared_norm_last, squared_norm_accept, squared_norm_reject;

  ntt_negative #(
                 .N(N)
               )ntt(
                 .clk(clk),
                 .rst_n(rst_n),
                 .mode(ntt_mode),
                 .start(ntt_start),
                 .input_polynomial(ntt_input),
                 .done(ntt_done),
                 .output_polynomial(ntt_output)
               );

  mod_mult_verify #(
                    .N(N),
                    .PARALLEL_OPS_COUNT(MULT_MOD_Q_OPS_PER_CYCLE)
                  )mod_mult (
                    .clk(clk),
                    .rst_n(rst_n),
                    .a(mod_mult_a),
                    .b(mod_mult_b),
                    .valid_in(mod_mult_valid_in),
                    .index_in(mod_mult_index_in),
                    .result(mod_mult_result),
                    .valid_out(mod_mult_valid_out),
                    .index_out(mod_mult_index_out),
                    .last(mod_mult_last)
                  );

  verify_compute_squared_norm #(
                                .N(8),
                                .PARALLEL_OPS_COUNT(SQUARED_NORM_OPS_PER_CYCLE)
                              )verify_compute_squared_norm (
                                .clk(clk),
                                .rst_n(rst_n),
                                .a(squared_norm_a),
                                .b(squared_norm_b),
                                .valid_in(squared_norm_valid_in),
                                .last(squared_norm_last),
                                .accept(squared_norm_accept),
                                .reject(squared_norm_reject)
                              );

  // Modulo 12289 subtraction
  function [14:0] mod_sub(input [14:0] a, b);
    begin
      if (a >= b)
        mod_sub = a - b;
      else
        mod_sub = a + 12289 - b;
    end
  endfunction

  typedef enum logic [3:0] {
            NTT_IDLE,
            START_NTT_PUBLIC_KEY, // Run NTT(public key)
            RUNNING_NTT_PUBLIC_KEY, // Wait for NTT(public key) to finish
            WAIT_FOR_DECOMPRESS, // Wait for decompression of signature to finish
            START_NTT_SIGNATURE, // Run NTT(decompressed signature)
            RUNNING_NTT_SIGNATURE, // Wait for NTT(decompressed signature) to finish
            MULT_MOD_Q, // Compute product = NTT(public key) * NTT(decompressed signature) mod q
            WAIT_FOR_MULT_MOD_Q, // Wait for the pipeline of MULT_MOD_Q to finish
            START_INTT, // Run INTT(product)
            RUNNING_INTT, // Wait for INTT to finish
            WAIT_FOR_HASH_TO_POINT, // Wait for hash_to_point to finish
            SUB_AND_NORMALIZE, // Compute htp_polynomial - product mod q and normalize to [ceil(-q/2), floor(q/2)]
            SQUARED_NORM, // Compute the squared norm ||(normalized result, decompressed signature)||^2
            FINISHED // Final state, here we accept the signature if there were no errors
          } ntt_state_t;
  ntt_state_t ntt_state, ntt_next_state;

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      ntt_state <= NTT_IDLE;
    else
      ntt_state <= ntt_next_state;
  end

  // State machine state changes
  always_comb begin
    ntt_next_state = ntt_state;

    case (ntt_state)
      NTT_IDLE: begin   // Waiting for the start signal
        if (start == 1'b1)
          ntt_next_state = START_NTT_PUBLIC_KEY;
      end
      START_NTT_PUBLIC_KEY: begin // Immediately go to next state
        ntt_next_state = RUNNING_NTT_PUBLIC_KEY;
      end
      RUNNING_NTT_PUBLIC_KEY: begin // Wait for NTT(public key) to finish and decompressed signature to be ready before moving to START_NTT_SIGNATURE
        if (ntt_done == 1'b1) begin
          // If there was an error decompressing the signature go straight to FINISHED
          if(signature_error == 1'b1)
            ntt_next_state = FINISHED;
          // Otherwise if decompression is done start NTT(decompressed signature)
          else if(decompression_done == 1'b1)
            ntt_next_state = START_NTT_SIGNATURE;
          // Otherwise wait for decompress to finish
          else
            ntt_next_state = WAIT_FOR_DECOMPRESS;
        end
      end
      WAIT_FOR_DECOMPRESS: begin // Wait for decompression to finish
        if (decompression_done == 1'b1)
          ntt_next_state = START_NTT_SIGNATURE;
      end
      START_NTT_SIGNATURE: begin // Immediately go to next state
        ntt_next_state = RUNNING_NTT_SIGNATURE;
      end
      RUNNING_NTT_SIGNATURE: begin // Wait for NTT(signature) to finish before moving to MULT_MOD_Q
        if (ntt_done == 1'b1)
          ntt_next_state = MULT_MOD_Q;
      end
      MULT_MOD_Q: begin // Send all data to mod_mult before moving to WAIT_FOR_MULT_MOD_Q
        // Check if we've sent all coefficients to mod_mult coefficients
        if (mult_mod_q_index == N - MULT_MOD_Q_OPS_PER_CYCLE)
          ntt_next_state = WAIT_FOR_MULT_MOD_Q;
      end
      WAIT_FOR_MULT_MOD_Q: begin // Wait for multiplication and modulo to finish before moving to START_INTT
        // Check if we've received all coefficients from mod_mult module
        if (mod_mult_last == 1'b1)
          ntt_next_state = START_INTT;
      end
      START_INTT: begin // Immediately go to next state
        ntt_next_state = RUNNING_INTT;
      end
      RUNNING_INTT: begin // Wait for INTT to finish before moving to WAIT_FOR_HASH_TO_POINT
        if (ntt_done == 1'b1) begin
          // If hash_to_point is finished go to SUB_AND_NORMALIZE, otherwise wait for it to finish
          if(htp_polynomial_valid == 1'b1)
            ntt_next_state =  SUB_AND_NORMALIZE;
          else
            ntt_next_state = WAIT_FOR_HASH_TO_POINT;
        end
      end
      WAIT_FOR_HASH_TO_POINT: begin // Wait for hash_to_point to finish before moving to SUB
        if(htp_polynomial_valid == 1'b1)
          ntt_next_state = SUB_AND_NORMALIZE;
      end
      SUB_AND_NORMALIZE: begin // Wait for subtraction and normalization to finish before moving to SQUARED_NORM
        // Check if we've processed all coefficients
        if (sub_and_normalize_index == N)
          ntt_next_state = SQUARED_NORM;
      end
      SQUARED_NORM: begin // Send all data to verify_compute_squared_norm before moving to FINISHED
        if(squared_norm_index == N)
          ntt_next_state = FINISHED;
      end
      FINISHED: begin // Wait for squared norm to finish and then accept or reject the signature
        ntt_next_state = FINISHED;
      end
      default: begin
        ntt_next_state = NTT_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    case (ntt_state)
      NTT_IDLE: begin
        ntt_mode <= 1'b0;
        ntt_start <= 1'b0;  // Doesn't really matter, we're not running NTT

        // Initialize mod_mult parameters (so they aren't undefined)
        for(int i = 0; i < MULT_MOD_Q_OPS_PER_CYCLE; i++) begin
          mod_mult_a[i] <= 0;
          mod_mult_b[i] <= 0;
        end
        mod_mult_valid_in <= 0;
        mod_mult_index_in <= 0;

        // Initialize squared norm parameters (so they aren't undefined)
        for(int i = 0; i < SQUARED_NORM_OPS_PER_CYCLE; i++) begin
          squared_norm_a[i] <= 0;
          squared_norm_b[i] <= 0;
        end
        squared_norm_valid_in <= 0;
        squared_norm_index <= 0;
        squared_norm_last <= 0;

        accept <= 1'b0;
        reject <= 1'b0;

        // Reset variables in case we run the module multiple times
        mult_mod_q_index <= 0;
        sub_and_normalize_index <= 0;
        squared_norm_index <= 0;
      end

      START_NTT_PUBLIC_KEY: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_input = public_key; // Must be non-blocking assignment, doesn't work otherwise
        ntt_start <= 1'b1;

        accept <= 1'b0;
        reject <= 1'b0;
      end

      WAIT_FOR_DECOMPRESS: begin
        accept <= 1'b0;
        reject <= 1'b0;
      end

      RUNNING_NTT_PUBLIC_KEY: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_input = public_key; // Must be non-blocking assignment, doesn't work otherwise
        ntt_start <= 1'b0;

        accept <= 1'b0;
        reject <= 1'b0;

        if (ntt_done == 1'b1) begin
          // Save output of NTT module for later use
          ntt_buffer1 <= ntt_output;
        end
      end

      START_NTT_SIGNATURE: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_input <= decompressed_polynomial;
        ntt_start <= 1'b1;

        accept <= 1'b0;
        reject <= 1'b0;
      end

      RUNNING_NTT_SIGNATURE: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_input <= decompressed_polynomial;
        ntt_start <= 1'b0;

        accept <= 1'b0;
        reject <= 1'b0;

        if (ntt_done == 1'b1) begin
          // Save output of NTT module for later use
          ntt_buffer2 <= ntt_output;
        end
      end

      MULT_MOD_Q: begin
        accept <= 1'b0;
        reject <= 1'b0;

        // Send data to mod_mult module
        for(int i = 0; i < MULT_MOD_Q_OPS_PER_CYCLE; i++) begin
          mod_mult_a[i] <= ntt_buffer1[mult_mod_q_index + i];
          mod_mult_b[i] <= ntt_buffer2[mult_mod_q_index + i];
        end
        mod_mult_index_in <= mult_mod_q_index;
        mod_mult_valid_in <= 1'b1;
        mult_mod_q_index <= mult_mod_q_index + MULT_MOD_Q_OPS_PER_CYCLE;

        // If output of mod_mult is valid we can save it
        if(mod_mult_valid_out == 1'b1)
          for(int i = 0; i < MULT_MOD_Q_OPS_PER_CYCLE; i++)
            ntt_buffer1[mod_mult_index_out + i] <= mod_mult_result[i];
      end

      WAIT_FOR_MULT_MOD_Q: begin
        accept <= 1'b0;
        reject <= 1'b0;

        for(int i = 0; i < MULT_MOD_Q_OPS_PER_CYCLE; i++) begin
          mod_mult_a[i] <= 0;
          mod_mult_b[i] <= 0;
        end
        mod_mult_valid_in <= 0;
        mod_mult_index_in <= 0;

        // If output of mod_mult is valid we can save it
        if(mod_mult_valid_out == 1'b1)
          for(int i = 0; i < MULT_MOD_Q_OPS_PER_CYCLE; i++)
            ntt_buffer1[mod_mult_index_out + i] <= mod_mult_result[i];
      end

      START_INTT: begin
        ntt_mode <= 1'b1;  // INTT
        ntt_input <= ntt_buffer1;
        ntt_start <= 1'b1;

        accept <= 1'b0;
        reject <= 1'b0;
      end

      RUNNING_INTT: begin
        ntt_mode <= 1'b1;  // INTT
        ntt_input <= ntt_buffer1;
        ntt_start <= 1'b0;

        accept <= 1'b0;
        reject <= 1'b0;

        if (ntt_done == 1'b1) begin
          // Save output of NTT module for later use
          ntt_buffer1 <= ntt_output;
        end
      end

      WAIT_FOR_HASH_TO_POINT: begin
        accept <= 1'b0;
        reject <= 1'b0;
      end

      SUB_AND_NORMALIZE: begin
        accept <= 1'b0;
        reject <= 1'b0;

        // Compute SUB_AND_NORMALIZE_OPS_PER_CYCLE coefficients per clock cycle
        for (int i = 0; i < SUB_AND_NORMALIZE_OPS_PER_CYCLE; i = i + 1) begin

          logic [14:0] temp;

          // Subtract htp_polynomial from INTT(product)
          temp = mod_sub(htp_polynomial[i+sub_and_normalize_index], ntt_buffer1[i+sub_and_normalize_index]);

          // Normalize to [-q/2, q/2]
          if (temp > 6144)
            ntt_buffer1[i+sub_and_normalize_index] <= temp - 12289;
          else
            ntt_buffer1[i+sub_and_normalize_index] <= temp;
        end

        sub_and_normalize_index <= sub_and_normalize_index + SUB_AND_NORMALIZE_OPS_PER_CYCLE;
      end

      SQUARED_NORM: begin
        accept <= 1'b0;
        reject <= 1'b0;

        // Send data to verify_compute_squared_norm module
        for(int i = 0; i < SQUARED_NORM_OPS_PER_CYCLE; i++) begin
          squared_norm_a[i] <= ntt_buffer1[squared_norm_index + i];
          squared_norm_b[i] <= decompressed_polynomial[squared_norm_index + i];
        end
        squared_norm_valid_in <= 1'b1;
        squared_norm_index <= squared_norm_index + SQUARED_NORM_OPS_PER_CYCLE;
        if(squared_norm_index == N)
          squared_norm_last <= 1'b1;
        else
          squared_norm_last <= 1'b0;
      end

      FINISHED: begin

        // Wait for squared norm pipeline to finish
        if(squared_norm_accept == 1'b1 || squared_norm_reject == 1'b1) begin
          if (signature_error == 1'b0 && squared_norm_reject == 1'b0 && squared_norm_accept == 1'b1) begin
            accept <= 1'b1;
            reject <= 1'b0;
          end
          else begin
            accept <= 1'b0;
            reject <= 1'b1;
          end
        end
      end
    endcase
  end

  /////////////////////////// End NTT and general control logic ////////

endmodule
