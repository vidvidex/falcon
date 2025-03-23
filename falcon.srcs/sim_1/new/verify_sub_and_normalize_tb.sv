`timescale 1ns / 1ps

module verify_sub_and_normalize_tb;



  logic clk;
  logic rst_n;

  parameter int PARALLEL_OPS_COUNT = 2;

  logic signed [14:0] a [PARALLEL_OPS_COUNT];
  logic signed [14:0] b [PARALLEL_OPS_COUNT];
  logic signed [14:0] result [PARALLEL_OPS_COUNT];
  logic signed [14:0] a_arr [8] = '{10, 20, 30, 40, 12251, 12253, 12288, 6155};
  logic signed [14:0] b_arr [8] = '{5, 15, 25, 35, 10, 10, 10, 10};
  logic signed [14:0] expected_results [8] = '{5, 5, 5, 5, -48, -46, -11, -6144};

  logic [3:0] index_in, index_out;
  logic valid_in, valid_out;
  logic last;

  logic run_test;
  int send_i = 0, receive_i = 0;    // Counters for sending data to module and receiving from module

  verify_sub_and_normalize #(
                             .N(8),
                             .PARALLEL_OPS_COUNT(PARALLEL_OPS_COUNT)
                           )uut (
                             .clk(clk),
                             .rst_n(rst_n),
                             .a(a),
                             .b(b),
                             .valid_in(valid_in),
                             .index_in(index_in),
                             .result(result),
                             .valid_out(valid_out),
                             .index_out(index_out),
                             .last(last)
                           );

  always #5 clk = ~clk;

  // Send input data
  always_ff @(posedge clk) begin
    if (run_test && send_i < 8) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        a[i] <= a_arr[send_i + i];
        b[i] <= b_arr[send_i + i];
      end
      valid_in <= 1;
      index_in <= send_i;
      send_i <= send_i + 2;
    end
    else begin
      valid_in <= 0;
    end
  end

  initial begin
    clk = 1;

    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;

    run_test = 1; // Start the test
    #10;

    // Wait for the test to finish
    while (receive_i != 8 ) begin
      if (valid_out) begin

        for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
          if (result[i] != expected_results[receive_i + i])
            $fatal(1, "Test failed: Result is not correct. Expected %d, got %d", expected_results[receive_i + i], result[i]);
        end

        if (receive_i != index_out)
          $fatal(1, "Test failed: index_out is not correct. Expected %d, got %d", receive_i, index_out);

        if(receive_i == 6)
          if(last != 1)
            $fatal(1, "Test failed: Expected last to be high");

        receive_i <= receive_i + 2;
      end
      #10;
    end

    run_test = 0;

    $display("All tests for verify_sub_and_normalize passed!");
    $finish;
  end

endmodule
