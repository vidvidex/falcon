# Computes twiddle factors for the FPGA implementation of negative-wrapped NTT
# This function is taken from the reference C implementation of Falcon, where the table is called GMb/iGMb.
# In that implementation they also use a factor R, which is used for Montgomery multiplication, which we are not using here.

N = 1024  # N = 1024 also works for all smaller Ns that are powers of 2
g = 7
g_inv = 8778
Q = 12289
twiddle_factors_ntt = []
twiddle_factors_intt = []
for i in range(N):
    rev_i = int("{:010b}".format(i)[::-1], 2)  # Bit reverse i
    twiddle_factors_ntt.append((pow(g, rev_i, Q)) % Q)
    twiddle_factors_intt.append((pow(g_inv, rev_i, Q)) % Q)

print(twiddle_factors_ntt)
print(twiddle_factors_intt)
