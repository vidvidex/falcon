`timescale 1ns / 1ps

module decompress_coefficient_tb;

  logic [23:0] compressed_signature;
  logic [11:0] coefficient;
  logic [4:0] compressed_coef_length;
  logic coefficient_error;

  decompress_coefficient uut (
               .compressed_signature(compressed_signature),
               .coefficient(coefficient),
               .compressed_coef_length(compressed_coef_length),
               .coefficient_error(coefficient_error)
             );

  // Helper task for tests
  task assert_result;
    input [11:0] expected_coefficient;
    input [4:0] expected_compressed_coef_length;
    input expected_coefficient_error;
    begin
      if (coefficient !== expected_coefficient)
      begin
        $display("ASSERTION FAILED: Expected coefficient %d, got %d", expected_coefficient, coefficient);
        $fatal;
      end
      if (compressed_coef_length !== expected_compressed_coef_length)
      begin
        $display("ASSERTION FAILED: Expected compressed_coef_length %d, got %d", expected_compressed_coef_length, compressed_coef_length);
        $fatal;
      end
      if (coefficient_error !== expected_coefficient_error)
      begin
        $display("ASSERTION FAILED: Expected coefficient_error %d, got %d", expected_coefficient_error, coefficient_error);
        $fatal;
      end
      $display("Test passed with coefficient = %d, compressed_coef_length = %d, coefficient_error = %d", coefficient, compressed_coef_length, coefficient_error);
    end
  endtask

  initial
  begin

    // Positive sign, low part=2, high part=0
    compressed_signature = 24'b0_0000010_1__000000000000000;
    #10;
    assert_result(12'b0000_0000_0010, 9, 0);

    // Negative sign, low part=2, high part=0
    compressed_signature = 24'b1_0000010_1__000000000000000;
    #10;
    assert_result(12'b1000_0000_0010, 9, 0);

    // Negative sign, low part=127, high part=15
    compressed_signature = 24'b1_1111111_0000000000000001;
    #10;
    assert_result(12'b1111_1111_1111, 24, 0);

    // Positive sign, low part=0, high part=0 (valid representation of coefficient 0)
    compressed_signature = 24'b0_0000000_1__000000000000000;
    #10;
    assert_result(12'b0000_0000_0000, 9, 0);

    // Negative sign, low part=0, high part=0 (invalid representation of coefficient 0)
    compressed_signature = 24'b1_0000000_1__000000000000000;
    #10;
    assert_result(12'b1000_0000_0000, 9, 1);

    // Real-world input data
    compressed_signature = 24'b0_0000010_1_100001111110010;
    #10;
    assert_result(12'b0000_0000_0010, 9, 0);

    $display("All tests for decompress_coefficient passed!");
    $finish;
  end

endmodule
