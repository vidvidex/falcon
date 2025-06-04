`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// ROM for FFT twiddle factors.
//
// This ROM inferred instead of explicitly instantiated simply because for explicit instantiation the simulation adds a 0.1 ns delay which breaks the simulation timing.
// As a bonus we can output real and imaginary parts separately and negate imaginary part for IFFT, which makes the use in parent module slightly nicer.
//
//////////////////////////////////////////////////////////////////////////////////


module fft_twiddle_factor_rom(
    input logic clk,
    input logic mode,
    input logic [9:0] tw_addr,
    output logic [63:0] tw_real,
    output logic [63:0] tw_imag
  );

  logic [127:0] rom_memory [1024];

  initial begin
    $readmemh("../../../../falcon.srcs/sources_1/coefficients/fft_twiddle_factors.mem", rom_memory);
  end

  always @(posedge clk) begin
    logic [127:0] tmp;
    tmp = rom_memory[tw_addr];

    tw_real <= tmp[127:64];

    if (mode == 1'b0) // FFT mode
      tw_imag <= tmp[63:0];
    else // IFFT mode
      tw_imag <= {~tmp[63], tmp[62:0]}; // Negate imaginary part
  end

endmodule
