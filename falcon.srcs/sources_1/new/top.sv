`timescale 1ns / 1ps

module top (
    input logic clk,
    input logic [3:0] btns,
    output logic [3:0] leds
  );

  logic rst_n, start, start_i, start_pulse;

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

  int message_block_index;
  int signature_block_index;
  int reset_counter;

  verify #(
           .N(8),
           .SBYTELEN(52)
         )verify(
           .clk(clk),
           .rst_n(rst_n),

           .start(start_pulse),

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

  typedef enum logic [1:0] {
            RESET,
            RUNNING,
            DONE
          } state_t;
  state_t state, next_state;

  always_ff @(posedge clk) begin
    rst_n <= !(btns[0] || btns[1] || btns[2] || btns[3]);
  end

  always_ff @(posedge clk) begin
    if (rst_n == 1'b0)
      state <= RESET;
    else
      state <= next_state;
  end

  always_comb begin
    next_state = state;

    case (state)
      RESET: begin
        if(reset_counter == 125_000_000*5)  // Wait 5 seconds
          // if(reset_counter == 25)
          next_state = RUNNING;
      end
      RUNNING: begin
        if(accept == 1'b1 || reject == 1'b1)
          next_state = DONE;
      end
      DONE: begin
        next_state = DONE;
      end
      default: begin
        next_state = RESET;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      reset_counter <= 0;
    end

    case (state)
      RESET: begin
        leds[0] <= 1'b1;
        leds[1] <= 1'b0;
        leds[2] <= 1'b0;
        leds[3] <= 1'b0;

        message_block_index <= 0;
        signature_block_index <= 0;

        reset_counter <= reset_counter + 1;

        start <= 1'b0;
        start_i <= 1'b0;
      end
      RUNNING: begin
        start <= 1'b1;

        leds[0] <= 1'b0;
        leds[1] <= 1'b1;
        leds[2] <= 1'b0;
        leds[3] <= 1'b0;

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
      DONE: begin
        leds[0] <= 1'b0;
        leds[1] <= 1'b0;
        leds[2] <= accept;
        leds[3] <= reject;
      end
    endcase

    start_i <= start;
  end

  assign message_len_bytes = 12; // len("Hello World!") = 12
  // First 5 blocks of message are the salt (40B), the rest is the message ("Hello World!", reversed and with padding)
  assign message_blocks = {64'h8ae56efee299dd5d, 64'h0ddf5a76484a58c2, 64'he5c9678b2d3ccf73, 64'haeb69f7b17f6be7d, 64'h0bdfb438301f6d76, 64'h6f57206f6c6c6548, 64'h0000000021646c72};

  // len(signature) = 11 bytes = 88 bits = 64 + 24
  assign signature_blocks = {64'h997b21eec3635e54, 64'h6308000000000000};
  assign signature_valid_blocks = '{64, 24};

  assign start_pulse = start == 1'b1 && start_i == 1'b0;

endmodule
