`timescale 1ns / 1ps

module ntt_8_tb;

  parameter int N = 8;

  logic clk;
  logic rst_n;

  logic mode;
  logic start;
  logic done;

  logic [$clog2(N)-1:0] input_bram_addr1, input_bram_addr2, output_bram_addr1, output_bram_addr2;
  logic signed [14:0] input_bram_data1, input_bram_data2, output_bram_data1, output_bram_data2;
  logic output_bram_we1, output_bram_we2;

  // Only used for populating BRAM / verifying results
  logic signed [14:0] input_bram_data_in_a;
  logic input_bram_we_a;
  logic signed [14:0] output_bram_data_out_a;

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

  bram #(
         .RAM_DEPTH(N)
       ) input_bram (
         .clk(clk),

         .addr_a(input_bram_addr1),
         .data_in_a(input_bram_data_in_a),
         .we_a(input_bram_we_a),
         .data_out_a(input_bram_data1),

         .addr_b(input_bram_addr2),
         .data_in_b(0),
         .we_b(0),
         .data_out_b(input_bram_data2)
       );

  bram #(
         .RAM_DEPTH(N)
       ) output_bram (
         .clk(clk),

         .addr_a(output_bram_addr1),
         .data_in_a(output_bram_data1),
         .we_a(output_bram_we1),
         .data_out_a(output_bram_data_out_a),

         .addr_b(output_bram_addr2),
         .data_in_b(output_bram_data2),
         .we_b(output_bram_we2)
       );

  // Task for writing to input BRAM
  task write_to_input_bram(input signed [14:0] data[N]);
    begin
      for (int i = 0; i < N; i = i + 1) begin
        input_bram_addr1 = i;
        input_bram_data_in_a = data[i];
        input_bram_we_a = 1;
        #10;
      end
      input_bram_we_a = 0;
    end
  endtask

  // Task for verifying content of output BRAM
  task verify_output_bram(int test, input signed [14:0] expected[N]);
    begin
      for (int i = 0; i < N; i = i + 1) begin
        output_bram_addr1 = i;
        #10;
        if (output_bram_data_out_a !== expected[i]) begin
          $fatal(1, "Output data mismatch at index %0d. Expected: %0d, Got: %0d", i, expected[i], output_bram_data_out_a);
        end
      end
      $display("Test %0d passed.", test);
    end
  endtask

  always #5 clk = ~clk;

  initial begin
    clk = 1;

    // Test 1: NTT of polynomial size 8
    rst_n = 0;
    #10;
    rst_n = 1;
    mode = 0;
    write_to_input_bram({0,1,2,3,4,5,6,7});

    // Start NTT
    start = 1;
    #10;
    start = 0;

    // Wait for NTT to finish
    while (!done)
      #10;

    verify_output_bram(1, {10914,5186,3052,6340,6212,9196,9416,11129});

    // Test 2: INTT of polynomial size 8
    rst_n = 0;
    #10;
    rst_n = 1;
    mode = 1;
    write_to_input_bram({10914,5186,3052,6340,6212,9196,9416,11129});

    // Start INTT
    start = 1;
    #10;
    start = 0;

    // Wait for INTT to finish
    while (!done)
      #10;

    verify_output_bram(2, {0,1,2,3,4,5,6,7});


    // Test 3: NTT with bigger numbers
    rst_n = 0;
    #10;
    rst_n = 1;
    mode = 0;
    write_to_input_bram({7644,6589,8565,4185,1184,607,3842,5361});

    // Start NTT
    start = 1;
    #10;
    start = 0;

    // Wait for NTT to finish
    while (!done)
      #10;

    verify_output_bram(3, {5550,7668,5033,222,2053,777,6055,9216});


    // Test 4: NTT with negative coefficients
    rst_n = 0;
    #10;
    rst_n = 1;
    mode = 0;
    write_to_input_bram({-153,-108,143,-216,-49,222,81,152});

    // Start NTT
    start = 1;
    #10;
    start = 0;

    // Wait for NTT to finish
    while (!done)
      #10;

    verify_output_bram(4, {2598,1143,7769,7404,5910,11731,1017,10360});

    $display("All tests for ntt_8 passed!");
    $finish;
  end

endmodule
