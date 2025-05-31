`timescale 1ns / 1ps

module fft#(
    parameter int N = 512 // Number of complex points
  )(
    input logic clk,
    input logic rst,
    input logic mode,  // 0 = FFT, 1 = IFFT
    input logic start, // Start pulse

    output logic [$clog2(N)-1:0] bram1_addr_a,
    output logic [$clog2(N)-1:0] bram1_addr_b,
    output logic [127:0] bram1_din_a,
    output logic [127:0] bram1_din_b,
    input logic [127:0] bram1_dout_a,
    input logic [127:0] bram1_dout_b,
    output logic bram1_we_a,
    output logic bram1_we_b,

    output logic [$clog2(N)-1:0] bram2_addr_a,
    output logic [$clog2(N)-1:0] bram2_addr_b,
    output logic [127:0] bram2_din_a,
    output logic [127:0] bram2_din_b,
    input logic [127:0] bram2_dout_a,
    input logic [127:0] bram2_dout_b,
    output logic bram2_we_a,
    output logic bram2_we_b,

    output logic done
  );

  logic [63:0] tw_real, tw_imag;
  logic [63:0] a_in_real, a_in_imag, b_in_real, b_in_imag;
  logic [63:0] a_out_real, a_out_imag, b_out_real, b_out_imag;
  logic butterfly_output_valid;

  // Since read delay from BRAM is a few cycles we need to also delay the valid signal for the butterfly
  logic butterfly_input_valid, butterfly_input_valid_3DP;
  DelayRegister #(.BITWIDTH(1), .CYCLE_COUNT(3)) butterfly_input_valid_delay(.clk(clk), .in(butterfly_input_valid), .out(butterfly_input_valid_3DP));

  logic [31:0] u, t, m;
  logic [31:0] i1, j1;
  logic [31:0] j, j2;

  logic [31:0] j_delayed; // Debug only to make j and data for butterfly be in sync
  DelayRegister #(.BITWIDTH(32), .CYCLE_COUNT(3)) j_delay(.clk(clk), .in(j), .out(j_delayed));

  typedef enum logic [2:0] {
            IDLE,
            RUN_FFT,  // Run FFT
            WAIT_FOR_BUTTERFLY, // Wait for the butterfly to output all remaining data
            DONE  // FFT is done
          } state_t;
  state_t state, next_state;

  FFTButterfly FFTButterfly(
                 .clk(clk),
                 .in_valid(butterfly_input_valid_3DP),
                 .use_ct(!mode),

                 .a_in_real(a_in_real),
                 .a_in_imag(a_in_imag),
                 .b_in_real(b_in_real),
                 .b_in_imag(b_in_imag),

                 .tw_real(tw_real),
                 .tw_imag(tw_imag),
                 .scale_factor(0),

                 .a_out_real(a_out_real),
                 .a_out_imag(a_out_imag),
                 .b_out_real(b_out_real),
                 .b_out_imag(b_out_imag),

                 .done(butterfly_output_valid)
               );

  // Twiddle factor ROM
  logic [9:0] tw_addr;
  assign tw_addr = m + i1;
  logic [127:0] tw_real_tw_imag;
  fft_twiddle_factors fft_twiddle_factors (
                        .clka(clk),
                        .addra(tw_addr),
                        .douta(tw_real_tw_imag)
                      );

  // Router between BRAM1 and BRAM2
  // On even stages read from BRAM1 and write to BRAM2, on odd stages read from BRAM and write to BRAM1
  always_comb begin
    if(u % 2 == 0) begin  // Even stage
      // Read from BRAM1
      bram1_addr_a = j;
      bram1_addr_b = j + t;
      bram1_we_a = 0;
      bram1_we_b = 0;

      // Write to BRAM2
      bram2_addr_a = write_addr1;
      bram2_addr_b = write_addr2;
      bram2_din_a = {a_out_real, a_out_imag};
      bram2_din_b = {b_out_real, b_out_imag};
      bram2_we_a = butterfly_output_valid;
      bram2_we_b = butterfly_output_valid;
    end
    else begin  // Odd stage
      // Read from BRAM2
      bram2_addr_a = j;
      bram2_addr_b = j + t;
      bram2_we_a = 0;
      bram2_we_b = 0;

      // Write to BRAM1
      bram1_addr_a = write_addr1;
      bram1_addr_b = write_addr2;
      bram1_din_a = {a_out_real, a_out_imag};
      bram1_din_b = {b_out_real, b_out_imag};
      bram1_we_a = butterfly_output_valid;
      bram1_we_b = butterfly_output_valid;
    end
  end

  // Register after reading from BRAM/ROM
  always @(posedge clk) begin
    {a_in_real, a_in_imag} <= bram1_dout_a;
    {b_in_real, b_in_imag} <= bram1_dout_b;
    {a_in_real, a_in_imag} <= bram2_dout_a;
    {b_in_real, b_in_imag} <= bram2_dout_b;

    {tw_real, tw_imag} <= tw_real_tw_imag;
  end

  // Delay write addresses until butterfly finished operation so we know where to write the values back into BRAM
  logic [$clog2(N):0] write_addr1, write_addr2;
  DelayRegister #(.BITWIDTH($clog2(N)+1), .CYCLE_COUNT(1+22)) write_addr1_delay(.clk(clk), .in(j), .out(write_addr1));
  DelayRegister #(.BITWIDTH($clog2(N)+1), .CYCLE_COUNT(1+22)) write_addr2_delay(.clk(clk), .in(j + t), .out(write_addr2));

  assign butterfly_input_valid = state == RUN_FFT;

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
        if(j == N - 2 && m == N)
          next_state = WAIT_FOR_BUTTERFLY;
      WAIT_FOR_BUTTERFLY:
        if(butterfly_output_valid == 1'b0)  // Wait for butterfly unit to output all data
          next_state = DONE;
      DONE:
        next_state = DONE;
      default:
        next_state = IDLE;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst || state != RUN_FFT) begin
      j1 <= 0;
      j <= 0;
      i1 <= 0;

      t <= N >> 1;
      u <= 1;
      m <= 2;
      j2 <= N >> 1;

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
          u <= u + 1;
          m <= m << 1;
          t <= t >> 1;
          j2 <= t >> 1;
        end
        else begin
          // Continuing in middle loop
          j <= j1 + (t << 1); // Inner Loop reset
          i1 <= i1 + 1;
          j1 <= j1 + t*2;
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
