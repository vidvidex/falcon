`timescale 1ns / 1ps

module verify_top_1024 (
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
  parameter int N = 1024;
  parameter int MESSAGE_BLOCKS = 7;
  parameter int SIGNATURE_BLOCKS = 155;
  (* ram_style = "block" *) logic signed [14:0] public_key[N] = '{4936, 11833, 10782, 11469, 3092, 259, 326, 2614, 12220, 1079, 3442, 12124, 1455, 7360, 4239, 2439, 6253, 7369, 11131, 10103, 7522, 6170, 4855, 2181, 7210, 11202, 6794, 11415, 1205, 3858, 7201, 6857, 2255, 341, 5394, 2215, 6901, 11639, 1796, 5587, 6257, 6232, 10306, 3126, 7369, 5664, 165, 7270, 459, 44, 2204, 6450, 5033, 4067, 4111, 8362, 3170, 9104, 6148, 2024, 6335, 11527, 3615, 8607, 8815, 4961, 5939, 11842, 188, 10659, 8488, 4549, 2988, 3374, 282, 11992, 5714, 445, 2867, 10862, 1559, 11674, 351, 3242, 3163, 9200, 9435, 4876, 10912, 7662, 5551, 7898, 10916, 1056, 8247, 2131, 4990, 11563, 6368, 575, 11884, 12100, 7869, 10940, 10456, 8104, 11389, 5449, 11359, 11298, 3106, 7068, 2153, 2666, 7404, 4751, 3251, 9074, 5356, 3356, 5481, 9233, 5764, 218, 805, 6461, 6291, 1239, 8359, 5702, 11193, 4774, 3248, 6526, 7690, 4389, 7845, 1286, 9999, 739, 3323, 4608, 8831, 10169, 1615, 8218, 7717, 7715, 219, 4062, 396, 7001, 9614, 4011, 6505, 11394, 5066, 4933, 4273, 8902, 9798, 8997, 6308, 1083, 8273, 8382, 4882, 500, 6590, 1728, 892, 8007, 10999, 11083, 9183, 7009, 7197, 3012, 7244, 2622, 6712, 10645, 2538, 6022, 4400, 1668, 8978, 12246, 3999, 6005, 8578, 8200, 8500, 7982, 3317, 10994, 1720, 1452, 7460, 8, 7336, 3130, 8223, 4769, 11447, 3045, 9030, 5959, 8221, 4576, 572, 8648, 1276, 12036, 7043, 8584, 897, 4832, 808, 2597, 572, 4110, 749, 10956, 6875, 4402, 22, 5802, 8336, 1509, 2119, 821, 8098, 7919, 3050, 1024, 4226, 7052, 2902, 8154, 863, 6596, 9906, 3254, 8087, 10134, 11482, 11754, 1768, 10490, 6219, 2363, 12188, 10134, 7974, 4986, 4501, 9931, 4738, 5563, 6295, 6316, 2117, 6371, 569, 4660, 4962, 9825, 5189, 11898, 5648, 5348, 8033, 2564, 6091, 7915, 10596, 8990, 8903, 1394, 1428, 10291, 7050, 6009, 6129, 2385, 6440, 10193, 7438, 11881, 7650, 9489, 8893, 11154, 9577, 7717, 6441, 2464, 10868, 9825, 8582, 3595, 5499, 10488, 6025, 10318, 3089, 2637, 7313, 10962, 8474, 12112, 8813, 12097, 783, 7116, 3844, 4469, 10276, 8133, 6805, 10115, 3594, 10693, 6920, 10293, 10674, 6151, 5929, 3633, 6496, 2336, 10885, 5477, 8658, 9093, 5118, 7823, 2574, 5290, 8166, 2591, 8621, 11553, 3571, 8172, 9829, 6405, 8623, 11535, 5418, 5371, 11949, 7366, 9182, 2817, 8198, 4922, 5506, 11179, 10051, 739, 6473, 10523, 876, 757, 11511, 10972, 11871, 1645, 1219, 4043, 8886, 8162, 9772, 2829, 8756, 7539, 10662, 2409, 5292, 5372, 11858, 12188, 8424, 10874, 4340, 741, 11676, 2549, 8931, 2170, 8488, 2907, 813, 5498, 10969, 2975, 11694, 11443, 6313, 4199, 6071, 5741, 6844, 5262, 1576, 3533, 5746, 2554, 2285, 4872, 3488, 11959, 3585, 12183, 11811, 2280, 11478, 2987, 10174, 8226, 6223, 5610, 9883, 2850, 1282, 826, 8218, 2076, 11708, 5449, 2335, 1835, 9319, 7730, 3472, 141, 2468, 4701, 7293, 6647, 1920, 5714, 8562, 9655, 7133, 2199, 1013, 6945, 12150, 8460, 6537, 1720, 11179, 8448, 8842, 7667, 826, 11132, 9069, 10081, 4074, 2283, 8554, 12234, 242, 4277, 604, 7248, 6256, 8047, 6258, 3900, 6890, 8606, 11315, 9147, 2897, 10477, 12120, 5993, 2314, 2361, 3869, 8461, 10953, 5583, 10328, 11186, 10633, 10337, 2581, 2534, 9700, 11820, 8613, 10477, 5577, 3109, 9041, 1435, 239, 5944, 11667, 8306, 3145, 11544, 7416, 11134, 8732, 10859, 2800, 8484, 9492, 8499, 7514, 1724, 11327, 1970, 10595, 672, 6498, 9436, 10265, 1658, 11705, 9912, 11165, 6866, 9444, 11368, 8310, 11971, 578, 4917, 6133, 11723, 3267, 7412, 12189, 11655, 4491, 5628, 6426, 8614, 7499, 4728, 6813, 3115, 2448, 4662, 301, 12119, 7646, 1948, 3513, 581, 1753, 1795, 7198, 9732, 3222, 7227, 6130, 10003, 7091, 11854, 2746, 9724, 8305, 1005, 4703, 6681, 5211, 9865, 7687, 3821, 4448, 4881, 5082, 5356, 11468, 6294, 5386, 9382, 8158, 8144, 8395, 9696, 6717, 3887, 3544, 7485, 3954, 8138, 4582, 11240, 8590, 6215, 598, 8696, 1457, 530, 11839, 10516, 5437, 8643, 5637, 9416, 9299, 7841, 2880, 835, 8392, 5352, 2055, 6863, 10406, 1308, 6254, 510, 4873, 7223, 1483, 4299, 11275, 5151, 6320, 5260, 4219, 7977, 3721, 2856, 3044, 8623, 5454, 8658, 7681, 78, 2559, 11158, 1836, 6408, 934, 9362, 237, 4925, 6907, 1516, 957, 12074, 1749, 1669, 251, 257, 5480, 9405, 7988, 3420, 2777, 9138, 4169, 1082, 5099, 4948, 5508, 3050, 12032, 2967, 6509, 11642, 1966, 10156, 26, 4778, 2227, 9411, 11836, 2680, 11116, 6095, 6989, 5127, 6123, 448, 12268, 2893, 6763, 5534, 10449, 2953, 5886, 365, 6053, 11043, 4673, 2008, 1988, 10045, 8413, 8367, 2166, 7806, 9765, 563, 8386, 3406, 2473, 11039, 11685, 8438, 11745, 2276, 235, 9600, 9990, 2298, 1087, 5937, 7457, 7424, 5187, 10592, 11678, 8866, 10277, 5050, 9797, 4170, 4434, 9917, 12119, 6020, 853, 4672, 7563, 2204, 2240, 9755, 2434, 2118, 8309, 6894, 3804, 8597, 4475, 10198, 5640, 3645, 4675, 10553, 3702, 1378, 4740, 3505, 6000, 5617, 6602, 1490, 3373, 5140, 847, 1402, 10672, 8803, 4823, 7188, 322, 8829, 3298, 3802, 211, 997, 11982, 7244, 4823, 5959, 5973, 402, 11028, 5078, 4606, 5442, 8334, 1616, 2475, 1610, 5344, 849, 8399, 11148, 4716, 2179, 12016, 4763, 8785, 6987, 12247, 9399, 2086, 10787, 2057, 11563, 3749, 6785, 4941, 2089, 8641, 10957, 1585, 2758, 2984, 10302, 11552, 1108, 9222, 2659, 3060, 10081, 496, 9949, 4141, 33, 11033, 3278, 9238, 1256, 5597, 5000, 6776, 746, 11449, 11415, 10505, 4736, 1438, 3904, 10345, 4420, 4584, 4111, 8091, 10117, 4358, 1034, 3820, 4204, 3211, 4521, 3987, 10921, 3462, 7261, 6201, 12083, 11756, 8117, 12006, 9899, 7960, 9066, 5819, 11246, 8254, 9519, 2396, 9105, 1661, 4698, 2491, 2994, 3069, 10620, 3504, 5685, 6374, 1530, 1069, 621, 11230, 11727, 9881, 6260, 5083, 6660, 1320, 8054, 11485, 11726, 1747, 4204, 2475, 4947, 10852, 3359, 11082, 12074, 9449, 7727, 10150, 589, 8155, 5442, 722, 899, 6424, 5321, 5678, 12159, 9658, 2952, 1700, 9146, 12051, 2616, 3228, 10160, 10681, 495, 2020, 7109, 8378, 7756, 11225, 3083, 1757, 10948, 5393, 4049, 8623, 1540, 1436, 1361, 3078, 7924, 5771, 10213, 10272, 11591, 5705, 5271, 8483, 10024, 1750, 7505, 5555, 9048, 7538, 2112, 4660, 12158, 1454, 9302, 11859, 1012, 5432, 9524, 213, 5514, 2212, 7678, 2631, 2782, 1372, 1365, 4268, 6168, 8437, 7207, 6825, 2387, 5172, 10300, 3489, 517, 8004, 4881, 12198, 5222, 8515, 3294, 3025, 7649, 11875, 11388, 6202, 10209, 6414, 3470, 6800, 10828, 8141, 5105, 11995, 5469, 2714, 9985, 4088, 6957, 45, 3675, 2613, 1460, 9097, 722, 7804, 10402, 9574, 3545, 11669, 6852, 12079, 4327, 3994, 8155, 1252, 4294, 7356, 5434, 897, 8731, 2079, 11238};
  logic [15:0] message_len_bytes = 12;
  (* ram_style = "block" *) logic [63:0] message_blocks[MESSAGE_BLOCKS] = '{64'h0710fee4bdb0fd90, 64'hb3fd641a3a72be23, 64'h29ad47b9369dc53f, 64'h07e074cf50d8cea3, 64'h334a2de7401c8ece, 64'h6f57206f6c6c6548, 64'h0000000021646c72};
  (* ram_style = "block" *) logic [63:0] signature_blocks[SIGNATURE_BLOCKS] = '{64'h2ceb4ad41d47d6c5, 64'hc57b9f13566ae859, 64'h176df99e446e1c34, 64'h37edfdfdd9998de7, 64'h79fa64e4526ed064, 64'heb471b78ee608f44, 64'hd7bd9fbc262b9cad, 64'h88f2fe0a2470a3c5, 64'h577d9e68c76004dd, 64'h0032ea8eca0aaa97, 64'hc4a0dbc4972b1776, 64'h00e54caa7a0f26c6, 64'h3485c95c8439b181, 64'h134d2ec50d4df23e, 64'hf4f9029dcb3988ea, 64'h2c8a6f098c899d60, 64'ha1a43d614eecd0a6, 64'h5a3ac65e94ac7512, 64'h12e3342f55aa7d8e, 64'h71594b579cc74ab7, 64'h2412ff329b4e755a, 64'h859bb67023ceae3f, 64'h94b17814130c6b95, 64'h09ad13d886217226, 64'hfd84238a3562551b, 64'hb46e6f32e8641020, 64'hf0147b818fa914ce, 64'hecc0f4f9f2a439a3, 64'h92aaf4b22b024226, 64'h48939ea63704293d, 64'hda31095b3702ba2c, 64'hef253ae6c915bbf1, 64'hbdede6297b99734e, 64'h7d1c3ccdce2074de, 64'hcc2ad06554849acf, 64'h96660370e058640e, 64'h5e877e9d7a8a9e8d, 64'hd0f6535569196b81, 64'hfeebb21cf74b5529, 64'h4a095e8707ecf244, 64'h629854d70462949e, 64'h793945ed3e5322a7, 64'h98af26a89099f5dd, 64'h1ca0523643a79c4d, 64'h987e388b8b5c9854, 64'heab13cd57ad3aa3d, 64'hda14621917775cfc, 64'h64dc618c773acaaa, 64'hd9ba11dc4e1f5889, 64'h5e1105499c9ce7b6, 64'h1ae98cf5c11fbabd, 64'h997e8048d4f29597, 64'h67d4f4633d03138e, 64'h621a617e7f0aaa36, 64'h9ea89825d5d9b455, 64'h6a99668898628f9b, 64'h026a2250ea1eb663, 64'hf868f911022d4dd5, 64'h2d878a898d92c1aa, 64'h99c5e53df0629965, 64'h8badacd5b6151e8d, 64'he64c871c4bed31b4, 64'h9c2e7dab366f10e9, 64'h272655548822f8fb, 64'h43fb2dc7a593b801, 64'h7cffefb9e8673623, 64'h9483c65f9def1edd, 64'h162c19fc8e9a37c4, 64'h6d73fb0921bcf3e2, 64'hd6252f1641f24e2a, 64'h3d097f9965befb88, 64'hc414e72dc1bc6b60, 64'hc62e2cd85f211174, 64'hd79d768240e8820c, 64'h2bac54d8e43b32b7, 64'h4a87c8c25423e84d, 64'h4741a59639bb529d, 64'h938c20301317c42a, 64'hb6691418d3f2904b, 64'h9f54b92196623b8f, 64'h3bb2dc7ae72481d8, 64'h9038b233dceeb8bd, 64'h130844e928715ac3, 64'h9263111dec3ebe82, 64'hb29d1956dde2629e, 64'h7d99d287f6f0cb99, 64'h6b97378d14157c53, 64'h150c2ebe08f9e90f, 64'h8b58988a59339fee, 64'h5f96895db6d3783a, 64'h29b72313c5883c4f, 64'hca85c18d614d0263, 64'h67532cd29943bc54, 64'h8fd54bd8446ef408, 64'h395b67f25f642b34, 64'h822dcebb08b5b768, 64'h138254f28e443a21, 64'hc1c1c408dd758cae, 64'hf68c732bfa2dbebc, 64'h59744f1b67133d18, 64'h46450cfab68e810a, 64'hb5227d2ebfee595d, 64'he1ffef1e4e940310, 64'hc2d0b008846b08cf, 64'h250934ca9cd72e70, 64'hdea509a24fcbb6a3, 64'h06a2e6730e2bc190, 64'h6cb59bce0c7d8cd8, 64'h2014a2e6e174f1f8, 64'he54ddf769ac60740, 64'h6555abbeff94a78d, 64'h8311d82004356df4, 64'h66fdd346bac4bc91, 64'h55ad6dcece382ecb, 64'h792f316c2137fb6d, 64'he36b86255fefb82b, 64'h01c68644e393bad9, 64'h501c28336441d440, 64'hc53b05a30266a6bb, 64'h23cd876ca0c4a6ad, 64'hbed81f9e22666875, 64'hfb29d305a776e8b9, 64'h779f856b8631cf4d, 64'h4309d9472466575c, 64'h74bdc3299a7bb8ba, 64'hb59237b2534c8679, 64'h4d5a70fb05354d55, 64'he6dcfefa38dcebd1, 64'h2dd2b13ce1b8d669, 64'h2287e7168715cd8b, 64'hf3d4b4175d4b9aed, 64'heb88869262cbc2d3, 64'h8dbb0ea7f2af34ba, 64'hf103412abf62e7a7, 64'h9e595b2b952a4308, 64'ha30eae01cfdf09ab, 64'h24a55d3c3b6d2bd5, 64'hc0faf22bac7f1886, 64'hcd901c191fb8d739, 64'hd6c9b377e15bcfed, 64'hdb07044db429e591, 64'h41f1e1d0b3cc94d7, 64'h4a8b0bfabbd9e7e9, 64'h9e66893133e9e257, 64'h1520d93302d99729, 64'hc136df961e87f29f, 64'h5d8961a91879caf8, 64'h6a686d8e32319537, 64'hddad515fc421d8d2, 64'h34c32630a9e6df18, 64'ha4725596761646b3, 64'h4d63a3a1bfd76a3e, 64'hd9d229d4f16b4c2f, 64'h87dc849a2b4c0000, 64'h0000000000000000};
  (* ram_style = "block" *) logic [6:0] signature_valid_blocks[SIGNATURE_BLOCKS] = '{64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 56};

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
           .SBYTELEN(1280)
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
