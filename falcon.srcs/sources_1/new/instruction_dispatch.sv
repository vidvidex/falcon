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
    input logic [1:0] algorithm_select, // 00 = signing, 01 = verification, 10 and 11 available for future expansion

    output logic done,
    output logic signature_accepted,
    output logic signature_rejected,

    // Manual control of instruction index (for debugging)
    input enable_manual_instruction_index_incr,
    input logic [15:0] manual_instruction_index,
    input logic manual_instruction_index_valid, // Should only be a pulse
    output logic [15:0] current_instruction_index,

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

  typedef enum logic [2:0] {
            IDLE, // Waiting for start signal
            INSTRUCTIONS_RUNNING,  // Instructions are running
            INSTRUCTIONS_DONE, // Instruction done, sending NOP to control unit
            WAIT_FOR_MANUAL_INDEX, // Waiting for manual instruction index increment
            DONE  // All instructions done
          } state_t;
  state_t state, next_state;

  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start == 1'b1)
          next_state = INSTRUCTIONS_RUNNING;
      end
      INSTRUCTIONS_RUNNING: begin
        if(instruction_done == 1'b1)
          next_state = INSTRUCTIONS_DONE;
      end
      INSTRUCTIONS_DONE: begin
        if (algorithm_select == 2'b00 && instruction_index == SIGN_INSTRUCTION_COUNT)
          next_state = DONE;
        else if (algorithm_select == 2'b01 && instruction_index == VERIFY_INSTRUCTION_COUNT)
          next_state = DONE;
        else if(enable_manual_instruction_index_incr == 1'b1)
          next_state = WAIT_FOR_MANUAL_INDEX;
        else
          next_state = INSTRUCTIONS_RUNNING;
      end
      WAIT_FOR_MANUAL_INDEX: begin
        if(manual_instruction_index_valid == 1'b1)
          next_state = INSTRUCTIONS_RUNNING;
      end
      DONE: begin
        next_state = DONE;
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst_n == 1'b0)
      state <= IDLE;
    else
      state <= next_state;
  end

  assign current_instruction_index = instruction_index;

  assign done = (state == DONE);

  always_comb begin
    if(state == INSTRUCTIONS_RUNNING)
      instruction = (algorithm_select == 2'b01) ? verify_instructions[instruction_index] : sign_instructions[instruction_index];
    else
      instruction = 128'b0;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      instruction_index <= 0;
    end
    else begin

      case (state)
        IDLE: begin
        end
        INSTRUCTIONS_RUNNING: begin
          // instruction_done being 1'b1 is also condition for going out of INSTRUCTIONS_RUNNING, which ensures this will be incremented only once per instruction_done pulse (even if not pulse)
          if (instruction_done == 1'b1 && enable_manual_instruction_index_incr == 1'b0)
            instruction_index <= instruction_index + 1;
        end
        INSTRUCTIONS_DONE: begin
        end
        WAIT_FOR_MANUAL_INDEX: begin
          if (manual_instruction_index_valid == 1'b1)
            instruction_index <= manual_instruction_index;
        end
        DONE: begin
          instruction_index <= 0;
        end
      endcase
    end
  end

endmodule
