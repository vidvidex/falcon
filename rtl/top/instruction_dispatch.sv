`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// This module dispatches instructions that guide the execution of Falcon signing and signature verification.
// The instructions come from instruction_generator. The generator always holds the next instruction, so when 
// the control unit reports that an instruction is done, the next one is issued in the following cycle.
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

    // External BRAM interface
    input logic ext_bram_en, // Enable signal for external BRAM interface. When this is high, software has access to the BRAM
    input logic [19:0] ext_bram_addr, // Top 3 bits select BRAM bank, lower 13 bits are address in the bank
    input logic [15:0] ext_bram_we,
    input logic[127:0] ext_bram_din,  // Data to write to BRAM
    output logic [127:0] ext_bram_dout // Data read from BRAM
  );

  logic [`INSTRUCTION_WIDTH-1:0] instruction;
  logic instruction_done;

  logic [13:0] instruction_index;  // Number of instructions done, for debugging

  logic generator_restart, generator_next, no_more_instructions;
  logic [`INSTRUCTION_WIDTH-1:0] next_instruction;
  instruction_generator #(
                          .N(N)
                        ) instruction_generator (
                          .clk(clk),
                          .restart(generator_restart),
                          .algorithm(algorithm_select == 2'b01),
                          .next(generator_next),
                          .instruction(next_instruction),
                          .finished(no_more_instructions)
                        );

  control_unit #(
                 .N(N)
               ) control_unit (
                 .clk(clk),
                 .rst_n(rst_n),
                 .instruction(instruction),
                 .instruction_done(instruction_done),

                 .signature_accepted(signature_accepted),
                 .signature_rejected(signature_rejected),

                 .ext_bram_en(ext_bram_en),
                 .ext_bram_addr(ext_bram_addr),
                 .ext_bram_din(ext_bram_din),
                 .ext_bram_dout(ext_bram_dout),
                 .ext_bram_we(ext_bram_we)
               );

  typedef enum logic [1:0] {
            IDLE, // Waiting for start signal
            START,  // Issue first instruction
            INSTRUCTIONS_RUNNING,  // Instructions are running
            DONE  // All instructions done
          } state_t;
  state_t state, next_state;

  // The generator starts from the first instruction while idle and moves to the next one whenever one is issued
  logic issue_next;
  assign issue_next = state == INSTRUCTIONS_RUNNING && instruction_done == 1'b1 && !no_more_instructions;
  assign generator_restart = state == IDLE;
  assign generator_next = state == START || issue_next;

  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start == 1'b1)
          next_state = START;
      end
      START: begin
        next_state = INSTRUCTIONS_RUNNING;
      end
      INSTRUCTIONS_RUNNING: begin
        if(instruction_done == 1'b1 && no_more_instructions)
          next_state = DONE;
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

  assign done = (state == DONE);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      instruction_index <= 0;
      instruction <= 0;
    end
    else begin

      case (state)
        IDLE: begin
        end
        START: begin
          instruction_index <= 0;
          instruction <= next_instruction;
        end
        INSTRUCTIONS_RUNNING: begin
          // instruction_done is high for one cycle per instruction
          if (instruction_done == 1'b1) begin
            instruction_index <= instruction_index + 1;
            instruction <= no_more_instructions ? '0 : next_instruction;
          end
        end
        DONE: begin
          instruction_index <= 0;
          instruction <= 0;
        end
      endcase
    end
  end

endmodule
