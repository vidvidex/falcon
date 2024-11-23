`timescale 1ns / 1ps

module compress_coefficient_tb;

  logic [11:0] coefficient;
  logic [23:0] compressed_coefficient;
  logic [4:0] compressed_coefficient_length;

  compress_coefficient uut (
                         .coefficient(coefficient),
                         .compressed_coefficient(compressed_coefficient),
                         .compressed_coefficient_length(compressed_coefficient_length)
                       );

  // Helper task for tests
  task assert_result;
    input [11:0] expected_compressed_coefficient;
    input [4:0] expected_compressed_coefficient_length;

    logic  [23:0] compressed_coefficient_shifted;

    // Because the compressed coefficient is variable length we shift it to the right to be able to compare it with the expected value
    compressed_coefficient_shifted = compressed_coefficient >> 24-compressed_coefficient_length;

    begin
      if (compressed_coefficient_shifted !== expected_compressed_coefficient)
      begin
        $display("ASSERTION FAILED: Expected compressed coefficient %d, got %d", expected_compressed_coefficient, compressed_coefficient_shifted);
        $fatal;
      end
      if (compressed_coefficient_length !== expected_compressed_coefficient_length)
      begin
        $display("ASSERTION FAILED: Expected compressed_coefficient_length %d, got %d", expected_compressed_coefficient_length, compressed_coefficient_length);
        $fatal;
      end
      $display("Test passed with compressed coefficient = %d, compressed_coefficient_length = %d", compressed_coefficient_shifted, compressed_coefficient_length);
    end
  endtask

  initial
  begin

    // Positive coefficient
    coefficient = 113;
    #10;
    assert_result(12'b011100011, 9);

    // Negative coefficient
    coefficient = -137;
    #10;
    assert_result(13'b1000100101, 10);

    $display("All tests for compress_coefficient passed!");
    $finish;
  end


endmodule
