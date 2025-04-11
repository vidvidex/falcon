`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements pipelined computation of subtraction, normalization, squared norm and acceptance/rejection (algorithm 16, lines 5-9)
//
// To increase the throughput the module can process PARALLEL_OPS_COUNT input parameters at the same time.
//
//////////////////////////////////////////////////////////////////////////////////


module sub_normalize_squared_norm#(
    parameter int N,
    parameter int PARALLEL_OPS_COUNT  //! How many operations to do in parallel
  )(
    input logic clk,
    input logic rst_n,

    input logic signed [14:0] a[PARALLEL_OPS_COUNT],  //! Coefficients from hash_to_point
    input logic signed [14:0] b[PARALLEL_OPS_COUNT],  //! Coefficients from INTT
    input logic signed [14:0] c[PARALLEL_OPS_COUNT],  //! Coefficients from decompress
    input logic valid,    //! Are inputs valid
    input logic last,     //! Are these the last inputs. After this signal passes through the pipeline the module will output the result

    output logic accept,    //! squared norm <= bound
    output logic reject     //! squared norm > bound
  );

  logic signed [14:0] difference[PARALLEL_OPS_COUNT];
  logic signed [14:0] difference_normalized[PARALLEL_OPS_COUNT];
  logic signed [28:0] difference_normalized_squared[PARALLEL_OPS_COUNT];
  logic signed [28:0] c_squared[PARALLEL_OPS_COUNT];
  logic signed [29+$clog2(PARALLEL_OPS_COUNT):0] elementwise_sum[PARALLEL_OPS_COUNT];
  logic signed [14:0] c1[PARALLEL_OPS_COUNT], c2[PARALLEL_OPS_COUNT];
  logic signed [29+$clog2(PARALLEL_OPS_COUNT):0] squared_norm; // Sum of all parallel elementwise sums
  logic over_bound; // If this is high we are already over the bound. In that case the data we're processing doesn't matter anymore. We are just waiting for the "last" signal to pass through the pipeline, so we can set "reject" high
  logic last1, last2, last3, last4, last5;

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

  // Stage 1: Compute a - b
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || valid == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        difference[i] <= 0;
        c1[i] <= 0;
      end
      last1 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        difference[i] <= a[i] - b[i];
      c1 <= c;
      last1 <= last;
    end
  end

  // Stage 2: Normalize a - b to the range [-6144, 6144]
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        difference_normalized[i] <= 0;
        c2[i] <= 0;
      end
      last2 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        if (difference[i] > 6144)
          difference_normalized[i] <= difference[i] - 12289;
        else if (difference[i] < -6144)
          difference_normalized[i] <= difference[i] + 12289;
        else
          difference_normalized[i] <= difference[i];
      c2 <= c1;
      last2 <= last1;
    end
  end

  // Stage 3: Square normalized difference and c
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        difference_normalized_squared[i] <= 0;
        c_squared[i] <= 0;
      end
      last3 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        difference_normalized_squared[i] <= difference_normalized[i] * difference_normalized[i];
        c_squared[i] <= c2[i] * c2[i];
      end
      last3 <= last2;
    end
  end

  // Stage 4: Sum element-wise
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        elementwise_sum[i] <= 0;
      last4 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        elementwise_sum[i] <= difference_normalized_squared[i] + c_squared[i];
      last4 <= last3;
    end
  end

  // Stage 5: Sum all element-wise sums and check if we're over the bound
  // If we are over the bound we don't immediately set "reject" high, but wait until all data is provided
  // to ensure this module is constant-time
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      squared_norm <= 0;
      over_bound <= 0;
      last5 <= 0;
    end
    else begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        squared_norm <= squared_norm + elementwise_sum[i];
      if(squared_norm > bound2)
        over_bound <= 1;
      last5 <= last4;
    end
  end

  // Stage 6: Wait for "last" signal and output the result
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      accept <= 0;
      reject <= 0;
    end
    else begin
      if(last5 == 1'b1) begin
        if(over_bound == 1 || squared_norm > bound2)
          reject <= 1;
        else
          accept <= 1;
      end
    end
  end

endmodule
