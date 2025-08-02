`timescale 1ns / 1ps
`include "common_definitions.vh"

module control_unit_sign_tb;

  parameter int N = 512;
  parameter int MESSAGE_BLOCKS = 1+7;
  parameter int TREE_SIZE = ($clog2(N)+1) << $clog2(N);
  logic [63:0] message_blocks[MESSAGE_BLOCKS] = '{12+40, 64'h837e8bcfb23c5981, 64'h41d5b10176855b9a, 64'h92208190cdfbc47f, 64'h92e859a168bea29f, 64'ha335ead74efe6969, 64'h6f57206f6c6c6548, 64'h0000000021646c72};

  logic [`BRAM_DATA_WIDTH-1:0] b00 [N/2];
  logic [`BRAM_DATA_WIDTH-1:0] b01 [N/2];
  logic [`BRAM_DATA_WIDTH-1:0] b10 [N/2];
  logic [`BRAM_DATA_WIDTH-1:0] b11 [N/2];
  logic [`BRAM_DATA_WIDTH-1:0] tree [TREE_SIZE];

  initial begin
    $readmemh("../../../../falcon.srcs/sources_1/coefficients/b00_512.mem", b00);
    $readmemh("../../../../falcon.srcs/sources_1/coefficients/b01_512.mem", b01);
    $readmemh("../../../../falcon.srcs/sources_1/coefficients/b10_512.mem", b10);
    $readmemh("../../../../falcon.srcs/sources_1/coefficients/b11_512.mem", b11);
    $readmemh("../../../../falcon.srcs/sources_1/coefficients/tree_512.mem", tree);
  end

  logic clk, rst_n;

  logic [127:0] instruction;
  logic instruction_done;
  logic [`BRAM_DATA_WIDTH-1:0] bram_din, bram_dout;

  always #5 clk = ~clk;

  control_unit #(
                 .N(N)
               ) control_unit (
                 .clk(clk),
                 .rst_n(rst_n),
                 .instruction(instruction),
                 .instruction_done(instruction_done),
                 .bram_din(bram_din),
                 .bram_dout(bram_dout)
               );

  logic [15:0] modules;
  logic [2:0] bank1, bank2, bank3, bank4;
  logic [12:0] address1, address2,address3, address4;
  logic mode;
  logic last;

  assign instruction = {modules, 46'b0, last, mode, address4, address3, address2, address1, bank4, bank3, bank2, bank1};

  initial begin

    modules = 16'b0000_0000_0000_0000;
    bank1 = 0;
    bank2 = 0;
    bank3 = 0;
    bank4 = 0;
    address1 = 0;
    address2 = 0;
    address3 = 0;
    address4 = 0;
    mode = 0;
    last = 0;

    clk = 1;

    rst_n = 0;
    #10;
    rst_n = 1;

    #10;

    // Load b00
    for (int i = 0; i < N/2; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 0;
      address1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = b00[i];
      last = (i == N/2 - 1) ? 1'b1 : 1'b0;
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load b01
    for (int i = 0; i < N/2; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 1;
      address1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = b01[i];
      last = (i == N/2 - 1) ? 1'b1 : 1'b0;
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load b10
    for (int i = 0; i < N/2; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 2;
      address1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = b10[i];
      last = (i == N/2 - 1) ? 1'b1 : 1'b0;
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load b11
    for (int i = 0; i < N/2; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 3;
      address1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = b11[i];
      last = (i == N/2 - 1) ? 1'b1 : 1'b0;
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load message len, message and salt
    for (int i = 0; i < MESSAGE_BLOCKS; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 4;
      address1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = {64'b0, message_blocks[i]}; // Write 64 bits of message, padding with zeros
      last = (i == MESSAGE_BLOCKS - 1) ? 1'b1 : 1'b0;
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load tree
    for (int i = 0; i < TREE_SIZE; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 6;
      address1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = tree[i];
      last = (i == TREE_SIZE - 1) ? 1'b1 : 1'b0;
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Run hash_to_point on salt and message
    modules = 16'b0001_0000_0000_0000; // hash_to_point
    bank1 = 4;
    bank2 = 5;
    #10;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Run int_to_double
    for (int i = 0; i < N/2; i++) begin
      modules = 16'b0000_1000_0000_0000; // int to double
      bank1 = 5;
      bank2 = 5;
      address1 = i[`BRAM_ADDR_WIDTH-1:0];
      address2 = i[`BRAM_ADDR_WIDTH-1:0];
      last = (i == N/2 - 1) ? 1'b1 : 1'b0;
      #10;
    end
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;

    // Run FFT
    modules = 16'b0000_0100_0000_0000; // FFT
    bank1 = 5;
    bank2 = 4;
    mode = 0; // FFT
    #10;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Run copy and mul
    for (int i = 0; i < N/2; i++) begin
      modules = 16'b0010_0001_0000_0000; // copy and mul
      bank1 = 5;  // Mul 5 and 3, destination 5
      bank2 = 3;
      bank3 = 5;  // Copy from 5 to 4
      bank4 = 4;
      address1 = i[`BRAM_ADDR_WIDTH-1:0];
      address2 = i[`BRAM_ADDR_WIDTH-1:0];
      address3 = i[`BRAM_ADDR_WIDTH-1:0];
      address4 = i[`BRAM_ADDR_WIDTH-1:0];
      last = (i == N/2 - 1) ? 1'b1 : 1'b0;
      #10;
    end
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;
  end

endmodule
