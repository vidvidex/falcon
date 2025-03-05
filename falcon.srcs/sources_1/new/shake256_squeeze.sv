`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Controls squeezing data out of Keccak state
// Will send new data every cycle until the entire rate part of state is squeezed out. Then it will pause for a few cycles, prepare new state and start squeezing again.
// To stop squeezing set rst high.
//
// Note: this file has been heavily modified to fit the needs of the Falcon project. For example in this version we can no longer specify the number of bytes to squeeze out.
//
//////////////////////////////////////////////////////////////////////////////////

// Note: Data output from Keccak squeeze happens in 64-bit words every cycle.
module shake256_squeeze(
    input logic clk,
    input logic rst,  //! Active high

    input logic keccak_round_complete,   //! This signal comes from Keccak-f1600 after its completion

    output logic call_keccak_f1600,//! This signal is used to start Keccak-f1600 on the state variable
    output logic[4:0] state_reg_sel,  //! This is used to select State[0]..to..State[rate] (at most). Note that only 64-bits are output every cycle.
    output logic we_output_buffer,  //! Used to write keccak_state into keccak_output_buffer
    output logic shift_output_buffer,  //! Used to shift the keccak_output_buffer in 64 bits such that one word is output
    output logic data_out_valid,  //! This signal is used to write Keccak-squeeze output
    output logic done   //! Becomes 1 when the entire input is absorbed.
  );

  logic [7:0] rate_counter;
  logic rst_rate_counter, inc_rate_counter;
  logic [3:0] state, next_state;
  logic rate_counter_eq;

  assign rate_counter_eq = (rate_counter=='d128) ? 1'b1 : 1'b0; // 128 = rate - 8 (rate for SHAKE256 is 1088 bits = 136 bytes)
  assign state_reg_sel = rate_counter[7:3];

  always_ff @(posedge clk) begin
    if(rst || rst_rate_counter)
      rate_counter <= 8'd0;
    else if(inc_rate_counter)
      rate_counter <= rate_counter + 8'd8;
    else
      rate_counter <= rate_counter;
  end

  always_ff @(posedge clk) begin
    if(rst)
      state <= 4'd0;
    else
      state <= next_state;
  end

  always_comb begin
    case(state)
      4'd0: begin // Reset state
        rst_rate_counter = 1;
        call_keccak_f1600 = 0;
        inc_rate_counter = 0;
        data_out_valid = 0;
        we_output_buffer = 1;
        shift_output_buffer = 0;
      end

      4'd1: begin // Start squeeze
        rst_rate_counter = 0;
        call_keccak_f1600 = 1;
        inc_rate_counter = 1;
        data_out_valid = 1;
        we_output_buffer = 0;
        shift_output_buffer = 1;
      end

      4'd2: begin
        rst_rate_counter = 1;
        call_keccak_f1600 = 1;
        inc_rate_counter = 0;
        data_out_valid = 0;
        we_output_buffer = 0;
        shift_output_buffer = 0;
      end

      4'd3: begin
        rst_rate_counter = 0;
        call_keccak_f1600 = 0;
        inc_rate_counter = 0;
        data_out_valid = 0;
        we_output_buffer = 1;
        shift_output_buffer = 0;
      end
      default: begin // Reset
        rst_rate_counter = 1;
        call_keccak_f1600 = 0;
        inc_rate_counter = 0;
        data_out_valid = 0;
        we_output_buffer = 0;
        shift_output_buffer = 0;
      end
    endcase
  end

  always_comb begin
    case(state)
      4'd0: begin
        next_state = 4'd1;
      end

      4'd1: begin
        if(rate_counter_eq)
          next_state = 4'd2;
        else
          next_state = 4'd1;
      end

      4'd2: begin
        if(keccak_round_complete)
          next_state = 4'd3;
        else
          next_state = 4'd2;
      end
      4'd3: begin
        next_state = 4'd1;
      end
      default:
        next_state = 4'd0;
    endcase
  end

  assign done = (state==4'd4);

endmodule
