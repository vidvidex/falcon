`timescale 1ns / 1ps

module mod_mult_verify_tb;

  logic clk;
  logic rst_n;

  logic signed [14:0] a, b, result;
  logic signed [14:0] a_arr [4] = '{1, 2, 12270, 12271};
  logic signed [14:0] b_arr [4] = '{2, 2, 2, 2};
  logic signed [14:0] expected_results [4] = '{2, 4, 12251, 12253};

  logic [2:0] index_in, index_out;

  logic valid_in, valid_out;
  logic last;

  logic run_test;
  int send_i, receive_i = 0;    // Counters for sending data to module and receiving from module

  mod_mult_verify #(
                    .N(8)
                  )uut (
                    .clk(clk),
                    .rst_n(rst_n),
                    .a(a),
                    .b(b),
                    .index_in(index_in),
                    .valid_in(valid_in),
                    .result(result),
                    .valid_out(valid_out),
                    .index_out(index_out),
                    .last(last)
                  );

  always #5 clk = ~clk;

  // Send input data
  always_ff @(posedge clk) begin
    if (run_test && send_i < 4) begin
      a <= a_arr[send_i];
      b <= b_arr[send_i];
      valid_in <= 1;
      index_in <= send_i;
      send_i <= send_i + 1;
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
    while (receive_i != 4 ) begin
      if (valid_out) begin
        if (result != expected_results[receive_i])
          $fatal(1, "Test failed: Result is not correct. Expected %d, got %d", expected_results[receive_i], result);

        if (receive_i != index_out)
          $fatal(1, "Test failed: index_out is not correct. Expected %d, got %d", receive_i, index_out);

        if(receive_i == 3)
          if(last != 1)
            $fatal(1, "Test failed: Expected last to be high");

        receive_i <= receive_i + 1;
      end
      #10;
    end

    run_test = 0;

    $display("All tests for mod_mult_verify passed!");
    $finish;
  end

endmodule

