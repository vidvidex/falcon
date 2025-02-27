`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Verifies that "signature" is a correct signature for "message" using the public key defined as (r, s)
//
//////////////////////////////////////////////////////////////////////////////////

module verify#(
    parameter int N,
    parameter int SIGNATURE_LENGTH,
    parameter int MULT_MOD_Q_OPS_PER_CYCLE = 4, //! The number of operations per cycle for the MULT_MOD_Q module. N should be divisible by this number.
    parameter int SUB_AND_NORMALIZE_OPS_PER_CYCLE = 4, //! The number of operations per cycle for the SUB_AND_NORMALIZE module. N should be divisible by this number.
    parameter int SQUARED_NORM_OPS_PER_CYCLE = 4 //! The number of operations per cycle for the SQUARED_NORM module. N should be divisible by this number.
  )(
    input logic clk,
    input logic rst_n,

    input logic start, //! Start signal for the module (currently only starts NTT, everything else runs automatically when the data is valid)

    input logic [14:0] public_key[0:N-1], //! Public key in coefficient form
    input logic public_key_valid, //! Is public key valid

    input logic [15:0] message_len_bytes, //! Length of the message in bytes.
    input logic [63:0] message, //! every clock cycle the next 64 bits of the message should be provided
    input logic message_valid, //! Is message valid
    output logic message_ready, //! Is ready to receive the next message

    input logic [63:0] signature_salt, //! Salt from the signature
    input logic signature_salt_valid,  //! Is signature_salt valid
    output logic signature_salt_ready, //! Is ready to receive the next signature_salt block
    input logic [63:0] signature_value,
    input logic [6:0] signature_value_valid, //! Is signature_value valid, bitwise from the left
    output logic signature_value_ready, //! Is ready to receive the next signature_value block

    output logic accept, //! Set to true if signature is valid
    output logic reject //! Set to true if signature is invalid
  );

  /////////////////////////// Start hash_to_point ///////////////////////////

  logic [15:0] htp_message_len_bytes; //! Length of the input to hash_to_point module
  logic [63:0] htp_input_message; //! Input block to hash_to_point module
  logic htp_message_valid  ; //! Is input block to hash_to_point module valid
  logic htp_ready; //! Is hash_to_point module ready to receive the next input block
  logic [14:0] htp_polynomial[0:N-1]; // Output polynomial from hash_to_point
  logic htp_polynomial_valid; // Is htp_polynomial from hash_to_point valid

  hash_to_point #(
                  .N(N)
                )hash_to_point(
                  .clk(clk),
                  .rst_n(rst_n),
                  .message_len_bytes(htp_message_len_bytes),
                  .message(htp_input_message),
                  .message_valid(htp_message_valid),
                  .ready(htp_ready),
                  .polynomial(htp_polynomial),
                  .polynomial_valid(htp_polynomial_valid)
                );

  // Input message to hash_to_point is the concatenation of the message and the salt. Salt is 40B long.
  // First we send the salt, then the message. As long as the salt is valid we keep sending it and then
  // we start sending the message. We set message_ready and signature_salt_ready to "ready" signal from hash_to_point
  // depending on what we're currently sending.
  assign htp_message_len_bytes = message_len_bytes+40;
  assign htp_input_message = signature_salt_valid ? signature_salt : message;
  assign htp_message_valid = signature_salt_valid ? signature_salt_valid : message_valid;
  assign message_ready = signature_salt_valid ? 0 : htp_ready;
  assign signature_salt_ready = signature_salt_valid ? htp_ready : 0;

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
  logic [7:0] compressed_signature_buffer_valid; //! Number of valid bits in compressed_signature_buffer. Only leftmost bits are valid.

  logic [14:0] coefficient; //! Decompressed coefficient
  logic [14:0] decompressed_coefficients [0:N-1];
  logic [5:0] compressed_coef_length; //! Number of bits that were used to compress the coefficient
  logic coefficient_valid; //! Is coefficient valid
  logic signature_error=0; //! Set to true if the signature is invalid
  logic squared_norm_error=0; //! Set to true if the squared norm is larger than the bound^2
  logic decompression_done; //! Set to true if the decompression is done
  logic [$clog2(N)-1:0] coefficient_index = 0; //! Index of the coefficient that is currently being decompressed

  decompress #(
               .N(N),
               .SIGNATURE_LENGTH(SIGNATURE_LENGTH)
             ) decompress(
               .clk(clk),
               .rst_n(rst_n),
               .compressed_signature(compressed_signature_buffer[3*64-1 -: 105]), // Provide top 105 bits of the buffer to decompress module
               .compressed_signature_valid_bits(compressed_signature_buffer_valid),
               .expected_signature_length_bytes(SIGNATURE_LENGTH),
               .coefficient(coefficient),
               .coefficient_valid(coefficient_valid),
               .compressed_coef_length(compressed_coef_length),
               .signature_error(signature_error),
               .decompression_done(decompression_done)
             );

  always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
      compressed_signature_buffer <= 0;
      compressed_signature_buffer_valid <= 0;
      signature_value_ready <= 0;
    end
    else begin

      // Load new block of signature data if we have the space for it in the buffer.
      // Check if signature data has at least one valid bit and if we have 64 bits of space in the buffer (total size is 3*64 bits)
      if (signature_value_valid > 0 && compressed_signature_buffer_valid < 128) begin
        compressed_signature_buffer[3*64-1-compressed_signature_buffer_valid -: 64] = signature_value;
        compressed_signature_buffer_valid = compressed_signature_buffer_valid + signature_value_valid;

        signature_value_ready <= 1'b1; // We can receive the next 64 bits of the signature
      end
      else
        signature_value_ready <= 0; // We can't receive the next 64 bits of the signature

      // If decompression module produced a valid coefficient we have to shift the buffer to the left by "compressed_coef_length" bits
      // to provide the next compressed coefficient to the decompression module. Here we have to use blocking assignments to ensure this block
      // is executed after loading the new block of signature data above.
      // We also need to save the coefficient to the coefficients array.
      if (coefficient_valid == 1'b1) begin
        compressed_signature_buffer = compressed_signature_buffer << compressed_coef_length;
        compressed_signature_buffer_valid = compressed_signature_buffer_valid - compressed_coef_length;

        decompressed_coefficients[coefficient_index] = coefficient;
        coefficient_index = coefficient_index + 1;
      end
    end
  end

  /////////////////////////// End decompress ///////////////////////////

  /////////////////////////// Start NTT and general control logic //////

  logic [14:0] ntt_input[0:N-1];
  logic [14:0] ntt_output[0:N-1];

  logic [14:0] ntt_buffer1[0:N-1]; // Buffer for NTT module, here we store the result of NTT(public key), NTT(public key) * NTT(decompressed signature) = product, INTT(product), htp_polynomial - INTT(product)
  logic [14:0] ntt_buffer2[0:N-1]; // Buffer for NTT module, here we store the result of NTT(decompressed signature)

  logic ntt_start; //! Start signal for NTT module
  logic ntt_mode; //! 0 - NTT, 1 - INTT
  logic ntt_done; //! Set high when NTT module is done and ntt_output is valid
  logic [$clog2(N):0] mult_mod_q_index=0, sub_and_normalize_index=0, squared_norm_index=0; // Indices used for iterating over the buffer arrays. Need to be large enough to store N.

  // The size is selected so that when we iteratively compute it we can check if it's larger than the bound^2 on each iteration, since 27 bits is enough for the value at previous iteration
  // to be 70265242-1 and to this we add (-6145)^2 (this is the worst case scenario)
  logic [26:0] squared_norm=0;

  logic [26:0] bound2; // The bound squared
  generate
    if (N == 8)
      assign bound2 = 428865; // floor(bound^2) = 428865
    else if (N == 512)
      assign bound2 = 34034726; // floor(bound^2) = 34034726
    else if (N == 1024)
      assign bound2 = 70265242; // floor(bound^2) = 70265242
    else
      $error("N must be 8, 512 or 1024");
  endgenerate

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

  // Modulo 12289 multiplication
  function [14:0] mod_mult(input [14:0] a, b);
    logic [29:0] temp;
    begin
      temp = a * b;
      mod_mult = temp % 12289;
    end
  endfunction

  // Modulo 12289 subtraction
  function [14:0] mod_sub(input [14:0] a, b);
    begin
      if (a >= b)
        mod_sub = a - b;
      else
        mod_sub = a + 12289 - b;
    end
  endfunction

  typedef enum {
            IDLE,
            START_NTT_PUBLIC_KEY, // Run NTT(public key)
            RUNNING_NTT_PUBLIC_KEY, // Wait for NTT(public key) to finish
            START_NTT_SIGNATURE, // Run NTT(decompressed signature)
            RUNNING_NTT_SIGNATURE, // Wait for NTT(decompressed signature) to finish
            MULT_MOD_Q, // Compute product = NTT(public key) * NTT(decompressed signature) mod q
            START_INTT, // Run INTT(product)
            RUNNING_INTT, // Wait for INTT to finish
            WAIT_FOR_HASH_TO_POINT, // Wait for hash_to_point to finish
            SUB_AND_NORMALIZE, // Compute htp_polynomial - product mod q and normalize to [ceil(-q/2), floor(q/2)]
            SQUARED_NORM, // Compute the squared norm ||(normalized result, decompressed signature)||^2
            FINISHED // Final state, here we accept the signature if there were no errors
          } state_t;
  state_t ntt_state, ntt_next_state;

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      ntt_state <= IDLE;
    else
      ntt_state <= ntt_next_state;
  end

  // State machine state changes
  always_comb begin
    case (ntt_state)
      IDLE: begin   // Waiting for the start signal

        if (start == 1'b1)
          ntt_next_state = START_NTT_PUBLIC_KEY;

      end
      START_NTT_PUBLIC_KEY: begin // Immediately go to next state

        ntt_next_state = RUNNING_NTT_PUBLIC_KEY;

      end
      RUNNING_NTT_PUBLIC_KEY: begin // Wait for NTT(public key) to finish and decompressed signature to be ready before moving to START_NTT_SIGNATURE
        if (ntt_done == 1'b1) begin
          // Save output of NTT module for later use
          ntt_buffer1 = ntt_output;

          // If both NTT(public key) and decompression are done, we can start NTT(decompressed signature)
          if(decompression_done == 1'b1)
            ntt_next_state = START_NTT_SIGNATURE;
        end
      end
      START_NTT_SIGNATURE: begin // Immediately go to next state

        ntt_next_state = RUNNING_NTT_SIGNATURE;

      end
      RUNNING_NTT_SIGNATURE: begin // Wait for NTT(signature) to finish before moving to MULT_MOD_Q
        if (ntt_done == 1'b1) begin
          // Save output of NTT module for later use
          ntt_buffer2 = ntt_output;

          ntt_next_state = MULT_MOD_Q;
        end
      end
      MULT_MOD_Q: begin // Wait for multiplication and modulo to finish before moving to START_INTT

        // Check if we've processed all coefficients
        if (mult_mod_q_index == N)
          ntt_next_state = START_INTT;

      end
      START_INTT: begin // Immediately go to next state

        ntt_next_state = RUNNING_INTT;

      end
      RUNNING_INTT: begin // Wait for INTT to finish before moving to WAIT_FOR_HASH_TO_POINT
        if (ntt_done == 1'b1) begin
          // Save output of NTT module for later use
          ntt_buffer1 = ntt_output;

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

      SQUARED_NORM: begin // Wait for squared norm to finish before moving to IDLE

        // Check if we've processed all coefficients
        if(squared_norm_index == N)
          ntt_next_state = FINISHED;
      end

      FINISHED: begin // Wait here forever

        ntt_next_state = FINISHED;

      end
      default: begin
        ntt_next_state = IDLE;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    case (ntt_state)
      IDLE: begin
        ntt_mode <= 1'b0;
        ntt_start <= 1'b0;  // Doesn't really matter, we're not running NTT

        accept <= 1'b0;
        reject <= 1'b0;
      end

      START_NTT_PUBLIC_KEY: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_input = public_key; // Must be non-blocking assignment, doesn't work otherwise
        ntt_start <= 1'b1;

        accept <= 1'b0;
        reject <= 1'b0;
      end

      RUNNING_NTT_PUBLIC_KEY: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_input = public_key; // Must be non-blocking assignment, doesn't work otherwise
        ntt_start <= 1'b0;

        accept <= 1'b0;
        reject <= 1'b0;
      end

      START_NTT_SIGNATURE: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_input <= decompressed_coefficients;
        ntt_start <= 1'b1;

        accept <= 1'b0;
        reject <= 1'b0;
      end

      RUNNING_NTT_SIGNATURE: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_input <= decompressed_coefficients;
        ntt_start <= 1'b0;

        accept <= 1'b0;
        reject <= 1'b0;
      end

      MULT_MOD_Q: begin
        ntt_mode <= 1'b0;  // Doesn't really matter, we're not running NTT
        ntt_start <= 1'b0;

        accept <= 1'b0;
        reject <= 1'b0;

        // Compute MULT_MOD_Q_OPS_PER_CYCLE coefficients per clock cycle
        for (int i = mult_mod_q_index; i < mult_mod_q_index + MULT_MOD_Q_OPS_PER_CYCLE; i = i + 1) begin
          ntt_buffer1[i] <= mod_mult(ntt_buffer1[i], ntt_buffer2[i]);
        end

        mult_mod_q_index <= mult_mod_q_index + MULT_MOD_Q_OPS_PER_CYCLE;

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
      end

      WAIT_FOR_HASH_TO_POINT: begin
        ntt_mode <= 1'b0;  // Doesn't really matter, we're not running NTT
        ntt_start <= 1'b0;

        accept <= 1'b0;
        reject <= 1'b0;
      end

      SUB_AND_NORMALIZE: begin
        ntt_mode <= 1'b0;  // Doesn't really matter, we're not running NTT
        ntt_start <= 1'b0;

        accept <= 1'b0;
        reject <= 1'b0;

        // Compute SUB_AND_NORMALIZE_OPS_PER_CYCLE coefficients per clock cycle
        for (int i = sub_and_normalize_index; i < sub_and_normalize_index + SUB_AND_NORMALIZE_OPS_PER_CYCLE; i = i + 1) begin

          logic [14:0] temp;

          // Subtract htp_polynomial from INTT(product)
          temp = mod_sub(htp_polynomial[i], ntt_buffer1[i]);

          // Normalize to [-q/2, q/2]
          if (temp > 6144)
            ntt_buffer1[i] <= temp - 12289;
          else
            ntt_buffer1[i] <= temp;
        end

        sub_and_normalize_index <= sub_and_normalize_index + SUB_AND_NORMALIZE_OPS_PER_CYCLE;
      end

      SQUARED_NORM: begin
        ntt_mode <= 1'b0;  // Doesn't really matter, we're not running NTT
        ntt_start <= 1'b0;

        accept <= 1'b0;
        reject <= 1'b0;

        // Compute SQUARED_NORM_OPS_PER_CYCLE coefficients per clock cycle
        for (int i = squared_norm_index; i < squared_norm_index + SQUARED_NORM_OPS_PER_CYCLE; i = i + 1) begin

          // squared_norm += normalized^2 + hashed_message^2
          squared_norm = squared_norm + ntt_buffer1[i] * ntt_buffer1[i] + htp_polynomial[i] * htp_polynomial[i];

          // Check if the squared norm is larger than the bound^2
          if (squared_norm > bound2)
            squared_norm_error <= 1'b1;
        end

        squared_norm_index <= squared_norm_index + SQUARED_NORM_OPS_PER_CYCLE;
      end

      FINISHED: begin
        ntt_mode <= 1'b0;  // Doesn't really matter, we're not running NTT
        ntt_start <= 1'b0;

        if (signature_error == 1'b0 && squared_norm_error == 1'b0) begin
          accept <= 1'b1;
          reject <= 1'b0;
        end
        else begin
          accept <= 1'b0;
          reject <= 1'b1;
        end
      end
    endcase
  end


  /////////////////////////// End NTT and general control logic ////////

endmodule
