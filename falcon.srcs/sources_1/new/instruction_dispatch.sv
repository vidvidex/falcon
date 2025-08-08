`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// This module dispatches instructions that guide the execution of Falcon signing and signature verification
//
//////////////////////////////////////////////////////////////////////////////////


module instruction_dispatch#(
    parameter int N = 1024
  )(
    input logic clk,
    input logic rst_n,

    input logic start,
    input logic algorithm_select, // 0 = signing, 1 = verification

    output logic done,

    // DMA interface
    input logic dma_bram_en, // Enable signal for BRAM DMA interface. When this is high, DMA has access to the BRAM
    input logic [19:0] dma_bram_addr, // Top 3 bits select BRAM bank, lower 13 bits are address in the bask
    input logic [15:0] dma_bram_byte_we,
    input logic[127:0] dma_bram_din,  // Data to write to BRAM
    output logic [127:0] dma_bram_dout // Data read from BRAM
  );

  localparam int VERIFY_INSTRUCTION_COUNT = 5 + 1 + 5; // run verify, read result, 5xNOP
  logic [127:0] verify_instructions[VERIFY_INSTRUCTION_COUNT] = '{
          128'h120400000000c18000000000001e1b90, // NTT, decompress, hash_to_point,
          128'h020000000000c18000000000001e1b8c, // NTT
          128'h001000000000c18000000000001e1b11, // mod_mult_q
          128'h020000000000c1c000000000001e1b0c, // INTT
          128'h000800000000c1c000000000001e10cd, // sub_norm_sq
          128'h800000000000c1c000000000000210c8 // read result
        };

  localparam int SIGN_INSTRUCTION_COUNT = N; // TODO
  logic [127:0] sign_instructions[SIGN_INSTRUCTION_COUNT];

  logic [127:0] instruction;
  logic instruction_done;
  logic [`BRAM_DATA_WIDTH-1:0] bram_din;
  logic [`BRAM_DATA_WIDTH-1:0] bram_dout;

  logic running;
  logic [$clog2(SIGN_INSTRUCTION_COUNT)-1:0] instruction_index;

  control_unit #(
                 .N(N)
               ) control_unit (
                 .clk(clk),
                 .rst_n(rst_n),
                 .instruction(instruction),
                 .instruction_done(instruction_done),
                 .bram_din(bram_din),
                 .bram_dout(bram_dout),

                 .dma_bram_en(dma_bram_en),
                 .dma_bram_addr(dma_bram_addr),
                 .dma_bram_din(dma_bram_din),
                 .dma_bram_dout(dma_bram_dout),
                 .dma_bram_byte_we(dma_bram_byte_we)
               );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      done <= 1'b0;
      running <= 1'b0;
      instruction_index <= 0;
    end
    else begin

      if (start == 1'b1)
        running <= 1'b1;

      if(running) begin

        // Increment on instruction done
        if(instruction_done)
          instruction_index <= instruction_index + 1;

        if(instruction_done)
          instruction <= 128'b0;
        else
          instruction <= (algorithm_select == 1'b1) ? verify_instructions[instruction_index] : sign_instructions[instruction_index];

        // Done condition for successful verify
        if(instruction_index == 5 && (bram_dout == 128'hffffffffffffffffffffffffffffffff || bram_dout == 128'b0))
          done <= 1'b1;
      end
    end
  end

endmodule
