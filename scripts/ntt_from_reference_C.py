# NTT from reference C implementation of Falcon, ported to Python
# This computes negative-wrapped NTT.


def ntt(arr, twiddles, q):
    n = len(arr)
    stage = 1
    stride = n >> 1

    while stage < n:
        for group in range(stage):
            twiddle = twiddles(stage + group)
            start = group * (stride << 1)
            for i in range(start, start + stride):
                print(f"i: {i}, stride: {stride}, stage: {stage}, group: {group}, start: {start}, address: {stage + group}")
                a = arr[i]
                b = (arr[i + stride] * twiddle) % q
                arr[i] = (a + b) % q
                arr[i + stride] = (a - b) % q
        print()

        stride >>= 1
        stage <<= 1

    return arr


def intt(arr, twiddles, q):
    n = len(arr)
    stage = n
    stride = 1

    while stage > 1:
        for group in range(stage >> 1):
            twiddle = twiddles((stage >> 1) + group)
            start = group * (stride << 1)
            for i in range(start, start + stride):
                print(f"i: {i}, stride: {stride}, stage: {stage}, group: {group}, start: {start}, address: {(stage >> 1) + group}")

                a = arr[i]
                b = arr[i + stride]
                arr[i] = (a + b) % q
                arr[i + stride] = ((a - b) * twiddle) % q
        print()
        stride <<= 1
        stage >>= 1

    # Scale the result
    for group in range(n):
        arr[group] = (arr[group] * pow(n, -1, q)) % q

    return arr
