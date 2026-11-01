module fp_i2flt_int32 (
    input  logic         aclk,
    input  logic         s_axis_a_tvalid,
    input  logic [31:0]  s_axis_a_tdata, // Input integer number
    input logic m_axis_result_tready,
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
        if(s_axis_a_tvalid & m_axis_result_tready) begin
            m_axis_result_tdata <= float_converted;
        end
    end

endmodule



