# Source: https://cryptographycaffe.sandboxaq.com/posts/ntt-02/
# This computes positive-wrapped NTT.
# it can be modified to also compute negative-wrapped NTT, see the negative_wrapped_convolution() below.

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


# Shows how to compute negative-wrapped convolution with this NTT implementation.
# This is also explained towards the end of the blog post linked above.
def negative_wrapped_convolution():

    a = [i for i in range(1, 5)]
    b = [i for i in range(5, 9)]

    q = 12289  # Modulus
    primitive_root4 = 1479  # Primitive root of unity for N = 4 (size of input polynomials)
    primitive_root8 = 4043  # Primitive root of unity for 2*N = 8
    primitive_root8_inv = pow(primitive_root8, -1, q)

    print(f"a = {a}")
    print(f"b = {b}")

    gen = [pow(primitive_root8, i, q) for i in range(len(a))]
    gen_inv = [pow(primitive_root8_inv, i, q) for i in range(len(a))]
    print(f"gen = {gen}")
    print(f"gen_inv = {gen_inv}")

    # Preprocess a and b by multiplying with the generator
    a_mul = [a[i] * gen[i] % q for i in range(len(a))]
    b_mul = [b[i] * gen[i] % q for i in range(len(b))]

    print(f"a*gen = {a_mul}")
    print(f"b*gen = {b_mul}")

    ntt_a = ntt(a_mul, primitive_root4, q)
    print(f"NTT(a*gen) = {ntt_a}")

    ntt_b = ntt(b_mul, primitive_root4, q)
    print(f"NTT(b*gen) = {ntt_b}")

    product = [(ntt_a[i] * ntt_b[i]) % q for i in range(len(a))]
    print(f"NTT(a*gen) * NTT(b*gen) = {product}")

    intt_product = intt(product, primitive_root4, q)
    print(f"INTT(product) = {intt_product}")
    
    # Postprocess the result by multiplying with the inverse generator
    intt_product_mul = [intt_product[i] * gen_inv[i] % q for i in range(len(intt_product))]
    print(f"INTT(product) * gen_inv = {intt_product_mul}")
