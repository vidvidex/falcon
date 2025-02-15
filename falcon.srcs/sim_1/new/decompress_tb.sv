`timescale 1ns / 1ps

module decompress_tb;
  logic clk;
  logic rst_n;
  logic [191:0] compressed_signature, shifted_compressed_signature; //! 192 bytes for signature in order to have enough space for testing the case when the signature is too long. These signatures are generated with key size 8.
  logic [6:0] compressed_signature_valid_bits;  // Number of valid bits in the compressed signature that is passed to the decompress module
    int compressed_signature_valid_bits_total, compressed_signature_valid_bits_initial;  // Total and initial number of valid bits in compressed signature
  logic [14:0] expected_coefficients [0:7];
  logic [6:0] compressed_coef_length;
  logic decompression_done;
  logic signature_error;
  logic [14:0] coefficient;
  logic coefficient_valid;
  int i;
  int expected_signature_length_bytes;  //! How many bytes long is the signature we expect to be
  int expected_coefficient_count;    //! How many coefficients we expect to get from the compressed signature

  decompress #(
               .N(8),
               .SIGNATURE_LENGTH(192)
             )
             uut (
               .clk(clk),
               .rst_n(rst_n),
               .compressed_signature(compressed_signature[191:87]),
               .compressed_signature_valid_bits(compressed_signature_valid_bits),
               .expected_signature_length_bytes(expected_signature_length_bytes),
               .compressed_coef_length(compressed_coef_length),
               .signature_error(signature_error),
               .decompression_done(decompression_done),
               .coefficient(coefficient),
               .coefficient_valid(coefficient_valid)
             );

  always #5 clk = ~clk;

  // Shift compressed_signature to the left by "compressed_coef_length" bits to get the next compressed coefficient
  always_ff @ (posedge clk) begin

    // If compressed_signature_valid_bits_initial is set, we use it to initialize compressed_signature_valid_bits_total
    if (compressed_signature_valid_bits_initial > 0 )
      compressed_signature_valid_bits_total <= compressed_signature_valid_bits_initial;
    else if (rst_n == 1'b0)
      compressed_signature_valid_bits_total <= 0;
    else if (coefficient_valid == 1'b1) begin
      shifted_compressed_signature <= compressed_signature << compressed_coef_length;
      compressed_signature_valid_bits_total <=  compressed_signature_valid_bits_total - compressed_coef_length;
    end
  end
  assign compressed_signature = shifted_compressed_signature; // We need this because we cannot directly assign to compressed_signature in the always_ff block

  // Limit the number of valid bits in the compressed signature to 104
  assign compressed_signature_valid_bits = compressed_signature_valid_bits_total > 104 ? 104 : compressed_signature_valid_bits_total;

  initial begin
    clk = 1;

    // Test 1: Real signature of size 8

    expected_signature_length_bytes = 11;
    expected_coefficient_count = 8;
    compressed_signature = {'h1767151d8254a265f4a800, 'h00000000000000000000000000};
    compressed_signature_valid_bits_initial = 0;

    expected_coefficients[0] = 15'b000000010010111;
    expected_coefficients[1] = 15'b100000010011100;
    expected_coefficients[2] = 15'b000000001010001;
    expected_coefficients[3] = 15'b100000010110000;
    expected_coefficients[4] = 15'b000000010101010;
    expected_coefficients[5] = 15'b000000001000100;
    expected_coefficients[6] = 15'b100000000010111;
    expected_coefficients[7] = 15'b100000010100101;

    rst_n = 0;
    #10;
    rst_n = 1;
    #20;
    compressed_signature_valid_bits_initial = 88; // Start decompression

    for (i = 0; i < expected_coefficient_count; i = i + 1) begin
      #10;
      compressed_signature_valid_bits_initial = 0; // Reset initialization
      if (expected_coefficients[i] !== coefficient) begin
        $display("ASSERTION FAILED: Expected coefficient %x, got %x", expected_coefficients[i], coefficient);
        $fatal;
      end
      if (coefficient_valid !== 1) begin
        $display("ASSERTION FAILED: Coefficient at index %d is not marked as valid", i);
        $fatal;
      end
    end
    #10;
    // Check coefficient_valid is low after the last coefficient is processed
    if (coefficient_valid !== 0) begin
      $display("ASSERTION FAILED: Coefficient valid is not low after the last coefficient is processed");
      $fatal;
    end

    // Run decompression until the end of the signature
    while (decompression_done === 0)
      #10;
    // Check if signature_error is low (the entire signature was processed successfully)
    if (signature_error !== 0) begin
      $display("ASSERTION FAILED: Signature error detected");
      $fatal;
    end

    $display("Test 1 passed!");

    // Test 2: Signature too long

    expected_signature_length_bytes = 11;
    expected_coefficient_count = 8;
    compressed_signature = 'h000001000001000001000001000001000001000001000001; // Very long representation for each of the signatures, more than the 11B we expect

    expected_coefficients[0] = 15'b000_0111_1000_0000;
    expected_coefficients[1] = 15'b000_0111_1000_0000;
    expected_coefficients[2] = 15'b000_0111_1000_0000;
    expected_coefficients[3] = 15'b000_0111_1000_0000;
    expected_coefficients[4] = 15'b000_0111_1000_0000;
    expected_coefficients[5] = 15'b000_0111_1000_0000;
    expected_coefficients[6] = 15'b000_0111_1000_0000;
    expected_coefficients[7] = 15'b000_0111_1000_0000;

    rst_n = 0;
    #20;
    rst_n = 1;
    #20;
    compressed_signature_valid_bits_initial = 192;  // Start decompression

    for (i = 0; i < expected_coefficient_count; i = i + 1) begin
      #10;
      compressed_signature_valid_bits_initial = 0; // Reset initialization
      if (expected_coefficients[i] !== coefficient) begin
        $display("ASSERTION FAILED: Expected coefficient %x, got %x", expected_coefficients[i], coefficient);
        $fatal;
      end
      if (coefficient_valid !== 1) begin
        $display("ASSERTION FAILED: Coefficient at index %d is not marked as valid", i);
        $fatal;
      end

      // At coefficient 5 we process more bits than expected and should detect an error
      if(i == 5 && signature_error !== 1) begin
        $display("ASSERTION FAILED: Signature error not detected");
        $fatal;
      end
    end

    $display("Test 2 passed!");

    $display("All tests for decompress passed!");
    $finish;
  end

endmodule
