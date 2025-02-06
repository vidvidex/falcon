`timescale 1ns / 1ps

module ntt_tb;

  logic clk;
  logic rst_n;

  logic start;
  logic [14:0] input_polynomial[0:7];
  logic [14:0] twiddle_factors[0:7];
  logic done;
  logic [14:0] output_polynomial[0:7];

  logic [14:0] expected_output_polynomial[0:7];

  ntt #(
        .N(8)
      )uut(
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .input_polynomial(input_polynomial),
        .done(done),
        .output_polynomial(output_polynomial)
      );

  always #5 clk = ~clk;

  initial begin
    clk = 1;

    // Test 1: Polynomial of size 8
    rst_n = 0;
    #10;
    rst_n = 1;
    input_polynomial = {0,1,2,3,4,5,6,7};
    start = 0;

    // Start NTT
    start = 1;
    #10;
    start = 0;

    // Wait for NTT to finish
    while (!done)
      #10;

    // Check output
    expected_output_polynomial = {28,10781,6369,10324,12285,1957,5912,1500};
    if (output_polynomial === expected_output_polynomial)
      $display("Test 1: Passed");
    else
      $display("Test 1: Failed");

    $finish;
  end

endmodule

