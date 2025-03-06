`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
//
//
//////////////////////////////////////////////////////////////////////////////////


module shake256_absorb(
    input logic clk,
    input logic  rst, //! Active high
    input logic [15:0]  inputlen_InBytes, //! Message length in bytes. If message is less than 64 bits, then the most significant bits are 0s.
    input logic [63:0]  din_64bit_raw,
    input logic din_valid, //! This signal is provided by a data source to indicate that din_64bit_raw is valid
    output reg ready,  //! When this signal is high, that means Keccak is ready to absorb.
    output wire [63:0]  data_in_padded, //! This is properly processed data that ill get written into state buffer.
    output reg data_in_padded_valid,   //! Used to write processed 64-bit data to the state buffer.
    output reg call_keccak_f1600, //! This signal is used to start Keccak-f1600 on the state variable
    input logic keccak_round_complete,  //! This signal comes from Keccak-f1600 after its completion
    output logic done  //! Becomes 1 when the entire input is absorbed.
  );

  reg [15:0] messageLen_InBytes;
  reg dec_messageLen;
  reg [7:0] rate_counter;
  reg rst_rate_counter, inc_rate_counter;
  wire messageLen_lt_8, messageLen_lte_8, rate_counter_eq, last_rate_byte;

  typedef enum logic [2:0] {
            IDLE,
            ABSORB,
            CONSUME_DELIMITED_SUFFIX,
            RATE_COMPLETE,
            FINALIZE
          } state_t;
  state_t state, next_state;

  reg delimitedSuffix_used;
  logic [7:0] delimitedSuffix = 8'h1f;
  logic [7:0] rateInBytes = 8'd136;

  assign data_in_padded[7:0] = (messageLen_lt_8==1'b0) ? din_64bit_raw[7:0] :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]==3'd0) ? delimitedSuffix :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]>3'd0) ? din_64bit_raw[7:0] : 8'd0;
  assign data_in_padded[15:8] = (messageLen_lt_8==1'b0) ? din_64bit_raw[15:8] :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]==3'd1) ? delimitedSuffix :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]>3'd1) ? din_64bit_raw[15:8] :	8'd0;
  assign data_in_padded[23:16] = (messageLen_lt_8==1'b0) ? din_64bit_raw[23:16] :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]==3'd2) ? delimitedSuffix :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]>3'd2) ? din_64bit_raw[23:16] : 8'd0;
  assign data_in_padded[31:24] = (messageLen_lt_8==1'b0) ? din_64bit_raw[31:24] :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]==3'd3) ? delimitedSuffix :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]>3'd3) ? din_64bit_raw[31:24] : 8'd0;
  assign data_in_padded[39:32] = (messageLen_lt_8==1'b0) ? din_64bit_raw[39:32] :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]==3'd4) ? delimitedSuffix :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]>3'd4) ? din_64bit_raw[39:32] : 8'd0;
  assign data_in_padded[47:40] = (messageLen_lt_8==1'b0) ? din_64bit_raw[47:40] :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]==3'd5) ? delimitedSuffix :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]>3'd5) ? din_64bit_raw[47:40] : 8'd0;
  assign data_in_padded[55:48] = (messageLen_lt_8==1'b0) ? din_64bit_raw[55:48] :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]==3'd6) ? delimitedSuffix :
         (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]>3'd6) ? din_64bit_raw[55:48] : 8'd0;
  wire [7:0] din_proce_temp = (messageLen_lt_8==1'b0) ? din_64bit_raw[63:56] :
       (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]==3'd7) ? delimitedSuffix :
       (delimitedSuffix_used==1'b0 && messageLen_InBytes[2:0]>3'd7) ? din_64bit_raw[63:56] : 8'd0;
  assign data_in_padded[63:56] = (last_rate_byte) ? {1'b1,din_proce_temp[6:0]} : din_proce_temp;


  always_ff @(posedge clk) begin
    if(rst)
      messageLen_InBytes <= inputlen_InBytes;
    else if(dec_messageLen==1'b1 && messageLen_lt_8==1'b0)
      messageLen_InBytes <= messageLen_InBytes - 8;
    else
      messageLen_InBytes <= messageLen_InBytes;
  end

  always_ff @(posedge clk) begin
    if(rst)
      delimitedSuffix_used <= 1'b0;
    else if(delimitedSuffix_used==1'b0 && messageLen_lt_8==1'b1 && state==CONSUME_DELIMITED_SUFFIX) // Note: delimitedSuffix is used only in state=2 (during the first cycle).
      delimitedSuffix_used <= 1'b1;
    else
      delimitedSuffix_used <= delimitedSuffix_used;
  end

  always_ff @(posedge clk) begin
    if(rst)
      rate_counter <= 8'd0;
    else if(rst_rate_counter)
      rate_counter <= 8'd0;
    else if(inc_rate_counter)
      rate_counter <= rate_counter + 8'd8;
    else
      rate_counter <= rate_counter;
  end


  // When message length is less than 8 bytes
  assign messageLen_lt_8 = (messageLen_InBytes < 16'd8) ? 1'b1 : 1'b0;
  assign messageLen_lte_8 = (messageLen_InBytes <= 16'd15) ? 1'b1 : 1'b0;
  assign rate_counter_eq = (rate_counter==(rateInBytes-8'd8)) ? 1'b1 : 1'b0;
  assign last_rate_byte = (messageLen_lt_8==1'b1 && rate_counter_eq==1'b1) ? 1'b1 : 1'b0;

  always_ff @(posedge clk) begin
    if(rst)
      state <= IDLE;
    else
      state <= next_state;
  end

  always_comb begin
    case(state)
      IDLE: begin // Reset state
        ready = 1;
        rst_rate_counter = 1;
        inc_rate_counter = 0;
        dec_messageLen = 0;
        data_in_padded_valid = 0;
        call_keccak_f1600 = 0;
      end
      ABSORB: begin // Absorb 8 bytes every cycle; Stays in this state till {rate_counter=rateInBytes-8; or remaining message len is <8 bytes}
        ready = 1;
        rst_rate_counter = 0;
        call_keccak_f1600 = 0;
        if(din_valid) begin
          inc_rate_counter = 1;
          data_in_padded_valid = 1;
        end
        else begin
          inc_rate_counter = 0;
          data_in_padded_valid = 0;
        end
        if(din_valid==1'b1)
          dec_messageLen = 1;
        else
          dec_messageLen = 0;
      end
      CONSUME_DELIMITED_SUFFIX: begin // Visited when messageLen was < rate in ABSORB ; Stay in this state till {rate_counter=rateInBytes-8}. delimitedSuffix_used is used in this state.
        ready = 1;
        rst_rate_counter = 0;
        call_keccak_f1600 = 0;
        inc_rate_counter = 1;
        data_in_padded_valid = 1;
        dec_messageLen = 0;
      end
      RATE_COMPLETE: begin // Visited after ABSORB when rate_counter completes the specified rate. Calls keccak-f1600
        ready = 0;
        rst_rate_counter = 1;
        inc_rate_counter = 0;
        dec_messageLen = 0;
        data_in_padded_valid = 0;
        call_keccak_f1600 = 1;
      end

      FINALIZE: begin // Absorb complete
        ready = 1;
        rst_rate_counter = 1;
        inc_rate_counter = 0;
        dec_messageLen = 0;
        data_in_padded_valid = 0;
        call_keccak_f1600 = 0;
      end
      default: begin // Reset state
        ready = 1;
        rst_rate_counter = 1;
        inc_rate_counter = 0;
        dec_messageLen = 0;
        data_in_padded_valid = 0;
        call_keccak_f1600 = 0;
      end
    endcase
  end

  always_comb begin
    case(state)
      IDLE:
        next_state = ABSORB;
      ABSORB: begin
        if(rate_counter_eq)
          next_state = RATE_COMPLETE;
        else if(messageLen_lte_8)
          next_state = CONSUME_DELIMITED_SUFFIX;
        else
          next_state = ABSORB;
      end
      CONSUME_DELIMITED_SUFFIX: begin
        if(rate_counter_eq)
          next_state = RATE_COMPLETE;
        else
          next_state = CONSUME_DELIMITED_SUFFIX;
      end
      RATE_COMPLETE: begin
        if(messageLen_lt_8 && keccak_round_complete && delimitedSuffix_used)
          next_state = FINALIZE;
        else if(messageLen_lt_8 && keccak_round_complete && delimitedSuffix_used==1'b0) // This is a special case: happens when message length is a multiple of keccak_rate. The delimitedSuffix and following 0s need to be consumed next.
          next_state = CONSUME_DELIMITED_SUFFIX;
        else if(keccak_round_complete)
          next_state = ABSORB;
        else
          next_state = RATE_COMPLETE;
      end

      FINALIZE:
        next_state = FINALIZE;
      default:
        next_state = IDLE;
    endcase
  end

  assign done = (state==4'd4) ? 1'b1 : 1'b0;

endmodule
