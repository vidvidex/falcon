`timescale 1ns / 1ps

module double_to_int_tb;

  localparam int RANDOM_TESTS = 5000;

  logic clk;
  logic signed [14:0] int_out;
  logic [63:0] double_in;
  logic valid_in;
  logic valid_out;

  always #5 clk = ~clk;

  double_to_int double_to_int (
                  .clk(clk),
                  .double_in(double_in),
                  .valid_in(valid_in),
                  .int_out(int_out),
                  .valid_out(valid_out)
                );

  real inputs [$];
  int expected [$];
  int sent = 0, checked = 0;

  // Reference: round to nearest, ties to even (x - floor(x) is exact for |x| < 2^52)
  function automatic int round_half_even(real x);
    int f = int'($floor(x));
    real d = x - $floor(x);
    return f + ((d > 0.5 || (d == 0.5 && f % 2 != 0)) ? 1 : 0);
  endfunction

  always_ff @(posedge clk) begin
    if (valid_out) begin
      if (expected.size() == 0)
        $fatal(1, "Unexpected output %0d", int_out);
      if (int_out !== 15'(expected[0]))
        $fatal(1, "%.17g: expected %0d, got %0d", inputs[0], expected[0], int_out);
      void'(inputs.pop_front());
      void'(expected.pop_front());
      checked <= checked + 1;
    end
  end

  task automatic send(input real x);
    double_in <= $realtobits(x);
    valid_in <= 1;
    inputs.push_back(x);
    expected.push_back(round_half_even(x));
    sent++;
    @(posedge clk);
  endtask

  initial begin
    clk = 1;
    valid_in = 0;
    @(posedge clk);

    for (int i = -4; i < 4; i++) begin
      send(i);
      send(i + 0.4);
      send(i + 0.5);
      send(i + 0.6);
    end
    send(0.0);
    send(-0.0);
    send($bitstoreal(64'h3feffffffffd0500)); // just below 1
    send(0.49999999999999994);               // largest double below 0.5
    send(-0.49999999999999994);
    send(1.0e-300);
    send(12288.0);
    send(-12288.0);
    send(12288.5);
    send(16383.4);
    send(-16383.4);

    // Random values in the range used by Falcon (|x| < 2^14)
    for (int i = 0; i < RANDOM_TESTS; i++)
      send(($urandom_range(32'hffff_fffe) / 4294967295.0 - 0.5) * 32760.0);

    valid_in <= 0;
    repeat (5) @(posedge clk);

    if (checked != sent)
      $fatal(1, "Got %0d results, expected %0d", checked, sent);
    $display("All tests for double_to_int passed! (%0d values)", sent);
    $finish;
  end

endmodule
