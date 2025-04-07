`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
//  Xilinx True Dual Port RAM No Change Single Clock
//  This code implements a parameterizable true dual port memory (both ports can read and write).
//  This is a no change RAM which retains the last read value on the output during writes
//  which is the most power efficient mode.
//
//////////////////////////////////////////////////////////////////////////////////


module bram#(
    parameter RAM_WIDTH = 64,
    parameter RAM_DEPTH = 8,
    parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE"   //! Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
  )(
    input logic clk,

    input logic [$clog2(RAM_DEPTH-1)-1:0] addr_a,   //! Port A address
    input logic [RAM_WIDTH-1:0] data_in_a,          //! Port A RAM input data
    input logic we_a,                               //! Port A write enable

    input logic [$clog2(RAM_DEPTH-1)-1:0] addr_b,  //! Port B address
    input logic [RAM_WIDTH-1:0] data_in_b,         //! Port B RAM input data
    input logic we_b,                              //! Port B write enable

    output logic [RAM_WIDTH-1:0] data_out_a,  //! Port A RAM output data
    output logic [RAM_WIDTH-1:0] data_out_b   //! Port B RAM output data
  );
endmodule

logic enable_a = 1;     //! Port A RAM Enable, for additional power savings, disable port when not in use. For now always enabled
logic enable_b = 1;     //! Port B RAM Enable, for additional power savings, disable port when not in use. For now always enabled
logic output_enable_a = 1;  //! Port A output register enable. For now always enabled
logic output_enable_b = 1;  //! Port B output register enable. For now always enabled

reg [RAM_WIDTH-1:0] ram [RAM_DEPTH-1:0];
reg [RAM_WIDTH-1:0] ram_data_a = {RAM_WIDTH{1'b0}};
reg [RAM_WIDTH-1:0] ram_data_b = {RAM_WIDTH{1'b0}};

// Initialize BRAM contents to 0
generate
  integer ram_index;
  initial
    for (ram_index = 0; ram_index < RAM_DEPTH; ram_index = ram_index + 1)
      ram[ram_index] = {RAM_WIDTH{1'b0}};
endgenerate

always @(posedge clk)
  if (enable_a)
    if (we_a)
      ram[addr_a] <= data_in_a;
    else
      ram_data_a <= ram[addr_a];

always @(posedge clk)
  if (enable_b)
    if (we_b)
      ram[addr_b] <= data_in_b;
    else
      ram_data_b <= ram[addr_b];

//  The following code generates HIGH_PERFORMANCE (use output register) or LOW_LATENCY (no output register)
generate
  if (RAM_PERFORMANCE == "LOW_LATENCY") begin: no_output_register

    // The following is a 1 clock cycle read latency at the cost of a longer clock-to-out timing
    assign data_out_a = ram_data_a;
    assign data_out_b = ram_data_b;

  end
  else begin: output_register

    // The following is a 2 clock cycle read latency with improve clock-to-out timing

    reg [RAM_WIDTH-1:0] douta_reg = {RAM_WIDTH{1'b0}};
    reg [RAM_WIDTH-1:0] doutb_reg = {RAM_WIDTH{1'b0}};

    always @(posedge clk)
      if (output_enable_a)
        douta_reg <= ram_data_a;

    always @(posedge clk)
      if (output_enable_b)
        doutb_reg <= ram_data_b;

    assign data_out_a = <douta_reg>;
    assign data_out_b = <doutb_reg>;

  end
endgenerate



