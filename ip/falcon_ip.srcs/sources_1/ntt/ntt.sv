`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Implements both NTT and inverse NTT for negative-wrapped convolution.
// Because we are never going to use both at the same time, we can save resources by reusing the same module.
//
// Uses 2 BRAMs to store the data. During any stage it will read from one BRAM and write to the other.
// Stage 1: read from BRAM1, write to BRAM2
// Stage 2: read from BRAM2, write to BRAM1
// ... and so on
//
// Input is always in BRAM1
// Output will be either in the BRAM1 or BRAM2 depending on the stage number. For N=512 it will be in BRAM2 and for N=1024 it will be in BRAM1.
//
// Forward NTT: IDLE -> NTT <-> NTT_WAIT_FOR_MULTIPLY -> DONE -> IDLE
// Inverse NTT: IDLE -> NTT <-> NTT_WAIT_FOR_MULTIPLY -> DONE -> IDLE
//
// The module is based on the reference C implementation via a modified Python version to allow for easier implementing
// See also utilities/ntt_from_reference_C.py and utilities/ntt_from_reference_C_for_FPGA.py
//
// This module uses Montgomery reduction to optimize calculation of a*b mod q. Should you not want to use it you have to compute different twiddle factors (with R=1).
// They are computed with utilities/NTT_negative_compute_twiddle_factors.py (supports both with and without Montgomery reduction)
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

  logic [$clog2(N)-1:0] stage_counter; // Incrementing counter that only counts at which stage we are (0..N-1)
  logic [$clog2(N):0] stage, counter, counter_max;
  logic [$clog2(N)-1:0] stride, butterfly;
  logic [$clog2(N)-1:0] i; // Index for butterfly unit
  logic signed [$clog2(N)-1:0] group;

  logic [14:0] twiddle_factor, twiddle_factor_delayed;
  delay_register #(.BITWIDTH(15), .CYCLE_COUNT(3)) twiddle_factor_delay(.clk(clk), .in(twiddle_factor), .out(twiddle_factor_delayed));
  logic [9:0] twiddle_address;

  logic signed [14:0] mod_mult_a, mod_mult_b, mod_mult_passthrough_in;
  logic [$clog2(N):0] mod_mult_index1_in, mod_mult_index1_in_delayed, mod_mult_index2_in, mod_mult_index2_in_delayed;
  logic mod_mult_valid_in, mod_mult_valid_in_delayed;
  logic signed [14:0] mod_mult_result, mod_mult_passthrough_out;
  logic [$clog2(N):0] mod_mult_index1_out, mod_mult_index2_out;
  logic mod_mult_valid_out, mod_mult_last;

  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(3)) mod_mult_valid_in_delay(.clk(clk), .in(mod_mult_valid_in), .out(mod_mult_valid_in_delayed));
  delay_register #(.BITWIDTH($clog2(N)+1), .CYCLE_COUNT(3)) mod_mult_index1_in_delay(.clk(clk), .in(mod_mult_index1_in), .out(mod_mult_index1_in_delayed));
  delay_register #(.BITWIDTH($clog2(N)+1), .CYCLE_COUNT(3)) mod_mult_index2_in_delay(.clk(clk), .in(mod_mult_index2_in), .out(mod_mult_index2_in_delayed));
  logic bram_write_complete; // This is high for one clock cycle when we've written all coefficients to the BRAM. It is essentially mod_mult_last but delayed to account for the extra cycle needed for writing to the BRAM

  // "logical" signals that get assigned to different BRAM banks depending on the stage
  // These are routed to either bram1, bram2
  logic [$clog2(N)-1:0] read_addr1, read_addr2, write_addr1, write_addr2;
  logic signed [14:0] read_data1, read_data2, write_data1, write_data2;
  logic write_enable1, write_enable2;

  // Signals for scaling pipeline
  logic signed [14:0] scale_data1_in, scale_data2_in, scale_mod_mult1, scale_mod_mult2;
  logic signed [28:0] scale_a_times_b1, scale_a_times_b2;
  logic [$clog2(N)-1:0] scale_addr1_in, scale_addr2_in, scale_addr1_1, scale_addr2_1, scale_addr1_out, scale_addr2_out;
  logic scale_we_a_in, scale_we_b_in, scale_we_a_1, scale_we_b_1, scale_we_a_out, scale_we_b_out;
  logic signed [14:0] scale_temp1, scale_temp2;

  logic bram11_read_part, bram12_read_part; // 0 = read from top half of the BRAM, 1 = read from bottom half
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(3)) bram11_read_part_delay(.clk(clk), .in(i >= N/2), .out(bram11_read_part));
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(3)) bram12_read_part_delay(.clk(clk), .in(i+stride >= N/2), .out(bram12_read_part));

  // (pow(N, -1, 12289) * R) % 12289 for N=8, 512, 1024
  // R = pow(2, 16, 12289) (constant for Montgomery multiplication), if not using Montgomery reduction R=1
  int intt_scale_factor;
  assign intt_scale_factor =
         N == 8 ? 10753 :
         N == 512 ? 12265 :
         N == 1024 ? 12277 :
         0;

  typedef enum logic [2:0] {
            IDLE,   // Waiting for start signal
            NTT, // Perform NTT/INTT
            NTT_WAIT_FOR_MULTIPLY, // Wait for multiplication to finish, because it is pipelined it will take a few cycles longer than NTT
            DONE  // Output "done" pulse
          } state_t;
  state_t state, next_state;

  ntt_twiddle_factor_rom twiddle_rom_ntt (
                           .clk(clk),
                           .mode(mode),
                           .addr(twiddle_address),
                           .data(twiddle_factor)
                         );

  assign twiddle_address = mode == 1'b0 ? stage + group:  (stage >> 1) + group;

  mod_mult_ntt #(
                 .N(N)
               )mod_mult(
                 .clk(clk),
                 .rst_n(rst_n),
                 .a(mod_mult_a),
                 .b(mod_mult_b),
                 .valid_in(mod_mult_valid_in_delayed),
                 .index1_in(mod_mult_index1_in_delayed),
                 .index2_in(mod_mult_index2_in_delayed),
                 .passthrough_in(mod_mult_passthrough_in),
                 .result(mod_mult_result),
                 .valid_out(mod_mult_valid_out),
                 .last(mod_mult_last),
                 .index1_out(mod_mult_index1_out),
                 .index2_out(mod_mult_index2_out),
                 .passthrough_out(mod_mult_passthrough_out)
               );

  // Modulo 12289 addition
  function [14:0] mod_add(input logic signed [14:0] a, b);
    logic signed [15:0] temp;
    begin
      temp = a + b;
      if (temp >= 12289)
        mod_add = temp - 12289;
      else
        mod_add = temp;
    end
  endfunction

  // Modulo 12289 subtraction
  function [14:0] mod_sub(input logic signed [14:0] a, b);
    begin
      if (a >= b)
        mod_sub = a - b;
      else
        mod_sub = a + 12289 - b;
    end
  endfunction

  // State machine state changes
  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin   // Waiting for the start signal
        if (start == 1'b1)
          next_state = NTT;
      end
      NTT: begin
        if (butterfly == N >> 1)
          next_state = NTT_WAIT_FOR_MULTIPLY;
      end
      NTT_WAIT_FOR_MULTIPLY: begin // Wait for mod_mult to finish and coefficient to be written to BRAM
        // When we write everything to BRAM we go to DONE if we're finished or to the next stage of NTT if we're not
        if(bram_write_complete == 1'b1)
          if(butterfly - 1 == N >> 1 && ((mode == 1'b0 && stride == 1) || (mode == 1'b1 && stride == N >> 1)))
            next_state = DONE;
          else
            next_state = NTT;
      end
      DONE: begin
        next_state = DONE;
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  // Pipeline for scaling output of INTT
  always_ff @(posedge clk) begin

    // Stage 1: Multiply by scale factor
    scale_a_times_b1 <= scale_data1_in * intt_scale_factor;
    scale_a_times_b2 <= scale_data2_in * intt_scale_factor;
    scale_addr1_1 <= scale_addr1_in;
    scale_addr2_1 <= scale_addr2_in;
    scale_we_a_1 <= scale_we_a_in;
    scale_we_b_1 <= scale_we_b_in;

    // Stage 2: Modulo 12289
    scale_temp1 = scale_a_times_b1 % 12289;
    scale_temp2 = scale_a_times_b2 % 12289;
    scale_mod_mult1 <= scale_temp1 < 0 ? scale_temp1 + 12289 : scale_temp1; // Make sure the result is positive
    scale_mod_mult2 <= scale_temp2 < 0 ? scale_temp2 + 12289 : scale_temp2; // Make sure the result is positive
    scale_addr1_out <= scale_addr1_1;
    scale_addr2_out <= scale_addr2_1;
    scale_we_a_out <= scale_we_a_1;
    scale_we_b_out <= scale_we_b_1;
  end

  // Output decision
  always_comb begin
    done = 1'b0;

    if(state == DONE) begin

      if(mode == 1'b0)  // For NTT we just set done to 1
        done = 1'b1;
      else begin  // For INTT we set done to 1 when the scaling pipeline is done
        if(scale_we_a_out == 1'b0 && scale_we_b_out == 1'b0)
          done = 1'b1;
        else
          done = 1'b0;
      end
    end
  end

  // Determine which signals are used to read/write to the BRAMs
  // stage 0: read from bram1, write to bank2
  // stage 1: read from bank2, write to bank1
  // stage 2: read from bank1, write to bank2
  // ...
  // for N=512 the final result is in bank2, for N=1024 it is in bank1
  always_comb begin

    bram1_addr_a = 0;
    bram1_din_a = 0;
    bram1_we_a = 0;
    bram1_addr_b = 0;
    bram1_din_b = 0;
    bram1_we_b = 0;

    bram2_addr_a = 0;
    bram2_din_a = 0;
    bram2_we_a = 0;
    bram2_addr_b = 0;
    bram2_din_b = 0;
    bram2_we_b = 0;

    scale_data1_in = 0;
    scale_data2_in = 0;
    scale_addr1_in = 0;
    scale_addr2_in = 0;
    scale_we_a_in = 0;
    scale_we_b_in = 0;

    if(stage_counter % 2 == 0) begin        // When stage_counter is even we read from bank1
      bram1_addr_a = read_addr1;
      bram1_addr_b = read_addr2;
    end
    else begin       // When stage_counter is odd we read from bank2
      bram2_addr_a = read_addr1;
      bram2_addr_b = read_addr2;
    end

    if((mode == 1'b1 && stage_counter == $clog2(N)-1)|| scale_we_a_out == 1'b1 || scale_we_b_out == 1'b1) begin // In the last stage of INTT we send output through scaling pipeline. We also keep this active as long as there is output of scaling pipeline

      // Input into scaling pipeline
      scale_data1_in = write_data1;
      scale_data2_in = write_data2;
      scale_addr1_in = write_addr1;
      scale_addr2_in = write_addr2;
      scale_we_a_in = write_enable1;
      scale_we_b_in = write_enable2;

      // Output from scaling pipeline
      if(N == 512) begin
        bram2_addr_a = scale_addr1_out;
        bram2_din_a = scale_mod_mult1;
        bram2_we_a = scale_we_a_out;
        bram2_addr_b = scale_addr2_out;
        bram2_din_b = scale_mod_mult2;
        bram2_we_b = scale_we_b_out;
      end
      else begin
        bram1_addr_a = scale_addr1_out;
        bram1_din_a = scale_mod_mult1;
        bram1_we_a = scale_we_a_out;
        bram1_addr_b = scale_addr2_out;
        bram1_din_b = scale_mod_mult2;
        bram1_we_b = scale_we_b_out;
      end
    end
    else begin  // In all other cases we just directly switch between the BRAM banks
      if(stage_counter % 2 == 0) begin // When stage_counter is even we write to bank2
        bram2_addr_a = write_addr1;
        bram2_din_a = write_data1;
        bram2_we_a = write_enable1;
        bram2_addr_b = write_addr2;
        bram2_din_b = write_data2;
        bram2_we_b = write_enable2;
      end
      else begin          // When stage_counter is odd we write to bank1
        bram1_addr_a = write_addr1;
        bram1_din_a = write_data1;
        bram1_we_a = write_enable1;
        bram1_addr_b = write_addr2;
        bram1_din_b = write_data2;
        bram1_we_b = write_enable2;
      end
    end
  end

  always_ff @(posedge clk) begin
    if(stage_counter == 0 && state != IDLE) begin  // Read from bram1 when stage_counter == 0
      if(mode == 1'b0) begin
        read_data1 <= bram1_dout_a[64+14:64];
        read_data2 <= bram1_dout_a[14:0];
      end
      else begin
        read_data1 <= bram11_read_part ? bram1_dout_a[14:0] : bram1_dout_a[64+14:64];
        read_data2 <= bram12_read_part ? bram1_dout_b[14:0] : bram1_dout_b[64+14:64];
      end
    end
    else begin // Read from bank1/bank2 when stage_counter > 0
      if(stage_counter % 2 == 0) begin        // When stage_counter is even we read from bank1
        read_data1 <= bram1_dout_a;
        read_data2 <= bram1_dout_b;
      end
      else begin       // When stage_counter is odd we read from bank2
        read_data1 <= bram2_dout_a;
        read_data2 <= bram2_dout_b;
      end
    end
  end

  // Next state control
  always_ff @(posedge clk) begin
    if (rst_n == 1'b0)
      state <= IDLE;
    else
      state <= next_state;
  end

  always_ff @(posedge clk) begin
    if(rst_n == 1'b0)
      bram_write_complete <= 0;
    else
      bram_write_complete <= mod_mult_last;
  end

  // Assign mod_mult parameters
  always_comb begin

    mod_mult_passthrough_in = 0;

    if (rst_n == 1'b0) begin
      mod_mult_a = 0;
      mod_mult_b = 0;
    end
    else if(state == NTT || state == NTT_WAIT_FOR_MULTIPLY) begin
      mod_mult_a = mode == 1'b0 ? read_data2 : mod_sub(read_data1, read_data2);
      mod_mult_b = twiddle_factor_delayed;
      mod_mult_passthrough_in = mode == 1'b0 ? read_data1 : mod_add(read_data1, read_data2);
    end
    else begin
      mod_mult_a = 0;
      mod_mult_b = 0;
    end
  end

  // NTT
  always_ff @(posedge clk) begin

    if (rst_n == 1'b0) begin
      read_addr1 <= 0;
      read_addr2 <= 0;
      mod_mult_valid_in <= 0;
      mod_mult_index1_in <= 0;
      mod_mult_index2_in <= 0;
    end

    case (state)
      NTT: begin

        read_addr1 <= (mode == 1'b1 && stage_counter == 0 && state != IDLE) ? (i % (N/2)) : i;
        read_addr2 <= (mode == 1'b1 && stage_counter == 0 && state != IDLE) ? (i + stride) % (N/2) : (i + stride);

        if (mode == 1'b0) begin
          mod_mult_valid_in <= 1'b1;
          mod_mult_index1_in <= i;
          mod_mult_index2_in <= i + stride;
        end
        else begin
          mod_mult_valid_in <= 1'b1;
          mod_mult_index1_in <= i;
          mod_mult_index2_in <= i + stride;
        end
      end

      NTT_WAIT_FOR_MULTIPLY: begin
        mod_mult_valid_in <= 0;
        mod_mult_index1_in <= 0;
        mod_mult_index2_in <= 0;
      end
    endcase

    // If there is valid output from mod_mult for main NTT operation we store the result
    if((state == NTT || state == NTT_WAIT_FOR_MULTIPLY) && mod_mult_valid_out == 1'b1) begin

      write_addr1 <= mod_mult_index1_out;
      write_addr2 <= mod_mult_index2_out;
      write_enable1 <= 1'b1;
      write_enable2 <= 1'b1;

      if (mode == 1'b0) begin
        write_data1 <= mod_add(mod_mult_passthrough_out, mod_mult_result);
        write_data2 <= mod_sub(mod_mult_passthrough_out, mod_mult_result);
      end
      else begin
        write_data1 <= mod_mult_passthrough_out;
        write_data2 <= mod_mult_result;
      end
    end
    else begin
      write_enable1 <= 1'b0;
      write_enable2 <= 1'b0;
    end
  end

  // Compute NTT parameters
  always_ff @(posedge clk) begin

    // Reset/initialize. We do it like this and not with the reset signal because at that point "mode" might not be set yet
    if (state != NTT && state != NTT_WAIT_FOR_MULTIPLY) begin
      stage = mode == 1'b0 ? 1 : N;
      stride = mode == 1'b0 ? N >> 1 : 1;
      counter_max = mode == 1'b0 ? N >> 1 : 1;
      counter = mode == 1'b0 ? 0 : 1;
      butterfly = 1;
      group = 0;
      i = 0;

      stage_counter = 0;
    end

    // Logic for moving to next stage of NTT (here we set some values, but they might be overridden in the next if
    if (state == NTT_WAIT_FOR_MULTIPLY && bram_write_complete == 1'b1) begin
      if (mode == 1'b0) begin
        stage = stage << 1;
        stride = stride >> 1;
        group = -1;
        counter_max = counter_max >> 1;
        counter = N;
        i = 0;
      end
      else begin
        stage = stage >> 1;
        stride = stride << 1;
        group = 0;
        counter_max = counter_max << 1;
        counter = 0;
        i = -1;
      end
      butterfly = 0;

      stage_counter = stage_counter + 1;
    end

    // Logic that we execute on every run of NTT as well as on the last cycle of NTT_WAIT_FOR_MULTIPLY
    if (state == NTT || (state == NTT_WAIT_FOR_MULTIPLY && bram_write_complete == 1'b1)) begin
      if (counter >= counter_max) begin
        group = group + 1;
        i = group * (stride << 1);
        counter = 1;
      end
      else begin
        i = i + 1;
        counter = counter + 1;
      end
      butterfly = butterfly + 1;
    end
  end

endmodule
