#!/usr/bin/env python3
"""Independent Falcon signature check for the accelerator's memory images.

Usage: falcon_verify.py N public_key.hex message.hex signature.hex

public_key.hex: N/2 words, word i = {h[i], h[i+N/2]} (64 bits each)
message.hex:    word 0 = byte length of salt||message, then 64-bit little-endian blocks (lower half of each word)
signature.hex:  compressed s2, bits MSB first across 128-bit words
"""
import hashlib, sys

Q = 12289
BOUND2 = {512: 34034726, 1024: 70265242}

def words(path):
    return [int(l, 16) for l in open(path).read().split()]

def main(n, pk_path, msg_path, sig_path):
    pk = words(pk_path)
    h = [0] * n
    for i in range(n // 2):
        h[i] = pk[i] >> 64
        h[i + n // 2] = pk[i] & (2**64 - 1)

    m = words(msg_path)
    length = m[0] & (2**64 - 1)
    data = b"".join((w & (2**64 - 1)).to_bytes(8, "little") for w in m[1:])[:length]

    # hash_to_point
    stream = hashlib.shake_256(data).digest(8 * n * 4)
    c, pos = [], 0
    while len(c) < n:
        t = int.from_bytes(stream[pos:pos + 2], "big")
        pos += 2
        if t < 5 * Q:
            c.append(t % Q)

    # decompress s2
    bits = "".join(format(w, "0128b") for w in words(sig_path))
    s2, p = [], 0
    for _ in range(n):
        sign = bits[p]; low = int(bits[p + 1:p + 8], 2); p += 8
        high = 0
        while bits[p] == "0":
            high += 1; p += 1
            if high > 2047:
                return "invalid encoding (unary part too long)"
        p += 1
        v = (high << 7) | low
        if sign == "1" and v == 0:
            return "invalid encoding (negative zero)"
        s2.append(-v if sign == "1" else v)
    if any(b != "0" for b in bits[p:]):
        return f"invalid encoding (non-zero padding after bit {p})"

    # s1 = c - s2*h mod (x^n + 1, q)
    prod = [0] * n
    for i, a in enumerate(s2):
        if a == 0:
            continue
        for j, b in enumerate(h):
            k = i + j
            if k < n: prod[k] += a * b
            else:     prod[k - n] -= a * b
    s1 = [(ci - pi) % Q for ci, pi in zip(c, prod)]
    s1 = [v - Q if v > Q // 2 else v for v in s1]
    norm = sum(v * v for v in s1) + sum(v * v for v in s2)
    ok = norm <= BOUND2[n]
    return f"{'VALID' if ok else 'INVALID'}: squared norm {norm}, bound {BOUND2[n]}, {p} signature bits"

if __name__ == "__main__":
    print(main(int(sys.argv[1]), *sys.argv[2:5]))
