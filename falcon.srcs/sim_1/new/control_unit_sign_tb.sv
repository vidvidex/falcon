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
  logic [2:0] bank1, bank2, bank3, bank4, bank5, bank6;
  logic [12:0] addr1, addr2;
  logic mode;
  logic mul_const_selection;
  logic [3:0] element_count;
  logic [2:0] decompress_output2;

  assign instruction = {modules, 59'b0, decompress_output2, element_count, mul_const_selection, mode, addr2, addr1, bank6, bank5, bank4, bank3, bank2, bank1};

  initial begin

    modules = 16'b0000_0000_0000_0000;
    bank1 = 0;
    bank2 = 0;
    bank3 = 0;
    bank4 = 0;
    bank5 = 0;
    bank6 = 0;
    addr1 = 0;
    addr2 = 0;
    mode = 0;
    mul_const_selection = 0;
    element_count = 0;
    decompress_output2 = 0;

    clk = 1;

    rst_n = 0;
    #10;
    rst_n = 1;

    #10;

    // Load b00
    for (int i = 0; i < N/2; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 0;
      addr1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = b00[i];
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load b01
    for (int i = 0; i < N/2; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 1;
      addr1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = b01[i];
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load b10
    for (int i = 0; i < N/2; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 2;
      addr1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = b10[i];
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load b11
    for (int i = 0; i < N/2; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 3;
      addr1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = b11[i];
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load message len, message and salt
    for (int i = 0; i < MESSAGE_BLOCKS; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 4;
      addr1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = {64'b0, message_blocks[i]}; // Write 64 bits of message, padding with zeros
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load tree
    for (int i = 0; i < TREE_SIZE; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 6;
      addr1 = i[`BRAM_ADDR_WIDTH-1:0];
      bram_din = tree[i];
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Run hash_to_point on salt and message
    modules = 16'b0001_0000_0000_0000; // hash_to_point
    bank3 = 4;
    bank4 = 5;
    #10;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Run int_to_double
    modules = 16'b0000_1000_0000_0000; // int to double
    bank1 = 5;
    bank2 = 5;
    element_count = $clog2(256);
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

    // Run copy and complex mul
    modules = 16'b0010_0001_0000_0000; // copy and complex mul
    bank1 = 5;  // complex mul 5 and 1, destination 5
    bank2 = 1;
    bank3 = 5;  // Copy from 5 to 4
    bank4 = 4;
    addr1 = 0;  // Offsets for copy and complex mul (same offsets for both modules)
    addr2 = 0;
    element_count = $clog2(256);
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;

    // Run complex mul and mul const
    modules = 16'b0000_0001_1000_0000; // complex mul and mul const
    bank1 = 4;  // complex mul 4 and 3, destination 4
    bank2 = 3;
    bank3 = 5;  // mul const 5, output to 5
    bank4 = 5;
    addr1 = 0;  // Offsets for complex mul
    addr2 = 0;
    element_count = $clog2(256);
    mul_const_selection = 1; // -1/12289
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;

    // Run mul const
    modules = 16'b0000_0000_1000_0000; // mul const
    bank3 = 4;  // mul const 4, output to 4
    bank4 = 4;
    mul_const_selection = 0; // 1/12289
    element_count = $clog2(256);
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;

    ////// Start ff_sampling //////

    // Run split (t1 -> z1_512)
    modules = 16'b0000_0000_0100_0000; // split
    bank1 = 5;
    addr1 = 0;
    bank2 = 0;
    addr2 = 512;
    element_count = 9;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;

    // Run split (z1_512 -> z1_256)
    modules = 16'b0000_0000_0100_0000; // split
    bank1 = 0;
    addr1 = 640;
    bank2 = 1;
    addr2 = 384;
    element_count = 8;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;

    // Run split (z1_256 -> z1_128)
    modules = 16'b0000_0000_0100_0000; // split
    bank1 = 1;
    addr1 = 448;
    bank2 = 2;
    addr2 = 320;
    element_count = 7;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;

    // Run split (z1_128 -> z1_64)
    modules = 16'b0000_0000_0100_0000; // split
    bank1 = 2;
    addr1 = 352;
    bank2 = 3;
    addr2 = 288;
    element_count = 6;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;

    // Run split (z1_64 -> z1_32)
    modules = 16'b0000_0000_0100_0000; // split
    bank1 = 3;
    addr1 = 304;
    bank2 = 0;
    addr2 = 784;
    element_count = 5;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;

    // Run split (z1_32 -> z1_16)
    modules = 16'b0000_0000_0100_0000; // split
    bank1 = 0;
    addr1 = 792;
    bank2 = 1;
    addr2 = 520;
    element_count = 4;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;

    // Run split (z1_16 -> z1_8)
    modules = 16'b0000_0000_0100_0000; // split
    bank1 = 1;
    addr1 = 524;
    bank2 = 2;
    addr2 = 388;
    element_count = 3;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;

    // Run split (z1_8 -> z1_4)
    modules = 16'b0000_0000_0100_0000; // split
    bank1 = 2;
    addr1 = 390;
    bank2 = 3;
    addr2 = 322;
    element_count = 2;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000;
    #10;
  end

endmodule
