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

    output logic signature_accepted,
    output logic signature_rejected,

    input logic [`BRAM_DATA_WIDTH-1:0] bram_din, // Data to write to BRAM
    output logic [`BRAM_DATA_WIDTH-1:0] bram_dout, // Data read from BRAM

    // External BRAM interface
    input logic ext_bram_en, // Enable signal for External BRAM interface. When this is high, software has access to the BRAM
    input logic [19:0] ext_bram_addr, // Top 3 bits select BRAM bank, lower 13 bits are address in the bask
    input logic [15:0] ext_bram_we,
    input logic[127:0] ext_bram_din,  // Data to write to BRAM
    output logic [127:0] ext_bram_dout // Data read from BRAM
  );

  localparam int BRAM1024_COUNT = 3; // Number of 1024x128 BRAM banks
  localparam int BRAM2048_COUNT = 2; // Number of 2048x128 BRAM banks
  localparam int BRAM3072_COUNT = 1; // Number of 3072x128 BRAM banks
  localparam int BRAM6144_COUNT = 1; // Number of 6144x128 BRAM banks
  localparam int BRAM_BANK_COUNT = BRAM3072_COUNT + BRAM1024_COUNT + BRAM2048_COUNT + BRAM6144_COUNT;
  localparam int INSTRUCTION_COUNT = 17;

  logic debug_BRAM_READ;
  logic debug_BRAM_WRITE;
  logic debug_COPY;
  logic debug_HASH_TO_POINT;
  logic debug_INT_TO_DOUBLE;
  logic debug_FFT_IFFT;
  logic debug_NTT_INTT;
  logic debug_COMPLEX_MUL;
  logic debug_MUL_CONST;
  logic debug_SPLIT;
  logic debug_MERGE;
  logic debug_MOD_MULT_Q;
  logic debug_SUB_NORM_SQ;
  logic debug_DECOMPRESS;
  logic debug_COMPRESS;
  logic debug_ADD_SUB;
  logic debug_SAMPLERZ;
  always_comb begin
    debug_BRAM_READ = instruction[127-0];
    debug_BRAM_WRITE = instruction[127-1];
    debug_COPY = instruction[127-2];
    debug_HASH_TO_POINT = instruction[127-3];
    debug_INT_TO_DOUBLE = instruction[127-4];
    debug_FFT_IFFT = instruction[127-5];
    debug_NTT_INTT = instruction[127-6];
    debug_COMPLEX_MUL = instruction[127-7];
    debug_MUL_CONST = instruction[127-8];
    debug_SPLIT = instruction[127-9];
    debug_MERGE = instruction[127-10];
    debug_MOD_MULT_Q = instruction[127-11];
    debug_SUB_NORM_SQ = instruction[127-12];
    debug_DECOMPRESS = instruction[127-13];
    debug_COMPRESS = instruction[127-14];
    debug_ADD_SUB = instruction[127-15];
    debug_SAMPLERZ = instruction[127-16];
  end

  logic [2:0] ext_bram_bank;
  logic [`BRAM_ADDR_WIDTH-1:0] ext_local_bram_addr;

  logic [INSTRUCTION_COUNT-1:0] modules_running, modules_running_i;
  logic [2:0] bank1, bank2, bank3, bank4, bank5, bank6;
  logic [12:0] addr1, addr2;

  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_a [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_dout_a [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_a [BRAM_BANK_COUNT];
  logic bram_we_a [BRAM_BANK_COUNT];
  logic [`BRAM_ADDR_WIDTH-1:0] bram_addr_b [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_din_b [BRAM_BANK_COUNT];
  logic [`BRAM_DATA_WIDTH-1:0] bram_dout_b [BRAM_BANK_COUNT];
  logic bram_we_b [BRAM_BANK_COUNT];

  logic [`BRAM3072_ADDR_WIDTH-1:0] bram3072_addr_a [BRAM3072_COUNT];
  logic [`BRAM3072_ADDR_WIDTH-1:0] bram3072_addr_b [BRAM3072_COUNT];

`ifdef DEBUG_BRAMS

  bram0 bram0 (
          .addra(bram3072_addr_a[0]),
          .clka(clk),
          .dina(bram_din_a[0]),
          .douta(bram_dout_a[0]),
          .wea(bram_we_a[0]),

          .addrb(bram3072_addr_b[0]),
          .clkb(clk),
          .dinb(bram_din_b[0]),
          .doutb(bram_dout_b[0]),
          .web(bram_we_b[0])
        );
  genvar i_bram3072;
`else
  generate
    for (i_bram3072 = 0; i_bram3072 < BRAM3072_COUNT; i_bram3072++) begin : bram3072_bank
      bram_3072x128 bram_3072x128_inst (
                      .addra(bram3072_addr_a[i_bram3072]),
                      .clka(clk),
                      .dina(bram_din_a[i_bram3072]),
                      .douta(bram_dout_a[i_bram3072]),
                      .wea(bram_we_a[i_bram3072]),

                      .addrb(bram3072_addr_b[i_bram3072]),
                      .clkb(clk),
                      .dinb(bram_din_b[i_bram3072]),
                      .doutb(bram_dout_b[i_bram3072]),
                      .web(bram_we_b[i_bram3072])
                    );
    end
  endgenerate
`endif


  logic [`BRAM2048_ADDR_WIDTH-1:0] bram2048_addr_a [BRAM2048_COUNT];
  logic [`BRAM2048_ADDR_WIDTH-1:0] bram2048_addr_b [BRAM2048_COUNT];
`ifdef DEBUG_BRAMS

  bram1 bram1 (
          .addra(bram2048_addr_a[0]),
          .clka(clk),
          .dina(bram_din_a[1]),
          .douta(bram_dout_a[1]),
          .wea(bram_we_a[1]),

          .addrb(bram2048_addr_b[0]),
          .clkb(clk),
          .dinb(bram_din_b[1]),
          .doutb(bram_dout_b[1]),
          .web(bram_we_b[1])
        );
  bram2 bram2 (
          .addra(bram2048_addr_a[1]),
          .clka(clk),
          .dina(bram_din_a[2]),
          .douta(bram_dout_a[2]),
          .wea(bram_we_a[2]),

          .addrb(bram2048_addr_b[1]),
          .clkb(clk),
          .dinb(bram_din_b[2]),
          .doutb(bram_dout_b[2]),
          .web(bram_we_b[2])
        );
`else
  genvar i_bram2048;
  generate
    for (i_bram2048 = BRAM3072_COUNT; i_bram2048 < BRAM2048_COUNT + BRAM3072_COUNT; i_bram2048++) begin : bram2048_bank
      bram_2048x128 bram_2048x128_inst (
                      .addra(bram2048_addr_a[i_bram2048-BRAM3072_COUNT]),
                      .clka(clk),
                      .dina(bram_din_a[i_bram2048]),
                      .douta(bram_dout_a[i_bram2048]),
                      .wea(bram_we_a[i_bram2048]),

                      .addrb(bram2048_addr_b[i_bram2048-BRAM3072_COUNT]),
                      .clkb(clk),
                      .dinb(bram_din_b[i_bram2048]),
                      .doutb(bram_dout_b[i_bram2048]),
                      .web(bram_we_b[i_bram2048])
                    );
    end
  endgenerate
`endif

  logic [`BRAM1024_ADDR_WIDTH-1:0] bram1024_addr_a [BRAM1024_COUNT];
  logic [`BRAM1024_ADDR_WIDTH-1:0] bram1024_addr_b [BRAM1024_COUNT];
`ifdef DEBUG_BRAMS

  bram3 bram3 (
          .addra(bram1024_addr_a[0]),
          .clka(clk),
          .dina(bram_din_a[3]),
          .douta(bram_dout_a[3]),
          .wea(bram_we_a[3]),

          .addrb(bram1024_addr_b[0]),
          .clkb(clk),
          .dinb(bram_din_b[3]),
          .doutb(bram_dout_b[3]),
          .web(bram_we_b[3])
        );
  bram4 bram4 (
          .addra(bram1024_addr_a[1]),
          .clka(clk),
          .dina(bram_din_a[4]),
          .douta(bram_dout_a[4]),
          .wea(bram_we_a[4]),

          .addrb(bram1024_addr_b[1]),
          .clkb(clk),
          .dinb(bram_din_b[4]),
          .doutb(bram_dout_b[4]),
          .web(bram_we_b[4])
        );
  bram5 bram5 (
          .addra(bram1024_addr_a[2]),
          .clka(clk),
          .dina(bram_din_a[5]),
          .douta(bram_dout_a[5]),
          .wea(bram_we_a[5]),

          .addrb(bram1024_addr_b[2]),
          .clkb(clk),
          .dinb(bram_din_b[5]),
          .doutb(bram_dout_b[5]),
          .web(bram_we_b[5])
        );
`else
  genvar i_bram1024;
  generate
    for (i_bram1024 = BRAM2048_COUNT+BRAM3072_COUNT; i_bram1024 < BRAM1024_COUNT + BRAM2048_COUNT + BRAM3072_COUNT; i_bram1024++) begin : bram1024_bank
      bram_1024x128 bram_1024x128_inst (
                      .addra(bram1024_addr_a[i_bram1024-BRAM2048_COUNT-BRAM3072_COUNT]),
                      .clka(clk),
                      .dina(bram_din_a[i_bram1024]),
                      .douta(bram_dout_a[i_bram1024]),
                      .wea(bram_we_a[i_bram1024]),

                      .addrb(bram1024_addr_b[i_bram1024-BRAM2048_COUNT-BRAM3072_COUNT]),
                      .clkb(clk),
                      .dinb(bram_din_b[i_bram1024]),
                      .doutb(bram_dout_b[i_bram1024]),
                      .web(bram_we_b[i_bram1024])
                    );
    end
  endgenerate
`endif

`ifdef DEBUG_BRAMS

  bram6 bram6 (
          .addra(bram_addr_a[6]),
          .clka(clk),
          .dina(bram_din_a[6]),
          .douta(bram_dout_a[6]),
          .wea(bram_we_a[6]),

          .addrb(bram_addr_b[6]),
          .clkb(clk),
          .dinb(bram_din_b[6]),
          .doutb(bram_dout_b[6]),
          .web(bram_we_b[6])
        );
`else
  genvar i_bram6144;
  generate
    for (i_bram6144 = BRAM1024_COUNT + BRAM2048_COUNT + BRAM3072_COUNT; i_bram6144 < BRAM1024_COUNT + BRAM2048_COUNT + BRAM3072_COUNT + BRAM6144_COUNT; i_bram6144++) begin : bram6144_bank
      bram_6144x128 bram_6144x128_inst (
                      .addra(bram_addr_a[i_bram6144]),
                      .clka(clk),
                      .dina(bram_din_a[i_bram6144]),
                      .douta(bram_dout_a[i_bram6144]),
                      .wea(bram_we_a[i_bram6144]),

                      .addrb(bram_addr_b[i_bram6144]),
                      .clkb(clk),
                      .dinb(bram_din_b[i_bram6144]),
                      .doutb(bram_dout_b[i_bram6144]),
                      .web(bram_we_b[i_bram6144])
                    );
    end
  endgenerate
`endif

  // Route from bram signals with widths specific to each BRAM type to the common bram signals
  always_comb begin
    for (int i = 0; i < BRAM3072_COUNT; i++) begin
      bram3072_addr_a[i] = bram_addr_a[i][`BRAM3072_ADDR_WIDTH-1:0];
      bram3072_addr_b[i] = bram_addr_b[i][`BRAM3072_ADDR_WIDTH-1:0];
    end
    for (int i = 0; i < BRAM2048_COUNT; i++) begin
      bram2048_addr_a[i] = bram_addr_a[i + BRAM3072_COUNT][`BRAM2048_ADDR_WIDTH-1:0];
      bram2048_addr_b[i] = bram_addr_b[i + BRAM3072_COUNT][`BRAM2048_ADDR_WIDTH-1:0];
    end
    for (int i = 0; i < BRAM1024_COUNT; i++) begin
      bram1024_addr_a[i] = bram_addr_a[i + BRAM2048_COUNT + BRAM3072_COUNT][`BRAM1024_ADDR_WIDTH-1:0];
      bram1024_addr_b[i] = bram_addr_b[i + BRAM2048_COUNT + BRAM3072_COUNT][`BRAM1024_ADDR_WIDTH-1:0];
    end
  end

  always_ff @(posedge clk) begin
    modules_running_i <= modules_running;
  end

  // Instruction done when no modules are running. Alternatively when we're using the debug read/write instructions
  assign instruction_done = modules_running == 0 && modules_running_i != 0 || (instruction[127-0] == 1'b1 || instruction[127-1] == 1'b1);

  logic [$clog2(N):0] pipelined_inst_index;  // Index for pipelined operations (split, merge, add, etc.)
  logic pipelined_inst_done; // Last/done signal for pipelined operations
  logic pipelined_inst_valid;
  logic [$clog2(N):0] element_count;

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
  logic int_to_double_done, int_to_double_done_delayed;
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
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) int_to_double_done_delay(.clk(clk), .in(int_to_double_done), .out(int_to_double_done_delayed));

  logic [63:0] btf_a_in_real, btf_a_in_imag, btf_b_in_real, btf_b_in_imag;
  logic [63:0] btf_a_out_real, btf_a_out_imag, btf_b_out_real, btf_b_out_imag;
  logic btf_mode;
  logic signed [4:0] btf_scale_factor;
  logic [9:0] btf_tw_addr;
  logic btf_valid_in, btf_valid_out;
  fft_butterfly fft_butterfly(
                  .clk(clk),
                  .mode(btf_mode),
                  .valid_in(btf_valid_in),

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

                  .valid_out(btf_valid_out)
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
  logic fft_btf_mode;
  logic [9:0] fft_btf_tw_addr;
  logic fft_btf_valid_in;
  logic signed [4:0] fft_btf_scale_factor;
  logic [63:0] fft_btf_a_in_real, fft_btf_a_in_imag, fft_btf_b_in_real, fft_btf_b_in_imag;
  logic [63:0] fft_btf_a_out_real, fft_btf_a_out_imag, fft_btf_b_out_real, fft_btf_b_out_imag;
  logic fft_btf_valid_out;
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

        .btf_mode(fft_btf_mode),
        .btf_valid_in(fft_btf_valid_in),
        .btf_a_in_real(fft_btf_a_in_real),
        .btf_a_in_imag(fft_btf_a_in_imag),
        .btf_b_in_real(fft_btf_b_in_real),
        .btf_b_in_imag(fft_btf_b_in_imag),
        .btf_scale_factor(fft_btf_scale_factor),
        .btf_tw_addr(fft_btf_tw_addr),
        .btf_a_out_real(fft_btf_a_out_real),
        .btf_a_out_imag(fft_btf_a_out_imag),
        .btf_b_out_real(fft_btf_b_out_real),
        .btf_b_out_imag(fft_btf_b_out_imag),
        .btf_valid_out(fft_btf_valid_out)
      );

  logic split_start, split_start_i;
  logic [$clog2(N):0] split_size;
  logic [`BRAM_ADDR_WIDTH-1:0] split_bram1_addr_a;
  logic [`BRAM_DATA_WIDTH-1:0] split_bram1_dout_a;
  logic [`BRAM_ADDR_WIDTH-1:0] split_bram1_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] split_bram1_dout_b;
  logic [`BRAM_ADDR_WIDTH-1:0] split_bram2_addr_a;
  logic [`BRAM_DATA_WIDTH-1:0] split_bram2_din_a;
  logic split_bram2_we_a;
  logic [`BRAM_ADDR_WIDTH-1:0] split_bram2_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] split_bram2_din_b;
  logic split_bram2_we_b;
  logic split_done;
  logic split_btf_mode;
  logic [9:0] split_btf_tw_addr;
  logic split_btf_valid_in;
  logic signed [4:0] split_btf_scale_factor;
  logic [63:0] split_btf_a_in_real, split_btf_a_in_imag, split_btf_b_in_real, split_btf_b_in_imag;
  logic [63:0] split_btf_a_out_real, split_btf_a_out_imag, split_btf_b_out_real, split_btf_b_out_imag;
  logic split_btf_valid_out;
  split_fft #(
              .N(N)
            )split_fft(
              .clk(clk),
              .rst(!rst_n || instruction_done),
              .size(split_size),
              .start(split_start && !split_start_i),

              .bram1_addr_a(split_bram1_addr_a),
              .bram1_dout_a(split_bram1_dout_a),
              .bram1_addr_b(split_bram1_addr_b),
              .bram1_dout_b(split_bram1_dout_b),

              .bram2_addr_a(split_bram2_addr_a),
              .bram2_din_a(split_bram2_din_a),
              .bram2_we_a(split_bram2_we_a),
              .bram2_addr_b(split_bram2_addr_b),
              .bram2_din_b(split_bram2_din_b),
              .bram2_we_b(split_bram2_we_b),

              .done(split_done),

              .btf_mode(split_btf_mode),
              .btf_valid_in(split_btf_valid_in),
              .btf_a_in_real(split_btf_a_in_real),
              .btf_a_in_imag(split_btf_a_in_imag),
              .btf_b_in_real(split_btf_b_in_real),
              .btf_b_in_imag(split_btf_b_in_imag),
              .btf_scale_factor(split_btf_scale_factor),
              .btf_tw_addr(split_btf_tw_addr),
              .btf_a_out_real(split_btf_a_out_real),
              .btf_a_out_imag(split_btf_a_out_imag),
              .btf_b_out_real(split_btf_b_out_real),
              .btf_b_out_imag(split_btf_b_out_imag),
              .btf_valid_out(split_btf_valid_out)
            );

  logic merge_start, merge_start_i;
  logic [$clog2(N):0] merge_size;
  logic [`BRAM_ADDR_WIDTH-1:0] merge_bram1_addr_a;
  logic [`BRAM_DATA_WIDTH-1:0] merge_bram1_dout_a;
  logic [`BRAM_ADDR_WIDTH-1:0] merge_bram1_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] merge_bram1_dout_b;
  logic [`BRAM_ADDR_WIDTH-1:0] merge_bram2_addr_a;
  logic [`BRAM_DATA_WIDTH-1:0] merge_bram2_din_a;
  logic merge_bram2_we_a;
  logic [`BRAM_ADDR_WIDTH-1:0] merge_bram2_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] merge_bram2_din_b;
  logic merge_bram2_we_b;
  logic merge_done;
  logic merge_btf_mode;
  logic [9:0] merge_btf_tw_addr;
  logic merge_btf_valid_in;
  logic signed [4:0] merge_btf_scale_factor;
  logic [63:0] merge_btf_a_in_real, merge_btf_a_in_imag, merge_btf_b_in_real, merge_btf_b_in_imag;
  logic [63:0] merge_btf_a_out_real, merge_btf_a_out_imag, merge_btf_b_out_real, merge_btf_b_out_imag;
  logic merge_btf_valid_out;
  merge_fft #(
              .N(N)
            )merge_fft(
              .clk(clk),
              .rst(!rst_n || instruction_done),
              .size(merge_size),
              .start(merge_start && !merge_start_i),

              .bram1_addr_a(merge_bram1_addr_a),
              .bram1_dout_a(merge_bram1_dout_a),
              .bram1_addr_b(merge_bram1_addr_b),
              .bram1_dout_b(merge_bram1_dout_b),

              .bram2_addr_a(merge_bram2_addr_a),
              .bram2_din_a(merge_bram2_din_a),
              .bram2_we_a(merge_bram2_we_a),
              .bram2_addr_b(merge_bram2_addr_b),
              .bram2_din_b(merge_bram2_din_b),
              .bram2_we_b(merge_bram2_we_b),

              .done(merge_done),

              .btf_mode(merge_btf_mode),
              .btf_valid_in(merge_btf_valid_in),
              .btf_a_in_real(merge_btf_a_in_real),
              .btf_a_in_imag(merge_btf_a_in_imag),
              .btf_b_in_real(merge_btf_b_in_real),
              .btf_b_in_imag(merge_btf_b_in_imag),
              .btf_scale_factor(merge_btf_scale_factor),
              .btf_tw_addr(merge_btf_tw_addr),
              .btf_a_out_real(merge_btf_a_out_real),
              .btf_a_out_imag(merge_btf_a_out_imag),
              .btf_b_out_real(merge_btf_b_out_real),
              .btf_b_out_imag(merge_btf_b_out_imag),
              .btf_valid_out(merge_btf_valid_out)
            );

  always_comb begin
    if(instruction[122]) begin
      btf_mode = fft_btf_mode;
      btf_valid_in = fft_btf_valid_in;
      btf_a_in_real = fft_btf_a_in_real;
      btf_a_in_imag = fft_btf_a_in_imag;
      btf_b_in_real = fft_btf_b_in_real;
      btf_b_in_imag = fft_btf_b_in_imag;
      btf_scale_factor = fft_btf_scale_factor;
      btf_tw_addr = fft_btf_tw_addr;

      fft_btf_a_out_real = btf_a_out_real;
      fft_btf_a_out_imag = btf_a_out_imag;
      fft_btf_b_out_real = btf_b_out_real;
      fft_btf_b_out_imag = btf_b_out_imag;
      fft_btf_valid_out = btf_valid_out;

      split_btf_a_out_real = 0;
      split_btf_a_out_imag = 0;
      split_btf_b_out_real = 0;
      split_btf_b_out_imag = 0;
      split_btf_valid_out = 0;
      merge_btf_a_out_real = 0;
      merge_btf_a_out_imag = 0;
      merge_btf_b_out_real = 0;
      merge_btf_b_out_imag = 0;
      merge_btf_valid_out = 0;
    end
    else if(instruction[118]) begin
      btf_mode = split_btf_mode;
      btf_valid_in = split_btf_valid_in;
      btf_a_in_real = split_btf_a_in_real;
      btf_a_in_imag = split_btf_a_in_imag;
      btf_b_in_real = split_btf_b_in_real;
      btf_b_in_imag = split_btf_b_in_imag;
      btf_scale_factor = split_btf_scale_factor;
      btf_tw_addr = split_btf_tw_addr;

      split_btf_a_out_real = btf_a_out_real;
      split_btf_a_out_imag = btf_a_out_imag;
      split_btf_b_out_real = btf_b_out_real;
      split_btf_b_out_imag = btf_b_out_imag;
      split_btf_valid_out = btf_valid_out;

      fft_btf_a_out_real = 0;
      fft_btf_a_out_imag = 0;
      fft_btf_b_out_real = 0;
      fft_btf_b_out_imag = 0;
      fft_btf_valid_out = 0;
      merge_btf_a_out_real = 0;
      merge_btf_a_out_imag = 0;
      merge_btf_b_out_real = 0;
      merge_btf_b_out_imag = 0;
      merge_btf_valid_out = 0;
    end
    else begin
      btf_mode = merge_btf_mode;
      btf_valid_in = merge_btf_valid_in;
      btf_a_in_real = merge_btf_a_in_real;
      btf_a_in_imag = merge_btf_a_in_imag;
      btf_b_in_real = merge_btf_b_in_real;
      btf_b_in_imag = merge_btf_b_in_imag;
      btf_scale_factor = merge_btf_scale_factor;
      btf_tw_addr = merge_btf_tw_addr;

      merge_btf_a_out_real = btf_a_out_real;
      merge_btf_a_out_imag = btf_a_out_imag;
      merge_btf_b_out_real = btf_b_out_real;
      merge_btf_b_out_imag = btf_b_out_imag;
      merge_btf_valid_out = btf_valid_out;

      fft_btf_a_out_real = 0;
      fft_btf_a_out_imag = 0;
      fft_btf_b_out_real = 0;
      fft_btf_b_out_imag = 0;
      fft_btf_valid_out = 0;
      split_btf_a_out_real = 0;
      split_btf_a_out_imag = 0;
      split_btf_b_out_real = 0;
      split_btf_b_out_imag = 0;
      split_btf_valid_out = 0;
    end
  end

  logic decompress_start, decompress_start_i;
  logic [`BRAM_ADDR_WIDTH-1:0] decompress_input_bram_addr;
  logic [`BRAM_DATA_WIDTH-1:0] decompress_input_bram_data;
  logic [`BRAM_ADDR_WIDTH-1:0] decompress_output_bram1_addr;
  logic [`BRAM_DATA_WIDTH-1:0] decompress_output_bram1_data;
  logic decompress_output_bram1_we;
  logic [`BRAM_ADDR_WIDTH-1:0] decompress_output_bram2_addr;
  logic [`BRAM_DATA_WIDTH-1:0] decompress_output_bram2_data;
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
  logic [`BRAM_ADDR_WIDTH-1:0] ntt_bram1_addr_a;
  logic [`BRAM_DATA_WIDTH-1:0] ntt_bram1_din_a, ntt_bram1_dout_a;
  logic ntt_bram1_we_a;
  logic [`BRAM_ADDR_WIDTH-1:0] ntt_bram1_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] ntt_bram1_din_b, ntt_bram1_dout_b;
  logic ntt_bram1_we_b;
  logic [`BRAM_ADDR_WIDTH-1:0] ntt_bram2_addr_a;
  logic [`BRAM_DATA_WIDTH-1:0] ntt_bram2_din_a, ntt_bram2_dout_a;
  logic ntt_bram2_we_a;
  logic [`BRAM_ADDR_WIDTH-1:0] ntt_bram2_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] ntt_bram2_din_b, ntt_bram2_dout_b;
  logic ntt_bram2_we_b;
  logic ntt_done;
  ntt #(
        .N(N)
      )ntt(
        .clk(clk),
        .rst_n(rst_n && !instruction_done), // Reset on instruction_done so it's ready for the next instruction
        .start(ntt_start && !ntt_start_i),
        .mode(ntt_mode),

        .bram1_addr_a(ntt_bram1_addr_a),
        .bram1_din_a(ntt_bram1_din_a),
        .bram1_dout_a(ntt_bram1_dout_a),
        .bram1_we_a(ntt_bram1_we_a),
        .bram1_addr_b(ntt_bram1_addr_b),
        .bram1_din_b(ntt_bram1_din_b),
        .bram1_dout_b(ntt_bram1_dout_b),
        .bram1_we_b(ntt_bram1_we_b),

        .bram2_addr_a(ntt_bram2_addr_a),
        .bram2_din_a(ntt_bram2_din_a),
        .bram2_dout_a(ntt_bram2_dout_a),
        .bram2_we_a(ntt_bram2_we_a),
        .bram2_addr_b(ntt_bram2_addr_b),
        .bram2_din_b(ntt_bram2_din_b),
        .bram2_dout_b(ntt_bram2_dout_b),
        .bram2_we_b(ntt_bram2_we_b),

        .done(ntt_done)
      );

  localparam int MOD_MULT_PARALLEL_OPS_COUNT = 2;
  logic signed [14:0] mod_mult_a [MOD_MULT_PARALLEL_OPS_COUNT], mod_mult_b [MOD_MULT_PARALLEL_OPS_COUNT];
  logic mod_mult_valid_in, mod_mult_valid_in_delayed;
  logic signed [14:0] mod_mult_result [MOD_MULT_PARALLEL_OPS_COUNT];
  logic mod_mult_valid_out;
  logic mod_mult_done, mod_mult_done_delayed;
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
  logic [`BRAM_ADDR_WIDTH-1:0] mod_mult_write_addr, mod_mult_write_addr_delayed;  // Where to write the output of mod_mult
  delay_register #(.BITWIDTH(`BRAM_ADDR_WIDTH), .CYCLE_COUNT(7)) mod_mult_write_addr_delay(.clk(clk), .in(mod_mult_write_addr), .out(mod_mult_write_addr_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) mod_mult_valid_in_delay(.clk(clk), .in(mod_mult_valid_in), .out(mod_mult_valid_in_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(6)) mod_mult_done_delay(.clk(clk), .in(mod_mult_done), .out(mod_mult_done_delayed));

  localparam int SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT = 2;
  logic signed [14:0] sub_normalize_squared_norm_a [SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT], sub_normalize_squared_norm_b [SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT], sub_normalize_squared_norm_c [SUB_NORMALIZE_SQUARED_NORM_PARALLEL_OPS_COUNT];
  logic sub_normalize_squared_norm_valid, sub_normalize_squared_norm_valid_delayed;
  logic sub_normalize_squared_norm_last_delayed;
  logic sub_normalize_squared_norm_accept, sub_normalize_squared_norm_reject;
  logic sub_normalize_squared_norm_done, sub_normalize_squared_norm_done_delayed;
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
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(1)) sub_normalize_squared_norm_last_delay(.clk(clk), .in(sub_normalize_squared_norm_done), .out(sub_normalize_squared_norm_last_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(7)) sub_normalize_squared_norm_done_delay(.clk(clk), .in(sub_normalize_squared_norm_done), .out(sub_normalize_squared_norm_done_delayed));

  // FLP adder can only add two 64 doubles at a time, so we use two instances of it to add 4 doubles at a time.
  logic fp_adder_mode;
  logic fp_adder_valid_in, fp_adder_valid_in_delayed;
  logic [63:0] fp_adder1_a, fp_adder1_b;
  logic [63:0] fp_adder2_a, fp_adder2_b;
  logic [63:0] fp_adder1_result;
  logic [63:0] fp_adder2_result;
  logic [`BRAM_ADDR_WIDTH-1:0] fp_adder_dst_addr, fp_adder_dst_addr_delayed;
  logic fp_adder_valid_out;
  logic fp_adder_done, fp_adder_done_delayed;
  fp_adder fp_adder1(
             .clk(clk),
             .mode(fp_adder_mode),
             .valid_in(fp_adder_valid_in_delayed),
             .a(fp_adder1_a),
             .b(fp_adder1_b),
             .result(fp_adder1_result),
             .valid_out(fp_adder_valid_out)
           );
  fp_adder fp_adder2(
             .clk(clk),
             .mode(fp_adder_mode),
             .valid_in(fp_adder_valid_in_delayed),
             .a(fp_adder2_a),
             .b(fp_adder2_b),
             .result(fp_adder2_result),
             .valid_out()
           );
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) fp_adder_valid_in_delay(.clk(clk), .in(fp_adder_valid_in), .out(fp_adder_valid_in_delayed));
  delay_register #(.BITWIDTH(`BRAM_ADDR_WIDTH), .CYCLE_COUNT(9)) fp_adder_dst_addr_delay(.clk(clk), .in(fp_adder_dst_addr), .out(fp_adder_dst_addr_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(9)) fp_adder_done_delay(.clk(clk), .in(fp_adder_done), .out(fp_adder_done_delayed));

  // FLP multiplier can only multiply two 64 doubles at a time, so we use two instances of it to multiply 4 doubles at a time.
  logic fp_mul_valid_in, fp_mul_valid_in_delayed;
  logic [63:0] fp_mul1_a, fp_mul1_b;
  logic [63:0] fp_mul2_a, fp_mul2_b;
  logic [63:0] fp_mul1_result;
  logic [63:0] fp_mul2_result;
  logic [`BRAM_ADDR_WIDTH-1:0] fp_mul_dst_addr, fp_mul_dst_addr_delayed;
  logic fp_mul_valid_out;
  logic fp_mul_done, fp_mul_done_delayed;
  fp_multiplier fp_multiplier1(
                  .clk(clk),
                  .valid_in(fp_mul_valid_in_delayed),
                  .a(fp_mul1_a),
                  .b(fp_mul1_b),
                  .scale_factor(5'b0),
                  .result(fp_mul1_result),
                  .valid_out(fp_mul_valid_out)
                );
  fp_multiplier fp_multiplier2(
                  .clk(clk),
                  .valid_in(fp_mul_valid_in_delayed),
                  .a(fp_mul2_a),
                  .b(fp_mul2_b),
                  .scale_factor(5'b0),
                  .result(fp_mul2_result),
                  .valid_out()
                );
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) fp_mul_valid_in_delay(.clk(clk), .in(fp_mul_valid_in), .out(fp_mul_valid_in_delayed));
  delay_register #(.BITWIDTH(`BRAM_ADDR_WIDTH), .CYCLE_COUNT(9)) fp_mul_dst_addr_delay(.clk(clk), .in(fp_mul_dst_addr), .out(fp_mul_dst_addr_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(8)) fp_mul_done_delay(.clk(clk), .in(fp_mul_done), .out(fp_mul_done_delayed));

  logic copy_valid_in;
  logic [`BRAM_ADDR_WIDTH-1:0] copy_dst_addr, copy_dst_addr_delayed;
  logic copy_valid_out;
  logic copy_done, copy_done_delayed;
  delay_register #(.BITWIDTH(`BRAM_ADDR_WIDTH), .CYCLE_COUNT(2)) copy_dst_addr_delay(.clk(clk), .in(copy_dst_addr), .out(copy_dst_addr_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) copy_valid_in_delay(.clk(clk), .in(copy_valid_in), .out(copy_valid_out));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(1)) copy_done_delay(.clk(clk), .in(copy_done), .out(copy_done_delayed));

  logic [63:0] complex_mul_a_real, complex_mul_a_imag, complex_mul_b_real, complex_mul_b_imag;
  logic complex_mul_valid_in, complex_mul_valid_in_delayed;
  logic [63:0] complex_mul_result_real, complex_mul_result_imag;
  logic complex_mul_valid_out;
  logic [`BRAM_ADDR_WIDTH-1:0] complex_mul_dst_addr, complex_mul_dst_addr_delayed;
  logic complex_mul_done, complex_mul_done_delayed;
  complex_multiplier complex_multiplier(
                       .clk(clk),
                       .valid_in(complex_mul_valid_in_delayed),
                       .a_real(complex_mul_a_real),
                       .a_imag(complex_mul_a_imag),
                       .b_real(complex_mul_b_real),
                       .b_imag(complex_mul_b_imag),
                       .scale_factor(5'b0),
                       .a_x_b_real(complex_mul_result_real),
                       .a_x_b_imag(complex_mul_result_imag),
                       .valid_out(complex_mul_valid_out)
                     );
  delay_register #(.BITWIDTH(`BRAM_ADDR_WIDTH), .CYCLE_COUNT(16)) complex_mul_dst_addr_delay(.clk(clk), .in(complex_mul_dst_addr), .out(complex_mul_dst_addr_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) complex_mul_valid_in_delay(.clk(clk), .in(complex_mul_valid_in), .out(complex_mul_valid_in_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(15)) complex_mul_done_delay(.clk(clk), .in(complex_mul_done), .out(complex_mul_done_delayed));

  logic [`BRAM_DATA_WIDTH-1:0] compress_t0;
  logic [`BRAM_DATA_WIDTH-1:0] compress_t1;
  logic [`BRAM_DATA_WIDTH-1:0] compress_hm;
  logic compress_lower_half, compress_lower_half_delayed;
  logic compress_valid, compress_valid_delayed;
  logic compress_last, compress_last_delayed;
  logic compress_done, compress_done_delayed;
  logic [`BRAM_ADDR_WIDTH-1:0] compress_bram_addr;
  logic [`BRAM_DATA_WIDTH-1:0] compress_bram_data;
  logic compress_bram_we;
  logic compress_accept;
  logic compress_reject;
  compress #(
             .N(N)
           )compress(
             .clk(clk),
             .rst_n(rst_n),

             .t0(compress_t0),
             .t1(compress_t1),
             .hm(compress_hm),
             .lower_half(compress_lower_half),
             .valid(compress_valid_delayed),
             .last(compress_last_delayed),

             .output_addr(compress_bram_addr),
             .output_data(compress_bram_data),
             .output_we(compress_bram_we),

             .accept(compress_accept),
             .reject(compress_reject)
           );
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(1)) compress_last_delay(.clk(clk), .in(compress_last), .out(compress_last_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) compress_done_delay(.clk(clk), .in(compress_done), .out(compress_done_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) compress_valid_delay(.clk(clk), .in(compress_valid), .out(compress_valid_delayed));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) compress_lower_half_delay(.clk(clk), .in(compress_lower_half), .out(compress_lower_half_delayed));

  logic samplerz_start, samplerz_start_i;
  logic samplerz_restart, samplerz_restart_i;
  logic [63:0] samplerz_mu1, samplerz_mu2, samplerz_isigma;
  logic [1:0] samplerz_seed_offset_a;
  logic [`BRAM_DATA_WIDTH-1:0] samplerz_seed_a;
  logic [1:0] samplerz_seed_offset_b;
  logic [`BRAM_DATA_WIDTH-1:0] samplerz_seed_b;
  logic [63:0] samplerz_result1, samplerz_result2;
  logic samplerz_done;
  samplerz #(
             .N(N)
           )samplerz (
             .clk(clk),
             .rst_n(rst_n),
             .start(samplerz_start == 1'b1 && samplerz_start_i == 1'b0),
             .restart(samplerz_restart == 1'b1 && samplerz_restart_i == 1'b0),

             .mu1(samplerz_mu1),
             .mu2(samplerz_mu2),
             .isigma(samplerz_isigma),

             .seed_offset_a(samplerz_seed_offset_a),
             .seed_bram_dout_a(samplerz_seed_a),
             .seed_offset_b(samplerz_seed_offset_b),
             .seed_bram_dout_b(samplerz_seed_b),

             .result1(samplerz_result1),
             .result2(samplerz_result2),
             .done(samplerz_done)
           );

  assign element_count = (1 << instruction[49:46]);
  assign pipelined_inst_valid = pipelined_inst_index < element_count ? 1'b1 : 1'b0;
  assign pipelined_inst_done = pipelined_inst_index > element_count-1 ? 1'b1 : 1'b0;

  always_ff @(posedge clk) begin

    if(!rst_n) begin
      modules_running <= 1'b0;
      signature_accepted <= 1'b0;
      signature_rejected <= 1'b0;
    end

    if(!rst_n || instruction_done)
      pipelined_inst_index <= -1;
    else
      pipelined_inst_index <= (pipelined_inst_index == N) ? pipelined_inst_index : pipelined_inst_index+1;

    if (!rst_n || instruction[127:127-INSTRUCTION_COUNT+1] == 0) begin
      htp_start <= 1'b0;
      htp_start_i <= 1'b0;

      fft_start <= 1'b0;
      fft_start_i <= 1'b0;

      split_start <= 1'b0;
      split_start_i <= 1'b0;

      merge_start <= 1'b0;
      merge_start_i <= 1'b0;

      decompress_start <= 1'b0;
      decompress_start_i <= 1'b0;

      ntt_start <= 1'b0;
      ntt_start_i <= 1'b0;

      samplerz_start <= 1'b0;
      samplerz_start_i <= 1'b0;
      samplerz_restart <= 1'b0;
      samplerz_restart_i <= 1'b0;
    end
    else if (!instruction_done) begin
      htp_start_i <= htp_start;
      fft_start_i <= fft_start;
      split_start_i <= split_start;
      merge_start_i <= merge_start;
      decompress_start_i <= decompress_start;
      ntt_start_i <= ntt_start;
      samplerz_start_i <= samplerz_start;
      samplerz_restart_i <= samplerz_restart;

      if(instruction[127-0] == 1'b1) begin // BRAM_READ
        // Empty
      end

      if(instruction[127-1] == 1'b1) begin // BRAM_WRITE
        // Empty
      end

      if(instruction[127-2] == 1'b1) begin // COPY
        if(copy_done_delayed)
          modules_running[INSTRUCTION_COUNT-2] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-2] <= 1'b1;
      end

      if(instruction[127-3] == 1'b1) begin // HASH_TO_POINT
        htp_start <= 1'b1;
        if(htp_done_delayed)
          modules_running[INSTRUCTION_COUNT-3] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-3] <= 1'b1;
      end

      if(instruction[127-4] == 1'b1) begin // INT_TO_DOUBLE
        if(int_to_double_done_delayed)
          modules_running[INSTRUCTION_COUNT-4] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-4] <= 1'b1;
      end

      if(instruction[127-5] == 1'b1) begin // FFT_IFFT
        fft_mode <= instruction[44];
        fft_start <= 1'b1;
        if(fft_done)
          modules_running[INSTRUCTION_COUNT-5] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-5] <= 1'b1;
      end

      if(instruction[127-6] == 1'b1) begin // NTT_INTT
        ntt_mode <= instruction[44];
        ntt_start <= 1'b1;
        if(ntt_done)
          modules_running[INSTRUCTION_COUNT-6] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-6] <= 1'b1;
      end

      if(instruction[127-7] == 1'b1) begin // COMPLEX_MUL
        if(complex_mul_done_delayed)
          modules_running[INSTRUCTION_COUNT-7] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-7] <= 1'b1;
      end

      if(instruction[127-8] == 1'b1) begin // MUL_CONST
        if(fp_mul_done_delayed)
          modules_running[INSTRUCTION_COUNT-8] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-8] <= 1'b1;
      end

      if(instruction[127-9] == 1'b1) begin // SPLIT
        split_size <= 1 << instruction[49:46];
        split_start <= 1'b1;
        if(split_done)
          modules_running[INSTRUCTION_COUNT-9] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-9] <= 1'b1;
      end

      if(instruction[127-10] == 1'b1) begin // MERGE
        merge_size <= 1 << instruction[49:46];
        merge_start <= 1'b1;
        if(merge_done)
          modules_running[INSTRUCTION_COUNT-10] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-10] <= 1'b1;
      end

      if(instruction[127-11] == 1'b1) begin // MOD_MULT_Q
        if(mod_mult_done_delayed)
          modules_running[INSTRUCTION_COUNT-11] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-11] <= 1'b1;
      end

      if(instruction[127-12] == 1'b1) begin // SUB_NORM_SQ
        if(sub_normalize_squared_norm_done_delayed)
          modules_running[INSTRUCTION_COUNT-12] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-12] <= 1'b1;

        if(sub_normalize_squared_norm_accept == 1'b1 && sub_normalize_squared_norm_reject == 1'b0) begin
          signature_accepted <= 1'b1;
          signature_rejected <= 1'b0;
        end
        else if (sub_normalize_squared_norm_accept == 1'b0 && sub_normalize_squared_norm_reject == 1'b1) begin
          signature_accepted <= 1'b0;
          signature_rejected <= 1'b1;
        end
      end

      if(instruction[127-13] == 1'b1) begin // DECOMPRESS
        decompress_start <= 1'b1;
        if(decompress_done)
          modules_running[INSTRUCTION_COUNT-13] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-13] <= 1'b1;
      end

      if(instruction[127-14] == 1'b1) begin // COMPRESS
        if(compress_done_delayed)
          modules_running[INSTRUCTION_COUNT-14] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-14] <= 1'b1;
      end

      if(instruction[127-15] == 1'b1) begin // ADD_SUB
        if(fp_adder_done_delayed)
          modules_running[INSTRUCTION_COUNT-15] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-15] <= 1'b1;
      end

      if(instruction[127-16] == 1'b1) begin // SAMPLERZ
        samplerz_start <= 1'b1;
        samplerz_restart <= instruction[44];
        if(samplerz_done)
          modules_running[INSTRUCTION_COUNT-16] <= 1'b0;
        else
          modules_running[INSTRUCTION_COUNT-16] <= 1'b1;
      end
    end
  end

  always_comb begin

    bank1 = instruction[2:0];
    bank2 = instruction[5:3];
    bank3 = instruction[8:6];
    bank4 = instruction[11:9];
    bank5 = instruction[14:12];
    bank6 = instruction[17:15];
    addr1 = instruction[30:18];
    addr2 = instruction[43:31];

    // If not specified otherwise set BRAM signals to 0 (this includes WE, which will turn off writing)
    for(int i = 0; i < BRAM_BANK_COUNT; i++) begin
      bram_addr_a[i] = 0;
      bram_addr_b[i] = 0;
      bram_din_a[i] = 0;
      bram_din_b[i] = 0;
      bram_we_a[i] = 1'b0;
      bram_we_b[i] = 1'b0;
    end

    int_to_double_valid_in = 1'b0;
    int_to_double_done = 1'b0;
    mod_mult_valid_in = 1'b0;
    mod_mult_done = 1'b0;
    sub_normalize_squared_norm_valid = 1'b0;
    sub_normalize_squared_norm_done = 1'b0;
    fp_adder_valid_in = 1'b0;
    fp_adder_done = 1'b0;
    fp_mul_valid_in = 1'b0;
    fp_mul_done = 1'b0;
    copy_valid_in = 1'b0;
    copy_done = 1'b0;
    complex_mul_valid_in = 1'b0;
    complex_mul_done = 1'b0;
    compress_valid = 1'b0;
    compress_last = 1'b0;
    compress_done = 1'b0;
    compress_lower_half = 1'b0;

    bram_dout = 0;
    copy_dst_addr = 0;
    htp_input_bram_data = 0;
    htp_output_bram2_data = 0;
    int_to_double_address_in = 0;
    int_to_double_data_in = 0;
    fft_bram1_dout_a = 0;
    fft_bram1_dout_b = 0;
    fft_bram2_dout_a = 0;
    fft_bram2_dout_b = 0;
    ntt_bram1_dout_a = 0;
    ntt_bram1_dout_b = 0;
    ntt_bram2_dout_a = 0;
    ntt_bram2_dout_b = 0;
    complex_mul_a_real = 0;
    complex_mul_a_imag = 0;
    complex_mul_b_real = 0;
    complex_mul_b_imag = 0;
    complex_mul_dst_addr = 0;
    fp_mul1_a = 0;
    fp_mul2_a = 0;
    fp_mul1_b = 0;
    fp_mul2_b = 0;
    fp_mul_dst_addr = 0;
    split_bram1_dout_a = 0;
    split_bram1_dout_b = 0;
    merge_bram1_dout_a = 0;
    merge_bram1_dout_b = 0;
    mod_mult_a[0] = 0;
    mod_mult_a[1] = 0;
    mod_mult_b[0] = 0;
    mod_mult_b[1] = 0;
    mod_mult_write_addr = 0;
    sub_normalize_squared_norm_a[0] = 0;
    sub_normalize_squared_norm_a[1] = 0;
    sub_normalize_squared_norm_b[0] = 0;
    sub_normalize_squared_norm_b[1] = 0;
    sub_normalize_squared_norm_c[0] = 0;
    sub_normalize_squared_norm_c[1] = 0;
    decompress_input_bram_data = 0;
    decompress_output_bram2_data = 0;
    fp_adder_mode = 0;
    fp_adder1_a = 0;
    fp_adder1_b = 0;
    fp_adder2_a = 0;
    fp_adder2_b = 0;
    fp_adder_dst_addr = 0;
    compress_t0 = 0;
    compress_t1 = 0;
    compress_hm = 0;
    ext_bram_dout = 0;

    if(ext_bram_en == 1'b1) begin     // Software has BRAM access

      ext_bram_bank = ext_bram_addr[19:17];  // Top 3 bits of the address specify the bank
      ext_local_bram_addr = ext_bram_addr[16:4]; // Middle 13 bits specify the address within the bank, bottom 4 bits are ignored

      bram_addr_a[ext_bram_bank] = ext_local_bram_addr;
      bram_din_a[ext_bram_bank] = ext_bram_din;
      bram_we_a[ext_bram_bank] = ext_bram_we[0];
      ext_bram_dout = bram_dout_a[ext_bram_bank];
    end
    else begin  // Instructions have BRAM access

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
        bram_addr_a[bank3] = addr1 + pipelined_inst_index;
        copy_valid_in = pipelined_inst_valid;
        copy_done = pipelined_inst_done;

        copy_dst_addr = (instruction[53] ? addr1 : addr2) + pipelined_inst_index;
        bram_addr_b[bank4] = copy_dst_addr_delayed;
        bram_din_b[bank4] = bram_dout_a[bank3];
        bram_we_b[bank4] = copy_valid_out;
      end

      if(instruction[127-3] == 1'b1) begin // HASH_TO_POINT
        bram_addr_a[bank3] = htp_input_bram_addr;
        htp_input_bram_data = bram_dout_a[bank3];

        bram_addr_a[bank4] = htp_output_bram1_addr;
        bram_din_a[bank4] = htp_output_bram1_data;
        bram_we_a[bank4] = htp_output_bram1_we;

        bram_addr_b[bank4] = htp_output_bram2_addr;
        htp_output_bram2_data = bram_dout_b[bank4];
      end

      if(instruction[127-4] == 1'b1) begin // INT_TO_DOUBLE
        bram_addr_a[bank1] = pipelined_inst_index;
        int_to_double_address_in = pipelined_inst_index;
        int_to_double_data_in = bram_dout_a[bank1];
        int_to_double_done = pipelined_inst_done;
        int_to_double_valid_in = pipelined_inst_valid;

        // Write output to BRAM
        bram_addr_b[bank2] = int_to_double_address_out;
        bram_din_b[bank2] = int_to_double_data_out;
        bram_we_b[bank2] = int_to_double_valid_out;
      end

      if(instruction[127-5] == 1'b1) begin // FFT_IFFT
        bram_addr_a[bank1] = addr1 + fft_bram1_addr_a;
        bram_din_a[bank1] = fft_bram1_din_a;
        bram_we_a[bank1] = fft_bram1_we_a;
        bram_addr_b[bank1] = addr1 + fft_bram1_addr_b;
        bram_din_b[bank1] = fft_bram1_din_b;
        bram_we_b[bank1] = fft_bram1_we_b;
        fft_bram1_dout_a = bram_dout_a[bank1];
        fft_bram1_dout_b = bram_dout_b[bank1];

        bram_addr_a[bank2] = addr2 + fft_bram2_addr_a;
        bram_din_a[bank2] = fft_bram2_din_a;
        bram_we_a[bank2] = fft_bram2_we_a;
        bram_addr_b[bank2] = addr2 + fft_bram2_addr_b;
        bram_din_b[bank2] = fft_bram2_din_b;
        bram_we_b[bank2] = fft_bram2_we_b;
        fft_bram2_dout_a = bram_dout_a[bank2];
        fft_bram2_dout_b = bram_dout_b[bank2];
      end

      if(instruction[127-6] == 1'b1) begin // NTT_INTT
        bram_addr_a[bank1] = ntt_bram1_addr_a;
        bram_din_a[bank1] = ntt_bram1_din_a;
        bram_we_a[bank1] = ntt_bram1_we_a;
        bram_addr_b[bank1] = ntt_bram1_addr_b;
        bram_din_b[bank1] = ntt_bram1_din_b;
        bram_we_b[bank1] = ntt_bram1_we_b;
        ntt_bram1_dout_a = bram_dout_a[bank1];
        ntt_bram1_dout_b = bram_dout_b[bank1];

        bram_addr_a[bank2] = ntt_bram2_addr_a;
        bram_din_a[bank2] = ntt_bram2_din_a;
        bram_we_a[bank2] = ntt_bram2_we_a;
        bram_addr_b[bank2] = ntt_bram2_addr_b;
        bram_din_b[bank2] = ntt_bram2_din_b;
        bram_we_b[bank2] = ntt_bram2_we_b;
        ntt_bram2_dout_a = bram_dout_a[bank2];
        ntt_bram2_dout_b = bram_dout_b[bank2];
      end

      if(instruction[127-7] == 1'b1) begin // COMPLEX_MUL
        bram_addr_a[bank1] = addr1 + pipelined_inst_index;
        bram_addr_a[bank2] = addr2 + pipelined_inst_index;
        complex_mul_a_real = bram_dout_a[bank1][127:64];
        complex_mul_a_imag = bram_dout_a[bank1][63:0];
        complex_mul_b_real = bram_dout_a[bank2][127:64];
        complex_mul_b_imag = bram_dout_a[bank2][63:0];
        complex_mul_valid_in = pipelined_inst_valid;
        complex_mul_done = pipelined_inst_done;

        complex_mul_dst_addr = addr1 + pipelined_inst_index;
        bram_addr_b[bank1] = complex_mul_dst_addr_delayed;
        bram_din_b[bank1] = {complex_mul_result_real, complex_mul_result_imag};
        bram_we_b[bank1] = complex_mul_valid_out;
      end

      if(instruction[127-8] == 1'b1) begin // MUL_CONST
        bram_addr_a[bank3] = pipelined_inst_index;
        fp_mul1_a = bram_dout_a[bank3][127:64];
        fp_mul2_a = bram_dout_a[bank3][63:0];

        fp_mul1_b = instruction[45] ? $realtobits(-1.0 / 12289.0) : $realtobits(1.0 / 12289.0);
        fp_mul2_b = instruction[45] ? $realtobits(-1.0 / 12289.0) : $realtobits(1.0 / 12289.0);
        fp_mul_valid_in = pipelined_inst_valid;
        fp_mul_done = pipelined_inst_done;
        fp_mul_dst_addr = pipelined_inst_index;

        bram_addr_b[bank4] = fp_mul_dst_addr_delayed;
        bram_din_b[bank4] = {fp_mul1_result, fp_mul2_result};
        bram_we_b[bank4] = fp_mul_valid_out;
      end

      if(instruction[127-9] == 1'b1) begin // SPLIT
        bram_addr_a[bank1] = split_bram1_addr_a + addr1;
        bram_addr_b[bank1] = split_bram1_addr_b + addr1;
        split_bram1_dout_a = bram_dout_a[bank1];
        split_bram1_dout_b = bram_dout_b[bank1];

        bram_addr_a[bank2] = split_bram2_addr_a + addr2;
        bram_din_a[bank2] = split_bram2_din_a;
        bram_we_a[bank2] = split_bram2_we_a;
        bram_addr_b[bank2] = split_bram2_addr_b + addr2;
        bram_din_b[bank2] = split_bram2_din_b;
        bram_we_b[bank2] = split_bram2_we_b;
      end

      if(instruction[127-10] == 1'b1) begin // MERGE
        bram_addr_a[bank1] = merge_bram1_addr_a + addr1;
        bram_addr_b[bank1] = merge_bram1_addr_b + addr1;
        merge_bram1_dout_a = bram_dout_a[bank1];
        merge_bram1_dout_b = bram_dout_b[bank1];

        bram_addr_a[bank2] = merge_bram2_addr_a + addr2;
        bram_din_a[bank2] = merge_bram2_din_a;
        bram_we_a[bank2] = merge_bram2_we_a;
        bram_addr_b[bank2] = merge_bram2_addr_b + addr2;
        bram_din_b[bank2] = merge_bram2_din_b;
        bram_we_b[bank2] = merge_bram2_we_b;
      end

      if(instruction[127-11] == 1'b1) begin // MOD_MULT_Q
        bram_addr_a[bank1] = pipelined_inst_index;
        bram_addr_b[bank1] = pipelined_inst_index + N/2;
        bram_addr_a[bank2] = pipelined_inst_index;
        bram_addr_b[bank2] = pipelined_inst_index + N/2;

        mod_mult_a[0] = bram_dout_a[bank1][14:0];
        mod_mult_a[1] = bram_dout_b[bank1][14:0];
        mod_mult_b[0] = bram_dout_a[bank2][14:0];
        mod_mult_b[1] = bram_dout_b[bank2][14:0];
        mod_mult_valid_in = pipelined_inst_valid;
        mod_mult_done = pipelined_inst_done;
        mod_mult_write_addr = pipelined_inst_index;

        bram_addr_a[bank3] = mod_mult_write_addr_delayed;
        bram_din_a[bank3] = {49'b0, mod_mult_result[0], 49'b0, mod_mult_result[1]};
        bram_we_a[bank3] = mod_mult_valid_out;
      end

      if(instruction[127-12] == 1'b1) begin // SUB_NORM_SQ
        bram_addr_a[bank1] = pipelined_inst_index; // Data from hash_to_point
        bram_addr_a[bank2] = pipelined_inst_index; // Data from INTT
        bram_addr_b[bank2] = pipelined_inst_index + N/2; // Data from INTT
        bram_addr_b[bank3] = pipelined_inst_index; // Data from decompress

        sub_normalize_squared_norm_a[0] = bram_dout_a[bank1][64+14:64];
        sub_normalize_squared_norm_a[1] = bram_dout_a[bank1][14:0];
        sub_normalize_squared_norm_b[0] = bram_dout_a[bank2][14:0];
        sub_normalize_squared_norm_b[1] = bram_dout_b[bank2][14:0];
        sub_normalize_squared_norm_c[0] = bram_dout_b[bank3][64+14:64];
        sub_normalize_squared_norm_c[1] = bram_dout_b[bank3][14:0];

        sub_normalize_squared_norm_valid = pipelined_inst_valid;
        sub_normalize_squared_norm_done = pipelined_inst_done;
      end

      if(instruction[127-13] == 1'b1) begin // DECOMPRESS
        bram_addr_a[bank5] = decompress_input_bram_addr;
        decompress_input_bram_data = bram_dout_a[bank5];

        bram_addr_a[bank6] = decompress_output_bram1_addr;
        bram_din_a[bank6] = decompress_output_bram1_data;
        bram_we_a[bank6] = decompress_output_bram1_we;

        bram_addr_a[instruction[52:50]] = decompress_output_bram1_addr; // decompress can output to two banks at the same time
        bram_din_a[instruction[52:50]] = decompress_output_bram1_data;
        bram_we_a[instruction[52:50]] = decompress_output_bram1_we;

        bram_addr_b[bank6] = decompress_output_bram2_addr;
        decompress_output_bram2_data = bram_dout_b[bank6];
      end

      if(instruction[127-14] == 1'b1) begin // COMPRESS
        bram_addr_a[bank1] = addr1 + (pipelined_inst_index % (N/2));
        bram_addr_a[bank2] = addr1 + (pipelined_inst_index % (N/2));
        bram_addr_a[bank3] = addr2 + (pipelined_inst_index % (N/2));

        compress_t0 = bram_dout_a[bank1];
        compress_t1 = bram_dout_a[bank2];
        compress_hm = bram_dout_a[bank3];
        compress_valid = pipelined_inst_valid;
        compress_done = pipelined_inst_done;
        compress_last = pipelined_inst_done;
        compress_lower_half = pipelined_inst_index >= (N/2) ? 1'b1 : 1'b0;

        bram_addr_b[bank4] = addr1 + compress_bram_addr;
        bram_we_b[bank4] = compress_bram_we;
        bram_din_b[bank4] = compress_bram_data;
      end

      if(instruction[127-15] == 1'b1) begin // ADD_SUB
        fp_adder_mode = instruction[54];

        bram_addr_a[bank3] = addr1 + pipelined_inst_index;
        bram_addr_a[bank4] = (instruction[53] ? addr1 : addr2) + pipelined_inst_index;

        fp_adder1_a = bram_dout_a[bank4][127:64];
        fp_adder2_a = bram_dout_a[bank4][63:0];
        fp_adder1_b = bram_dout_a[bank3][127:64];
        fp_adder2_b = bram_dout_a[bank3][63:0];

        fp_adder_valid_in = pipelined_inst_valid;
        fp_adder_done = pipelined_inst_done;
        fp_adder_dst_addr = (instruction[53] ? addr1 : addr2) + pipelined_inst_index;

        bram_addr_b[bank4] = fp_adder_dst_addr_delayed;
        bram_din_b[bank4] = {fp_adder1_result, fp_adder2_result};
        bram_we_b[bank4] = fp_adder_valid_out;
      end

      if(instruction[127-16] == 1'b1) begin // SAMPLERZ
        // mu
        bram_addr_a[bank1] = addr1;
        {samplerz_mu1, samplerz_mu2} = bram_dout_a[bank1];

        // isigma. Take either high 64 bits or low 64 bits
        bram_addr_a[bank2] = addr2;
        samplerz_isigma = instruction[54] ? bram_dout_a[bank2][63:0] : bram_dout_a[bank2][127:64];

        // result
        bram_addr_a[bank3] = (N == 512) ? 528 : 784;
        bram_din_a[bank3] = {samplerz_result1, samplerz_result2};
        bram_we_a[bank3] = samplerz_done;

        // seed
        bram_addr_a[bank4] = ((N == 512) ? 802 : 1604) + samplerz_seed_offset_a;
        bram_addr_b[bank4] = ((N == 512) ? 802 : 1604) + samplerz_seed_offset_b;
        // samplerz_seed_a = bram_din_a[bank4];
        // samplerz_seed_b = bram_din_b[bank4];
        samplerz_seed_a = 128'h11111111111111111111111111111111;
        samplerz_seed_b = 128'h11111111111111111111111111111111;
      end
    end
  end
endmodule
