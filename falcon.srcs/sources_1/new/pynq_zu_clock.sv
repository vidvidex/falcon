`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// A top module that fixes the clock when running the design on a PYNQ-ZU.
//
// This is needed because the constraints file for PYNQ-ZU exposes a positive and a negative clock signal.
// These signals need to be combined into a single clock signal.
//
//////////////////////////////////////////////////////////////////////////////////


module pynq_zu_clock(
    input logic FPGA_CLK125_P,
    input logic FPGA_CLK125_N,

    input logic [3:0] btns,
    output logic [3:0] leds
  );

  logic clk;

  IBUFDS #(
           .IOSTANDARD("LVDS")
         ) ibufds_clk (
           .I(FPGA_CLK125_P),
           .IB(FPGA_CLK125_N),
           .O(clk)
         );

  top_8 uut(
          .clk(clk),
          .btns(btns),
          .leds(leds)
        );
endmodule
