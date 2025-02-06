`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Converts polynomial from coefficient form to NTT form.
//
//////////////////////////////////////////////////////////////////////////////////


module ntt#(
    parameter integer N
  )(
    input logic clk,
    input logic rst_n,

    input logic start, //! Polynomial is valid, NTT can start
    input logic [14:0] input_polynomial[0:N-1], //! Polynomial in coefficient form

    output logic done, //! NTT is done and output_polynomial is valid
    output logic [14:0] output_polynomial[0:N-1] //! Polynomial in NTT form
  );

  logic [14:0] polynomial[0:N-1]; // Intermediate storage for polynomial
  logic [$clog2(N):0] index, index_rev; // For bit reversal
  logic [$clog2(N)-1:0] i, starting_i;
  int stage, stride, address_stride;
  logic [$clog2(N/2)-1:0] butterfly; // Index of the current butterfly operation, in each stage there are N/2 butterfly operations
  logic [$clog2(N)-1:0] address;
  logic [14:0] twiddle_factor;  // twiddle_rom[address]

  typedef enum logic [1:0] {
            IDLE,   // Waiting for start signal
            COPY_BIT_REVERSED, // Copy input polynomial to intermediate storage in bit-reversed order
            NTT, // Perform NTT
            DONE  // NTT is done, copy polynomial to output
          } state_t;
  state_t state, next_state;

  // Instantiate twiddle factor ROM
  twiddle_rom #(.N(N)) twiddle_rom (
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
    reg [15:0] temp;
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
  always_ff @(posedge clk) begin
    case (state)
      IDLE: begin   // Waiting for the start signal
        if (start == 1'b1)
          next_state <= COPY_BIT_REVERSED;

      end
      COPY_BIT_REVERSED: begin // Copy input polynomial to intermediate storage in bit-reversed order. This takes one cycle, so we continue directly to NTT
        next_state <= NTT;
      end
      NTT: begin
        if (stage == $clog2(N)-1 && butterfly >= N/2-2) // Set next_state when we are at the second to last element of the last stage (this accounts for the delay in switching states)
          next_state <= DONE;
        else
          next_state <= NTT;
      end
      DONE: begin
        next_state <= IDLE;
      end
      default: begin
        next_state <= IDLE;
      end
    endcase
  end

  always_comb begin
    case (state)
      IDLE: begin
        done = 0;
      end
      COPY_BIT_REVERSED: begin
        done = 0;

        // Copy coefficients from input to intermediate storage and reverse indices
        // at which they are stored (000 -> 000, 001 -> 100, 010 -> 010, 011 -> 110, ...)
        // Example for N=8:
        // polynomial[3'b000] = input_polynomial[3'b000];
        // polynomial[3'b001] = input_polynomial[3'b100];
        // ...
        // polynomial[3'b110] = input_polynomial[3'b011];
        // polynomial[3'b111] = input_polynomial[3'b111];
        for (index = 0; index < N; index = index + 1) begin
          index_rev = {<<{index}};  // index and index_rev should be [log(N)-1:0] but are [log(N):0] because with the one bit shorter the simulation doesn't start (it's just waiting). For this reason we have the >>1 in the next line to correct the index_rev
          polynomial[index] = input_polynomial[index_rev>>1];
        end

      end

      NTT: begin
        done = 0;
      end

      DONE: begin
        // Copy polynomial from intermediate storage to output
        for (index = 0; index < N; index = index + 1) begin
          output_polynomial[index] = polynomial[index];
        end
        done = 1;
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

      stride <= 1;  // Offset between indices of elements in the same stage
      address_stride <= $clog2(N<<1); // How far to jump in the twiddle factor ROM (stage 1: N/2, stage 2: N/4, ...)

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
        stride <= stride << 1;
        address_stride <= address_stride >> 1;
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
      polynomial[i] <= mod_add(polynomial[i], mod_mult(polynomial[i + stride], twiddle_factor));
      polynomial[i + stride] <= mod_sub(polynomial[i], mod_mult(polynomial[i + stride], twiddle_factor));

    end
  end
endmodule
