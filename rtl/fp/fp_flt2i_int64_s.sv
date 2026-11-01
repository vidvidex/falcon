module fp_flt2i_int64_s (
    input  logic         aclk,
    input  logic         s_axis_a_tvalid,
    input  logic [63:0]  s_axis_a_tdata, // Input double-precision floating-point number
    output logic m_axis_result_tvalid,
    output logic [63:0] m_axis_result_tdata        // Output 64-bit integer
);

    // Note: valid signal is passed through directly without checking conversion completion
    // in samplerZ design the input valid is always high 

    // Internal signal to hold the converted integer
    logic [63:0] int_converted;

    // Instantiate the doublefloat2int module
    doublefloat2int #(
        .INT_WIDTH(64)
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
