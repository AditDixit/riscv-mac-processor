#!/usr/bin/env python3
"""Run the whole verification suite in Questa / ModelSim (Intel FPGA edition).

Usage:
  python verif/questa/run_questa.py <suite> [options]
    suite: tbs | directed | bench | random | arch | all
  options:
    --vectors DIR   vectors from gen_vectors.py (default: verif/questa/vectors)
    --build DIR     work directory (default: verif/questa/build)
    --sim questa    (default) uses vlib / vlog / vsim from your PATH
    --sim icarus    uses iverilog / vvp instead (same testbenches)
    --async-mem     simulate the plain memories (imem.v, dmem.v) instead of the
                    block-RAM variant (imem_sync.v, dmem_sync.v) that the
                    Quartus / MAX 10 build uses (FPGA_SYNC_MEM)

Suites:
  tbs       the 7 directed testbenches; counts PASS lines        (expect 180 PASS, 0 FAIL)
  directed  14 directed programs vs the reference simulator       (expect 14 pass)
  bench     10 kernels x {mul+add, MAC}: cycles, speed-up, CPI    (expect 0 failing)
  random    random hazard-heavy programs vs the reference         (expect 0 failing)
  arch      39 official riscv-arch-test programs vs Sail          (expect 39/39)
  all       everything above, then a summary

Each suite prints a table and writes it to <build>/report.md. directed,
bench and random need gen_vectors.py to have been run first (pure Python).
"""
import argparse, os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
RTL = ["ALU.v", "Forward_units.v", "Hazard_units.v", "Imem.v", "RegFile.v", "control.v",
       "dmem.v", "lsu_align.v", "mul_pipe.v", "imem_sync.v", "dmem_sync.v", "pipeline_reg.v",
       "riscv_single.v", "Riscv_pipeline.v"]
TBS = [("tb_memory_regfile", "Tb_memory_regfile.v"), ("tb_alu", "Tb_ALU.v"),
       ("tb_control", "tb_control.v"), ("tb_hazard_forward", "tb_hazard_forward.v"),
       ("tb_riscv_single", "tb_riscv_single.v"), ("tb_riscv_pipeline", "tb_riscv_pipeline.v"),
       ("tb_benchmark", "tb_benchmark.v")]
EXTRA = [("tb_batch", "verif/questa/tb_batch.v"), ("tb_arch", "verif/arch/tb_arch.v")]


def p(path):
    """Absolute path with forward slashes (safe inside Verilog strings on Windows)."""
    return os.path.abspath(path).replace("\\", "/")


