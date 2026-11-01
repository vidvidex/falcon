`timescale 1ns / 1ps

// Compares complex_multiplier bit for bit against the simulator's IEEE-754 double arithmetic, with s = 2^scale_factor:
//   real = ar*br*s - ai*bi*s, imag = ar*bi*s + ai*br*s
// (each product and the sum are rounded separately, as in the hardware)
module complex_multiplier_tb;

  localparam int RANDOM_TESTS = 2000;

  logic clk;
  logic valid_in, valid_out;
  logic [63:0] a_real, a_imag;
  logic [63:0] b_real, b_imag;
  logic [63:0] result_real, result_imag;
  logic signed [4:0] scale_factor;

  always #5 clk = ~clk;

  complex_multiplier complex_multiplier(
                      .clk(clk),
                      .valid_in(valid_in),
                      .a_real(a_real),
                      .a_imag(a_imag),
                      .b_real(b_real),
                      .b_imag(b_imag),
                      .scale_factor(scale_factor),
                      .a_x_b_real(result_real),
                      .a_x_b_imag(result_imag),
                      .valid_out(valid_out)
                    );

  typedef struct {
    real ar, ai, br, bi;
    int scale;
    logic [63:0] expected_real, expected_imag;
  } test_t;

  test_t tests [$];
  int sent = 0, checked = 0;

  always_ff @(posedge clk) begin
    if (valid_out) begin
      if (tests.size() == 0)
        $fatal(1, "Unexpected output");
      if (result_real !== tests[0].expected_real || result_imag !== tests[0].expected_imag)
        $fatal(1, "(%g + j%g) * (%g + j%g) * 2^%0d: expected %h + j%h, got %h + j%h",
               tests[0].ar, tests[0].ai, tests[0].br, tests[0].bi, tests[0].scale,
               tests[0].expected_real, tests[0].expected_imag, result_real, result_imag);
      void'(tests.pop_front());
      checked <= checked + 1;
    end
  end

  // Random normal double with exponent in [-range, range]
  function automatic real random_double(int range);
    int e = $urandom_range(2 * range) - range;
    return $bitstoreal({1'($urandom), 11'(1023 + e), 20'($urandom), 32'($urandom)});
  endfunction

  task automatic send(input real ar, input real ai, input real br, input real bi, input int scale);
    real s = 2.0 ** scale;
    tests.push_back('{ar, ai, br, bi, scale, $realtobits(ar * br * s - ai * bi * s), $realtobits(ar * bi * s + ai * br * s)});
    a_real <= $realtobits(ar);
    a_imag <= $realtobits(ai);
    b_real <= $realtobits(br);
    b_imag <= $realtobits(bi);
    scale_factor <= scale;
    valid_in <= 1;
    sent++;
    @(posedge clk);
  endtask

  initial begin
    clk = 1;
    valid_in = 0;
    scale_factor = 0;
    @(posedge clk);

    send(1.5, 2.5, 3.5, 4.5, -1);
    send(2.5, 4.5, 8.5, 16.5, -1);
    send(1.0, 0.0, 0.0, 1.0, 0);
    send(0.0, 1.0, 0.0, 1.0, 0);
    send(3.0, -4.0, 3.0, 4.0, 0);

    for (int i = 0; i < RANDOM_TESTS; i++)
      send(random_double(10), random_double(10), random_double(10), random_double(10), $urandom_range(10) - 10);

    valid_in <= 0;
    repeat (30) @(posedge clk);

    if (checked != sent)
      $fatal(1, "Got %0d results, expected %0d", checked, sent);
    $display("All tests for complex_multiplier passed! (%0d operations)", sent);
    $finish;
  end

endmodule
