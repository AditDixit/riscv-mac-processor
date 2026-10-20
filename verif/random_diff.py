#!/usr/bin/env python3
"""Differential random testing: RTL pipeline vs the Python reference simulator.

Usage: random_diff.py <build-dir> [num_programs] [seed]
Each program initialises registers, runs a random mix of ALU, MAC, load/store,
forward branches and jumps (small register set to force hazards), then halts.
Final registers and data memory of the RTL must equal the reference exactly.
"""
import random, sys, tempfile
import rvtools, simrun

REGS = [f"x{i}" for i in range(1, 9)]
RO = ["add", "sub", "and", "or", "xor", "sll", "srl", "sra", "slt", "sltu", "mul"]
IO = ["addi", "andi", "ori", "xori", "slti", "sltiu"]
SO = ["slli", "srli", "srai"]
BO = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]


def gen(rng, n_body):
    L = []
    for i, r in enumerate(REGS):
        L.append(f"li {r}, {rng.choice([rng.getrandbits(32), rng.randint(-8, 8), rng.randint(-2048, 2047)])}")
    L.append(f"li x9, {rng.randrange(0, 256) * 4}")  # base pointer
    for k in range(n_body):
        c = rng.random()
        r = lambda: rng.choice(REGS)
        if c < 0.25:
            L.append(f"{rng.choice(RO)} {r()}, {r()}, {r()}")
        elif c < 0.40:
            L.append(f"{rng.choice(IO)} {r()}, {r()}, {rng.randint(-2048, 2047)}")
        elif c < 0.46:
            L.append(f"{rng.choice(SO)} {r()}, {r()}, {rng.randint(0, 31)}")
        elif c < 0.62:
            L.append(f"mac {r()}, {r()}, {r()}")
        elif c < 0.74:
            L.append(f"lw {r()}, {rng.randrange(0, 128) * 4}(x9)" if rng.random() < .5 else f"lw {r()}, {rng.randrange(0, 255) * 4 % 2048}(x0)")
        elif c < 0.84:
            L.append(f"sw {r()}, {rng.randrange(0, 128) * 4}(x9)" if rng.random() < .5 else f"sw {r()}, {rng.randrange(0, 255) * 4 % 2048}(x0)")
        elif c < 0.93:
            skip = rng.randint(1, 3)
            L.append(f"{rng.choice(BO)} {r()}, {r()}, skip{k}")
            for _ in range(skip):
                L.append(f"{rng.choice(RO)} {r()}, {r()}, {r()}" if rng.random() < .5 else f"mac {r()}, {r()}, {r()}")
            L.append(f"skip{k}:")
        elif c < 0.97:
            L.append(f"jal x{rng.choice([0, 10, 11])}, jt{k}")
            L.append(f"addi {r()}, {r()}, 1")
            L.append(f"jt{k}:")
        elif c < 0.985:
            L.append("auipc x12, 0")
            L.append(f"jalr x13, 12(x12)")
            L.append(f"addi {r()}, {r()}, 7")
        else:
            L.append(f"lui {r()}, {rng.getrandbits(20)}")
    L.append("halt: jal x0, 0")
    return "\n".join(L)


def main():
    work = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    exe = simrun.build(work)
    rng = random.Random(seed)
    tmp = tempfile.mkdtemp()
    fails, total_instr = 0, 0
    for t in range(n):
        data = [rng.getrandbits(32) for _ in range(256)]
        words = rvtools.assemble(gen(rng, rng.randint(60, 140)))
        assert len(words) <= 255
        rx, rd, steps, _ = rvtools.run_iss(words, data)
        hx, hd, cyc = simrun.run_rtl(exe, words, data, tmp)
        total_instr += steps
        if rx != hx or rd != hd:
            fails += 1
            bad = [i for i in range(32) if rx[i] != hx[i]]
            badm = [i for i in range(256) if rd[i] != hd[i]]
            print(f"MISMATCH program {t}: regs {bad[:6]} mem {badm[:6]}")
            if fails == 1:
                open(f"{work}/fail_{t}.s", "w").write("\n".join(f"{w:08x}" for w in words))
    print(f"RANDOM-DIFF programs={n} seed={seed} dynamic_instrs={total_instr} mismatches={fails}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
