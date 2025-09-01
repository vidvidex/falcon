`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Implements compression of Falcon signatures.
// It also converts t0 and t1 from doubles to ints and checks if signature is valid
// (squared norm less than acceptance bound)
//
// sum((hashed_message - t0)^2 + t1^2) < acceptance_bound
//
// We compute and compress the signature while checking if it's valid because it will
// be valid in most cases and we can save a few cycles.
//
// The compressed signature is written to BRAM via "output_*" signals.
// First memory location will contain the bitlength of compressed signature.
//
//////////////////////////////////////////////////////////////////////////////////


module compress#(
    parameter int N = 512
  )(
    input logic clk,
    input logic rst_n,

    input logic [`BRAM_DATA_WIDTH-1:0] t0,  // Inputs read from BRAM
    input logic [`BRAM_DATA_WIDTH-1:0] t1,
    input logic [`BRAM_DATA_WIDTH-1:0] hm,
    input logic lower_half, // 0 for first N/2 inputs, 1 for second N/2 inputs
    input logic valid,
    input logic last,

    output logic [`BRAM_ADDR_WIDTH-1:0] output_addr,  // Address where to write output
    output logic [`BRAM_DATA_WIDTH-1:0] output_data,
    output logic output_we,

    output logic accept,  // Signature is valid
    output logic reject   // Signature is invalid
  );

  // Expected (max) signature length in bytes, sbytelen(depends on N) - HEAD_LEN(1) - SALT_LEN(40)
  localparam int slen = N == 8 ? 52-1-40 :
             N == 512 ? 666-1-40 :
             N == 1024 ? 1280-1-40 : 0;

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

  logic accept_i, reject_i; // Internal signals for accept and reject

  logic [27:0] squared;
  logic signed [29:0] squared_norm;
  logic over_bound;
  logic [14:0] compressed_signature_length; // Current length of compressed signature in bits

  logic double_to_int_valid_in, double_to_int_valid_out;
  logic [63:0] t0_double;
  logic signed [14:0] t0_int;
  double_to_int double_to_int_t0 (
                  .clk(clk),
                  .double_in(t0_double),
                  .valid_in(double_to_int_valid_in),
                  .int_out(t0_int),
                  .valid_out(double_to_int_valid_out)
                );

  logic [63:0] t1_double;
  logic signed [14:0] t1_int;
  double_to_int double_to_int_t1 (
                  .clk(clk),
                  .double_in(t1_double),
                  .valid_in(double_to_int_valid_in),
                  .int_out(t1_int),
                  .valid_out()
                );

  logic signed [14:0] hm_delayed, hm_delayed_i;

  logic signed [14:0] uncompressed_coefficient;
  logic uncompressed_coefficient_valid;
  logic [104:0] compressed_coefficient;
  logic [6:0] compressed_coefficient_length;
  compress_coefficient compress_coefficient (
                         .clk(clk),
                         .coefficient(uncompressed_coefficient),
                         .coefficient_valid(uncompressed_coefficient_valid),
                         .compressed_coefficient(compressed_coefficient),
                         .compressed_coefficient_length(compressed_coefficient_length)
                       );

  logic last_delayed;
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(4)) last_delay(.clk(clk), .in(last), .out(last_delayed));

  // Step 1: Convert t0 and t1 to int
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      t0_double <= 0;
      t1_double <= 0;
      double_to_int_valid_in <= 0;
      hm_delayed <= 0;
      hm_delayed_i <= 0;
    end
    else if(valid == 1'b1) begin
      t0_double <= lower_half ? t0[63:0] : t0[127:64];
      t1_double <= lower_half ? t1[63:0] : t1[127:64];
      double_to_int_valid_in <= 1;
      hm_delayed <= lower_half ? hm[14:0] : hm[64+14:64];
    end
    else
      double_to_int_valid_in <= 0;

    hm_delayed_i <= hm_delayed;
  end

  // Step 2: Compute (hm-t0)^2 and compress -t1
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      squared <= 0;
      uncompressed_coefficient <= 0;
      uncompressed_coefficient_valid <= 0;
    end
    else if(double_to_int_valid_out == 1'b1) begin
      squared <= (hm_delayed_i - t0_int) * (hm_delayed_i - t0_int);
      uncompressed_coefficient <= -t1_int;
      uncompressed_coefficient_valid <= 1;
    end
  end

  // Step 3: Compute sum of squares
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      squared_norm <= 0;
      over_bound <= 0;
    end
    else begin
      squared_norm <= squared_norm + squared;
      if(squared_norm > bound2)
        over_bound <= 1;
    end
  end

  // Wait for "last" signal and output the result
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      accept_i <= 0;
      reject_i <= 0;
    end
    else begin
      if(last_delayed == 1'b1 && accept_i == 1'b0 && reject_i == 1'b0) begin
        if(over_bound == 1 || squared_norm > bound2 || compressed_signature_length > slen*8)
          reject_i <= 1;
        else
          accept_i <= 1;
      end
    end
  end

  logic [127:0] buffer;
  logic [8:0] buffer_valid_bits;
  logic [6:0] bits_that_fit;
  logic [6:0] remaining_bits;
  logic output_final_zeros;
  logic output_signature_bitlength;
  logic signature_output_done;

  assign accept = signature_output_done ? accept_i : 0;
  assign reject = signature_output_done ? reject_i : 0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      output_addr <= 0;
      output_data <= 0;
      output_we <= 0;
      buffer <= 0;
      buffer_valid_bits <= 0;
      compressed_signature_length <= 0;
      output_final_zeros = 0;
      output_signature_bitlength = 0;
      signature_output_done = 0;
    end
    else begin
      output_we <= 0;

      if (compressed_coefficient_length > 0 && reject_i == 1'b0 && accept_i == 1'b0) begin

        compressed_signature_length <= compressed_signature_length + compressed_coefficient_length;

        if (buffer_valid_bits + compressed_coefficient_length < 128) begin // Entire compressed coefficient fits into buffer and it won't be full
          buffer <= buffer | ({compressed_coefficient, 23'b0} >> buffer_valid_bits);
          buffer_valid_bits <= buffer_valid_bits + compressed_coefficient_length;
        end
        else if (buffer_valid_bits + compressed_coefficient_length == 128) begin // Entire compressed coefficient fits into buffer and it fills it
          output_data <= buffer | ({compressed_coefficient, 23'b0} >> buffer_valid_bits);
          output_we <= 1;
          output_addr <= output_addr + 1;
          buffer <= 0;
          buffer_valid_bits <= 0;
        end
        else begin  // Split the compressed coefficient
          bits_that_fit = 128 - buffer_valid_bits;
          remaining_bits = compressed_coefficient_length - bits_that_fit;

          // Fill the buffer with what fits and output it
          output_data <= buffer | ({compressed_coefficient, 23'b0} >> buffer_valid_bits);
          output_we <= 1;
          output_addr <= output_addr + 1;

          // Put the remaining bits in the cleared buffer
          buffer <= {compressed_coefficient, 23'b0} << bits_that_fit;
          buffer_valid_bits <= remaining_bits;
        end
      end

      // Final flush on last signal
      if (last_delayed && !signature_output_done) begin
        output_data <= buffer | ({compressed_coefficient, 23'b0} >> buffer_valid_bits);
        output_we <= 1;
        output_addr <= output_addr + 1;
        buffer <= 0;
        buffer_valid_bits <= 0;

        // After the signature is sent we might have to output some zeros to clear anything that was in BRAM before
        compressed_signature_length <= compressed_signature_length + 128;
        if(compressed_signature_length < slen*8)
          output_final_zeros <= 1;
        else
          output_signature_bitlength <= 1;
      end

      if(output_final_zeros == 1'b1) begin
        output_data <= 0;
        output_we <= 1;
        output_addr <= output_addr + 1;
        compressed_signature_length <= compressed_signature_length + 128;

        if(compressed_signature_length >= slen*8) begin
          output_final_zeros <= 0; // Stop outputting zeros after reaching the expected length
          output_signature_bitlength <= 1;
        end
      end

      if(output_signature_bitlength == 1'b1) begin
        output_data <= compressed_signature_length;
        output_we <= 1;
        output_addr <= 0;

        output_signature_bitlength <= 0;
        signature_output_done <= 1;
      end
    end
  end

endmodule
