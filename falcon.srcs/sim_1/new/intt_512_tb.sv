`timescale 1ns / 1ps
`include "common_definitions.vh"

module intt_512_tb;

  parameter int N = 512;

  logic clk;
  logic rst_n;

  logic mode;
  logic start;
  logic done;

  logic signed[14:0] expected_polynomial [N];

  logic [`BRAM_ADDR_WIDTH-1:0] input_bram_addr1;
  logic signed [`BRAM_DATA_WIDTH-1:0] input_bram_data1;
  logic [`BRAM_ADDR_WIDTH-1:0] input_bram_addr2;
  logic signed [`BRAM_DATA_WIDTH-1:0] input_bram_data2;
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
    mode = 1;
    expected_polynomial = '{6400, 2213, 7599, 9119, 884, 2359, 5352, 9873, 6158, 9626, 10727, 9120, 5116, 3596, 5600, 8835, 4395, 7391, 5814, 9022, 5928, 2112, 10802, 6396, 7883, 3581, 4324, 2646, 2666, 6834, 3768, 60, 7181, 10201, 11116, 4446, 10816, 6671, 9647, 6951, 4458, 6371, 1410, 8019, 8792, 11792, 10479, 2064, 7450, 11218, 1741, 7198, 1267, 5797, 9697, 7401, 10481, 7226, 8206, 4165, 11697, 3451, 959, 8563, 8152, 9610, 7587, 9417, 622, 9630, 1992, 4613, 7685, 10943, 5235, 12094, 11755, 12239, 9804, 7985, 5121, 1138, 2708, 10568, 8702, 11216, 8077, 98, 8421, 5319, 9750, 7241, 10045, 10820, 6969, 9002, 224, 10164, 11241, 2304, 6605, 4731, 755, 8617, 11941, 10710, 11870, 5174, 3161, 9679, 9032, 10448, 3333, 9920, 3508, 12004, 5002, 6093, 2860, 9644, 5388, 4465, 11110, 7987, 3315, 6164, 4759, 4361, 1571, 1229, 1253, 9073, 12284, 2307, 6189, 5020, 3360, 7150, 4281, 8429, 8412, 2327, 89, 4854, 10430, 6012, 5418, 775, 5375, 10891, 9345, 1875, 535, 4956, 9388, 11081, 10107, 7126, 4831, 513, 8417, 7719, 4853, 10816, 973, 6087, 10568, 6748, 8786, 8755, 6970, 1624, 7426, 5459, 5722, 3097, 6, 8757, 5213, 1887, 4775, 5910, 11023, 11515, 831, 7069, 6040, 4697, 5911, 3944, 6761, 10222, 9153, 6837, 11486, 4470, 9815, 6168, 12217, 8344, 1379, 8095, 11053, 3258, 6029, 5522, 5331, 8589, 2737, 9126, 8971, 6846, 1549, 4084, 5093, 9546, 4052, 5053, 3139, 2217, 2160, 1882, 1894, 3100, 11772, 3483, 7632, 5904, 5327, 7443, 7717, 8210, 10093, 96, 9543, 3051, 11454, 9410, 124, 5259, 6310, 1865, 4725, 4295, 4046, 3849, 4663, 989, 1141, 11355, 11762, 8591, 2446, 4437, 6774, 8222, 7312, 8222, 6774, 4437, 2446, 8591, 11762, 11355, 1141, 989, 4663, 3849, 4046, 4295, 4725, 1865, 6310, 5259, 124, 9410, 11454, 3051, 9543, 96, 10093, 8210, 7717, 7443, 5327, 5904, 7632, 3483, 11772, 3100, 1894, 1882, 2160, 2217, 3139, 5053, 4052, 9546, 5093, 4084, 1549, 6846, 8971, 9126, 2737, 8589, 5331, 5522, 6029, 3258, 11053, 8095, 1379, 8344, 12217, 6168, 9815, 4470, 11486, 6837, 9153, 10222, 6761, 3944, 5911, 4697, 6040, 7069, 831, 11515, 11023, 5910, 4775, 1887, 5213, 8757, 6, 3097, 5722, 5459, 7426, 1624, 6970, 8755, 8786, 6748, 10568, 6087, 973, 10816, 4853, 7719, 8417, 513, 4831, 7126, 10107, 11081, 9388, 4956, 535, 1875, 9345, 10891, 5375, 775, 5418, 6012, 10430, 4854, 89, 2327, 8412, 8429, 4281, 7150, 3360, 5020, 6189, 2307, 12284, 9073, 1253, 1229, 1571, 4361, 4759, 6164, 3315, 7987, 11110, 4465, 5388, 9644, 2860, 6093, 5002, 12004, 3508, 9920, 3333, 10448, 9032, 9679, 3161, 5174, 11870, 10710, 11941, 8617, 755, 4731, 6605, 2304, 11241, 10164, 224, 9002, 6969, 10820, 10045, 7241, 9750, 5319, 8421, 98, 8077, 11216, 8702, 10568, 2708, 1138, 5121, 7985, 9804, 12239, 11755, 12094, 5235, 10943, 7685, 4613, 1992, 9630, 622, 9417, 7587, 9610, 8152, 8563, 959, 3451, 11697, 4165, 8206, 7226, 10481, 7401, 9697, 5797, 1267, 7198, 1741, 11218, 7450, 2064, 10479, 11792, 8792, 8019, 1410, 6371, 4458, 6951, 9647, 6671, 10816, 4446, 11116, 10201, 7181, 60, 3768, 6834, 2666, 2646, 4324, 3581, 7883, 6396, 10802, 2112, 5928, 9022, 5814, 7391, 4395, 8835, 5600, 3596, 5116, 9120, 10727, 9626, 6158, 9873, 5352, 2359, 884, 9119, 7599, 2213};

    // Start NTT
    start = 1;
    #10;
    start = 0;

    // Wait for NTT to finish
    while (!done)
      #10;

    $display("All tests for intt_512 passed!");
    $finish;

  end

endmodule
