#!/usr/bin/env python3
"""CPI and hazard statistics for the pipeline.

Usage: perf.py <build-dir> [random_programs] [seed]

For every benchmark kernel (both mul+add and MAC variants) and for a batch of
random hazard-heavy programs, runs the RTL with performance counters and
reports CPI with a breakdown of where the extra cycles go:

    cycles = instructions + 3 (startup) + load-use stalls
             + 2 x (taken branches + jumps)

The script checks that identity holds exactly for every program, so the
counters are validated against the cycle count rather than trusted.
"""
import random, sys
import rvtools, simrun, bench
from random_diff import gen

FILL, FLUSH = 3, 2   # startup = reset-release edge + IF->ID->EX for the first instr


def run(exe, words, data):
    rx, rd, steps, _ = rvtools.run_iss(words, data)
    hx, hd, cyc, st = simrun.run_rtl_stats(exe, words, data)
    assert rx == hx and rd == hd, "RTL / reference mismatch"
    predicted = steps + FILL + st["stall"] + FLUSH * st["ctrl"]
    assert predicted == cyc, f"cycle identity broken: {predicted} != {cyc} {st}"
    return steps, cyc, st


def main():
    exe = simrun.build(sys.argv[1])
    n_rand = int(sys.argv[2]) if len(sys.argv) > 2 else 500
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1

    print("| Program | Instrs | Cycles | CPI | Load-use stall cycles | Taken branches+jumps "
          "(2-cycle flush) | EX/MEM fwds | MEM/WB fwds | MAC acc bypasses |")
    print("|---|---|---|---|---|---|---|---|---|")
    for name in bench.NAMES:
        g, args, data, _ = bench.make(name, random.Random(name))
        for v in ("mul", "mac"):
            s, c, st = run(exe, rvtools.assemble(g(*args, v)), data)
            print(f"| `{name}` {'mul+add' if v == 'mul' else 'MAC'} | {s} | {c} | {c / s:.3f} | "
                  f"{st['stall']} | {st['ctrl']} | {st['fwd_ex']} | {st['fwd_mem']} | {st['mac_bypass']} |")

    rng = random.Random(seed)
    tot = dict(steps=0, cyc=0, stall=0, ctrl=0, fwd_ex=0, fwd_mem=0, mac_bypass=0)
    for _ in range(n_rand):
        data = [rng.getrandbits(32) for _ in range(256)]
        words = rvtools.assemble(gen(rng, rng.randint(60, 140)))
        s, c, st = run(exe, words, data)
        tot["steps"] += s; tot["cyc"] += c
        for k in st:
            tot[k] += st[k]
    s, c = tot["steps"], tot["cyc"]
    print(f"\nRANDOM programs={n_rand} seed={seed} instrs={s} cycles={c} CPI={c / s:.3f} "
          f"(fill {FILL * n_rand / s:.3f} + load-use {tot['stall'] / s:.3f} + "
          f"control {FLUSH * tot['ctrl'] / s:.3f}) fwd_ex={tot['fwd_ex']} fwd_mem={tot['fwd_mem']} "
          f"mac_bypass={tot['mac_bypass']}")
    print("PERF-STATUS identity holds for all programs")


if __name__ == "__main__":
    main()
