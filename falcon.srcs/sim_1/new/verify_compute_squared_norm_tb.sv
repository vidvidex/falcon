`timescale 1ns / 1ps
module verify_compute_squared_norm_tb;

  logic clk;
  logic rst_n;

  parameter int N = 8;
  parameter int PARALLEL_OPS_COUNT = 1;

  logic signed [14:0] a [PARALLEL_OPS_COUNT];
  logic signed [14:0] b [PARALLEL_OPS_COUNT];
  logic signed [14:0] a_arr [N];
  logic signed [14:0] b_arr [N];

  logic valid_in;
  logic last;
  int send_index;
  logic accept, reject;

  logic run_test = 0;

  verify_compute_squared_norm #(
                                .N(N),
                                .PARALLEL_OPS_COUNT(PARALLEL_OPS_COUNT)
                              )uut (
                                .clk(clk),
                                .rst_n(rst_n),
                                .a(a),
                                .b(b),
                                .valid_in(valid_in),
                                .last(last),
                                .accept(accept),
                                .reject(reject)
                              );

  // Send data to the module
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || run_test == 1'b0) begin
      send_index <= 0;
      valid_in <= 0;
      last <= 0;
    end
    else begin
      if(send_index < N) begin
        for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
          a[i] <= a_arr[send_index + i];
          b[i] <= b_arr[send_index + i];
        end
        valid_in <= 1;
        last <= send_index == N-PARALLEL_OPS_COUNT ? 1 : 0;
        send_index <= send_index + PARALLEL_OPS_COUNT;
      end
      else begin
        valid_in <= 0;
        last <= 0;
      end
    end
  end

  always #5 clk = ~clk;

  initial begin
    clk = 1;

    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;

    // Test 1: Should accept
    a_arr = '{1, 2, 3, 4, 5, 6, 7, 8};
    b_arr = '{1, 2, 3, 4, 5, 6, 7, 8};
    run_test = 1;
    while (accept == 1'b0 && reject == 1'b0)
      #10;
    run_test = 0;
    if(accept == 1'b1 && reject == 1'b0)
      $display("Test 1 passed!");
    else
      $fatal("Test 1 failed!");


    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;


    // Test 2: Should reject
    a_arr = '{12288, 12288, 12288, 12288, 12288, 12288, 12288, 12288};
    b_arr = '{12288, 12288, 12288, 12288, 12288, 12288, 12288, 12288};
    run_test = 1;
    while (accept == 1'b0 && reject == 1'b0)
      #10;
    run_test = 0;
    if(accept == 1'b0 && reject == 1'b1)
      $display("Test 2 passed!");
    else
      $fatal("Test 2 failed!");


    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;


    // Test 3: Should reject, but only in the last cycle
    a_arr = '{1, 1, 1, 1, 1, 1, 1, 12288};
    b_arr = '{1, 1, 1, 1, 1, 1, 1, 12288};
    run_test = 1;
    while (accept == 1'b0 && reject == 1'b0)
      #10;
    run_test = 0;
    if(accept == 1'b0 && reject == 1'b1)
      $display("Test 3 passed!");
    else
      $fatal("Test 3 failed!");


    $display("All tests for verify_compute_squared_norm passed!");
    $finish;
  end

endmodule


