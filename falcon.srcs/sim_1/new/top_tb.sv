module top_tb;

  logic clk;
  logic rst_n;
  logic [3:0] btns;
  logic [3:0] leds;

  top uut(
        .clk(clk),
        .btns(btns),
        .leds(leds)
      );

  always #5 clk = ~clk;

  initial begin
    clk = 1;


    // Reset
    #50;
    btns[3] = 1'b1;
    #50;
    btns[3] = 1'b0;
    #100;


    // Start
    #50;
    btns[2] = 1'b1;
    #50;
    btns[2] = 1'b0;
    #100;

    // Wait for accept or reject
    while(leds[0] == 1'b0 && leds[1] == 1'b0)
      #10;

    // Check that it was accepted
    if(leds[0] == 1'b1 && leds[1] == 1'b0)
      $display("Test 1: Passed");
    else
      $fatal("Test 1: Failed. Expected accept to be 1 and reject to be 0. Got: accept=%d, reject=%d", leds[0], leds[1]);

  end

endmodule
