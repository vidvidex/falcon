`timescale 1ns / 1ps

// Compares fp_adder bit for bit against the simulator's IEEE-754 double arithmetic.
// Subnormal numbers are not supported by the adder, so inputs are normal numbers whose results stay normal.
module fp_adder_tb;

  localparam int RANDOM_TESTS = 1000;

  logic clk;
  logic valid_in, valid_out;
  logic [63:0] a;
  logic [63:0] b;
  logic [63:0] result;
  logic mode;

  always #5 clk = ~clk;

  fp_adder fp_adder(
             .clk(clk),
             .mode(mode),  // 0 = add, 1 = subtract
             .valid_in(valid_in),
             .a(a),
             .b(b),
             .result(result),
             .valid_out(valid_out)
           );

  typedef struct {
    logic [63:0] a, b, expected;
    logic mode;
  } test_t;

  test_t tests [$];
  int sent = 0, checked = 0;

  always_ff @(posedge clk) begin
    if (valid_out) begin
      if (tests.size() == 0)
        $fatal(1, "Unexpected output %h", result);
      if (result !== tests[0].expected)
        $fatal(1, "%h (%g) %s %h (%g): expected %h (%g), got %h (%g)",
               tests[0].a, $bitstoreal(tests[0].a), tests[0].mode ? "-" : "+", tests[0].b, $bitstoreal(tests[0].b),
               tests[0].expected, $bitstoreal(tests[0].expected), result, $bitstoreal(result));
      void'(tests.pop_front());
      checked <= checked + 1;
    end
  end

  // Random normal double with exponent in [-range, range]
  function automatic logic [63:0] random_double(int range);
    int e = $urandom_range(2 * range) - range;
    return {1'($urandom), 11'(1023 + e), 20'($urandom), 32'($urandom)};
  endfunction

  task automatic send(input real x, input real y, input logic m);
    tests.push_back('{$realtobits(x), $realtobits(y), $realtobits(m ? x - y : x + y), m});
    a <= $realtobits(x);
    b <= $realtobits(y);
    mode <= m;
    valid_in <= 1;
    sent++;
    @(posedge clk);
  endtask

  initial begin
    clk = 1;
    valid_in = 0;
    mode = 0;
    @(posedge clk);

    send(1.0, 2.0, 0);
    send(10.5, 20.5, 0);
    send(4.5, 8.5, 1);
    send(-3.25, 3.25, 0);     // exact cancellation gives +0
    send(3.25, 3.25, 1);
    send(-0.0, -0.0, 0);      // -0 + -0 = -0
    send(-0.0, 0.0, 1);
    send(0.0, 5.0, 0);
    send(5.0, 0.0, 1);
    send(12289.0, -0.5, 0);
    send(1.0, 1.0e-17, 0);    // b below a's precision
    send(1.0, 1.0e-17, 1);
    send(1.0, 2.0 ** -53, 0); // ties: round to even
    send(1.0 + 2.0 ** -52, 2.0 ** -53, 0);
    send(1.0, 2.0 ** -53 + 2.0 ** -105, 0);
    send(2.0, 2.0 ** -53, 1);
    send($bitstoreal(64'h3fffffffffffffff), 2.0 ** -52, 0);  // rounding carries into the exponent

    for (int i = 0; i < RANDOM_TESTS; i++)
      send($bitstoreal(random_double(20)), $bitstoreal(random_double(20)), 1'($urandom));
    // Operands of similar magnitude (cancellation and normalization)
    for (int i = 0; i < RANDOM_TESTS; i++)
      send($bitstoreal(random_double(1)), $bitstoreal(random_double(1)), 1'($urandom));
    // Exponents up to 60 apart (alignment shifts past the guard, round and sticky bits)
    for (int i = 0; i < RANDOM_TESTS; i++)
      send($bitstoreal(random_double(30)), $bitstoreal(random_double(30)), 1'($urandom));

    valid_in <= 0;
    repeat (20) @(posedge clk);

    if (checked != sent)
      $fatal(1, "Got %0d results, expected %0d", checked, sent);
    $display("All tests for fp_adder passed! (%0d operations)", sent);
    $finish;
  end

endmodule
