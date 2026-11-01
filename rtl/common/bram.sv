
module bram#(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 8,
    parameter INIT_FILE = ""  // Has to be provided as an absolute path, I have absolutely no idea why Vivado won't accept any kind of relative path for this
  ) (
    input logic clk,
    input logic [ADDR_WIDTH-1:0] addra,
    input logic [DATA_WIDTH-1:0] dina,
    output logic [DATA_WIDTH-1:0] douta,
    input logic wea,

    input logic [ADDR_WIDTH-1:0] addrb,
    input logic [DATA_WIDTH-1:0] dinb,
    output logic [DATA_WIDTH-1:0] doutb,
    input logic web
  );

  logic [DATA_WIDTH-1:0] mem [0:2**ADDR_WIDTH-1];
  logic [DATA_WIDTH-1:0] data_a, data_b;

  always_ff @(posedge clk) begin
    if (wea) begin
      mem[addra] <= dina;
    end
    data_a <= mem[addra];
  end

  always_ff @(posedge clk) begin
    if (web) begin
      mem[addrb] <= dinb;
    end
    data_b <= mem[addrb];
  end

  always_ff @(posedge clk) begin
    douta <= data_a;
    doutb <= data_b;
  end

  initial begin
    if(INIT_FILE != "")
      $readmemh(INIT_FILE, mem);
  end

endmodule
