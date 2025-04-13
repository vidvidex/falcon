`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements both NTT and inverse NTT for negative-wrapped convolution.
// Because we are never going to use both at the same time, we can save resources by reusing the same module.
//
// The module accepts the input polynomial in a BRAM and writes the output polynomial to a BRAM.
// Additionally it uses 2 BRAM banks for intermediate storage of the polynomial while performing the NTT.
// The reason for two banks is that we have 2 port BRAMs, so we can read/write two coefficients at the same time,
// but we need to read 2 AND write 2 coefficients at the same time, so we use separate BRAM banks.
//
// Forward NTT: IDLE -> NTT <-> NTT_WAIT_FOR_MULTIPLY -> DONE -> IDLE
// Inverse NTT: IDLE -> NTT <-> NTT_WAIT_FOR_MULTIPLY -> SCALE -> DONE -> IDLE
//
// The module is based on the reference C implementation via a modified Python version to allow for easier implementing
// See also scripts/ntt_from_reference_C.py and scripts/ntt_from_reference_C_for_FPGA.py
//
// Note that the coefficients in the output of this module are in a different order than the coefficients in the Python implementation of Falcon.
// I have no idea why but the final polynomial multiplication still works fine so I think it "cancels out" when running INTT.
//
// This module uses Montgomery reduction to optimize calculation of a*b mod q. Should you not want to use it you have to compute different twiddle factors (with R=1).
// They are computed with scripts/NTT_negative_compute_twiddle_factors.py (supports both with and without Montgomery reduction)
//
//////////////////////////////////////////////////////////////////////////////////


module ntt_negative#(
    parameter int N
  )(
    input logic clk,
    input logic rst_n,

    input logic mode, // 0: NTT, 1: Inverse NTT
    input logic start, //! Data in input BRAM is valid, NTT can start

    output logic [$clog2(N)-1:0] input_bram_addr1, //! Address for input BRAM. Module uses this to select which coefficient to read from input BRAM
    output logic [$clog2(N)-1:0] input_bram_addr2, //! Address for input BRAM. Module uses this to select which coefficient to read from input BRAM
    input logic signed [14:0] input_bram_data1, //! Data that is read from input_bram[input_bram_addr1]
    input logic signed [14:0] input_bram_data2, //! Data that is read from input_bram[input_bram_addr2]

    output logic [$clog2(N)-1:0] output_bram_addr1, //! Address for output BRAM. Module uses this to select where to write the coefficient to output BRAM
    output logic [$clog2(N)-1:0] output_bram_addr2, //! Address for output BRAM. Module uses this to select where to write the coefficient to output BRAM
    output logic signed [14:0] output_bram_data1, //! Data that is written to output_bram[output_bram_addr1]
    output logic signed [14:0] output_bram_data2, //! Data that is written to output_bram[output_bram_addr2]
    output logic output_bram_we1, //! Write enable for output BRAM
    output logic output_bram_we2, //! Write enable for output BRAM

    output logic done //! NTT is done and data in output BRAM is valid
  );

  logic [$clog2(N)-1:0] stage_counter; // Incrementing counter that only counts at which stage we are (0..N-1)
  logic [$clog2(N):0] stage, counter, counter_max;
  logic [$clog2(N)-1:0] stride, butterfly;
  logic [$clog2(N)-1:0] i; // Index for butterfly unit
  logic signed [$clog2(N)-1:0] group;

  logic [14:0] twiddle_factor, twiddle_factor_i;
  logic [9:0] twiddle_address;

  logic signed [14:0] mod_mult_a, mod_mult_b, mod_mult_result;  // Parameters and result for mod_mult module
  logic [$clog2(N):0] mod_mult_index1_in, mod_mult_index1_in_i, mod_mult_index2_in, mod_mult_index2_in_i, mod_mult_index1_out, mod_mult_index2_out; // Input and output indeces from mod_mult module
  logic mod_mult_valid_in, mod_mult_valid_in_i, mod_mult_valid_out, mod_mult_last; // Valid, last signals for mod_mult module
  logic signed [14:0] mod_mult_passthrough_in, mod_mult_passthrough_out; // Passthrough signals for mod_mult module

  logic [$clog2(N):0] intt_scale_index;

  logic bram_write_complete; // This is high for one clock cycle when we've written all coefficients to the BRAM (bank1/bank2/output_bram). It is essentially mod_mult_last but delayed to account for the extra cycle needed for writing to the BRAM


  // Signals for BRAM banks
  logic [$clog2(N)-1:0] bram1_addr_a, bram1_addr_b, bram2_addr_a, bram2_addr_b;
  logic signed [14:0] bram1_data_in_a, bram1_data_in_b, bram2_data_in_a, bram2_data_in_b;
  logic signed [14:0] bram1_data_out_a, bram1_data_out_b, bram2_data_out_a, bram2_data_out_b;
  logic bram1_we_a, bram1_we_b, bram2_we_a, bram2_we_b;

  // "logical" signals that get assigned to different BRAM banks depending on the stage
  // These are routed to either input_bram, output_bram, bram_bank1 or bram_bank2
  logic [$clog2(N)-1:0] read_addr1, read_addr2, write_addr1, write_addr2;
  logic signed [14:0] read_data1, read_data2, write_data1, write_data2;
  logic write_enable1, write_enable2;


  // (pow(N, -1, 12289) * R) % 12289 for N=8, 512, 1024
  // R = pow(2, 16, 12289) (constant for Montgomery multiplication)
  int intt_scale_factor;
  assign intt_scale_factor =
         N == 8 ? 8192 :
         N == 512 ? 128 :
         N == 1024 ? 64 :
         0;

  typedef enum logic [2:0] {
            IDLE,   // Waiting for start signal
            NTT, // Perform NTT/INTT
            NTT_WAIT_FOR_MULTIPLY, // Wait for multiplication to finish, because it is pipelined it will take a few cycles longer than NTT
            SCALE, // Scale the coefficients for INTT
            DONE  // Output "done" pulse
          } state_t;
  state_t state, next_state;

  ntt_negative_twiddle_rom #(
                             .N(N)
                           ) twiddle_rom_ntt (
                             .clk(clk),
                             .mode(mode),
                             .addr(twiddle_address),
                             .data(twiddle_factor)
                           );

  assign twiddle_address = mode == 1'b0 ? stage + group:  (stage >> 1) + group;

  bram #(
         .RAM_DEPTH(N)
       ) bram_bank1 (
         .clk(clk),

         .addr_a(bram1_addr_a),
         .data_in_a(bram1_data_in_a),
         .we_a(bram1_we_a),
         .data_out_a(bram1_data_out_a),

         .addr_b(bram1_addr_b),
         .data_in_b(bram1_data_in_b),
         .we_b(bram1_we_b),
         .data_out_b(bram1_data_out_b)
       );

  bram #(
         .RAM_DEPTH(N)
       ) bram_bank2 (
         .clk(clk),

         .addr_a(bram2_addr_a),
         .data_in_a(bram2_data_in_a),
         .we_a(bram2_we_a),
         .data_out_a(bram2_data_out_a),

         .addr_b(bram2_addr_b),
         .data_in_b(bram2_data_in_b),
         .we_b(bram2_we_b),
         .data_out_b(bram2_data_out_b)
       );

  mod_mult_ntt_negative #(
                          .N(N)
                        )mod_mult(
                          .clk(clk),
                          .rst_n(rst_n),
                          .a(mod_mult_a),
                          .b(mod_mult_b),
                          .valid_in(mod_mult_valid_in_i),
                          .index1_in(mod_mult_index1_in_i),
                          .index2_in(mod_mult_index2_in_i),
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
        // When we write everything to BRAM we go to DONE for NTT and SCALE for INTT if we're finished with NTT or to the next stage of NTT if we're not
        if(bram_write_complete == 1'b1)
          if(butterfly - 1 == N >> 1 && ((mode == 1'b0 && stride == 1) || (mode == 1'b1 && stride == N >> 1)))
            next_state = mode == 1'b0 ? DONE : SCALE;
          else
            next_state = NTT;
      end
      SCALE: begin // Scale coefficients.
        if( bram_write_complete == 1'b1)  // Wait for the scaling pipeline to finish and all coefficients to be written to BRAM
          next_state = DONE;
      end
      DONE: begin
        next_state = IDLE;
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  // Output decision (since we only have one output signal we don't need a whole always_comb for that)
  assign done = state == DONE;

  // Determine which signals are used to read/write to the BRAMs
  // stage 0: read from input_bram, write to bank1
  // stage 1: read from bank1, write to bank2
  // stage 2: read from bank2, write to bank1
  // ...
  // stage log2(N) for NTT | state=SCALE for INTT: read from bank1/bank2, write to output_bram
  always_comb begin

    // Default values
    output_bram_addr1 = 0;
    output_bram_data1 = 0;
    output_bram_we1 = 0;

    output_bram_addr2 = 0;
    output_bram_data2 = 0;
    output_bram_we2 = 0;

    input_bram_addr1 = 0;
    input_bram_addr2 = 0;

    bram1_addr_a = 0;
    bram1_data_in_a = 0;
    bram1_we_a = 0;
    bram1_addr_b = 0;
    bram1_data_in_b = 0;
    bram1_we_b = 0;

    bram2_addr_a = 0;
    bram2_data_in_a = 0;
    bram2_we_a = 0;
    bram2_addr_b = 0;
    bram2_data_in_b = 0;
    bram2_we_b = 0;

    read_data1 = 0;
    read_data2 = 0;

    if(stage_counter == 0 && state != IDLE) begin  // Read from input_bram when stage_counter == 0
      input_bram_addr1 = read_addr1;
      read_data1 = input_bram_data1;

      input_bram_addr2 = read_addr2;
      read_data2 = input_bram_data2;
    end
    else begin // Read from bank1/bank2 when stage_counter > 0
      if(stage_counter % 2 == 0) begin        // When stage_counter is even we read from bank2
        bram2_addr_a = read_addr1;
        read_data1 = bram2_data_out_a;
        bram2_addr_b = read_addr2;
        read_data2 = bram2_data_out_b;
      end
      else begin       // When stage_counter is odd we read from bank1
        bram1_addr_a = read_addr1;
        read_data1 = bram1_data_out_a;
        bram1_addr_b = read_addr2;
        read_data2 = bram1_data_out_b;
      end
    end

    if((mode == 1'b0 && stage_counter == $clog2(N)-1) || (mode == 1'b1 && state == SCALE)) begin      // Write to output_bram when stage_counter == log2(N)-1 (for NTT) and when state == SCALE (for INTT)
      output_bram_addr1 = write_addr1;
      output_bram_data1 = write_data1;
      output_bram_we1 = write_enable1;

      output_bram_addr2 = write_addr2;
      output_bram_data2 = write_data2;
      output_bram_we2 = write_enable2;
    end
    else begin  // Write to bank1/bank2 when stage_counter > 0
      if(stage_counter % 2 == 0) begin        // When stage_counter is even we write to bank1
        bram1_addr_a = write_addr1;
        bram1_data_in_a = write_data1;
        bram1_we_a = write_enable1;

        bram1_addr_b = write_addr2;
        bram1_data_in_b = write_data2;
        bram1_we_b = write_enable2;
      end
      else begin          // When stage_counter is odd we write to bank2
        bram2_addr_a = write_addr1;
        bram2_data_in_a = write_data1;
        bram2_we_a = write_enable1;

        bram2_addr_b = write_addr2;
        bram2_data_in_b = write_data2;
        bram2_we_b = write_enable2;
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

  // BRAM has delay of 1 cycle so we have to delay other signals
  // We can also use this block to delay bram_write_complete, so we know when to change the state
  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      mod_mult_valid_in_i <= 0;
      mod_mult_index1_in_i <= 0;
      mod_mult_index2_in_i <= 0;
      bram_write_complete <= 0;
      twiddle_factor_i <= 0;
    end
    else begin
      mod_mult_valid_in_i <= mod_mult_valid_in;
      mod_mult_index1_in_i <= mod_mult_index1_in;
      mod_mult_index2_in_i <= mod_mult_index2_in;
      bram_write_complete <= mod_mult_last;
      twiddle_factor_i <= twiddle_factor;
    end
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
      mod_mult_b = twiddle_factor_i;
      mod_mult_passthrough_in = mode == 1'b0 ? read_data1 : mod_add(read_data1, read_data2);
    end
    else if(state == SCALE) begin
      mod_mult_a = read_data1;
      mod_mult_b = intt_scale_factor;
    end
    else begin
      mod_mult_a = 0;
      mod_mult_b = 0;
    end
  end

  // NTT
  always_ff @(posedge clk) begin

    if (rst_n == 1'b0) begin
      mod_mult_valid_in <= 0;
      mod_mult_index1_in <= 0;
      mod_mult_index2_in <= 0;

      intt_scale_index <= 0;
    end

    case (state)
      NTT: begin

        read_addr1 <= i;
        read_addr2 <= i+stride;

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

      SCALE: begin
        if(intt_scale_index < N) begin
          read_addr1 <= intt_scale_index;
          mod_mult_valid_in <= 1'b1;
          mod_mult_index1_in <= intt_scale_index;
          intt_scale_index <= intt_scale_index + 1;
        end
        else begin
          mod_mult_valid_in <= 0;
        end
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

    // If there is valid output from mod_mult for main final scaling operation we store the result
    if(state == SCALE && mod_mult_valid_out == 1'b1) begin
      write_addr1 <= mod_mult_index1_out;
      write_data1 <= mod_mult_result;
      write_enable1 <= 1'b1;
    end
    else if(state == SCALE) begin
      write_enable1 <= 1'b0;
    end
  end

  // Compute NTT parameters
  always_ff @(posedge clk) begin

    // Reset/initialize. We do it like this and not with the reset signal because at that point "mode" might not be set yet
    if (state != NTT && state != NTT_WAIT_FOR_MULTIPLY && state != SCALE) begin
      stage       = mode == 1'b0 ? 1 : N;
      stride      = mode == 1'b0 ? N >> 1 : 1;
      counter_max = mode == 1'b0 ? N >> 1 : 1;
      counter     = mode == 1'b0 ? 0 : 1;
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
