`timescale 1ns / 1ps

// Compares fp_multiplier (a * b * 2^scale_factor) bit for bit against the simulator's IEEE-754 double arithmetic.
// Subnormal numbers are not supported by the multiplier, so inputs are normal numbers whose results stay normal.
module fp_multiplier_tb;

  localparam int RANDOM_TESTS = 2000;

  logic clk;
  logic valid_in, valid_out;
  logic [63:0] a;
  logic [63:0] b;
  logic [63:0] result;
  logic signed [4:0] scale_factor;

  always #5 clk = ~clk;

  fp_multiplier fp_multiplier(
                  .clk(clk),
                  .valid_in(valid_in),
                  .a(a),
                  .b(b),
                  .scale_factor(scale_factor),
                  .result(result),
                  .valid_out(valid_out)
                );

  typedef struct {
    logic [63:0] a, b, expected;
    int scale;
  } test_t;

  test_t tests [$];
  int sent = 0, checked = 0;

  always_ff @(posedge clk) begin
    if (valid_out) begin
      if (tests.size() == 0)
        $fatal(1, "Unexpected output %h", result);
      if (result !== tests[0].expected)
        $fatal(1, "%h (%g) * %h (%g) * 2^%0d: expected %h (%g), got %h (%g)",
               tests[0].a, $bitstoreal(tests[0].a), tests[0].b, $bitstoreal(tests[0].b), tests[0].scale,
               tests[0].expected, $bitstoreal(tests[0].expected), result, $bitstoreal(result));
      void'(tests.pop_front());
      checked <= checked + 1;
    end
  end

  // Random normal double with exponent in [-range, range]
  function automatic real random_double(int range);
    int e = $urandom_range(2 * range) - range;
    return $bitstoreal({1'($urandom), 11'(1023 + e), 20'($urandom), 32'($urandom)});
  endfunction

  task automatic send(input real x, input real y, input int scale);
    tests.push_back('{$realtobits(x), $realtobits(y), $realtobits(x * y * (2.0 ** scale)), scale});
    a <= $realtobits(x);
    b <= $realtobits(y);
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

    send(2.0, -4.5, 0);
    send(1.0, 1.5, 0);
    send(-12.1, -3.0, 0);
    send(0.0, 0.0, 0);
    send(0.0, -7.25, 0);
    send(3.0, 5.0, -1);   // IFFT scaling
    send(3.0, 5.0, -9);
    send(3.0, 5.0, 4);
    send(1.0 + 2.0 ** -52, 1.0 + 2.0 ** -52, 0);           // below half an ulp: rounds down
    send(1.0 + 2.0 ** -26, 1.0 + 2.0 ** -27, 0);           // exactly half an ulp: ties to even
    send($bitstoreal(64'h3fefffffffffffff), $bitstoreal(64'h3ff0000000000001), 0);
    send($bitstoreal(64'h3ff6a09e667f3bcd), $bitstoreal(64'h3ff6a09e667f3bcd), 0);  // sqrt(2)^2, carry bit set

    for (int i = 0; i < RANDOM_TESTS; i++)
      send(random_double(20), random_double(20), 0);
    for (int i = 0; i < RANDOM_TESTS; i++)
      send(random_double(20), random_double(20), $urandom_range(10) - 10);  // scale factor in [-10, 0]

    valid_in <= 0;
    repeat (20) @(posedge clk);

    if (checked != sent)
      $fatal(1, "Got %0d results, expected %0d", checked, sent);
    $display("All tests for fp_multiplier passed! (%0d operations)", sent);
    $finish;
  end

endmodule
