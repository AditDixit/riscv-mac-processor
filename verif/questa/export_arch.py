#!/usr/bin/env python3
"""Pre-build the riscv-arch-test images so they can run without a RISC-V compiler.

Usage: export_arch.py <work-dir> [out-dir]   (out-dir default: verif/questa/arch)

Compiles every test exactly as verif/arch/run_arch.py does (needs git and
riscv64-unknown-elf-gcc), then writes to out-dir:
  <test>.hex   the image in $readmemh format; runs of zero words are skipped
               with @address lines (tb_arch.v clears memory first)
  <test>.ref   the Sail reference signature from riscv-arch-test 2.7.4
  tests.txt    one line per test: name halt_addr sig_begin sig_end (decimal)
The committed copy in verif/questa/arch was produced by this script.
"""
import os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "arch"))
sys.path.insert(0, os.path.dirname(HERE))
import run_arch  # noqa: E402


def sparse_hex(src, dst):
    words = [l.strip() for l in open(src) if l.strip()]
    out, gap = [], True
    for i, w in enumerate(words):
        if int(w, 16) == 0:
            gap = True
            continue
        if gap:
            out.append(f"@{i:x}")
            gap = False
        out.append(w)
    open(dst, "w").write("\n".join(out) + "\n")


def main():
    work = os.path.abspath(sys.argv[1])
    out = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.join(HERE, "arch")
    os.makedirs(work, exist_ok=True)
    os.makedirs(out, exist_ok=True)
    suite = run_arch.fetch(work)
    lines = []
    for sub, only in (("I", None), ("M", ["mul-01"])):
        d = os.path.join(suite, "rv32i_m", sub)
        for f in sorted(os.listdir(os.path.join(d, "src"))):
            n = f[:-2]
            if not f.endswith(".S") or (only and n not in only):
                continue
            hexf, syms = run_arch.compile_test(os.path.join(d, "src", f), suite, work)
            sparse_hex(hexf, os.path.join(out, n + ".hex"))
            shutil.copy(os.path.join(d, "references", n + ".reference_output"), os.path.join(out, n + ".ref"))
            lines.append(f"{n} {syms['rvmodel_halt']} {syms['begin_signature']} {syms['end_signature']}")
    open(os.path.join(out, "tests.txt"), "w").write("\n".join(lines) + "\n")
    print(f"exported {len(lines)} tests to {out}")


if __name__ == "__main__":
    main()
