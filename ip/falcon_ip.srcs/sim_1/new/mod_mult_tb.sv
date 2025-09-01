`timescale 1ns / 1ps

module mod_mult_tb;

  logic clk;
  logic rst_n;

  parameter int PARALLEL_OPS_COUNT = 2;

  logic signed [14:0] a [PARALLEL_OPS_COUNT];
  logic signed [14:0] b [PARALLEL_OPS_COUNT];
  logic signed [14:0] result [PARALLEL_OPS_COUNT];
  logic signed [14:0] a_arr [8] = '{1, 2, 3, 4, 12270, 12271, 5550, 7668};
  logic signed [14:0] b_arr [8] = '{2, 2, 2, 2, 2, 2, 2598, 1143};
  logic signed [14:0] expected_results [8] = '{2, 4, 6, 8, 12251, 12253, 3903, 2467};

  logic valid_in, valid_out;

  logic run_test;
  int send_i = 0, receive_i = 0;    // Counters for sending data to module and receiving from module

  mod_mult #(
                    .N(8),
                    .PARALLEL_OPS_COUNT(PARALLEL_OPS_COUNT)
                  )uut (
                    .clk(clk),
                    .rst_n(rst_n),
                    .a(a),
                    .b(b),
                    .valid_in(valid_in),
                    .result(result),
                    .valid_out(valid_out)
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

        receive_i <= receive_i + 2;
      end
      #10;
    end

    run_test = 0;

    $display("All tests for mod_mult passed!");
    $finish;
  end

endmodule

