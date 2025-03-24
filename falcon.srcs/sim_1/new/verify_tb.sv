`timescale 1ns / 1ps

module verify_tb;

  logic clk;
  logic rst_n;

  logic start;

  logic [63:0] message_blocks [7];   // Buffer for signature salt and message blocks (first 40B (5 blocks) are salt, the rest is the message)
  logic [63:0] signature_blocks [2];   // Buffer for signature value blocks (without salt)
  logic [6:0] signature_valid_blocks [2];   // Buffer for signature value valid blocks

  logic signed [14:0] public_key[8] = {7644, 6589, 8565, 4185, 1184, 607, 3842, 5361};

  logic [15:0] message_len_bytes; //! Length of the message in bytes (without salt)
  logic [63:0] message;
  logic message_valid; //! Is message valid
  logic message_last; //! Is this the last block of message
  logic message_ready; //! Is ready to receive the next message

  logic [63:0] signature;
  logic [6:0] signature_valid; //! Number of valid bits in signature (from the left)
  logic signature_ready; //! Is ready to receive the next signature block

  logic accept; //! Set to true if signature is valid
  logic reject; //! Set to true if signature is invalid

  int message_block_index = 0;
  int signature_block_index = 0;

  verify #(
           .N(8),
           .SBYTELEN(52)
         )uut(
           .clk(clk),
           .rst_n(rst_n),

           .start(start),

           .public_key(public_key),
           .public_key_valid(1'b1),

           .message_len_bytes(message_len_bytes),
           .message(message),
           .message_valid(message_valid),
           .message_last(message_last),
           .message_ready(message_ready),

           .signature(signature),
           .signature_valid(signature_valid),
           .signature_ready(signature_ready),

           .accept(accept),
           .reject(reject)
         );

  always_ff @(posedge clk) begin

    if(rst_n == 1'b0) begin
      message_block_index <= 0;
      signature_block_index <= 0;
    end

    if(!accept && !reject) begin

      // Send new message block if module is ready for it
      if (message_ready && message_block_index < 7) begin
        message <= message_blocks[message_block_index];
        message_valid <= 1;
        message_block_index <= message_block_index + 1;
      end
      else if (message_block_index >= 7)  // Set valid to low after we've sent all message blocks
        message_valid <= 0;
      message_last <= message_block_index == 6;

      // Send new signature block if module is ready for it
      if(signature_ready && signature_block_index < 2) begin
        signature <= signature_blocks[signature_block_index];
        signature_valid <= signature_valid_blocks[signature_block_index];
        signature_block_index <= signature_block_index + 1;
      end
      else
        signature_valid <= 0; // Set valid to low after we've sent all signature value blocks
    end

  end


  always #5 clk = ~clk;

  initial begin
    clk = 1;

    //////////////////////////////////////////////////////////////////////////////////
    // Test 1: Valid signature for N=8
    //
    // Debugging help:
    // After sending both salt and message the valid polynomial should be
    // [1112, 5539, 5209, 3423, 2324, 1901, 12163, 9202] (signed decimal)
    //
    // After sending the valid decompressed signature should be
    // [[-153, -108, 143, -216, -49, 222, 81, 152]] (signed decimal)
    //////////////////////////////////////////////////////////////////////////////////

    message_len_bytes <= 12; // len("Hello World!") = 12
    // First 5 blocks of message are the salt (40B), the rest is the message ("Hello World!", reversed and with padding)
    message_blocks <= {64'h8ae56efee299dd5d, 64'h0ddf5a76484a58c2, 64'he5c9678b2d3ccf73, 64'haeb69f7b17f6be7d, 64'h0bdfb438301f6d76, 64'h6f57206f6c6c6548, 64'h0000000021646c72};

    // len(signature value) = 11 bytes = 88 bits = 64 + 24
    signature_blocks <= {64'h997b21eec3635e54, 64'h6308000000000000};
    signature_valid_blocks <= '{64, 24};

    rst_n <= 0;
    #10;
    rst_n <= 1;
    start <= 1;
    #10;
    start <= 0;

    while(!reject && !accept)
      #10;

    if (accept == 1'b1 && reject == 1'b0)
      $display("Test 1: Passed");
    else
      $fatal(1, "Test 1: Failed. Expected accept to be 1 and reject to be 0. Got: accept=%d, reject=%d", accept, reject);


    //////////////////////////////////////////////////////////////////////////////////
    // Test 2: Invalid signature for N=8 (same values as in test 1 but signature is corrupted)
    //////////////////////////////////////////////////////////////////////////////////

    message_len_bytes <= 12; // len("Hello World!") = 12
    // First 5 blocks of message are the salt (40B), the rest is the message ("Hello World!", reversed and with padding)
    message_blocks <= {64'h8ae56efee299ddaa, 64'h0ddf5a76484a58c2, 64'he5c9678b2d3ccf73, 64'haeb69f7b17f6be7d, 64'h0bdfb438301f6d76, 64'h6f57206f6c6c6548, 64'h0000000021646c72}; // Last byte of first block should be '5d' but changed to 'aa' to make it invalid

    // len(signature value) = 11 bytes = 88 bits = 64 + 24
    signature_blocks <= {64'h997b21eec3635e54, 64'h6308000000000000};
    signature_valid_blocks <= '{64, 24};

    rst_n <= 0;
    #20;
    rst_n <= 1;
    start <= 1;
    #10;
    start <= 0;

    while(!reject && !accept)
      #10;

    if (accept == 1'b0 && reject == 1'b1)
      $display("Test 2: Passed");
    else
      $fatal(1, "Test 2: Failed. Expected accept to be 0 and reject to be 1. Got: accept=%d, reject=%d", accept, reject);


    //////////////////////////////////////////////////////////////////////////////////
    // Test 3: Incorrectly compressed coefficients in signature
    //////////////////////////////////////////////////////////////////////////////////

    message_len_bytes <= 12; // len("Hello World!") = 12
    // First 5 blocks of message are the salt (40B), the rest is the message ("Hello World!", reversed and with padding)
    message_blocks <= {64'h8ae56efee299dd5d, 64'h0ddf5a76484a58c2, 64'he5c9678b2d3ccf73, 64'haeb69f7b17f6be7d, 64'h0bdfb438301f6d76, 64'h6f57206f6c6c6548, 64'h0000000021646c72};

    signature_blocks <= {64'h1111111111111111, 64'h0000000000000000};
    signature_valid_blocks <= '{2, 0};

    rst_n <= 0;
    #20;
    rst_n <= 1;
    start <= 1;
    #10;
    start <= 0;

    while(!reject && !accept)
      #10;

    if (accept == 1'b0 && reject == 1'b1)
      $display("Test 3: Passed");
    else
      $fatal(1, "Test 3: Failed. Expected accept to be 0 and reject to be 1. Got: accept=%d, reject=%d", accept, reject);


    // Test 3: Valid signature for N=512

    // Test 4: Valid signature for N=1024

    $display("All tests for verify passed!");
    $finish;
  end

endmodule
