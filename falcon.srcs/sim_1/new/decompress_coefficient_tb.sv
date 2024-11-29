`timescale 1ns / 1ps

module decompress_coefficient_tb;

  logic [104:0] compressed_signature;
  logic [14:0] coefficient;
  logic [6:0] compressed_coef_length;
  logic coefficient_error;

  decompress_coefficient uut (
                           .compressed_signature(compressed_signature),
                           .coefficient(coefficient),
                           .compressed_coef_length(compressed_coef_length),
                           .coefficient_error(coefficient_error)
                         );

  // Helper task for tests
  task assert_result;
    input [14:0] expected_coefficient;
    input [6:0] expected_compressed_coef_length;
    input expected_coefficient_error;
    begin
      if (coefficient !== expected_coefficient) begin
        $display("ASSERTION FAILED: Expected coefficient %x, got %x", expected_coefficient, coefficient);
        $fatal;
      end
      if (compressed_coef_length !== expected_compressed_coef_length) begin
        $display("ASSERTION FAILED: Expected compressed_coef_length %d, got %d", expected_compressed_coef_length, compressed_coef_length);
        $fatal;
      end
      if (coefficient_error !== expected_coefficient_error) begin
        $display("ASSERTION FAILED: Expected coefficient_error %d, got %d", expected_coefficient_error, coefficient_error);
        $fatal;
      end
      $display("Test passed with coefficient = %d, compressed_coef_length = %d, coefficient_error = %d", coefficient, compressed_coef_length, coefficient_error);
    end
  endtask

  initial begin
    // Positive sign, low part=2, high part=0
    compressed_signature = {105'b0_0000010_1, {96{1'b0}}};
    #10;
    assert_result(15'b000_0000_0000_0010, 9, 0);

    // Negative sign, low part=2, high part=0
    compressed_signature = {105'b1_0000010_1, {96{1'b0}}};
    #10;
    assert_result(15'b100_0000_0000_0010, 9, 0);

    // Negative sign, low part=127, high part=16
    compressed_signature = {105'b1_1111111_00000000000000001, {80{1'b0}}};
    #10;
    assert_result(15'b100_1000_0111_1111, 25, 0);

    // Positive sign, low part=0, high part=0 (valid representation of coefficient 0)
    compressed_signature = {105'b0_0000000_1, {96{1'b0}}};
    #10;
    assert_result(15'b000_0000_0000_0000, 9, 0);

    // Negative sign, low part=0, high part=0 (invalid representation of coefficient 0)
    compressed_signature = {105'b1_0000000_1, {96{1'b0}}};
    #10;
    assert_result(15'b100_0000_0000_0000, 9, 1);

    $display("All tests for decompress_coefficient passed!");
    $finish;
  end

endmodule
