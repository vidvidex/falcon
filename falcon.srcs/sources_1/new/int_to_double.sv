`timescale 1ns / 1ps
`include "common_definitions.vh"

//////////////////////////////////////////////////////////////////////////////////
//
// Converts numbers stored in BRAM from int to double.
//
// The module receives 128 bits of data (read from BRAM), which contain 2 ints, which for our purposes happen to be at most 12289 and use at most 15 bits.
//
//      64 bit (15 used)    64 bit (15 used)
//     <-----------------> <----------------->
//    |-------------------|-------------------|
//    |   integer 1       |   integer 2       |
//    |-------------------|-------------------|
//
// Both integers are converted to doubles and outputted in the same layout, so they can be written back to BRAM
//
//            64 bit             64 bit
//     <-----------------> <----------------->
//    |-------------------|-------------------|
//    |   double 1        |   double 2        |
//    |-------------------|-------------------|
//
// Signals valid_in, valid_out, address_in, address_out are used to make it easier for the parent module to write the result back to BRAM
//
//////////////////////////////////////////////////////////////////////////////////


(* keep_hierarchy = `KEEP_HIERARCHY *)
module int_to_double
  (
    input logic clk,

    input logic [`FFT_BRAM_DATA_WIDTH-1:0] data_in,
    input logic valid_in,
    input logic [`FFT_BRAM_ADDR_WIDTH-1:0] address_in,

    output logic [`FFT_BRAM_DATA_WIDTH-1:0] data_out,
    output logic valid_out,
    output logic [`FFT_BRAM_ADDR_WIDTH-1:0] address_out
  );

  logic signed [14:0] input_int1, input_int2;
  logic sign1, sign2;
  logic [14:0] abs_val1, abs_val2;
  logic [10:0] exponent1, exponent2;
  logic [51:0] mantissa1, mantissa2;
  logic [14:0] normalized1, normalized2;
  logic [5:0] shift1, shift2;
  logic [3:0] i1, i2;
  logic [63:0] output_double1, output_double2;

  // Convert first integer to double
  always_comb begin
    input_int1 = data_in[78:64];
    sign1 = input_int1[14];
    abs_val1 = sign1 ? -input_int1 : input_int1;

    if (abs_val1 != 0) begin
      // Find MSB position
      shift1 = 0;
      for (i1 = 14; i1 >= 0; i1 = i1 - 1) begin
        if (abs_val1[i1]) begin
          shift1 = i1;
          break;
        end
      end

      // Exponent = bias + MSB position
      exponent1 = 11'd1023 + shift1;

      // Normalize the input so the MSB is at bit 14
      normalized1 = abs_val1 << (14 - shift1);

      // Drop the leading 1 (implicit), align to 52-bit mantissa
      mantissa1 = {normalized1[13:0], 38'd0};

      // Assemble the double: sign | exponent | mantissa
      output_double1 = {sign1, exponent1, mantissa1};
    end
    else begin
      // Zero case
      output_double1 = 64'd0;
    end
  end

  // Convert second integer to double
  always_comb begin
    input_int2 = data_in[14:0];
    sign2 = input_int2[14];
    abs_val2 = sign2 ? -input_int2 : input_int2;

    if (abs_val2 != 0) begin
      // Find MSB position
      shift2 = 0;
      for (i2 = 14; i2 >= 0; i2 = i2 - 1) begin
        if (abs_val2[i2]) begin
          shift2 = i2;
          break;
        end
      end

      // Exponent = bias + MSB position
      exponent2 = 11'd1023 + shift2;

      // Normalize the input so the MSB is at bit 14
      normalized2 = abs_val2 << (14 - shift2);

      // Drop the leading 1 (implicit), align to 52-bit mantissa
      mantissa2 = {normalized2[13:0], 38'd0};

      // Assemble the double: sign | exponent | mantissa
      output_double2 = {sign2, exponent2, mantissa2};
    end
    else begin
      // Zero case
      output_double2 = 64'd0;
    end
  end

  // Register the output
  always_ff @(posedge clk) begin
    data_out <= {output_double1, output_double2};
    address_out <= address_in;
    valid_out <= valid_in;
  end
endmodule
