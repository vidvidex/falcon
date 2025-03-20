`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements pipelined multiplication a*b mod 12289.
// This module does not use Montgomery form for any of the operations.
//
// To speed up calculating a*b mod 12289 for many number this module supports parallel processing of PARALLEL_OPS_COUNT operands at the same time.
// Total number of operands that will be processed needs to be divisible by PARALLEL_OPS_COUNT (if N = 8, then PARALLEL_OPS_COUNT can be 1, 2, 4 or 8)
//
// The module is tailored specifically for use in the verify module. For this reason we also have a parameter "index" that we just pass through the pipeline,
// but it makes using this module easier.
// Should you want to use this module for something else you can safely remove these parameters and just keep the basic multiplication functionality.
//
//////////////////////////////////////////////////////////////////////////////////


module mod_mult_verify #(
    parameter int N,
    parameter int PARALLEL_OPS_COUNT  //! How many operations to do in parallel (how many a_i * b_i % 12289 operations we do at the same time)
  )(
    input logic clk,
    input logic rst_n,
    input logic signed [14:0] a[PARALLEL_OPS_COUNT],  //! First parameters
    input logic signed [14:0] b[PARALLEL_OPS_COUNT],  //! Second parameters
    input logic valid_in,  //! Are current inputs to the module valid. This is used mainly to generate the "last" signal, signifying the end of data output
    input logic [$clog2(N):0] index_in,  //! Index of first a and b parameters (first element of "a"/"b") ,passed through the pipeline

    output logic signed [14:0] result[PARALLEL_OPS_COUNT], //! Results of a*b mod 12289
    output logic valid_out, //! Are the output from the module valid
    output logic last, //! Is this the last result that we're outputting
    output logic [$clog2(N):0] index_out
  );
  logic signed [29:0] a_times_b[PARALLEL_OPS_COUNT];
  logic signed [14:0] a_times_b_mod_12289[PARALLEL_OPS_COUNT];
  logic [$clog2(N):0] index1, index2;

  logic valid1, valid2;

  // Stage 1: Multiplication
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || valid_in == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        a_times_b[i] <= 0;
      valid1 <= 0;
      index1 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        a_times_b[i] <= a[i] * b[i];
      valid1 <= valid_in;
      index1 <= index_in;
    end
  end

  // Stage 2: Modulo 12289
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        a_times_b_mod_12289[i] <= 0;
      valid2 <= 0;
      index2 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        a_times_b_mod_12289[i] <= a_times_b[i] % 12289;
      valid2 <= valid1;
      index2 <= index1;
    end
  end

  assign result = a_times_b_mod_12289;
  assign valid_out = valid2;
  assign last = valid2 == 1'b1 && valid1 == 1'b0;
  assign index_out = index2;

endmodule
