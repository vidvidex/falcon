`timescale 1ns / 1ps

module ntt_positive_tb;

  logic clk;
  logic rst_n;

  logic mode;
  logic start;
  logic [14:0] input_polynomial[0:7];
  logic [14:0] twiddle_factors[0:7];
  logic done;
  logic [14:0] output_polynomial[0:7];

  logic [14:0] expected_output_polynomial[0:7];

  ntt_positive #(
                 .N(8)
               )uut(
                 .clk(clk),
                 .rst_n(rst_n),
                 .mode(mode),
                 .start(start),
                 .input_polynomial(input_polynomial),
                 .done(done),
                 .output_polynomial(output_polynomial)
               );

  always #5 clk = ~clk;

  initial begin
    clk = 1;

    // Test 1: NTT of polynomial size 8
    rst_n = 0;
    #10;
    rst_n = 1;
    mode = 0;
    input_polynomial = {0,1,2,3,4,5,6,7};

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
      $fatal("Test 1: Failed. Expected: %p, Got: %p", expected_output_polynomial, output_polynomial);

    // Test 2: INTT of polynomial size 8
    rst_n = 0;
    #10;
    rst_n = 1;
    mode = 1;
    input_polynomial = {28,10781,6369,10324,12285,1957,5912,1500};

    // Start INTT
    start = 1;
    #10;
    start = 0;

    // Wait for INTT to finish
    while (!done)
      #10;

    // Check output
    expected_output_polynomial = {0,1,2,3,4,5,6,7};
    if (output_polynomial === expected_output_polynomial)
      $display("Test 2: Passed");
    else
      $fatal("Test 2: Failed. Expected: %p, Got: %p", expected_output_polynomial, output_polynomial);

    $display("All tests for ntt_positive passed!");
    $finish;
  end

endmodule
