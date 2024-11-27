`timescale 1ns / 1ps


module shake256_tb;
  logic clk;
  logic rst;

  // TODO: It would be nice if we didn't have to provide input length in advance. Perhaps we could use a signal "last" to indicate that this is the last block of input.
  logic [15:0] input_len_bytes;  // Message length in bytes. If message is less than 64 bits, then the most significant bits are 0s. CAUTION: that is the opposite of everything else in this implementation
  logic [15:0] output_len_bytes; // Length of logic PRNG string in bytes.

  logic ready_in;  // Is shake256 module ready to receive data?
  logic [63:0] data_in;
  logic data_in_valid;

  logic ready_out;     // Are we ready to receive result from shake256 module?
  logic [63:0] data_out;
  logic data_out_valid;

  shake256 uut(
             .clk(clk),
             .rst(rst),
             .input_len_bytes(input_len_bytes),
             .output_len_bytes(output_len_bytes),
             .ready_in(ready_in),
             .data_in(data_in),
             .data_in_valid(data_in_valid),
             .ready_out(ready_out),
             .data_out(data_out),
             .data_out_valid(data_out_valid)
           );

  always #5 clk = ~clk;

  assign ready_out = 1; // We are always ready to receive the result

  initial begin
    clk = 0;
    rst = 1;

    #5;

    input_len_bytes = 16'h0049;
    output_len_bytes = 16'h0040;

    #10;
    data_in = 64'h1720e40775c0b333;
    rst = 0;
    #10;

    data_in_valid = 1;
    #20;

    data_in = 64'ha6e26e2b834d4948;
    #10;

    data_in = 64'hb543e30e9bff3bc9;
    #10;

    data_in = 64'hd7e00d3d5af8d150;
    #10;

    data_in = 64'h913954278d1c604;
    #10;

    data_in = 64'hfbcb4f738d4d1cd8;
    #10;

    data_in = 64'haa9f038a3f3ddeea;
    #10;

    data_in = 64'h55ad35e857992c2a;
    #10;

    data_in = 64'h6a55bb57bf752eb2;
    #10;

    data_in = 64'hc8;
    #10;

    data_in = 64'h0000000000000000;
    #70;
    data_in_valid = 0;
    #260;

  end
endmodule
