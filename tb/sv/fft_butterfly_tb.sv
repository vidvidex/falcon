`timescale 1ns / 1ps

// Compares fft_butterfly bit for bit against a reference model in the simulator's IEEE-754 double arithmetic, with w
// the twiddle factor at tw_addr and s = 2^scale_factor:
//   FFT  (mode 0): a_out = a + b*w,     b_out = a - b*w
//   IFFT (mode 1): a_out = (a + b)*s,   b_out = (a - b)*conj(w)*s
// Complex products are computed like complex_multiplier: re = xr*yr*s - xi*yi*s, im = xr*yi*s + xi*yr*s.
//
// Twiddle factors are read from a separate fft_twiddle_factor_rom instance (its contents are checked by the
// FFT/IFFT testbenches).
//
// The butterfly must not switch modes while it is processing, and the scale factor is not fully pipelined, so mode
// and scale factor are held constant within a batch.
module fft_butterfly_tb;

  localparam int RANDOM_TESTS = 1000;

  logic clk;
  logic valid_in, valid_out, mode;
  logic [63:0] a_in_real, a_in_imag, b_in_real, b_in_imag;
  logic [9:0] tw_addr;
  logic [63:0] a_out_real, a_out_imag, b_out_real, b_out_imag;
  logic signed [4:0] scale_factor;
  logic ext_mul = 0, ext_valid_in = 0;
  logic [63:0] ext_a_real, ext_a_imag, ext_b_real, ext_b_imag, product_real, product_imag;

  always #5 clk = ~clk;

  fft_butterfly fft_butterfly(
                 .clk(clk),
                 .valid_in(valid_in),
                 .mode(mode),
                 .a_in_real(a_in_real),
                 .a_in_imag(a_in_imag),
                 .b_in_real(b_in_real),
                 .b_in_imag(b_in_imag),
                 .tw_addr(tw_addr),
                 .scale_factor(scale_factor),
                 .a_out_real(a_out_real),
                 .a_out_imag(a_out_imag),
                 .b_out_real(b_out_real),
                 .b_out_imag(b_out_imag),
                 .valid_out(valid_out),
                 .ext_mul(ext_mul),
                 .ext_valid_in(ext_valid_in),
                 .ext_a_real(ext_a_real),
                 .ext_a_imag(ext_a_imag),
                 .ext_b_real(ext_b_real),
                 .ext_b_imag(ext_b_imag),
                 .product_real(product_real),
                 .product_imag(product_imag)
               );

  // Expected products for ext_mul
  logic [127:0] expected_products [$];
  int products_checked = 0;

  // Twiddle factor table
  logic [9:0] rom_addr;
  logic [63:0] rom_real, rom_imag;
  fft_twiddle_factor_rom rom(.clk(clk), .mode(1'b0), .tw_addr(rom_addr), .tw_real(rom_real), .tw_imag(rom_imag));
  real w_real [1024], w_imag [1024];

  typedef struct {
    logic [63:0] a_re, a_im, b_re, b_im;
    logic m;
    int addr;
  } expected_t;

  expected_t expected [$];
  int sent = 0, checked = 0;

  task automatic check(string name, logic [63:0] got, logic [63:0] exp, expected_t e);
    if (got !== exp)
      $fatal(1, "Output %0d (%s, tw_addr %0d), %s: expected %h (%g), got %h (%g)", checked, e.m ? "IFFT" : "FFT", e.addr,
             name, exp, $bitstoreal(exp), got, $bitstoreal(got));
  endtask

  always_ff @(posedge clk) begin
    if (valid_out && ext_mul) begin
      if (expected_products.size() == 0)
        $fatal(1, "Unexpected product");
      if ({product_real, product_imag} !== expected_products[0])
        $fatal(1, "Product %0d: expected %h, got %h", products_checked, expected_products[0], {product_real, product_imag});
      void'(expected_products.pop_front());
      products_checked <= products_checked + 1;
    end
    else if (valid_out) begin
      if (expected.size() == 0)
        $fatal(1, "Unexpected output");
      check("a_out real", a_out_real, expected[0].a_re, expected[0]);
      check("a_out imag", a_out_imag, expected[0].a_im, expected[0]);
      check("b_out real", b_out_real, expected[0].b_re, expected[0]);
      check("b_out imag", b_out_imag, expected[0].b_im, expected[0]);
      void'(expected.pop_front());
      checked <= checked + 1;
    end
  end

  function automatic real random_double(int range);
    int e = $urandom_range(2 * range) - range;
    return $bitstoreal({1'($urandom), 11'(1023 + e), 20'($urandom), 32'($urandom)});
  endfunction

  task automatic send(logic m, real ar, real ai, real br, real bi, int addr, int scale);
    expected_t e;
    real s = 2.0 ** scale;
    real wr = w_real[addr];
    real wi = m ? -w_imag[addr] : w_imag[addr];
    real tr, ti, dr, di;
    if (m == 1'b0) begin
      tr = br * wr - bi * wi;
      ti = br * wi + bi * wr;
      e.a_re = $realtobits(ar + tr);
      e.a_im = $realtobits(ai + ti);
      e.b_re = $realtobits(ar - tr);
      e.b_im = $realtobits(ai - ti);
    end
    else begin
      dr = ar - br;
      di = ai - bi;
      e.a_re = $realtobits((ar + br) * s);
      e.a_im = $realtobits((ai + bi) * s);
      e.b_re = $realtobits(dr * wr * s - di * wi * s);
      e.b_im = $realtobits(dr * wi * s + di * wr * s);
    end
    e.m = m;
    e.addr = addr;
    expected.push_back(e);

    mode <= m;
    a_in_real <= $realtobits(ar);
    a_in_imag <= $realtobits(ai);
    b_in_real <= $realtobits(br);
    b_in_imag <= $realtobits(bi);
    tw_addr <= addr;
    scale_factor <= scale;
    valid_in <= 1;
    sent++;
    @(posedge clk);
  endtask

  task automatic drain();
    valid_in <= 0;
    while (expected.size() != 0)
      @(posedge clk);
    repeat (5) @(posedge clk);
  endtask

  initial begin
    clk = 1;
    valid_in = 0;
    mode = 0;
    scale_factor = 0;
    tw_addr = 0;

    // Read the twiddle factor table (the ROM has a latency of one cycle)
    for (int i = 0; i < 1024; i++) begin
      rom_addr <= i;
      @(posedge clk);
      #1;
      w_real[i] = $bitstoreal(rom_real);
      w_imag[i] = $bitstoreal(rom_imag);
    end
    if ($realtobits(w_real[2]) !== 64'h3FE6A09E667F3BCD || $realtobits(w_imag[2]) !== 64'h3FE6A09E667F3BCD)  // sqrt(2)/2
      $fatal(1, "Unexpected twiddle factor at address 2: %g + j%g", w_real[2], w_imag[2]);

    // FFT
    send(0, 1.0, 2.0, 3.0, 4.0, 2, 0);    // 0.29289+6.94974i, 1.70710-2.9497i
    send(0, 12.5, 2.7, 1.5, -4.2, 4, 0);  // 15.49308-0.60626i, 9.50691+6.00626i
    send(0, 3.0, 2.0, 1.0, 0.0, 2, 0);    // 3.70710+2.70710i, 2.29289+1.29289i
    for (int i = 0; i < RANDOM_TESTS; i++)
      send(0, random_double(10), random_double(10), random_double(10), random_double(10), $urandom_range(1023), 0);
    drain();

    // IFFT (scaled by 1/2 per stage, as used in the IFFT module)
    send(1, 1.0, 2.0, 3.0, 4.0, 2, -1);
    send(1, 12.5, 2.7, 1.5, -4.2, 4, -1);
    send(1, 3.0, 2.0, 1.0, 0.0, 2, -1);
    for (int i = 0; i < RANDOM_TESTS; i++)
      send(1, random_double(10), random_double(10), random_double(10), random_double(10), $urandom_range(1023), -1);
    drain();
    for (int i = 0; i < RANDOM_TESTS; i++)
      send(1, random_double(10), random_double(10), random_double(10), random_double(10), $urandom_range(1023), -5);
    drain();

    if (checked != sent)
      $fatal(1, "Got %0d results, expected %0d", checked, sent);
    // The complex multiplier on its own
    ext_mul <= 1;
    for (int i = 0; i < RANDOM_TESTS; i++) begin
      real ar = random_double(10), ai = random_double(10), br = random_double(10), bi = random_double(10);
      expected_products.push_back({$realtobits(ar * br - ai * bi), $realtobits(ar * bi + ai * br)});
      ext_a_real <= $realtobits(ar);
      ext_a_imag <= $realtobits(ai);
      ext_b_real <= $realtobits(br);
      ext_b_imag <= $realtobits(bi);
      ext_valid_in <= 1;
      @(posedge clk);
    end
    ext_valid_in <= 0;
    while (expected_products.size() != 0)
      @(posedge clk);
    @(posedge clk);
    if (products_checked != RANDOM_TESTS)
      $fatal(1, "Got %0d products, expected %0d", products_checked, RANDOM_TESTS);

    $display("All tests for fft_butterfly passed! (%0d butterflies, %0d products)", sent, products_checked);
    $finish;
  end

endmodule
