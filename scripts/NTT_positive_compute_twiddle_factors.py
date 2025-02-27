# Computes twiddle factors for the FPGA implementation of positive-wrapped NTT
# For more info: A Complete Beginner Guide to the Number Theoretic Transform (NTT)

# Change params here
Ns = [8]    # For what sizes N do you want to compute the primitive roots and twiddle factors?
q = 12289   # Modulus

def is_primitive_nth_root(w, n, q):
    """Check if w is a primitive n-th root of unity modulo q."""
    if pow(w, n, q) != 1:
        return False  # Must satisfy w^n ≡ 1 (mod q)

    for k in range(1, n):
        if pow(w, k, q) == 1:
            return False  # Must not satisfy w^k ≡ 1 (mod q) for k < n

    return True

def find_primitive_nth_root(n, q):
    """Find a primitive n-th root of unity modulo q."""
    for w in range(2, q):
        if is_primitive_nth_root(w, n, q):
            return w
    return None  # No primitive root found


def twiddle_factor(root, n, q):
    return [(pow(root, k, q)) for k in range(n // 2)]

for n in Ns:
    primitive_root = find_primitive_nth_root(n, q)
    primitive_root_inv = pow(primitive_root, -1, q)

    if primitive_root:
        print(f"A primitive {n}-th root of unity modulo {q} is omega={primitive_root}, omega^-1 = {primitive_root_inv} (for positively wrapped convolution)")

        print(f"Forward twiddle factors: {twiddle_factor(primitive_root, n, q)}")
        print(f"Inverse twiddle factors: {twiddle_factor(primitive_root_inv, n, q)}")
        print()
    else:
        print(f"No primitive {n}-th root of unity found modulo {q}")
