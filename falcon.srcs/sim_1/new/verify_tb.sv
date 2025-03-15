`timescale 1ns / 1ps

module verify_tb;

  logic clk;
  logic rst_n;

  logic start;

  logic [63:0] message_blocks [2];   // Buffer for message blocks
  logic [63:0] signature_salt_blocks [5];   // Buffer for signature salt blocks
  logic [63:0] signature_value_blocks [2];   // Buffer for signature value blocks
  logic [6:0] signature_value_valid_blocks [2];   // Buffer for signature value valid blocks

  logic signed [14:0] public_key[8] = {7644, 6589, 8565, 4185, 1184, 607, 3842, 5361};

  logic [15:0] message_len_bytes; //! Length of the message in bytes
  logic [63:0] message;
  logic message_valid; //! Is message valid
  logic message_ready; //! Is ready to receive the next message

  logic [63:0] signature_salt; //! Salt from the signature
  logic signature_salt_valid;  //! Is signature_salt valid
  logic signature_salt_ready; //! Is ready to receive the next signature_salt block
  logic [63:0] signature_value;
  logic [6:0] signature_value_valid; //! Number of valid bits in signature_value (from the left)
  logic signature_value_ready; //! Is ready to receive the next signature_value block

  logic accept; //! Set to true if signature is valid
  logic reject; //! Set to true if signature is invalid

  int message_block_index = 0;
  int signature_salt_block_index = 0;
  int signature_value_block_index = 0;

  verify #(
           .N(8),
           .SIGNATURE_LENGTH(11)
         )uut(
           .clk(clk),
           .rst_n(rst_n),

           .start(start),

           .public_key(public_key),
           .public_key_valid(1'b1),

           .message_len_bytes(message_len_bytes),
           .message(message),
           .message_valid(message_valid),
           .message_ready(message_ready),

           .signature_salt(signature_salt),
           .signature_salt_valid(signature_salt_valid),
           .signature_salt_ready(signature_salt_ready),
           .signature_value(signature_value),
           .signature_value_valid(signature_value_valid),
           .signature_value_ready(signature_value_ready),

           .accept(accept),
           .reject(reject)
         );

  always_ff @(posedge clk) begin

    if(rst_n == 1'b0) begin
      message_block_index <= 0;
      signature_salt_block_index <= 0;
      signature_value_block_index <= 0;
    end

    if(!accept && !reject) begin

      // Send new signature salt block if module is ready for it
      // For the first block we cannot depend on signature_salt_ready signal, because that is only set high after signature_salt_valid is set high
      // We also have to make sure we don't send more than 5 blocks, since we only have 5 blocks of salt
      if ((signature_salt_block_index == 0 || signature_salt_ready) && signature_salt_block_index < 5) begin
        signature_salt = signature_salt_blocks[signature_salt_block_index];
        signature_salt_valid = 1;
        signature_salt_block_index <= signature_salt_block_index + 1;
      end
      else if (signature_salt_block_index >= 5)  // Set valid to low after we've sent all salt blocks
        signature_salt_valid <= 0;

      // Send new message block if module is ready for it
      if ((message_block_index == 0 || message_ready) && message_block_index < 2) begin
        message = message_blocks[message_block_index];
        message_valid = 1;
        message_block_index <= message_block_index + 1;
      end
      else if (message_block_index >= 2)  // Set valid to low after we've sent all message blocks
        message_valid <= 0;

      // Send new signature value block if module is ready for it
      if ((signature_value_block_index == 0 || signature_value_ready) && signature_value_block_index < 2) begin
        signature_value = signature_value_blocks[signature_value_block_index];
        signature_value_valid = signature_value_valid_blocks[signature_value_block_index];
        signature_value_block_index <= signature_value_block_index + 1;
      end
      else if (signature_value_block_index >= 2)  // Set valid to low after we've sent all signature value blocks
        signature_value_valid = 0;
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

    message_len_bytes = 12; // len("Hello World!") = 12
    message_blocks = {64'h6f57206f6c6c6548, 64'h0000000021646c72}; // "Hello World!" (reversed and with padding)

    // len(signature salt) = 40 bytes
    signature_salt_blocks = {64'h8ae56efee299dd5d, 64'h0ddf5a76484a58c2, 64'he5c9678b2d3ccf73, 64'haeb69f7b17f6be7d, 64'h0bdfb438301f6d76};

    // len(signature value) = 11 bytes = 88 bits = 64 + 24
    signature_value_blocks = {64'h997b21eec3635e54, 64'h6308000000000000};
    signature_value_valid_blocks = {64, 24};

    rst_n = 0;
    #10;
    rst_n = 1;
    start = 1;
    #10;
    start = 0;

    while(!reject && !accept)
      #10;

    // Check that it was accepted
    if (accept && !reject)
      $display("Test 1: Passed");
    else
      $fatal("Test 1: Failed. Expected accept to be 1 and reject to be 0. Got: accept=%d, reject=%d", accept, reject);


    //////////////////////////////////////////////////////////////////////////////////
    // Test 2: Invalid signature for N=8 (same values as in test 1 but signature is corrupted)
    //////////////////////////////////////////////////////////////////////////////////

    message_len_bytes = 12; // len("Hello World!") = 12
    message_blocks = {64'h6f57206f6c6c6548, 64'h0000000021646c72}; // "Hello World!" (reversed and with padding)

    // len(signature salt) = 40 bytes
    signature_salt_blocks = {64'h8ae56efee299ddaa, 64'h0ddf5a76484a58c2, 64'he5c9678b2d3ccf73, 64'haeb69f7b17f6be7d, 64'h0bdfb438301f6d76}; // Last byte of first block should be '5d' but changed to 'aa' to make it invalid

    // len(signature value) = 11 bytes = 88 bits = 64 + 24
    signature_value_blocks = {64'h997b21eec3635e54, 64'h6308000000000000};
    signature_value_valid_blocks = {64, 24};

    rst_n = 0;
    #50;
    rst_n = 1;
    start = 1;
    #10;
    start = 0;

    while(!reject && !accept)
      #10;

    // Check that it was rejected
    if (!accept && reject)
      $display("Test 2: Passed");
    else
      $fatal("Test 2: Failed. Expected accept to be 0 and reject to be 1. Got: accept=%d, reject=%d", accept, reject);

    //////////////////////////////////////////////////////////////////////////////////
    // Test 3: Incorrectly compressed coefficients in signature
    //////////////////////////////////////////////////////////////////////////////////

    message_len_bytes = 12; // len("Hello World!") = 12
    message_blocks = {64'h6f57206f6c6c6548, 64'h0000000021646c72}; // "Hello World!" (reversed and with padding)

    // len(signature salt) = 40 bytes
    signature_salt_blocks = {64'h8ae56efee299dd5d, 64'h0ddf5a76484a58c2, 64'he5c9678b2d3ccf73, 64'haeb69f7b17f6be7d, 64'h0bdfb438301f6d76};

    signature_value_blocks = {64'h1111111111111111, 64'h0000000000000000};
    signature_value_valid_blocks = {2, 0};

    rst_n = 0;
    #10;
    rst_n = 1;
    start = 1;
    #10;
    start = 0;

    while(!reject && !accept)
      #10;

    // Check that it was rejected
    if (!accept && reject)
      $display("Test 3: Passed");
    else
      $fatal("Test 3: Failed. Expected accept to be 0 and reject to be 1. Got: accept=%d, reject=%d", accept, reject);


    // Test 3: Valid signature for N=512

    // Test 4: Valid signature for N=1024

    $display("All tests for verify passed!");
    $finish;
  end

endmodule
