`timescale 1ns / 1ps

module double_to_int_tb;

  logic clk;

  logic signed [14:0] int_out;
  logic [63:0] double_in;

  always #5 clk = ~clk;

  double_to_int double_to_int (
                .clk(clk),
                .double_in(double_in),
                .int_out(int_out)
              );

  initial begin

    clk = 1;

    for (real i = -4; i < 4; i++) begin
      double_in <= $realtobits(i);
      #10;
    end

    #10;

    for (real i = -4; i < 4; i++) begin
      double_in <= $realtobits(i+0.4);
      #10;
    end

    #10;

    for (real i = -4; i < 4; i++) begin
      double_in <= $realtobits(i+0.5);
      #10;
    end

    #10;

    for (real i = -4; i < 4; i++) begin
      double_in <= $realtobits(i+0.6);
      #10;
    end

  end
endmodule
