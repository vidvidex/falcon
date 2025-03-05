`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
//
//
//////////////////////////////////////////////////////////////////////////////////


module shake256_rounds(
    input logic clk,
    input logic rst,
    input logic [64*25-1:0] state_in,
    output logic [64*25-1:0]state_out,
    output logic we_state_out, //! This signal is 1 for writing 25x64 bit state to the buffer
    output logic final_round
  );

  wire [63:0] round_constant;
  reg [4:0] round_nr;

  wire [64*25-1:0] lanes_in;
  wire [64*25-1:0] lanes_out;

  // 5x5 Lanes are just transpose of 5x5 States. Perform the transpose.
  // for x=0, y=0..4                            // for x=0..4, y=0
  assign lanes_in[63+64*5*0+64*0:64*5*0+64*0] = state_in[63+64*5*0+64*0:64*5*0+64*0];
  assign lanes_in[63+64*5*0+64*1:64*5*0+64*1] = state_in[63+64*5*1+64*0:64*5*1+64*0];
  assign lanes_in[63+64*5*0+64*2:64*5*0+64*2] = state_in[63+64*5*2+64*0:64*5*2+64*0];
  assign lanes_in[63+64*5*0+64*3:64*5*0+64*3] = state_in[63+64*5*3+64*0:64*5*3+64*0];
  assign lanes_in[63+64*5*0+64*4:64*5*0+64*4] = state_in[63+64*5*4+64*0:64*5*4+64*0];
  // for x=1, y=0..4                            // for x=0..4, y=1
  assign lanes_in[63+64*5*1+64*0:64*5*1+64*0] = state_in[63+64*5*0+64*1:64*5*0+64*1];
  assign lanes_in[63+64*5*1+64*1:64*5*1+64*1] = state_in[63+64*5*1+64*1:64*5*1+64*1];
  assign lanes_in[63+64*5*1+64*2:64*5*1+64*2] = state_in[63+64*5*2+64*1:64*5*2+64*1];
  assign lanes_in[63+64*5*1+64*3:64*5*1+64*3] = state_in[63+64*5*3+64*1:64*5*3+64*1];
  assign lanes_in[63+64*5*1+64*4:64*5*1+64*4] = state_in[63+64*5*4+64*1:64*5*4+64*1];
  // for x=2, y=0..4                            // for x=0..4, y=2
  assign lanes_in[63+64*5*2+64*0:64*5*2+64*0] = state_in[63+64*5*0+64*2:64*5*0+64*2];
  assign lanes_in[63+64*5*2+64*1:64*5*2+64*1] = state_in[63+64*5*1+64*2:64*5*1+64*2];
  assign lanes_in[63+64*5*2+64*2:64*5*2+64*2] = state_in[63+64*5*2+64*2:64*5*2+64*2];
  assign lanes_in[63+64*5*2+64*3:64*5*2+64*3] = state_in[63+64*5*3+64*2:64*5*3+64*2];
  assign lanes_in[63+64*5*2+64*4:64*5*2+64*4] = state_in[63+64*5*4+64*2:64*5*4+64*2];
  // for x=3, y=0..4                            // for x=0..4, y=3
  assign lanes_in[63+64*5*3+64*0:64*5*3+64*0] = state_in[63+64*5*0+64*3:64*5*0+64*3];
  assign lanes_in[63+64*5*3+64*1:64*5*3+64*1] = state_in[63+64*5*1+64*3:64*5*1+64*3];
  assign lanes_in[63+64*5*3+64*2:64*5*3+64*2] = state_in[63+64*5*2+64*3:64*5*2+64*3];
  assign lanes_in[63+64*5*3+64*3:64*5*3+64*3] = state_in[63+64*5*3+64*3:64*5*3+64*3];
  assign lanes_in[63+64*5*3+64*4:64*5*3+64*4] = state_in[63+64*5*4+64*3:64*5*4+64*3];
  // for x=4, y=0..4                            // for x=0..4, y=4
  assign lanes_in[63+64*5*4+64*0:64*5*4+64*0] = state_in[63+64*5*0+64*4:64*5*0+64*4];
  assign lanes_in[63+64*5*4+64*1:64*5*4+64*1] = state_in[63+64*5*1+64*4:64*5*1+64*4];
  assign lanes_in[63+64*5*4+64*2:64*5*4+64*2] = state_in[63+64*5*2+64*4:64*5*2+64*4];
  assign lanes_in[63+64*5*4+64*3:64*5*4+64*3] = state_in[63+64*5*3+64*4:64*5*3+64*4];
  assign lanes_in[63+64*5*4+64*4:64*5*4+64*4] = state_in[63+64*5*4+64*4:64*5*4+64*4];


  shake256_round round(
                   .lanes_in(lanes_in),
                   .round_constant(round_constant),
                   .lanes_out(lanes_out)
                 );
  shake256_round_constants constants(
                             .round_nr(round_nr),
                             .round_constant(round_constant)
                           );

  // 5x5 Lanes are just transpose of 5x5 States. Perform the transpose.
  // for x=0, y=0..4                            // for x=0..4, y=0
  assign state_out[63+64*5*0+64*0:64*5*0+64*0] = lanes_out[63+64*5*0+64*0:64*5*0+64*0];
  assign state_out[63+64*5*0+64*1:64*5*0+64*1] = lanes_out[63+64*5*1+64*0:64*5*1+64*0];
  assign state_out[63+64*5*0+64*2:64*5*0+64*2] = lanes_out[63+64*5*2+64*0:64*5*2+64*0];
  assign state_out[63+64*5*0+64*3:64*5*0+64*3] = lanes_out[63+64*5*3+64*0:64*5*3+64*0];
  assign state_out[63+64*5*0+64*4:64*5*0+64*4] = lanes_out[63+64*5*4+64*0:64*5*4+64*0];
  // for x=1, y=0..4                            // for x=0..4, y=1
  assign state_out[63+64*5*1+64*0:64*5*1+64*0] = lanes_out[63+64*5*0+64*1:64*5*0+64*1];
  assign state_out[63+64*5*1+64*1:64*5*1+64*1] = lanes_out[63+64*5*1+64*1:64*5*1+64*1];
  assign state_out[63+64*5*1+64*2:64*5*1+64*2] = lanes_out[63+64*5*2+64*1:64*5*2+64*1];
  assign state_out[63+64*5*1+64*3:64*5*1+64*3] = lanes_out[63+64*5*3+64*1:64*5*3+64*1];
  assign state_out[63+64*5*1+64*4:64*5*1+64*4] = lanes_out[63+64*5*4+64*1:64*5*4+64*1];
  // for x=2, y=0..4                            // for x=0..4, y=2
  assign state_out[63+64*5*2+64*0:64*5*2+64*0] = lanes_out[63+64*5*0+64*2:64*5*0+64*2];
  assign state_out[63+64*5*2+64*1:64*5*2+64*1] = lanes_out[63+64*5*1+64*2:64*5*1+64*2];
  assign state_out[63+64*5*2+64*2:64*5*2+64*2] = lanes_out[63+64*5*2+64*2:64*5*2+64*2];
  assign state_out[63+64*5*2+64*3:64*5*2+64*3] = lanes_out[63+64*5*3+64*2:64*5*3+64*2];
  assign state_out[63+64*5*2+64*4:64*5*2+64*4] = lanes_out[63+64*5*4+64*2:64*5*4+64*2];
  // for x=3, y=0..4                            // for x=0..4, y=3
  assign state_out[63+64*5*3+64*0:64*5*3+64*0] = lanes_out[63+64*5*0+64*3:64*5*0+64*3];
  assign state_out[63+64*5*3+64*1:64*5*3+64*1] = lanes_out[63+64*5*1+64*3:64*5*1+64*3];
  assign state_out[63+64*5*3+64*2:64*5*3+64*2] = lanes_out[63+64*5*2+64*3:64*5*2+64*3];
  assign state_out[63+64*5*3+64*3:64*5*3+64*3] = lanes_out[63+64*5*3+64*3:64*5*3+64*3];
  assign state_out[63+64*5*3+64*4:64*5*3+64*4] = lanes_out[63+64*5*4+64*3:64*5*4+64*3];
  // for x=4, y=0..4                            // for x=0..4, y=4
  assign state_out[63+64*5*4+64*0:64*5*4+64*0] = lanes_out[63+64*5*0+64*4:64*5*0+64*4];
  assign state_out[63+64*5*4+64*1:64*5*4+64*1] = lanes_out[63+64*5*1+64*4:64*5*1+64*4];
  assign state_out[63+64*5*4+64*2:64*5*4+64*2] = lanes_out[63+64*5*2+64*4:64*5*2+64*4];
  assign state_out[63+64*5*4+64*3:64*5*4+64*3] = lanes_out[63+64*5*3+64*4:64*5*3+64*4];
  assign state_out[63+64*5*4+64*4:64*5*4+64*4] = lanes_out[63+64*5*4+64*4:64*5*4+64*4];


  always_ff @(posedge clk) begin
    if(rst)
      round_nr <= 5'd31;
    else if(round_nr!=5'd24)
      round_nr <= round_nr + 1'b1;
    else
      round_nr <= round_nr;
  end

  assign we_state_out = (round_nr<5'd24) ? 1'b1 : 1'b0;

  always_ff @(posedge clk) begin
    if(rst)
      final_round <= 1'b0;
    else if(round_nr==5'd22)
      final_round <= 1'b1;
    else
      final_round <= final_round;
  end

endmodule
