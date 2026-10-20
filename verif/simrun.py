"""Helpers to build tb_prog_runner with Verilator and run programs on the RTL."""
import os, subprocess, tempfile, shutil
import rvtools

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.dirname(HERE)
SRCS = ["ALU.v", "Forward_units.v", "Hazard_units.v", "Imem.v", "RegFile.v",
        "Riscv_pipeline.v", "control.v", "dmem.v", "pipeline_reg.v"]


def build(workdir):
    env = dict(os.environ)
    vroot = env.get("VERILATOR_ROOT", "")
    exe = os.path.join(vroot, "bin", "verilator") if vroot else "verilator"
    cmd = [exe, "--binary", "--timing", "-Wno-fatal", "-Wno-lint", "-Wno-style",
           "--top-module", "tb_prog_runner", "-Mdir", workdir,
           "-CFLAGS", "-std=c++20 -fcoroutines",
           os.path.join(HERE, "tb_prog_runner.v")] + [os.path.join(RTL, s) for s in SRCS]
    subprocess.run(cmd, check=True, capture_output=True, text=True, env=env)
    return os.path.join(workdir, "Vtb_prog_runner")


def run_rtl(exe, words, data=None, tmp=None):
    """Run a program on the RTL. Returns (regs[32], dmem[256], cycles)."""
    tmp = tmp or tempfile.mkdtemp()
    p, d, o = (os.path.join(tmp, n) for n in ("prog.hex", "data.hex", "out.txt"))
    rvtools.write_hex(p, words)
    rvtools.write_hex(d, data or [])
    halt = 4 * words.index(rvtools.HALT)
    r = subprocess.run([exe, f"+PROG={p}", f"+DATA={d}", f"+HALT={halt}", f"+OUT={o}"],
                       capture_output=True, text=True, check=True)
    cyc = int([l for l in r.stdout.splitlines() if l.startswith("CYCLES")][0].split()[1])
    vals = [int(l, 16) for l in open(o).read().split()]
    return vals[:32], vals[32:], cyc
