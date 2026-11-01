`timescale 1ns / 1ps
`include "common_definitions.vh"

// Replays SamplerZ calls recorded from a full sign512 simulation and checks that the results are identical.
// mem/tb/samplerz_512.hex: {restart (4 bits), mu1, mu2, isigma, result1, result2} (doubles).
module samplerz_tb;

  parameter int N = 512;
  localparam int CALLS = 64;

  logic clk;
  logic rst_n;

  logic restart;
  logic start;
  logic done;

  logic [127:0] seed_a, seed_b, seed_a_i, seed_b_i;
  logic [127:0] seed [4] = '{default: 128'h11111111111111111111111111111111};

  logic [63:0] mu1, mu2, isigma;
  logic [63:0] result1, result2;

  logic [1:0] seed_offset_a;
  logic [1:0] seed_offset_b;

  logic [323:0] calls [CALLS];

  samplerz #(.N(N)) samplerz (
                .clk(clk),
                .rst_n(rst_n),
                .start(start),
                .restart(restart),

                .mu1(mu1),
                .mu2(mu2),
                .isigma(isigma),

                .seed_offset_a(seed_offset_a),
                .seed_bram_dout_a(seed_a),
                .seed_offset_b(seed_offset_b),
                .seed_bram_dout_b(seed_b),

                .result1(result1),
                .result2(result2),
                .done(done)
              );

  // The seed is read from BRAM, which has a read latency of 2 cycles
  always_ff @(posedge clk) begin
    seed_a_i <= seed[seed_offset_a];
    seed_b_i <= seed[seed_offset_b];
    seed_a <= seed_a_i;
    seed_b <= seed_b_i;
  end

  always #5 clk = ~clk;

  initial begin
    logic [63:0] expected1, expected2;
    int cycles;

    $readmemh({`FALCON_MEM_DIR, "/tb/samplerz_512.hex"}, calls);

    clk = 1;
    start = 0;
    restart = 0;
    mu1 = 0;
    mu2 = 0;
    isigma = 0;

    rst_n = 0;
    repeat (2) @(posedge clk);
    rst_n <= 1;
    repeat (100) @(posedge clk);  // start must come at least 90 cycles after reset

    for (int i = 0; i < CALLS; i++) begin
      if ($isunknown(calls[i]))
        $fatal(1, "Recorded call %0d missing from samplerz_512.hex", i);
      restart <= calls[i][323:320] != 0;
      {mu1, mu2, isigma} <= calls[i][319:128];
      expected1 = calls[i][127:64];
      expected2 = calls[i][63:0];
      start <= 1;
      @(posedge clk);
      start <= 0;
      restart <= 0;

      cycles = 0;
      do begin
        @(posedge clk);
        if (++cycles > 10000)
          $fatal(1, "Call %0d: samplerz did not finish", i);
      end while (done !== 1'b1);

      if (result1 !== expected1 || result2 !== expected2)
        $fatal(1, "Call %0d (mu1 %g, mu2 %g, isigma %g): expected %g, %g, got %g, %g", i,
               $bitstoreal(mu1), $bitstoreal(mu2), $bitstoreal(isigma),
               $bitstoreal(expected1), $bitstoreal(expected2), $bitstoreal(result1), $bitstoreal(result2));

      @(posedge clk);
    end

    $display("All tests for samplerz passed! (%0d calls)", CALLS);
    $finish;
  end

endmodule
