#!/usr/bin/env python3
"""Differential random testing: RTL pipeline vs the Python reference simulator.

Usage: random_diff.py <build-dir> [num_programs] [seed]
Each program initialises registers, runs a random mix of ALU, MAC,
byte/halfword/word loads and stores, fences,
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


def mem_operand(rng, op):
    """Naturally aligned address operand for a load/store of op's width.
    x9 holds a word-aligned base; x0-relative offsets cover the whole 1 KB."""
    align = {"b": 1, "h": 2, "w": 4}[op[1]]
    if rng.random() < .5:
        return f"{rng.randrange(0, 512 // align) * align}(x9)"
    return f"{rng.randrange(0, 1024 // align) * align}(x0)"


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
            op = rng.choice(["lw", "lw", "lw", "lb", "lbu", "lh", "lhu"])
            L.append(f"{op} {r()}, {mem_operand(rng, op)}")
        elif c < 0.84:
            op = rng.choice(["sw", "sw", "sb", "sh"])
            L.append(f"{op} {r()}, {mem_operand(rng, op)}")
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
        elif c < 0.98:
            L.append("auipc x12, 0")
            L.append(f"jalr x13, 12(x12)")
            L.append(f"addi {r()}, {r()}, 7")
        elif c < 0.985:
            L.append("fence")
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
