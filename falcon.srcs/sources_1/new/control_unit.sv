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
// See definition of enum opcode_t for available opcodes.
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

    input logic [`FFT_BRAM_DATA_WIDTH-1:0] bram_din, // Data to write to BRAM
    output logic [`FFT_BRAM_DATA_WIDTH-1:0] bram_dout // Data read from BRAM
  );

  parameter int FFT_BRAM_BANK_COUNT = 6; // Number of 512x128 BRAM banks
  parameter int NTT_BRAM_BANK_COUNT = 2; // Number of 1024x15 BRAM banks

  typedef enum logic [3:0] {
            NOP           = 4'b0000, // No operation, sets WE for all BRAMs to 0
            HASH_TO_POINT = 4'b0001, // Input is task_bram1. First BRAM cell contains length of salt and message combined in bytes. Output is task_bram2. src and dest cannot be the same because we need 3 channels (1 for input and 2 for output)
            FFT_IFFT      = 4'b0010, // Input is task_bram1, output is task_bram1 or task_bram2 (depends on N, see fft module header for more info). task_params[3] sets FFT (0) or IFFT (1) mode.
            FP_ARITH      = 4'b0011,
            FFT_SPLIT     = 4'b0100,
            FFT_MERGE     = 4'b0101,
            CHECK_NORM    = 4'b0110,
            DECOMPRESS    = 4'b0111, // Input is task_bank1. First BRAM cell contains the length of signature in bits. The remaining BRAM cells contain the compressed signature. Output is task_bank2 and also task_params[2:0] (output is written to two banks at the same time, because we destroy one of them with NTT later)
            BRAM_READ     = 4'b1000, // Reads task_bank1 at address task_addr1. Output is bram_dout
            BRAM_WRITE    = 4'b1001, // Writes bram_din to task_bank1 address task_addr1 .
            INT_TO_DOUBLE = 4'b1010, // Input is task_bank1 at address task_addr1. Output is task_bank2 at address task_addr2
            NTT_INTT      = 4'b1011,  // Input is task_bank1, which should be 0-5, output is task_bank2, which should be 6 or 7. task_params[3] sets NTT (0) or INTT (1) mode.
            MOD_MULT_Q    = 4'b1100  // Inputs are always BRAM 6 and BRAM 7 (because those two are the only ones with the expected shape - 1024x128). Output is task_bram2. Module reads from both input BRAMs at address task_addr1 and task_addr2 and writes the output to task_addr1
          } opcode_t;

  opcode_t opcode;
  logic [2:0] task_bank1;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] task_addr1;
  logic [2:0] task_bank2;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] task_addr2;
  logic [3:0] task_params;

  logic [`FFT_BRAM_ADDR_WIDTH-1:0] fft_bram_addr_a [FFT_BRAM_BANK_COUNT];
  logic [`FFT_BRAM_DATA_WIDTH-1:0] fft_bram_dout_a [FFT_BRAM_BANK_COUNT];
  logic [`FFT_BRAM_DATA_WIDTH-1:0] fft_bram_din_a [FFT_BRAM_BANK_COUNT];
  logic fft_bram_we_a [FFT_BRAM_BANK_COUNT];
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] fft_bram_addr_b [FFT_BRAM_BANK_COUNT];
  logic [`FFT_BRAM_DATA_WIDTH-1:0] fft_bram_din_b [FFT_BRAM_BANK_COUNT];
  logic [`FFT_BRAM_DATA_WIDTH-1:0] fft_bram_dout_b [FFT_BRAM_BANK_COUNT];
  logic fft_bram_we_b [FFT_BRAM_BANK_COUNT];
  genvar i_fft;
  generate
    for (i_fft = 0; i_fft < FFT_BRAM_BANK_COUNT; i_fft++) begin : fft_bram_bank
      bram_512x128 bram_512x128_inst (
                     .addra(fft_bram_addr_a[i_fft]),
                     .clka(clk),
                     .dina(fft_bram_din_a[i_fft]),
                     .douta(fft_bram_dout_a[i_fft]),
                     .wea(fft_bram_we_a[i_fft]),

                     .addrb(fft_bram_addr_b[i_fft]),
                     .clkb(clk),
                     .dinb(fft_bram_din_b[i_fft]),
                     .doutb(fft_bram_dout_b[i_fft]),
                     .web(fft_bram_we_b[i_fft])
                   );
    end
  endgenerate

  logic [`NTT_BRAM_ADDR_WIDTH-1:0] ntt_bram_addr_a [NTT_BRAM_BANK_COUNT];
  logic [`NTT_BRAM_DATA_WIDTH-1:0] ntt_bram_dout_a [NTT_BRAM_BANK_COUNT];
  logic [`NTT_BRAM_DATA_WIDTH-1:0] ntt_bram_din_a [NTT_BRAM_BANK_COUNT];
  logic ntt_bram_we_a [NTT_BRAM_BANK_COUNT];
  logic [`NTT_BRAM_ADDR_WIDTH-1:0] ntt_bram_addr_b [NTT_BRAM_BANK_COUNT];
  logic [`NTT_BRAM_DATA_WIDTH-1:0] ntt_bram_din_b [NTT_BRAM_BANK_COUNT];
  logic [`NTT_BRAM_DATA_WIDTH-1:0] ntt_bram_dout_b [NTT_BRAM_BANK_COUNT];
  logic ntt_bram_we_b [NTT_BRAM_BANK_COUNT];
  genvar i_ntt;
  generate
    for (i_ntt = 0; i_ntt < NTT_BRAM_BANK_COUNT; i_ntt++) begin : ntt_bram_bank
      bram_1024x15 bram_1024x15_inst (
                     .addra(ntt_bram_addr_a[i_ntt]),
                     .clka(clk),
                     .dina(ntt_bram_din_a[i_ntt]),
                     .douta(ntt_bram_dout_a[i_ntt]),
                     .wea(ntt_bram_we_a[i_ntt]),

                     .addrb(ntt_bram_addr_b[i_ntt]),
                     .clkb(clk),
                     .dinb(ntt_bram_din_b[i_ntt]),
                     .doutb(ntt_bram_dout_b[i_ntt]),
                     .web(ntt_bram_we_b[i_ntt])
                   );
    end
  endgenerate

  logic htp_start, htp_start_i;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] htp_input_bram_addr;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] htp_input_bram_data;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] htp_output_bram1_addr, htp_output_bram2_addr;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] htp_output_bram1_data, htp_output_bram2_data;
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

  logic [`FFT_BRAM_DATA_WIDTH-1:0] int_to_double_data_in, int_to_double_data_out;
  logic int_to_double_valid_in, int_to_double_valid_in_delayed, int_to_double_valid_out;
  int_to_double int_to_double (
                  .clk(clk),
                  .data_in(int_to_double_data_in),
                  .valid_in(int_to_double_valid_in_delayed),
                  .data_out(int_to_double_data_out),
                  .valid_out(int_to_double_valid_out)
                );
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] int_to_double_write_addr;  // Where to write the output of int_to_double
  delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(3)) int_to_double_write_addr_delay(.clk(clk), .in(task_addr2), .out(int_to_double_write_addr));
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
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] fft_bram1_addr_a, fft_bram1_addr_b;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] fft_bram1_din_a, fft_bram1_din_b;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] fft_bram1_dout_a, fft_bram1_dout_b;
  logic fft_bram1_we_a, fft_bram1_we_b;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] fft_bram2_addr_a, fft_bram2_addr_b;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] fft_bram2_din_a, fft_bram2_din_b;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] fft_bram2_dout_a, fft_bram2_dout_b;
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

  logic decompress_start, decompress_start_i;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] decompress_input_bram_addr;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] decompress_input_bram_data;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] decompress_output_bram1_addr;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] decompress_output_bram1_data;
  logic decompress_output_bram1_we;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] decompress_output_bram2_addr;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] decompress_output_bram2_data;
  logic decompress_signature_error, decompress_done;
  decompress #(
               .N(N)
             )
             decompress (
               .clk(clk),
               .rst_n(rst_n),
               .start(decompress_start && !decompress_start_i),

               .input_bram_addr(decompress_input_bram_addr),
               .input_bram_data(decompress_input_bram_data),

               .output_bram1_addr(decompress_output_bram1_addr),
               .output_bram1_data(decompress_output_bram1_data),
               .output_bram1_we(decompress_output_bram1_we),

               .output_bram2_addr(decompress_output_bram2_addr),
               .output_bram2_data(decompress_output_bram2_data),

               .signature_error(decompress_signature_error),
               .done(decompress_done)
             );


  logic ntt_start, ntt_start_i;
  logic ntt_mode;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] ntt_input_bram_addr1;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] ntt_input_bram_data1;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] ntt_input_bram_addr2;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] ntt_input_bram_data2;
  logic [`NTT_BRAM_ADDR_WIDTH-1:0] ntt_output_bram_addr1;
  logic [`NTT_BRAM_DATA_WIDTH-1:0] ntt_output_bram_data1;
  logic ntt_output_bram_we1;
  logic [`NTT_BRAM_ADDR_WIDTH-1:0] ntt_output_bram_addr2;
  logic [`NTT_BRAM_DATA_WIDTH-1:0] ntt_output_bram_data2;
  logic ntt_output_bram_we2;
  logic ntt_done;
  ntt #(
        .N(N)
      )ntt(
        .clk(clk),
        .rst_n(rst_n),
        .start(ntt_start && !ntt_start_i),
        .mode(ntt_mode),

        .input_bram_addr1(ntt_input_bram_addr1),
        .input_bram_data1(ntt_input_bram_data1),
        .input_bram_addr2(ntt_input_bram_addr2),
        .input_bram_data2(ntt_input_bram_data2),

        .output_bram_addr1(ntt_output_bram_addr1),
        .output_bram_data1(ntt_output_bram_data1),
        .output_bram_we1(ntt_output_bram_we1),
        .output_bram_addr2(ntt_output_bram_addr2),
        .output_bram_data2(ntt_output_bram_data2),
        .output_bram_we2(ntt_output_bram_we2),

        .done(ntt_done)
      );

  parameter int MOD_MULT_PARALLEL_OPS_COUNT = 2;
  logic [`NTT_BRAM_DATA_WIDTH-1:0] mod_mult_a [MOD_MULT_PARALLEL_OPS_COUNT], mod_mult_b [MOD_MULT_PARALLEL_OPS_COUNT];
  logic mod_mult_valid_in, mod_mult_valid_in_delayed;
  logic [`NTT_BRAM_DATA_WIDTH-1:0] mod_mult_result [MOD_MULT_PARALLEL_OPS_COUNT];
  logic mod_mult_valid_out;
  mod_mult #(
             .N(N),
             .PARALLEL_OPS_COUNT(MOD_MULT_PARALLEL_OPS_COUNT)
           )mod_mult (
             .clk(clk),
             .rst_n(rst_n),
             .a(mod_mult_a),
             .b(mod_mult_b),
             .valid_in(mod_mult_valid_in_delayed),
             .result(mod_mult_result),
             .valid_out(mod_mult_valid_out)
           );
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] mod_mult_write_addr;  // Where to write the output of mod_mult
  delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(7)) mod_mult_write_addr_delay(.clk(clk), .in(task_addr1), .out(mod_mult_write_addr));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) mod_mult_valid_in_delay(.clk(clk), .in(mod_mult_valid_in), .out(mod_mult_valid_in_delayed));


  // Task execution based on opcode
  always_ff @(posedge clk) begin

    // Instruction decoding
    opcode <= opcode_t'(instruction[31:28]);
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

      decompress_start <= 1'b0;
      decompress_start_i <= 1'b0;

      ntt_start <= 1'b0;
      ntt_start_i <= 1'b0;
    end
    else begin

      htp_start_i <= htp_start;
      fft_start_i <= fft_start;
      decompress_start_i <= decompress_start;
      ntt_start_i <= ntt_start;

      case (opcode)
        NOP: begin
          htp_start <= 1'b0;
          fft_start <= 1'b0;
          decompress_start <= 1'b0;
          ntt_start <= 1'b0;
        end

        HASH_TO_POINT: begin
          htp_start <= 1'b1;
        end

        FFT_IFFT: begin
          fft_mode <= task_params[3]; // Set FFT mode based on task parameters
          fft_start <= 1'b1;
        end

        FP_ARITH: begin

        end

        FFT_SPLIT: begin

        end

        FFT_MERGE: begin

        end

        CHECK_NORM: begin

        end

        DECOMPRESS: begin
          decompress_start <= 1'b1;
        end

        BRAM_READ: begin

        end

        BRAM_WRITE: begin

        end

        INT_TO_DOUBLE: begin

        end

        NTT_INTT: begin
          ntt_mode <= task_params[3]; // Set NTT mode based on task parameters
          ntt_start <= 1'b1;
        end

        MOD_MULT_Q: begin

        end

        default: begin

        end

      endcase
    end
  end

  // BRAM routing
  always_comb begin

    instruction_done = 1'b0; // Default to not done
    int_to_double_valid_in = 1'b0;
    mod_mult_valid_in = 1'b0;

    case (opcode)
      NOP: begin
        // No operation, do nothing except stop writing to BRAMs
        for(int i = 0; i < FFT_BRAM_BANK_COUNT; i++) begin
          fft_bram_we_a[i] = 1'b0;
          fft_bram_we_b[i] = 1'b0;
        end
        for(int i = 0; i < NTT_BRAM_BANK_COUNT; i++) begin
          ntt_bram_we_a[i] = 1'b0;
          ntt_bram_we_b[i] = 1'b0;
        end
      end

      HASH_TO_POINT: begin
        fft_bram_addr_a[task_bank1] = htp_input_bram_addr;
        htp_input_bram_data = fft_bram_dout_a[task_bank1];

        fft_bram_addr_a[task_bank2] = htp_output_bram1_addr;
        fft_bram_din_a[task_bank2] = htp_output_bram1_data;
        fft_bram_we_a[task_bank2] = htp_output_bram1_we;

        fft_bram_addr_b[task_bank2] = htp_output_bram2_addr;
        htp_output_bram2_data = fft_bram_dout_b[task_bank2];

        instruction_done = htp_done;
      end

      FFT_IFFT: begin
        fft_bram_addr_a[task_bank1] = fft_bram1_addr_a;
        fft_bram_din_a[task_bank1] = fft_bram1_din_a;
        fft_bram_we_a[task_bank1] = fft_bram1_we_a;
        fft_bram_addr_b[task_bank1] = fft_bram1_addr_b;
        fft_bram_din_b[task_bank1] = fft_bram1_din_b;
        fft_bram_we_b[task_bank1] = fft_bram1_we_b;
        fft_bram1_dout_a = fft_bram_dout_a[task_bank1];
        fft_bram1_dout_b = fft_bram_dout_b[task_bank1];

        fft_bram_addr_a[task_bank2] = fft_bram2_addr_a;
        fft_bram_din_a[task_bank2] = fft_bram2_din_a;
        fft_bram_we_a[task_bank2] = fft_bram2_we_a;
        fft_bram_addr_b[task_bank2] = fft_bram2_addr_b;
        fft_bram_din_b[task_bank2] = fft_bram2_din_b;
        fft_bram_we_b[task_bank2] = fft_bram2_we_b;
        fft_bram2_dout_a = fft_bram_dout_a[task_bank2];
        fft_bram2_dout_b = fft_bram_dout_b[task_bank2];

        instruction_done = fft_done;
      end

      FP_ARITH: begin

      end

      FFT_SPLIT: begin

      end

      FFT_MERGE: begin

      end

      CHECK_NORM: begin

      end

      DECOMPRESS: begin
        fft_bram_addr_a[task_bank1] = decompress_input_bram_addr;
        decompress_input_bram_data = fft_bram_dout_a[task_bank1];

        // We output to both task_bank2 and task_params[2:0]
        fft_bram_addr_a[task_bank2] = decompress_output_bram1_addr;
        fft_bram_din_a[task_bank2] = decompress_output_bram1_data;
        fft_bram_we_a[task_bank2] = decompress_output_bram1_we;
        fft_bram_addr_a[task_params[2:0]] = decompress_output_bram1_addr;
        fft_bram_din_a[task_params[2:0]] = decompress_output_bram1_data;
        fft_bram_we_a[task_params[2:0]] = decompress_output_bram1_we;

        fft_bram_addr_b[task_bank2] = decompress_output_bram2_addr;
        decompress_output_bram2_data = fft_bram_dout_b[task_bank2];

        instruction_done = decompress_done;
      end

      BRAM_READ: begin
        // Reads from BRAM "task_bank1" at address "task_addr1". Output is "bram_dout".

        fft_bram_addr_a[task_bank1] = task_addr1;
        bram_dout = fft_bram_dout_a[task_bank1];

        instruction_done = 1'b1; // We set done to 1 immediately even though the read will take a few cycles. This is because the data will definitely be available then, so we can issue the next instruction.
      end

      BRAM_WRITE: begin
        // Writes to BRAM "task_bank1" at address "task_addr1". Input is "bram_din".

        fft_bram_addr_a[task_bank1] = task_addr1;
        fft_bram_din_a[task_bank1] = bram_din;
        fft_bram_we_a[task_bank1] = 1'b1;

        instruction_done = 1'b1;
      end

      INT_TO_DOUBLE: begin
        fft_bram_addr_a[task_bank1] = task_addr1;
        int_to_double_data_in = fft_bram_dout_a[task_bank1];

        // Write output to BRAM
        if(int_to_double_valid_out) begin
          fft_bram_addr_b[task_bank2] = int_to_double_write_addr;
          fft_bram_din_b[task_bank2] = int_to_double_data_out;
          fft_bram_we_b[task_bank2] = 1'b1;
        end

        int_to_double_valid_in = 1'b1;
        instruction_done = 1'b1;
      end

      NTT_INTT: begin
        fft_bram_addr_a[task_bank1] = ntt_input_bram_addr1;
        ntt_input_bram_data1 = fft_bram_dout_a[task_bank1];
        fft_bram_addr_b[task_bank1] = ntt_input_bram_addr2;
        ntt_input_bram_data2 = fft_bram_dout_b[task_bank1];

        ntt_bram_addr_a[task_bank2] = ntt_output_bram_addr1;
        ntt_bram_din_a[task_bank2] = ntt_output_bram_data1;
        ntt_bram_we_a[task_bank2] = ntt_output_bram_we1;
        ntt_bram_addr_b[task_bank2] = ntt_output_bram_addr2;
        ntt_bram_din_b[task_bank2] = ntt_output_bram_data2;
        ntt_bram_we_b[task_bank2] = ntt_output_bram_we2;

        instruction_done = ntt_done;
      end

      MOD_MULT_Q: begin
        // From each input BRAM we read at address "task_addr1" and "task_addr2"
        ntt_bram_addr_a[0] = task_addr1;
        ntt_bram_addr_b[0] = task_addr2;
        ntt_bram_addr_a[1] = task_addr1;
        ntt_bram_addr_b[1] = task_addr2;

        mod_mult_a[0] = ntt_bram_dout_a[0];
        mod_mult_a[1] = ntt_bram_dout_b[0];
        mod_mult_b[0] = ntt_bram_dout_a[1];
        mod_mult_b[1] = ntt_bram_dout_b[1];

        mod_mult_valid_in = 1'b1;
        instruction_done = 1'b1;

        if(mod_mult_valid_out) begin
          fft_bram_addr_a[task_bank2] = mod_mult_write_addr;
          fft_bram_din_a[task_bank2] = {49'b0, mod_mult_result[0], 49'b0, mod_mult_result[1]};
          fft_bram_we_a[task_bank2] = 1'b1;
        end
      end

      default: begin

      end

    endcase
  end

endmodule
