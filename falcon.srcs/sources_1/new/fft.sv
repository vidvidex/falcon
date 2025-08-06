`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Implements FFT and IFFT with 512 or 1024 coefficients (256 or 512 complex points).
// The implementation is essentially a port of the reference Falcon C implementation of the FFT/IFFT algorithm.
//
// Uses 2 BRAMs to store the data. During any stage it will read from one BRAM and write to the other.
// Stage 1: read from BRAM1, write to BRAM2
// Stage 2: read from BRAM2, write to BRAM1
// ... and so on
//
// Input is always in BRAM1
// Output will be either in the BRAM1 or BRAM2 depending on the stage number. For N=512 it will be in BRAM1 and for N=1024 it will be in BRAM2.
//
// After each stage we have to wait until the butterfly unit finishes processing all data before we can continue to the next stage.
// If we continued to the next stage immediately we'd have the problem that we would be reading from the same BRAM as we're writing the previous stage's output to.
//
// To save resources we share a single butterfly unit between fft, split_fft and merge_fft modules.
// For this reason this module also includes a bunch of signals for the butterfly unit.
//
//////////////////////////////////////////////////////////////////////////////////

module fft#(
    parameter int N = 512
  )(
    input logic clk,
    input logic rst,
    input logic mode,  // 0 = FFT, 1 = IFFT
    input logic start, // Start pulse

    output logic [`BRAM_ADDR_WIDTH-1:0] bram1_addr_a,
    output logic [`BRAM_ADDR_WIDTH-1:0] bram1_addr_b,
    output logic [127:0] bram1_din_a,
    output logic [127:0] bram1_din_b,
    input logic [127:0] bram1_dout_a,
    input logic [127:0] bram1_dout_b,
    output logic bram1_we_a,
    output logic bram1_we_b,

    output logic [`BRAM_ADDR_WIDTH-1:0] bram2_addr_a,
    output logic [`BRAM_ADDR_WIDTH-1:0] bram2_addr_b,
    output logic [127:0] bram2_din_a,
    output logic [127:0] bram2_din_b,
    input logic [127:0] bram2_dout_a,
    input logic [127:0] bram2_dout_b,
    output logic bram2_we_a,
    output logic bram2_we_b,

    output logic done,

    // Signals for external butterfly unit
    output logic btf_mode,
    output logic btf_valid_in,
    output logic [63:0] btf_a_in_real,
    output logic [63:0] btf_a_in_imag,
    output logic [63:0] btf_b_in_real,
    output logic [63:0] btf_b_in_imag,
    output logic signed [4:0] btf_scale_factor,
    output logic [9:0] btf_tw_addr,
    input logic [63:0] btf_a_out_real,
    input logic [63:0] btf_a_out_imag,
    input logic [63:0] btf_b_out_real,
    input logic [63:0] btf_b_out_imag,
    input logic btf_valid_out
  );

  logic [3:0] u, u_2DP; // Will be at most 8 for N=512 and 9 for N=1024
  logic [$clog2(N)-1:0] t;
  logic [$clog2(N):0] m;
  logic [$clog2(N)-1:0] i1;
  logic [$clog2(N)-1:0] j1;
  logic [$clog2(N)-1:0] j, j2;

  assign btf_mode = mode;

  // scale factor should be 0 always, except on the last stage of IIFFT, where we should scale (divide) by N-1
  always_comb begin
    if (mode == 1'b0 || (mode == 1'b1 && u_2DP != $clog2(N)-2))
      btf_scale_factor = 0;
    else
      btf_scale_factor = -($clog2(N)-1);
  end

  logic butterfly_paused; // If high then we pause sending data into butterfly. We need to pause after each stage completes to wait for the remaining operations to finish

  // Since read delay from BRAM is a few cycles we need to also delay the valid signal for the butterfly
  logic butterfly_input_valid;
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(2)) butterfly_input_valid_delay(.clk(clk), .in(butterfly_input_valid), .out(btf_valid_in));

  delay_register #(.BITWIDTH(4), .CYCLE_COUNT(2)) u_delay(.clk(clk), .in(u), .out(u_2DP));

  typedef enum logic [2:0] {
            IDLE,
            RUN_FFT,
            WAIT_FOR_BUTTERFLY,
            DONE
          } state_t;
  state_t state, next_state;

  delay_register #(.BITWIDTH(10), .CYCLE_COUNT(3)) tw_addr_delay(.clk(clk), .in(m + i1), .out(btf_tw_addr));

  // Delay write addresses until butterfly finished operation so we know where to write the values back into BRAM
  logic [$clog2(N)-1:0] write_addr1, write_addr2;
  delay_register #(.BITWIDTH($clog2(N)), .CYCLE_COUNT(1+25)) write_addr1_delay(.clk(clk), .in(j), .out(write_addr1));
  delay_register #(.BITWIDTH($clog2(N)), .CYCLE_COUNT(1+25)) write_addr2_delay(.clk(clk), .in(j + t), .out(write_addr2));

  // Router between BRAM1 and BRAM2. On odd stages read from BRAM1 and write to BRAM2, on even stages read from BRAM and write to BRAM1 (we start with stage 1)
  always_comb begin
    if(u % 2 == 1) begin  // Odd stage
      // Read from BRAM1
      bram1_addr_a = j;
      bram1_addr_b = j + t;
      bram1_we_a = 0;
      bram1_we_b = 0;
      bram1_din_a = 0;
      bram1_din_b = 0;

      // Write to BRAM2
      bram2_addr_a = write_addr1;
      bram2_addr_b = write_addr2;
      bram2_din_a = {btf_a_out_real, btf_a_out_imag};
      bram2_din_b = {btf_b_out_real, btf_b_out_imag};
      bram2_we_a = btf_valid_out;
      bram2_we_b = btf_valid_out;
    end
    else begin  // Even stage
      // Read from BRAM2
      bram2_addr_a = j;
      bram2_addr_b = j + t;
      bram2_we_a = 0;
      bram2_we_b = 0;
      bram2_din_a = 0;
      bram2_din_b = 0;

      // Write to BRAM1
      bram1_addr_a = write_addr1;
      bram1_addr_b = write_addr2;
      bram1_din_a = {btf_a_out_real, btf_a_out_imag};
      bram1_din_b = {btf_b_out_real, btf_b_out_imag};
      bram1_we_a = btf_valid_out;
      bram1_we_b = btf_valid_out;
    end
  end

  // Register after reading from BRAM/ROM
  always @(posedge clk) begin
    if(u % 2 == 1) begin
      {btf_a_in_real, btf_a_in_imag} <= bram1_dout_a;
      {btf_b_in_real, btf_b_in_imag} <= bram1_dout_b;
    end
    else begin
      {btf_a_in_real, btf_a_in_imag} <= bram2_dout_a;
      {btf_b_in_real, btf_b_in_imag} <= bram2_dout_b;
    end
  end

  always_ff @(posedge clk) begin
    butterfly_input_valid <= state == RUN_FFT && !butterfly_paused;
  end

  logic butterfly_unpause_pulse, butterfly_unpause_pulse_delayed; // When we pause the butterfly we set this high and then delay it for the latency of butterfly. Once the delayed version is high we can unpause
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(1+24)) buttefly_unpause_pulse_delay(.clk(clk), .in(butterfly_unpause_pulse), .out(butterfly_unpause_pulse_delayed));

  always_ff @(posedge clk) begin
    if (rst)
      state <= IDLE;
    else
      state <= next_state;
  end

  always_comb  begin
    next_state = state;

    case(state)
      IDLE:
        if(start)
          next_state = RUN_FFT;
      RUN_FFT:
        if((mode == 1'b0 && j == (N >> 1) - 2 && m == (N >> 1)) || (mode == 1'b1 && j == (N >> 2) - 1 && m == 2))
          next_state = WAIT_FOR_BUTTERFLY;
      WAIT_FOR_BUTTERFLY:
        if(btf_valid_out == 1'b0)  // Wait for butterfly unit to output all data
          next_state = DONE;
      DONE:
        next_state = DONE;
      default:
        next_state = IDLE;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst || state == IDLE) begin
      j1 <= 0;
      j <= 0;
      i1 <= 0;

      t <= mode == 1'b0 ? N >> 2 : 1;
      u <= 1;
      m <= mode == 1'b0 ? 2 : N >> 1;
      j2 <= mode == 1'b0 ? N >> 2 : 1;

      butterfly_paused <= 1'b0;
      butterfly_unpause_pulse <= 1'b0;
    end
    else if (butterfly_paused) begin
      // While butterfly is paused we just wait for the unpause signal

      butterfly_unpause_pulse <= 1'b0;  // Reset pulse signal

      // Unpause butterfly
      if(butterfly_unpause_pulse_delayed == 1'b1) begin
        butterfly_paused <= 1'b0;

        u <= u + 1; // Only increment stage counter (u) after the pause to make sure reading/writing from BRAM is correct
      end
    end
    else begin
      if (j == j2 - 1) begin
        // End of most inner loop

        if (i1 == (m >> 1) - 1) begin
          // End of middle loop

          // Continuing in outer loop
          i1 <= 0;  // Middle Loop reset
          j1 <= 0;  // Middle Loop reset
          j <= 0;   // Inner Loop reset
          m <= mode == 1'b0 ? m << 1 : m >> 1;
          t <= mode == 1'b0 ? t >> 1 : t << 1;
          j2 <= mode == 1'b0 ? t >> 1 : t << 1;

          butterfly_paused <= 1'b1;
          butterfly_unpause_pulse <= 1'b1;
        end
        else begin
          // Continuing in middle loop
          j <= j1 + (t << 1); // Inner Loop reset
          i1 <= i1 + 1;
          j1 <= j1 + (t << 1);
          j2 <= j1 + t*3;
        end
      end
      else begin
        // Continuing in inner loop
        j <= j + 1;
      end
    end
  end

  assign done = state == DONE;

endmodule
