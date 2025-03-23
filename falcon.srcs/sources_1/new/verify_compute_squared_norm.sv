`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements pipelined computation of squared norm for the verify module.
//
// Every clock cycle we provide a new a_i and b_i to this module. These numbers are squared,
// summed and aggregated into the internal "squared_sum" register. Once all a_i and b_i have
// been provided the module will set signal:
//  - "accept" high if squared norm is smaller or equal to the bound
//  - "reject" high if squared norm is larger than the bound
//
// To increase the throughput the module can process PARALLEL_OPS_COUNT input parameters at the same time.
//
//////////////////////////////////////////////////////////////////////////////////


module verify_compute_squared_norm#(
    parameter int N,
    parameter int PARALLEL_OPS_COUNT  //! How many operations to do in parallel
  )(
    input logic clk,
    input logic rst_n,

    input logic signed [14:0] a[PARALLEL_OPS_COUNT],
    input logic signed [14:0] b[PARALLEL_OPS_COUNT],
    input logic valid_in, //! Are all numbers in "a" and "b" valid? This module does not support processing only part of the input a and b
    input logic last,    //! Are these the last inputs. After this signal passes through the pipeline the module will output the result

    output logic accept,    //! squared norm <= bound
    output logic reject     //! squared norm > bound
  );

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

  logic signed [28:0] a_squared[PARALLEL_OPS_COUNT];
  logic signed [28:0] b_squared[PARALLEL_OPS_COUNT];
  logic signed [29+$clog2(PARALLEL_OPS_COUNT):0] elementwise_sum[PARALLEL_OPS_COUNT];
  logic signed [29+$clog2(PARALLEL_OPS_COUNT):0] squared_norm; // Sum of all parallel elementwise sums
  logic over_bound; // If this is high we are already over the bound. In that case the data we're processing doesn't matter anymore. We are just waiting for the "last" signal to pass through the pipeline, so we can set "reject" high
  logic last1, last2, last3;

  // Stage 1: Square a and b
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || valid_in !== 1'b1) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        a_squared[i] <= 0;
        b_squared[i] <= 0;
      end
      last1 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        a_squared[i] <= a[i] * a[i];
        b_squared[i] <= b[i] * b[i];
      end
      last1 <= last;
    end
  end

  // Stage 2: Sum element-wise
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        elementwise_sum[i] <= 0;
      last2 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        elementwise_sum[i] <= a_squared[i] + b_squared[i];
      last2 <= last1;
    end
  end

  // Stage 3: Sum all element-wise sums and check if we're over the bound
  // If we are over the bound we don't immediately set "reject" high, but wait until all data is provided
  // to ensure this module is constant-time
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      squared_norm <= 0;
      last3 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        squared_norm <= squared_norm + elementwise_sum[i];
      if(squared_norm > bound2)
        over_bound <= 1;
      last3 <= last2;
    end
  end

  // Stage 4: Wait for "last" signal and output the result
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      accept <= 0;
      reject <= 0;
    end
    else begin
      if(last3 == 1'b1) begin
        if(over_bound == 1 || squared_norm > bound2)
          reject <= 1;
        else
          accept <= 1;
      end
    end
  end

endmodule
