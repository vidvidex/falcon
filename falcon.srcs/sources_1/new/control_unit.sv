`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Control unit that run submodules/tasks based on received instructions
//
// Instruction format:
// [31:28] opcode
// [27:25] task BRAM bank 1
// [24:16] task address 1
// [15:13] task BRAM bank 2
// [12:4]  task address 2
// [3:0]   task parameters
//
// opcodes:
// 0000 - NOP (No operation)
// 0001 - Hash to point
// 0010 - FFT/IFFT
// 0011 - FP arithmetic
// 0100 - FFT split
// 0101 - FFT merge
// 0110 - Check norm
// 0111 - Compress
// 1000 - BRAM read
// 1001 - BRAM write
// 1010 - int to double
//
// After receiving done for an instruction, a NOP instruction should be issued for 1 cycle to ensure all BRAM write enable signals are set to 0.
//
//////////////////////////////////////////////////////////////////////////////////


module control_unit#(
    parameter int N
  )(
    input logic clk,
    input logic rst_n,

    input logic [31:0] instruction,
    output logic instruction_done,  // When this is high the next instruction can be issued. Does not necessarily mean that the instruction has really been executed all the way (for example some simpler pipelines, such as int_to_double.).

    input logic [`BRAM_DATA_WIDTH-1:0] bram_din, // Data to write to BRAM
    output logic [`BRAM_DATA_WIDTH-1:0] bram_dout // Data read from BRAM
  );

  parameter int BRAM_BANK_COUNT = 4; // Number of BRAM banks

  logic [3:0] opcode, opcode_registered;
  logic [2:0] task_bank1;
  logic [`BRAM_ADDR_WIDTH-1:0] task_addr1;
  logic [2:0] task_bank2;
  logic [`BRAM_ADDR_WIDTH-1:0] task_addr2;
  logic [3:0] task_params;


  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_a [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_dout_a [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_a [BRAM_BANK_COUNT];
  logic bram_we_a [BRAM_BANK_COUNT];

  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_b [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_b [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_dout_b [BRAM_BANK_COUNT];
  logic bram_we_b [BRAM_BANK_COUNT];

  genvar i;
  generate
    for (i = 0; i < BRAM_BANK_COUNT; i++) begin : bram_bank
      bram_512x128 bram_512x128_inst (
                     .addra(bram_addr_a[i]),
                     .clka(clk),
                     .dina(bram_din_a[i]),
                     .douta(bram_dout_a[i]),
                     .wea(bram_we_a[i]),

                     .addrb(bram_addr_b[i]),
                     .clkb(clk),
                     .dinb(bram_din_b[i]),
                     .doutb(bram_dout_b[i]),
                     .web(bram_we_b[i])
                   );
    end
  endgenerate

  logic htp_start, htp_start_i;
  logic [`BRAM_ADDR_WIDTH-1:0] htp_input_bram_addr;
  logic [`BRAM_DATA_WIDTH-1:0] htp_input_bram_data;
  logic [`BRAM_ADDR_WIDTH-1:0] htp_output_bram1_addr, htp_output_bram2_addr;
  logic [`BRAM_DATA_WIDTH-1:0] htp_output_bram1_data, htp_output_bram2_data;
  logic htp_output_bram1_we;
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

                  .output_bram1_addr(htp_output_bram1_addr),
                  .output_bram1_data(htp_output_bram1_data),
                  .output_bram1_we(htp_output_bram1_we),

                  .output_bram2_addr(htp_output_bram2_addr),
                  .output_bram2_data(htp_output_bram2_data),

                  .done(htp_done)
                );

  logic [`BRAM_DATA_WIDTH-1:0] int_to_double_data_in, int_to_double_data_out;
  logic int_to_double_valid_in, int_to_double_valid_in_delayed, int_to_double_valid_out;
  int_to_double int_to_double (
                  .clk(clk),
                  .data_in(int_to_double_data_in),
                  .valid_in(int_to_double_valid_in_delayed),
                  .data_out(int_to_double_data_out),
                  .valid_out(int_to_double_valid_out)
                );
  logic [`BRAM_ADDR_WIDTH-1:0] int_to_double_write_addr;  // Where to write the output of int_to_double
  delay_register #(.BITWIDTH(`BRAM_ADDR_WIDTH), .CYCLE_COUNT(3)) int_to_double_write_addr_delay(.clk(clk), .in(task_addr2), .out(int_to_double_write_addr));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(1)) int_to_double_valid_in_delay(.clk(clk), .in(int_to_double_valid_in), .out(int_to_double_valid_in_delayed));

  logic [63:0] btf_a_in_real, btf_a_in_imag, btf_b_in_real, btf_b_in_imag;
  logic [63:0] btf_a_out_real, btf_a_out_imag, btf_b_out_real, btf_b_out_imag;
  logic btf_mode;
  logic signed [4:0] btf_scale_factor;
  logic [9:0] btf_tw_addr;
  logic btf_in_valid, btf_out_valid;
  fft_butterfly fft_butterfly(
                  .clk(clk),
                  .mode(btf_mode),
                  .in_valid(btf_in_valid),

                  .a_in_real(btf_a_in_real),
                  .a_in_imag(btf_a_in_imag),
                  .b_in_real(btf_b_in_real),
                  .b_in_imag(btf_b_in_imag),

                  .tw_addr(btf_tw_addr),

                  .scale_factor(btf_scale_factor),

                  .a_out_real(btf_a_out_real),
                  .a_out_imag(btf_a_out_imag),
                  .b_out_real(btf_b_out_real),
                  .b_out_imag(btf_b_out_imag),

                  .out_valid(btf_out_valid)
                );

  logic fft_mode, fft_start, fft_start_i, fft_done;
  logic [`BRAM_ADDR_WIDTH-1:0] fft_bram1_addr_a, fft_bram1_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] fft_bram1_din_a, fft_bram1_din_b;
  logic [`BRAM_DATA_WIDTH-1:0] fft_bram1_dout_a, fft_bram1_dout_b;
  logic fft_bram1_we_a, fft_bram1_we_b;
  logic [`BRAM_ADDR_WIDTH-1:0] fft_bram2_addr_a, fft_bram2_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] fft_bram2_din_a, fft_bram2_din_b;
  logic [`BRAM_DATA_WIDTH-1:0] fft_bram2_dout_a, fft_bram2_dout_b;
  logic fft_bram2_we_a, fft_bram2_we_b;
  fft #(
        .N(N)
      )fft(
        .clk(clk),
        .rst(!rst_n),
        .mode(fft_mode),
        .start(fft_start && !fft_start_i),

        .bram1_addr_a(fft_bram1_addr_a),
        .bram1_din_a(fft_bram1_din_a),
        .bram1_dout_a(fft_bram1_dout_a),
        .bram1_we_a(fft_bram1_we_a),
        .bram1_addr_b(fft_bram1_addr_b),
        .bram1_din_b(fft_bram1_din_b),
        .bram1_dout_b(fft_bram1_dout_b),
        .bram1_we_b(fft_bram1_we_b),

        .bram2_addr_a(fft_bram2_addr_a),
        .bram2_din_a(fft_bram2_din_a),
        .bram2_dout_a(fft_bram2_dout_a),
        .bram2_we_a(fft_bram2_we_a),
        .bram2_addr_b(fft_bram2_addr_b),
        .bram2_din_b(fft_bram2_din_b),
        .bram2_dout_b(fft_bram2_dout_b),
        .bram2_we_b(fft_bram2_we_b),

        .done(fft_done),

        .btf_mode(btf_mode),
        .btf_in_valid(btf_in_valid),
        .btf_a_in_real(btf_a_in_real),
        .btf_a_in_imag(btf_a_in_imag),
        .btf_b_in_real(btf_b_in_real),
        .btf_b_in_imag(btf_b_in_imag),
        .btf_scale_factor(btf_scale_factor),
        .btf_tw_addr(btf_tw_addr),
        .btf_a_out_real(btf_a_out_real),
        .btf_a_out_imag(btf_a_out_imag),
        .btf_b_out_real(btf_b_out_real),
        .btf_b_out_imag(btf_b_out_imag),
        .btf_out_valid(btf_out_valid)
      );

  // Task execution based on opcode
  always_ff @(posedge clk) begin

    // Instruction decoding
    opcode <= instruction[31:28];
    task_bank1 <= instruction[27:25];
    task_addr1 <= instruction[24:16];
    task_bank2 <= instruction[15:13];
    task_addr2 <= instruction[12:4];
    task_params <= instruction[3:0];

    if (!rst_n) begin
      htp_start <= 1'b0;
      htp_start_i <= 1'b0;

      fft_start <= 1'b0;
      fft_start_i <= 1'b0;
    end
    else begin

      htp_start_i <= htp_start;
      fft_start_i <= fft_start;

      case (opcode)
        4'b0000: begin // NOP
          // No operation, do nothing except stop writing to BRAMs

          htp_start <= 1'b0;

          for(int i = 0; i < BRAM_BANK_COUNT; i++) begin
            bram_we_a[i] <= 1'b0;
            bram_we_b[i] <= 1'b0;
          end
        end

        4'b0001: begin  // Hash to point
          htp_start <= 1'b1;
        end

        4'b0010: begin  // FFT
          fft_mode <= task_params[3]; // Set FFT mode based on task parameters
          fft_start <= 1'b1;
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

        4'b1010: begin  // int to double

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
        bram_addr_a[task_bank1] = htp_input_bram_addr;
        htp_input_bram_data = bram_dout_a[task_bank1];

        bram_addr_a[task_bank2] = htp_output_bram1_addr;
        bram_din_a[task_bank2] = htp_output_bram1_data;
        bram_we_a[task_bank2] = htp_output_bram1_we;

        bram_addr_b[task_bank2] = htp_output_bram2_addr;
        htp_output_bram2_data = bram_dout_b[task_bank2];

        instruction_done = htp_done;
      end

      4'b0010: begin  // FFT/IFFT
        bram_addr_a[task_bank1] = fft_bram1_addr_a;
        bram_din_a[task_bank1] = fft_bram1_din_a;
        bram_we_a[task_bank1] = fft_bram1_we_a;
        bram_addr_b[task_bank1] = fft_bram1_addr_b;
        bram_din_b[task_bank1] = fft_bram1_din_b;
        bram_we_b[task_bank1] = fft_bram1_we_b;
        fft_bram1_dout_a = bram_dout_a[task_bank1];
        fft_bram1_dout_b = bram_dout_b[task_bank1];

        bram_addr_a[task_bank2] = fft_bram2_addr_a;
        bram_din_a[task_bank2] = fft_bram2_din_a;
        bram_we_a[task_bank2] = fft_bram2_we_a;
        bram_addr_b[task_bank2] = fft_bram2_addr_b;
        bram_din_b[task_bank2] = fft_bram2_din_b;
        bram_we_b[task_bank2] = fft_bram2_we_b;
        fft_bram2_dout_a = bram_dout_a[task_bank2];
        fft_bram2_dout_b = bram_dout_b[task_bank2];

        instruction_done = fft_done;
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

        bram_addr_a[task_bank1] = task_addr1;
        bram_dout = bram_dout_a[task_bank1];

        instruction_done = 1'b1; // We set done to 1 immediately even though the read will take a few cycles. This is because the data will definitely be available then, so we can issue the next instruction.
      end

      4'b1001: begin  // BRAM write
        // Writes to BRAM "task_bank1" at address "task_addr1". Input is "bram_din".

        bram_addr_a[task_bank1] = task_addr1;
        bram_din_a[task_bank1] = bram_din;
        bram_we_a[task_bank1] = 1'b1;

        instruction_done = 1'b1;
      end

      4'b1010: begin  // int to double
        bram_addr_a[task_bank1] = task_addr1;
        int_to_double_data_in = bram_dout_a[task_bank1];

        // Write output to BRAM
        if(int_to_double_valid_out) begin
          bram_addr_b[task_bank2] = int_to_double_write_addr;
          bram_din_b[task_bank2] = int_to_double_data_out;
          bram_we_b[task_bank2] = 1'b1;
        end

        int_to_double_valid_in = 1'b1;
        instruction_done = 1'b1;
      end

      default: begin

      end

    endcase
  end

endmodule
