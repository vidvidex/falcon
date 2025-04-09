`timescale 1ns / 1ps

module top_512 (
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
  (* ram_style = "block" *) logic signed [14:0] public_key[N] = '{1600, 11566, 8571, 4686, 10920, 9940, 6729, 7402, 1766, 9278, 8872, 3544, 8661, 11370, 215, 2995, 11827, 5591, 1613, 11982, 1095, 4313, 9885, 2387, 4094, 3713, 11646, 2205, 10593, 5044, 10242, 1539, 4696, 9298, 10422, 5043, 1922, 12125, 8177, 3057, 7715, 9471, 3938, 4414, 9055, 8048, 5433, 3686, 8483, 860, 8478, 3836, 10123, 477, 10404, 10509, 6934, 2501, 5466, 4942, 9688, 723, 11661, 1613, 8430, 6184, 2204, 10216, 3833, 1489, 337, 2675, 10460, 11271, 5043, 1880, 1559, 7960, 2664, 10043, 959, 8166, 792, 5821, 4307, 7048, 9556, 1450, 11854, 448, 7113, 4057, 8369, 2602, 9286, 259, 5377, 10703, 11664, 10405, 4653, 2612, 1503, 7725, 2564, 5570, 2139, 8170, 1475, 10748, 4676, 2173, 2946, 8470, 3239, 4751, 1810, 11901, 7642, 11128, 4012, 2227, 9236, 9944, 402, 9941, 4272, 8515, 3139, 7735, 11314, 9458, 1552, 3789, 9365, 3024, 4619, 4541, 3763, 394, 7140, 9598, 8158, 9094, 5068, 8539, 8690, 3884, 4017, 10221, 8134, 8086, 2035, 146, 8397, 10405, 8737, 9982, 1340, 10661, 1293, 10451, 4510, 7315, 2547, 1378, 12007, 4990, 1799, 2376, 921, 8925, 3804, 4356, 2815, 11535, 6686, 6240, 10473, 3968, 5745, 7764, 6730, 6292, 2687, 10964, 10461, 2635, 10190, 7651, 811, 3697, 8785, 10938, 7128, 12092, 323, 1494, 6061, 6231, 5467, 6583, 3056, 5023, 11062, 4099, 3002, 5146, 3993, 6347, 5217, 6227, 6912, 5440, 4857, 9947, 674, 1942, 12201, 3663, 11901, 1444, 5194, 6490, 8689, 11124, 8763, 4082, 11013, 8460, 6870, 2629, 5863, 3710, 8106, 8041, 1195, 9473, 3648, 7363, 4018, 3045, 2126, 446, 9276, 10562, 5389, 7032, 6512, 3963, 4316, 7804, 11916, 8621, 7350, 4142, 5641, 6589, 9474, 7497, 2247, 6212, 1932, 2460, 2984, 953, 4488, 5432, 11901, 6712, 6132, 8035, 3219, 3104, 4781, 3089, 7586, 4919, 2539, 11440, 10801, 6624, 7329, 2978, 2126, 8900, 4612, 4400, 8758, 5977, 6906, 6126, 9841, 6422, 5409, 10517, 2228, 3098, 555, 8146, 2317, 9331, 6085, 4473, 10052, 7751, 9335, 9668, 11432, 1588, 11533, 9123, 9471, 12135, 10392, 1515, 11991, 8074, 11283, 1520, 2230, 5755, 1520, 7238, 11778, 1559, 9044, 7636, 2962, 10789, 1096, 1649, 8574, 4236, 3155, 8444, 11517, 9405, 2115, 7771, 6881, 8049, 2255, 11491, 2068, 6348, 10982, 10564, 5130, 3642, 7084, 1616, 8973, 1963, 5552, 3204, 2572, 5960, 7122, 9812, 8525, 11315, 9166, 1262, 9615, 1997, 9501, 5403, 6759, 8930, 3317, 10566, 7559, 9289, 10549, 5548, 1379, 3641, 1155, 5750, 12120, 8284, 5033, 10498, 9712, 7200, 9240, 8777, 1985, 6319, 8308, 6397, 7383, 232, 2732, 3978, 9741, 9256, 5816, 7735, 11912, 8466, 6928, 10967, 3412, 2178, 11848, 3388, 3351, 9818, 7374, 5821, 11878, 11534, 10265, 4718, 5604, 10161, 3752, 8550, 8883, 10572, 9301, 2978, 6055, 11230, 10024, 3218, 6985, 3014, 8604, 7482, 12075, 5910, 6403, 851, 161, 1866, 11679, 11454, 1507, 9793, 11282, 1475, 4663, 1803, 7654, 8912, 10874, 8827, 8380, 8750, 5187, 3906, 6301, 11826, 189, 10268, 5664, 10586, 3512, 6379, 3542, 5361, 2528, 11800, 5688, 9943, 3812, 9462, 2839, 4759, 5337, 10381, 2044, 10449, 4391, 2846, 4846, 5387, 10637, 12184, 9011, 3265, 5680, 3473, 1838, 11296, 8878, 6136, 10612, 7764, 357, 5152, 5824, 11602, 977, 11807, 2551, 804, 8215, 12231, 1657, 2039, 3827, 1430, 12012, 291, 1003, 140, 5637, 6420};
  logic [15:0] message_len_bytes = 12;
  (* ram_style = "block" *) logic [63:0] message_blocks[MESSAGE_BLOCKS] = '{64'ha15cf12f22a35cbd, 64'h77a517bb6bebe0a6, 64'h3c8df85266833103, 64'h1536fff4b7eeb842, 64'h79f9094c80f1380b, 64'h6f57206f6c6c6548, 64'h0000000021646c72};
  (* ram_style = "block" *) logic [63:0] signature_blocks[SIGNATURE_BLOCKS] = '{64'h06e743735f59c269, 64'h3a5e69bd23c2497e, 64'h79395cb5a2ec5baa, 64'h090a6d772294c419, 64'h2691b337dd49437c, 64'h1284e0b4e2b1a46a, 64'h74c36219c4e510b0, 64'h4d9af4c15666101d, 64'h8b9d37f895e600eb, 64'h72b47c86b4e314db, 64'h53d31b440cd9f5fa, 64'ha631047753de2994, 64'h3b5f47c8c9221f54, 64'he1302892f48f6a23, 64'hcaced1f6dea7fec3, 64'h0f2a68b2ef0a419f, 64'hffb40c3ead8955e3, 64'hbaf2c7e24ae635ad, 64'hceed6490bb85e9c8, 64'h3cc89757ff1b4354, 64'ha6d14d9c1d397f48, 64'hbb5963189399d3a3, 64'hed0ca169d33ece79, 64'hcbe4ea5972acb8fc, 64'hdf9b06c5ac486b93, 64'h07bb6ddce455b8a7, 64'hd5c49bd13e520d5e, 64'h41caaecbf5a536f5, 64'h83a4be049225be4a, 64'h67bcca4d8d2c44ce, 64'hdb8091d71aa9232f, 64'h2be72b16797ed2bd, 64'h6a449e34c30e23d6, 64'hcfcbca9659f30cce, 64'hbb68e640df8eaad1, 64'h81a1aa0db5a79ba2, 64'h526d1706cc856ca1, 64'h8d0ec952cebdf1de, 64'h6454962b3423aec5, 64'h69d8824353a7f861, 64'h8ec324e91cb8b94d, 64'h9ddc645f3de74868, 64'h669befa6661b0bef, 64'h1fcbd2c5baea5f14, 64'hbbf0dcbf293d1e1c, 64'hcdf0d65d39dcdf15, 64'h79be8af09c79fda6, 64'h5990571046e28eec, 64'h6264ac39937d52f9, 64'h00fc5fd41bf55201, 64'he5f9774d8ff481c8, 64'ha8734e03e0e7e379, 64'h709a25b1ede5091f, 64'h7ca9522768fb5278, 64'hb4a966832ffb1904, 64'h130aa1a7fe9e16a1, 64'hecfbdbb66fa2a0d8, 64'h5976e6db6da1252b, 64'he61eb792edc16eb1, 64'hd536708c31a85be3, 64'ha5224c0d3a99d899, 64'hec617a82981c3396, 64'hce6fd59904f1ffd0, 64'h7ba55b924aa15b73, 64'h6b729beccd5215fc, 64'h038d81302e7d5631, 64'hfadbf11515ae2919, 64'h50cfa4d1e1f51137, 64'h568f6fb8df1a7e54, 64'hc53aad65f2c33fc9, 64'h8a0dbc21084e9c28, 64'hef85526b99713ac6, 64'hb0b1efabe2719232, 64'ha14d9312c4e11b8f, 64'h48d047f70b86c0d7, 64'h173c42119a72c47c, 64'ha5485057dbc0a1c0, 64'h0000000000000000, 64'h0000000000000000};
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
