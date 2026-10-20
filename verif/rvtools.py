#!/usr/bin/env python3
"""Tiny assembler and instruction-set simulator for the riscv-mac-processor core.

Supported: add sub and or xor sll srl sra slt sltu mul, addi andi ori xori
slli srli srai slti sltiu, lw sw, beq bne blt bge bltu bgeu, lui auipc jal jalr,
mac (custom-0: rd = rd + rs1*rs2), plus pseudo-ops nop, li, mv, j.

Memory model matches the RTL: 256-word instruction and data memories, indexed
by addr[9:2] (so addresses wrap at 1 KB), word accesses only.
"""
import re

M32 = 0xFFFFFFFF
ABI = {'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4, 't0': 5, 't1': 6, 't2': 7,
       's0': 8, 'fp': 8, 's1': 9}
ABI.update({f'a{i}': 10 + i for i in range(8)})
ABI.update({f's{i}': 16 + i for i in range(2, 12)})
ABI.update({f't{i}': 25 + i for i in range(3, 7)})
ABI.update({f'x{i}': i for i in range(32)})

R_OPS = {'add': (0, 0), 'sub': (0, 0x20), 'sll': (1, 0), 'slt': (2, 0), 'sltu': (3, 0),
         'xor': (4, 0), 'srl': (5, 0), 'sra': (5, 0x20), 'or': (6, 0), 'and': (7, 0),
         'mul': (0, 1)}
I_OPS = {'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7}
SH_OPS = {'slli': (1, 0), 'srli': (5, 0), 'srai': (5, 0x20)}
B_OPS = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}


