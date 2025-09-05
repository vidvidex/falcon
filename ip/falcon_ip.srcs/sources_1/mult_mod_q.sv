`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements pipelined multiplication a*b mod 12289.
// This module uses Barrett reduction to avoid using the modulo operator
// https://www.nayuki.io/page/barrett-reduction-algorithm
//
// To speed up calculating a*b mod 12289 for many number this module supports parallel processing of PARALLEL_OPS_COUNT operands at the same time.
// Total number of operands that will be processed needs to be divisible by PARALLEL_OPS_COUNT (if N = 8, then PARALLEL_OPS_COUNT can be 1, 2, 4 or 8)
//
//////////////////////////////////////////////////////////////////////////////////


module mult_mod_q #(
    parameter int N = 512,
    parameter int PARALLEL_OPS_COUNT = 2  //! How many operations to do in parallel (how many a_i * b_i % 12289 operations we do at the same time)
  )(
    input logic clk,
    input logic rst_n,
    input logic signed [14:0] a[PARALLEL_OPS_COUNT],  //! First parameters
    input logic signed [14:0] b[PARALLEL_OPS_COUNT],  //! Second parameters
    input logic valid_in,  //! Are current inputs to the module valid

    output logic signed [14:0] result[PARALLEL_OPS_COUNT], //! Results of a*b mod 12289
    output logic valid_out //! Are the output from the module valid
  );
  logic signed [29:0] a_times_b[PARALLEL_OPS_COUNT];
  logic signed [14:0] a_times_b_1[PARALLEL_OPS_COUNT], a_times_b_2[PARALLEL_OPS_COUNT], a_times_b_3[PARALLEL_OPS_COUNT];  // We only need lower 15 bits for this part
  logic signed [43:0] a_times_b_times_21843[PARALLEL_OPS_COUNT];
  logic signed [14:0] shifted[PARALLEL_OPS_COUNT];
  logic signed [14:0] times_12289[PARALLEL_OPS_COUNT];
  logic signed [14:0] result_i[PARALLEL_OPS_COUNT];
  logic valid1, valid2, valid3, valid4, valid5;

  // Stage 1: Multiply a * b
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || valid_in == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        a_times_b[i] <= 0;
      valid1 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        a_times_b[i] <= a[i] * b[i];
      valid1 <= valid_in;
    end
  end

  // Stage 2: Multiply (a * b) * r
  //
  // r = floor(4^k / 12289) = 21843
  // k = ceil(log2(11289)) = 14
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        a_times_b_times_21843[i] <= 0;
        a_times_b_1[i] <= 0;
      end
      valid2 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        a_times_b_times_21843[i] <= a_times_b[i] * 21843;
        a_times_b_1[i] <= a_times_b[i][14:0]; // Take lower 15 bits of a_times_b
      end
      valid2 <= valid1;
    end
  end

  // Stage 3: Right shift by 2*k
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        shifted[i] <= 0;
        a_times_b_2[i] <= 0;
      end
      valid3 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        shifted[i] <= a_times_b_times_21843[i] >> 28;
      a_times_b_2 <= a_times_b_1;
      valid3 <= valid2;
    end
  end

  // Stage 4: Multiply by 12289
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        times_12289[i] <= 0;
      valid4 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        times_12289[i] <= (((shifted[i] << 3) + (shifted[i] << 2)) << 10) + shifted[i]; // Efficient multiplication by 12289
      a_times_b_3 <= a_times_b_2;
      valid4 <= valid3;
    end
  end

  // Stage 5: Modulo reduction
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        result_i[i] <= 0;
      valid5 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        if(a_times_b_3[i] - times_12289[i] >= 12289)
          result_i[i] = a_times_b_3[i] - times_12289[i] - 12289;
        else
          result_i[i] = a_times_b_3[i] - times_12289[i];
      end
      valid5 <= valid4;
    end
  end

  assign result = result_i;
  assign valid_out = valid5;

endmodule
