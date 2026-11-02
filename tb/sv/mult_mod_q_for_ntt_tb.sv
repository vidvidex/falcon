`timescale 1ns / 1ps

module mult_mod_q_for_ntt_tb;

  localparam int FIXED = 8;
  localparam int COUNT = FIXED + 200;

  logic clk;
  logic rst_n;

  logic signed [14:0] a, b, result;
  logic signed [14:0] fixed_a [FIXED] = '{1, 2, 3, 4, 12288, 5550, 7668, 0};
  logic signed [14:0] fixed_b [FIXED] = '{2, 2, 2, 2, 12288, 2598, 1143, 12288};
  logic signed [14:0] fixed_expected [FIXED] = '{2, 4, 6, 8, 1, 3903, 2467, 0};  // a*b mod 12289
  logic signed [14:0] a_arr [COUNT], b_arr [COUNT], expected_results [COUNT];
  logic signed [14:0] passthrough_in, passthrough_out;

  logic valid_in, valid_out;
  logic last;

  logic [8:0] index1_in, index2_in, index1_out, index2_out;

  logic run_test = 0;
  int i = 0;
  int received = 0;

  mult_mod_q_for_ntt #(
                       .N(256)
                     )uut (
                       .clk(clk),
                       .rst_n(rst_n),
                       .a(a),
                       .b(b),
                       .valid_in(valid_in),
                       .index1_in(index1_in),
                       .index2_in(index2_in),
                       .passthrough_in(passthrough_in),
                       .result(result),
                       .valid_out(valid_out),
                       .last(last),
                       .index1_out(index1_out),
                       .index2_out(index2_out),
                       .passthrough_out(passthrough_out)
                     );

  always #5 clk = ~clk;

  // Send input data
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_in <= 0;
    end
    else if (run_test && i < COUNT) begin
      a <= a_arr[i];
      b <= (longint'(b_arr[i]) * 4095) % 12289;  // Montgomery form: 2^14 mod 12289 = 4095
      valid_in <= 1;
      index1_in <= i;
      index2_in <= i + COUNT;
      passthrough_in <= 42 + i;
      i <= i + 1;
    end
    else begin
      valid_in <= 0;
    end
  end

  // Check output data
  always_ff @(posedge clk) begin
    if (valid_out) begin
      if (index1_out != received)
        $fatal(1, "Test failed: results out of order. Expected index %0d, got %0d", received, index1_out);
      if (result != expected_results[index1_out])
        $fatal(1, "Test failed: %0d * %0d mod 12289. Expected %0d, got %0d", a_arr[index1_out], b_arr[index1_out], expected_results[index1_out], result);
      if (index2_out != index1_out + COUNT)
        $fatal(1, "Test failed: Index2 is not correct. Expected %0d, got %0d", index1_out + COUNT, index2_out);
      if (passthrough_out != 42 + index1_out)
        $fatal(1, "Test failed: Passthrough is not correct. Expected %0d, got %0d", 42 + index1_out, passthrough_out);
      received <= received + 1;
    end
    // "last" marks the final result
    if (last && !(valid_out && index1_out == COUNT - 1))
      $fatal(1, "Test failed: last raised without the final result (valid_out=%0d, index=%0d)", valid_out, index1_out);
  end

  initial begin
    for (int i = 0; i < COUNT; i++) begin
      if (i < FIXED) begin
        a_arr[i] = fixed_a[i];
        b_arr[i] = fixed_b[i];
        expected_results[i] = fixed_expected[i];
      end
      else begin
        a_arr[i] = $urandom_range(12288);
        b_arr[i] = $urandom_range(12288);
        expected_results[i] = (longint'(a_arr[i]) * longint'(b_arr[i])) % 12289;
      end
    end

    clk = 1;

    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;

    run_test = 1; // Start the test

    while (last !== 1'b1)
      #10;
    #10;  // let the checker count the final result

    if (received != COUNT)
      $fatal(1, "Test failed: got %0d results, expected %0d", received, COUNT);

    $display("All tests for mult_mod_q_for_ntt passed!");
    $finish;
  end

endmodule
