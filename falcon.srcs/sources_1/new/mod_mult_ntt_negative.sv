`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements pipelined multiplication a*b mod 12289.
//
// The module is tailored specifically for use in the ntt_negative module. For this reason we also have many other parameters, which we just pass through the pipeline
// and output as they are. These parameters are for example index1, index2 and valid. They will be used when processing the result of multiplication in the parent module.
// Should you want to use this module for something else you can safely remove these parameters and just keep the basic multiplication functionality.
//
//////////////////////////////////////////////////////////////////////////////////


module mod_mult_ntt_negative #(
    parameter int N
  )(
    input logic clk,
    input logic rst_n,
    input logic signed [14:0] a,  //! First parameter
    input logic signed [14:0] b,  //! Second parameter
    input logic valid_in,  //! Are current inputs to the module valid. This is used mainly to generate the "last" signal, signifying the end of data output
    input logic [$clog2(N):0] index1_in,  //! Index at which the result (or what we compute out of result) should be saved in the polynomial
    input logic [$clog2(N):0] index2_in,  //! Index at which the result (or what we compute out of result) should be saved in the polynomial. This is essentially index+stride.
    input logic signed [14:0] passthrough_in,  //! We'll just pass this through the pipeline

    output logic signed [14:0] result, //! Result of a*b mod 12289
    output logic valid_out, //! Are the output from the module valid
    output logic last, //! Is this the last result that we're outputting
    output logic [$clog2(N):0] index1_out,  //! Outputted index
    output logic [$clog2(N):0] index2_out,   //! Outputted index
    output logic signed [14:0] passthrough_out  //! Passthrough output
  );
  logic signed [29:0] a_times_b;

  logic valid1;
  logic [$clog2(N):0] index1_1;
  logic [$clog2(N):0] index2_1;

  logic signed [14:0] passthrough_1;

  // Stage 1: Multiplication
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || valid_in == 1'b0) begin
      a_times_b <= 0;
      valid1 <= 0;
      index1_1 <= 0;
      index2_1 <= 0;
      passthrough_1 <= 0;
    end
    else begin
      a_times_b <= a * b;
      valid1 <= valid_in;
      index1_1 <= index1_in;
      index2_1 <= index2_in;
      passthrough_1 <= passthrough_in;
    end
  end

  // Stage 2: Modulo 12289
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      valid_out <= 0;
    end
    else begin
      logic signed [14:0] temp;
      temp = a_times_b % 12289;
      result <= temp < 0 ? temp + 12289 : temp; // Make sure the result is positive
      valid_out <= valid1;
      index1_out <= index1_1;
      index2_out <= index2_1;
      passthrough_out <= passthrough_1;
      last <= valid_out == 1'b1 && valid_in == 1'b0;
    end
  end

endmodule
