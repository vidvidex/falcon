`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Negates floating point numbers
//
//////////////////////////////////////////////////////////////////////////////////


module flp_negate#(
    parameter int PARALLEL_OPS_COUNT = 2  //! How many operations to do in parallel
  ) (
    input clk,

    input logic [63:0] double_in[PARALLEL_OPS_COUNT],
    input logic valid_in,
    input logic [`FFT_BRAM_ADDR_WIDTH-1:0] address_in,

    output logic [63:0] double_out[PARALLEL_OPS_COUNT],
    output logic valid_out,
    output logic [`FFT_BRAM_ADDR_WIDTH-1:0] address_out
  );

  always @(posedge clk) begin
    for (int i = 0; i < PARALLEL_OPS_COUNT; i++)
      double_out[i] <= {~double_in[i][63], double_in[i][62:0]};
    valid_out <= valid_in;
    address_out <= address_in;
  end

endmodule
