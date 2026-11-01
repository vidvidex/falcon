`timescale 1ns / 1ps

module compress_coefficient_tb;

  logic [14:0] coefficient;
  logic [104:0] compressed_coefficient;
  logic [6:0] compressed_coefficient_length;

  compress_coefficient uut (
                         .coefficient(coefficient),
                         .compressed_coefficient(compressed_coefficient),
                         .compressed_coefficient_length(compressed_coefficient_length)
                       );

  // Helper task for tests
  task assert_result;
    input [14:0] expected_compressed_coefficient;
    input [6:0] expected_compressed_coefficient_length;

    logic [104:0] compressed_coefficient_shifted;
    // Because the compressed coefficient is variable length we shift it to the right to be able to compare it with the expected value
    compressed_coefficient_shifted = compressed_coefficient >> 105-compressed_coefficient_length;

    begin
      if (compressed_coefficient_shifted !== expected_compressed_coefficient)
        $fatal(1, "Test 1 failed: Expected compressed coefficient %x, got %x", expected_compressed_coefficient, compressed_coefficient_shifted);

      if (compressed_coefficient_length !== expected_compressed_coefficient_length)
        $fatal(1, "Test 1 failed: Expected compressed_coefficient_length %d, got %d", expected_compressed_coefficient_length, compressed_coefficient_length);

      $display("Test 1 passed with compressed coefficient = %d, compressed_coefficient_length = %d", compressed_coefficient_shifted, compressed_coefficient_length);
    end
  endtask

  initial begin

    // Positive coefficient
    coefficient = 113;
    #10;
    assert_result(9'b0_1110001_1, 9);

    // Negative coefficient
    coefficient = -137;
    #10;
    assert_result(10'b1_0001001_01, 10);

    $display("All tests for compress_coefficient passed!");
    $finish;
  end


endmodule
