`timescale 1ns/1ps

module samplerz_tb;

  parameter int N = 512;

  logic clk;
  logic rst_n;

  logic restart;
  logic start;
  logic done;

  logic [127:0] seed_a;
  logic [127:0] seed_b;
  logic [127:0] seed [4] = '{
          128'h0000000011111111_2222222233333333,
          128'h8888888899999999_aaaaaaaabbbbbbbb,
          128'h4444444455555555_6666666677777777,
          128'hccccccccdddddddd_eeeeeeeeffffffff
        };

  logic [63:0] mu1, mu2, isigma;
  logic [63:0] result1, result2;

  logic [1:0] seed_offset_a;
  logic [1:0] seed_offset_b;

  Bi_samplerz #(.N(N))samplerz (
                .clk(clk),
                .reset(rst_n),
                .start(start),
                .restart(restart),

                .mu1(mu1),
                .mu2(mu2),
                .isigma(isigma),

                .seed_offset_a(seed_offset_a),
                .seed_bram_dout_a(seed_a),
                .seed_offset_b(seed_offset_b),
                .seed_bram_dout_b(seed_b),

                .result1(result1),
                .result2(result2),
                .done(done)
              );

  always_ff @(posedge clk) begin
    seed_a <= seed[seed_offset_a];
    seed_b <= seed[seed_offset_b];
  end

  always #5 clk = ~clk;

  initial begin
    clk = 1;

    rst_n = 0;
    #20;
    rst_n = 1;

    #30;

    mu1 = $realtobits(-2.98266742615349);
    mu2 = $realtobits(-110.482952233705);
    isigma = $realtobits(1.7237520213066);

    #1000;


    start <= 1;
    restart <= 1;
    #10;
    restart <= 0;
    start <= 0;

    while(done !== 1)
      #10;

    mu1 = $realtobits(56.95491949528823);
    mu2 = $realtobits(6.458067295424501);
    isigma = $realtobits(1/1.7410445103037335);


    start <= 1;
    #10;
    start <= 0;

    while(done !== 1)
      #10;

    mu1 = $realtobits(-11.662806799958712);
    mu2 = $realtobits(39.64107628004665);
    isigma = $realtobits(1/1.714965058508814);


    start <= 1;
    #10;
    start <= 0;

    while(done !== 1)
      #10;

    mu1 = $realtobits(83.89098065383646);
    mu2 = $realtobits(-11.706270418552691);
    isigma = $realtobits(1/1.732882618121838);


    start <= 1;
    #10;
    start <= 0;

  end

endmodule


