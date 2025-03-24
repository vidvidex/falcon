`timescale 1ns / 1ps

module decompress_coefficient_tb;

  logic clk;
  logic rst_n;

  logic [104:0] compressed_signature;
  logic [6:0] valid_bits;

  logic [14:0] coefficient;
  logic [6:0] bits_used;
  logic coefficient_valid;
  logic invalid_bits_used_error;
  logic cannot_find_high_error;
  logic invalid_zero_representation_error;

  decompress_coefficient uut (
                           .clk(clk),
                           .rst_n(rst_n),

                           .compressed_signature(compressed_signature),
                           .valid_bits(valid_bits),

                           .coefficient(coefficient),
                           .bits_used(bits_used),
                           .coefficient_valid(coefficient_valid),
                           .invalid_bits_used_error(invalid_bits_used_error),
                           .cannot_find_high_error(cannot_find_high_error),
                           .invalid_zero_representation_error(invalid_zero_representation_error)
                         );


  task check(
      int test_num,
      logic signed [14:0] expected_coefficient,
      logic [6:0] expected_bits_used,
      logic expected_coefficient_valid,
      logic expected_invalid_bits_used_error,
      logic expected_cannot_find_high_error,
      logic invalid_zero_representation_error
    );

    if(coefficient != expected_coefficient)
      $fatal(1, "Test %d failed: Expected coefficient %d, got %d", test_num, expected_coefficient, coefficient);
    else if(bits_used != expected_bits_used)
      $fatal(1, "Test %d failed: Expected bits_used %d, got %d", test_num, expected_bits_used, bits_used);
    else if(coefficient_valid != expected_coefficient_valid)
      $fatal(1, "Test %d failed: Expected coefficient_valid %d, got %d", test_num, expected_coefficient_valid, coefficient_valid);
    else if(invalid_bits_used_error != expected_invalid_bits_used_error)
      $fatal(1, "Test %d failed: Expected invalid_bits_used_error %d, got %d", test_num, expected_invalid_bits_used_error, invalid_bits_used_error);
    else if(cannot_find_high_error != expected_cannot_find_high_error)
      $fatal(1, "Test %d failed: Expected cannot_find_high_error %d, got %d", test_num, expected_cannot_find_high_error, cannot_find_high_error);
    else if(invalid_zero_representation_error != invalid_zero_representation_error)
      $fatal(1, "Test %d failed: Expected invalid_zero_representation_error %d, got %d", test_num, invalid_zero_representation_error, invalid_zero_representation_error);
    else
      $display("Test %d passed", test_num);
  endtask

  always #5 clk = ~clk;

  initial begin
    clk = 1;

    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #30;    // Intentionally long delay, so we see nothing happens before we have any valid bits

    // Test 1: Positive coefficient
    compressed_signature = {10'b0001011101, 95'b0};
    valid_bits = 10;
    #10;
    while(coefficient_valid == 1'b0 && invalid_bits_used_error == 1'b0 && cannot_find_high_error == 1'b0 && invalid_zero_representation_error == 1'b0)
      #10;
    check(1, 151, 10, 1, 0, 0, 0);

    rst_n = 0;
    #10;
    rst_n = 1;

    // Test 2: Negative coefficient
    compressed_signature = {10'b1001110001, 95'b0};
    valid_bits = 10;
    #10;
    while(coefficient_valid == 1'b0 && invalid_bits_used_error == 1'b0 && cannot_find_high_error == 1'b0 && invalid_zero_representation_error == 1'b0)
      #10;
    check(2, -156, 10, 1, 0, 0, 0);

    rst_n = 0;
    #10;
    rst_n = 1;

    // Test 3: Many cycles to find high bit
    compressed_signature = 105'b0_0000000_0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001;
    valid_bits = 105;
    #10;
    while(coefficient_valid == 1'b0 && invalid_bits_used_error == 1'b0 && cannot_find_high_error == 1'b0 && invalid_zero_representation_error == 1'b0)
      #10;
    check(3, 12288, 105, 1, 0, 0, 0);

    rst_n = 0;
    #10;
    rst_n = 1;

    // Test 4: Used invalid bits
    compressed_signature = {10'b1001110001, 95'b0};
    valid_bits = 5; // Only 5 bits are valid, but we'll need 10
    #10;
    while(coefficient_valid == 1'b0 && invalid_bits_used_error == 1'b0 && cannot_find_high_error == 1'b0 && invalid_zero_representation_error == 1'b0)
      #10;
    check(4, -156, 10, 0, 1, 0, 0);

    rst_n = 0;
    #10;
    rst_n = 1;

    // Test 5: Cannot find high bit
    compressed_signature = 105'b0_0000000_0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
    valid_bits = 105;
    #10;
    while(coefficient_valid == 1'b0 && invalid_bits_used_error == 1'b0 && cannot_find_high_error == 1'b0 && invalid_zero_representation_error == 1'b0)
      #10;
    check(5, 0, 0, 0, 0, 1, 0);

    rst_n = 0;
    #10;
    rst_n = 1;

    // Test 6: Correct representation of zero
    compressed_signature = {9'b000000001, 96'b0};
    valid_bits = 9;
    #10;
    while(coefficient_valid == 1'b0 && invalid_bits_used_error == 1'b0 && cannot_find_high_error == 1'b0 && invalid_zero_representation_error == 1'b0)
      #10;
    check(6, 0, 9, 1, 0, 0, 0);

    rst_n = 0;
    #10;
    rst_n = 1;

    // Test 7: Incorrect representation of zero
    compressed_signature = {9'b100000001, 96'b0};
    valid_bits = 9;
    #10;
    while(coefficient_valid == 1'b0 && invalid_bits_used_error == 1'b0 && cannot_find_high_error == 1'b0 && invalid_zero_representation_error == 1'b0)
      #10;
    check(7, 0, 9, 0, 0, 0, 1);

    $display("All tests for decompress_coefficient passed!");
    $finish;
  end

endmodule
