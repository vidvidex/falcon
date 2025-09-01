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

    input logic [`BRAM_DATA_WIDTH-1:0] data_in,
    input logic valid_in,
    input logic [`BRAM_ADDR_WIDTH-1:0] address_in,

    output logic [`BRAM_DATA_WIDTH-1:0] data_out,
    output logic valid_out,
    output logic [`BRAM_ADDR_WIDTH-1:0] address_out
  );

  logic signed [14:0] input_int1, input_int2;
  logic sign1, sign2;
  logic [14:0] abs_val1, abs_val2;
  logic [10:0] exponent1, exponent2;
  logic [51:0] mantissa1, mantissa2;
  logic [14:0] normalized1, normalized2;
  logic [5:0] shift1, shift2;
  logic [63:0] output_double1, output_double2;

  // Convert first integer to double
  always_comb begin
    input_int1 = data_in[78:64];
    sign1 = input_int1[14];
    abs_val1 = sign1 ? -input_int1 : input_int1;

    if (abs_val1 != 0) begin
      // Find MSB position
      casez (abs_val1)
        15'b1??????????????:
          shift1 = 14;
        15'b01?????????????:
          shift1 = 13;
        15'b001????????????:
          shift1 = 12;
        15'b0001???????????:
          shift1 = 11;
        15'b00001??????????:
          shift1 = 10;
        15'b000001?????????:
          shift1 = 9;
        15'b0000001????????:
          shift1 = 8;
        15'b00000001???????:
          shift1 = 7;
        15'b000000001??????:
          shift1 = 6;
        15'b0000000001?????:
          shift1 = 5;
        15'b00000000001????:
          shift1 = 4;
        15'b000000000001???:
          shift1 = 3;
        15'b0000000000001??:
          shift1 = 2;
        15'b00000000000001?:
          shift1 = 1;
        15'b000000000000001:
          shift1 = 0;
        default:
          shift1 = 0;
      endcase

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
      casez (abs_val2)
        15'b1??????????????:
          shift2 = 14;
        15'b01?????????????:
          shift2 = 13;
        15'b001????????????:
          shift2 = 12;
        15'b0001???????????:
          shift2 = 11;
        15'b00001??????????:
          shift2 = 10;
        15'b000001?????????:
          shift2 = 9;
        15'b0000001????????:
          shift2 = 8;
        15'b00000001???????:
          shift2 = 7;
        15'b000000001??????:
          shift2 = 6;
        15'b0000000001?????:
          shift2 = 5;
        15'b00000000001????:
          shift2 = 4;
        15'b000000000001???:
          shift2 = 3;
        15'b0000000000001??:
          shift2 = 2;
        15'b00000000000001?:
          shift2 = 1;
        15'b000000000000001:
          shift2 = 0;
        default:
          shift2 = 0;
      endcase

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
