`timescale 1ns / 1ps
`include "common_definitions.vh"

// Compares fft_butterfly_add_stage bit for bit against the simulator's IEEE-754 double arithmetic:
//   a_p_b = (a + b) * 2^scale_factor, a_m_b = a - b
module fft_butterfly_add_stage_tb;

  localparam int RANDOM_TESTS = 2000;

  logic clk;
  logic valid_in, valid_out;
  logic [63:0] a_real, a_imag, b_real, b_imag;
  logic [63:0] a_p_b_real, a_p_b_imag, a_m_b_real, a_m_b_imag;
  logic signed [4:0] scale_factor;

  always #5 clk = ~clk;

  fft_butterfly_add_stage uut(
                            .clk(clk),
                            .valid_in(valid_in),
                            .a_real(a_real),
                            .a_imag(a_imag),
                            .b_real(b_real),
                            .b_imag(b_imag),
                            .scale_factor(scale_factor),
                            .a_p_b_real(a_p_b_real),
                            .a_p_b_imag(a_p_b_imag),
                            .a_m_b_real(a_m_b_real),
                            .a_m_b_imag(a_m_b_imag),
                            .valid_out(valid_out)
                          );

  typedef struct {
    logic [63:0] apb_re, apb_im, amb_re, amb_im;
  } expected_t;

  expected_t expected [$];
  int sent = 0, checked = 0;

  task automatic check(string name, logic [63:0] got, logic [63:0] exp);
    if (got !== exp)
      $fatal(1, "Output %0d, %s: expected %h (%g), got %h (%g)", checked, name, exp, $bitstoreal(exp), got, $bitstoreal(got));
  endtask

  always_ff @(posedge clk) begin
    if (valid_out) begin
      if (expected.size() == 0)
        $fatal(1, "Unexpected output");
      check("a+b real", a_p_b_real, expected[0].apb_re);
      check("a+b imag", a_p_b_imag, expected[0].apb_im);
      check("a-b real", a_m_b_real, expected[0].amb_re);
      check("a-b imag", a_m_b_imag, expected[0].amb_im);
      void'(expected.pop_front());
      checked <= checked + 1;
    end
  end

  function automatic real random_double(int range);
    int e = $urandom_range(2 * range) - range;
    return $bitstoreal({1'($urandom), 11'(1023 + e), 20'($urandom), 32'($urandom)});
  endfunction

  task automatic send(real ar, real ai, real br, real bi, int scale);
    expected_t e;
    real s = 2.0 ** scale;
    e.apb_re = $realtobits((ar + br) * s);
    e.apb_im = $realtobits((ai + bi) * s);
    e.amb_re = $realtobits(ar - br);
    e.amb_im = $realtobits(ai - bi);
    expected.push_back(e);
    a_real <= $realtobits(ar);
    a_imag <= $realtobits(ai);
    b_real <= $realtobits(br);
    b_imag <= $realtobits(bi);
    scale_factor <= scale;
    valid_in <= 1;
    sent++;
    @(posedge clk);
  endtask

  task automatic drain();
    valid_in <= 0;
    while (expected.size() != 0)
      @(posedge clk);
    repeat (3) @(posedge clk);
  endtask

  initial begin
    clk = 1;
    valid_in = 0;
    scale_factor = 0;
    @(posedge clk);

    send(1.0, 1.0, 2.0, 2.0, 0);
    send(5.0, 6.0, 7.0, 8.0, 0);
    for (int i = 0; i < RANDOM_TESTS; i++)
      send(random_double(10), random_double(10), random_double(10), random_double(10), 0);
    drain();

    for (int scale = -1; scale >= -9; scale -= 4) begin
      scale_factor <= scale;
      @(posedge clk);
      send(5.0, 6.0, 7.0, 8.0, scale);
      send(3.0, -3.0, -3.0, 3.0, scale);
      for (int i = 0; i < RANDOM_TESTS; i++)
        send(random_double(10), random_double(10), random_double(10), random_double(10), scale);
      drain();
    end

    valid_in <= 0;
    repeat (20) @(posedge clk);

    if (checked != sent)
      $fatal(1, "Got %0d results, expected %0d", checked, sent);
    $display("All tests for fft_butterfly_add_stage passed! (%0d operations)", sent);
    $finish;
  end

endmodule
