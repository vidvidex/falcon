`timescale 1ns / 1ps

module IntToDouble_tb;

  logic clk;

  logic [14:0] int_in;
  logic [`OVERALL_BITS-1:0] double_out;

  always #5 clk = ~clk;

  IntToDouble IntToDouble (
                   .clk(clk),
                   .int_in(int_in),
                   .double_out(double_out)
                 );

  initial begin

    clk = 1;

    for (int i = -32; i < 32; i++) begin
      int_in <= i;
      #10;
    end

  end

endmodule