def reg(name):
    return ABI[name.strip()]


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def assemble(src):
    """Return list of 32-bit words. Labels end with ':'."""
    lines = []
    for raw in src.splitlines():
        line = raw.split('#')[0].strip()
        while ':' in line:
            lab, line = line.split(':', 1)
            lines.append(('label', lab.strip()))
            line = line.strip()
        if line:
            lines.append(('ins', line))
    # pass 1: expand pseudo-ops to count size
    expanded = []
    for kind, val in lines:
        if kind == 'label':
            expanded.append((kind, val))
            continue
        op, _, rest = val.partition(' ')
        args = [a.strip() for a in rest.split(',')] if rest.strip() else []
        if op == 'nop':
            expanded.append(('ins', ('addi', ['zero', 'zero', '0'])))
        elif op == 'mv':
            expanded.append(('ins', ('addi', [args[0], args[1], '0'])))
        elif op == 'j':
            expanded.append(('ins', ('jal', ['zero', args[0]])))
        elif op == 'li':
            v = int(args[1], 0) & M32
            sv = sx(v, 32)
            if -2048 <= sv < 2048:
                expanded.append(('ins', ('addi', [args[0], 'zero', str(sv)])))
            else:
                hi = (v + 0x800) >> 12 & 0xFFFFF
                lo = sx(v - (hi << 12), 12)
                expanded.append(('ins', ('lui', [args[0], str(hi)])))
                expanded.append(('ins', ('addi', [args[0], args[0], str(lo)])))
        else:
            expanded.append(('ins', (op, args)))
    labels, pc = {}, 0
    for kind, val in expanded:
        if kind == 'label':
            labels[val] = pc
        else:
            pc += 4
    words, pc = [], 0
    for kind, val in expanded:
        if kind == 'label':
            continue
        op, a = val
        def tgt(s):
            return (labels[s] - pc) if s in labels else int(s, 0)
        def mem(s):
            m = re.match(r'(-?\w+)\((\w+)\)', s.strip())
            return int(m.group(1), 0), reg(m.group(2))
        if op in R_OPS:
            f3, f7 = R_OPS[op]
            w = (f7 << 25) | (reg(a[2]) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x33
        elif op in I_OPS:
            imm = int(a[2], 0)
            assert -2048 <= imm < 2048, (op, imm)
            w = ((imm & 0xFFF) << 20) | (reg(a[1]) << 15) | (I_OPS[op] << 12) | (reg(a[0]) << 7) | 0x13
        elif op in SH_OPS:
            f3, f7 = SH_OPS[op]
            w = (f7 << 25) | ((int(a[2], 0) & 31) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x13
        elif op == 'lw':
            imm, rs1 = mem(a[1])
            w = ((imm & 0xFFF) << 20) | (rs1 << 15) | (2 << 12) | (reg(a[0]) << 7) | 0x03
        elif op == 'sw':
            imm, rs1 = mem(a[1])
            w = (((imm >> 5) & 0x7F) << 25) | (reg(a[0]) << 20) | (rs1 << 15) | (2 << 12) | ((imm & 0x1F) << 7) | 0x23
        elif op in B_OPS:
            o = tgt(a[2]) & 0x1FFF
            w = (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (reg(a[1]) << 20) | (reg(a[0]) << 15) | \
                (B_OPS[op] << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | 0x63
        elif op == 'lui':
            w = ((int(a[1], 0) & 0xFFFFF) << 12) | (reg(a[0]) << 7) | 0x37
        elif op == 'auipc':
            w = ((int(a[1], 0) & 0xFFFFF) << 12) | (reg(a[0]) << 7) | 0x17
        elif op == 'jal':
            o = tgt(a[1]) & 0x1FFFFF
            w = (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) | \
                (((o >> 12) & 0xFF) << 12) | (reg(a[0]) << 7) | 0x6F
        elif op == 'jalr':
            imm, rs1 = mem(a[1])
            w = ((imm & 0xFFF) << 20) | (rs1 << 15) | (reg(a[0]) << 7) | 0x67
        elif op == 'mac':
            w = (reg(a[2]) << 20) | (reg(a[1]) << 15) | (reg(a[0]) << 7) | 0x0B
        else:
            raise ValueError(f'unknown op {op}')
        words.append(w & M32)
        pc += 4
    return words


HALT = 0x0000006F  # jal x0, 0


def run_iss(words, data=None, max_steps=2_000_000):
    """Execute until the halt instruction (jal x0,0). Returns (regs, dmem, steps, pc)."""
    imem = list(words) + [0] * (256 - len(words))
    dmem = list(data or []) + [0] * (256 - len(data or []))
    x = [0] * 32
    pc, steps = 0, 0
    while steps < max_steps:
        w = imem[(pc >> 2) & 255]
        if w == HALT:
            return x, dmem, steps, pc
        steps += 1
        op = w & 0x7F
        rd, f3, rs1, rs2, f7 = (w >> 7) & 31, (w >> 12) & 7, (w >> 15) & 31, (w >> 20) & 31, w >> 25
        a, b = x[rs1], x[rs2]
        sa, sb = sx(a, 32), sx(b, 32)
        npc, res = (pc + 4) & M32, None
        immI = sx(w >> 20, 12)
        if op == 0x33:
            if f7 == 1 and f3 == 0:
                res = (a * b) & M32
            else:
                res = {0: (a - b if f7 == 0x20 else a + b), 1: a << (b & 31), 2: int(sa < sb), 3: int(a < b),
                       4: a ^ b, 5: (sa >> (b & 31)) if f7 == 0x20 else a >> (b & 31), 6: a | b, 7: a & b}[f3]
        elif op == 0x13:
            sh = rs2
            res = {0: a + immI, 1: a << sh, 2: int(sa < immI), 3: int(a < (immI & M32)), 4: a ^ immI,
                   5: (sa >> sh) if (w >> 30) & 1 else a >> sh, 6: a | immI, 7: a & immI}[f3]
        elif op == 0x03:
            res = dmem[((a + immI) & M32) >> 2 & 255]
        elif op == 0x23:
            imm = sx(((w >> 25) << 5) | ((w >> 7) & 31), 12)
            dmem[((a + imm) & M32) >> 2 & 255] = b
        elif op == 0x63:
            imm = sx(((w >> 31) << 12) | (((w >> 7) & 1) << 11) | (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1), 13)
            t = {0: a == b, 1: a != b, 4: sa < sb, 5: sa >= sb, 6: a < b, 7: a >= b}[f3]
            if t:
                npc = (pc + imm) & M32
        elif op == 0x37:
            res = w & 0xFFFFF000
        elif op == 0x17:
            res = pc + (w & 0xFFFFF000)
        elif op == 0x6F:
            imm = sx(((w >> 31) << 20) | (((w >> 12) & 0xFF) << 12) | (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1), 21)
            res, npc = pc + 4, (pc + imm) & M32
        elif op == 0x67:
            res, npc = pc + 4, (a + immI) & M32 & ~1
        elif op == 0x0B:
            res = x[rd] + a * b
        else:
            raise ValueError(f'illegal instruction {w:08x} at {pc:#x}')
        if res is not None and rd:
            x[rd] = res & M32
        pc = npc
    raise RuntimeError('ISS step limit')


def write_hex(path, words, size=256):
    with open(path, 'w') as f:
        for w in list(words) + [0] * (size - len(words)):
            f.write(f'{w:08x}\n')
