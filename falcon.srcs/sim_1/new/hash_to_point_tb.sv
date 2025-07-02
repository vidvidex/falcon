`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Hashing takes 2615 ns, which is more than the default 1000 ns that the simulations run for in Vivado.
// Click Run to finish the simulation and see the results.
//
//////////////////////////////////////////////////////////////////////////////////

module hash_to_point_tb;

  parameter int N = 512;

  logic clk;
  logic rst_n;
  logic start;

  logic [15:0] message_len_bytes; //! Length of the message in bytes

  logic[14:0] expected_polynomial [N];
  logic done;

  logic [`BRAM_ADDR_WIDTH-1:0] message_address;
  logic [`BRAM_ADDR_WIDTH-1:0] result_address;

  logic initializing = 1'b1; // Are we still initializing the testbench (changes who writes to the BRAM)

  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_a, bram_addr_b;
  logic [`BRAM_DATA_WIDTH:0] bram_din_b;
  logic [`BRAM_DATA_WIDTH:0] bram_dout_a, bram_dout_b;
  logic bram_we_b;
  bram_1024x128 bram_1024x128 (
                  .addra(bram_addr_a),
                  .clka(clk),
                  .dina(0),
                  .douta(bram_dout_a),
                  .wea(0),

                  .addrb(initializing ? init_bram_addr : bram_addr_b),
                  .clkb(clk),
                  .dinb(initializing ? init_bram_din : bram_din_b),
                  .doutb(),
                  .web(initializing ? init_bram_we : bram_we_b)
                );

  hash_to_point #(
                  .N(N)
                )
                hash_to_point(
                  .clk(clk),
                  .rst_n(rst_n),
                  .start(start),
                  .message_len_bytes(message_len_bytes),

                  .message_address(message_address),
                  .result_address(result_address),

                  .input_bram_addr(bram_addr_a),
                  .input_bram_data(bram_dout_a),

                  .output_bram_addr(bram_addr_b),
                  .output_bram_data(bram_din_b),
                  .output_bram_we(bram_we_b),

                  .done(done)
                );

  logic [`BRAM_ADDR_WIDTH:0] init_bram_addr;
  logic [`BRAM_DATA_WIDTH:0] init_bram_din;
  logic init_bram_we;

  logic signed [14:0] coefficient;

  always #5 clk = ~clk;


  initial begin
    message_address = 0;
    result_address = 64;


    clk = 0;
    rst_n = 0;
    #15;
    rst_n = 1;

    message_len_bytes = 16'h0049;

    // Careful: endianness is different than in the python implementation
    init_bram_we = 1;
    init_bram_addr = 0;
    init_bram_din = 64'h33b3c07507e42017;
    #10;
    init_bram_addr = 1;
    init_bram_din = 64'h48494d832b6ee2a6;
    #10;
    init_bram_addr = 2;
    init_bram_din = 64'hc93bff9b0ee343b5;
    #10;
    init_bram_addr = 3;
    init_bram_din = 64'h50d1f85a3d0de0d7;
    #10;
    init_bram_addr = 4;
    init_bram_din = 64'h04c6d17842951309;
    #10;
    init_bram_addr = 5;
    init_bram_din = 64'hd81c4d8d734fcbfb;
    #10;
    init_bram_addr = 6;
    init_bram_din = 64'heade3d3f8a039faa;
    #10;
    init_bram_addr = 7;
    init_bram_din = 64'h2a2c9957e835ad55;
    #10;
    init_bram_addr = 8;
    init_bram_din = 64'hb22e75bf57bb556a;
    #10;
    init_bram_addr = 9;
    init_bram_din = 64'h00000000000000c8;
    #10;
    init_bram_we = 0;

    expected_polynomial = '{3433,4506,10834,4901,438,1569,11215,585,2342,8788,6079,193,10201,11612,5972,10562,2909,2271,6670,5601,3459,2283,2961,11623,4243,177,7454,6819,9663,2505,2581,10800,6109,11991,2023,1045,5482,8395,2591,4729,1302,7658,1772,336,11239,9684,9895,243,7015,2497,1830,9190,5939,10525,8899,10590,7929,4217,861,7554,6523,4410,11417,7708,7839,5102,4753,7113,12081,5276,7849,8065,7069,375,9075,11666,10014,5133,6659,7754,10459,6060,5453,9230,11978,6296,10670,3149,4157,11985,7011,3544,9643,8547,1628,3620,2266,4909,7541,8555,8111,6085,3254,7776,12270,4859,12093,6620,1866,5548,4324,9890,745,7910,10721,7065,8936,4676,2008,11510,1614,11750,98,8225,11107,4516,2027,11099,9253,3840,1991,3914,5676,5001,500,3572,6207,3489,2478,4923,4229,3225,10092,3931,3258,10699,234,8725,2241,0,1677,3502,9909,11407,5268,2201,7269,10357,5455,3116,6426,770,12192,2510,661,11441,6514,1625,1029,7422,1531,1610,3643,8475,1346,5040,627,2255,8620,3253,8094,10216,1216,4405,11557,1779,3104,12056,654,11734,8570,4703,7023,6463,5344,3134,10943,10584,12001,3199,1890,5403,3205,1933,5728,1,234,3164,6299,196,11546,594,2623,3005,10624,1637,9995,6059,1989,265,5178,1255,12274,5195,3873,11275,3156,7105,4618,5738,1978,10413,1686,135,9186,4378,3418,6706,11214,1395,2900,8691,3810,4337,6171,4678,326,3454,10949,7157,8535,10468,5003,5996,6410,10017,6189,8900,9831,9332,4573,1638,5570,1000,4733,1961,458,4617,6961,11421,5590,10286,9497,1030,4931,2181,11781,1670,3434,4953,5074,10684,6826,4066,10132,9612,6885,6100,8801,8564,4642,5230,9411,4296,10944,11254,8944,11451,9841,10844,11617,8860,9177,8726,2557,11254,9473,820,3035,2176,8217,1801,4956,4477,10873,10163,73,2786,2529,10384,2035,3567,2916,1017,9668,5025,10674,6727,4978,9497,5320,3102,7688,4257,9380,3366,4526,624,7319,12048,3996,10551,1114,3689,2040,8793,11988,715,167,4146,6819,8611,4407,12005,7266,3271,6510,129,4826,7939,5836,8979,7402,2965,4196,8710,7,9802,12118,8325,6891,4560,3874,8109,2478,7197,3664,11355,3583,4193,1875,2745,4323,8577,4399,9718,10361,4572,2043,5753,10197,11116,9037,64,883,6546,283,1560,8220,3289,6990,1041,2039,2045,10395,9826,11494,9731,747,9308,1844,6498,1561,6804,2508,8956,8535,9240,7146,6053,12138,1750,11655,559,1271,10655,10458,3529,6055,9100,834,10354,10554,1356,10254,3912,11148,6852,2295,1496,9269,5944,4079,6980,11780,8799,6119,2548,11204,362,2412,7769,10897,416,8646,10351,7932,2736,8006,3604,11884,9084,4169,12175,224,8995,9920,11596,4458,12157,896,12017,6287,17,4491,4185,6837,5621,11498,5536,7783,5159,1899,10454,799,3148,6710,6819,7856,11957,11911,4589,2558,10018,4213,8189,10308,11702,12147,10414,6779,1046,3121,6964,6127,26,5224,6516,4588,2189,7209,10174};
    initializing = 0; // We are done initializing the BRAM
    #20;

    // Start the module
    start = 1;
    #10;
    start = 0;
    #20;

    while(done !== 1'b1)
      #10;

    for (int i = 1; i <= N; i++) begin
      bram_addr_a = result_address + i;
      #10;
      coefficient = bram_dout_a[14:0];
      if (i > 1 && coefficient !== expected_polynomial[i-1]) begin // i>1 and -1 used to account for BRAM read latency
        $fatal(1, "Test failed at index %d. Expected %d, got %d", i, expected_polynomial[i], coefficient);
      end
    end

    $display("All tests for hash_to_point passed!");
    $finish;

  end
endmodule





// `timescale 1ns / 1ps
// //////////////////////////////////////////////////////////////////////////////////
// //
// // Hashing takes 2615 ns, which is more than the default 1000 ns that the simulations run for in Vivado.
// // Click Run to finish the simulation and see the results.
// //
// //////////////////////////////////////////////////////////////////////////////////

// module hash_to_point_tb;

//   parameter int N = 512;

//   logic clk;
//   logic rst_n;
//   logic start;

//   logic [15:0] message_len_bytes; //! Length of the message in bytes
//   logic [63:0] messages [16];
//   logic [63:0] message;
//   logic message_valid; //! Is message valid
//   logic message_last; //! Is message valid

//   logic ready; //! Are we ready to receive the next message? When set we are ready to receive the next message

//   logic signed [14:0] coefficient;
//   logic [$clog2(N)-1:0] coefficient_index;
//   logic coefficient_valid;

//   logic[14:0] expected_polynomial [N];
//   logic done;
//   int i;

//   hash_to_point #(
//                   .N(N)
//                 )
//                 uut(
//                   .clk(clk),
//                   .rst_n(rst_n),
//                   .start(start),
//                   .message_len_bytes(message_len_bytes),
//                   .message(message),
//                   .message_valid(message_valid),
//                   .message_last(message_last),
//                   .ready(ready),
//                   .coefficient(coefficient),
//                   .coefficient_valid(coefficient_valid),
//                   .coefficient_index(coefficient_index),
//                   .done(done)
//                 );

//   always #5 clk = ~clk;


//   initial begin
//     clk = 0;
//     rst_n = 0;
//     #15;
//     rst_n = 1;

//     message_len_bytes = 16'h0049;
//     messages[0] = 64'h33b3c07507e42017; // Endianness is different than in the python implementation
//     messages[1] = 64'h48494d832b6ee2a6;
//     messages[2] = 64'hc93bff9b0ee343b5;
//     messages[3] = 64'h50d1f85a3d0de0d7;
//     messages[4] = 64'h04c6d17842951309;
//     messages[5] = 64'hd81c4d8d734fcbfb;
//     messages[6] = 64'heade3d3f8a039faa;
//     messages[7] = 64'h2a2c9957e835ad55;
//     messages[8] = 64'hb22e75bf57bb556a;
//     messages[9] = 64'h00000000000000c8;

//     expected_polynomial = '{3433,4506,10834,4901,438,1569,11215,585,2342,8788,6079,193,10201,11612,5972,10562,2909,2271,6670,5601,3459,2283,2961,11623,4243,177,7454,6819,9663,2505,2581,10800,6109,11991,2023,1045,5482,8395,2591,4729,1302,7658,1772,336,11239,9684,9895,243,7015,2497,1830,9190,5939,10525,8899,10590,7929,4217,861,7554,6523,4410,11417,7708,7839,5102,4753,7113,12081,5276,7849,8065,7069,375,9075,11666,10014,5133,6659,7754,10459,6060,5453,9230,11978,6296,10670,3149,4157,11985,7011,3544,9643,8547,1628,3620,2266,4909,7541,8555,8111,6085,3254,7776,12270,4859,12093,6620,1866,5548,4324,9890,745,7910,10721,7065,8936,4676,2008,11510,1614,11750,98,8225,11107,4516,2027,11099,9253,3840,1991,3914,5676,5001,500,3572,6207,3489,2478,4923,4229,3225,10092,3931,3258,10699,234,8725,2241,0,1677,3502,9909,11407,5268,2201,7269,10357,5455,3116,6426,770,12192,2510,661,11441,6514,1625,1029,7422,1531,1610,3643,8475,1346,5040,627,2255,8620,3253,8094,10216,1216,4405,11557,1779,3104,12056,654,11734,8570,4703,7023,6463,5344,3134,10943,10584,12001,3199,1890,5403,3205,1933,5728,1,234,3164,6299,196,11546,594,2623,3005,10624,1637,9995,6059,1989,265,5178,1255,12274,5195,3873,11275,3156,7105,4618,5738,1978,10413,1686,135,9186,4378,3418,6706,11214,1395,2900,8691,3810,4337,6171,4678,326,3454,10949,7157,8535,10468,5003,5996,6410,10017,6189,8900,9831,9332,4573,1638,5570,1000,4733,1961,458,4617,6961,11421,5590,10286,9497,1030,4931,2181,11781,1670,3434,4953,5074,10684,6826,4066,10132,9612,6885,6100,8801,8564,4642,5230,9411,4296,10944,11254,8944,11451,9841,10844,11617,8860,9177,8726,2557,11254,9473,820,3035,2176,8217,1801,4956,4477,10873,10163,73,2786,2529,10384,2035,3567,2916,1017,9668,5025,10674,6727,4978,9497,5320,3102,7688,4257,9380,3366,4526,624,7319,12048,3996,10551,1114,3689,2040,8793,11988,715,167,4146,6819,8611,4407,12005,7266,3271,6510,129,4826,7939,5836,8979,7402,2965,4196,8710,7,9802,12118,8325,6891,4560,3874,8109,2478,7197,3664,11355,3583,4193,1875,2745,4323,8577,4399,9718,10361,4572,2043,5753,10197,11116,9037,64,883,6546,283,1560,8220,3289,6990,1041,2039,2045,10395,9826,11494,9731,747,9308,1844,6498,1561,6804,2508,8956,8535,9240,7146,6053,12138,1750,11655,559,1271,10655,10458,3529,6055,9100,834,10354,10554,1356,10254,3912,11148,6852,2295,1496,9269,5944,4079,6980,11780,8799,6119,2548,11204,362,2412,7769,10897,416,8646,10351,7932,2736,8006,3604,11884,9084,4169,12175,224,8995,9920,11596,4458,12157,896,12017,6287,17,4491,4185,6837,5621,11498,5536,7783,5159,1899,10454,799,3148,6710,6819,7856,11957,11911,4589,2558,10018,4213,8189,10308,11702,12147,10414,6779,1046,3121,6964,6127,26,5224,6516,4588,2189,7209,10174};

//     #20;

//     // Start the module
//     start = 1;
//     #10;
//     start = 0;
//     #20;

//     while(done !== 1'b1) begin

//       message_valid <= i < 10; // Valid for 10 blocks of data
//       message <= messages[i];
//       message_last <= (i == 9) ? 1'b1 : 1'b0; // Last block of data

//       if(ready == 1'b1 && i < 10)
//         i <= i + 1;

//       if(coefficient_valid == 1'b1) begin
//         // Check if the coefficient is correct
//         if (coefficient !== expected_polynomial[coefficient_index]) begin
//           $fatal(1, "Test 1 failed at index %d. Expected %d, got %d", coefficient_index, expected_polynomial[coefficient_index], coefficient);
//         end
//       end

//       #10;
//     end
//     message_valid = 0;

//     $display("All tests for hash_to_point passed!");
//     $finish;

//   end
// endmodule
