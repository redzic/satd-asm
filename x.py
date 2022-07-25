from sympy import *


buf = []

for i in range(16):
    # buf.append(Symbol(str(i)))
    # buf.append(Symbol(f"x[{i}]"))
    buf.append(i)


def butterfly(a, b):
    return (a + b, a - b)


def hadamard4_1d(data, n, stride0, stride1):
    for i in range(n):
        # let sub: &mut [i32] = &mut data[i * STRIDE0..];
        idx = i * stride0
        (a0, a1) = butterfly(data[idx + 0 * stride1], data[idx + 1 * stride1])
        (a2, a3) = butterfly(data[idx + 2 * stride1], data[idx + 3 * stride1])
        (b0, b2) = butterfly(a0, a2)
        (b1, b3) = butterfly(a1, a3)
        data[idx + 0 * stride1] = b0
        data[idx + 1 * stride1] = b1
        data[idx + 2 * stride1] = b2
        data[idx + 3 * stride1] = b3


def hadamard4x4(data):
    # vertical transform
    hadamard4_1d(data, 4, 1, 4)
    # horizontal transform
    hadamard4_1d(data, 4, 4, 1)


def satd4x4(data):
    assert len(data) == 16

    hadamard4x4(data)
    # sum up absolute value of transform
    return sum(map(abs, data))


# print(buf)
hadamard4x4(buf)
print(buf)
# for x in buf:
#     print(x)
# print(satd4x4(buf))
