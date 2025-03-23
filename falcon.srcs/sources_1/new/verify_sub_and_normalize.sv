`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements pipelined computation sub and normalize.
//
// Every clock cycle we provide a new a_i and b_i to this module.
// In the first stage of the pipeline a_i - b_i is computed and in the second stage the difference is normalized to range [-6144, 6144].
//
// To increase the throughput the module can process PARALLEL_OPS_COUNT input parameters at the same time.
//
//////////////////////////////////////////////////////////////////////////////////


module verify_sub_and_normalize#(
    parameter int N,
    parameter int PARALLEL_OPS_COUNT  //! How many operations to do in parallel
  )(
    input logic clk,
    input logic rst_n,

    input logic signed [14:0] a[PARALLEL_OPS_COUNT],
    input logic signed [14:0] b[PARALLEL_OPS_COUNT],
    input logic valid_in, //! Are all numbers in "a" and "b" valid? This module does not support processing only part of the input a and b
    input logic [$clog2(N):0] index_in,  //! Index of the current operation

    output logic valid_out,
    output logic last,
    output logic [$clog2(N):0] index_out,
    output logic signed [14:0] result[PARALLEL_OPS_COUNT]
  );

  logic signed [14:0] difference[PARALLEL_OPS_COUNT];
  logic signed [14:0] difference_normalized[PARALLEL_OPS_COUNT];
  logic valid1, valid2;
  logic [$clog2(N):0] index1, index2;

  // Stage 1: Subtract b from a
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || valid_in == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        difference[i] <= 0;
      valid1 <= 0;
      index1 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        difference[i] <= a[i] - b[i];
      valid1 <= valid_in;
      index1 <= index_in;
    end
  end

  // Stage 2: Normalize the difference
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        difference_normalized[i] <= 0;
      valid2 <= 0;
      index2 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        if (difference[i] > 6144)
          difference_normalized[i] <= difference[i] - 12289;
        else
          difference_normalized[i] <= difference[i];
      valid2 <= valid1;
      index2 <= index1;
    end
  end

  // Output
  assign valid_out = valid2;
  assign last = valid2 == 1'b1 && valid1 == 1'b0;
  assign index_out = index2;
  assign result = difference_normalized;

endmodule
