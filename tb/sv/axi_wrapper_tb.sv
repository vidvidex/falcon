`timescale 1ns / 1ps
`include "common_definitions.vh"

// Tests the accelerator through its AXI-Lite registers and external BRAM port, the way the software uses it
// (see sw/src/utilities.h):
//   1. registers read as zero after reset
//   2. BRAM access through the external port (enabled with slv_reg0[31]): write and read back
//   3. load the verify512 public key, signature and message, run verification through slv_reg0 and check
//      done/accepted in slv_reg1 and the cycle count in slv_reg2
//   4. the reset bit (slv_reg0[3]) clears the status
module axi_wrapper_tb;

  localparam int N = 512;
  localparam int PUBLIC_KEY_BLOCK_COUNT = N / 2;
  localparam int SIGNATURE_BLOCK_COUNT = 40;
  localparam int MESSAGE_BLOCK_COUNT = 8;

  localparam logic [3:0] CONTROL_REG = 4'h0;
  localparam logic [3:0] OUTPUT_REG = 4'h4;
  localparam logic [3:0] CYCLE_COUNT_REG = 4'h8;

  logic clk, rst_n;

  logic [19:0] ext_bram_addr;
  logic [15:0] ext_bram_we;
  logic [127:0] ext_bram_din;
  logic [127:0] ext_bram_dout;

  logic [3:0] awaddr, araddr;
  logic awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready;
  logic [31:0] wdata, rdata;
  logic [1:0] bresp, rresp;

  axi_wrapper #(.N(N)) axi_wrapper (
                .ext_bram_addr(ext_bram_addr),
                .ext_bram_we(ext_bram_we),
                .ext_bram_din(ext_bram_din),
                .ext_bram_dout(ext_bram_dout),

                .S_AXI_ACLK(clk),
                .S_AXI_ARESETN(rst_n),
                .S_AXI_AWADDR(awaddr),
                .S_AXI_AWPROT(3'b0),
                .S_AXI_AWVALID(awvalid),
                .S_AXI_AWREADY(awready),
                .S_AXI_WDATA(wdata),
                .S_AXI_WSTRB(4'hf),
                .S_AXI_WVALID(wvalid),
                .S_AXI_WREADY(wready),
                .S_AXI_BRESP(bresp),
                .S_AXI_BVALID(bvalid),
                .S_AXI_BREADY(bready),
                .S_AXI_ARADDR(araddr),
                .S_AXI_ARPROT(3'b0),
                .S_AXI_ARVALID(arvalid),
                .S_AXI_ARREADY(arready),
                .S_AXI_RDATA(rdata),
                .S_AXI_RRESP(rresp),
                .S_AXI_RVALID(rvalid),
                .S_AXI_RREADY(rready)
              );

  always #5 clk = ~clk;

  // AXI-Lite master
  task automatic axi_write(input logic [3:0] addr, input logic [31:0] data);
    int cycles = 0;
    awaddr <= addr;
    awvalid <= 1;
    wdata <= data;
    wvalid <= 1;
    bready <= 1;
    do begin
      @(posedge clk);
      if (++cycles > 100) $fatal(1, "AXI write to %h: no AWREADY/WREADY", addr);
    end while (!(awready && wready));
    awvalid <= 0;
    wvalid <= 0;
    while (!bvalid) @(posedge clk);
    if (bresp !== 2'b00)
      $fatal(1, "AXI write to %h: BRESP %b", addr, bresp);
    @(posedge clk);
    bready <= 0;
  endtask

  task automatic axi_read(input logic [3:0] addr, output logic [31:0] data);
    int cycles = 0;
    araddr <= addr;
    arvalid <= 1;
    rready <= 1;
    do begin
      @(posedge clk);
      if (++cycles > 100) $fatal(1, "AXI read from %h: no ARREADY", addr);
    end while (!arready);
    arvalid <= 0;
    while (!rvalid) @(posedge clk);
    if (rresp !== 2'b00)
      $fatal(1, "AXI read from %h: RRESP %b", addr, rresp);
    data = rdata;
    @(posedge clk);
    rready <= 0;
  endtask

  // External BRAM port (driven by the AXI BRAM controller in the block design). Requires slv_reg0[31] = 1.
  task automatic bram_write(input int bank, input int addr, input logic [127:0] data);
    ext_bram_addr <= {3'(bank), 13'(addr), 4'b0};
    ext_bram_din <= data;
    ext_bram_we <= 16'hffff;
    @(posedge clk);
    ext_bram_we <= 0;
  endtask

  task automatic bram_read(input int bank, input int addr, output logic [127:0] data);
    ext_bram_addr <= {3'(bank), 13'(addr), 4'b0};
    ext_bram_we <= 0;
    repeat (3) @(posedge clk);  // BRAM read latency is 2 cycles
    #1;
    data = ext_bram_dout;
    @(posedge clk);
  endtask

  logic [127:0] public_key [PUBLIC_KEY_BLOCK_COUNT];
  logic [127:0] signature [SIGNATURE_BLOCK_COUNT];
  logic [127:0] message [MESSAGE_BLOCK_COUNT];

  initial begin
    logic [31:0] value;
    logic [127:0] data;
    string dir;
    int polls;

    clk = 1;
    awaddr = 0; awvalid = 0; wdata = 0; wvalid = 0; bready = 0;
    araddr = 0; arvalid = 0; rready = 0;
    ext_bram_addr = 0; ext_bram_we = 0; ext_bram_din = 0;

    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n <= 1;
    repeat (5) @(posedge clk);

    // 1. Registers after reset
    for (int r = 0; r < 4; r++) begin
      axi_read(4'(r * 4), value);
      if (value !== 0)
        $fatal(1, "slv_reg%0d after reset: expected 0, got %h", r, value);
    end
    $display("Test 1 passed: registers are zero after reset");

    // 2. BRAM access through the external port
    axi_write(CONTROL_REG, 32'h8000_0000);
    for (int bank = 0; bank < 7; bank++)
      bram_write(bank, 3 + bank, {4{bank[7:0], 24'h5a5a5a}});
    for (int bank = 0; bank < 7; bank++) begin
      bram_read(bank, 3 + bank, data);
      if (data !== {4{bank[7:0], 24'h5a5a5a}})
        $fatal(1, "BRAM%0d read back %h, expected %h", bank, data, {4{bank[7:0], 24'h5a5a5a}});
    end
    $display("Test 2 passed: external BRAM write and read back");

    // 3. Verification of the verify512 signature
    dir = {`FALCON_MEM_DIR, "/instruction_dispatch_tb/verify512"};
    $readmemh({dir, "/bram0.hex"}, public_key);
    $readmemh({dir, "/bram1.hex"}, signature);
    $readmemh({dir, "/bram6.hex"}, message);
    for (int i = 0; i < SIGNATURE_BLOCK_COUNT; i++)
      if ($isunknown(signature[i])) signature[i] = 0;  // the file holds fewer words than the padded signature
    for (int i = 0; i < PUBLIC_KEY_BLOCK_COUNT; i++) bram_write(0, i, public_key[i]);
    for (int i = 0; i < SIGNATURE_BLOCK_COUNT; i++) bram_write(1, i, signature[i]);
    for (int i = 0; i < MESSAGE_BLOCK_COUNT; i++) bram_write(6, i, message[i]);
    axi_write(CONTROL_REG, 32'h0);              // disable external BRAM access

    axi_write(CONTROL_REG, 32'b011);            // algorithm 01 (verify) + start
    polls = 0;
    do begin
      axi_read(OUTPUT_REG, value);
      if (++polls > 10000) $fatal(1, "Verification did not finish");
    end while (value[0] !== 1'b1);
    if (value[2:0] !== 3'b011)
      $fatal(1, "slv_reg1 after verification: expected done + accepted (011), got %b", value[2:0]);
    axi_read(CYCLE_COUNT_REG, value);
    if (value == 0 || value > 100_000)
      $fatal(1, "Implausible cycle count %0d", value);
    $display("Test 3 passed: verify512 signature accepted in %0d cycles", value);

    // 4. Reset bit clears the status
    axi_write(CONTROL_REG, 32'b1000);
    axi_write(CONTROL_REG, 32'b0);
    repeat (3) @(posedge clk);
    axi_read(OUTPUT_REG, value);
    if (value[2:0] !== 3'b000)
      $fatal(1, "slv_reg1 after reset bit: expected 000, got %b", value[2:0]);
    $display("Test 4 passed: reset bit clears the status");

    $display("All tests for axi_wrapper passed!");
    $finish;
  end

endmodule
