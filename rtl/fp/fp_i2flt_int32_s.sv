module fp_i2flt_int32_s (
    input  logic         aclk,
    input  logic         s_axis_a_tvalid,
    input  logic [31:0]  s_axis_a_tdata, // Input integer number
    output logic m_axis_result_tvalid,
    output logic [63:0] m_axis_result_tdata        // Output 64-bit double-precision floating-point number
);

    // Note: valid signal is passed through directly without checking conversion completion
    // in samplerZ design the input valid is always high 


    // Internal signal to hold the converted integer
    logic [63:0] float_converted;

    // Instantiate the doublefloat2int module
    int2doublefloat #(
        .INT_WIDTH(32)
    ) u_int2doublefloat (
        .int_in(s_axis_a_tdata),
        .double_float_out(float_converted)
    );

    // Sequential logic to register the output
    always_ff @(posedge aclk) begin
        m_axis_result_tdata <= float_converted;
        m_axis_result_tvalid <= s_axis_a_tvalid;
    end

endmodule


module int2doublefloat #(
    parameter INT_WIDTH = 32
) (
    input  logic [INT_WIDTH-1:0] int_in,        // Input integer
    output logic [63:0] double_float_out       // Output double-precision floating-point number
);

    // Internal signals
    logic sign;
    logic [10:0] exponent;
    logic [51:0] mantissa;
    logic [INT_WIDTH+31:0] shifted_mantissa;
    logic [10:0] exp_adjusted;
    logic [INT_WIDTH-1:0] abs_int;
    logic [$clog2(INT_WIDTH)-1:    0] leading_one_pos;
    logic is_zero;
    
    assign abs_int = int_in[INT_WIDTH-1] ? ~int_in+1 : int_in;
    assign sign = int_in[INT_WIDTH-1];
    assign exponent = is_zero ? 11'b0 : (leading_one_pos + 1023);
    assign mantissa = is_zero ? 52'b0 : (abs_int << (52 - leading_one_pos)) & 52'hFFFFFFFFFFFFF;
    assign double_float_out = {sign, exponent, mantissa};

    leading_one_detector #(
    .N(INT_WIDTH)
    ) lod (
        .input_a(abs_int),
        .leading_one_pos(leading_one_pos),
        .is_zero(is_zero)
    );
endmodule



module leading_one_detector #(
    parameter N = 16
) (
    input  logic [N-1:0] input_a,
    output logic [$clog2(N)-1:0] leading_one_pos,
    output logic is_zero
);

    logic [N-1:0] w;
    logic [N-1:0] output_a;

    // generate one hot output
    always_comb begin
        output_a[N-1] = input_a[N-1];
        w[N-1] = input_a[N-1] ? 0 : 1;
        for (int k = N-2; k >= 0; k--) begin
            w[k] = input_a[k] ? 0 : w[k+1];
            output_a[k] = w[k+1] & input_a[k];
        end
    end

    // encode the one hot output
    always_comb begin
        leading_one_pos = 0;
        if (output_a != 0) begin
            for (int i = 0; i < N; i++) begin
                if (output_a[i]) begin
                    leading_one_pos = i;
                end
            end
        end
    end

    assign is_zero = (input_a == 0);

endmodule