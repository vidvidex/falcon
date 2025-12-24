
module fp_flt2i_int32_s (
    input  logic         aclk,
    input  logic         s_axis_a_tvalid,
    input  logic [63:0]  s_axis_a_tdata, // Input double-precision floating-point number
    output logic m_axis_result_tvalid,
    output logic [31:0] m_axis_result_tdata        // Output 32-bit integer
);

    // Note: valid signal is passed through directly without checking conversion completion
    // in samplerZ design the input valid is always high 

    // Internal signal to hold the converted integer
    logic [31:0] int_converted;

    // Instantiate the doublefloat2int module
    doublefloat2int #(
        .INT_WIDTH(32)
    ) u_doublefloat2int (
        .double_float(s_axis_a_tdata),
        .int_out(int_converted)
    );

    // Sequential logic to register the output
    always_ff @(posedge aclk) begin
        m_axis_result_tdata <= int_converted;
        m_axis_result_tvalid <= s_axis_a_tvalid;
    end

endmodule


// this module converts a double-precision floating-point number to an integer

module doublefloat2int #(
    parameter INT_WIDTH = 32  // 32 or 64 bits
) (
    input  logic [63:0] double_float,           // Input double-precision floating-point number
    output logic [INT_WIDTH-1:0] int_out        // Output integer
);

    // Internal signals
    logic sign;
    logic [10:0] exponent;
    logic [51:0] mantissa;
    logic [INT_WIDTH+31:0] shifted_mantissa;
    logic [INT_WIDTH-1:0] result;
    logic overflow;
    logic signed [11:0] exp_adjusted;
    logic [52:0] mantissa_with_hidden_bit;
    // Extract sign, exponent, and mantissa
    assign sign = double_float[63];
    assign exponent = double_float[62:52];
    assign mantissa = double_float[51:0];

    // Convert to integer
    always_comb begin
        // Handle special cases
        if (exponent == 11'b11111111111) begin
            // NaN or Infinity
            result = {1'b1, {(INT_WIDTH-1){1'b0}}}; // Indicate overflow
        end else if (exponent == 11'b00000000000) begin
            // Zero or denormalized number
            result = {INT_WIDTH{1'b0}};
        end else begin
            // Normalized number
            // Add hidden bit for normalized numbers
            mantissa_with_hidden_bit = {1'b1, mantissa};
            
            // Unbias exponent (bias = 1023)
            exp_adjusted = $signed(exponent) - 12'd1023;
            
            shifted_mantissa = {(INT_WIDTH+32){1'b0}};
            
            if (exp_adjusted < 0) begin
                result = {INT_WIDTH{1'b0}}; // Value less than 1
            end else if (exp_adjusted >= INT_WIDTH) begin
                result = {1'b1, {(INT_WIDTH-1){1'b0}}}; // Overflow
            end else if (exp_adjusted < 52) begin
                // Right shift — add rounding before shift
                automatic int shift_amount = 52 - exp_adjusted;
                
                if (shift_amount < 64 && shift_amount > 0) begin
                    automatic logic [63:0] extended_mantissa = {11'b0, mantissa_with_hidden_bit};
                    automatic logic [63:0] rounding_add = 64'd1 << (shift_amount - 1);
                    automatic logic [63:0] rounded_mantissa = extended_mantissa + rounding_add;
                    shifted_mantissa = rounded_mantissa >> shift_amount;
                end
                else if (shift_amount <= 0) begin
                    // No shift needed or left shift needed
                    shifted_mantissa = mantissa_with_hidden_bit;
                end
                else begin
                    shifted_mantissa = 0; // too small, rounds to zero
                end
                
                result = shifted_mantissa[INT_WIDTH-1:0];
                
                if (sign) begin
                    result = -result; // Apply sign
                end
            end else begin
                // Left shift for large exponent (no rounding needed)
                shifted_mantissa = mantissa_with_hidden_bit << (exp_adjusted - 52);
                result = shifted_mantissa[INT_WIDTH-1:0];
                
                if (sign) begin
                    result = -result; // Apply sign
                end
            end
        end
    end

    assign int_out = result;

endmodule