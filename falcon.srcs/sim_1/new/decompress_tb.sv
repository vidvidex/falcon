`timescale 1ns / 1ps
`include "common_definitions.vh"

module decompress_tb;
  logic clk;
  logic rst_n;

  parameter int N = 512;
  parameter int SIGNATURE_BLOCKS = 2+79;  // First block (2*64 bit) is the length (in bits)
  logic [63:0] signature_blocks[SIGNATURE_BLOCKS] = '{0, 5000, 64'ha0419223bd4a6372, 64'h1a58ccb4e73f1726, 64'h6639462c2cbc86c9, 64'h81588aba090bd137, 64'h7b848999c8bbb33d, 64'h93bb1ca8aa844b09, 64'h3598b2fb5ba24541, 64'h5933ca988644b44c, 64'h91a579213091ade0, 64'ha6f23b9cece4c224, 64'h652fa2675299f88b, 64'h147cec9df0fb914f, 64'h9aa94adaf9cba4db, 64'hbf52c026d4c9eb36, 64'h61e83d9fea72aff1, 64'hdb39f914f2263f74, 64'hd179686e69e490c5, 64'hdb3cef26159c884a, 64'he30b8fd9f571f986, 64'h8bc0fb2a6e615482, 64'h213bc49aa283ed2e, 64'h51fec9a331ab7b11, 64'hdddb4cb81c38177f, 64'h4263f8668cded02e, 64'hf8fcb704559002bd, 64'h75edffaa9697a774, 64'hec3076a4129facf7, 64'h2b9adc0ccb79f3d8, 64'hd9e3c28281a88eda, 64'h50786e95d40bd9c6, 64'h660ebb0dc9c1ba2e, 64'haa16962048a698cd, 64'hf61454095fe116a9, 64'h9599f8b65114d78d, 64'h3fdad68f91239d59, 64'h6499043cb8c3f0e4, 64'h88e847e2a4596d4c, 64'h4762e52bc037304c, 64'h9e28e95d25bbbf1c, 64'h18b8236dcc62f66a, 64'hc51d4bf6c1187c5b, 64'h4b9b65a2d38f0f43, 64'heb9e6f30b78a0bdf, 64'h53ebc0dcff54b308, 64'h233b9c8d9a61acba, 64'hd0165a3ec920ef41, 64'h539aafa91e4e78ab, 64'he6d4e6d5d32ee36f, 64'h43ba75bbba4fbbbe, 64'h7867772b1c3d12cf, 64'h77ac7497936dd2b5, 64'h3b736816c3d06163, 64'h10fc810b28572531, 64'h56d1e17b3d7ecdd7, 64'he0e24cfcf23eccc1, 64'h8e6d7f9018db639f, 64'h6f6bc7491378b6f5, 64'h92ab93ee57218fe5, 64'hd386ca611c772b83, 64'hda7dac6e5a0b8172, 64'hb37706c77dcefb30, 64'h862f374d40d40f51, 64'hb9424d242716e7fd, 64'hd15d05d088b59e15, 64'h6e8f15f9a4e9fcaf, 64'hfc9b3c0b552a12d4, 64'h3311ab8e958de47e, 64'h4e934138aa7c7910, 64'hdedc415068de5eff, 64'ha230de76d328a717, 64'h31de97acbc9a7392, 64'hddc718aee7922902, 64'h53eca64497ba1aae, 64'hc1647658f3205d66, 64'h26f4db4fbb31a55f, 64'hf712ce4b5d578614, 64'h9626ed3400000000, 64'h0000000000000000, 64'h0000000000000000};

  logic signed [14:0] expected_polynomial[N];

  logic start, done;

  logic [`FFT_BRAM_ADDR_WIDTH-1:0] bram0_addr_a, bram0_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram0_din_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram0_dout_a;
  logic bram0_we_b;
  bram_512x128 bram_512x128_0 (
                 .addra(bram0_addr_a),
                 .clka(clk),
                 .dina(128'b0),
                 .douta(bram0_dout_a),
                 .wea(1'b0),

                 .addrb(bram0_addr_b),
                 .clkb(clk),
                 .dinb(bram0_din_b),
                 .doutb(),
                 .web(bram0_we_b)
               );

  logic [`FFT_BRAM_ADDR_WIDTH-1:0] bram1_addr_a, bram1_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram1_din_a;
  logic [`BRAM_DATA_WIDTH-1:0] bram1_dout_b;
  logic bram1_we_a;
  bram_512x128 bram_512x128_1 (
                 .addra(bram1_addr_a),
                 .clka(clk),
                 .dina(bram1_din_a),
                 .douta(),
                 .wea(bram1_we_a),

                 .addrb(bram1_addr_b),
                 .clkb(clk),
                 .dinb(128'b0),
                 .doutb(bram1_dout_b),
                 .web(1'b0)
               );

  decompress #(
               .N(N)
             )
             decompress (
               .clk(clk),
               .rst_n(rst_n),
               .start(start),

               .input_bram_addr(bram0_addr_a),
               .input_bram_data(bram0_dout_a),

               .output_bram1_addr(bram1_addr_a),
               .output_bram1_data(bram1_din_a),
               .output_bram1_we(bram1_we_a),

               .output_bram2_addr(bram1_addr_b),
               .output_bram2_data(bram1_dout_b),

               .signature_error(signature_error),
               .done(done)
             );

  logic bram_output_valid, bram_output_valid_i;
  int index, index_i, index_ii;

  always_ff @(posedge clk) begin
    bram_output_valid_i <= bram_output_valid;
    index_i <= index;
    index_ii <= index_i;
  end

  logic signed [14:0] coefficient1, coefficient2;
  assign coefficient1 = bram1_dout_b[78:64];
  assign coefficient2 = bram1_dout_b[14:0];

  // Check if result is correct
  always_ff @(posedge clk) begin
    if(bram_output_valid_i === 1) begin
      if(coefficient1 != expected_polynomial[index_ii])
        $fatal(1, "Test failed at index %d. Expected %d, got %d", index_ii, expected_polynomial[index_ii], coefficient1);
      if(coefficient2 != expected_polynomial[index_ii + N/2])
        $fatal(1, "Test failed at index %d. Expected %d, got %d", index_ii + N/2, expected_polynomial[index_ii + N/2], coefficient2);
    end

    if(index_ii == N/2 - 1) begin
      $display("All tests for decompress passed!");
      $finish;
    end
  end

  always #5 clk = ~clk;

  initial begin
    clk = 0;
    rst_n = 0;
    #15;
    rst_n = 1;

    expected_polynomial = '{-160, 134, 290, -94, 202, -13, -16, -37, 25, 301, -206, -120, 242, -25, 28, 326, 225, -23, 33, 100, -129, 354, 215, 4, 11, -162, -59, -184, 162, -25, -145, -93, 51, -178, -93, 28, 209, 340, 18, -4, 53, 177, -23, -53, 244, 34, 193, 100, -158, 467, 12, 18, -162, -274, -165, -100, 9, 393, -45, -193, 55, 35, 115, 315, -73, 8, 291, 75, -337, -157, 41, 447, 278, 71, -29, 167, -112, -375, 20, -243, 84, 74, -53, -359, 116, 54, -95, 82, -128, 54, 76, 189, -283, -7, 65, -89, -253, 185, 95, -199, -51, 319, 20, -228, 49, -247, 180, 249, -33, 243, 60, 292, -11, 108, -231, -100, -133, -28, 16, 43, 152, 113, -246, -245, -71, -332, -34, -224, -246, 211, -332, 84, 132, 9, -188, 38, 209, 7, -52, 114, 31, -345, -291, -141, 239, -8, -93, -54, 50, -64, -67, 2, -95, -289, -15, -323, -291, -61, 64, 119, -15, -22, -449, 214, 256, 94, 117, -91, -126, 84, 233, -105, -186, -216, -3, 234, 4, 79, -44, -238, 92, -45, -1, 50, -60, -115, -49, 103, 414, 193, 131, 196, -219, 296, -97, 116, 221, 2, -108, -198, -280, -215, -6, -73, -131, -209, -213, 139, 172, 130, 20, -294, -27, -216, 197, 130, 95, -322, 106, 50, 230, -120, 108, 196, 205, -227, 63, -53, 346, -370, 35, 58, 101, 36, -144, 271, 113, 15, -263, 290, -80, 31, 277, 150, 237, 433, -88, 114, 43, -128, -57, 4, -19, -266, -82, 116, 45, -59, -99, 262, 240, 155, -57, 24, 379, -427, 199, 75, -109, 132, -7, -139, -37, -155, -22, 22, 56, -97, -80, -117, -158, -60, -5, 120, 193, -111, 83, -87, 131, -79, -106, 44, -388, 25, -57, -17, 102, 48, -44, 117, 192, 101, 71, -178, 32, -94, 133, 57, 85, -234, 158, 57, -197, 124, -309, -77, 215, 50, -220, -55, 67, 116, -86, -93, -36, -247, -351, -97, 59, 114, 99, 143, 18, -30, -94, 99, 201, -100, -54, -82, 234, -91, 54, 2, -48, -360, -5, 24, 15, -272, 267, 66, 242, 204, 86, -35, -5, -89, -87, -89, 117, -240, -68, 51, -103, 35, -89, 176, -142, -53, -124, 1, 155, -49, -159, -61, 350, -210, 147, -98, -55, 345, 85, -19, -92, 92, 140, -124, 116, -195, -20, -132, -199, -74, -65, -218, -118, 227, -203, 5, -129, -74, -27, 240, -49, -62, -78, -246, -260, -11, -27, 205, 131, 64, -362, -185, 265, -36, 9, -139, -79, -247, 21, -32, 372, 145, -44, -225, 91, 71, 21, -243, 167, 63, 43, -254, 182, -224, 106, 74, 137, -168, -24, 26, 113, -165, -13, -72, -377, -210, -32, 56, 84, -113, -72, 13, -91, 144, 208, -163, -101, -95, -104, 152, -60, -219, 50, 20, -69, -24, -94, 175, 101, -73, 206, -201, -59, 156, -10, -92, -100, 20, 130, 79, 357, -273, 175, -80, -42, -344, 228, -217, -271, -272, 117, 305, -317, -54, 62, -89, 154, 87, -123, 18, -28, 173, -213, -97, 138, 172, 183, -38};

    bram0_we_b = 1;
    for (int i = 0; i < SIGNATURE_BLOCKS/2; i++) begin
      bram0_addr_b = i;
      bram0_din_b = {signature_blocks[2*i], signature_blocks[2*i+1]};
      #10;
    end
    bram0_we_b = 0;
    #20;

    // Start the module
    start <= 1;
    #10;
    start <= 0;

    while(done !== 1'b1)
      #10;
    #100;

    for (index = 0; index < N/2; index++) begin
      bram1_addr_b = index;
      bram_output_valid <= 1;
      #10;
    end

  end

endmodule
