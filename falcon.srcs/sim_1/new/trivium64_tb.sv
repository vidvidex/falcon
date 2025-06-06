`timescale 1ns / 1ps

module trivium64_tb;

  logic clk, rst;

  logic [63:0] seed;
  logic [63:0] random_out;
  logic random_valid;
  trivium64 trivium64(
              .clk(clk),
              .rst(rst),
              .seed(seed),
              .random_out(random_out),
              .random_valid(random_valid)
            );

  always #5 clk = ~clk;

  initial begin
    clk = 0;

    seed = 64'h1234567890abcdef;

    rst = 1;
    #15;
    rst = 0;

    // Wait for the random output to be valid
    wait(random_valid);
    #10;
    // Check the random output
    if (random_out !== 64'h491a4055893d23f1)
      $fatal(1, "Test failed: Expected random_out = 64'h491a4055893d23f1, got %h", random_out);

    $display("All tests for trivium64 passed!");

    $finish;

  end

endmodule
