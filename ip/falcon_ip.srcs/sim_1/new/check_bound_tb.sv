`timescale 1ns / 1ps

module check_bound_tb;

  logic clk;
  logic rst_n;

  parameter int N = 8;
  parameter int PARALLEL_OPS_COUNT = 2;

  logic signed [14:0] a [PARALLEL_OPS_COUNT];
  logic signed [14:0] b [PARALLEL_OPS_COUNT];
  logic signed [14:0] c [PARALLEL_OPS_COUNT];

  logic signed [14:0] a_arr [N] = '{10, 20, 30, 40, 12251, 12253, 12288, 6155};
  logic signed [14:0] b_arr [N] = '{5, 15, 25, 35, 10, 10, 10, 10};
  logic signed [14:0] c_arr [N] = '{5, 15, 25, 35, 10, 10, 10, 10};

  logic valid;
  logic last;
  logic accept, reject;

  logic run_test = 0;
  int send_index;

  check_bound #(
                .N(N),
                .PARALLEL_OPS_COUNT(PARALLEL_OPS_COUNT)
              )uut (
                .clk(clk),
                .rst_n(rst_n),
                .a(a),
                .b(b),
                .c(c),
                .valid(valid),
                .last(last),
                .accept(accept),
                .reject(reject)
              );

  always #5 clk = ~clk;

  // Send input data
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0 || run_test == 1'b0) begin
      send_index <= 0;
      valid <= 0;
      last <= 0;
    end
    else begin
      if(send_index < N) begin
        for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
          a[i] <= a_arr[send_index + i];
          b[i] <= b_arr[send_index + i];
          c[i] <= c_arr[send_index + i];
        end
        valid <= 1;
        last <= send_index == N-PARALLEL_OPS_COUNT ? 1 : 0;
        send_index <= send_index + PARALLEL_OPS_COUNT;
      end
      else begin
        valid <= 0;
        last <= 0;
      end
    end
  end


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
    c_arr = '{1, 2, 3, 4, 5, 6, 7, 8};
    run_test = 1;
    while (accept == 1'b0 && reject == 1'b0)
      #10;
    run_test = 0;
    if(accept == 1'b1 && reject == 1'b0)
      $display("Test 1 passed!");
    else
      $fatal(1, "Test 1 failed!");


    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;


    // Test 2: Should reject because c is large
    a_arr = '{1, 2, 3, 4, 5, 6, 7, 8};
    b_arr = '{1, 2, 3, 4, 5, 6, 7, 8};
    c_arr = '{12288, 12288, 12288, 12288, 12288, 12288, 12288, 12288};
    run_test = 1;
    while (accept == 1'b0 && reject == 1'b0)
      #10;
    run_test = 0;
    if(accept == 1'b0 && reject == 1'b1)
      $display("Test 2 passed!");
    else
      $fatal(1, "Test 2 failed!");


    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;


    // Test 3: Should reject because norm(a-b) is large
    a_arr = '{6145, 6145, 6145, 6145, 6145, 6145, 6145, 6145};
    b_arr = '{1, 1, 1, 1, 1, 1, 1, 1}; // norm(a_i - b_i) = 6144 (maximum value)
    c_arr = '{1, 2, 3, 4, 5, 6, 7, 8};
    run_test = 1;
    while (accept == 1'b0 && reject == 1'b0)
      #10;
    run_test = 0;
    if(accept == 1'b0 && reject == 1'b1)
      $display("Test 3 passed!");
    else
      $fatal(1, "Test 3 failed!");


    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;


    // Test 4: Should reject because norm(a-b) is large (but negative)
    a_arr = '{6146, 6146, 6146, 6146, 6146, 6146, 6146, 6146};
    b_arr = '{1, 1, 1, 1, 1, 1, 1, 1}; // norm(a_i - b_i) = −6144 (minimum value)
    c_arr = '{1, 2, 3, 4, 5, 6, 7, 8};
    run_test = 1;
    while (accept == 1'b0 && reject == 1'b0)
      #10;
    run_test = 0;
    if(accept == 1'b0 && reject == 1'b1)
      $display("Test 4 passed!");
    else
      $fatal(1, "Test 4 failed!");


    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;


    // Test 5: Should reject because all inputs are large
    a_arr = '{6145, 6145, 6145, 6145, 6145, 6145, 6145, 6145};
    b_arr = '{1, 1, 1, 1, 1, 1, 1, 1}; // norm(a_i - b_i) = 6144 (maximum value)
    c_arr = '{12288, 12288, 12288, 12288, 12288, 12288, 12288, 12288};
    run_test = 1;
    while (accept == 1'b0 && reject == 1'b0)
      #10;
    run_test = 0;
    if(accept == 1'b0 && reject == 1'b1)
      $display("Test 5 passed!");
    else
      $fatal(1, "Test 5 failed!");


    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;


    // Test 6: Should reject, but only in the last cycle
    a_arr = '{1, 1, 1, 1, 1, 1, 1, 6145};
    b_arr = '{1, 1, 1, 1, 1, 1, 1, 1};
    c_arr = '{1, 1, 1, 1, 1, 1, 1, 12288};
    run_test = 1;
    while (accept == 1'b0 && reject == 1'b0)
      #10;
    run_test = 0;
    if(accept == 1'b0 && reject == 1'b1)
      $display("Test 6 passed!");
    else
      $fatal(1, "Test 6 failed!");



    $display("All tests for check_bound passed!");
    $finish;
  end

endmodule
