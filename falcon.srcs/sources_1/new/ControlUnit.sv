`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Control unit that run submodules/tasks based on received instructions
//
// Instruction format:
// [31:28] opcode
// [27:26] task BRAM bank 1
// [25:16] task address 1
// [15:14] task BRAM bank 2
// [13:4]  task address 2
// [3:0]   task parameters
//
// opcodes:
// 0000 - NOP (No operation)
// 0001 - Hash to point
// 0010 - FFT
// 0011 - FP arithmetic
// 0100 - FFT split
// 0101 - FFT merge
// 0110 - Check norm
// 0111 - Compress
// 1000 - BRAM read
// 1001 - BRAM write
//
//////////////////////////////////////////////////////////////////////////////////


module ControlUnit#(
    parameter int N
  )(
    input logic clk,
    input logic rst_n,

    input logic [31:0] instruction,
    output logic instruction_done,

    input logic [`BRAM_DATA_WIDTH-1:0] bram_din, // Data to write to BRAM
    output logic [`BRAM_DATA_WIDTH-1:0] bram_dout // Data read from BRAM
  );

  logic [3:0] opcode, opcode_registered;
  logic [1:0] task_bank1;
  logic [`BRAM_ADDR_WIDTH-1:0] task_addr1;
  logic [1:0] task_bank2;
  logic [`BRAM_ADDR_WIDTH-1:0] task_addr2;
  logic [3:0] task_params;

  logic [`BRAM_ADDR_WIDTH-1:0] bram0_addr_a, bram0_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram0_din_a, bram0_din_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram0_dout_a, bram0_dout_b;
  logic bram0_we_a, bram0_we_b;
  bram_512x128 bram_512x128_0 (
                  .addra(bram0_addr_a),
                  .clka(clk),
                  .dina(bram0_din_a),
                  .douta(bram0_dout_a),
                  .wea(bram0_we_a),

                  .addrb(bram0_addr_b),
                  .clkb(clk),
                  .dinb(bram0_din_b),
                  .doutb(bram0_dout_b),
                  .web(bram0_we_b)
                );

  logic [`BRAM_ADDR_WIDTH-1:0] bram1_addr_a, bram1_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram1_din_a, bram1_din_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram1_dout_a, bram1_dout_b;
  logic bram1_we_a, bram1_we_b;
  bram_512x128 bram_512x128_1 (
                  .addra(bram1_addr_a),
                  .clka(clk),
                  .dina(bram1_din_a),
                  .douta(bram1_dout_a),
                  .wea(bram1_we_a),

                  .addrb(bram1_addr_b),
                  .clkb(clk),
                  .dinb(bram1_din_b),
                  .doutb(bram1_dout_b),
                  .web(bram1_we_b)
                );

  logic [`BRAM_ADDR_WIDTH-1:0] bram2_addr_a, bram2_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram2_din_a, bram2_din_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram2_dout_a, bram2_dout_b;
  logic bram2_we_a, bram2_we_b;
  bram_512x128 bram_512x128_2 (
                  .addra(bram2_addr_a),
                  .clka(clk),
                  .dina(bram2_din_a),
                  .douta(bram2_dout_a),
                  .wea(bram2_we_a),

                  .addrb(bram2_addr_b),
                  .clkb(clk),
                  .dinb(bram2_din_b),
                  .doutb(bram2_dout_b),
                  .web(bram2_we_b)
                );

  logic [$clog2(N)-2:0] bram3_addr_a, bram3_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram3_din_a, bram3_din_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram3_dout_a, bram3_dout_b;
  logic bram3_we_a, bram3_we_b;
  bram_512x128 bram_512x128_3 (
                  .addra(bram3_addr_a),
                  .clka(clk),
                  .dina(bram3_din_a),
                  .douta(bram3_dout_a),
                  .wea(bram3_we_a),

                  .addrb(bram3_addr_b),
                  .clkb(clk),
                  .dinb(bram3_din_b),
                  .doutb(bram3_dout_b),
                  .web(bram3_we_b)
                );


  logic htp_start, htp_start_i;
  logic [`BRAM_ADDR_WIDTH-1:0] htp_input_bram_addr;
  logic [`BRAM_DATA_WIDTH-1:0] htp_input_bram_data;
  logic [`BRAM_ADDR_WIDTH-1:0] htp_output_bram_addr;
  logic [`BRAM_DATA_WIDTH-1:0] htp_output_bram_data;
  logic htp_output_bram_we;
  logic htp_done;
  hash_to_point #(
                  .N(N)
                )
                hash_to_point(
                  .clk(clk),
                  .rst_n(rst_n),
                  .start(htp_start && !htp_start_i),

                  .input_bram_addr(htp_input_bram_addr),
                  .input_bram_data(htp_input_bram_data),

                  .output_bram_addr(htp_output_bram_addr),
                  .output_bram_data(htp_output_bram_data),
                  .output_bram_we(htp_output_bram_we),

                  .done(htp_done)
                );

  // Task execution based on opcode
  always_ff @(posedge clk) begin

    // Instruction decoding
    opcode <= instruction[31:28];
    task_bank1 <= instruction[27:26];
    task_addr1 <= instruction[25:16];
    task_bank2 <= instruction[15:14];
    task_addr2 <= instruction[13:4];
    task_params <= instruction[3:0];

    if (!rst_n) begin
      htp_start <= 1'b0;
      htp_start_i <= 1'b0;
    end
    else begin

      htp_start_i <= htp_start;

      case (opcode)
        4'b0000: begin // NOP
          // No operation, do nothing except stop writing to BRAMs
          htp_start <= 1'b0;
          bram0_we_a <= 1'b0;
          bram0_we_b <= 1'b0;
          bram1_we_a <= 1'b0;
          bram1_we_b <= 1'b0;
          bram2_we_a <= 1'b0;
          bram2_we_b <= 1'b0;
          bram3_we_a <= 1'b0;
          bram3_we_b <= 1'b0;
        end

        4'b0001: begin  // Hash to point

          htp_start <= 1'b1;

        end

        4'b0010: begin  // FFT

        end

        4'b0011: begin  // FP arithmetic

        end

        4'b0100: begin  // fft_split

        end

        4'b0101: begin  // fft_merge

        end

        4'b0110: begin  // Check norm

        end

        4'b0111: begin  // Compress

        end

        4'b1000: begin  // BRAM read

        end

        4'b1001: begin  // BRAM write

        end

        default: begin

        end

      endcase
    end
  end

  // BRAM routing
  always_comb begin

    instruction_done = 1'b0; // Default to not done

    case (opcode)
      4'b0000: begin // NOP

      end

      4'b0001: begin  // Hash to point

        // Connect input BRAM
        case (task_bank1)
          2'b00: begin
            bram0_addr_a = htp_input_bram_addr;
            htp_input_bram_data = bram0_dout_a;
          end
          2'b01: begin
            bram1_addr_a = htp_input_bram_addr;
            htp_input_bram_data = bram1_dout_a;
          end
          2'b10: begin
            bram2_addr_a = htp_input_bram_addr;
            htp_input_bram_data = bram2_dout_a;
          end
          2'b11: begin
            bram3_addr_a = htp_input_bram_addr;
            htp_input_bram_data = bram3_dout_a;
          end
        endcase

        // Connect output BRAM
        case (task_bank2)
          2'b00: begin
            bram0_addr_a = htp_output_bram_addr;
            bram0_din_a = htp_output_bram_data;
            bram0_we_a = htp_output_bram_we;
          end
          2'b01: begin
            bram1_addr_a = htp_output_bram_addr;
            bram1_din_a = htp_output_bram_data;
            bram1_we_a = htp_output_bram_we;
          end
          2'b10: begin
            bram2_addr_a = htp_output_bram_addr;
            bram2_din_a = htp_output_bram_data;
            bram2_we_a = htp_output_bram_we;
          end
          2'b11: begin
            bram3_addr_a = htp_output_bram_addr;
            bram3_din_a = htp_output_bram_data;
            bram3_we_a = htp_output_bram_we;
          end
        endcase

        instruction_done = htp_done;
      end

      4'b0010: begin  // FFT

      end

      4'b0011: begin  // FP arithmetic

      end

      4'b0100: begin  // fft_split

      end

      4'b0101: begin  // fft_merge

      end

      4'b0110: begin  // Check norm

      end

      4'b0111: begin  // Compress

      end

      4'b1000: begin  // BRAM read
        // Reads from BRAM "task_bank1" at address "task_addr1". Output is "bram_dout".
        case (task_bank1)
          2'b00: begin
            bram0_addr_a = task_addr1;
            bram_dout = bram0_dout_a;
          end
          2'b01: begin
            bram1_addr_a = task_addr1;
            bram_dout = bram1_dout_a;
          end
          2'b10: begin
            bram2_addr_a = task_addr1;
            bram_dout = bram2_dout_a;
          end
          2'b11: begin
            bram3_addr_a = task_addr1;
            bram_dout = bram3_dout_a;
          end
        endcase

        instruction_done = 1'b1; // We set done to 1 immediately even though the read will take a few cycles. This is because the data will definitely be available then, so we can issue the next instruction.
      end

      4'b1001: begin  // BRAM write
        // Writes to BRAM "task_bank1" at address "task_addr1". Input is "bram_din".
        case (task_bank1)
          2'b00: begin
            bram0_addr_a = task_addr1;
            bram0_din_a = bram_din;
            bram0_we_a = 1'b1;
          end
          2'b01: begin
            bram1_addr_a = task_addr1;
            bram1_din_a = bram_din;
            bram1_we_a = 1'b1;
          end
          2'b10: begin
            bram2_addr_a = task_addr1;
            bram2_din_a = bram_din;
            bram2_we_a <= 1'b1;
          end
          2'b11: begin
            bram3_addr_a = task_addr1;
            bram3_din_a = bram_din;
            bram3_we_a = 1'b1;
          end
        endcase

        instruction_done = 1'b1;
      end

      default: begin

      end

    endcase
  end

endmodule
