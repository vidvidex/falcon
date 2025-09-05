`timescale 1ns / 1ps

module mult_mod_q_for_ntt_tb;

  logic clk;
  logic rst_n;

  logic signed [14:0] a, b, result;
  logic signed [14:0] a_arr [4] = '{4091, 8182, 12273, 4075};             // 1, 2, 3, 4 in Montgomery form
  logic signed [14:0] b_arr [4] = '{8182, 8182, 8182, 8182};              // 2, 2, 2, 2 in Montgomery form
  logic signed [14:0] expected_results [4] = '{8182, 4075, 12257, 8150};  // 2, 4, 6, 8 in Montgomery form
  logic signed [14:0] passthrough_in, passthrough_out;

  logic valid_in, valid_out;
  logic last;

  logic [3:0] index1_in, index2_in, index1_out, index2_out;

  logic run_test;
  int i = 0;

  mult_mod_q_for_ntt #(
                       .N(8)
                     )uut (
                       .clk(clk),
                       .rst_n(rst_n),
                       .a(a),
                       .b(b),
                       .valid_in(valid_in),
                       .index1_in(index1_in),
                       .index2_in(index2_in),
                       .result(result),
                       .valid_out(valid_out),
                       .last(last),
                       .index1_out(index1_out),
                       .index2_out(index2_out)
                     );

  always #5 clk = ~clk;

  // Send input data
  always_ff @(posedge clk) begin
    if (run_test && i < 4) begin
      a <= a_arr[i];
      b <= b_arr[i];
      valid_in <= 1;
      index1_in <= i;
      index2_in <= i + 4;
      i <= i + 1;
      passthrough_in <= 42;
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
    while (last != 1 ) begin
      if (valid_out) begin

        if (result != expected_results[index1_out])
          $fatal(1, "Test failed: Result is not correct. Expected %d, got %d", expected_results[index1_out], result);

        if(index2_out != index1_out + 4)
          $fatal(1, "Test failed: Index2 is not correct. Expected %d, got %d", index1_out + 4, index2_out);

        if(passthrough_out != 42)
          $fatal(1, "Test failed: Passthrough is not correct. Expected %d, got %d", passthrough_in, passthrough_out);

        if(index1_out == 4)
          if(last != 1)
            $fatal(1, "Test failed: Last is not correct. Expected 1, got %d", last);
      end

      #10;
    end

    run_test = 0;

    $display("All tests for mult_mod_q_for_ntt passed!");
    $finish;
  end

endmodule

