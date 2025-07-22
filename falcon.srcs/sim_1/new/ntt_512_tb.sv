`timescale 1ns / 1ps
`include "common_definitions.vh"

module ntt_512_tb;

  parameter int N = 512;

  logic clk;
  logic rst_n;

  logic mode;
  logic start;
  logic done;

  logic signed[14:0] expected_polynomial [N];

  logic [`FFT_BRAM_ADDR_WIDTH-1:0] input_bram_addr1;
  logic signed [`FFT_BRAM_DATA_WIDTH-1:0] input_bram_data1;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] input_bram_addr2;
  logic signed [`FFT_BRAM_DATA_WIDTH-1:0] input_bram_data2;
  bram_512x128_preinit_for_ntt_tb input_bram (
                                    .clka(clk),
                                    .addra(input_bram_addr1),
                                    .dina(128'b0),
                                    .wea(1'b0),
                                    .douta(input_bram_data1),

                                    .clkb(clk),
                                    .addrb(input_bram_addr2),
                                    .dinb(128'b0),
                                    .web(1'b0),
                                    .doutb(input_bram_data2)
                                  );

  logic [`NTT_BRAM_ADDR_WIDTH-1:0] output_bram_addr1;
  logic signed [`NTT_BRAM_DATA_WIDTH-1:0] output_bram_data1;
  logic output_bram_we1;
  logic [`NTT_BRAM_ADDR_WIDTH-1:0] output_bram_addr2;
  logic signed [`NTT_BRAM_DATA_WIDTH-1:0] output_bram_data2;
  logic output_bram_we2;
  bram_1024x15 output_bram (
                 .clka(clk),
                 .addra(output_bram_addr1),
                 .dina(output_bram_data1),
                 .wea(output_bram_we1),

                 .clkb(clk),
                 .addrb(output_bram_addr2),
                 .dinb(output_bram_data2),
                 .web(output_bram_we2)
               );

  ntt #(
        .N(N)
      )uut(
        .clk(clk),
        .rst_n(rst_n),
        .mode(mode),
        .start(start),
        .done(done),

        .input_bram_addr1(input_bram_addr1),
        .input_bram_addr2(input_bram_addr2),
        .input_bram_data1(input_bram_data1),
        .input_bram_data2(input_bram_data2),

        .output_bram_addr1(output_bram_addr1),
        .output_bram_addr2(output_bram_addr2),
        .output_bram_data1(output_bram_data1),
        .output_bram_data2(output_bram_data2),
        .output_bram_we1(output_bram_we1),
        .output_bram_we2(output_bram_we2)
      );

  // Check if result is correct
  always_ff @(posedge clk) begin
    if(output_bram_we1 === 1) begin
      if(output_bram_data1 !== expected_polynomial[output_bram_addr1])
        $fatal(1, "Test failed at index %d. Expected %d, got %d", output_bram_addr1, expected_polynomial[output_bram_addr1], output_bram_data1);
      if(output_bram_we2 === 1) begin
        if(output_bram_data2 !== expected_polynomial[output_bram_addr2])
          $fatal(1, "Test failed at index %d. Expected %d, got %d", output_bram_addr2, expected_polynomial[output_bram_addr2], output_bram_data2);
      end
    end
  end

  always #5 clk = ~clk;

  initial begin
    clk = 1;

    rst_n = 0;
    #10;
    rst_n = 1;
    mode = 0;
    expected_polynomial = '{3563,6312,914,1410,11670,3443,12179,10019,517,1596,4599,12059,2269,11382,7426,1130,246,10435,6449,299,1812,4928,12005,1256,5618,6703,7229,8046,8409,9999,3485,3908,8088,7095,8931,4210,10742,1391,12033,6888,10845,11474,3669,11279,1536,9546,8664,526,7131,972,5209,3222,4965,9341,7660,11592,10113,10612,9779,5716,7087,2728,10156,9673,2188,5184,413,1664,4718,11832,4207,11117,3116,6620,9465,3331,5582,3095,9217,9987,8073,832,11453,6766,4911,9219,10507,6306,3267,10701,4245,7238,4352,320,9126,9699,6384,2256,11657,3197,8966,7195,6343,9782,673,10393,11335,7383,2100,10387,7057,343,10741,6579,8973,1239,10562,3883,6143,9990,9572,6346,6050,76,6755,10825,3082,6983,5350,7948,7847,10678,1710,3253,1995,3120,2935,11778,2829,25,4509,11522,5213,1164,12172,7585,4010,4452,3504,7300,4992,10211,10931,10760,7215,6174,2156,4415,4856,1494,11727,606,5760,7340,5890,3864,152,3991,1009,10467,2762,7702,8942,4167,8794,10354,395,400,12033,6403,10161,8259,3337,7058,4704,976,1130,4295,7457,12247,3146,12118,2185,2315,1282,9736,5480,1856,8275,7214,803,7655,6805,10501,3883,517,9425,7414,10590,9221,11611,2226,7730,5299,2380,6630,10840,11522,3233,1815,4668,470,5278,99,9789,8865,1219,8020,4045,9786,9554,9646,3100,8216,7752,4197,6488,7443,973,11347,3678,1191,1617,10040,3597,8338,3826,7791,5447,4709,3229,8382,3421,5631,10708,11939,6129,8920,1131,3898,3491,8590,3003,4573,1938,6517,9116,8799,8244,6206,365,6723,8657,3644,11062,8479,9828,11980,358,10395,9394,9294,8305,3478,6662,5985,5560,3132,3294,4260,12266,8324,1222,2936,6024,4583,6173,6324,1261,11311,4052,10597,5436,1985,4970,10967,5014,6398,5370,8452,4710,12110,10504,11694,7160,7661,10528,9185,6793,8528,5583,4772,8083,7760,1698,9982,6634,12261,1083,1331,8591,4584,3451,621,8451,1812,6674,3166,6735,5522,2302,9304,5867,3880,7341,11250,5118,8941,4613,10319,8373,11294,11138,4506,6965,2760,922,3674,8997,2111,4625,9323,4636,2483,11972,7810,8697,11170,10672,12189,8806,6892,8860,11349,2003,10792,5550,5208,4549,3126,4171,7412,7128,10965,5063,4584,8348,9487,6958,10013,1734,2939,9743,1997,5443,10604,3391,2562,4459,5609,9476,5541,8926,11417,10839,11866,5724,1746,8722,8368,1825,6139,2520,796,108,5461,3127,5092,6433,2272,4957,8230,5750,583,66,4352,2221,6886,1973,8419,10731,3058,7852,3344,8762,4351,8103,5791,11749,4068,6319,1253,117,7230,7956,7939,12126,10206,11079,7563,4588,10690,4322,6576,3033,3865,2889,3751,7025,7611,6391,6172,10611,7941,11764,9654,5909,6316,7046,492,10679,1256,10805,2942,5448,953,5759,1373,7998,730,1904,4041,2549,2099,10519,7012,7732,10196,8031,5521,590,7304,9771,4816,10792,9827,8642,3430,8166,8118,5304,7964,4877,95,4303,4101,1620,9032,5499,7620,10736,0};

    // Start NTT
    start = 1;
    #10;
    start = 0;

    // Wait for NTT to finish
    while (!done)
      #10;

    $display("All tests for ntt_512 passed!");
    $finish;

  end

endmodule
