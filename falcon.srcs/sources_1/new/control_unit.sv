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
// Only 8 BRAM banks are addressable using the instruction format, but we have more than that.
// The others can only be accessed by hardcoded instructions.
// Note also that there are 2 additional 1024x15 BRAM banks (called ntt_bram) that can be accessed by the same indices as the 512x128 BRAM banks,
// but will be used only with specific instructions (such as NTT_INTT).
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

  parameter int FFT_BRAM_BANK_COUNT = 10; // Number of 512x128 BRAM banks
  parameter int NTT_BRAM_BANK_COUNT = 2; // Number of 1024x15 BRAM banks

  typedef enum logic [3:0] {
            NOP           = 4'b0000, // No operation, sets WE for all BRAMs to 0
            HASH_TO_POINT = 4'b0001, // Input is task_bram1. First BRAM cell contains length of salt and message combined in bytes. Output is task_bram2. src and dest cannot be the same because we need 3 channels (1 for input and 2 for output)
            FFT_IFFT      = 4'b0010, // Input is task_bram1, output is task_bram1 or task_bram2 (depends on N, see fft module header for more info). task_params[3] sets FFT (0) or IFFT (1) mode.
            COMBINED      = 4'b0011, // Runs multiple modules in parallel with hardcoded BRAM inputs and outputs. task_params[3:0] is the index of which set of modules to run. See definition of combined_instruction_t for available sets.
            AVAILABLE1    = 4'b0100,
            AVAILABLE2    = 4'b0101,
            AVAILABLE3    = 4'b0110,
            AVAILABLE4    = 4'b0111,
            BRAM_RW       = 4'b1000, // If task_params[3] = 0: bram_dout = task_bank1[task_addr1]; if task_params[3] = 1: task_bank2[task_addr2] = bram_din; for writing, if task_params[2] == 1 we run the input data through int_to_double before writing it to BRAM
            AVAILABLE5    = 4'b1001,
            INT_TO_DOUBLE = 4'b1010, // Input is task_bank1 at address task_addr1. Output is task_bank2 at address task_addr2
            NTT_INTT      = 4'b1011, // Input is task_bank1, which should be 0-5, output is task_bank2, which should be 6 or 7. task_params[3] sets NTT (0) or INTT (1) mode.
            MOD_MULT_Q    = 4'b1100, // Inputs are always BRAM 6 and BRAM 7 (because those two are the only ones with the expected shape - 1024x128). Output is task_bram2. Module reads from both input BRAMs at address task_addr1 and task_addr2 and writes the output to task_addr1
            SUB_NORM_SQ   = 4'b1101, // Reads from BRAMs task_bank1[task_addr1] (data from hash_to_point), task_bank2[task_addr2], task_bank2[task_addr2+N/2] (data from INTT) and task_params[2:0][task_addr1] (data from decompress). Output is BRAM0 at address 0 (accept/reject), 0x000...00 = accept, 0xfff...ff = reject
            AVAILABLE6    = 4'b1110,
            AVAILABLE7    = 4'b1111
          } opcode_t;

  typedef enum logic [3:0] {
            HTP_DECMP_NTT = 4'b0000, // hash_to_point, decompress, ntt. Used in verify. NTT takes the longest, so we use it's done signal to know when everything is done
            SIGN_STEP_1   = 4'b0001, // Step 1 of sign: FFT, negate and hash_to_point. task_addr1 and task_addr2 are source and destination addresses for negate
            SIGN_STEP_2   = 4'b0010, // Step 2 of sign: mulselfadj, FFT, negate and int_to_double. task_addr1 and task_addr2 are source and destination addresses for negate, int_to_double and mulselfadj
            SIGN_STEP_3   = 4'b0011, // Step 3 of sign: mulselfadj and FFT. task_addr1 and task_addr2 are source and destination addresses for mulselfadj
            SIGN_STEP_4   = 4'b0100, // Step 4 of sign: copy, FFT, add. task_addr1 and task_addr2 are source and destination addresses for copy and add
            SIGN_STEP_5   = 4'b0101, // Step 5 of sign: mul, mulselfadj and FFT. task_addr1 and task_addr2 are source and destination addresses for mulselfadj and mul
            SIGN_STEP_6   = 4'b0110, // Step 6 of sign: mul and mulselfadj. task_addr1 and task_addr2 are source and destination addresses for mulselfadj and mul
            SIGN_STEP_7   = 4'b0111, // Step 7 of sign: add, muladj, mul const. task_addr1 and task_addr2 are source and destination addresses for add, muladj and mul const
            SIGN_STEP_8   = 4'b1000, // Step 8 of sign: muladj, mul const. task_addr1 and task_addr2 are source and destination addresses for muladj and mul const
            SIGN_STEP_9   = 4'b1001  // Step 9 of sign: add. task_addr1 and task_addr2 are source and destination addresses for add
          } combined_instruction_t;

  opcode_t opcode;
  combined_instruction_t combined_instruction;
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

  logic [`FFT_BRAM_DATA_WIDTH-1:0] int_to_double_data_in;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] int_to_double_address_in, int_to_double_address_in_delayed, int_to_double_address_in_override;
  logic int_to_double_valid_in, int_to_double_valid_in_delayed, int_to_double_valid_in_override;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] int_to_double_data_out;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] int_to_double_address_out;
  logic int_to_double_valid_out;
  logic int_to_double_done;
  int_to_double int_to_double (
                  .clk(clk),
                  .data_in(int_to_double_data_in),
                  .valid_in(int_to_double_valid_in_delayed || int_to_double_valid_in_override),
                  .address_in(int_to_double_valid_in_override ? int_to_double_address_in_override : int_to_double_address_in_delayed),
                  .data_out(int_to_double_data_out),
                  .valid_out(int_to_double_valid_out),
                  .address_out(int_to_double_address_out)
                );
  delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(1)) int_to_double_address_in_delay(.clk(clk), .in(int_to_double_address_in), .out(int_to_double_address_in_delayed));
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
        .rst(!rst_n || instruction_done), // Reset on instruction_done so it's ready for the next instruction
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

  parameter int SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT = 2;
  logic [`NTT_BRAM_DATA_WIDTH-1:0] sub_normalize_squared_norm_a [SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT], sub_normalize_squared_norm_b [SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT], sub_normalize_squared_norm_c [SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT];
  logic sub_normalize_squared_norm_valid, sub_normalize_squared_norm_valid_delayed;
  logic sub_normalize_squared_norm_last, sub_normalize_squared_norm_last_delayed;
  logic sub_normalize_squared_norm_accept, sub_normalize_squared_norm_reject;
  sub_normalize_squared_norm #(
                               .N(N),
                               .PARALLEL_OPS_COUNT(SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT)
                             )sub_normalize_squared_norm (
                               .clk(clk),
                               .rst_n(rst_n),
                               .a(sub_normalize_squared_norm_a),
                               .b(sub_normalize_squared_norm_b),
                               .c(sub_normalize_squared_norm_c),
                               .valid(sub_normalize_squared_norm_valid_delayed),
                               .last(sub_normalize_squared_norm_last_delayed),
                               .accept(sub_normalize_squared_norm_accept),
                               .reject(sub_normalize_squared_norm_reject)
                             );
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) sub_normalize_squared_norm_valid_delay(.clk(clk), .in(sub_normalize_squared_norm_valid), .out(sub_normalize_squared_norm_valid_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) sub_normalize_squared_norm_last_delay(.clk(clk), .in(sub_normalize_squared_norm_last), .out(sub_normalize_squared_norm_last_delayed));

  parameter int FLP_NEGATE_PARALLEL_OPS_COUNT = 2;
  logic [63:0] flp_negate_double_in [FLP_NEGATE_PARALLEL_OPS_COUNT];
  logic flp_negate_valid_in, flp_negate_valid_in_delayed;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] flp_negate_address_in, flp_negate_address_in_delayed;
  logic [63:0] flp_negate_double_out [FLP_NEGATE_PARALLEL_OPS_COUNT];
  logic flp_negate_valid_out;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] flp_negate_address_out;
  logic flp_negate_done;
  flp_negate #(
               .PARALLEL_OPS_COUNT(FLP_NEGATE_PARALLEL_OPS_COUNT)
             )flp_negate (
               .clk(clk),
               .double_in(flp_negate_double_in),
               .valid_in(flp_negate_valid_in_delayed),
               .address_in(flp_negate_address_in_delayed),
               .double_out(flp_negate_double_out),
               .valid_out(flp_negate_valid_out),
               .address_out(flp_negate_address_out)
             );
  delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(2)) flp_negate_address_in_delay(.clk(clk), .in(flp_negate_address_in), .out(flp_negate_address_in_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) flp_negate_valid_in_delay(.clk(clk), .in(flp_negate_valid_in), .out(flp_negate_valid_in_delayed));

  logic [`FFT_BRAM_DATA_WIDTH-1:0] muladjoint_data_a_in, muladjoint_data_b_in;
  logic muladjoint_valid_in, muladjoint_valid_in_delayed;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] muladjoint_address_in, muladjoint_address_in_delayed;
  logic [`FFT_BRAM_DATA_WIDTH-1:0] muladjoint_data_out;
  logic muladjoint_valid_out;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] muladjoint_address_out;
  logic muladjoint_done;
  muladjoint muladjoint (
               .clk(clk),
               .a_in(muladjoint_data_a_in),
               .b_in(muladjoint_data_b_in),
               .valid_in(muladjoint_valid_in_delayed),
               .address_in(muladjoint_address_in_delayed),
               .data_out(muladjoint_data_out),
               .valid_out(muladjoint_valid_out),
               .address_out(muladjoint_address_out)
             );
  delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(2)) muladjoint_address_in_delay(.clk(clk), .in(muladjoint_address_in), .out(muladjoint_address_in_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) muladjoint_valid_in_delay(.clk(clk), .in(muladjoint_valid_in), .out(muladjoint_valid_in_delayed));

  // FLP adder can only add two 64 doubles at a time, so we use two instances of it to add 4 doubles at a time.
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] flp_adder_address_in;
  logic flp_adder_in_valid, flp_adder_in_valid_delayed;
  logic [63:0] flp_adder1_a, flp_adder1_b;
  logic [63:0] flp_adder2_a, flp_adder2_b;
  logic [63:0] flp_adder1_result;
  logic [63:0] flp_adder2_result;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] flp_adder_address_out;
  logic flp_adder_out_valid;
  logic flp_adder_done;
  flp_adder #(
              .DO_SUBSTRACTION(0)  // 0 for addition, 1 for subtraction
            ) flp_adder1(
              .clk(clk),
              .in_valid(flp_adder_in_valid_delayed),
              .a(flp_adder1_a),
              .b(flp_adder1_b),
              .result(flp_adder1_result),
              .out_valid(flp_adder_out_valid)
            );
  flp_adder #(
              .DO_SUBSTRACTION(0)  // 0 for addition, 1 for subtraction
            ) flp_adder2(
              .clk(clk),
              .in_valid(flp_adder_in_valid_delayed),
              .a(flp_adder2_a),
              .b(flp_adder2_b),
              .result(flp_adder2_result),
              .out_valid()
            );
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) flp_adder1_in_valid_delay(.clk(clk), .in(flp_adder_in_valid), .out(flp_adder_in_valid_delayed));
  delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(9)) flp_adder1_address_in_delay(.clk(clk), .in(flp_adder_address_in), .out(flp_adder_address_out));

  logic [`FFT_BRAM_ADDR_WIDTH-1:0] copy_address_in;
  logic copy_valid_in;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] copy_address_out;
  logic copy_valid_out;
  logic copy_done;
  delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(2)) copy_address_in_delay(.clk(clk), .in(copy_address_in), .out(copy_address_out));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) copy_valid_in_delay(.clk(clk), .in(copy_valid_in), .out(copy_valid_out));

  logic [63:0] mul_a_real, mul_a_imag, mul_b_real, mul_b_imag;
  logic mul_valid_in, mul_valid_in_delayed;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] mul_address_in;
  logic [63:0] mul_result_real, mul_result_imag;
  logic mul_valid_out;
  logic [`FFT_BRAM_ADDR_WIDTH-1:0] mul_address_out;
  logic mul_done;
  complex_multiplier complex_multiplier(
                       .clk(clk),
                       .in_valid(mul_valid_in_delayed),
                       .a_real(mul_a_real),
                       .a_imag(mul_a_imag),
                       .b_real(mul_b_real),
                       .b_imag(mul_b_imag),
                       .scale_factor(5'b0),
                       .a_x_b_real(mul_result_real),
                       .a_x_b_imag(mul_result_imag),
                       .out_valid(mul_valid_out)
                     );
  delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(16)) mul_address_in_delay(.clk(clk), .in(mul_address_in), .out(mul_address_out));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) mul_valid_in_delay(.clk(clk), .in(mul_valid_in), .out(mul_valid_in_delayed));

  // Task execution based on opcode
  always_ff @(posedge clk) begin

    // Instruction decoding
    opcode <= opcode_t'(instruction[31:28]);
    combined_instruction <= combined_instruction_t'(instruction[3:0]);
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
          flp_negate_done <= 1'b0;
          muladjoint_done <= 1'b0;
          flp_adder_done <= 1'b0;
          copy_done <= 1'b0;
          mul_done <= 1'b0;
          int_to_double_done <= 1'b0;
        end

        HASH_TO_POINT: begin
          htp_start <= 1'b1;
        end

        FFT_IFFT: begin
          fft_mode <= task_params[3]; // Set FFT mode based on task parameters
          fft_start <= 1'b1;
        end

        COMBINED: begin

          case (combined_instruction)
            HTP_DECMP_NTT: begin
              htp_start <= 1'b1;
              decompress_start <= 1'b1;
              ntt_mode <= 1'b0;
              ntt_start <= 1'b1;
            end

            SIGN_STEP_1: begin
              fft_start <= 1'b1;
              fft_mode <= 1'b0;
              htp_start <= 1'b1;

              if(flp_negate_address_in == N/2-1)
                flp_negate_done <= 1'b1;
            end

            SIGN_STEP_2: begin
              fft_start <= 1'b1;
              fft_mode <= 1'b0;

              if(flp_negate_address_in == N/2-1)
                flp_negate_done <= 1'b1;
              if(muladjoint_address_in == N/2-1)
                muladjoint_done <= 1'b1;
              if(int_to_double_address_in == N/2-1)
                int_to_double_done <= 1'b1;
            end

            SIGN_STEP_3: begin
              fft_start <= 1'b1;
              fft_mode <= 1'b0;

              if(muladjoint_address_in == N/2-1)
                muladjoint_done <= 1'b1;
            end

            SIGN_STEP_4: begin
              fft_start <= 1'b1;
              fft_mode <= 1'b0;

              if(flp_adder_address_in == N/2-1)
                flp_adder_done <= 1'b1;
              if(copy_address_in == N/2-1)
                copy_done <= 1'b1;
            end

            SIGN_STEP_5: begin
              fft_start <= 1'b1;
              fft_mode <= 1'b0;

              if(muladjoint_address_in == N/2-1)
                muladjoint_done <= 1'b1;
              if(mul_address_in == N/2-1)
                mul_done <= 1'b1;
            end

            SIGN_STEP_6: begin
              if(muladjoint_address_in == N/2-1)
                muladjoint_done <= 1'b1;
              if(mul_address_in == N/2-1)
                mul_done <= 1'b1;
            end

            SIGN_STEP_7: begin
              if(muladjoint_address_in == N/2-1)
                muladjoint_done <= 1'b1;
              if(flp_adder_address_in == N/2-1)
                flp_adder_done <= 1'b1;
              if(mul_address_in == N/2-1)
                mul_done <= 1'b1;
            end

            SIGN_STEP_8: begin
              if(muladjoint_address_in == N/2-1)
                muladjoint_done <= 1'b1;
              if(mul_address_in == N/2-1)
                mul_done <= 1'b1;
            end

            SIGN_STEP_9: begin
              if(flp_adder_address_in == N/2-1)
                flp_adder_done <= 1'b1;
            end

            default: begin
            end
          endcase
        end

        BRAM_RW: begin

        end

        INT_TO_DOUBLE: begin

        end

        NTT_INTT: begin
          ntt_mode <= task_params[3]; // Set NTT mode based on task parameters
          ntt_start <= 1'b1;
        end

        MOD_MULT_Q: begin

        end

        SUB_NORM_SQ: begin

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
    int_to_double_valid_in_override = 1'b0;
    mod_mult_valid_in = 1'b0;
    sub_normalize_squared_norm_valid = 1'b0;
    sub_normalize_squared_norm_last = 1'b0;
    flp_negate_valid_in = 1'b0;
    muladjoint_valid_in = 1'b0;
    flp_adder_in_valid = 1'b0;

    // Ensure these signals are not undefined to ensure proper behaviour of the module
    sub_normalize_squared_norm_a[0] = 0;
    sub_normalize_squared_norm_a[1] = 0;
    sub_normalize_squared_norm_b[0] = 0;
    sub_normalize_squared_norm_b[1] = 0;
    sub_normalize_squared_norm_c[0] = 0;
    sub_normalize_squared_norm_c[1] = 0;

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

      COMBINED: begin
        case (combined_instruction)
          HTP_DECMP_NTT: begin
            // hash_to_point: input is BRAM0, output is BRAM3
            fft_bram_addr_a[0] = htp_input_bram_addr;
            htp_input_bram_data = fft_bram_dout_a[0];

            fft_bram_addr_a[3] = htp_output_bram1_addr;
            fft_bram_din_a[3] = htp_output_bram1_data;
            fft_bram_we_a[3] = htp_output_bram1_we;

            fft_bram_addr_b[3] = htp_output_bram2_addr;
            htp_output_bram2_data = fft_bram_dout_b[3];

            // decompress: input is BRAM2, output is BRAM5
            fft_bram_addr_a[2] = decompress_input_bram_addr;
            decompress_input_bram_data = fft_bram_dout_a[2];

            fft_bram_addr_a[5] = decompress_output_bram1_addr;
            fft_bram_din_a[5] = decompress_output_bram1_data;
            fft_bram_we_a[5] = decompress_output_bram1_we;

            fft_bram_addr_b[5] = decompress_output_bram2_addr;
            decompress_output_bram2_data = fft_bram_dout_b[5];

            // NTT: input is BRAM1, output is BRAM6 (ntt bram 0)
            fft_bram_addr_a[1] = ntt_input_bram_addr1;
            ntt_input_bram_data1 = fft_bram_dout_a[1];
            fft_bram_addr_b[1] = ntt_input_bram_addr2;
            ntt_input_bram_data2 = fft_bram_dout_b[1];

            ntt_bram_addr_a[0] = ntt_output_bram_addr1;
            ntt_bram_din_a[0] = ntt_output_bram_data1;
            ntt_bram_we_a[0] = ntt_output_bram_we1;
            ntt_bram_addr_b[0] = ntt_output_bram_addr2;
            ntt_bram_din_b[0] = ntt_output_bram_data2;
            ntt_bram_we_b[0] = ntt_output_bram_we2;

            instruction_done = ntt_done;  // NTT takes the longest
          end

          SIGN_STEP_1: begin
            // FFT: input is BRAM0, also uses BRAM4
            fft_bram_addr_a[0] = fft_bram1_addr_a;
            fft_bram_din_a[0] = fft_bram1_din_a;
            fft_bram_we_a[0] = fft_bram1_we_a;
            fft_bram_addr_b[0] = fft_bram1_addr_b;
            fft_bram_din_b[0] = fft_bram1_din_b;
            fft_bram_we_b[0] = fft_bram1_we_b;
            fft_bram1_dout_a = fft_bram_dout_a[0];
            fft_bram1_dout_b = fft_bram_dout_b[0];

            fft_bram_addr_a[4] = fft_bram2_addr_a;
            fft_bram_din_a[4] = fft_bram2_din_a;
            fft_bram_we_a[4] = fft_bram2_we_a;
            fft_bram_addr_b[4] = fft_bram2_addr_b;
            fft_bram_din_b[4] = fft_bram2_din_b;
            fft_bram_we_b[4] = fft_bram2_we_b;
            fft_bram2_dout_a = fft_bram_dout_a[4];
            fft_bram2_dout_b = fft_bram_dout_b[4];

            // hash_to_point: input is BRAM6, output is BRAM7
            fft_bram_addr_a[6] = htp_input_bram_addr;
            htp_input_bram_data = fft_bram_dout_a[6];

            fft_bram_addr_a[7] = htp_output_bram1_addr;
            fft_bram_din_a[7] = htp_output_bram1_data;
            fft_bram_we_a[7] = htp_output_bram1_we;

            fft_bram_addr_b[7] = htp_output_bram2_addr;
            htp_output_bram2_data = fft_bram_dout_b[7];

            // negate
            fft_bram_addr_a[1] = task_addr1;
            flp_negate_double_in[0] = fft_bram_dout_a[1][127:64];
            flp_negate_double_in[1] = fft_bram_dout_a[1][63:0];
            flp_negate_valid_in = !flp_negate_done;
            flp_negate_address_in = task_addr1;
            fft_bram_addr_b[1] = flp_negate_address_out;
            fft_bram_din_b[1] = {flp_negate_double_out[0], flp_negate_double_out[1]};
            fft_bram_we_b[1] = flp_negate_valid_out;

            instruction_done = fft_done;  // FFT takes the longest
          end

          SIGN_STEP_2: begin
            // FFT: input is BRAM1, also uses BRAM5
            fft_bram_addr_a[1] = fft_bram1_addr_a;
            fft_bram_din_a[1] = fft_bram1_din_a;
            fft_bram_we_a[1] = fft_bram1_we_a;
            fft_bram_addr_b[1] = fft_bram1_addr_b;
            fft_bram_din_b[1] = fft_bram1_din_b;
            fft_bram_we_b[1] = fft_bram1_we_b;
            fft_bram1_dout_a = fft_bram_dout_a[1];
            fft_bram1_dout_b = fft_bram_dout_b[1];

            fft_bram_addr_a[5] = fft_bram2_addr_a;
            fft_bram_din_a[5] = fft_bram2_din_a;
            fft_bram_we_a[5] = fft_bram2_we_a;
            fft_bram_addr_b[5] = fft_bram2_addr_b;
            fft_bram_din_b[5] = fft_bram2_din_b;
            fft_bram_we_b[5] = fft_bram2_we_b;
            fft_bram2_dout_a = fft_bram_dout_a[5];
            fft_bram2_dout_b = fft_bram_dout_b[5];

            // negate on BRAM3
            fft_bram_addr_a[3] = task_addr1;
            flp_negate_double_in[0] = fft_bram_dout_a[3][127:64];
            flp_negate_double_in[1] = fft_bram_dout_a[3][63:0];
            flp_negate_valid_in = !flp_negate_done;
            flp_negate_address_in = task_addr1;
            fft_bram_addr_b[3] = flp_negate_address_out;
            fft_bram_din_b[3] = {flp_negate_double_out[0], flp_negate_double_out[1]};
            fft_bram_we_b[3] = flp_negate_valid_out;

            // int_to_double on BRAM7
            fft_bram_addr_a[7] = task_addr1;
            int_to_double_data_in = fft_bram_dout_a[7];
            int_to_double_address_in = task_addr1;
            int_to_double_valid_in = !int_to_double_done;
            fft_bram_addr_b[7] = int_to_double_address_out;
            fft_bram_din_b[7] = int_to_double_data_out;
            fft_bram_we_b[7] = int_to_double_valid_out;

            // self muladjoint on BRAM0, output is BRAM4
            fft_bram_addr_a[0] = task_addr1;
            muladjoint_data_a_in = fft_bram_dout_a[0];
            muladjoint_data_b_in = fft_bram_dout_a[0];
            muladjoint_valid_in = !muladjoint_done;
            muladjoint_address_in = task_addr1;
            fft_bram_addr_b[4] = muladjoint_address_out;
            fft_bram_din_b[4] = muladjoint_data_out;
            fft_bram_we_b[4] = muladjoint_valid_out;

            instruction_done = fft_done;  // FFT takes the longest
          end

          SIGN_STEP_3: begin
            // FFT: input is BRAM7, also uses BRAM6
            fft_bram_addr_a[7] = fft_bram1_addr_a;
            fft_bram_din_a[7] = fft_bram1_din_a;
            fft_bram_we_a[7] = fft_bram1_we_a;
            fft_bram_addr_b[7] = fft_bram1_addr_b;
            fft_bram_din_b[7] = fft_bram1_din_b;
            fft_bram_we_b[7] = fft_bram1_we_b;
            fft_bram1_dout_a = fft_bram_dout_a[7];
            fft_bram1_dout_b = fft_bram_dout_b[7];

            fft_bram_addr_a[6] = fft_bram2_addr_a;
            fft_bram_din_a[6] = fft_bram2_din_a;
            fft_bram_we_a[6] = fft_bram2_we_a;
            fft_bram_addr_b[6] = fft_bram2_addr_b;
            fft_bram_din_b[6] = fft_bram2_din_b;
            fft_bram_we_b[6] = fft_bram2_we_b;
            fft_bram2_dout_a = fft_bram_dout_a[6];
            fft_bram2_dout_b = fft_bram_dout_b[6];

            // self muladjoint on BRAM1, output is BRAM5
            fft_bram_addr_a[1] = task_addr1;
            muladjoint_data_a_in = fft_bram_dout_a[1];
            muladjoint_data_b_in = fft_bram_dout_a[1];
            muladjoint_valid_in = !muladjoint_done;
            muladjoint_address_in = task_addr1;
            fft_bram_addr_b[5] = muladjoint_address_out;
            fft_bram_din_b[5] = muladjoint_data_out;
            fft_bram_we_b[5] = muladjoint_valid_out;

            instruction_done = fft_done;  // FFT takes the longest
          end

          SIGN_STEP_4: begin
            // FFT: input is BRAM3, also uses BRAM9
            fft_bram_addr_a[3] = fft_bram1_addr_a;
            fft_bram_din_a[3] = fft_bram1_din_a;
            fft_bram_we_a[3] = fft_bram1_we_a;
            fft_bram_addr_b[3] = fft_bram1_addr_b;
            fft_bram_din_b[3] = fft_bram1_din_b;
            fft_bram_we_b[3] = fft_bram1_we_b;
            fft_bram1_dout_a = fft_bram_dout_a[3];
            fft_bram1_dout_b = fft_bram_dout_b[3];

            fft_bram_addr_a[9] = fft_bram2_addr_a;
            fft_bram_din_a[9] = fft_bram2_din_a;
            fft_bram_we_a[9] = fft_bram2_we_a;
            fft_bram_addr_b[9] = fft_bram2_addr_b;
            fft_bram_din_b[9] = fft_bram2_din_b;
            fft_bram_we_b[9] = fft_bram2_we_b;
            fft_bram2_dout_a = fft_bram_dout_a[9];
            fft_bram2_dout_b = fft_bram_dout_b[9];

            // add BRAM4 and BRAM 5, output is BRAM4
            fft_bram_addr_a[4] = task_addr1;
            fft_bram_addr_a[5] = task_addr1;
            flp_adder1_a = fft_bram_dout_a[4][127:64];
            flp_adder1_b = fft_bram_dout_a[5][127:64];
            flp_adder2_a = fft_bram_dout_a[4][63:0];
            flp_adder2_b = fft_bram_dout_a[5][63:0];
            flp_adder_in_valid = !flp_adder_done;
            flp_adder_address_in = task_addr1;
            fft_bram_addr_b[4] = flp_adder_address_out;
            fft_bram_din_b[4] = {flp_adder1_result, flp_adder2_result};
            fft_bram_we_b[4] = flp_adder_out_valid;

            // copy BRAM 7 to BRAM 6
            fft_bram_addr_a[7] = task_addr1;
            copy_address_in = task_addr1;
            copy_valid_in = !copy_done;
            fft_bram_addr_a[6] = copy_address_out;
            fft_bram_din_a[6] = fft_bram_dout_a[7];
            fft_bram_we_a[6] = copy_valid_out;

            instruction_done = fft_done;  // FFT takes the longest
          end

          SIGN_STEP_5: begin
            // FFT: input is BRAM7, also uses BRAM6
            fft_bram_addr_a[7] = fft_bram1_addr_a;
            fft_bram_din_a[7] = fft_bram1_din_a;
            fft_bram_we_a[7] = fft_bram1_we_a;
            fft_bram_addr_b[7] = fft_bram1_addr_b;
            fft_bram_din_b[7] = fft_bram1_din_b;
            fft_bram_we_b[7] = fft_bram1_we_b;
            fft_bram1_dout_a = fft_bram_dout_a[7];
            fft_bram1_dout_b = fft_bram_dout_b[7];

            fft_bram_addr_a[6] = fft_bram2_addr_a;
            fft_bram_din_a[6] = fft_bram2_din_a;
            fft_bram_we_a[6] = fft_bram2_we_a;
            fft_bram_addr_b[6] = fft_bram2_addr_b;
            fft_bram_din_b[6] = fft_bram2_din_b;
            fft_bram_we_b[6] = fft_bram2_we_b;
            fft_bram2_dout_a = fft_bram_dout_a[6];
            fft_bram2_dout_b = fft_bram_dout_b[6];

            // self muladjoint on BRAM3, output is BRAM9
            fft_bram_addr_a[3] = task_addr1;
            muladjoint_data_a_in = fft_bram_dout_a[3];
            muladjoint_data_b_in = fft_bram_dout_a[3];
            muladjoint_valid_in = !muladjoint_done;
            muladjoint_address_in = task_addr1;
            fft_bram_addr_b[9] = muladjoint_address_out;
            fft_bram_din_b[9] = muladjoint_data_out;
            fft_bram_we_b[9] = muladjoint_valid_out;

            // mul BRAM 1 and BRAM 6, result is written to BRAM 6
            fft_bram_addr_a[1] = task_addr1;
            fft_bram_addr_a[6] = task_addr1;
            mul_a_real = fft_bram_dout_a[1][127:64];
            mul_a_imag = fft_bram_dout_a[1][63:0];
            mul_b_real = fft_bram_dout_a[6][127:64];
            mul_b_imag = fft_bram_dout_a[6][63:0];
            mul_valid_in = !mul_done;
            mul_address_in = task_addr1;
            fft_bram_addr_b[6] = mul_address_out;
            fft_bram_din_b[6] = {mul_result_real, mul_result_imag};
            fft_bram_we_b[6] =mul_valid_out;

            instruction_done = fft_done;  // FFT takes the longest
          end

          SIGN_STEP_6: begin

            // self muladjoint on BRAM2, output is BRAM8
            fft_bram_addr_a[2] = task_addr1;
            muladjoint_data_a_in = fft_bram_dout_a[2];
            muladjoint_data_b_in = fft_bram_dout_a[2];
            muladjoint_valid_in = !muladjoint_done;
            muladjoint_address_in = task_addr1;
            fft_bram_addr_b[8] = muladjoint_address_out;
            fft_bram_din_b[8] = muladjoint_data_out;
            fft_bram_we_b[8] = muladjoint_valid_out;

            // mul BRAM 3 and BRAM 7, result is written to BRAM 7
            fft_bram_addr_a[3] = task_addr1;
            fft_bram_addr_a[7] = task_addr1;
            mul_a_real = fft_bram_dout_a[3][127:64];
            mul_a_imag = fft_bram_dout_a[3][63:0];
            mul_b_real = fft_bram_dout_a[7][127:64];
            mul_b_imag = fft_bram_dout_a[7][63:0];
            mul_valid_in = !mul_done;
            mul_address_in = task_addr1;
            fft_bram_addr_b[7] = mul_address_out;
            fft_bram_din_b[7] = {mul_result_real, mul_result_imag};
            fft_bram_we_b[7] = mul_valid_out;

            instruction_done = 1'b1;
          end

          SIGN_STEP_7: begin

            // muladjoint on BRAM1 and BRAM3, output is BRAM9
            fft_bram_addr_a[1] = task_addr1;
            fft_bram_addr_a[3] = task_addr1;
            muladjoint_data_a_in = fft_bram_dout_a[1];
            muladjoint_data_b_in = fft_bram_dout_a[3];
            muladjoint_valid_in = !muladjoint_done;
            muladjoint_address_in = task_addr1;
            fft_bram_addr_b[9] = muladjoint_address_out;
            fft_bram_din_b[9] = muladjoint_data_out;
            fft_bram_we_b[9] = muladjoint_valid_out;

            // add BRAM 8 and BRAM 9, result is written to BRAM 8
            fft_bram_addr_a[8] = task_addr1;
            fft_bram_addr_a[9] = task_addr1;
            flp_adder1_a = fft_bram_dout_a[8][127:64];
            flp_adder1_b = fft_bram_dout_a[9][127:64];
            flp_adder2_a = fft_bram_dout_a[8][63:0];
            flp_adder2_b = fft_bram_dout_a[9][63:0];
            flp_adder_in_valid = !flp_adder_done;
            flp_adder_address_in = task_addr1;
            fft_bram_addr_b[8] = flp_adder_address_out;
            fft_bram_din_b[8] = {flp_adder1_result, flp_adder2_result};
            fft_bram_we_b[8] = flp_adder_out_valid;

            // mul BRAM 7 with constant inv(q), result is written to BRAM 7
            fft_bram_addr_a[7] = task_addr1;
            mul_a_real = fft_bram_dout_a[3][127:64];
            mul_a_imag = fft_bram_dout_a[3][63:0];
            mul_b_real = $realtobits(1.0 / 12289.0);
            mul_b_imag = $realtobits(1.0 / 12289.0);
            mul_valid_in = !mul_done;
            mul_address_in = task_addr1;
            fft_bram_addr_b[7] = mul_address_out;
            fft_bram_din_b[7] = {mul_result_real, mul_result_imag};
            fft_bram_we_b[7] = mul_valid_out;

            instruction_done = 1'b1;
          end

          SIGN_STEP_8: begin

            // muladjoint on BRAM0 and BRAM2, output is BRAM5
            fft_bram_addr_a[0] = task_addr1;
            fft_bram_addr_a[2] = task_addr1;
            muladjoint_data_a_in = fft_bram_dout_a[0];
            muladjoint_data_b_in = fft_bram_dout_a[2];
            muladjoint_valid_in = !muladjoint_done;
            muladjoint_address_in = task_addr1;
            fft_bram_addr_b[5] = muladjoint_address_out;
            fft_bram_din_b[5] = muladjoint_data_out;
            fft_bram_we_b[5] = muladjoint_valid_out;

            // mul BRAM 6 with constant inv(q), result is written to BRAM 6
            fft_bram_addr_a[6] = task_addr1;
            mul_a_real = fft_bram_dout_a[3][127:64];
            mul_a_imag = fft_bram_dout_a[3][63:0];
            mul_b_real = $realtobits(-1.0 / 12289.0);
            mul_b_imag = $realtobits(-1.0 / 12289.0);
            mul_valid_in = !mul_done;
            mul_address_in = task_addr1;
            fft_bram_addr_b[6] = mul_address_out;
            fft_bram_din_b[6] = {mul_result_real, mul_result_imag};
            fft_bram_we_b[6] = mul_valid_out;

            instruction_done = 1'b1;
          end

          SIGN_STEP_9: begin

            // add BRAM 5 and BRAM 9, result is written to BRAM 5
            fft_bram_addr_a[5] = task_addr1;
            fft_bram_addr_a[9] = task_addr1;
            flp_adder1_a = fft_bram_dout_a[5][127:64];
            flp_adder1_b = fft_bram_dout_a[9][127:64];
            flp_adder2_a = fft_bram_dout_a[5][63:0];
            flp_adder2_b = fft_bram_dout_a[9][63:0];
            flp_adder_in_valid = !flp_adder_done;
            flp_adder_address_in = task_addr1;
            fft_bram_addr_b[5] = flp_adder_address_out;
            fft_bram_din_b[5] = {flp_adder1_result, flp_adder2_result};
            fft_bram_we_b[5] =flp_adder_out_valid;

            instruction_done = 1'b1;
          end

          default: begin
          end
        endcase
      end

      BRAM_RW: begin
        if(task_params[3]) begin  // BRAM write

          if(task_params[2]) begin  // Run through int_to_double before writing
            int_to_double_data_in = bram_din;
            int_to_double_address_in_override = task_addr1; // Override: signals will not be delayed, since we don't have the delay of reading from BRAM
            int_to_double_valid_in_override = 1'b1;

            // Wait for int_to_double to finish
            if(int_to_double_valid_out) begin
              fft_bram_addr_a[task_bank1] = int_to_double_address_out;
              fft_bram_din_a[task_bank1] = int_to_double_data_out;
              fft_bram_we_a[task_bank1] = 1'b1;
            end
          end
          else begin  // Write directly to BRAM
            fft_bram_addr_a[task_bank1] = task_addr1;
            fft_bram_din_a[task_bank1] = bram_din;
            fft_bram_we_a[task_bank1] = 1'b1;
          end
        end
        else begin // BRAM read
          fft_bram_addr_a[task_bank1] = task_addr1;
          bram_dout = fft_bram_dout_a[task_bank1];
        end
        instruction_done = 1'b1;
      end

      INT_TO_DOUBLE: begin
        fft_bram_addr_a[task_bank1] = task_addr1;
        int_to_double_address_in = task_addr1;
        int_to_double_data_in = fft_bram_dout_a[task_bank1];

        // Write output to BRAM
        if(int_to_double_valid_out) begin
          fft_bram_addr_b[task_bank2] = int_to_double_address_out;
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

      SUB_NORM_SQ: begin
        // Reads the following data from BRAMs:
        // - data from hash_to_point: task_bram1[task_addr1] - 2 coefficients per memory line
        // - data from INTT: task_bram2[task_addr2] and task_bram2[task_addr2+N/2] - 1 coefficient per memory line
        // - data from decompress: task_params[2:0][task_addr1] - 2 coefficients per memory line

        fft_bram_addr_a[task_bank1] = task_addr1; // Data from hash_to_point
        ntt_bram_addr_a[task_bank2] = task_addr2; // Data from INTT
        ntt_bram_addr_b[task_bank2] = task_addr2 + N/2; // Data from INTT
        fft_bram_addr_b[task_params[2:0]] = task_addr1; // Data from decompress

        sub_normalize_squared_norm_a[0] = fft_bram_dout_a[task_bank1][64+14:64];
        sub_normalize_squared_norm_a[1] = fft_bram_dout_a[task_bank1][14:0];
        sub_normalize_squared_norm_b[0] = ntt_bram_dout_a[task_bank2];
        sub_normalize_squared_norm_b[1] = ntt_bram_dout_b[task_bank2];
        sub_normalize_squared_norm_c[0] = fft_bram_dout_b[task_params[2:0]][64+14:64];
        sub_normalize_squared_norm_c[1] = fft_bram_dout_b[task_params[2:0]][14:0];

        sub_normalize_squared_norm_valid = 1'b1;
        sub_normalize_squared_norm_last = task_params[3];

        instruction_done = sub_normalize_squared_norm_accept == 1'b1 || sub_normalize_squared_norm_reject == 1'b1;


        // Write result
        if(sub_normalize_squared_norm_accept == 1'b1 && sub_normalize_squared_norm_reject == 1'b0) begin
          fft_bram_addr_a[0] = 0;
          fft_bram_din_a[0] = 128'b0;
          fft_bram_we_a[0] = 1'b1;
        end
        else if (sub_normalize_squared_norm_accept == 1'b0 && sub_normalize_squared_norm_reject == 1'b1) begin
          fft_bram_addr_a[0] = 0;
          fft_bram_din_a[0] = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
          fft_bram_we_a[0] = 1'b1;
        end
        else begin
          fft_bram_we_a[0] = 1'b0;
        end
      end

      default: begin

      end

    endcase
  end

endmodule
