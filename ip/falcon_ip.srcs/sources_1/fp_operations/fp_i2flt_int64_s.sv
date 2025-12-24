module fp_i2flt_int64_s (
    input  logic         aclk,
    input  logic         s_axis_a_tvalid,
    input  logic [63:0]  s_axis_a_tdata, // Input 64-bit integer
    output logic m_axis_result_tvalid,
    output logic [63:0] m_axis_result_tdata        // Output 64-bit double-precision floating-point number
);

    // Note: valid signal is passed through directly without checking conversion completion
    // in samplerZ design the input valid is always high 

    // Internal signal to hold the converted integer
    logic [63:0] float_converted;

    // Instantiate the doublefloat2int module
    int2doublefloat #(
        .INT_WIDTH(64)
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