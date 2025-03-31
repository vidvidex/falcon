`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Implements both NTT and inverse NTT for positive-wrapped convolution.
// This module is not needed for Falcon, but since I accidentally implemented the wrong NTT
// might as well preserve it, since it could be useful for something else in the future.
//
//  NOTE: this is not optimized and the timing is probably way off.
//
//  Forward NTT: IDLE -> COPY_BIT_REVERSED -> NTT -> COPY(done=1) -> IDLE
//  Inverse NTT: IDLE -> COPY -> NTT -> COPY_BIT_REVERSED(done=1) -> IDLE
//
// This module is based on the Python implementation from https://cryptographycaffe.sandboxaq.com/posts/ntt-02/
// See: scripts/ntt_iter.py
//
// Note: behavior with negative inputs has not been tested and it might not work.
//
//////////////////////////////////////////////////////////////////////////////////


module ntt_positive#(
    parameter int N
  )(
    input logic clk,
    input logic rst_n,

    input logic mode, // 0: NTT, 1: Inverse NTT

    input logic start, //! Polynomial is valid, NTT can start
    input logic [14:0] input_polynomial[N], //! Polynomial in coefficient form

    output logic done, //! NTT is done and output_polynomial is valid
    output logic [14:0] output_polynomial[N] //! Polynomial in NTT form
  );

  logic [14:0] polynomial[N]; // Intermediate storage for polynomial
  logic [$clog2(N):0] index, index_rev; // For bit reversal
  logic [$clog2(N)-1:0] i, starting_i;
  int stage, stride, address_stride;
  logic [$clog2(N/2)-1:0] butterfly; // Index of the current butterfly operation, in each stage there are N/2 butterfly operations
  logic [$clog2(N)-1:0] address;
  logic [14:0] twiddle_factor;  // twiddle_rom[address]
  int n_to_minus1;

  // N^-1 mod 12289 for N=8, 512, 1024
  assign n_to_minus1 =
         N == 8 ? 10753 :
         N == 512 ? 12265 :
         N == 1024 ? 12277 :
         0;

  typedef enum logic[1:0] {
            IDLE,   // Waiting for start signal
            COPY_BIT_REVERSED, // Copy input polynomial to intermediate intermediate or intermediate polynomial to output while reversing the order of the coefficients
            COPY, // Copy input polynomial to intermediate intermediate or intermediate polynomial to output
            NTT // Perform NTT/INTT
          } state_t;
  state_t state, next_state;

  // Instantiate twiddle factor ROM
  twiddle_rom #(.N(N)) twiddle_rom (
                .mode(mode),
                .addr(address),
                .data(twiddle_factor)
              );

  // Modulo 12289 multiplication
  function [14:0] mod_mult(input [14:0] a, b);
    logic [29:0] temp;
    begin
      temp = a * b;
      mod_mult = temp % 12289;
    end
  endfunction

  // Modulo 12289 addition
  function [14:0] mod_add(input [14:0] a, b);
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
  function [14:0] mod_sub(input [14:0] a, b);
    begin
      if (a >= b)
        mod_sub = a - b;
      else
        mod_sub = a + 12289 - b;
    end
  endfunction


  // Modulo 2^k (returns only the k least significant bits)
  function [14:0] mod_pow2(input [14:0] a, k);
    begin
      mod_pow2 = a & ((1 << k) - 1);
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
      state <= IDLE;
    else
      state <= next_state;
  end

  // State machine state changes
  always_comb begin
    case (state)
      IDLE: begin   // Waiting for the start signal
        if (start == 1'b1)

          // For NTT we have to bit reverse now, for INTT we do it at the end
          if(mode == 1'b0)
            next_state = COPY_BIT_REVERSED;
          else
            next_state = COPY;
      end
      COPY_BIT_REVERSED: begin // Copy input polynomial to intermediate storage or from intermediate storage to output polynomial while reversing the order of the coefficients. This takes just one cycle

        // For NTT we go to the NTT state, while for INTT we go to the IDLE state (we reverse at the end)
        if(mode == 1'b0)
          next_state = NTT;
        else
          next_state = IDLE;
      end
      COPY: begin // Copy input polynomial to intermediate storage or from intermediate storage to output polynomial. This takes just one cycle

        // For NTT we go to the IDLE state, while for INTT we go to the NTT state
        if(mode == 1'b0)
          next_state = IDLE;
        else
          next_state = NTT;
      end
      NTT: begin
        if (stage == $clog2(N)-1 && butterfly >= N/2-1) begin // Set next_state when we are at the last-1 element of the last stage

          // For NTT we just copy, for INTT we have to copy and bit reverse
          if(mode == 1'b0)
            next_state = COPY;
          else
            next_state = COPY_BIT_REVERSED;
        end
        else
          next_state = NTT;
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  always_comb begin
    case (state)
      IDLE: begin
        done = 0;
      end
      COPY_BIT_REVERSED: begin

        // For INTT this is the last state
        if(mode == 1'b0)
          done = 0;
        else
          done = 1;

        // Copy coefficients from input to intermediate storage or from intermediate storage to output
        // while reversing the order of the coefficients

        // at which they are stored (000 -> 000, 001 -> 100, 010 -> 010, 011 -> 110, ...)
        // Example for N=8:
        // polynomial[3'b000] = input_polynomial[3'b000];
        // polynomial[3'b001] = input_polynomial[3'b100];
        // ...
        // polynomial[3'b110] = input_polynomial[3'b011];
        // polynomial[3'b111] = input_polynomial[3'b111];
        for (index = 0; index < N; index = index + 1) begin
          index_rev = {<<{index}};  // index and index_rev should be [log(N)-1:0] but are [log(N):0] because with the one bit shorter the simulation doesn't start (it's just waiting). For this reason we have the >>1 in the next line to correct the index_rev

          if(mode == 1'b0)
            polynomial[index_rev>>1] = input_polynomial[index];
          else
            output_polynomial[index] = mod_mult(polynomial[index_rev>>1], n_to_minus1);  // For INTT we have to scale the coefficients by N^-1
        end
      end

      COPY: begin

        // For NTT this is the last state
        if(mode == 1'b0)
          done = 1;
        else
          done = 0;

        // Copy coefficients from input to intermediate storage or from intermediate storage to output
        for (index = 0; index < N; index = index + 1) begin
          if(mode == 1'b0)
            output_polynomial[index] = polynomial[index];
          else
            polynomial[index] = input_polynomial[index];
        end
      end

      NTT: begin
        done = 0;
      end

      default: begin
        done = 0;
      end
    endcase
  end

  // NTT
  always_ff @(posedge clk) begin

    if (state != NTT) begin
      stage <= 0;
      butterfly <= 0;

      if(mode == 1'b0) begin
        stride <= 1;        // Initialize stride (offset between indices of elements in the same stage)
        address_stride <= $clog2(N<<1); // How far to jump in the twiddle factor ROM (stage 1: N/2, stage 2: N/4, ...)
      end
      else begin
        stride <= N >> 1;
        address_stride <= 1;
      end

      address <= 0;

      starting_i <= 0; // Starting value for i in each stage
      i <= 0;
    end
    else begin

      // Calculate address for twiddle factor ROM
      address <= mod_pow2(address + address_stride, $clog2(N>>1));

      // Increment stage when we have processed all elements in the current stage
      if (butterfly == N/2-1) begin
        stage <= stage + 1;

        if(mode == 1'b0) begin
          stride <= stride << 1;
          address_stride <= address_stride >> 1;
        end
        else begin
          stride <= stride >> 1;
          address_stride <= address_stride << 1;
        end
        butterfly <= 0;
      end
      else
        butterfly <= butterfly + 1;

      // Calculate indices for butterfly operation
      if(i == starting_i + stride-1) begin
        starting_i = starting_i + (stride << 1);
        i <= starting_i;
      end
      else
        i <= i + 1;

      // Butterfly operation
      if (mode == 1'b0) begin
        polynomial[i] <= mod_add(polynomial[i], mod_mult(polynomial[i + stride], twiddle_factor));
        polynomial[i + stride] <= mod_sub(polynomial[i], mod_mult(polynomial[i + stride], twiddle_factor));
      end
      else begin
        polynomial[i] <= mod_add(polynomial[i], polynomial[i + stride]);
        polynomial[i + stride] <= mod_mult(mod_sub(polynomial[i], polynomial[i + stride]), twiddle_factor);
      end
    end
  end
endmodule
