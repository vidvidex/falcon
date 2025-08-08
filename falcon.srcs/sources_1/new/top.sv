`timescale 1ns / 1ps

module top (
    input logic clk,
    input logic [3:0] btns,
    output logic [3:0] leds
  );

  logic rst_n, start, start_i, start_pulse;

  parameter int N = 512;

  int reset_counter;

  logic dma_bram_en;
  logic [19:0] dma_bram_addr;
  logic [15:0] dma_bram_byte_we;
  logic[127:0] dma_bram_din;
  logic [127:0] dma_bram_dout;

  logic signature_accepted;
  logic signature_rejected;

  instruction_dispatch #(
                         .N(N)
                       ) instruction_dispatch (
                         .clk(clk),
                         .rst_n(rst_n),
                         .start(start_pulse),
                         .algorithm_select(1'b1),
                         .done(done),

                         .signature_accepted(signature_accepted),
                         .signature_rejected(signature_rejected),

                         .dma_bram_en(dma_bram_en),
                         .dma_bram_addr(dma_bram_addr),
                         .dma_bram_din(dma_bram_din),
                         .dma_bram_dout(dma_bram_dout),
                         .dma_bram_byte_we(dma_bram_byte_we)
                       );
  typedef enum logic [1:0] {
            RESET,
            RUNNING,
            DONE
          } state_t;
  state_t state, next_state;

  always_ff @(posedge clk) begin
    rst_n <= !(btns[0] || btns[1] || btns[2] || btns[3]);
  end

  always_ff @(posedge clk) begin
    if (rst_n == 1'b0)
      state <= RESET;
    else
      state <= next_state;
  end

  always_comb begin
    dma_bram_en = 0;
    dma_bram_addr = 0;
    dma_bram_byte_we = 0;
    dma_bram_din = 0;

    next_state = state;

    case (state)
      RESET: begin
        if(reset_counter == 25000000)
          next_state = RUNNING;
      end
      RUNNING: begin
        if(signature_accepted == 1'b1 || signature_rejected == 1'b1)
          next_state = DONE;
      end
      DONE: begin
        next_state = DONE;
      end
      default: begin
        next_state = RESET;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
      reset_counter <= 0;
    end

    case (state)
      RESET: begin
        leds[0] <= 1'b1;
        leds[1] <= 1'b0;
        leds[2] <= 1'b0;
        leds[3] <= 1'b0;

        reset_counter <= reset_counter + 1;

        start <= 1'b0;
        start_i <= 1'b0;
      end
      RUNNING: begin
        start <= 1'b1;

        leds[0] <= 1'b0;
        leds[1] <= 1'b1;
        leds[2] <= 1'b0;
        leds[3] <= 1'b0;

      end
      DONE: begin
        leds[0] <= 1'b1;
        leds[1] <= 1'b1;
        leds[2] <= signature_accepted;
        leds[3] <= signature_rejected;
      end
    endcase

    start_i <= start;
  end

  assign start_pulse = start == 1'b1 && start_i == 1'b0;

endmodule
