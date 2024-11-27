`timescale 1ns / 1ps


module shake256_tb;
  logic clk;
  logic rst;

  logic [15:0] inputLen_InBytes;  // Message length in bytes. If message is less than 64 bits, then the most significant bits are 0s.
  logic [15:0] outputLen_InBytes; // Length of logic PRNG string in bytes.

  logic keccak_is_ready_to_receive;  // when this signal is high, that means Keccak is ready to absorb.
  logic [63:0] din_64bit_raw;
  logic din_valid;                    // This signal is provided by a data source to indicate that din_64bit_raw is valid

  logic keccak_squeeze_resume;     // This is used to 'resume' Keccak squeeze after a pause. Useful to generate PRNG in short chunks.
  logic [63:0] dout_64bit;        // 64-bit PRNG word logic from Keccak state
  logic dout_valid;               // This signal is used to write Keccak-squeeze logic

  keccak_speed uut(
                 .clk(clk),
                 .rst(rst),
                 .inputLen_InBytes(inputLen_InBytes),
                 .outputLen_InBytes(outputLen_InBytes),
                 .keccak_is_ready_to_receive(keccak_is_ready_to_receive),
                 .din_64bit_raw(din_64bit_raw),
                 .din_valid(din_valid),
                 .keccak_squeeze_resume(keccak_squeeze_resume),
                 .dout_64bit(dout_64bit),
                 .dout_valid(dout_valid)
                 );

  always #5 clk = ~clk;

  assign keccak_squeeze_resume = 0;

  initial begin
    clk = 0;
    rst = 1;

    #5;


    inputLen_InBytes = 16'h0049;
    outputLen_InBytes = 16'h0040;

    #10;
    din_64bit_raw = 64'h1720e40775c0b333;
    rst = 0;
    #20;

    din_valid = 1;
    #20;

    din_64bit_raw = 64'ha6e26e2b834d4948;
    #10;

    din_64bit_raw = 64'hb543e30e9bff3bc9;
    #10;

    din_64bit_raw = 64'hd7e00d3d5af8d150;
    #10;

    din_64bit_raw = 64'h913954278d1c604;
    #10;

    din_64bit_raw = 64'hfbcb4f738d4d1cd8;
    #10;

    din_64bit_raw = 64'haa9f038a3f3ddeea;
    #10;

    din_64bit_raw = 64'h55ad35e857992c2a;
    #10;

    din_64bit_raw = 64'h6a55bb57bf752eb2;
    #10;

    din_64bit_raw = 64'hc8;
    #10;

    din_64bit_raw = 64'h0000000000000000;
    #70;
    din_valid = 0;
    #260;
    keccak_squeeze_resume = 1;
    #100;
    keccak_squeeze_resume = 0;

  end
endmodule
