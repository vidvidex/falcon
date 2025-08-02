`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Control unit that run submodules based on received instructions
//
// Multiple modules can be ran at the same time by setting multiple bits corresponding to the module in the instruction.
// If none of the module bits are set it is treated as a NOP, with the side effect of setting WE for all BRAMs to 0.
//
//////////////////////////////////////////////////////////////////////////////////


module control_unit#(
    parameter int N = 1024
  )(
    input logic clk,
    input logic rst_n,

    input logic [127:0] instruction,
    output logic instruction_done,

    input logic [`BRAM_DATA_WIDTH-1:0] bram_din, // Data to write to BRAM
    output logic [`BRAM_DATA_WIDTH-1:0] bram_dout // Data read from BRAM
  );

  localparam int BRAM1024_COUNT = 4; // Number of 1024x15 BRAM banks
  localparam int BRAM2048_COUNT = 2; // Number of 2048x15 BRAM banks
  localparam int BRAM5632_COUNT = 1; // Number of 5632x15 BRAM banks
  localparam int BRAM_BANK_COUNT = BRAM1024_COUNT + BRAM2048_COUNT + BRAM5632_COUNT;

  // typedef enum logic [12:0] {
  //           FFT_IFFT      = 4'b0010, // Input is task_bram1, output is task_bram1 or task_bram2 (depends on N, see fft module header for more info). task_params[3] sets FFT (0) or IFFT (1) mode.
  //           HTP_DECMP_NTT = 4'b0011, // hash_to_point, decompress, ntt. Used in verify. NTT takes the longest, so we use it's done signal to know when everything is done
  //           NTT_INTT      = 4'b1011, // Input is bank1, which should be 0-5, output is bank2, which should be 6 or 7. task_params[3] sets NTT (0) or INTT (1) mode.
  //           MOD_MULT_Q    = 4'b1100, // Inputs are always BRAM 6 and BRAM 7 (because those two are the only ones with the expected shape - 1024x128). Output is task_bram2. Module reads from both input BRAMs at address addr1 and addr2 and writes the output to addr1
  //           SUB_NORM_SQ   = 4'b1101, // Reads from BRAMs bank1[addr1] (data from hash_to_point), bank2[addr2], bank2[addr2+N/2] (data from INTT) and task_params[2:0][addr1] (data from decompress). Output is BRAM0 at address 0 (accept/reject), 0x000...00 = accept, 0xfff...ff = reject
  //         } opcode_t;

  logic debug_BRAM_READ;
  logic debug_BRAM_WRITE;
  logic debug_COPY;
  logic debug_HASH_TO_POINT;
  logic debug_INT_TO_DOUBLE;
  logic debug_FFT_IFFT;
  logic debug_NTT_INTT;
  logic debug_MUL;
  logic debug_MUL_CONST;
  logic debug_SPLIT_MERGE;
  logic debug_MOD_MULT_Q;
  logic debug_SUB_NORM_SQ;
  logic debug_DECOMPRESS;
  logic debug_COMPRESS;
  logic debug_ADD_SUB;
  always_comb begin
    debug_BRAM_READ = instruction[127-0];
    debug_BRAM_WRITE = instruction[127-1];
    debug_COPY = instruction[127-2];
    debug_HASH_TO_POINT = instruction[127-3];
    debug_INT_TO_DOUBLE = instruction[127-4];
    debug_FFT_IFFT = instruction[127-5];
    debug_NTT_INTT = instruction[127-6];
    debug_MUL = instruction[127-7];
    debug_MUL_CONST = instruction[127-8];
    debug_SPLIT_MERGE = instruction[127-9];
    debug_MOD_MULT_Q = instruction[127-10];
    debug_SUB_NORM_SQ = instruction[127-11];
    debug_DECOMPRESS = instruction[127-12];
    debug_COMPRESS = instruction[127-13];
    debug_ADD_SUB = instruction[127-14];
  end

  logic [15:0] modules_running;
  logic [2:0] bank1;
  logic [2:0] bank2;
  logic [12:0] addr1;
  logic [12:0] addr2;

  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_a [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_dout_a [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_a [BRAM_BANK_COUNT];
  logic bram_we_a [BRAM_BANK_COUNT];
  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_b [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_b [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_dout_b [BRAM_BANK_COUNT];
  logic bram_we_b [BRAM_BANK_COUNT];

  logic [`BRAM2048_ADDR_WIDTH-1:0] bram2048_addr_a [BRAM2048_COUNT];
  logic [`BRAM2048_ADDR_WIDTH-1:0] bram2048_addr_b [BRAM2048_COUNT];
  genvar i_bram2048;
  generate
    for (i_bram2048 = 0; i_bram2048 < BRAM2048_COUNT; i_bram2048++) begin : bram2048_bank
      bram_2048x128 bram_2048x128_inst (
                      .addra(bram2048_addr_a[i_bram2048]),
                      .clka(clk),
                      .dina(bram_din_a[i_bram2048]),
                      .douta(bram_dout_a[i_bram2048]),
                      .wea(bram_we_a[i_bram2048]),

                      .addrb(bram2048_addr_b[i_bram2048]),
                      .clkb(clk),
                      .dinb(bram_din_b[i_bram2048]),
                      .doutb(bram_dout_b[i_bram2048]),
                      .web(bram_we_b[i_bram2048])
                    );
    end
  endgenerate

  logic [`BRAM1024_ADDR_WIDTH-1:0] bram1024_addr_a [BRAM1024_COUNT];
  logic [`BRAM1024_ADDR_WIDTH-1:0] bram1024_addr_b [BRAM1024_COUNT];
  genvar i_bram1024;
  generate
    for (i_bram1024 = BRAM2048_COUNT; i_bram1024 < BRAM1024_COUNT + BRAM2048_COUNT; i_bram1024++) begin : bram1024_bank
      bram_1024x128 bram_1024x128_inst (
                      .addra(bram1024_addr_a[i_bram1024-BRAM2048_COUNT]),
                      .clka(clk),
                      .dina(bram_din_a[i_bram1024]),
                      .douta(bram_dout_a[i_bram1024]),
                      .wea(bram_we_a[i_bram1024]),

                      .addrb(bram1024_addr_b[i_bram1024-BRAM2048_COUNT]),
                      .clkb(clk),
                      .dinb(bram_din_b[i_bram1024]),
                      .doutb(bram_dout_b[i_bram1024]),
                      .web(bram_we_b[i_bram1024])
                    );
    end
  endgenerate

  genvar i_bram5632;
  generate
    for (i_bram5632 = BRAM1024_COUNT + BRAM2048_COUNT; i_bram5632 < BRAM1024_COUNT + BRAM2048_COUNT + BRAM5632_COUNT; i_bram5632++) begin : bram5632_bank
      bram_5632x128 bram_5632x128_inst (
                      .addra(bram_addr_a[i_bram5632]),
                      .clka(clk),
                      .dina(bram_din_a[i_bram5632]),
                      .douta(bram_dout_a[i_bram5632]),
                      .wea(bram_we_a[i_bram5632]),

                      .addrb(bram_addr_b[i_bram5632]),
                      .clkb(clk),
                      .dinb(bram_din_b[i_bram5632]),
                      .doutb(bram_dout_b[i_bram5632]),
                      .web(bram_we_b[i_bram5632])
                    );
    end
  endgenerate

  // Route from bram signals with widths specific to each BRAM type to the common bram signals
  always_comb begin
    for (int i = 0; i < BRAM2048_COUNT; i++) begin
      bram2048_addr_a[i] = bram_addr_a[i][`BRAM2048_ADDR_WIDTH-1:0];
      bram2048_addr_b[i] = bram_addr_b[i][`BRAM2048_ADDR_WIDTH-1:0];
    end
    for (int i = 0; i < BRAM1024_COUNT; i++) begin
      bram1024_addr_a[i] = bram_addr_a[i+BRAM2048_COUNT][`BRAM1024_ADDR_WIDTH-1:0];
      bram1024_addr_b[i] = bram_addr_b[i+BRAM2048_COUNT][`BRAM1024_ADDR_WIDTH-1:0];
    end
  end


  logic htp_start, htp_start_i;
  logic [`BRAM_ADDR_WIDTH-1:0] htp_input_bram_addr;
  logic [`BRAM_DATA_WIDTH-1:0] htp_input_bram_data;
  logic [`BRAM_ADDR_WIDTH-1:0] htp_output_bram1_addr, htp_output_bram2_addr;
  logic [`BRAM_DATA_WIDTH-1:0] htp_output_bram1_data, htp_output_bram2_data;
  logic htp_output_bram1_we;
  logic htp_done, htp_done_delayed;
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
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) htp_done_delay(.clk(clk), .in(htp_done), .out(htp_done_delayed));

  logic [`BRAM_DATA_WIDTH-1:0] int_to_double_data_in;
  logic [`BRAM_ADDR_WIDTH-1:0] int_to_double_address_in, int_to_double_address_in_delayed;
  logic int_to_double_valid_in, int_to_double_valid_in_delayed;
  logic [`BRAM_DATA_WIDTH-1:0] int_to_double_data_out;
  logic [`BRAM_ADDR_WIDTH-1:0] int_to_double_address_out;
  logic int_to_double_valid_out;
  int_to_double int_to_double (
                  .clk(clk),
                  .data_in(int_to_double_data_in),
                  .valid_in(int_to_double_valid_in_delayed),
                  .address_in(int_to_double_address_in_delayed),
                  .data_out(int_to_double_data_out),
                  .valid_out(int_to_double_valid_out),
                  .address_out(int_to_double_address_out)
                );
  delay_register #(.BITWIDTH(`BRAM_ADDR_WIDTH), .CYCLE_COUNT(2)) int_to_double_address_in_delay(.clk(clk), .in(int_to_double_address_in), .out(int_to_double_address_in_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) int_to_double_valid_in_delay(.clk(clk), .in(int_to_double_valid_in), .out(int_to_double_valid_in_delayed));

  // logic [63:0] btf_a_in_real, btf_a_in_imag, btf_b_in_real, btf_b_in_imag;
  // logic [63:0] btf_a_out_real, btf_a_out_imag, btf_b_out_real, btf_b_out_imag;
  // logic btf_mode;
  // logic signed [4:0] btf_scale_factor;
  // logic [9:0] btf_tw_addr;
  // logic btf_valid_in, btf_valid_out;
  // fft_butterfly fft_butterfly(
  //                 .clk(clk),
  //                 .mode(btf_mode),
  //                 .valid_in(btf_valid_in),

  //                 .a_in_real(btf_a_in_real),
  //                 .a_in_imag(btf_a_in_imag),
  //                 .b_in_real(btf_b_in_real),
  //                 .b_in_imag(btf_b_in_imag),

  //                 .tw_addr(btf_tw_addr),

  //                 .scale_factor(btf_scale_factor),

  //                 .a_out_real(btf_a_out_real),
  //                 .a_out_imag(btf_a_out_imag),
  //                 .b_out_real(btf_b_out_real),
  //                 .b_out_imag(btf_b_out_imag),

  //                 .valid_out(btf_valid_out)
  //               );

  // logic fft_mode, fft_start, fft_start_i, fft_done;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] fft_bram1_addr_a, fft_bram1_addr_b;
  // logic [`BRAM_DATA_WIDTH-1:0] fft_bram1_din_a, fft_bram1_din_b;
  // logic [`BRAM_DATA_WIDTH-1:0] fft_bram1_dout_a, fft_bram1_dout_b;
  // logic fft_bram1_we_a, fft_bram1_we_b;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] fft_bram2_addr_a, fft_bram2_addr_b;
  // logic [`BRAM_DATA_WIDTH-1:0] fft_bram2_din_a, fft_bram2_din_b;
  // logic [`BRAM_DATA_WIDTH-1:0] fft_bram2_dout_a, fft_bram2_dout_b;
  // logic fft_bram2_we_a, fft_bram2_we_b;
  // fft #(
  //       .N(N)
  //     )fft(
  //       .clk(clk),
  //       .rst(!rst_n || instruction_done), // Reset on instruction_done so it's ready for the next instruction
  //       .mode(fft_mode),
  //       .start(fft_start && !fft_start_i),

  //       .bram1_addr_a(fft_bram1_addr_a),
  //       .bram1_din_a(fft_bram1_din_a),
  //       .bram1_dout_a(fft_bram1_dout_a),
  //       .bram1_we_a(fft_bram1_we_a),
  //       .bram1_addr_b(fft_bram1_addr_b),
  //       .bram1_din_b(fft_bram1_din_b),
  //       .bram1_dout_b(fft_bram1_dout_b),
  //       .bram1_we_b(fft_bram1_we_b),

  //       .bram2_addr_a(fft_bram2_addr_a),
  //       .bram2_din_a(fft_bram2_din_a),
  //       .bram2_dout_a(fft_bram2_dout_a),
  //       .bram2_we_a(fft_bram2_we_a),
  //       .bram2_addr_b(fft_bram2_addr_b),
  //       .bram2_din_b(fft_bram2_din_b),
  //       .bram2_dout_b(fft_bram2_dout_b),
  //       .bram2_we_b(fft_bram2_we_b),

  //       .done(fft_done),

  //       .btf_mode(btf_mode),
  //       .btf_valid_in(btf_valid_in),
  //       .btf_a_in_real(btf_a_in_real),
  //       .btf_a_in_imag(btf_a_in_imag),
  //       .btf_b_in_real(btf_b_in_real),
  //       .btf_b_in_imag(btf_b_in_imag),
  //       .btf_scale_factor(btf_scale_factor),
  //       .btf_tw_addr(btf_tw_addr),
  //       .btf_a_out_real(btf_a_out_real),
  //       .btf_a_out_imag(btf_a_out_imag),
  //       .btf_b_out_real(btf_b_out_real),
  //       .btf_b_out_imag(btf_b_out_imag),
  //       .btf_valid_out(btf_valid_out)
  //     );

  // logic decompress_start, decompress_start_i;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] decompress_input_bram_addr;
  // logic [`BRAM_DATA_WIDTH-1:0] decompress_input_bram_data;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] decompress_output_bram1_addr;
  // logic [`BRAM_DATA_WIDTH-1:0] decompress_output_bram1_data;
  // logic decompress_output_bram1_we;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] decompress_output_bram2_addr;
  // logic [`BRAM_DATA_WIDTH-1:0] decompress_output_bram2_data;
  // logic decompress_signature_error, decompress_done;
  // decompress #(
  //              .N(N)
  //            )
  //            decompress (
  //              .clk(clk),
  //              .rst_n(rst_n),
  //              .start(decompress_start && !decompress_start_i),

  //              .input_bram_addr(decompress_input_bram_addr),
  //              .input_bram_data(decompress_input_bram_data),

  //              .output_bram1_addr(decompress_output_bram1_addr),
  //              .output_bram1_data(decompress_output_bram1_data),
  //              .output_bram1_we(decompress_output_bram1_we),

  //              .output_bram2_addr(decompress_output_bram2_addr),
  //              .output_bram2_data(decompress_output_bram2_data),

  //              .signature_error(decompress_signature_error),
  //              .done(decompress_done)
  //            );


  // logic ntt_start, ntt_start_i;
  // logic ntt_mode;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] ntt_input_bram_addr1;
  // logic [`BRAM_DATA_WIDTH-1:0] ntt_input_bram_data1;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] ntt_input_bram_addr2;
  // logic [`BRAM_DATA_WIDTH-1:0] ntt_input_bram_data2;
  // logic [`NTT_BRAM_ADDR_WIDTH-1:0] ntt_output_bram_addr1;
  // logic [`NTT_BRAM_DATA_WIDTH-1:0] ntt_output_bram_data1;
  // logic ntt_output_bram_we1;
  // logic [`NTT_BRAM_ADDR_WIDTH-1:0] ntt_output_bram_addr2;
  // logic [`NTT_BRAM_DATA_WIDTH-1:0] ntt_output_bram_data2;
  // logic ntt_output_bram_we2;
  // logic ntt_done;
  // ntt #(
  //       .N(N)
  //     )ntt(
  //       .clk(clk),
  //       .rst_n(rst_n),
  //       .start(ntt_start && !ntt_start_i),
  //       .mode(ntt_mode),

  //       .input_bram_addr1(ntt_input_bram_addr1),
  //       .input_bram_data1(ntt_input_bram_data1),
  //       .input_bram_addr2(ntt_input_bram_addr2),
  //       .input_bram_data2(ntt_input_bram_data2),

  //       .output_bram_addr1(ntt_output_bram_addr1),
  //       .output_bram_data1(ntt_output_bram_data1),
  //       .output_bram_we1(ntt_output_bram_we1),
  //       .output_bram_addr2(ntt_output_bram_addr2),
  //       .output_bram_data2(ntt_output_bram_data2),
  //       .output_bram_we2(ntt_output_bram_we2),

  //       .done(ntt_done)
  //     );

  // parameter int MOD_MULT_PARALLEL_OPS_COUNT = 2;
  // logic [`NTT_BRAM_DATA_WIDTH-1:0] mod_mult_a [MOD_MULT_PARALLEL_OPS_COUNT], mod_mult_b [MOD_MULT_PARALLEL_OPS_COUNT];
  // logic mod_mult_valid_in, mod_mult_valid_in_delayed;
  // logic [`NTT_BRAM_DATA_WIDTH-1:0] mod_mult_result [MOD_MULT_PARALLEL_OPS_COUNT];
  // logic mod_mult_valid_out;
  // mod_mult #(
  //            .N(N),
  //            .PARALLEL_OPS_COUNT(MOD_MULT_PARALLEL_OPS_COUNT)
  //          )mod_mult (
  //            .clk(clk),
  //            .rst_n(rst_n),
  //            .a(mod_mult_a),
  //            .b(mod_mult_b),
  //            .valid_in(mod_mult_valid_in_delayed),
  //            .result(mod_mult_result),
  //            .valid_out(mod_mult_valid_out)
  //          );
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] mod_mult_write_addr;  // Where to write the output of mod_mult
  // delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(7)) mod_mult_write_addr_delay(.clk(clk), .in(addr1), .out(mod_mult_write_addr));
  // delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) mod_mult_valid_in_delay(.clk(clk), .in(mod_mult_valid_in), .out(mod_mult_valid_in_delayed));

  // parameter int SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT = 2;
  // logic [`NTT_BRAM_DATA_WIDTH-1:0] sub_normalize_squared_norm_a [SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT], sub_normalize_squared_norm_b [SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT], sub_normalize_squared_norm_c [SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT];
  // logic sub_normalize_squared_norm_valid, sub_normalize_squared_norm_valid_delayed;
  // logic sub_normalize_squared_norm_last, sub_normalize_squared_norm_last_delayed;
  // logic sub_normalize_squared_norm_accept, sub_normalize_squared_norm_reject;
  // sub_normalize_squared_norm #(
  //                              .N(N),
  //                              .PARALLEL_OPS_COUNT(SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT)
  //                            )sub_normalize_squared_norm (
  //                              .clk(clk),
  //                              .rst_n(rst_n),
  //                              .a(sub_normalize_squared_norm_a),
  //                              .b(sub_normalize_squared_norm_b),
  //                              .c(sub_normalize_squared_norm_c),
  //                              .valid(sub_normalize_squared_norm_valid_delayed),
  //                              .last(sub_normalize_squared_norm_last_delayed),
  //                              .accept(sub_normalize_squared_norm_accept),
  //                              .reject(sub_normalize_squared_norm_reject)
  //                            );
  // delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) sub_normalize_squared_norm_valid_delay(.clk(clk), .in(sub_normalize_squared_norm_valid), .out(sub_normalize_squared_norm_valid_delayed));
  // delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) sub_normalize_squared_norm_last_delay(.clk(clk), .in(sub_normalize_squared_norm_last), .out(sub_normalize_squared_norm_last_delayed));

  // parameter int fp_NEGATE_PARALLEL_OPS_COUNT = 2;
  // logic [63:0] fp_negate_double_in [fp_NEGATE_PARALLEL_OPS_COUNT];
  // logic fp_negate_valid_in, fp_negate_valid_in_delayed;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] fp_negate_address_in, fp_negate_address_in_delayed;
  // logic [63:0] fp_negate_double_out [fp_NEGATE_PARALLEL_OPS_COUNT];
  // logic fp_negate_valid_out;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] fp_negate_address_out;
  // logic fp_negate_done;
  // fp_negate #(
  //             .PARALLEL_OPS_COUNT(fp_NEGATE_PARALLEL_OPS_COUNT)
  //           )fp_negate (
  //             .clk(clk),
  //             .double_in(fp_negate_double_in),
  //             .valid_in(fp_negate_valid_in_delayed),
  //             .address_in(fp_negate_address_in_delayed),
  //             .double_out(fp_negate_double_out),
  //             .valid_out(fp_negate_valid_out),
  //             .address_out(fp_negate_address_out)
  //           );
  // delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(2)) fp_negate_address_in_delay(.clk(clk), .in(fp_negate_address_in), .out(fp_negate_address_in_delayed));
  // delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) fp_negate_valid_in_delay(.clk(clk), .in(fp_negate_valid_in), .out(fp_negate_valid_in_delayed));

  // logic [`BRAM_DATA_WIDTH-1:0] mul_adjoint_data_a_in, mul_adjoint_data_b_in;
  // logic mul_adjoint_valid_in, mul_adjoint_valid_in_delayed;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] mul_adjoint_address_in, mul_adjoint_address_in_delayed;
  // logic [`BRAM_DATA_WIDTH-1:0] mul_adjoint_data_out;
  // logic mul_adjoint_valid_out;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] mul_adjoint_address_out;
  // logic mul_adjoint_done;
  // mul_adjoint mul_adjoint (
  //               .clk(clk),
  //               .a_in(mul_adjoint_data_a_in),
  //               .b_in(mul_adjoint_data_b_in),
  //               .valid_in(mul_adjoint_valid_in_delayed),
  //               .address_in(mul_adjoint_address_in_delayed),
  //               .data_out(mul_adjoint_data_out),
  //               .valid_out(mul_adjoint_valid_out),
  //               .address_out(mul_adjoint_address_out)
  //             );
  // delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(2)) mul_adjoint_address_in_delay(.clk(clk), .in(mul_adjoint_address_in), .out(mul_adjoint_address_in_delayed));
  // delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) mul_adjoint_valid_in_delay(.clk(clk), .in(mul_adjoint_valid_in), .out(mul_adjoint_valid_in_delayed));

  // // FLP adder can only add two 64 doubles at a time, so we use two instances of it to add 4 doubles at a time.
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] fp_adder_address_in;
  // logic fp_adder_valid_in, fp_adder_valid_in_delayed;
  // logic [63:0] fp_adder1_a, fp_adder1_b;
  // logic [63:0] fp_adder2_a, fp_adder2_b;
  // logic [63:0] fp_adder1_result;
  // logic [63:0] fp_adder2_result;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] fp_adder_address_out;
  // logic fp_adder_valid_out;
  // logic fp_adder_done;
  // fp_adder #(
  //            .DO_SUBSTRACTION(0)  // 0 for addition, 1 for subtraction
  //          ) fp_adder1(
  //            .clk(clk),
  //            .valid_in(fp_adder_valid_in_delayed),
  //            .a(fp_adder1_a),
  //            .b(fp_adder1_b),
  //            .result(fp_adder1_result),
  //            .valid_out(fp_adder_valid_out)
  //          );
  // fp_adder #(
  //            .DO_SUBSTRACTION(0)  // 0 for addition, 1 for subtraction
  //          ) fp_adder2(
  //            .clk(clk),
  //            .valid_in(fp_adder_valid_in_delayed),
  //            .a(fp_adder2_a),
  //            .b(fp_adder2_b),
  //            .result(fp_adder2_result),
  //            .valid_out()
  //          );
  // delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) fp_adder_valid_in_delay(.clk(clk), .in(fp_adder_valid_in), .out(fp_adder_valid_in_delayed));
  // delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(9)) fp_adder1_address_in_delay(.clk(clk), .in(fp_adder_address_in), .out(fp_adder_address_out));

  // // FLP multiplier can only multiply two 64 doubles at a time, so we use two instances of it to multiply 4 doubles at a time.
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] fp_mul_address_in;
  // logic fp_mul_valid_in, fp_mul_valid_in_delayed;
  // logic [63:0] fp_mul1_a, fp_mul1_b;
  // logic [63:0] fp_mul2_a, fp_mul2_b;
  // logic [63:0] fp_mul1_result;
  // logic [63:0] fp_mul2_result;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] fp_mul_address_out;
  // logic fp_mul_valid_out;
  // logic fp_mul_done;
  // fp_multiplier fp_multiplier1(
  //                 .clk(clk),
  //                 .valid_in(fp_mul_valid_in_delayed),
  //                 .a(fp_mul1_a),
  //                 .b(fp_mul1_b),
  //                 .scale_factor(5'b0),
  //                 .result(fp_mul1_result),
  //                 .valid_out(fp_mul_valid_out)
  //               );
  // fp_multiplier fp_multiplier2(
  //                 .clk(clk),
  //                 .valid_in(fp_mul_valid_in_delayed),
  //                 .a(fp_mul2_a),
  //                 .b(fp_mul2_b),
  //                 .scale_factor(5'b0),
  //                 .result(fp_mul2_result),
  //                 .valid_out()
  //               );
  // delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) fp_mul_valid_in_delay(.clk(clk), .in(fp_mul_valid_in), .out(fp_mul_valid_in_delayed));
  // delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(9)) fp_mul1_address_in_delay(.clk(clk), .in(fp_mul_address_in), .out(fp_mul_address_out));

  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] copy_address_in;
  // logic copy_valid_in;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] copy_address_out;
  // logic copy_valid_out;
  // logic copy_done;
  // delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(2)) copy_address_in_delay(.clk(clk), .in(copy_address_in), .out(copy_address_out));
  // delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) copy_valid_in_delay(.clk(clk), .in(copy_valid_in), .out(copy_valid_out));

  // logic [63:0] complex_mul_a_real, complex_mul_a_imag, complex_mul_b_real, complex_mul_b_imag;
  // logic complex_mul_valid_in, complex_mul_valid_in_delayed;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] complex_mul_address_in;
  // logic [63:0] complex_mul_result_real, complex_mul_result_imag;
  // logic complex_mul_valid_out;
  // logic [`FFT_BRAM_ADDR_WIDTH-1:0] complex_mul_address_out;
  // logic complex_mul_done;
  // complex_multiplier complex_multiplier(
  //                      .clk(clk),
  //                      .valid_in(complex_mul_valid_in_delayed),
  //                      .a_real(complex_mul_a_real),
  //                      .a_imag(complex_mul_a_imag),
  //                      .b_real(complex_mul_b_real),
  //                      .b_imag(complex_mul_b_imag),
  //                      .scale_factor(5'b0),
  //                      .a_x_b_real(complex_mul_result_real),
  //                      .a_x_b_imag(complex_mul_result_imag),
  //                      .valid_out(complex_mul_valid_out)
  //                    );
  // delay_register #(.BITWIDTH(`FFT_BRAM_ADDR_WIDTH), .CYCLE_COUNT(16)) complex_mul_address_in_delay(.clk(clk), .in(complex_mul_address_in), .out(complex_mul_address_out));
  // delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) complex_mul_valid_in_delay(.clk(clk), .in(complex_mul_valid_in), .out(complex_mul_valid_in_delayed));

  always_ff @(posedge clk) begin

    bank1 <= instruction[2:0];
    bank2 <= instruction[5:3];
    addr1 <= instruction[18:6];
    addr2 <= instruction[31:19];

    if (!rst_n) begin

      modules_running <= 1'b0;

      htp_start <= 1'b0;
      htp_start_i <= 1'b0;

      // fft_start <= 1'b0;
      // fft_start_i <= 1'b0;

      // decompress_start <= 1'b0;
      // decompress_start_i <= 1'b0;

      // ntt_start <= 1'b0;
      // ntt_start_i <= 1'b0;
    end
    else begin

      htp_start_i <= htp_start;
      // fft_start_i <= fft_start;
      // decompress_start_i <= decompress_start;
      // ntt_start_i <= ntt_start;

      if(instruction[127-0] == 1'b1) begin // BRAM_READ
        // Empty
      end
      if(instruction[127-1] == 1'b1) begin // BRAM_WRITE
        // Empty
      end
      if(instruction[127-2] == 1'b1) begin // COPY

      end
      if(instruction[127-3] == 1'b1) begin // HASH_TO_POINT
        if(htp_done) begin
          modules_running[3] <= 1'b0;
          htp_start <= 1'b0;
        end
        else begin
          modules_running[3] <= 1'b1;
          htp_start <= 1'b1;
        end
      end
      if(instruction[127-4] == 1'b1) begin // INT_TO_DOUBLE
        // Empty
      end
      if(instruction[127-5] == 1'b1) begin // FFT_IFFT

      end
      if(instruction[127-6] == 1'b1) begin // NTT_INTT

      end
      if(instruction[127-7] == 1'b1) begin // MUL

      end
      if(instruction[127-8] == 1'b1) begin // MUL_CONST

      end
      if(instruction[127-9] == 1'b1) begin // SPLIT_MERGE

      end
      if(instruction[127-10] == 1'b1) begin // MOD_MULT_Q

      end
      if(instruction[127-11] == 1'b1) begin // SUB_NORM_SQ

      end
      if(instruction[127-12] == 1'b1) begin // DECOMPRESS

      end
      if(instruction[127-13] == 1'b1) begin // COMPRESS

      end
      if(instruction[127-14] == 1'b1) begin // ADD_SUB

      end


      // case (opcode)
      //   NOP: begin
      //     // htp_start <= 1'b0;
      //     // fft_start <= 1'b0;
      //     // decompress_start <= 1'b0;
      //     // ntt_start <= 1'b0;
      //     // fp_negate_done <= 1'b0;
      //     // mul_adjoint_done <= 1'b0;
      //     // fp_adder_done <= 1'b0;
      //     // fp_mul_done <= 1'b0;
      //     // copy_done <= 1'b0;
      //     // complex_mul_done <= 1'b0;
      //   end

      //   FFT_IFFT: begin
      //     // fft_mode <= task_params[3]; // Set FFT mode based on task parameters
      //     // fft_start <= 1'b1;
      //   end

      //   HTP_DECMP_NTT: begin
      //     // htp_start <= 1'b1;
      //     // decompress_start <= 1'b1;
      //     // ntt_mode <= 1'b0;
      //     // ntt_start <= 1'b1;
      //   end

      //   NTT_INTT: begin
      //     // ntt_mode <= task_params[3]; // Set NTT mode based on task parameters
      //     // ntt_start <= 1'b1;
      //   end

      //   MOD_MULT_Q: begin

      //   end

      //   SUB_NORM_SQ: begin

      //   end

      //   default: begin

      //   end

      // endcase
    end
  end

  always_comb begin

    // If not specified otherwise set WE for all BRAMs to 0
    for(int i = 0; i < BRAM_BANK_COUNT; i++) begin
      bram_we_a[i] = 1'b0;
      bram_we_b[i] = 1'b0;
    end

    instruction_done = 1'b0; // Default to not done
    int_to_double_valid_in = 1'b0;
    // mod_mult_valid_in = 1'b0;
    // sub_normalize_squared_norm_valid = 1'b0;
    // sub_normalize_squared_norm_last = 1'b0;
    // fp_negate_valid_in = 1'b0;
    // mul_adjoint_valid_in = 1'b0;
    // fp_adder_valid_in = 1'b0;
    // fp_mul_valid_in = 1'b0;
    // copy_valid_in = 1'b0;
    // complex_mul_valid_in = 1'b0;

    // // Ensure these signals are not undefined to ensure proper behaviour of the module
    // sub_normalize_squared_norm_a[0] = 0;
    // sub_normalize_squared_norm_a[1] = 0;
    // sub_normalize_squared_norm_b[0] = 0;
    // sub_normalize_squared_norm_b[1] = 0;
    // sub_normalize_squared_norm_c[0] = 0;
    // sub_normalize_squared_norm_c[1] = 0;

    if(instruction[127-0] == 1'b1) begin // BRAM_READ
      bram_addr_a[bank1] = addr1;
      bram_dout = bram_dout_a[bank1];
    end

    if(instruction[127-1] == 1'b1) begin // BRAM_WRITE
      bram_addr_a[bank1] = addr1;
      bram_din_a[bank1] = bram_din;
      bram_we_a[bank1] = 1'b1;
    end

    if(instruction[127-2] == 1'b1) begin // COPY

    end

    if(instruction[127-3] == 1'b1) begin // HASH_TO_POINT
      bram_addr_a[bank1] = htp_input_bram_addr;
      htp_input_bram_data = bram_dout_a[bank1];

      bram_addr_a[bank2] = htp_output_bram1_addr;
      bram_din_a[bank2] = htp_output_bram1_data;
      bram_we_a[bank2] = htp_output_bram1_we;

      bram_addr_b[bank2] = htp_output_bram2_addr;
      htp_output_bram2_data = bram_dout_b[bank2];

      instruction_done = htp_done_delayed;  // Deleayed so that all data is written to BRAM before the instruction is done
    end

    if(instruction[127-4] == 1'b1) begin // INT_TO_DOUBLE
      bram_addr_a[bank1] = addr1;
      int_to_double_address_in = addr1;
      int_to_double_data_in = bram_dout_a[bank1];

      // Write output to BRAM
      if(int_to_double_valid_out) begin
        bram_addr_b[bank2] = int_to_double_address_out;
        bram_din_b[bank2] = int_to_double_data_out;
        bram_we_b[bank2] = 1'b1;
      end

      int_to_double_valid_in = 1'b1;
    end

    if(instruction[127-5] == 1'b1) begin // FFT_IFFT

    end

    if(instruction[127-6] == 1'b1) begin // NTT_INTT

    end

    if(instruction[127-7] == 1'b1) begin // MUL

    end

    if(instruction[127-8] == 1'b1) begin // MUL_CONST

    end

    if(instruction[127-9] == 1'b1) begin // SPLIT_MERGE

    end

    if(instruction[127-10] == 1'b1) begin // MOD_MULT_Q

    end

    if(instruction[127-11] == 1'b1) begin // SUB_NORM_SQ

    end

    if(instruction[127-12] == 1'b1) begin // DECOMPRESS

    end

    if(instruction[127-13] == 1'b1) begin // COMPRESS

    end

    if(instruction[127-14] == 1'b1) begin // ADD_SUB

    end



    // case (opcode)
    //   NOP: begin
    //     // // No operation, do nothing except stop writing to BRAMs
    //     // for(int i = 0; i < FFT_BRAM_BANK_COUNT; i++) begin
    //     //   fft_bram_we_a[i] = 1'b0;
    //     //   fft_bram_we_b[i] = 1'b0;
    //     // end
    //     // for(int i = 0; i < NTT_BRAM_BANK_COUNT; i++) begin
    //     //   ntt_bram_we_a[i] = 1'b0;
    //     //   ntt_bram_we_b[i] = 1'b0;
    //     // end
    //   end

    //   FFT_IFFT: begin
    //     // fft_bram_addr_a[bank1] = fft_bram1_addr_a;
    //     // fft_bram_din_a[bank1] = fft_bram1_din_a;
    //     // fft_bram_we_a[bank1] = fft_bram1_we_a;
    //     // fft_bram_addr_b[bank1] = fft_bram1_addr_b;
    //     // fft_bram_din_b[bank1] = fft_bram1_din_b;
    //     // fft_bram_we_b[bank1] = fft_bram1_we_b;
    //     // fft_bram1_dout_a = fft_bram_dout_a[bank1];
    //     // fft_bram1_dout_b = fft_bram_dout_b[bank1];

    //     // fft_bram_addr_a[bank2] = fft_bram2_addr_a;
    //     // fft_bram_din_a[bank2] = fft_bram2_din_a;
    //     // fft_bram_we_a[bank2] = fft_bram2_we_a;
    //     // fft_bram_addr_b[bank2] = fft_bram2_addr_b;
    //     // fft_bram_din_b[bank2] = fft_bram2_din_b;
    //     // fft_bram_we_b[bank2] = fft_bram2_we_b;
    //     // fft_bram2_dout_a = fft_bram_dout_a[bank2];
    //     // fft_bram2_dout_b = fft_bram_dout_b[bank2];

    //     // instruction_done = fft_done;
    //   end

    //   HTP_DECMP_NTT: begin
    //     // // hash_to_point: input is BRAM0, output is BRAM3
    //     // fft_bram_addr_a[0] = htp_input_bram_addr;
    //     // htp_input_bram_data = fft_bram_dout_a[0];

    //     // fft_bram_addr_a[3] = htp_output_bram1_addr;
    //     // fft_bram_din_a[3] = htp_output_bram1_data;
    //     // fft_bram_we_a[3] = htp_output_bram1_we;

    //     // fft_bram_addr_b[3] = htp_output_bram2_addr;
    //     // htp_output_bram2_data = fft_bram_dout_b[3];

    //     // // decompress: input is BRAM2, output is BRAM5
    //     // fft_bram_addr_a[2] = decompress_input_bram_addr;
    //     // decompress_input_bram_data = fft_bram_dout_a[2];

    //     // fft_bram_addr_a[5] = decompress_output_bram1_addr;
    //     // fft_bram_din_a[5] = decompress_output_bram1_data;
    //     // fft_bram_we_a[5] = decompress_output_bram1_we;

    //     // fft_bram_addr_b[5] = decompress_output_bram2_addr;
    //     // decompress_output_bram2_data = fft_bram_dout_b[5];

    //     // // NTT: input is BRAM1, output is BRAM6 (ntt bram 0)
    //     // fft_bram_addr_a[1] = ntt_input_bram_addr1;
    //     // ntt_input_bram_data1 = fft_bram_dout_a[1];
    //     // fft_bram_addr_b[1] = ntt_input_bram_addr2;
    //     // ntt_input_bram_data2 = fft_bram_dout_b[1];

    //     // ntt_bram_addr_a[0] = ntt_output_bram_addr1;
    //     // ntt_bram_din_a[0] = ntt_output_bram_data1;
    //     // ntt_bram_we_a[0] = ntt_output_bram_we1;
    //     // ntt_bram_addr_b[0] = ntt_output_bram_addr2;
    //     // ntt_bram_din_b[0] = ntt_output_bram_data2;
    //     // ntt_bram_we_b[0] = ntt_output_bram_we2;

    //     // instruction_done = ntt_done;  // NTT takes the longest
    //   end

    //   NTT_INTT: begin
    //     // fft_bram_addr_a[bank1] = ntt_input_bram_addr1;
    //     // ntt_input_bram_data1 = fft_bram_dout_a[bank1];
    //     // fft_bram_addr_b[bank1] = ntt_input_bram_addr2;
    //     // ntt_input_bram_data2 = fft_bram_dout_b[bank1];

    //     // ntt_bram_addr_a[bank2] = ntt_output_bram_addr1;
    //     // ntt_bram_din_a[bank2] = ntt_output_bram_data1;
    //     // ntt_bram_we_a[bank2] = ntt_output_bram_we1;
    //     // ntt_bram_addr_b[bank2] = ntt_output_bram_addr2;
    //     // ntt_bram_din_b[bank2] = ntt_output_bram_data2;
    //     // ntt_bram_we_b[bank2] = ntt_output_bram_we2;

    //     // instruction_done = ntt_done;
    //   end

    //   MOD_MULT_Q: begin
    //     // // From each input BRAM we read at address "addr1" and "addr2"
    //     // ntt_bram_addr_a[0] = addr1;
    //     // ntt_bram_addr_b[0] = addr2;
    //     // ntt_bram_addr_a[1] = addr1;
    //     // ntt_bram_addr_b[1] = addr2;

    //     // mod_mult_a[0] = ntt_bram_dout_a[0];
    //     // mod_mult_a[1] = ntt_bram_dout_b[0];
    //     // mod_mult_b[0] = ntt_bram_dout_a[1];
    //     // mod_mult_b[1] = ntt_bram_dout_b[1];

    //     // mod_mult_valid_in = 1'b1;
    //     // instruction_done = 1'b1;

    //     // if(mod_mult_valid_out) begin
    //     //   fft_bram_addr_a[bank2] = mod_mult_write_addr;
    //     //   fft_bram_din_a[bank2] = {49'b0, mod_mult_result[0], 49'b0, mod_mult_result[1]};
    //     //   fft_bram_we_a[bank2] = 1'b1;
    //     // end
    //   end

    //   SUB_NORM_SQ: begin
    //     // // Reads the following data from BRAMs:
    //     // // - data from hash_to_point: task_bram1[addr1] - 2 coefficients per memory line
    //     // // - data from INTT: task_bram2[addr2] and task_bram2[addr2+N/2] - 1 coefficient per memory line
    //     // // - data from decompress: task_params[2:0][addr1] - 2 coefficients per memory line

    //     // fft_bram_addr_a[bank1] = addr1; // Data from hash_to_point
    //     // ntt_bram_addr_a[bank2] = addr2; // Data from INTT
    //     // ntt_bram_addr_b[bank2] = addr2 + N/2; // Data from INTT
    //     // fft_bram_addr_b[task_params[2:0]] = addr1; // Data from decompress

    //     // sub_normalize_squared_norm_a[0] = fft_bram_dout_a[bank1][64+14:64];
    //     // sub_normalize_squared_norm_a[1] = fft_bram_dout_a[bank1][14:0];
    //     // sub_normalize_squared_norm_b[0] = ntt_bram_dout_a[bank2];
    //     // sub_normalize_squared_norm_b[1] = ntt_bram_dout_b[bank2];
    //     // sub_normalize_squared_norm_c[0] = fft_bram_dout_b[task_params[2:0]][64+14:64];
    //     // sub_normalize_squared_norm_c[1] = fft_bram_dout_b[task_params[2:0]][14:0];

    //     // sub_normalize_squared_norm_valid = 1'b1;
    //     // sub_normalize_squared_norm_last = task_params[3];

    //     // instruction_done = sub_normalize_squared_norm_accept == 1'b1 || sub_normalize_squared_norm_reject == 1'b1;


    //     // // Write result
    //     // if(sub_normalize_squared_norm_accept == 1'b1 && sub_normalize_squared_norm_reject == 1'b0) begin
    //     //   fft_bram_addr_a[0] = 0;
    //     //   fft_bram_din_a[0] = 128'b0;
    //     //   fft_bram_we_a[0] = 1'b1;
    //     // end
    //     // else if (sub_normalize_squared_norm_accept == 1'b0 && sub_normalize_squared_norm_reject == 1'b1) begin
    //     //   fft_bram_addr_a[0] = 0;
    //     //   fft_bram_din_a[0] = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    //     //   fft_bram_we_a[0] = 1'b1;
    //     // end
    //     // else begin
    //     //   fft_bram_we_a[0] = 1'b0;
    //     // end
    //   end

    //   default: begin

    //   end

    // endcase

  end

endmodule
