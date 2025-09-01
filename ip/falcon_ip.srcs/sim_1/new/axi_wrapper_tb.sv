`timescale 1ns / 1ps

module axi_wrapper_tb;

  logic clk, rst_n;

  logic ext_bram_en;
  logic [19:0] ext_bram_addr;
  logic [15:0] ext_bram_we;
  logic[127:0] ext_bram_din;
  logic [127:0] ext_bram_dout;

  axi_wrapper axi_wrapper (
                // .ext_bram_en(ext_bram_en),
                .ext_bram_addr(ext_bram_addr),
                .ext_bram_we(ext_bram_we),
                .ext_bram_din(ext_bram_din),
                .ext_bram_dout(ext_bram_dout),

                .S_AXI_ACLK(clk),
                .S_AXI_ARESETN(rst_n),
                .S_AXI_AWADDR(0),
                .S_AXI_AWPROT(0),
                .S_AXI_AWVALID(0),
                .S_AXI_AWREADY(),
                .S_AXI_WDATA(0),
                .S_AXI_WSTRB(0),
                .S_AXI_WVALID(0),
                .S_AXI_WREADY(),
                .S_AXI_BRESP(),
                .S_AXI_BVALID(),
                .S_AXI_BREADY(),
                .S_AXI_ARADDR(0),
                .S_AXI_ARPROT(0),
                .S_AXI_ARVALID(0),
                .S_AXI_ARREADY(),
                .S_AXI_RDATA(),
                .S_AXI_RRESP(),
                .S_AXI_RVALID(),
                .S_AXI_RREADY()
              );

  always #5 clk = ~clk;

  initial begin
    clk = 1;

    rst_n = 0;
    #10;
    rst_n = 1;

    ext_bram_en = 0;
    ext_bram_addr = 0;
    ext_bram_we = 0;
    ext_bram_din = 0;

    #50;
    ext_bram_en = 1;
    ext_bram_addr = 16'h0001;
    ext_bram_we = 16'hFFFF; // Write all bytes
    ext_bram_din = 128'hffffffff_ffffffff_ffffffff_ffffffff;
    #10;
    ext_bram_en = 0;
    ext_bram_addr = 16'h0000;
    ext_bram_we = 16'b0;
    ext_bram_din = 128'b0;

    #20;
    ext_bram_addr = 16'h0001;
    #10;
    ext_bram_en = 1;
    #50;
    ext_bram_en = 0;


  end


endmodule
