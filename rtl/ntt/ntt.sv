`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Implements both NTT and inverse NTT for negative-wrapped convolution, computing two butterflies per cycle.
// Because we are never going to use both at the same time, we can save resources by reusing the same module.
//
// Data layout: BRAM word holds coefficient w in bits [78:64] and coefficient w + N/2 in bits [14:0]
//
// Uses 2 BRAMs to store the data. During any stage it will read from one BRAM and write to the other.
// Stage 1: read from BRAM1, write to BRAM2
// Stage 2: read from BRAM2, write to BRAM1
// ... and so on
// Input is always in BRAM1. Output is in BRAM2 for N=512 and in BRAM1 for N=1024 (odd/even number of stages).
//
// Each stage has butterflies (x, x+s) for stride s: N/2, N/4, ..., 1 for NTT and 1, 2, ..., N/2 for inverse NTT.
// Every cycle two words are read and two butterflies computed:
//   s = N/2: words 2k and 2k+1, each holding one butterfly pair (x, x + N/2)
//   s < N/2: words x and x+s, giving butterflies (x, x+s) and (x + N/2, x + N/2 + s)
//
// The results are written to the same word addresses in the other BRAM.
//
// Twiddle factors are in Montgomery form.
//
// The inverse NTT also multiplies the result by 1/N in its last stage.
//
//////////////////////////////////////////////////////////////////////////////////


module ntt#(
    parameter int N = 512
  )(
    input logic clk,
    input logic rst_n,

    input logic mode, // 0: NTT, 1: Inverse NTT
    input logic start,

    output logic [`BRAM_ADDR_WIDTH-1:0] bram1_addr_a,
    output logic [`BRAM_DATA_WIDTH-1:0] bram1_din_a,
    input logic [`BRAM_DATA_WIDTH-1:0] bram1_dout_a,
    output logic bram1_we_a,
    output logic [`BRAM_ADDR_WIDTH-1:0] bram1_addr_b,
    output logic [`BRAM_DATA_WIDTH-1:0] bram1_din_b,
    input logic [`BRAM_DATA_WIDTH-1:0] bram1_dout_b,
    output logic bram1_we_b,

    output logic [`BRAM_ADDR_WIDTH-1:0] bram2_addr_a,
    output logic [`BRAM_DATA_WIDTH-1:0] bram2_din_a,
    input logic [`BRAM_DATA_WIDTH-1:0] bram2_dout_a,
    output logic bram2_we_a,
    output logic [`BRAM_ADDR_WIDTH-1:0] bram2_addr_b,
    output logic [`BRAM_DATA_WIDTH-1:0] bram2_din_b,
    input logic [`BRAM_DATA_WIDTH-1:0] bram2_dout_b,
    output logic bram2_we_b,

    output logic done
  );

  localparam int ITEM_BITS = (N / 4) > 1 ? $clog2(N / 4) : 1;
  localparam int WORD_BITS = $clog2(N / 2);
  localparam int LATENCY = 8;  // Cycles from issuing the read addresses to writing the results
  localparam int SCALE_SHIFT = 14 - $clog2(N);

  typedef enum logic [1:0] {IDLE, RUN, DRAIN, DONE} state_t;
  state_t state;

  logic [$clog2($clog2(N)+1)-1:0] stage;
  logic [ITEM_BITS-1:0] item;
  logic [3:0] drain_count;

  logic [$clog2($clog2(N)+1)-1:0] log_stride;
  logic pair_stage, last_intt_stage;
  assign log_stride = mode == 1'b0 ? $clog2(N) - 1 - stage : stage;
  assign pair_stage = log_stride == $clog2(N) - 1;
  assign last_intt_stage = mode == 1'b1 && stage == $clog2(N) - 1;

  logic read_bram2;
  assign read_bram2 = stage[0];

  //////////////////////////////// Issue: read addresses and twiddle factor addresses ////////////////////////////////

  logic [WORD_BITS-1:0] x, read_addr_a, read_addr_b;
  logic [9:0] twiddle_addr0, twiddle_addr1;
  always_comb
  begin
    // x: item with a zero inserted at bit log_stride (the lower index of the butterfly)
    x = ((WORD_BITS'(item) >> log_stride) << (log_stride + 1)) | (WORD_BITS'(item) & ((WORD_BITS'(1) << log_stride) - 1));
    if (pair_stage)
    begin
      read_addr_a = WORD_BITS'(item) << 1;
      read_addr_b = (WORD_BITS'(item) << 1) + 1;
      twiddle_addr0 = 1;
      twiddle_addr1 = 1;
    end
    else
    begin
      read_addr_a = x;
      read_addr_b = x + (WORD_BITS'(1) << log_stride);
      // Twiddle factor of butterfly (x, x+s): N/(2s) + x/(2s) for both the NTT and the inverse NTT
      twiddle_addr0 = (10'(1) << ($clog2(N) - 1 - log_stride)) + (10'(x) >> (log_stride + 1));
      twiddle_addr1 = twiddle_addr0 + (10'(1) << ($clog2(N) - 2 - log_stride));  // butterfly (x + N/2, x + N/2 + s)
    end
  end

  logic issue_valid;
  logic [WORD_BITS-1:0] issue_addr_a, issue_addr_b;
  logic [9:0] issue_twiddle_addr0, issue_twiddle_addr1;

  always_ff @(posedge clk)
  begin
    if (!rst_n)
    begin
      state <= IDLE;
      issue_valid <= 0;
    end
    else
    begin
      issue_valid <= 0;
      case (state)
        IDLE:
        begin
          stage <= 0;
          item <= 0;
          if (start)
            state <= RUN;
        end
        RUN:
        begin
          issue_valid <= 1;
          issue_addr_a <= read_addr_a;
          issue_addr_b <= read_addr_b;
          issue_twiddle_addr0 <= twiddle_addr0;
          issue_twiddle_addr1 <= twiddle_addr1;
          item <= item + 1;
          drain_count <= 0;
          if (item == (N / 4) - 1)
            state <= DRAIN;
        end
        DRAIN:
        begin  // Wait until the last results are written: the next stage reads them
          drain_count <= drain_count + 1;
          if (drain_count == LATENCY)
          begin
            if (stage == $clog2(N) - 1)
              state <= DONE;
            else
            begin
              stage <= stage + 1;
              state <= RUN;
            end
          end
        end
        default:
          ;
      endcase
    end
  end

  assign done = state == DONE;

  //////////////////////////////// Datapath ////////////////////////////////

  logic signed [14:0] twiddle0, twiddle1, twiddle0_1, twiddle1_1;
  ntt_twiddle_factor_rom twiddle_rom0(.clk(clk), .mode(mode), .addr(issue_twiddle_addr0), .data(twiddle0));
  ntt_twiddle_factor_rom twiddle_rom1(.clk(clk), .mode(mode), .addr(issue_twiddle_addr1), .data(twiddle1));
  always_ff @(posedge clk)
  begin
    twiddle0_1 <= twiddle0;
    twiddle1_1 <= twiddle1;
  end

  logic [`BRAM_DATA_WIDTH-1:0] word_a, word_b;
  assign word_a = read_bram2 ? bram2_dout_a : bram1_dout_a;
  assign word_b = read_bram2 ? bram2_dout_b : bram1_dout_b;

  function automatic logic [14:0] canonical(input logic signed [14:0] a);
    return a < 0 ? a + 15'(12289) : a;
  endfunction

  function automatic logic [14:0] mod_add(input logic [14:0] a, b);
    logic [15:0] sum = a + b;
    return sum >= 12289 ? 15'(sum - 12289) : 15'(sum);
  endfunction

  function automatic logic [14:0] mod_sub(input logic [14:0] a, b);
    return a >= b ? a - b : a + 15'(12289) - b;
  endfunction

  logic [14:0] u_in [2], v_in [2];
  always_comb
  begin
    if (pair_stage)
    begin
      u_in[0] = word_a[64+14:64];
      v_in[0] = word_a[14:0];
      u_in[1] = word_b[64+14:64];
      v_in[1] = word_b[14:0];
    end
    else
    begin
      u_in[0] = word_a[64+14:64];
      v_in[0] = word_b[64+14:64];
      u_in[1] = word_a[14:0];
      v_in[1] = word_b[14:0];
    end
  end

  logic [14:0] out_u_8 [2], out_v_8 [2];

  for (genvar lane = 0; lane < 2; lane++)
  begin : lanes
    logic [14:0] u_3, v_3, w_3;
    logic [14:0] factor_4, keep_4, w_4;
    logic [27:0] product_5;
    logic [14:0] keep_5;
    logic [13:0] reduced;
    logic [14:0] product_6, keep_6;
    logic [14:0] out_u_7, out_v_7;
    logic [13:0] scaled_u, scaled_v;
    logic [14:0] out_u, out_v;

    montgomery_reduce reduce(.x(product_5), .result(reduced));
    montgomery_reduce scale_u(.x(28'(out_u_7) << SCALE_SHIFT), .result(scaled_u));
    montgomery_reduce scale_v(.x(28'(out_v_7) << SCALE_SHIFT), .result(scaled_v));

    always_ff @(posedge clk)
    begin
      u_3 <= mode == 1'b0 ? canonical(u_in[lane]) : u_in[lane];
      v_3 <= mode == 1'b0 ? canonical(v_in[lane]) : v_in[lane];
      w_3 <= lane == 0 ? twiddle0_1 : twiddle1_1;

      factor_4 <= mode == 1'b0 ? v_3 : mod_sub(u_3, v_3);
      keep_4 <= mode == 1'b0 ? u_3 : mod_add(u_3, v_3);
      w_4 <= w_3;

      product_5 <= factor_4 * w_4;
      keep_5 <= keep_4;
      product_6 <= reduced;
      keep_6 <= keep_5;

      out_u_7 <= mode == 1'b0 ? mod_add(keep_6, product_6) : keep_6;
      out_v_7 <= mode == 1'b0 ? mod_sub(keep_6, product_6) : product_6;

      out_u <= last_intt_stage ? 15'(scaled_u) : out_u_7;
      out_v <= last_intt_stage ? 15'(scaled_v) : out_v_7;
    end

    assign out_u_8[lane] = out_u;
    assign out_v_8[lane] = out_v;
  end

  logic write_valid;
  logic [WORD_BITS-1:0] write_addr_a, write_addr_b;
  delay_register #(.BITWIDTH(1 + 2*WORD_BITS), .CYCLE_COUNT(LATENCY)) write_delay(
                   .clk(clk),
                   .in({issue_valid, issue_addr_a, issue_addr_b}),
                   .out({write_valid, write_addr_a, write_addr_b}));

  logic [`BRAM_DATA_WIDTH-1:0] write_word_a, write_word_b;
  always_comb
  begin
    if (pair_stage)
    begin
      write_word_a = {49'b0, out_u_8[0], 49'b0, out_v_8[0]};
      write_word_b = {49'b0, out_u_8[1], 49'b0, out_v_8[1]};
    end
    else
    begin
      write_word_a = {49'b0, out_u_8[0], 49'b0, out_u_8[1]};
      write_word_b = {49'b0, out_v_8[0], 49'b0, out_v_8[1]};
    end
  end

  always_comb
  begin
    bram1_addr_a = read_bram2 ? `BRAM_ADDR_WIDTH'(write_addr_a) : `BRAM_ADDR_WIDTH'(issue_addr_a);
    bram1_addr_b = read_bram2 ? `BRAM_ADDR_WIDTH'(write_addr_b) : `BRAM_ADDR_WIDTH'(issue_addr_b);
    bram1_din_a = write_word_a;
    bram1_din_b = write_word_b;
    bram1_we_a = read_bram2 && write_valid;
    bram1_we_b = read_bram2 && write_valid;

    bram2_addr_a = read_bram2 ? `BRAM_ADDR_WIDTH'(issue_addr_a) : `BRAM_ADDR_WIDTH'(write_addr_a);
    bram2_addr_b = read_bram2 ? `BRAM_ADDR_WIDTH'(issue_addr_b) : `BRAM_ADDR_WIDTH'(write_addr_b);
    bram2_din_a = write_word_a;
    bram2_din_b = write_word_b;
    bram2_we_a = !read_bram2 && write_valid;
    bram2_we_b = !read_bram2 && write_valid;
  end

endmodule
