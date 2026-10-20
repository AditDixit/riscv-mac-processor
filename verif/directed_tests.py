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
}

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
