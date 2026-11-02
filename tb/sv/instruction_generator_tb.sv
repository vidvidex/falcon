`timescale 1ns / 1ps
`include "common_definitions.vh"

// Compares the instructions of instruction_generator with mem/tb/instructions_<algorithm><N>.hex, written by the
// reference model scripts/generate_instruction_list.py, for signing and verification with N = 512 and 1024.
module instruction_generator_tb;

  logic clk = 1;
  always #5 clk = ~clk;

  logic restart, algorithm, next;
  logic [`INSTRUCTION_WIDTH-1:0] instruction_512, instruction_1024;
  logic finished_512, finished_1024;

  instruction_generator #(.N(512)) generator_512(
                          .clk(clk),
                          .restart(restart),
                          .algorithm(algorithm),
                          .next(next),
                          .instruction(instruction_512),
                          .finished(finished_512)
                        );

  instruction_generator #(.N(1024)) generator_1024(
                          .clk(clk),
                          .restart(restart),
                          .algorithm(algorithm),
                          .next(next),
                          .instruction(instruction_1024),
                          .finished(finished_1024)
                        );

  logic [`INSTRUCTION_WIDTH-1:0] expected [$];

  task automatic check(string name, int n, logic alg);
    logic [`INSTRUCTION_WIDTH-1:0] list [20000];
    int count = 0;
    list = '{default: 'x};
    $readmemh({`FALCON_MEM_DIR, "/tb/instructions_", name, ".hex"}, list);
    while (count < 20000 && !$isunknown(list[count]))
      count++;

    algorithm <= alg;
    restart <= 1;
    @(posedge clk);
    restart <= 0;
    for (int i = 0; i < count; i++)
    begin
      #1;
      if ((n == 512 ? finished_512 : finished_1024) !== 1'b0)
        $fatal(1, "%s: finished after %0d instructions, expected %0d", name, i, count);
      if ((n == 512 ? instruction_512 : instruction_1024) !== list[i])
        $fatal(1, "%s: instruction %0d: expected %h, got %h", name, i, list[i], n == 512 ? instruction_512 : instruction_1024);
      next <= 1;
      @(posedge clk);
      next <= 0;
    end
    #1;
    if ((n == 512 ? finished_512 : finished_1024) !== 1'b1)
      $fatal(1, "%s: not finished after %0d instructions", name, count);
    $display("%s: %0d instructions match", name, count);
  endtask

  initial
  begin
    restart = 1;
    algorithm = 0;
    next = 0;
    @(posedge clk);

    check("sign512", 512, 0);
    check("sign1024", 1024, 0);
    check("verify512", 512, 1);
    check("verify1024", 1024, 1);

    $display("All tests for instruction_generator passed!");
    $finish;
  end

endmodule
