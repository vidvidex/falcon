`timescale 1ns / 1ps

module double_to_int_tb;

  logic clk;

  logic signed [14:0] int_out;
  logic [63:0] double_in;
  logic valid_in;
  logic valid_out;

  always #5 clk = ~clk;

  double_to_int double_to_int (
                  .clk(clk),
                  .double_in(double_in),
                  .valid_in(valid_in),
                  .int_out(int_out),
                  .valid_out(valid_out)
                );

  initial begin

    clk = 1;
    valid_in <= 0;

    for (real i = -4; i < 4; i++) begin
      double_in <= $realtobits(i);
      valid_in <= 1;
      #10;
    end
    valid_in <= 0;

    #10;

    for (real i = -4; i < 4; i++) begin
      double_in <= $realtobits(i+0.4);
      valid_in <= 1;
      #10;
    end
    valid_in <= 0;

    #10;

    for (real i = -4; i < 4; i++) begin
      double_in <= $realtobits(i+0.5);
      valid_in <= 1;
      #10;
    end
    valid_in <= 0;

    #10;

    for (real i = -4; i < 4; i++) begin
      double_in <= $realtobits(i+0.6);
      valid_in <= 1;
      #10;
    end
    valid_in <= 0;

    #10;

    double_in <= 64'h3feffffffffd0500;
    valid_in <= 1;
    #10;
    valid_out <= 0;

  end
endmodule
