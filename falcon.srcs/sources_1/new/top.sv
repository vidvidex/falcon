`timescale 1ns / 1ps

module top (
    input logic clk,
    input logic [3:0] btns,
    output logic [3:0] leds
  );

  logic rst, start;

  logic [63:0] message_blocks [7];   // Buffer for message blocks
  logic [63:0] signature_blocks [2];   // Buffer for signature value blocks
  logic [6:0] signature_valid_blocks [2];   // Buffer for signature value valid blocks

  logic signed [14:0] public_key[8] = {7644, 6589, 8565, 4185, 1184, 607, 3842, 5361};

  logic [15:0] message_len_bytes; //! Length of the message in bytes
  logic [63:0] message;
  logic message_valid; //! Is message valid
  logic message_last;
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
           .SIGNATURE_LENGTH(11)
         )verify(
           .clk(clk),
           .rst_n(!rst),

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

    if(rst == 1'b1) begin
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

      if(signature_ready && signature_block_index < 2) begin
        signature <= signature_blocks[signature_block_index];
        signature_valid <= signature_valid_blocks[signature_block_index];
        signature_block_index <= signature_block_index + 1;
      end
      else
        signature_valid <= 0; // Set valid to low after we've sent all signature value blocks
    end
  end

  assign message_len_bytes = 12; // len("Hello World!") = 12
    // First 5 blocks of message are the salt (40B), the rest is the message ("Hello World!", reversed and with padding)
  assign message_blocks = {64'h8ae56efee299dd5d, 64'h0ddf5a76484a58c2, 64'he5c9678b2d3ccf73, 64'haeb69f7b17f6be7d, 64'h0bdfb438301f6d76, 64'h6f57206f6c6c6548, 64'h0000000021646c72};

  // len(signature) = 11 bytes = 88 bits = 64 + 24
  assign signature_blocks = {64'h997b21eec3635e54, 64'h6308000000000000};
  assign signature_valid_blocks = '{64, 24};

  assign rst = btns[3];
  assign start = btns[2];

  assign leds[0] = accept;
  assign leds[1] = reject;
  assign leds[2] = start;
  assign leds[3] = rst;

endmodule
