`timescale 1ns / 1ps

module ntt_negative_tb;

  logic clk;
  logic rst_n;

  logic mode;
  logic start;
  logic signed [14:0] input_polynomial[0:7];
  logic done;
  logic [14:0] output_polynomial[0:7];

  logic [14:0] expected_output_polynomial[0:7];

  ntt_negative #(
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
    expected_output_polynomial = {10914, 5186, 3052, 6340, 6212, 9196, 9416, 11129};
    if (output_polynomial === expected_output_polynomial)
      $display("Test 1: Passed");
    else
      $display("Test 1: Failed. Expected: %p, Got: %p", expected_output_polynomial, output_polynomial);

    // Test 2: INTT of polynomial size 8
    rst_n = 0;
    #10;
    rst_n = 1;
    mode = 1;
    input_polynomial = {10914, 5186, 3052, 6340, 6212, 9196, 9416, 11129};

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
      $display("Test 2: Failed. Expected: %p, Got: %p", expected_output_polynomial, output_polynomial);


    // Test 3: NTT with bigger numbers
    rst_n = 0;
    #10;
    rst_n = 1;
    mode = 0;
    input_polynomial = {7644, 6589, 8565, 4185, 1184, 607, 3842, 5361};

    // Start NTT
    start = 1;
    #10;
    start = 0;

    // Wait for NTT to finish
    while (!done)
      #10;

    // Check output
    expected_output_polynomial = {5550, 7668, 5033, 222, 2053, 777, 6055, 9216};
    if (output_polynomial === expected_output_polynomial)
      $display("Test 3: Passed");
    else
      $display("Test 3: Failed. Expected: %p, Got: %p", expected_output_polynomial, output_polynomial);


    // Test 4: NTT with negative coefficients
    rst_n = 0;
    #10;
    rst_n = 1;
    mode = 0;
    input_polynomial = {-153,-108,143,-216,-49,222,81,152};

    // Start NTT
    start = 1;
    #10;
    start = 0;

    // Wait for NTT to finish
    while (!done)
      #10;

    // Check output
    expected_output_polynomial = {2598, 1143, 7769, 7404, 5910, 11731, 1017, 10360};
    if (output_polynomial === expected_output_polynomial)
      $display("Test 4: Passed");
    else
      $display("Test 4: Failed. Expected: %p, Got: %p", expected_output_polynomial, output_polynomial);

    $finish;
  end

endmodule
