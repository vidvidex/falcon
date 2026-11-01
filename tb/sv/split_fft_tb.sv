`timescale 1ns / 1ps
`include "common_definitions.vh"

// Checks split_fft bit for bit against Falcon's reference poly_split_fft (see the check task), for sizes 16 and N.
module split_fft_tb;

  parameter int N = 1024;

  logic clk, rst;
  logic mode;
  logic start;
  logic done;
  logic [$clog2(N):0] size;

  logic [`BRAM_ADDR_WIDTH-1:0] bram1_addr_a, bram1_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram1_din_a, bram1_din_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram1_dout_a, bram1_dout_b;
  logic bram1_we_a;
  bram #(.DATA_WIDTH(`BRAM_DATA_WIDTH), .ADDR_WIDTH(`BRAM_ADDR_WIDTH)) bram_6144x128_1 (
                  .addra(bram1_addr_a),
                  .clk(clk),
                  .dina(bram1_din_a),
                  .douta(bram1_dout_a),
                  .wea(bram1_we_a),

                  .addrb(bram1_addr_b),
                  .dinb(bram1_din_b),
                  .doutb(bram1_dout_b),
                  .web(1'b0)
                );

  logic [`BRAM_ADDR_WIDTH-1:0] bram2_addr_a, bram2_addr_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram2_din_a, bram2_din_b;
  logic [`BRAM_DATA_WIDTH-1:0] bram2_dout_a, bram2_dout_b;
  logic bram2_we_a, bram2_we_b;
  bram #(.DATA_WIDTH(`BRAM_DATA_WIDTH), .ADDR_WIDTH(`BRAM_ADDR_WIDTH)) bram_6144x128_2 (
                  .addra(bram2_addr_a),
                  .clk(clk),
                  .dina(bram2_din_a),
                  .douta(bram2_dout_a),
                  .wea(bram2_we_a),

                  .addrb(bram2_addr_b),
                  .dinb(bram2_din_b),
                  .doutb(bram2_dout_b),
                  .web(bram2_we_b)
                );

  logic [63:0] btf_a_in_real, btf_a_in_imag, btf_b_in_real, btf_b_in_imag;
  logic [63:0] btf_a_out_real, btf_a_out_imag, btf_b_out_real, btf_b_out_imag;
  logic btf_mode;
  logic signed [4:0] btf_scale_factor;
  logic [9:0] btf_tw_addr;
  logic btf_valid_in, btf_valid_out;
  fft_butterfly fft_butterfly(
                 .clk(clk),
                 .mode(btf_mode),
                 .valid_in(btf_valid_in),

                 .a_in_real(btf_a_in_real),
                 .a_in_imag(btf_a_in_imag),
                 .b_in_real(btf_b_in_real),
                 .b_in_imag(btf_b_in_imag),

                 .tw_addr(btf_tw_addr),

                 .scale_factor(btf_scale_factor),

                 .a_out_real(btf_a_out_real),
                 .a_out_imag(btf_a_out_imag),
                 .b_out_real(btf_b_out_real),
                 .b_out_imag(btf_b_out_imag),

                 .valid_out(btf_valid_out)
               );

  split_fft #(
              .N(N)
            )split_fft(
              .clk(clk),
              .rst(rst),
              .size(size),
              .start(start),

              .bram1_addr_a(bram1_addr_a),
              .bram1_dout_a(bram1_dout_a),
              .bram1_addr_b(bram1_addr_b),
              .bram1_dout_b(bram1_dout_b),

              .bram2_addr_a(bram2_addr_a),
              .bram2_din_a(bram2_din_a),
              .bram2_we_a(bram2_we_a),
              .bram2_addr_b(bram2_addr_b),
              .bram2_din_b(bram2_din_b),
              .bram2_we_b(bram2_we_b),

              .done(done),

              .btf_mode(btf_mode),
              .btf_valid_in(btf_valid_in),
              .btf_a_in_real(btf_a_in_real),
              .btf_a_in_imag(btf_a_in_imag),
              .btf_b_in_real(btf_b_in_real),
              .btf_b_in_imag(btf_b_in_imag),
              .btf_scale_factor(btf_scale_factor),
              .btf_tw_addr(btf_tw_addr),
              .btf_a_out_real(btf_a_out_real),
              .btf_a_out_imag(btf_a_out_imag),
              .btf_b_out_real(btf_b_out_real),
              .btf_b_out_imag(btf_b_out_imag),
              .btf_valid_out(btf_valid_out)
            );

  // Twiddle factors (fpr_gm_tab), read from a separate ROM instance (its contents are checked by the FFT testbenches)
  logic [9:0] rom_addr;
  logic [63:0] rom_real, rom_imag;
  fft_twiddle_factor_rom rom(.clk(clk), .mode(1'b0), .tw_addr(rom_addr), .tw_real(rom_real), .tw_imag(rom_imag));
  real w_real [1024], w_imag [1024];

  always #5 clk = ~clk;

  function automatic real re(logic [127:0] word);
    return $bitstoreal(word[127:64]);
  endfunction

  function automatic real im(logic [127:0] word);
    return $bitstoreal(word[63:0]);
  endfunction

  task automatic compare(int size, int addr, logic [127:0] expected);
    if (bram_6144x128_2.mem[addr] !== expected)
      $fatal(1, "size %0d, output word %0d: expected %h, got %h", size, addr, expected, bram_6144x128_2.mem[addr]);
  endtask

  task automatic run(int s);
    size = s;
    rst = 1;
    @(posedge clk);
    rst = 0;
    start = 1;
    @(posedge clk);
    start = 0;
    while (!done)
      @(posedge clk);
    repeat (5) @(posedge clk);
  endtask

  // Reference: poly_split_fft from Falcon's reference implementation. The input (BRAM1) holds a polynomial f of `size`
  // coefficients as size/2 complex values; f0 is written to words [0, size/4) and f1 to [size/4, size/2) of BRAM2:
  //   f0[u] = (f[2u] + f[2u+1]) / 2,   f1[u] = (f[2u] - f[2u+1]) * conj(w[u + size/2]) / 2
  task automatic check(int size);
    for (int u = 0; u < size/4; u++) begin
      logic [127:0] a = bram_6144x128_1.mem[2*u], b = bram_6144x128_1.mem[2*u + 1];
      real dr = re(a) - re(b), di = im(a) - im(b);
      real wr = w_real[u + size/2], wi = -w_imag[u + size/2];
      compare(size, u, {$realtobits((re(a) + re(b)) * 0.5), $realtobits((im(a) + im(b)) * 0.5)});
      compare(size, u + size/4, {$realtobits(dr * wr * 0.5 - di * wi * 0.5), $realtobits(dr * wi * 0.5 + di * wr * 0.5)});
    end
    $display("All tests for split_fft with size %0d passed!", size);
  endtask

  initial begin
    clk = 0;
    mode = 0;
    rst = 1;
    start = 0;
    size = 16;
    bram1_we_a = 0;

    // Read the twiddle factor table (the ROM has a latency of one cycle)
    for (int i = 0; i < 1024; i++) begin
      rom_addr <= i;
      @(posedge clk);
      #1;
      w_real[i] = $bitstoreal(rom_real);
      w_imag[i] = $bitstoreal(rom_imag);
    end

    // Random input (with simple patterns such as consecutive integers the products are exact and rounding is not tested)
    for (int i = 0; i < N/2; i++) begin
      bram1_we_a <= 1;
      bram1_addr_a <= i;
      bram1_din_a <= {$realtobits($urandom_range(2_000_000) / 1000.0 - 1000.0), $realtobits($urandom_range(2_000_000) / 1000.0 - 1000.0)};
      @(posedge clk);
    end
    bram1_we_a <= 0;
    @(posedge clk);

    run(16);
    check(16);
    run(N);
    check(N);

    $finish;
  end

endmodule
