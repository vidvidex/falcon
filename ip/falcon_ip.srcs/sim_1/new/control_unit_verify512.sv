`timescale 1ns / 1ps
`include "common_definitions.vh"

module control_unit_verify512_tb;

  parameter int N = 512;
  parameter int MESSAGE_BLOCKS = 1+7; // First block is the length (in bytes)
  parameter int SIGNATURE_BLOCKS = 40;  // 666-1-40 bytes / 16 bytes per block
  logic signed [14:0] public_key[N] = '{3605, 11394, 3623, 9500, 11987, 4336, 3361, 1348, 6563, 8102, 758, 8455, 5789, 7614, 797, 11215, 7518, 3116, 4556, 1762, 11267, 9507, 4586, 5420, 4091, 6788, 1729, 6433, 4730, 1830, 4200, 1416, 3705, 5380, 5767, 9261, 924, 6822, 8978, 2536, 8232, 10530, 10137, 11653, 11704, 1887, 11653, 10218, 9207, 10699, 3288, 1478, 7261, 10152, 3871, 10134, 7359, 9993, 9510, 8661, 419, 1826, 978, 11037, 10899, 3311, 2064, 5939, 11072, 1748, 9516, 5458, 7665, 4459, 5937, 5615, 7288, 3438, 6009, 3217, 264, 3696, 608, 11576, 2774, 10976, 11146, 11188, 3237, 10913, 3541, 11755, 9412, 5720, 4226, 1154, 9010, 9922, 3994, 11252, 11575, 11077, 9308, 7784, 11086, 12047, 5310, 8524, 4117, 504, 3145, 12216, 2718, 1181, 5446, 1818, 6156, 1945, 11240, 7398, 8307, 8259, 10113, 11431, 10691, 2147, 2742, 8242, 12031, 8808, 7609, 3657, 3567, 2485, 7669, 4388, 3255, 1395, 596, 9635, 6739, 10284, 4910, 9410, 11788, 10978, 3877, 4006, 1860, 6225, 8834, 11969, 11742, 9733, 8790, 7871, 10347, 2658, 4468, 947, 3384, 9733, 6496, 382, 81, 7977, 7138, 8962, 10195, 2830, 10227, 5302, 9974, 9157, 7442, 4931, 9761, 5759, 2115, 431, 12242, 2353, 7529, 7822, 6343, 3370, 9369, 8491, 6742, 5681, 10973, 412, 12105, 6913, 5565, 3760, 4378, 4454, 9070, 1289, 2596, 5355, 12117, 2787, 3798, 4954, 9708, 2191, 2935, 4073, 7455, 11661, 4170, 8782, 9611, 8647, 2318, 4779, 11339, 3962, 361, 9358, 7727, 11723, 9018, 10552, 3025, 6852, 6028, 10603, 7147, 8434, 5604, 4483, 5954, 426, 11403, 2643, 8294, 9504, 7268, 8958, 2773, 7764, 5926, 8213, 2100, 8814, 7540, 4212, 7012, 353, 7166, 5717, 9799, 10379, 7768, 9515, 2534, 4504, 5410, 5358, 1879, 11581, 10692, 2614, 11002, 11667, 7333, 6932, 4254, 9503, 7386, 2581, 4153, 6079, 6149, 5496, 2397, 11735, 6496, 9250, 11872, 10842, 2934, 4022, 10681, 914, 4397, 7287, 9673, 4709, 4895, 3770, 3146, 7254, 4953, 11018, 9062, 3817, 11979, 8723, 3091, 2675, 8946, 7376, 3652, 6861, 8298, 5547, 11, 4758, 10734, 7434, 11702, 6466, 9135, 11199, 10059, 503, 2510, 1730, 6101, 11965, 10264, 6045, 11690, 11530, 761, 9270, 4531, 5482, 6951, 5776, 10348, 2668, 5246, 8046, 7106, 11302, 3276, 6632, 12008, 6564, 8465, 1953, 5904, 1036, 3109, 5020, 11945, 458, 11742, 5271, 4474, 9918, 7963, 11786, 8318, 756, 560, 11377, 1084, 9634, 9203, 1062, 8461, 1845, 3719, 6672, 6660, 4711, 11337, 10460, 5367, 4072, 7043, 5567, 6356, 657, 8877, 3633, 11487, 10421, 10877, 5052, 2174, 4711, 11853, 4461, 10942, 11619, 7591, 3424, 3372, 4493, 11393, 7115, 9057, 7145, 2060, 9137, 707, 1968, 7853, 645, 253, 2697, 9294, 8357, 7503, 6187, 7505, 8302, 4635, 8899, 9258, 8559, 7988, 9571, 243, 6979, 8233, 11555, 5257, 8361, 1836, 11185, 3771, 3517, 10585, 4756, 10212, 2035, 2778, 6798, 11229, 11768, 8707, 7931, 3744, 10939, 5317, 6104, 11137, 3936, 5418, 4368, 201, 3094, 8211, 6803, 2559, 3164, 6846, 8515, 8894, 8556, 2219, 9593, 6391, 3374, 4868, 192, 2791, 4309, 62, 20, 9968, 8831, 11185, 1365, 9722, 5623, 2398, 5049, 2241, 6060, 998, 4233, 1455, 5324, 1053, 5626, 1726, 11569, 12033, 4897, 859, 1676, 2097, 11147, 5155, 5187, 2026, 12050, 5615, 5450, 260, 7526, 11923, 6346, 7221, 405, 882, 842, 4621, 4130, 3513, 114, 3673, 4914};
  logic [63:0] message_blocks[MESSAGE_BLOCKS] = '{40+12, 64'h837e8bcfb23c5981, 64'h41d5b10176855b9a, 64'h92208190cdfbc47f, 64'h92e859a168bea29f, 64'ha335ead74efe6969, 64'h6f57206f6c6c6548, 64'h0000000021646c72};
  logic [127:0] signature_blocks[SIGNATURE_BLOCKS] = '{128'h2e3d32018ae7c7954a141b0ceb63dc88, 128'h3e0e1483b1ae7e59cb308c4927adc86b, 128'h040115d2a12dbcfe572ee0fc68742a1d, 128'h9d83b537cdd75a389d439a376f432ec8, 128'h8d03e8d8e162109ed2b0df0b031099a3, 128'h31849508da1b74596891b87d09933a81, 128'h63d1a78195e9a65607aee9afa2f1ea11, 128'h416d8c563a38fc50dbe951325eb2edb2, 128'hda9716df0e3089457db49d619477b33d, 128'h9264d84f056bff61b1917e93648e964f, 128'h4d4ef15b99e5177aa52a758d56e097c7, 128'h7a7cc3a5eae58a651782b14ed63d3c44, 128'h135807d75883273b5680e0b7cda64268, 128'h6c93dad280836272e36719dac15b587b, 128'hd92b9a40e60c8999c0a04e3c7ba3a42a, 128'hd0dc2efa9d3b27f1edfcfa5bb2655f59, 128'hba057347b06d9a41006ffac801d0538f, 128'h72bd8f89182bdd1e8f37e8e7bd9b262b, 128'h6aa73f5fcd5bd7f0b31493f31c4c44e4, 128'ha1ee3e881a951f29fc86460a6c9676cf, 128'h894af4b0afe339ddd4e2c64f3ae4d333, 128'hdb62cd947b748e8e9f3a94d395130cbd, 128'h7f79fe95b64d9ecc374f4b1b72dcb8ce, 128'hde1532760667cee5f5b7cfba2f02c09c, 128'h26ebcd4cf4bd752786bedd2d9147eba8, 128'hd6cfbdd8d94606771061f98fee31d322, 128'ha756c903f95fa9bb5ab8c43b4c49f471, 128'h6918632cb573e2222de4c12db3e3a661, 128'h0fb40ccdae9be8ce5a95874c9d0356aa, 128'he64997f570e0df27084b32d6c36afd2d, 128'hd624b7ed9ddbef298ce5105ef715b9bf, 128'ha1c6c6152c875da9859ef0d3921bcea8, 128'hf7222d0d157bd3d8b988fcbabd6eec3a, 128'ha82d613a5bf19425039340c436afa70a, 128'hf9485ce193641e44ace92c15ca842333, 128'hfe2e0aaa6a432e499b1a6cd7a62cb86c, 128'h841d0f21f225ba50d6bcb59c93651fcb, 128'h9219ec1136cfdb04fa2666e0abcddabf, 128'h7d7426970e9400000000000000000000, 128'h00000000000000000000000000000000};

  logic clk, rst_n;

  logic [127:0] instruction;
  logic instruction_done;
  logic [`BRAM_DATA_WIDTH-1:0] bram_din, bram_dout;

  logic signature_accepted;
  logic signature_rejected;

  always #5 clk = ~clk;

  control_unit #(
                 .N(N)
               ) control_unit (
                 .clk(clk),
                 .rst_n(rst_n),
                 .instruction(instruction),
                 .instruction_done(instruction_done),

                 .signature_accepted(signature_accepted),
                 .signature_rejected(signature_rejected),

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

    // Load public key
    for (int i = 0; i < N/2; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 0;
      addr1 = i;
      bram_din = {49'b0, public_key[i], 49'b0, public_key[i + N/2]};
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load signature
    for (int i = 0; i < SIGNATURE_BLOCKS; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 1;
      addr1 = i;
      bram_din = signature_blocks[i];
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Load message len, message and salt
    for (int i = 0; i < MESSAGE_BLOCKS; i++) begin
      modules = 16'b0100_0000_0000_0000; // BRAM_WRITE
      bank1 = 6;
      addr1 = i;
      bram_din = {64'b0, message_blocks[i]}; // Write 64 bits of message, padding with zeros
      #10;
    end
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Run hash_to_point, decompress and NTT
    modules = 16'b0001_0010_0000_0100; // hash_to_point, NTT, decompress
    mode = 1'b0; // NTT
    bank1 = 0;
    bank2 = 2;
    bank3 = 6; // hash_to_point
    bank4 = 5;
    bank5 = 1;  // decompress
    bank6 = 4;
    decompress_output2 = 3;
    #10;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Run NTT
    modules = 16'b0000_0010_0000_0000; // NTT
    mode = 1'b0; // NTT
    bank1 = 4;
    bank2 = 1;
    #10;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Compute public_key * decompressed signature % 12289 (in NTT domain) by running mod_mult_q
    modules = 16'b0000_0000_0001_0000; // mod_mult_q
    bank1 = 1;
    bank2 = 2;
    bank3 = 6;
    element_count = $clog2(256);
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Run INTT
    modules = 16'b0000_0010_0000_0000; // NTT
    mode = 1'b1; // INTT
    bank1 = 6;
    bank2 = 4;
    #10;
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    // Run sub_normalize_squared_norm pipeline on the output of INTT
    modules = 16'b0000_0000_0000_1000; // sub_normalize_squared_norm
    bank1 = 5;
    bank2 = 4;
    bank3 = 3;
    element_count = $clog2(256);
    while (instruction_done !== 1'b1)
      #10;
    modules = 16'b0000_0000_0000_0000; // Stop writing to BRAM
    #10;

    while(signature_accepted === 1'b0 && signature_rejected === 1'b0)
      #10;

    if(signature_accepted === 1'b1 && signature_rejected === 1'b0)
      $display("All tests for control_unit_verify passed!");
    else
      $fatal(1, "Test failed! signature_accepted: %b, signature_rejected: %b", signature_accepted, signature_rejected);

    $finish;
  end

endmodule
