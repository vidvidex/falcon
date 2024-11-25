`timescale 1ns / 1ps

module compress_tb;
  parameter integer SIGNATURE_LENGTH = 11;
  parameter integer SIGNATURE_LENGTH_WIDTH = 4;

  logic clk;
  logic rst;

  logic [11:0] coefficients [0:7];    // Coefficients to compress
  logic [11:0] coefficient;           // Next coefficient to compress
  logic valid;                        // Indicates that "coefficient" is valid and should be compressed
  logic finalize;                     // Indicats that all coefficients have been compressed and that the padding should be added
  logic [87:0] compressed_signature;  // Compressed signature containing all compressed coefficients (when done). (space for 11x8 bytes - size of signature for 8 coefficients)
  logic error;                        // Error signal, something went wrong while compressing
  integer i;                          // Loop variable

  compress #(
             .SIGNATURE_LENGTH(SIGNATURE_LENGTH),
             .SIGNATURE_LENGTH_WIDTH(SIGNATURE_LENGTH_WIDTH)
           )uut(
             .clk(clk),
             .rst(rst),
             .coefficient(coefficient),
             .valid(valid),
             .finalize(finalize),
             .compressed_signature(compressed_signature),
             .error(error)
           );

  always #5 clk = ~clk;

  initial begin
    clk = 1;

    // Test 1: Real signature of size 8
    rst = 0;
    #10;
    rst = 1;
    coefficients = {-26, -88, 50, -9, -165, -161, 189, -21};
    finalize = 0;

    // Compress all coefficients
    for (i = 0; i < 8; i++) begin
      coefficient = coefficients[i];
      valid = 1;
      #10;
    end
    finalize = 1;
    valid = 0;
    #10;
    finalize = 0;
    // Check if error is low (all coefficients were compressed successfully)
    if (error !== 0) begin
      $display("ASSERTION FAILED: Signature error detected");
      $fatal;
    end
    if(compressed_signature !== 88'h9aec4cb13a56853d656000) begin
      $display("ASSERTION FAILED: Compressed signature is not correct");
      $fatal;
    end

    // Test 2: Signature too long
    rst = 0;
    #10;
    rst = 1;
    coefficients = {12'h780, 12'h780, 12'h780, 12'h780, 12'h780, 12'h780, 12'h780, 12'h780};
    finalize = 0;

    // Compress all coefficients
    for (i = 0; i < 8; i++) begin
      coefficient = coefficients[i];
      valid = 1;
      #10;

      // When processing the 5th coefficient the signature should become too long
      if(i == 4 && error !== 1) begin
        $display("ASSERTION FAILED: Signature error not detected");
        $fatal;
      end

    end
    finalize = 1;
    valid = 0;
    #10;
    finalize = 0;
    // Check if error stays highL
    if (error !== 1) begin
      $display("ASSERTION FAILED: Signature error not detected");
      $fatal;
    end


    $display("All tests for compress passed!");
    $finish;
  end

endmodule
