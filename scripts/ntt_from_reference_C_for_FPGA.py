# NTT from reference C implementation of Falcon, ported to Python and
# modified to be easier to implement in hardware, especially by removing most of the loops
# This computes positive-wrapped NTT.

def ntt(arr, twiddles, q):
    n = len(arr)
    stage = 1
    stride = n >> 1
    butterfly = 0
    group = 0
    i = -1
    counter = 0
    counter_max = n >> 1

    while not (stride == 1 and butterfly == n >> 1):

        if butterfly == n >> 1:
            stride >>= 1
            stage <<= 1
            butterfly = 0
            group = -1
            counter_max >>= 1
            counter = n
            i = -1

        if counter >= counter_max:
            group += 1
            i = group * (stride << 1)
            counter = 1
        else:
            i += 1
            counter += 1
        butterfly += 1

        twiddle = twiddles(stage + group)
        a = arr[i]
        b = (arr[i + stride] * twiddle) % q
        arr[i] = (a + b) % q
        arr[i + stride] = (a - b) % q

    return arr


def intt(arr, twiddles, q):
    n = len(arr)
    stage = n
    stride = 1
    butterfly = 0
    group = 0
    i = -1
    counter = 0
    counter_max = 1

    while not (stride == n >> 1 and butterfly == n >> 1):

        if butterfly == n >> 1:
            stride <<= 1
            stage >>= 1
            butterfly = 0
            group = 0
            counter_max <<= 1
            counter = 0
            i = -1

        if counter >= counter_max:
            group += 1
            i = group * (stride << 1)
            counter = 1
        else:
            i += 1
            counter += 1
        butterfly += 1

        twiddle = twiddles((stage >> 1) + group)
        a = arr[i]
        b = arr[i + stride]
        arr[i] = (a + b) % q
        arr[i + stride] = ((a - b) * twiddle) % q
        pass
    for group in range(n):
        arr[group] = (arr[group] * pow(n, -1, q)) % q

    return arr
