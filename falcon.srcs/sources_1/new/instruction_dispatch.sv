`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// This module dispatches instructions that guide the execution of Falcon signing and signature verification
//
//////////////////////////////////////////////////////////////////////////////////


module instruction_dispatch#(
    parameter int N = 512
  )(
    input logic clk,
    input logic rst_n,

    input logic start,
    input logic algorithm_select, // 0 = signing, 1 = verification

    output logic done,
    output logic signature_accepted,
    output logic signature_rejected,

    // External BRAM interface
    input logic ext_bram_en, // Enable signal for external BRAM interface. When this is high, software has access to the BRAM
    input logic [19:0] ext_bram_addr, // Top 3 bits select BRAM bank, lower 13 bits are address in the bank
    input logic [15:0] ext_bram_we,
    input logic[127:0] ext_bram_din,  // Data to write to BRAM
    output logic [127:0] ext_bram_dout // Data read from BRAM
  );

  localparam int VERIFY_INSTRUCTION_COUNT = 5;
  logic [127:0] verify_instructions[VERIFY_INSTRUCTION_COUNT] = '{
          128'h1204000000000000000c000000021b90,
          128'h0200000000000000000000000000000c,
          128'h00100000000000000002000000000111,
          128'h0200000000000000000010000000000c,
          128'h000800000000000000020000000000cd
        };

  localparam int SIGN_INSTRUCTION_COUNT = 15;
  logic [127:0] sign_instructions[SIGN_INSTRUCTION_COUNT] = '{
          128'h10000000000000000000000000000b00,
          128'h0800000000000000000200000000002d,
          128'h04000000000000000000000000000025,
          128'h2100000000000000000200000000094d,
          128'h01800000000000000002200000000b5c,
          128'h00800000000000000002000000000900,
          128'h00400000000000000002410000000005,
          128'h0040000000000000000200c00a000008,
          128'h00400000000000000001c0a007000011,
          128'h0040000000000000000180900580001a,
          128'h00400000000000000001418804c00003,
          128'h0040000000000000000101040c600008,
          128'h00400000000000000000c0c208300011,
          128'h0040000000000000000080a10618001a,
          128'h200000000000000000004190850c00c0
        };


  logic [127:0] instruction;
  logic instruction_done;

  logic running;
  localparam int MAX_INSTRUCTION_COUNT = (SIGN_INSTRUCTION_COUNT > VERIFY_INSTRUCTION_COUNT) ? SIGN_INSTRUCTION_COUNT : VERIFY_INSTRUCTION_COUNT;
  logic [$clog2(MAX_INSTRUCTION_COUNT):0] instruction_index;

  control_unit #(
                 .N(N)
               ) control_unit (
                 .clk(clk),
                 .rst_n(rst_n),
                 .instruction(instruction),
                 .instruction_done(instruction_done),

                 .signature_accepted(signature_accepted),
                 .signature_rejected(signature_rejected),

                 .bram_din(128'b0),
                 .bram_dout(),

                 .ext_bram_en(ext_bram_en),
                 .ext_bram_addr(ext_bram_addr),
                 .ext_bram_din(ext_bram_din),
                 .ext_bram_dout(ext_bram_dout),
                 .ext_bram_we(ext_bram_we)
               );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      running <= 1'b0;
      instruction_index <= 0;
      done <= 1'b0;
    end
    else begin

      if (start == 1'b1)
        running <= 1'b1;

      if(running) begin
        if((algorithm_select == 1'b0 && instruction_index == SIGN_INSTRUCTION_COUNT) || (algorithm_select == 1'b1 && instruction_index == VERIFY_INSTRUCTION_COUNT)) begin
          running <= 1'b0;
          instruction_index <= 0;
          instruction <= 128'b0;
          done <= 1'b1;
        end
        else if(instruction_done) begin
          instruction_index <= instruction_index + 1;
          instruction <= 128'b0;
        end
        else
          instruction <= (algorithm_select == 1'b1) ? verify_instructions[instruction_index] : sign_instructions[instruction_index];
      end
      else
        instruction <= 128'b0;
    end
  end

endmodule
