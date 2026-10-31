#!/usr/bin/env python3
"""Directed regression programs (RTL vs reference simulator). Usage: directed_tests.py <build-dir>"""
import sys
import rvtools, simrun

TESTS = {
    "auipc value":        "nop\nnop\nauipc x12, 0\nhalt: jal x0, 0",
    "auipc + imm":        "nop\nauipc x5, 0x12\naddi x6, x5, 1\nhalt: jal x0, 0",
    "auipc then jalr":    "nop\nauipc x12, 0\njalr x13, 12(x12)\naddi x8, x0, 7\nhalt: jal x0, 0",
    "auipc after branch": "li x1, 1\nbne x1, x0, t\nauipc x2, 0\nt: auipc x3, 0\nhalt: jal x0, 0",
    "lui + addi":         "lui x5, 0x92bd1\naddi x5, x5, 0x74e\nhalt: jal x0, 0",
    "load -> mac acc":    "li x1, 100\nsw x1, 0(x0)\nli x2, 3\nli x3, 4\nlw x1, 0(x0)\nmac x1, x2, x3\nhalt: jal x0, 0",
    "mac chain":          "li x1, 0\nli x2, 3\nli x3, 4\nmac x1, x2, x3\nmac x1, x2, x3\nmac x1, x2, x3\nhalt: jal x0, 0",
    "mul -> add fwd":     "li x1, 6\nli x2, 7\nmul x3, x1, x2\nadd x4, x3, x3\nhalt: jal x0, 0",
    "lb/lbu all lanes":   "li x1, 0x80FF7F01\nsw x1, 8(x0)\nlb x2, 8(x0)\nlb x3, 9(x0)\nlb x4, 10(x0)\nlb x5, 11(x0)\n"
                          "lbu x6, 10(x0)\nlbu x7, 11(x0)\nhalt: jal x0, 0",
    "lh/lhu both halves": "li x1, 0x80017FFE\nsw x1, 8(x0)\nlh x2, 8(x0)\nlh x3, 10(x0)\nlhu x4, 8(x0)\nlhu x5, 10(x0)\n"
                          "halt: jal x0, 0",
    "sb/sh lane merge":   "li x1, -1\nsw x1, 12(x0)\nli x2, 0x12\nsb x2, 13(x0)\nli x3, 0x3456\nsh x3, 14(x0)\n"
                          "lw x4, 12(x0)\nhalt: jal x0, 0",
    "lb -> use stall":    "li x1, 0xF0\nsb x1, 4(x0)\nlb x2, 4(x0)\nadd x3, x2, x2\nhalt: jal x0, 0",
    "lbu -> mac acc":     "li x1, 200\nsb x1, 4(x0)\nli x2, 3\nli x3, 4\nlbu x5, 4(x0)\nmac x5, x2, x3\nhalt: jal x0, 0",
    "fence no-op":        "li x1, 5\nfence\naddi x2, x1, 1\nhalt: jal x0, 0",
}

def main():
    exe = simrun.build(sys.argv[1])
    bad = 0
    for name, src in TESTS.items():
        w = rvtools.assemble(src)
        ix, im, _, _ = rvtools.run_iss(w, [])
        hx, hm, _ = simrun.run_rtl(exe, w, [])
        ok = ix == hx and im == hm
        bad += not ok
        print(f"{'PASS' if ok else 'FAIL'}  {name}")
    print(f"DIRECTED passed={len(TESTS)-bad} failed={bad}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
