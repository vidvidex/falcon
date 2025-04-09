`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Verifies that "signature" is a correct signature for "message" using the "public_key"
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
    parameter int MULT_MOD_Q_OPS_PER_CYCLE = 1, //! The number of operations per cycle for the MULT_MOD_Q module. N should be divisible by this number.
    parameter int SUB_AND_NORMALIZE_OPS_PER_CYCLE = 1, //! The number of operations per cycle for the SUB_AND_NORMALIZE module. N should be divisible by this number.
    parameter int SQUARED_NORM_OPS_PER_CYCLE = 1 //! The number of operations per cycle for the SQUARED_NORM module. N should be divisible by this number.
  )(
    input logic clk,
    input logic rst_n,

    input logic start, //! Start signal for the module

    input logic signed [14:0] public_key_element, //! Public key element in coefficient form
    input logic public_key_valid, //! Is public key block valid
    output logic public_key_ready, //! Is ready to receive the next public key block

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

  logic signed [14:0] htp_coefficient;
  logic [$clog2(N)-1:0] htp_coefficient_index;
  logic htp_coefficient_valid;

  logic htp_done; // Is hash_to_point done
  logic [15:0] htp_message_len_bytes;

  hash_to_point #(
                  .N(N)
                )hash_to_point(
                  .clk(clk),
                  .rst_n(rst_n),
                  .start(start),
                  .message_len_bytes(htp_message_len_bytes),
                  .message(message),
                  .message_valid(message_valid),
                  .message_last(message_last),
                  .ready(message_ready),
                  .coefficient(htp_coefficient),
                  .coefficient_valid(htp_coefficient_valid),
                  .coefficient_index(htp_coefficient_index),
                  .done(htp_done)
                );

  assign htp_message_len_bytes = message_len_bytes + 40; // Add 40 bytes of salt to the message length

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

  logic signed [14:0] decompressed_coefficient;
  logic [$clog2(N)-1:0] decompressed_coefficient_index;
  logic decompressed_coefficient_valid;
  logic [6:0] shift_by; //! Number of bits that were used to compress the coefficient, we need to shift the buffer by this amount
  logic signature_error; //! Set to true if the signature is invalid
  logic decompression_done; //! Set to true if the decompression is done
  logic decompress_ready;

  decompress #(
               .N(N),
               .SLEN(8 * SBYTELEN - 328)  // 328 = 8 * (40 + 1), 40 bytes of salt and 1 byte of header
             ) decompress(
               .clk(clk),
               .rst_n(rst_n),
               .start(start),
               .compressed_signature(compressed_signature_buffer[3*64-1 -: 105]), // Provide top 105 bits of the buffer to decompress module
               .valid_bits(compressed_signature_buffer_valid),
               .ready(decompress_ready),
               .shift_by(shift_by),
               .coefficient(decompressed_coefficient),
               .coefficient_valid(decompressed_coefficient_valid),
               .coefficient_index(decompressed_coefficient_index),
               .decompression_done(decompression_done),
               .signature_error(signature_error)
             );

  typedef enum logic [2:0] {
            DECOMPRESS_IDLE, // Waiting for the start signal
            DECOMPRESSING, // Decompressing coefficients
            DECOMPRESSION_DONE // Decompression is done
          } decompress_state_t;
  decompress_state_t decompress_state, decompress_next_state;

  // State machine state changes
  always_comb begin
    decompress_next_state = decompress_state;

    case (decompress_state)
      DECOMPRESS_IDLE: begin   // Waiting for the start signal
        if (start == 1'b1)
          decompress_next_state = DECOMPRESSING;
      end
      DECOMPRESSING: begin  // Go to DECOMPRESSION_DONE if we're done
        if(decompression_done == 1'b1 || signature_error == 1'b1)
          decompress_next_state = DECOMPRESSION_DONE;
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
        compressed_signature_buffer = 0;
        compressed_signature_buffer_valid = 0;
      end
      DECOMPRESSING: begin

        // Load new block of signature data
        if(signature_valid > 0) begin
          compressed_signature_buffer[3*64-1-compressed_signature_buffer_valid -: 64] = signature;
          compressed_signature_buffer_valid = compressed_signature_buffer_valid + signature_valid;
        end

        // We have to shift the buffer to the left by "shift_by" bits to provide the next compressed coefficient to the decompression module.
        compressed_signature_buffer = compressed_signature_buffer << shift_by;
        compressed_signature_buffer_valid = compressed_signature_buffer_valid - shift_by;
      end
      DECOMPRESSION_DONE: begin
      end
    endcase
  end

  assign signature_ready = decompress_ready && compressed_signature_buffer_valid < 2*64;

  /////////////////////////// End decompress ///////////////////////////

  /////////////////////////// Start NTT and general control logic //////

  logic [$clog2(N)-1:0] public_key_element_index; //! Index of the public key element

  logic ntt_start; //! Start signal for NTT module
  logic ntt_mode; //! 0 - NTT, 1 - INTT
  logic ntt_done; //! Set high when NTT module is done and ntt_output is valid
  logic [$clog2(N):0] mult_mod_q_index, sub_and_normalize_index, squared_norm_index; //! Indices used for iterating over the buffer arrays. Need to be large enough to store N.

  logic signed [14:0] mod_mult_a [MULT_MOD_Q_OPS_PER_CYCLE], mod_mult_b [MULT_MOD_Q_OPS_PER_CYCLE], mod_mult_result [MULT_MOD_Q_OPS_PER_CYCLE];
  logic mod_mult_valid_in, mod_mult_valid_out, mod_mult_last;
  logic [$clog2(N):0] mod_mult_index_in, mod_mult_index_out;

  logic signed [14:0] sub_and_norm_a [SUB_AND_NORMALIZE_OPS_PER_CYCLE], sub_and_norm_b [SUB_AND_NORMALIZE_OPS_PER_CYCLE], sub_and_norm_result [SUB_AND_NORMALIZE_OPS_PER_CYCLE];
  logic sub_and_norm_valid_in, sub_and_norm_valid_out, sub_and_norm_last;
  logic [$clog2(N):0] sub_and_norm_index_in, sub_and_norm_index_out;

  logic signed [14:0] squared_norm_a [SQUARED_NORM_OPS_PER_CYCLE], squared_norm_b [SQUARED_NORM_OPS_PER_CYCLE];
  logic squared_norm_valid_in, squared_norm_last, squared_norm_accept, squared_norm_reject;

  // BRAM1
  logic [$clog2(N-1)-1:0] bram1_addr_a, bram1_addr_b;
  logic signed [14:0] bram1_data_in_a, bram1_data_in_b, bram1_data_out_a, bram1_data_out_b;
  logic bram1_we_a, bram1_we_b;
  bram #(
         .RAM_DEPTH(N)
       ) bram1 (
         .clk(clk),

         .addr_a(bram1_addr_a),
         .data_in_a(bram1_data_in_a),
         .we_a(bram1_we_a),
         .data_out_a(bram1_data_out_a),

         .addr_b(bram1_addr_b),
         .data_in_b(bram1_data_in_b),
         .we_b(bram1_we_b),
         .data_out_b(bram1_data_out_b)
       );

  // BRAM2
  logic [$clog2(N-1)-1:0] bram2_addr_a, bram2_addr_b;
  logic signed [14:0] bram2_data_in_a, bram2_data_in_b, bram2_data_out_a, bram2_data_out_b;
  logic bram2_we_a, bram2_we_b;
  bram #(
         .RAM_DEPTH(N)
       ) bram2 (
         .clk(clk),

         .addr_a(bram2_addr_a),
         .data_in_a(bram2_data_in_a),
         .we_a(bram2_we_a),
         .data_out_a(bram2_data_out_a),

         .addr_b(bram2_addr_b),
         .data_in_b(bram2_data_in_b),
         .we_b(bram2_we_b),
         .data_out_b(bram2_data_out_b)
       );

  // BRAM3
  logic [$clog2(N-1)-1:0] bram3_addr_a, bram3_addr_b;
  logic signed [14:0] bram3_data_in_a, bram3_data_in_b, bram3_data_out_a, bram3_data_out_b;
  logic bram3_we_a, bram3_we_b;
  bram #(
         .RAM_DEPTH(N)
       ) bram3 (
         .clk(clk),

         .addr_a(bram3_addr_a),
         .data_in_a(bram3_data_in_a),
         .we_a(bram3_we_a),
         .data_out_a(bram3_data_out_a),

         .addr_b(bram3_addr_b),
         .data_in_b(bram3_data_in_b),
         .we_b(bram3_we_b),
         .data_out_b(bram3_data_out_b)
       );

  // BRAM4
  logic [$clog2(N-1)-1:0] bram4_addr_a, bram4_addr_b;
  logic signed [14:0] bram4_data_in_a, bram4_data_in_b, bram4_data_out_a, bram4_data_out_b;
  logic bram4_we_a, bram4_we_b;
  bram #(
         .RAM_DEPTH(N)
       ) bram4 (
         .clk(clk),

         .addr_a(bram4_addr_a),
         .data_in_a(bram4_data_in_a),
         .we_a(bram4_we_a),
         .data_out_a(bram4_data_out_a),

         .addr_b(bram4_addr_b),
         .data_in_b(bram4_data_in_b),
         .we_b(bram4_we_b),
         .data_out_b(bram4_data_out_b)
       );

  logic [$clog2(N-1)-1:0] ntt_input_addr1, ntt_input_addr2, ntt_output_addr1, ntt_output_addr2;
  logic signed [14:0] ntt_input_data1, ntt_input_data2, ntt_output_data1, ntt_output_data2;
  logic ntt_output_we1, ntt_output_we2;
  ntt_negative #(
                 .N(N)
               )ntt(
                 .clk(clk),
                 .rst_n(rst_n),
                 .mode(ntt_mode),
                 .start(ntt_start),

                 .input_bram_addr1(ntt_input_addr1),
                 .input_bram_addr2(ntt_input_addr2),
                 .input_bram_data1(ntt_input_data1),
                 .input_bram_data2(ntt_input_data2),

                 .output_bram_addr1(ntt_output_addr1),
                 .output_bram_addr2(ntt_output_addr2),
                 .output_bram_data1(ntt_output_data1),
                 .output_bram_data2(ntt_output_data2),
                 .output_bram_we1(ntt_output_we1),
                 .output_bram_we2(ntt_output_we2),

                 .done(ntt_done)
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

  verify_sub_and_normalize #(
                             .N(N),
                             .PARALLEL_OPS_COUNT(SUB_AND_NORMALIZE_OPS_PER_CYCLE)
                           )verify_sub_and_normalize (
                             .clk(clk),
                             .rst_n(rst_n),
                             .a(sub_and_norm_a),
                             .b(sub_and_norm_b),
                             .valid_in(sub_and_norm_valid_in),
                             .index_in(sub_and_norm_index_in),
                             .result(sub_and_norm_result),
                             .valid_out(sub_and_norm_valid_out),
                             .index_out(sub_and_norm_index_out),
                             .last(sub_and_norm_last)
                           );

  verify_compute_squared_norm #(
                                .N(N),
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

  typedef enum logic [4:0] {
            NTT_IDLE,
            RECEIVE_PUBLIC_KEY,  // Receive public key from parent. We write it into the NTT input buffer
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
            WAIT_FOR_SUB_AND_NORMALIZE, // Wait for the pipeline of SUB_AND_NORMALIZE to finish
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

  // BRAM signal routing
  always_comb begin

    bram1_we_a = 0;
    bram1_we_b = 0;
    bram2_we_a = 0;
    bram2_we_b = 0;
    bram3_we_a = 0;
    bram3_we_b = 0;
    bram4_we_a = 0;
    bram4_we_b = 0;

    // In RECEIVE_PUBLIC_KEY we are storing public key in BRAM1 port A
    if(ntt_state == RECEIVE_PUBLIC_KEY) begin
      bram1_addr_a = public_key_element_index;
      bram1_data_in_a = public_key_element;
      bram1_we_a = 1'b1;
    end

    // decompress is permanently connected to BRAM4 port A
    bram4_addr_a = decompressed_coefficient_index;
    bram4_data_in_a = decompressed_coefficient;
    bram4_we_a = decompressed_coefficient_valid;

    // hash_to_point is permanently connected to BRAM3 port A
    bram3_addr_a = htp_coefficient_index;
    bram3_data_in_a = htp_coefficient;
    bram3_we_a = htp_coefficient_valid;

    // In START_NTT_PUBLIC_KEY, RUNNING_NTT_PUBLIC_KEY AND START_INTT, RUNNING_INTT we are connecting ntt_input to BRAM1 and ntt_output to BRAM2
    if(ntt_state == START_NTT_PUBLIC_KEY || ntt_state == RUNNING_NTT_PUBLIC_KEY || ntt_state == START_INTT || ntt_state == RUNNING_INTT) begin
      bram1_addr_a = ntt_input_addr1;
      ntt_input_data1 = bram1_data_out_a;
      bram1_addr_b = ntt_input_addr2;
      ntt_input_data2 = bram1_data_out_b;

      bram2_addr_a = ntt_output_addr1;
      bram2_data_in_a = ntt_output_data1;
      bram2_we_a = ntt_output_we1;
      bram2_addr_b = ntt_output_addr2;
      bram2_data_in_b = ntt_output_data2;
      bram2_we_b = ntt_output_we2;
    end

    // In START_NTT_SIGNATURE and RUNNING_NTT_SIGNATURE we are connecting ntt_input to BRAM4 and ntt_output to BRAM1
    if(ntt_state == START_NTT_SIGNATURE || ntt_state == RUNNING_NTT_SIGNATURE) begin
      bram4_addr_a = ntt_input_addr1;
      ntt_input_data1 = bram4_data_out_a;
      bram4_addr_b = ntt_input_addr2;
      ntt_input_data2 = bram4_data_out_b;

      bram1_addr_a = ntt_output_addr1;
      bram1_data_in_a = ntt_output_data1;
      bram1_we_a = ntt_output_we1;
      bram1_addr_b = ntt_output_addr2;
      bram1_data_in_b = ntt_output_data2;
      bram1_we_b = ntt_output_we2;
    end

    // In MULT_MOD_Q and WAIT_FOR_MULT_MOD_Q we are reading from BRAM1 port A and BRAM2 port A and writing to BRAM1 port B
    if(ntt_state == MULT_MOD_Q || ntt_state == WAIT_FOR_MULT_MOD_Q) begin
      bram1_addr_a = mult_mod_q_index;
      bram2_addr_a = mult_mod_q_index;
      mod_mult_a[0] <= bram1_data_out_a;
      mod_mult_b[0] <= bram2_data_out_a;

      bram1_we_b = mod_mult_valid_out;
      bram1_data_in_b = mod_mult_result[0];
      bram1_addr_b = mod_mult_index_out;
    end

    // In SUB_AND_NORMALIZE and WAIT_FOR_SUB_AND_NORMALIZE we are reading from BRAM2 port A and BRAM 3 port B and writing to BRAM1 port A
    if(ntt_state == SUB_AND_NORMALIZE || ntt_state == WAIT_FOR_SUB_AND_NORMALIZE) begin
      bram2_addr_a = sub_and_normalize_index;
      bram3_addr_b = sub_and_normalize_index;
      sub_and_norm_a[0] <= bram2_data_out_a;
      sub_and_norm_b[0] <= bram3_data_out_b;

      bram1_we_a = sub_and_norm_valid_out;
      bram1_data_in_a = sub_and_norm_result[0];
      bram1_addr_a = sub_and_norm_index_out;
    end

    // In SQUARED_NORM we are reading from BRAM1 port A and BRAM4 port B
    if(ntt_state == SQUARED_NORM) begin
      bram1_addr_a = squared_norm_index;
      bram4_addr_b = squared_norm_index;
      squared_norm_a[0] <= bram1_data_out_a;
      squared_norm_b[0] <= bram4_data_out_b;
    end
  end

  // BRAM has delay of 1 cycle so we have to delay signals that are not originating from BRAM but need to be in sync with those that are
  // always_ff @(posedge clk) begin
  //   if(rst_n == 1'b0) begin
  //   end
  //   else begin
  //   end
  // end

  // State machine state changes
  always_comb begin
    ntt_next_state = ntt_state;

    case (ntt_state)
      NTT_IDLE: begin   // Waiting for the start signal
        if (start == 1'b1)
          ntt_next_state = RECEIVE_PUBLIC_KEY;
      end
      RECEIVE_PUBLIC_KEY: begin // Wait to receive the entire public key before moving to START_NTT_PUBLIC_KEY
        if (public_key_element_index == N - 1)
          ntt_next_state = START_NTT_PUBLIC_KEY;
      end
      START_NTT_PUBLIC_KEY: begin // Immediately go to next state
        ntt_next_state = RUNNING_NTT_PUBLIC_KEY;
      end
      RUNNING_NTT_PUBLIC_KEY: begin // Wait for NTT(public key) to finish and decompressed signature to be ready before moving to START_NTT_SIGNATURE
        if(signature_error == 1'b1) // If there was an error decompressing the signature go straight to FINISHED
          ntt_next_state = FINISHED;

        if (ntt_done == 1'b1) begin
          if(decompression_done == 1'b1)
            ntt_next_state = START_NTT_SIGNATURE; // If decompression is done start NTT(decompressed signature)
          else
            ntt_next_state = WAIT_FOR_DECOMPRESS; // Otherwise wait for decompress to finish
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
          if(htp_done == 1'b1)
            ntt_next_state =  SUB_AND_NORMALIZE;
          else
            ntt_next_state = WAIT_FOR_HASH_TO_POINT;
        end
      end
      WAIT_FOR_HASH_TO_POINT: begin // Wait for hash_to_point to finish before moving to SUB
        if(htp_done == 1'b1)
          ntt_next_state = SUB_AND_NORMALIZE;
      end
      SUB_AND_NORMALIZE: begin // Send all data to verify_sub_and_normalize before moving to WAIT_FOR_SUB_AND_NORMALIZE
        if (sub_and_normalize_index == N - SUB_AND_NORMALIZE_OPS_PER_CYCLE)
          ntt_next_state = WAIT_FOR_SUB_AND_NORMALIZE;
      end
      WAIT_FOR_SUB_AND_NORMALIZE: begin // Wait for sub_and_normalize to finish before moving to SQUARED_NORM
        if (sub_and_norm_last == 1'b1)
          ntt_next_state = SQUARED_NORM;
      end
      SQUARED_NORM: begin // Send all data to verify_compute_squared_norm before moving to FINISHED
        if(squared_norm_index == N - SQUARED_NORM_OPS_PER_CYCLE)
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

        // Initialize sub_and_norm parameters (so they aren't undefined)
        for(int i = 0; i < MULT_MOD_Q_OPS_PER_CYCLE; i++) begin
          sub_and_norm_a[i] <= 0;
          sub_and_norm_b[i] <= 0;
        end
        sub_and_norm_valid_in <= 0;
        sub_and_norm_index_in <= 0;

        accept <= 1'b0;
        reject <= 1'b0;

        // Reset variables in case we run the module multiple times
        mult_mod_q_index <= 0;
        sub_and_normalize_index <= 0;
        squared_norm_index <= 0;

        public_key_element_index <= 0;
      end

      RECEIVE_PUBLIC_KEY: begin
        if(public_key_ready == 1'b1 && public_key_valid == 1'b1)
          public_key_element_index <= public_key_element_index + 1;
      end

      START_NTT_PUBLIC_KEY: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_start <= 1'b1;
      end

      WAIT_FOR_DECOMPRESS: begin
      end

      RUNNING_NTT_PUBLIC_KEY: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_start <= 1'b0;
      end

      START_NTT_SIGNATURE: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_start <= 1'b1;
      end

      RUNNING_NTT_SIGNATURE: begin
        ntt_mode <= 1'b0;  // NTT
        ntt_start <= 1'b0;
      end

      MULT_MOD_Q: begin
        mod_mult_index_in <= mult_mod_q_index;
        mod_mult_valid_in <= 1'b1;
        mult_mod_q_index <= mult_mod_q_index + 1;
      end

      WAIT_FOR_MULT_MOD_Q: begin
        mod_mult_valid_in <= 0;
        mod_mult_index_in <= 0;
      end

      START_INTT: begin
        ntt_mode <= 1'b1;  // INTT
        ntt_start <= 1'b1;
      end

      RUNNING_INTT: begin
        ntt_mode <= 1'b1;  // INTT
        ntt_start <= 1'b0;
      end

      WAIT_FOR_HASH_TO_POINT: begin
      end

      SUB_AND_NORMALIZE: begin
        sub_and_norm_valid_in <= 1'b1;
        sub_and_norm_index_in <= sub_and_normalize_index;
        sub_and_normalize_index <= sub_and_normalize_index + 1;
      end

      WAIT_FOR_SUB_AND_NORMALIZE: begin
        sub_and_norm_valid_in <= 0;
        sub_and_norm_index_in <= 0;
      end

      SQUARED_NORM: begin
        squared_norm_valid_in <= 1'b1;
        squared_norm_index <= squared_norm_index + 1;
        if(squared_norm_index == N - 1)
          squared_norm_last <= 1'b1;
        else
          squared_norm_last <= 1'b0;
      end

      FINISHED: begin

        // If there was a signature error we can immediately reject the signature
        if(signature_error == 1'b1) begin
          accept <= 1'b0;
          reject <= 1'b1;
        end
        else begin // Otherwise we have to finish squared_norm and then decide
          squared_norm_valid_in <= 0;
          squared_norm_last <= 0;

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
      end
    endcase
  end

  assign public_key_ready = (ntt_state == RECEIVE_PUBLIC_KEY) ? 1'b1 : 1'b0;

  /////////////////////////// End NTT and general control logic ////////

endmodule
