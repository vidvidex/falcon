`timescale 1ns / 1ps

module verify_top_512 (
    input logic clk,
    input logic [3:0] btns,
    output logic [3:0] leds
  );

  logic rst_n, start, start_i, start_pulse;

  // public_key - Public key in signed decimal form
  // message_len_bytes - Length of the message in bytes
  // message_blocks - Buffer for salt and message (first 5 blocks of message_blocks are the salt (40B), the rest is the message). Message is reversed and padded
  // signature_blocks - Buffer for signature value blocks
  // signature_valid_blocks - Buffer for signature value valid blocks; len(signature value) = 11 bytes = 88 bits = 64 + 24
  parameter int N = 512;
  parameter int MESSAGE_BLOCKS = 7;
  parameter int SIGNATURE_BLOCKS = 79;
  (* ram_style = "block" *) logic signed [14:0] public_key[N] = '{4162, 5489, 9391, 6649, 9653, 4881, 3686, 191, 134, 209, 164, 7392, 9905, 8495, 7293, 4815, 3294, 839, 8742, 10592, 8248, 3744, 6163, 1295, 2169, 5157, 11103, 607, 10884, 8861, 3785, 2289, 9241, 7505, 5670, 6103, 4897, 1033, 5286, 1379, 10307, 641, 8319, 9477, 3892, 1451, 2889, 9928, 12176, 11807, 2460, 8461, 8496, 10919, 7983, 8422, 6967, 6227, 3056, 4623, 6298, 5439, 8560, 8381, 734, 7393, 3021, 7927, 8717, 3151, 9823, 9422, 6225, 11787, 4442, 1744, 1977, 8793, 11698, 6676, 4991, 11730, 10672, 4332, 1636, 5963, 7370, 11877, 5902, 7279, 2631, 5393, 10232, 6038, 6327, 11727, 12059, 3780, 5228, 9144, 11746, 5752, 2103, 9384, 8473, 2373, 4415, 9460, 9163, 9091, 11614, 10776, 389, 4994, 12116, 12166, 10680, 4121, 4627, 9058, 3149, 6623, 1164, 1840, 2914, 8431, 6235, 2963, 528, 10720, 1478, 6478, 1821, 4654, 12127, 737, 5896, 9191, 10386, 1782, 3535, 5625, 9292, 7681, 9356, 3219, 6170, 5368, 2464, 7362, 1800, 9627, 10561, 9312, 11010, 691, 11883, 4994, 4376, 8197, 5674, 518, 3926, 11447, 10647, 947, 9298, 2672, 11190, 2054, 7283, 4058, 12081, 100, 8265, 10632, 1508, 11487, 3465, 6563, 3042, 9701, 7049, 10832, 3938, 454, 7534, 9593, 7653, 6910, 10880, 2253, 3080, 8254, 9522, 10765, 9859, 479, 7497, 10067, 4580, 280, 2295, 1394, 1710, 3762, 4816, 9975, 9657, 2350, 1091, 5891, 6702, 8428, 5510, 5582, 11639, 6440, 8870, 4272, 7797, 4430, 12035, 10113, 2792, 2818, 6637, 10100, 1042, 3535, 6803, 1292, 2259, 12283, 1069, 9339, 8339, 4187, 6091, 9152, 11937, 10549, 6800, 432, 2119, 8545, 8033, 5009, 6898, 6443, 9455, 4308, 4495, 3006, 973, 1311, 2099, 3551, 2920, 5410, 7656, 2551, 10436, 3799, 9322, 2896, 1384, 6401, 12144, 8529, 8969, 11439, 1767, 4604, 10224, 4718, 3247, 281, 9523, 10400, 8715, 10876, 3220, 11672, 5876, 11110, 10251, 3712, 9280, 31, 5873, 6541, 10593, 5896, 7465, 3287, 596, 7014, 6688, 9216, 3211, 7541, 3621, 1627, 11211, 8116, 8223, 7645, 1624, 1086, 1519, 3508, 4864, 4693, 9995, 11160, 5028, 8917, 10670, 11725, 4407, 7684, 3574, 7769, 11217, 3388, 10437, 8595, 6614, 5040, 560, 12067, 8406, 766, 12051, 3521, 8279, 11342, 11186, 9536, 6448, 7144, 11283, 4471, 7052, 9841, 5876, 4709, 416, 7331, 8688, 270, 11453, 8917, 11026, 749, 5376, 8800, 11980, 8403, 3112, 6159, 6873, 8818, 10665, 8260, 1857, 5604, 8087, 5490, 7480, 5503, 11255, 8114, 6356, 1018, 2077, 4388, 7627, 6154, 5256, 8042, 6668, 6749, 3720, 6601, 7170, 3286, 9454, 1698, 8050, 2181, 10272, 9682, 7891, 9685, 1280, 11146, 12040, 11577, 4561, 9234, 11516, 10454, 8819, 11330, 6188, 2029, 8474, 5279, 3773, 10890, 1504, 8012, 8613, 9968, 6197, 6906, 11904, 10787, 4280, 7088, 6238, 2380, 8858, 12020, 11990, 3004, 2930, 8324, 9421, 2053, 7550, 4959, 3675, 173, 3846, 5958, 1616, 5416, 9632, 1160, 10759, 5679, 12252, 5903, 8376, 5872, 6299, 11074, 1591, 12271, 2305, 12090, 2705, 7179, 5154, 1399, 6109, 6639, 883, 4809, 2680, 8925, 9882, 6164, 1116, 5931, 4013, 6634, 2550, 4607, 8534, 6742, 7635, 4755, 2636, 3000, 5305, 3789, 3940, 8584, 10314, 7222, 82, 8384, 3380, 939, 4861, 6147, 6388, 10256, 10522, 5609, 2142, 7634, 3690, 12218, 7314, 3177, 7339, 10847, 7451, 1710, 2574, 8926, 2865, 12070, 9897, 9950, 12195, 194};
  logic [15:0] message_len_bytes = 12;
  (* ram_style = "block" *) logic [63:0] message_blocks[MESSAGE_BLOCKS] = '{64'h837e8bcfb23c5981, 64'h41d5b10176855b9a, 64'h92208190cdfbc47f, 64'h92e859a168bea29f, 64'ha335ead74efe6969, 64'h6f57206f6c6c6548, 64'h0000000021646c72};
  (* ram_style = "block" *) logic [63:0] signature_blocks[SIGNATURE_BLOCKS] = '{64'ha0419223bd4a6372, 64'h1a58ccb4e73f1726, 64'h6639462c2cbc86c9, 64'h81588aba090bd137, 64'h7b848999c8bbb33d, 64'h93bb1ca8aa844b09, 64'h3598b2fb5ba24541, 64'h5933ca988644b44c, 64'h91a579213091ade0, 64'ha6f23b9cece4c224, 64'h652fa2675299f88b, 64'h147cec9df0fb914f, 64'h9aa94adaf9cba4db, 64'hbf52c026d4c9eb36, 64'h61e83d9fea72aff1, 64'hdb39f914f2263f74, 64'hd179686e69e490c5, 64'hdb3cef26159c884a, 64'he30b8fd9f571f986, 64'h8bc0fb2a6e615482, 64'h213bc49aa283ed2e, 64'h51fec9a331ab7b11, 64'hdddb4cb81c38177f, 64'h4263f8668cded02e, 64'hf8fcb704559002bd, 64'h75edffaa9697a774, 64'hec3076a4129facf7, 64'h2b9adc0ccb79f3d8, 64'hd9e3c28281a88eda, 64'h50786e95d40bd9c6, 64'h660ebb0dc9c1ba2e, 64'haa16962048a698cd, 64'hf61454095fe116a9, 64'h9599f8b65114d78d, 64'h3fdad68f91239d59, 64'h6499043cb8c3f0e4, 64'h88e847e2a4596d4c, 64'h4762e52bc037304c, 64'h9e28e95d25bbbf1c, 64'h18b8236dcc62f66a, 64'hc51d4bf6c1187c5b, 64'h4b9b65a2d38f0f43, 64'heb9e6f30b78a0bdf, 64'h53ebc0dcff54b308, 64'h233b9c8d9a61acba, 64'hd0165a3ec920ef41, 64'h539aafa91e4e78ab, 64'he6d4e6d5d32ee36f, 64'h43ba75bbba4fbbbe, 64'h7867772b1c3d12cf, 64'h77ac7497936dd2b5, 64'h3b736816c3d06163, 64'h10fc810b28572531, 64'h56d1e17b3d7ecdd7, 64'he0e24cfcf23eccc1, 64'h8e6d7f9018db639f, 64'h6f6bc7491378b6f5, 64'h92ab93ee57218fe5, 64'hd386ca611c772b83, 64'hda7dac6e5a0b8172, 64'hb37706c77dcefb30, 64'h862f374d40d40f51, 64'hb9424d242716e7fd, 64'hd15d05d088b59e15, 64'h6e8f15f9a4e9fcaf, 64'hfc9b3c0b552a12d4, 64'h3311ab8e958de47e, 64'h4e934138aa7c7910, 64'hdedc415068de5eff, 64'ha230de76d328a717, 64'h31de97acbc9a7392, 64'hddc718aee7922902, 64'h53eca64497ba1aae, 64'hc1647658f3205d66, 64'h26f4db4fbb31a55f, 64'hf712ce4b5d578614, 64'h9626ed3400000000, 64'h0000000000000000, 64'h0000000000000000};
  (* ram_style = "block" *) logic [6:0] signature_valid_blocks[SIGNATURE_BLOCKS] = '{64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 8};

  logic signed [14:0] public_key_element; //! Public key element (one of the 8 elements of the public key)
  logic public_key_valid; //! Is public key valid
  logic public_key_ready; //! Is ready to receive the next public key element

  logic [63:0] message;
  logic message_valid; //! Is message valid
  logic message_last;
  logic message_ready; //! Is ready to receive the next message

  logic [63:0] signature;
  logic [6:0] signature_valid; //! Number of valid bits in signature (from the left)
  logic signature_ready; //! Is ready to receive the next signature block

  logic accept; //! Set to true if signature is valid
  logic reject; //! Set to true if signature is invalid

  int public_key_block_index;
  int message_block_index;
  int signature_block_index;
  int reset_counter;

  verify #(
           .N(N),
           .SBYTELEN(666)
         )verify(
           .clk(clk),
           .rst_n(rst_n),

           .start(start_pulse),

           .public_key_element(public_key_element),
           .public_key_valid(public_key_valid),
           .public_key_ready(public_key_ready),

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
        if(reset_counter == 25)
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

        public_key_block_index <= 0;
        message_block_index <= 0;
        signature_block_index <= 0;
        message <= 0;
        message_valid <= 0;
        message_last <= 0;

        signature <= 0;
        signature_valid <= 0;

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

        // Send new public key element if module is ready for it
        if (public_key_ready && public_key_block_index < N) begin
          public_key_element <= public_key[public_key_block_index];
          public_key_block_index <= public_key_block_index + 1;
          public_key_valid <= 1;
        end
        else if (public_key_block_index >= N) // Set valid to low after we've sent all public key elements
          public_key_valid <= 0;

        // Send new message block if module is ready for it
        if (message_ready && message_block_index < MESSAGE_BLOCKS) begin
          message <= message_blocks[message_block_index];
          message_valid <= 1;
          message_block_index <= message_block_index + 1;
        end
        else if (message_block_index >= MESSAGE_BLOCKS) begin // Set valid to low after we've sent all message blocks
          message_valid <= 0;
          message <= 0;
        end
        message_last <= message_block_index == MESSAGE_BLOCKS-1;

        // Send new signature block if module is ready for it
        if(signature_ready && signature_block_index < SIGNATURE_BLOCKS) begin
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

  assign start_pulse = start == 1'b1 && start_i == 1'b0;

endmodule
