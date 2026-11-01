`timescale 1ns / 1ps
`include "common_definitions.vh"

module hash_to_point_tb;

  parameter int N = 512;
  parameter int MESSAGE_BLOCKS = 1+7;
  logic [63:0] message_blocks[MESSAGE_BLOCKS] = '{12+40, 64'h837e8bcfb23c5981, 64'h41d5b10176855b9a, 64'h92208190cdfbc47f, 64'h92e859a168bea29f, 64'ha335ead74efe6969, 64'h6f57206f6c6c6548, 64'h0000000021646c72};

  logic clk;
  logic rst_n;
  logic start;

  logic[14:0] expected_polynomial [N];
  logic done;

  logic [`BRAM_ADDR_WIDTH-1:0] bram0_addr_a, bram0_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram0_din_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram0_dout_a;
  logic bram0_we_b;
  bram_6144x128 bram_6144x128_1 (
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

  logic [`BRAM_ADDR_WIDTH-1:0] bram1_addr_a, bram1_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram1_din_a;
  logic [`BRAM_DATA_WIDTH-1:0] bram1_dout_b;
  logic bram1_we_a;
  bram_6144x128 bram_6144x128_2 (
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

  hash_to_point #(
                  .N(N)
                )
                hash_to_point(
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
      $display("All tests for hash_to_point passed!");
      $finish;
    end
  end

  always #5 clk = ~clk;

  initial begin
    clk = 0;
    rst_n = 0;
    #15;
    rst_n = 1;

    bram0_we_b = 1;
    for (int i = 0; i < MESSAGE_BLOCKS; i++) begin
      bram0_addr_b = i;
      bram0_din_b = {48'b0, message_blocks[i]};
      #10;
    end
    bram0_we_b = 0;

    expected_polynomial = '{7063, 6465, 7534, 6261, 9055, 11350, 9084, 4004, 434, 4149, 11963, 9565, 10361, 4619, 2889, 11047, 10959, 3772, 6544, 38, 5216, 1341, 7437, 2337, 5484, 3868, 6462, 6099, 11126, 1405, 590, 6679, 2866, 11506, 5068, 5966, 12127, 1636, 1928, 8817, 9958, 11327, 10204, 11536, 3102, 4751, 1074, 6329, 6997, 1739, 3263, 11839, 6115, 10065, 7754, 5553, 9488, 5537, 6479, 2175, 4716, 8156, 8923, 7926, 5819, 3862, 1698, 9704, 2633, 6366, 2917, 4646, 9750, 2376, 1402, 5860, 1999, 11328, 9701, 3593, 4579, 1454, 6650, 10483, 9713, 10553, 10352, 3898, 9822, 8239, 10917, 10556, 9817, 1345, 6471, 8732, 558, 11140, 903, 5954, 6749, 2925, 8805, 11724, 8293, 7164, 7787, 4529, 2170, 2893, 3279, 5763, 12217, 7665, 6671, 6926, 8745, 867, 5783, 1523, 7674, 2729, 12030, 6956, 4124, 5516, 8340, 1638, 3499, 6652, 5336, 3424, 11944, 465, 3471, 1557, 4422, 3355, 130, 3027, 7741, 10787, 5547, 12068, 4114, 6545, 5300, 1944, 969, 10450, 9461, 7947, 2060, 2523, 8597, 1339, 6529, 3605, 6356, 7582, 5942, 7912, 5582, 10534, 8517, 918, 5352, 4077, 4322, 2944, 1737, 4280, 8440, 2131, 3119, 11399, 10993, 11923, 9583, 6096, 8387, 1569, 3029, 12094, 12256, 1914, 5679, 9204, 11244, 898, 10032, 4634, 7821, 4933, 7188, 6227, 119, 7594, 7442, 7149, 6723, 7661, 11912, 7122, 5845, 3448, 4341, 7923, 11464, 5914, 5438, 3267, 3274, 10535, 1954, 2455, 7260, 12075, 2377, 7569, 9204, 3730, 1734, 8775, 4119, 2335, 12051, 11556, 6400, 2369, 1989, 10539, 9167, 12270, 9866, 6622, 6284, 7770, 195, 2651, 7857, 10332, 6746, 9577, 7180, 5532, 9322, 11907, 3020, 1409, 10313, 1472, 3535, 2688, 5927, 8587, 9512, 12063, 9180, 1861, 6809, 4676, 10411, 5202, 6180, 7158, 1264, 12006, 8503, 8321, 98, 12284, 7897, 8302, 1536, 1895, 9547, 10980, 966, 6740, 140, 8543, 8257, 672, 11706, 8492, 533, 8914, 7418, 5749, 5384, 3687, 6263, 873, 10221, 12207, 711, 4913, 7538, 12268, 8131, 2476, 1919, 9184, 2853, 11926, 5301, 10593, 6435, 75, 1681, 2815, 4142, 10363, 6013, 3911, 8870, 12046, 11644, 9270, 5057, 7754, 10761, 6789, 3556, 9836, 8275, 701, 3814, 10933, 11334, 2675, 2450, 4123, 12116, 6633, 8671, 215, 9200, 10411, 6766, 11889, 11338, 10863, 10384, 2089, 4086, 190, 11072, 7851, 6489, 9456, 10396, 6073, 3339, 3931, 10951, 5418, 11666, 11587, 12288, 9290, 4453, 9922, 8063, 2842, 10661, 9153, 7826, 4614, 182, 7939, 12139, 2123, 9731, 8306, 5730, 4364, 11187, 6301, 7151, 10019, 10441, 8086, 3470, 1774, 7117, 6760, 1726, 319, 7942, 6506, 5626, 10717, 6119, 4282, 8164, 7991, 9156, 7273, 11108, 10831, 9742, 2185, 12184, 3528, 9078, 8880, 6512, 6774, 1773, 5211, 10266, 7531, 11763, 4512, 10640, 7507, 8974, 1481, 9586, 295, 11633, 234, 11240, 4658, 8197, 615, 7328, 1788, 5933, 4955, 5730, 50, 1054, 2736, 4871, 9113, 6346, 9885, 6298, 5196, 7305, 1642, 10490, 10311, 2840, 9079, 10753, 8806, 7065, 3884, 5848, 9247, 4677, 9683, 890, 5665, 7470, 449, 9671, 1319, 9076, 3526, 4484, 3842, 1175, 2971, 4224, 1214, 6647, 7765, 2106, 717, 8247, 8883, 8285, 5041, 6044, 2467, 10542, 5412, 7346, 1345, 3666, 1594, 6409, 2818, 6788, 3698, 12286, 10200, 10716, 135, 4437, 7677, 12201, 3586, 9666, 3250, 3194, 3464, 10842, 5146, 11411, 11854, 10402, 11663, 6379, 8350, 7651, 9601};
    #20;

    // Start the module
    start <= 1;
    #10;
    start <= 0;
    #20;

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
