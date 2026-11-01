`timescale 1ns / 1ps

// Checks mult_mod_q (a * b mod 12289, PARALLEL_OPS_COUNT products per cycle) on fixed cases and random operands in [0, q).
module mult_mod_q_tb;

  localparam int Q = 12289;
  localparam int FIXED = 8;
  localparam int COUNT = FIXED + 2000;

  logic clk;
  logic rst_n;

  parameter int PARALLEL_OPS_COUNT = 2;

  logic signed [14:0] a [PARALLEL_OPS_COUNT];
  logic signed [14:0] b [PARALLEL_OPS_COUNT];
  logic signed [14:0] result [PARALLEL_OPS_COUNT];
  logic signed [14:0] fixed_a [FIXED] = '{1, 2, 3, 4, 12270, 12271, 5550, 7668};
  logic signed [14:0] fixed_b [FIXED] = '{2, 2, 2, 2, 2, 2, 2598, 1143};
  logic signed [14:0] fixed_expected [FIXED] = '{2, 4, 6, 8, 12251, 12253, 3903, 2467};
  logic signed [14:0] a_arr [COUNT], b_arr [COUNT], expected_results [COUNT];

  logic valid_in, valid_out;

  logic run_test = 0;
  int send_i = 0, receive_i = 0;    // Counters for sending data to module and receiving from module

  mult_mod_q #(
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
    if (run_test && send_i < COUNT) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++) begin
        a[i] <= a_arr[send_i + i];
        b[i] <= b_arr[send_i + i];
      end
      valid_in <= 1;
      send_i <= send_i + PARALLEL_OPS_COUNT;
    end
    else begin
      valid_in <= 0;
    end
  end

  // Check results
  always_ff @(posedge clk) begin
    if (valid_out) begin
      for(int i = 0; i < PARALLEL_OPS_COUNT; i++)
        if (result[i] !== expected_results[receive_i + i])
          $fatal(1, "Test failed: %0d * %0d mod %0d: expected %0d, got %0d", a_arr[receive_i + i], b_arr[receive_i + i], Q,
                 expected_results[receive_i + i], result[i]);
      receive_i <= receive_i + PARALLEL_OPS_COUNT;
    end
  end

  initial begin
    for (int i = 0; i < COUNT; i++) begin
      if (i < FIXED) begin
        a_arr[i] = fixed_a[i];
        b_arr[i] = fixed_b[i];
        expected_results[i] = fixed_expected[i];
      end
      else begin
        a_arr[i] = $urandom_range(Q - 1);
        b_arr[i] = $urandom_range(Q - 1);
        expected_results[i] = (longint'(a_arr[i]) * longint'(b_arr[i])) % Q;
      end
    end

    clk = 1;

    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;

    run_test = 1; // Start the test

    // Wait for the test to finish
    while (receive_i < COUNT)
      #10;

    $display("All tests for mult_mod_q passed! (%0d products)", COUNT);
    $finish;
  end

endmodule
