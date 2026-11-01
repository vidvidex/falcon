`timescale 1ns / 1ps
`include "common_definitions.vh"

// Converts every 15-bit signed integer (two per 128-bit word) and compares with the exact double.
module int_to_double_tb;

  logic clk;
  logic [127:0] data_in;
  logic [127:0] data_out;
  logic valid_in;
  logic valid_out;
  logic [`BRAM_ADDR_WIDTH-1:0] address_in;
  logic [`BRAM_ADDR_WIDTH-1:0] address_out;

  always #5 clk = ~clk;

  int_to_double int_to_double (
                  .clk(clk),
                  .data_in(data_in),
                  .valid_in(valid_in),
                  .address_in(address_in),
                  .data_out(data_out),
                  .valid_out(valid_out),
                  .address_out(address_out)
                );

  typedef struct {
    int i1, i2;
    logic [`BRAM_ADDR_WIDTH-1:0] address;
  } test_t;

  test_t tests [$];
  int sent = 0, checked = 0;

  always_ff @(posedge clk) begin
    if (valid_out) begin
      if (tests.size() == 0)
        $fatal(1, "Unexpected output");
      if (data_out[127:64] !== $realtobits(real'(tests[0].i1)))
        $fatal(1, "%0d: expected %h, got %h", tests[0].i1, $realtobits(real'(tests[0].i1)), data_out[127:64]);
      if (data_out[63:0] !== $realtobits(real'(tests[0].i2)))
        $fatal(1, "%0d: expected %h, got %h", tests[0].i2, $realtobits(real'(tests[0].i2)), data_out[63:0]);
      if (address_out !== tests[0].address)
        $fatal(1, "Address: expected %0d, got %0d", tests[0].address, address_out);
      void'(tests.pop_front());
      checked <= checked + 1;
    end
  end

  initial begin
    test_t t;
    logic signed [14:0] i1, i2;
    clk = 1;
    valid_in = 0;
    @(posedge clk);

    // All 15-bit signed values; the unused upper bits of each 64-bit half are set to check they are ignored
    for (int i = -16384; i < 16384; i += 2) begin
      i1 = i;
      i2 = i + 1;
      t.i1 = i1;
      t.i2 = i2;
      t.address = sent;
      tests.push_back(t);
      data_in <= {49'h1_5555_5555_5555, i1, 49'h0_aaaa_aaaa_aaaa, i2};
      address_in <= sent;
      valid_in <= 1;
      sent++;
      @(posedge clk);
    end
    valid_in <= 0;
    repeat (10) @(posedge clk);

    if (checked != sent)
      $fatal(1, "Got %0d results, expected %0d", checked, sent);
    $display("All tests for int_to_double passed! (%0d values)", 2 * sent);
    $finish;
  end

endmodule
