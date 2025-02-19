# For more info: A Complete Beginner Guide to the Number Theoretic Transform (NTT)
# Use this script to generate the twiddle factors

def is_primitive_root(w, n, q):
    """Check if w is a primitive n-th root of unity modulo q."""
    if pow(w, n, q) != 1:
        return False  # Must satisfy w^n ≡ 1 (mod q)

    for k in range(1, n):
        if pow(w, k, q) == 1:
            return False  # Must not satisfy w^k ≡ 1 (mod q) for k < n

    return True


def find_primitive_root(n, q):
    """Find a primitive n-th root of unity modulo q."""
    for w in range(2, q):
        if is_primitive_root(w, n, q):
            return w
    return None  # No primitive root found


def twiddle_factor(root, n, q):
    return [(pow(root, k, q)) for k in range(n // 2)]


# Change params here
ns = [4]
q = 12289
for n in ns:
    primitive_root = find_primitive_root(n, q)
    primitive_root_inverse = pow(primitive_root, -1, q)

    if primitive_root:
        print(f"A primitive {n}-th root of unity modulo {q} is omega={primitive_root}, omega^-1 = {primitive_root_inverse}")
        print(f"Forward twiddle factors: {twiddle_factor(primitive_root, n, q)}")
        print(f"Inverse twiddle factors: {twiddle_factor(primitive_root_inverse, n, q)}")
        print()
    else:
        print(f"No primitive {n}-th root of unity found modulo {q}")
