#!/usr/bin/env python3
"""MAC vs mul+add benchmarks on the RTL pipeline.

Usage: bench.py <build-dir>
Every benchmark is run on the RTL and on the reference simulator; both must
match each other and an independent pure-Python computation of the result.
Prints a Markdown table.
"""
import random, sys
import rvtools, simrun

M32 = 0xFFFFFFFF


def madd(variant, acc="a0", x="t0", y="t1"):
    if variant == "mac":
        return f"mac {acc}, {x}, {y}"
    return f"mul t2, {x}, {y}\nadd {acc}, {acc}, t2"


def dot_rolled(n, v):
    B, R = n * 4, 2 * n * 4
    return f"""li a0, 0
li t3, 0
li t4, {n*4}
loop:
lw t0, 0(t3)
lw t1, {B}(t3)
{madd(v)}
addi t3, t3, 4
bne t3, t4, loop
sw a0, {R}(x0)
halt: jal x0, 0"""


def dot_unrolled(n, v):
    B, R = n * 4, 2 * n * 4
    regs = [("t0", "t1"), ("t5", "t6"), ("s2", "s3"), ("s4", "s5")]
    body = []
    for i, (x, y) in enumerate(regs):
        body += [f"lw {x}, {4*i}(t3)", f"lw {y}, {B+4*i}(t3)"]
    for x, y in regs:
        body.append(madd(v, "a0", x, y))
    return f"""li a0, 0
li t3, 0
li t4, {n*4}
loop:
{chr(10).join(body)}
addi t3, t3, 16
bne t3, t4, loop
sw a0, {R}(x0)
halt: jal x0, 0"""


def fir(m, k, v):
    H, Y = (m + k - 1) * 4, (m + k - 1 + k) * 4
    return f"""li s2, 0
li s3, {m*4}
oloop:
li a0, 0
li t3, 0
li t4, {k*4}
iloop:
add t5, s2, t3
lw t0, 0(t5)
lw t1, {H}(t3)
{madd(v)}
addi t3, t3, 4
bne t3, t4, iloop
sw a0, {Y}(s2)
addi s2, s2, 4
bne s2, s3, oloop
halt: jal x0, 0"""


def matmul(n, v):
    B, C = n * n * 4, 2 * n * n * 4
    return f"""li s2, 0
li s4, {n*n*4}
li t4, {n*4}
oi:
li s3, 0
oj:
li a0, 0
li t3, 0
mv t6, s3
ik:
add t5, s2, t3
lw t0, 0(t5)
lw t1, {B}(t6)
{madd(v)}
addi t3, t3, 4
addi t6, t6, {n*4}
bne t3, t4, ik
add t5, s2, s3
sw a0, {C}(t5)
addi s3, s3, 4
bne s3, t4, oj
addi s2, s2, {n*4}
bne s2, s4, oi
halt: jal x0, 0"""


def signed(v):
    return v - (1 << 32) if v >> 31 else v


def make(name, rng):
    """Return (generator, data words, expected {word_index: value})."""
    r = lambda: rng.randint(-100, 100) & M32
    if name.startswith("dot"):
        n = int(name.split("_")[-1]); unrolled = "unrolled" in name
        a, b = [r() for _ in range(n)], [r() for _ in range(n)]
        exp = {2 * n: sum(signed(x) * signed(y) for x, y in zip(a, b)) & M32}
        return (dot_unrolled if unrolled else dot_rolled, (n,), a + b, exp)
    if name.startswith("fir"):
        _, m, k = name.split("_"); m, k = int(m), int(k)
        x, h = [r() for _ in range(m + k - 1)], [r() for _ in range(k)]
        exp = {m + k - 1 + k + i: sum(signed(h[j]) * signed(x[i + j]) for j in range(k)) & M32 for i in range(m)}
        return (fir, (m, k), x + h, exp)
    n = int(name.split("_")[-1])
    A = [[r() for _ in range(n)] for _ in range(n)]
    Bm = [[r() for _ in range(n)] for _ in range(n)]
    flat = lambda M: [v for row in M for v in row]
    exp = {2 * n * n + i * n + j: sum(signed(A[i][k]) * signed(Bm[k][j]) for k in range(n)) & M32
           for i in range(n) for j in range(n)}
    return (matmul, (n,), flat(A) + flat(Bm), exp)


NAMES = ["dot_8", "dot_16", "dot_32", "dot_64", "dot_unrolled_16", "dot_unrolled_64",
         "fir_32_8", "fir_32_16", "matmul_4", "matmul_8"]


def main():
    exe = simrun.build(sys.argv[1])
    rows, bad = [], 0
    for name in NAMES:
        rng = random.Random(name)
        gen, args, data, exp = make(name, rng)
        res = {}
        for v in ("mul", "mac"):
            words = rvtools.assemble(gen(*args, v))
            assert len(words) <= 255, (name, len(words))
            ix, idm, steps, _ = rvtools.run_iss(words, data)
            hx, hd, cyc = simrun.run_rtl(exe, words, data)
            ok = (ix == hx and idm == hd and all(hd[i] == e for i, e in exp.items()))
            bad += not ok
            res[v] = (cyc, steps, ok, len(words))
        (c1, s1, o1, w1), (c2, s2, o2, w2) = res["mul"], res["mac"]
        rows.append((name, s1, c1, s2, c2, c1 / c2, w1, w2, o1 and o2))
    print("| Benchmark | mul+add instrs | mul+add cycles | MAC instrs | MAC cycles | Speed-up | Code words (mul+add / MAC) | Correct |")
    print("|---|---|---|---|---|---|---|---|")
    for n, s1, c1, s2, c2, sp, w1, w2, ok in rows:
        print(f"| `{n}` | {s1} | {c1} | {s2} | {c2} | {sp:.2f}x | {w1} / {w2} | {'yes' if ok else 'NO'} |")
    print(f"BENCH-STATUS mismatches={bad}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
