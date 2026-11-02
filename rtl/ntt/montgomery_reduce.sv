`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Montgomery reduction for q = 12289 and R = 2^14: computes x * 2^-14 mod 12289 for 0 <= x < 12289^2
//
//////////////////////////////////////////////////////////////////////////////////

module montgomery_reduce (
    input logic [27:0] x,
    output logic [13:0] result
  );

  logic [13:0] t;
  logic [27:0] t_times_q;
  logic signed [15:0] u;

  assign t = x[13:0] + {x[1:0], 12'b0};  // x * (2^12 + 1) mod 2^14
  assign t_times_q = {t, 13'b0} + {t, 12'b0} + t;
  // The lower 14 bits of x and t*q are equal, so only the upper bits are subtracted
  assign u = $signed({2'b0, x[27:14]}) - $signed({2'b0, t_times_q[27:14]});
  assign result = 14'(u < 0 ? u + 16'sd12289 : u);

endmodule
