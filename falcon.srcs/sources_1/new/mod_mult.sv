`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements pipelined multiplication a*b mod 12289.
// The delay of this module is 5 clock cycles.
//
// The module is tailored specifically for use in the ntt_negative module. For this reason we also have many other parameters, which we just pass through the pipeline
// and output as they are. These parameters are for example index1, index2 and valid. They will be used when processing the result of multiplication in the parent module.a
// Should you want to use this module for something else you can safely remove these parameters and just keep the basic multiplication functionality.
//
// Parameters a and b and the result are all in Montgomery form
//
// Conversion to and from Montgomery form can be done using this module:
//      to Montgomery form:   a_mont = mod_mult(a, R^2 % 12289)
//      from Montgomery form: a = mod_mult(a_mont, 1)
//
//////////////////////////////////////////////////////////////////////////////////


module mod_mult #(
    parameter int N
  )(
    input logic clk,
    input logic rst_n,
    input logic signed [14:0] a,  //! First parameter
    input logic signed [14:0] b,  //! Second parameter
    input logic valid_in,  //! Are current inputs to the module valid. This is used mainly to generate the "last" signal, signifying the end of data output
    input logic [$clog2(N):0] index1_in,  //! Index at which the result (or what we compute out of result) should be saved in the polynomial
    input logic [$clog2(N):0] index2_in,  //! Index at which the result (or what we compute out of result) should be saved in the polynomial. This is essentially index+stride.

    output logic signed [14:0] result, //! Result of a*b mod 12289
    output logic valid_out, //! Are the output from the module valid
    output logic last, //! Is this the last result that we're outputting
    output logic [$clog2(N):0] index1_out,  //! Outputted index
    output logic [$clog2(N):0] index2_out   //! Outputted index
  );
  logic signed [29:0] a_times_b, a_times_b_1, a_times_b_2;
  logic [15:0] a_times_b_times_12287;
  logic signed [30:0] a_times_b_times_12287_times_12289;
  logic signed [14:0] sum_shifted, result_i;

  logic valid1, valid2, valid3, valid4, valid5;
  logic [$clog2(N):0] index1_1, index1_2, index1_3, index1_4, index1_5;
  logic [$clog2(N):0] index2_1, index2_2, index2_3, index2_4, index2_5;

  // Stage 1: Multiplication
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || valid_in == 1'b0) begin
      a_times_b <= 0;
      valid1 <= 0;
      index1_1 <= 0;
      index2_1 <= 0;
    end
    else begin
      a_times_b <= a * b;
      valid1 <= valid_in;
      index1_1 <= index1_in;
      index2_1 <= index2_in;
    end
  end

  // Stage 2: Efficient multiplication by 12287
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      a_times_b_times_12287 <= 0;
      a_times_b_1 <= 0;
      valid2 <= 0;
      index1_2 <= 0;
      index2_2 <= 0;
    end
    else begin
      a_times_b_times_12287 <= 16'((((a_times_b << 3) + (a_times_b << 2)) << 10) - a_times_b);  // We only take the lowest 16 bits
      a_times_b_1 <= a_times_b;
      valid2 <= valid1;
      index1_2 <= index1_1;
      index2_2 <= index2_1;
    end
  end

  // Stage 3: Efficient multiplication by 12289
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      a_times_b_times_12287_times_12289 <= 0;
      a_times_b_2 <= 0;
      valid3 <= 0;
      index1_3 <= 0;
      index2_3 <= 0;
    end
    else begin
      a_times_b_times_12287_times_12289 <= (((a_times_b_times_12287 << 3) + (a_times_b_times_12287 << 2)) << 10) + a_times_b_times_12287;
      a_times_b_2 <= a_times_b_1;
      valid3 <= valid2;
      index1_3 <= index1_2;
      index2_3 <= index2_2;
    end
  end

  // Stage 4: Final computation
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      sum_shifted <= 0;
      valid4 <= 0;
      index1_4 <= 0;
      index2_4 <= 0;
    end
    else begin
      sum_shifted <= (a_times_b_2 + a_times_b_times_12287_times_12289) >> 16;
      valid4 <= valid3;
      index1_4 <= index1_3;
      index2_4 <= index2_3;
    end
  end

  // Stage 5: Modulo reduction
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      result_i <= 0;
      valid5 <= 0;
      index1_5 <= 0;
      index2_5 <= 0;
    end
    else begin
      result_i <= (sum_shifted >= 12289) ? (sum_shifted - 12289) : sum_shifted;
      valid5 <= valid4;
      index1_5 <= index1_4;
      index2_5 <= index2_4;
    end
  end

  assign result = result_i;
  assign index1_out = index1_5;
  assign index2_out = index2_5;
  assign valid_out = valid5;
  assign last = valid5 == 1'b1 && valid4 == 1'b0;

endmodule