class Sim:
    def __init__(self, kind, build, defines):
        self.kind, self.build, self.defines, self.done = kind, os.path.abspath(build), defines, set()
        os.makedirs(self.build, exist_ok=True)
        shutil.copy(os.path.join(ROOT, "program.hex"), self.build)   # read by the single-cycle tbs
        tools = ["vlib", "vlog", "vsim"] if kind == "questa" else ["iverilog", "vvp"]
        for t in tools:
            if not shutil.which(t):
                sys.exit(f"'{t}' not found on PATH. For Questa, add its bin folder (for example "
                         f"C:\\intelFPGA_lite\\<version>\\questa_fse\\win64) to PATH.")

    def _sh(self, cmd):
        r = subprocess.run(cmd, cwd=self.build, capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        out = r.stdout + r.stderr
        if r.returncode != 0 and not re.search(r"\$finish|Note: \$finish", out):
            sys.exit(f"command failed: {' '.join(cmd)}\n{out[-3000:]}")
        return out

    def compile(self, top, tb_file):
        if top in self.done:
            return
        files = [p(os.path.join(ROOT, f)) for f in RTL + [tb_file]]
        if self.kind == "questa":
            if not os.path.isdir(os.path.join(self.build, "work")):
                self._sh(["vlib", "work"])
            self._sh(["vlog", "-quiet", "-timescale", "1ns/1ps", *[f"+define+{d}" for d in self.defines], *files])
        else:
            self._sh(["iverilog", "-g2012", *[f"-D{d}" for d in self.defines], "-s", top,
                      "-o", f"{top}.vvp", *files])
        self.done.add(top)

    def run(self, top, plusargs=()):
        if self.kind == "questa":
            return self._sh(["vsim", "-c", "-quiet", "-do", "run -all; quit -f", f"work.{top}", *plusargs])
        return self._sh(["vvp", "-n", f"{top}.vvp", *plusargs])


REPORT = []


def emit(line=""):
    print(line, flush=True)
    REPORT.append(line)


def suite_tbs(sim):
    emit("## Directed testbenches\n")
    emit("| Testbench | PASS | FAIL |")
    emit("|---|---|---|")
    tp = tf = 0
    for top, f in TBS:
        sim.compile(top, f)
        out = sim.run(top)
        lines = out.splitlines()
        npass = sum(1 for l in lines if "PASS" in l and not re.search(r"ALL .*PASSED", l))
        nfail = sum(1 for l in lines if re.search(r"\bFAIL", l))
        tp += npass; tf += nfail
        emit(f"| {top} | {npass} | {nfail} |")
    emit(f"| **Total** | **{tp}** | **{tf}** |\n")
    return tf == 0, f"testbenches: {tp} PASS, {tf} FAIL"


def run_batch(sim, vectors, name):
    vec = os.path.join(vectors, f"{name}.vec")
    if not os.path.exists(vec):
        sys.exit(f"{vec} not found: run  python verif/questa/gen_vectors.py {vectors}  first")
    sim.compile("tb_batch", "verif/questa/tb_batch.v")
    res = os.path.join(sim.build, f"{name}.results")
    out = sim.run("tb_batch", [f"+VEC={p(vec)}", f"+OUT={p(res)}"])
    m = re.search(r"BATCH programs=(\d+) failing=(\d+) identity_failures=(\d+)", out)
    if not m:
        sys.exit(f"tb_batch did not finish:\n{out[-3000:]}")
    rows = [list(map(int, l.split())) for l in open(res) if l.strip()]
    names_f = os.path.join(vectors, f"{name}.names")
    names = [l.strip() for l in open(names_f)] if os.path.exists(names_f) else [str(r[0]) for r in rows]
    return rows, names, int(m.group(2)), int(m.group(3))


def suite_directed(sim, vectors):
    rows, names, bad, ident = run_batch(sim, vectors, "directed")
    emit("## Directed programs (RTL vs reference simulator)\n")
    emit("| Program | Result |")
    emit("|---|---|")
    for r, n in zip(rows, names):
        emit(f"| {n} | {'PASS' if r[9] == 0 else f'FAIL ({r[9]} words differ)'} |")
    emit(f"\npassed={len(rows) - bad} failed={bad} identity_failures={ident}\n")
    return bad == 0 and ident == 0, f"directed: {len(rows) - bad}/{len(rows)} pass"


def suite_bench(sim, vectors):
    rows, names, bad, ident = run_batch(sim, vectors, "bench")
    emit("## Benchmarks: MAC vs mul+add\n")
    emit("| Benchmark | mul+add instrs | mul+add cycles | MAC instrs | MAC cycles | Speed-up |")
    emit("|---|---|---|---|---|---|")
    for i in range(0, len(rows), 2):
        a, b = rows[i], rows[i + 1]
        emit(f"| {names[i].split()[0]} | {a[2]} | {a[1]} | {b[2]} | {b[1]} | {a[1] / b[1]:.2f}x |")
    emit("\n## CPI and hazard counters\n")
    emit("| Program | Instrs | Cycles | CPI | Load-use | Mul-use | Taken br/jumps | EX/MEM fwds | MEM/WB fwds | MAC acc fwds |")
    emit("|---|---|---|---|---|---|---|---|---|---|")
    for r, n in zip(rows, names):
        emit(f"| {n} | {r[2]} | {r[1]} | {r[1] / r[2]:.3f} | {r[3]} | {r[4]} | {r[5]} | {r[6]} | {r[7]} | {r[8]} |")
    emit(f"\nfailing={bad} identity_failures={ident} "
         f"(cycles = instrs + 3 + load-use + mul-use + 2 x taken)\n")
    return bad == 0 and ident == 0, f"bench: {len(rows)} programs, {bad} failing, identity holds: {ident == 0}"


def suite_random(sim, vectors):
    rows, _, bad, ident = run_batch(sim, vectors, "random")
    n = len(rows)
    I, C = sum(r[2] for r in rows), sum(r[1] for r in rows)
    lu, mu, ct = sum(r[3] for r in rows), sum(r[4] for r in rows), sum(r[5] for r in rows)
    fe, fm, mf = sum(r[6] for r in rows), sum(r[7] for r in rows), sum(r[8] for r in rows)
    emit("## Differential random testing\n")
    emit("| Programs | Instructions | Failing | Identity failures |")
    emit("|---|---|---|---|")
    emit(f"| {n} | {I} | {bad} | {ident} |\n")
    emit(f"- CPI over all {n} programs: cycles={C} CPI={C / I:.3f} (startup {3 * n / I:.3f} + "
         f"load-use {lu / I:.3f} + mul-use {mu / I:.3f} + control {2 * ct / I:.3f})")
    emit(f"- forwards: EX/MEM {fe}, MEM/WB {fm}, MAC accumulator {mf}\n")
    return bad == 0 and ident == 0, f"random: {n} programs, {I} instructions, {bad} failing"


def suite_arch(sim):
    d = os.path.join(HERE, "arch")
    sim.compile("tb_arch", "verif/arch/tb_arch.v")
    emit("## Official RISC-V architecture tests (riscv-arch-test 2.7.4, Sail reference)\n")
    emit("| Test | Signature words | Mismatches | Result |")
    emit("|---|---|---|---|")
    passed = total = words = 0
    for line in open(os.path.join(d, "tests.txt")):
        if not line.strip():
            continue
        name, halt, sb, se = line.split()
        out = sim.run("tb_arch", [f"+PROG={p(os.path.join(d, name + '.hex'))}", f"+HALT={halt}",
                                  f"+SIGB={sb}", f"+SIGE={se}", f"+REF={p(os.path.join(d, name + '.ref'))}"])
        m = re.search(r"ARCH-RESULT words=(\d+) mismatches=(\d+)", out)
        ok = bool(m) and m.group(2) == "0" and "TIMEOUT" not in out
        total += 1; passed += ok; words += int(m.group(1)) if m else 0
        emit(f"| {name} | {m.group(1) if m else '?'} | {m.group(2) if m else '?'} | {'PASS' if ok else 'FAIL'} |")
    emit(f"\nARCH-TEST passed={passed}/{total} signature_words={words}\n")
    return passed == total, f"arch tests: {passed}/{total} pass, {words} signature words"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("suite", choices=["tbs", "directed", "bench", "random", "arch", "all"])
    ap.add_argument("--vectors", default=os.path.join(HERE, "vectors"))
    ap.add_argument("--build", default=os.path.join(HERE, "build"))
    ap.add_argument("--sim", choices=["questa", "icarus"], default="questa")
    ap.add_argument("--async-mem", action="store_true")
    a = ap.parse_args()
    defines = [] if a.async_mem else ["FPGA_SYNC_MEM"]
    sim = Sim(a.sim, a.build, defines)
    emit(f"# Verification report ({a.sim}, {'plain memories' if a.async_mem else 'FPGA_SYNC_MEM memories'})\n")
    todo = ["tbs", "directed", "bench", "random", "arch"] if a.suite == "all" else [a.suite]
    results = []
    for s in todo:
        if s == "tbs":
            results.append(suite_tbs(sim))
        elif s == "arch":
            results.append(suite_arch(sim))
        else:
            results.append({"directed": suite_directed, "bench": suite_bench,
                            "random": suite_random}[s](sim, a.vectors))
    emit("## Summary\n")
    for ok, msg in results:
        emit(f"- {'OK  ' if ok else 'FAIL'} {msg}")
    open(os.path.join(sim.build, "report.md"), "w").write("\n".join(REPORT) + "\n")
    print(f"\nreport written to {os.path.join(sim.build, 'report.md')}")
    sys.exit(0 if all(ok for ok, _ in results) else 1)


if __name__ == "__main__":
    main()
