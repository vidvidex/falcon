`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements split_fft
//
// Works for all powers of 2 smaller or equal to N (parameter "size")
//
// In the reference C implementation the function has 3 parameters:
// - f (input)
// - f0 (output)
// - f1 (output)
// Because each of the outputs is half the size of input this module is designed so that both outputs are in the same BRAM.
// BRAM 1 is always input and BRAM 2 is always output.
// The first half of BRAM 2 is for f0 and the second half for f1. Half in this case refers to "size"/2, not "N"/2
//
//          ---------------------------------------------------------------------------------
// BRAM 1:  |   0   |   1   |   2  |   3   |      ...           | size/2-2    | size/2-1    |
//          | f[0]  | f[1]  | f[2] | f[3]  |                    | f[size/2-2] | f[size/2-1] |   (total length = "size"/2)
//          ---------------------------------------------------------------------------------
//
//          ---------------------------------------------------------------------------------
// BRAM 2:  |   0   |   1   | ...  | size/4-1     | size/4 | size/4 +1 | ... | size/2-1     |
//          | f0[0] | f0[1] |      | f0[size/4-1] | f1[0]  | f1[1]     |     | f1[size/4-1] |   (total length = "size"/2)
//          ---------------------------------------------------------------------------------
//
// When size is less than N/2 there will be empty space at the end of each BRAM
//
// To save resources we share a single butterfly unit between fft, split_fft and merge_fft modules.
// For this reason this module also includes a bunch of signals for the butterfly unit.
//
//////////////////////////////////////////////////////////////////////////////////


module split_fft#(
    parameter int N //
  )(
    input logic clk,
    input logic rst,

    input logic [$clog2(N):0] size, // Size of input (number of total real and complex values together, size = 1024 means 512 real and 512 imaginary values). Must be <= N
    input logic start,

    output logic [$clog2(N)-2:0] bram1_addr_a,
    output logic [$clog2(N)-2:0] bram1_addr_b,
    output logic [127:0] bram1_din_a,
    output logic [127:0] bram1_din_b,
    input logic [127:0] bram1_dout_a,
    input logic [127:0] bram1_dout_b,
    output logic bram1_we_a,
    output logic bram1_we_b,

    output logic [$clog2(N)-2:0] bram2_addr_a,
    output logic [$clog2(N)-2:0] bram2_addr_b,
    output logic [127:0] bram2_din_a,
    output logic [127:0] bram2_din_b,
    input logic [127:0] bram2_dout_a,
    input logic [127:0] bram2_dout_b,
    output logic bram2_we_a,
    output logic bram2_we_b,

    output logic done,

    // Signals for external butterfly unit
    output logic btf_mode,
    output logic btf_in_valid,
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
    input logic btf_out_valid
  );

  assign btf_mode = 1'b1; // For split_fft we always need mode = 1 (IFFT)
  assign btf_scale_factor = -1;

  logic [$clog2(N/4)-1:0] u, u_delayed; // Counter over the input. Will be at most N/4. We need the delayed version to know where to write the butterfly output
  delay_register #(.BITWIDTH($clog2(N/4)), .CYCLE_COUNT(27)) u_delay(.clk(clk), .in(u), .out(u_delayed));

  typedef enum logic [2:0] {
            IDLE,
            RUN,  // Run FFT
            WAIT_FOR_BUTTERFLY_START, // Wait for the butterfly to start outputting data
            WAIT_FOR_BUTTERFLY_END, // Wait for the butterfly to finish outputting all data
            DONE  // FFT is done, immediately goes back to IDLE
          } state_t;
  state_t state, next_state;

  logic butterfly_input_valid;
  delay_register #(.BITWIDTH(1), .CYCLE_COUNT(3)) butterfly_input_valid_delay(.clk(clk), .in(butterfly_input_valid), .out(btf_in_valid));

  logic [9:0] tw_addr;
  delay_register #(.BITWIDTH(10), .CYCLE_COUNT(3)) tw_addr_delay(.clk(clk), .in(tw_addr), .out(btf_tw_addr));

  // Reading inputs from BRAM 1
  always @(posedge clk) begin
    {btf_a_in_real, btf_a_in_imag} <= bram1_dout_a;
    {btf_b_in_real, btf_b_in_imag} <= bram1_dout_b;
  end

  // Writing results to BRAM 2
  always_ff @(posedge clk) begin
    if (btf_out_valid) begin
      bram2_addr_a <= u_delayed;
      bram2_addr_b <= u_delayed + (size >> 2);
      bram2_din_a <= {btf_a_out_real, btf_a_out_imag};
      bram2_din_b <= {btf_b_out_real, btf_b_out_imag};
      bram2_we_a <= 1'b1;
      bram2_we_b <= 1'b1;
    end
    else begin
      bram2_we_a <= 1'b0;
      bram2_we_b <= 1'b0;
    end
  end

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
          next_state = RUN;
      RUN:
        if(u == (size >> 2) - 1)
          next_state = WAIT_FOR_BUTTERFLY_START;
      WAIT_FOR_BUTTERFLY_START:
        if(btf_out_valid == 1'b1)  // Wait for butterfly unit to start outputting data
          next_state = WAIT_FOR_BUTTERFLY_END;
      WAIT_FOR_BUTTERFLY_END:
        if(btf_out_valid == 1'b0)  // Wait for butterfly unit to finish outputting all data
          next_state = DONE;
      DONE:
        next_state = IDLE;
      default:
        next_state = IDLE;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      u <= 0;

      butterfly_input_valid <= 1'b0;
    end
    else if(state == RUN) begin

      butterfly_input_valid <= 1'b1;

      bram1_addr_a <= (u << 1) + 0;
      bram1_addr_b <= (u << 1) + 1;

      bram1_we_a <= 1'b0;
      bram1_we_b <= 1'b0;

      tw_addr <= u + (size >> 1);

      u <= u + 1;
    end
    else begin
      butterfly_input_valid <= 1'b0;
    end
  end

  assign done = state == DONE;

endmodule
