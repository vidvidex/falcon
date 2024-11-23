`timescale 1ns / 1ps

module decompress_tb;
  logic clk;
  logic rst;
  logic [191:0] compressed_signature; //! 192 bytes for signature in order to have enough space for testing the case when the signature is too long. These signatures are generated with key size 8.
  logic [191:0] compressed_signature_valid;
  logic [11:0] expected_coefficients [0:7];
  logic [4:0] compressed_coef_length;
  logic decompression_done;
  logic signature_error;
  logic [11:0] coefficient;
  integer i;
  integer compressed_signature_length;  //! How many bytes should the compressed signature be
  integer expected_coefficient_count;    //! How many coefficients we expect to get from the compressed signature

  decompress uut (
               .clk(clk),
               .rst(rst),
               .compressed_signature(compressed_signature[191:168]),  // Pass top 24 bits of the compressed signature
               .compressed_signature_valid(compressed_signature_valid[191:168]),
               .compressed_signature_length(compressed_signature_length),
               .compressed_coef_length(compressed_coef_length),
               .signature_error(signature_error),
               .decompression_done(decompression_done),
               .coefficient(coefficient)
             );

  always #5 clk = ~clk;

  // Shift compressed_signature to the left by "compressed_coef_length" bits to get the next compressed coefficient
  always @ (posedge clk)
  begin
    if (rst == 1'b1)
      compressed_signature <= compressed_signature << compressed_coef_length;
    compressed_signature_valid <= compressed_signature_valid << compressed_coef_length;
  end

  initial
  begin
    clk = 0;

    // Test 1: Real signature of size 8
    rst = 0;
    #10;
    rst = 1;
    compressed_signature_length = 11;
    expected_coefficient_count = 8;
    compressed_signature = {'h1767151d8254a265f4a800, 'h00000000000000000000000000};
    compressed_signature_valid = {'hffffffffffffffffffffff, 'h00000000000000000000000000};

    expected_coefficients[0] = 12'h097;
    expected_coefficients[1] = 12'h89C;
    expected_coefficients[2] = 12'h051;
    expected_coefficients[3] = 12'h8B0;
    expected_coefficients[4] = 12'h0AA;
    expected_coefficients[5] = 12'h044;
    expected_coefficients[6] = 12'h817;
    expected_coefficients[7] = 12'h8A5;

    for (i = 1; i < expected_coefficient_count; i = i + 1)
    begin
      #10;
      if (expected_coefficients[i] !== coefficient)
      begin
        $display("ASSERTION FAILED: Expected coefficient %d, got %d", expected_coefficients[i], coefficient);
        $fatal;
      end
    end
    // Run decompression until the end of the signature
    while (decompression_done === 0)
      #10;
    // Check if signature_error is low (the entire signature was processed successfully)
    if (signature_error !== 0)
    begin
      $display("ASSERTION FAILED: Signature error detected");
      $fatal;
    end


    // Test 2: Signature too long
    rst = 0;
    #20;
    rst = 1;
    compressed_signature_length = 11;
    expected_coefficient_count = 8;
    compressed_signature = 'h000001000001000001000001000001000001000001000001; // Maximum length representation for each of the signatures, total length is 24B, but we only expect 11B
    compressed_signature_valid = 'hffffffffffffffffffffffffffffffffffffffffffffffff;

    expected_coefficients[0] = 12'h780;
    expected_coefficients[1] = 12'h780;
    expected_coefficients[2] = 12'h780;
    expected_coefficients[3] = 12'h780;
    expected_coefficients[4] = 12'h780;
    expected_coefficients[5] = 12'h780;
    expected_coefficients[6] = 12'h780;
    expected_coefficients[7] = 12'h780;

    for (i = 1; i < expected_coefficient_count; i = i + 1)
    begin
      #10;
      if (expected_coefficients[i] !== coefficient)
      begin
        $display("ASSERTION FAILED: Expected coefficient %d, got %d", expected_coefficients[i], coefficient);
        $fatal;
      end

      // At coefficient 5 we process more bits than expected and should detect an error
      if(i == 5 && signature_error !== 1)
      begin
        $display("ASSERTION FAILED: Signature error not detected");
        $fatal;
      end
    end


    $display("All tests for decompress passed!");
    $finish;
  end

endmodule
