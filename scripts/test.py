from ntt import ntt_iter, intt_iter


# Falcon signature verification
def falcon_verify():
    q = 12289
    primitive_root = 4043

    public_key = [7644, 6589, 8565, 4185, 1184, 607, 3842, 5361]
    signature = [16537, 16492, 143, 16600, 16433, 222, 81, 152]
    hashed_message = [1112, 5539, 5209, 3423, 2324, 1901, 12163, 9202]

    ntt_public_key = ntt_iter(public_key, primitive_root, q)
    ntt_signature = ntt_iter(signature, primitive_root, q)

    print(f"public_key = {public_key}")
    print(f"signature = {signature}")
    print(f"NTT(public_key) = {ntt_public_key}")
    print(f"NTT(signature) = {ntt_signature}")

    product = [(ntt_public_key[i] * ntt_signature[i]) % q for i in range(len(public_key))]
    print(f"NTT(public_key) * NTT(signature) = {product}")

    ntt_product = intt_iter(product, primitive_root, q)
    print(f"INTT(product) = {ntt_product}")

    sub = [(hashed_message[i] - ntt_product[i]) % q for i in range(len(hashed_message))]
    print(f"hashed_message - INTT(product) = {sub}")

    normalized = [a - 12289 if a > 6144 else a for a in sub]
    print(f"normalized = {normalized}")

    squared_norm_normalized = sum(a**2 for a in normalized)
    squared_norm_hashed = sum(a**2 for a in hashed_message)
    print(f"squared_norm_normalized = {squared_norm_normalized}")
    print(f"squared_norm_hashed = {squared_norm_hashed}")

    total_sum = squared_norm_normalized + squared_norm_hashed
    print(f"total_sum = {total_sum}")

    print()


# Test for NTT and INTT
def ntt_intt_test():
    print("NTT and INTT")

    q = 12289
    primitive_root = 4043
    a = [i for i in range(1,9)]
    b = [i for i in range(1,9)]

    print(f"a = {a}")
    print(f"b = {b}")

    ntt_a = ntt_iter(a, primitive_root, q)
    print(f"NTT(a) = {ntt_a}")

    ntt_b = ntt_iter(b, primitive_root, q)
    print(f"NTT(b) = {ntt_b}")

    product = [(ntt_a[i] * ntt_b[i]) % q for i in range(len(a))]
    print(f"NTT(a) * NTT(b) = {product}")

    intt_product = intt_iter(product, primitive_root, q)
    print(f"INTT(product) = {intt_product}")

    print()


def test_convolve():
    import numpy as np
    print("numpy cyclic convolution")

    # a = [i for i in range(1,5)]
    # b = [i for i in range(5,9)]
    a = [1 ,1]
    b= [1 ,1]

    cyclic_convolution = np.fft.ifft(np.fft.fft(a, len(a)) * np.fft.fft(b, len(b))).real
    cyclic_convolution = np.round(cyclic_convolution).astype(int)

    cyclic_convolution = [int(cyclic_convolution[i] % 12289) for i in range(len(cyclic_convolution))]

    print(f"a = {a}")
    print(f"b = {b}")
    print(f"a*b = {cyclic_convolution}")

    print()


# Test for NTT and INTT
# ntt_intt_test()

# Test for Falcon signature verification
# falcon_verify()

# Test for convolution
test_convolve()

# import numpy as np

# p1 = np.poly1d([i for i in range(1, 9)])  
# p2 = np.poly1d([i for i in range(1, 9)])  
# mul = np.polymul(p2, p1) 
# print(f'mul = {mul}')