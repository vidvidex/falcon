`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// A simple counter that can be started or stopped by input pulses
//
//////////////////////////////////////////////////////////////////////////////////


module counter #(
    parameter WIDTH = 32
  )(
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic stop,

    output logic [WIDTH-1:0] count
  );

  logic running;

  always @(posedge clk)
    if (!rst_n) begin
      count <= {WIDTH{1'b0}};
      running <= 1'b0;
    end
    else begin
      if (start)
        running <= 1'b1;
      else if (stop)
        running <= 1'b0;

      if (running)
        count <= count + 1'b1;
    end

endmodule
