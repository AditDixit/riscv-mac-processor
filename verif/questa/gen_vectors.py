#!/usr/bin/env python3
"""Generate test vectors for tb_batch.v (Questa/ModelSim flow). Pure Python.

Usage: gen_vectors.py <out-dir> [random_per_seed]

Writes, in <out-dir>:
  directed.vec / directed.names   the 14 directed programs (verif/directed_tests.py)
  bench.vec    / bench.names      the 10 benchmark kernels, mul+add and MAC (verif/bench.py)
  random.vec                      random hazard-heavy programs (verif/random_diff.py),
                                  seeds 1-8 and 11-18, random_per_seed each (default 500)

Every program is assembled and run on the reference simulator (verif/rvtools.py)
to get the expected final registers, data memory and instruction count. Benchmark
results are also checked against an independent Python computation, exactly as
verif/bench.py does. Needs only Python 3 (no Verilator, no RISC-V GCC).
"""
import os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import rvtools                     # noqa: E402
import bench                       # noqa: E402
from random_diff import gen        # noqa: E402
from directed_tests import TESTS   # noqa: E402

SEEDS = [1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13, 14, 15, 16, 17, 18]


def record(words, data):
    """One program's vector record, as a list of 32-bit words."""
    assert len(words) <= 256 and rvtools.HALT in words
    data = list(data or [])
    regs, mem, steps, _ = rvtools.run_iss(words, data)
    halt = 4 * words.index(rvtools.HALT)
    pad = lambda xs: list(xs) + [0] * (256 - len(xs))
    return [halt, steps] + pad(words) + pad(data) + regs + mem, regs, mem


def write_vec(path, records):
    with open(path, "w") as f:
        f.write(f"{len(records):08x}\n")
        for r in records:
            f.write("\n".join(f"{w & 0xFFFFFFFF:08x}" for w in r) + "\n")


def main():
    out = sys.argv[1]
    per_seed = int(sys.argv[2]) if len(sys.argv) > 2 else 500
    os.makedirs(out, exist_ok=True)

    recs, names = [], []
    for name, src in TESTS.items():
        recs.append(record(rvtools.assemble(src), [])[0])
        names.append(name)
    write_vec(os.path.join(out, "directed.vec"), recs)
    open(os.path.join(out, "directed.names"), "w").write("\n".join(names) + "\n")
    print(f"directed: {len(recs)} programs")

    recs, names = [], []
    for name in bench.NAMES:
        g, args, data, exp = bench.make(name, random.Random(name))
        for v in ("mul", "mac"):
            r, regs, mem = record(rvtools.assemble(g(*args, v)), data)
            assert all(mem[i] == e for i, e in exp.items()), f"{name} {v}: reference != Python"
            recs.append(r)
            names.append(f"{name} {v}")
    write_vec(os.path.join(out, "bench.vec"), recs)
    open(os.path.join(out, "bench.names"), "w").write("\n".join(names) + "\n")
    print(f"bench: {len(recs)} programs (results checked against Python)")

    recs = []
    for seed in SEEDS:
        rng = random.Random(seed)   # same streams as random_diff.py <dir> N <seed>
        for _ in range(per_seed):
            data = [rng.getrandbits(32) for _ in range(256)]
            words = rvtools.assemble(gen(rng, rng.randint(60, 140)))
            recs.append(record(words, data)[0])
    write_vec(os.path.join(out, "random.vec"), recs)
    print(f"random: {len(recs)} programs (seeds {SEEDS[0]}-8 and 11-18, {per_seed} each)")


if __name__ == "__main__":
    main()
