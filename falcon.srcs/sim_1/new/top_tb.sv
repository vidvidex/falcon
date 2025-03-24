module top_tb;

  logic clk;
  logic [3:0] leds;
  logic [3:0] btns;

  top uut(
        .clk(clk),
        .btns(btns),
        .leds(leds)
      );

  always #5 clk = ~clk;

  initial begin
    clk = 1;

    btns = 4'b0;
    #100;
    btns[0] = 1'b1;
    #100;
    btns[0] = 1'b0;

    // Wait for accept or reject
    while(leds[2] !== 1'b1 && leds[3] !== 1'b1)
      #10;

    // Check that it was accepted
    if(leds[2] == 1'b1 && leds[3] == 1'b0)
      $display("Test 1: Passed");
    else
      $fatal(1, "Test 1: Failed");

    $finish;
  end

endmodule
