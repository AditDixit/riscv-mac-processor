#!/usr/bin/env python3
"""Code coverage of the pipeline RTL over the program-level regression.

Usage: coverage.py <build-dir> [random_programs] [seed]

Builds tb_prog_runner with Verilator line + toggle coverage, runs the directed
programs, every benchmark kernel and a batch of random programs, merges the
per-run coverage files and prints per-file line coverage and overall toggle
coverage. Annotated sources are written to <build-dir>/annotated/ (lines
prefixed with %000000 were never executed).
"""
import os, random, re, subprocess, sys
import rvtools, simrun, bench
from random_diff import gen
from directed_tests import TESTS

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.dirname(HERE)


# Minimal timing-aware main that saves coverage to $COV_FILE when the run ends
# (Verilator's --binary main does not write coverage in all versions).
MAIN_CPP = r"""
#include <cstdlib>
#include <memory>
#include "verilated.h"
#include "verilated_cov.h"
#include "Vtb_prog_runner.h"
int main(int argc, char** argv) {
    auto ctx = std::make_unique<VerilatedContext>();
    ctx->commandArgs(argc, argv);
    auto top = std::make_unique<Vtb_prog_runner>(ctx.get());
    while (!ctx->gotFinish()) {
        top->eval();
        if (!top->eventsPending()) break;
        ctx->time(top->nextTimeSlot());
    }
    top->final();
    const char* f = std::getenv("COV_FILE");
    ctx->coveragep()->write(f ? f : "coverage.dat");
    return 0;
}
"""


def build(work):
    main = os.path.join(work, "cov_main.cpp")
    open(main, "w").write(MAIN_CPP)
    cmd = ["verilator", "--cc", "--exe", "--build", "--timing", "--coverage-line", "--coverage-toggle",
           "-Wno-fatal", "-Wno-lint", "-Wno-style", "--top-module", "tb_prog_runner",
           "-Mdir", work, "-CFLAGS", "-std=c++20 -fcoroutines", main,
           os.path.join(HERE, "tb_prog_runner.v")] + [os.path.join(RTL, s) for s in simrun.SRCS]
    subprocess.run(cmd, check=True, capture_output=True, text=True)
    return os.path.join(work, "Vtb_prog_runner")


def run(exe, words, data, cov_file, tmp):
    p, d, o = (os.path.join(tmp, n) for n in ("prog.hex", "data.hex", "out.txt"))
    rvtools.write_hex(p, words)
    rvtools.write_hex(d, data or [])
    halt = 4 * words.index(rvtools.HALT)
    subprocess.run([exe, f"+PROG={p}", f"+DATA={d}", f"+HALT={halt}", f"+OUT={o}"],
                   check=True, capture_output=True, env=dict(os.environ, COV_FILE=cov_file))


def main():
    work = os.path.abspath(sys.argv[1])
    n_rand = int(sys.argv[2]) if len(sys.argv) > 2 else 500
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    os.makedirs(work, exist_ok=True)
    exe = build(work)
    tmp = os.path.join(work, "run"); os.makedirs(tmp, exist_ok=True)
    covdir = os.path.join(work, "cov"); os.makedirs(covdir, exist_ok=True)

    progs = [(rvtools.assemble(src), []) for src in TESTS.values()]
    for name in bench.NAMES:
        g, args, data, _ = bench.make(name, random.Random(name))
        progs += [(rvtools.assemble(g(*args, v)), data) for v in ("mul", "mac")]
    rng = random.Random(seed)
    for _ in range(n_rand):
        data = [rng.getrandbits(32) for _ in range(256)]
        progs.append((rvtools.assemble(gen(rng, rng.randint(60, 140))), data))

    files = []
    for i, (w, d) in enumerate(progs):
        f = os.path.join(covdir, f"c{i}.dat")
        run(exe, w, d, f, tmp)
        files.append(f)

    merged = os.path.join(work, "merged.dat")
    subprocess.run(["verilator_coverage", "--write", merged] + files, check=True, capture_output=True)
    ann = os.path.join(work, "annotated")
    r = subprocess.run(["verilator_coverage", "--annotate", ann, "--annotate-min", "1", merged],
                       check=True, capture_output=True, text=True)

    # Per-file line coverage from the annotated sources (RTL files only).
    print(f"programs run: {len(progs)} ({len(TESTS)} directed, {2 * len(bench.NAMES)} kernels, "
          f"{n_rand} random)")
    print("| RTL file | Lines hit / instrumented | Line coverage |")
    print("|---|---|---|")
    th = tt = 0
    for src in simrun.SRCS:
        path = os.path.join(ann, src)
        if not os.path.exists(path):
            continue
        hit = tot = 0
        for line in open(path):
            m = re.match(r"^[ %](\d{6})", line)
            if m:
                tot += 1
                hit += int(m.group(1)) > 0
        if tot:
            th += hit; tt += tot
            print(f"| {src} | {hit} / {tot} | {100 * hit / tot:.1f}% |")
    print(f"| **Total** | {th} / {tt} | **{100 * th / tt:.1f}%** |")
    print("verilator_coverage summary:", " ".join(r.stdout.split()[-8:]))


if __name__ == "__main__":
    main()
