`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements pipelined multiplication a*b mod 12289.
// This module does not use Montgomery form for any of the operations.
//
// The module is tailored specifically for use in the verify module.
// Should you want to use this module for something else you can safely remove these parameters and just keep the basic multiplication functionality.
//
//////////////////////////////////////////////////////////////////////////////////


module mod_mult_verify #(
    parameter int N
  )(
    input logic clk,
    input logic rst_n,
    input logic signed [14:0] a,  //! First parameter
    input logic signed [14:0] b,  //! Second parameter
    input logic valid_in,  //! Are current inputs to the module valid. This is used mainly to generate the "last" signal, signifying the end of data output
    input logic [$clog2(N):0] index_in,  //! Index of current parameters (passed through the pipeline)

    output logic signed [14:0] result, //! Result of a*b mod 12289
    output logic valid_out, //! Are the output from the module valid
    output logic last, //! Is this the last result that we're outputting
    output logic [$clog2(N):0] index_out  //! Index of current parameters (passed through the pipeline)
  );
  logic signed [29:0] a_times_b;
  logic [15:0] a_times_b_mod_12289;
  logic [$clog2(N):0] index1, index2;

  logic valid1, valid2;

  // Stage 1: Multiplication
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || valid_in == 1'b0) begin
      a_times_b <= 0;
      valid1 <= 0;
      index1 <= 0;
    end
    else begin
      a_times_b <= a * b;
      valid1 <= valid_in;
      index1 <= index_in;
    end
  end

  // Stage 2: Modulo 12289
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      a_times_b_mod_12289 <= 0;
      valid2 <= 0;
      index2 <= 0;
    end
    else begin
      a_times_b_mod_12289 <= a_times_b % 12289;
      valid2 <= valid1;
      index2 <= index1;
    end
  end

  assign result = a_times_b_mod_12289;
  assign valid_out = valid2;
  assign last = valid2 == 1'b1 && valid1 == 1'b0;
  assign index_out = index2;

endmodule
