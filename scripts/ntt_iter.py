# Source: https://cryptographycaffe.sandboxaq.com/posts/ntt-02/

import math


def brv(x, n):
    """Reverses a n-bit number"""
    return int("".join(reversed(bin(x)[2:].zfill(n))), 2)


def ntt(a, gen, modulus):
    deg_d = len(a)

    # Start with stride = 1.
    stride = 1

    # Shuffle the input array in bit-reversal order.
    nbits = int(math.log2(deg_d))
    res = [a[brv(i, nbits)] for i in range(deg_d)]

    # Pre-compute the generators used in different stages of the recursion.
    gens = [pow(gen, pow(2, i), modulus) for i in range(nbits)]
    # The first layer uses the lowest (2nd) root of unity, hence the last one.
    gen_ptr = len(gens) - 1

    # Iterate until the last layer.
    while stride < deg_d:
        # For each stride, iterate over all N//(stride*2) slices.
        for start in range(0, deg_d, stride * 2):
            # For each pair of the CT butterfly operation.
            for i in range(start, start + stride):
                # Compute the omega multiplier. Here j = i - start.
                zp = pow(gens[gen_ptr], i - start, modulus)

                # Cooley-Tukey butterfly.
                a = res[i]
                b = res[i + stride]
                res[i] = (a + zp * b) % modulus
                res[i + stride] = (a - zp * b) % modulus

        # Grow the stride.
        stride <<= 1
        # Move to the next root of unity.
        gen_ptr -= 1

    return res


def intt(a, gen, modulus):
    deg_d = len(a)

    # Start with stride = N/2.
    stride = deg_d // 2

    # Shuffle the input array in bit-reversal order.
    nbits = int(math.log2(deg_d))
    res = a[:]

    # Pre-compute the inverse generators used in different stages of the recursion.
    gen = pow(gen, -1, modulus)
    gens = [pow(gen, pow(2, i), modulus) for i in range(nbits)]
    # The first layer uses the highest (d-th) root of unity, hence the first one.
    gen_ptr = 0

    # Iterate until the last layer.
    while stride > 0:
        # For each stride, iterate over all N//(stride*2) slices.
        for start in range(0, deg_d, stride * 2):
            # For each pair of the CT butterfly operation.
            for i in range(start, start + stride):
                # Compute the omega multiplier. Here j = i - start.
                zp = pow(gens[gen_ptr], i - start, modulus)

                # Gentleman-Sande butterfly.
                a = res[i]
                b = res[i + stride]
                res[i] = (a + b) % modulus
                res[i + stride] = ((a - b) * zp) % modulus

        # Grow the stride.
        stride >>= 1
        # Move to the next root of unity.
        gen_ptr += 1

    # Scale it down before returning.
    scaler = pow(deg_d, -1, modulus)

    # Reverse shuffle and return.
    return [(res[brv(i, nbits)] * scaler) % modulus for i in range(deg_d)]
