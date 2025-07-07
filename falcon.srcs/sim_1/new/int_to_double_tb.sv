`timescale 1ns / 1ps

module int_to_double_tb;

  logic clk;

  logic [127:0] data_in;
  logic [127:0] data_out;
  logic valid_in;
  logic valid_out;

  always #5 clk = ~clk;

  int_to_double int_to_double (
                .clk(clk),
                .data_in(data_in),
                .valid_in(valid_in),
                .data_out(data_out),
                .valid_out(valid_out)
              );

  logic signed [14:0] i1, i2;
  logic [63:0] out1, out2;

  assign {out1, out2} = data_out;

  initial begin

    clk = 1;

    for (int i = -32; i < 32; i+=2) begin
      i1 = i;
      i2 = i + 1;
      data_in <= {49'b0, i1, 49'b0, i2};
      valid_in <= 1;
      #10;
    end
    valid_in <= 0;
    #10;

  end

endmodule
