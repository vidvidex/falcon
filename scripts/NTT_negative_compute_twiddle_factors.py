# Computes twiddle factors for the FPGA implementation of negative-wrapped NTT
# This function is taken from the reference C implementation of Falcon, where the table is called GMb/iGMb.
# In that implementation they also use a factor R, which is used for Montgomery multiplication, which we are not using here.

N = 1024  # N = 1024 also works for all smaller Ns that are powers of 2
Q = 12289  # Modulus
g = 7  # Primitive root
g_inv = pow(g, -1, Q)


# Computes NTT twiddle factor at index i
def ntt_twiddle_factor(i):
    rev_i = int("{:010b}".format(i)[::-1], 2)  # Bit reverse i
    return (pow(g, rev_i, Q)) % Q


# Computes INTT twiddle factor at index i
def intt_twiddle_factor(i):
    rev_i = int("{:010b}".format(i)[::-1], 2)  # Bit reverse i
    return (pow(g_inv, rev_i, Q)) % Q


# Computes NTT twiddle factors for NTT of size N
def ntt_twiddle_factors():
    factors = []
    for i in range(N):
        factors.append(ntt_twiddle_factor(i))

    return factors


# Computes INTT twiddle factors for INTT of size N
def intt_twiddle_factors():
    factors = []
    for i in range(N):
        factors.append(intt_twiddle_factor(i))

    return factors


if __name__ == "__main__":
    print(f"Twiddle factors for NTT with N up to {N}:")
    print(ntt_twiddle_factors())
    print()

    print(f"Twiddle factors for INTT with N up to {N}:")
    print(intt_twiddle_factors())
    print()
