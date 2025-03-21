`timescale 1ns / 1ps

module decompress_tb;
  logic clk;
  logic rst_n;

  parameter int N = 8;
  parameter int SLEN = 11;

  logic [191:0] compressed_signature;

  logic signed [14:0] decompressed_polynomial [N];
  logic signed [14:0] expected_polynomial [N];
  logic [6:0] compressed_signature_valid_bits, shift_by;
  logic decompression_done;

  int valid_bits;
  int index;

  decompress #(
               .N(N),
               .SLEN(SLEN)
             )
             uut (
               .clk(clk),
               .rst_n(rst_n),

               .compressed_signature(compressed_signature[191:87]),
               .valid_bits(compressed_signature_valid_bits),

               .shift_by(shift_by),
               .polynomial(decompressed_polynomial),
               .decompression_done(decompression_done),
               .signature_error(signature_error)
             );

  always #5 clk = ~clk;

  // // Limit the number of valid bits in the compressed signature to 104
  assign compressed_signature_valid_bits = valid_bits > 104 ? 104 : valid_bits;

  initial begin
    clk = 1;

    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #30;  // Intentionally long delay, so we see nothing happens before we have any valid bits

    // Test 1: Real signature of size 8
    compressed_signature = {'h1767151d8254a265f4a800, 'h00000000000000000000000000};
    valid_bits = 88;
    expected_polynomial = '{151, -156, 81, -176, 170, 68, -23, -165};

    while(decompression_done == 1'b0 && signature_error == 1'b0) begin
      #10;
      // Prepare for the next iteration
      compressed_signature = compressed_signature << shift_by;
      valid_bits = valid_bits - shift_by;
    end

    // Check output
    for(int i = 0; i < N; i = i + 1)
      if(decompressed_polynomial[i] != expected_polynomial[i])
        $fatal("Test 1: Expected coefficient %d, got %d", expected_polynomial[i], decompressed_polynomial[i]);
    if(signature_error == 1'b1)
      $fatal("Test 1: Signature error detected");

    $display("Test 1 passed!");


    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;

    // Test 2: Signature too long
    compressed_signature = 'h000001000001000001000001000001000001000001000001; // Very long representation for each of the signatures, more than the 11B we expect
    valid_bits = 192;
    expected_polynomial = '{1920, 1920, 1920, 1920, 1920, 1920, 1920, 1920};

    while(decompression_done == 1'b0 && signature_error == 1'b0) begin
      #10;
      // Prepare for the next iteration
      compressed_signature = compressed_signature << shift_by;
      valid_bits = valid_bits - shift_by;
    end

    // Check output
    if(signature_error == 0)
      $fatal("Test 2: Signature error not detected");

    $display("Test 2 passed!");

    // Reset
    rst_n = 0;
    #10;
    rst_n = 1;
    #10;


    $display("All tests for decompress passed!");
    $finish;
  end

endmodule
