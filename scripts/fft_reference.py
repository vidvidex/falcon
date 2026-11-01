#!/usr/bin/env python3
"""Reference FFT/iFFT for the FFT testbenches.

Port of falcon_FFT and falcon_iFFT from Falcon's reference implementation (fft.c)

The polynomial f of N real coefficients is stored as N/2 complex values f[j] + i*f[j + N/2], one per 128-bit
BRAM word {re, im}. Twiddle factors (fpr_gm_tab) are read from rtl/fft/fft_twiddle_factor_rom.sv.

Usage: scripts/fft_reference.py   (writes mem/tb/{fft,ifft}_{512,1024}_tb_expected.hex)
"""

import math
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def bits_to_float(h):
    return struct.unpack(">d", bytes.fromhex(h))[0]


def float_to_bits(x):
    return struct.pack(">d", x).hex()


def read_twiddle_factors():
    rom = (ROOT / "rtl/fft/fft_twiddle_factor_rom.sv").read_text()
    gm = {}
    for k, re_bits, im_bits in re.findall(r"10'd(\d+): data_out = \{64'h(\w+), 64'h(\w+)\}", rom):
        gm[int(k)] = (bits_to_float(re_bits), bits_to_float(im_bits))
    assert sorted(gm) == list(range(1024))
    # Sanity check: entry k is exp(i*pi*rev10(k)/1024)
    for k in range(1, 1024):
        angle = math.pi * int(f"{k:010b}"[::-1], 2) / 1024
        assert abs(gm[k][0] - math.cos(angle)) < 1e-15 and abs(gm[k][1] - math.sin(angle)) < 1e-15, k
    return gm


def fft(f, gm):
    """falcon_FFT: f is a list of complex values as (re, im) tuples, modified in place."""
    hn = len(f)
    logn = hn.bit_length()  # log2(N) with N = 2 * hn
    t = hn
    m = 2
    for _ in range(1, logn):
        ht = t >> 1
        hm = m >> 1
        j1 = 0
        for i1 in range(hm):
            s_re, s_im = gm[m + i1]
            for j in range(j1, j1 + ht):
                x_re, x_im = f[j]
                y_re, y_im = f[j + ht]
                y_re, y_im = y_re * s_re - y_im * s_im, y_re * s_im + y_im * s_re
                f[j] = (x_re + y_re, x_im + y_im)
                f[j + ht] = (x_re - y_re, x_im - y_im)
            j1 += t
        t = ht
        m <<= 1


def ifft(f, gm):
    """falcon_iFFT: f is a list of complex values as (re, im) tuples, modified in place."""
    hn = len(f)
    logn = hn.bit_length()
    t = 1
    m = 2 * hn
    for _ in range(logn, 1, -1):
        hm = m >> 1
        dt = t << 1
        i1 = 0
        for j1 in range(0, hn, dt):
            s_re, s_im = gm[hm + i1]
            s_im = -s_im
            for j in range(j1, j1 + t):
                x_re, x_im = f[j]
                y_re, y_im = f[j + t]
                f[j] = (x_re + y_re, x_im + y_im)
                x_re, x_im = x_re - y_re, x_im - y_im
                f[j + t] = (x_re * s_re - x_im * s_im, x_re * s_im + x_im * s_re)
            i1 += 1
        t = dt
        m = hm
    ni = 2.0 / (2 * hn)  # fpr_p2_tab[logn]
    for j in range(hn):
        f[j] = (f[j][0] * ni, f[j][1] * ni)


def main():
    gm = read_twiddle_factors()
    for n in (512, 1024):
        words = (ROOT / f"mem/tb/fft_{n}.hex").read_text().split()
        values = [(bits_to_float(w[:16]), bits_to_float(w[16:])) for w in words]
        assert len(values) == n // 2
        for name, transform in (("fft", fft), ("ifft", ifft)):
            f = list(values)
            transform(f, gm)
            out = ROOT / f"mem/tb/{name}_{n}_tb_expected.hex"
            out.write_text("".join(float_to_bits(r) + float_to_bits(i) + "\n" for r, i in f))
            print(f"wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
