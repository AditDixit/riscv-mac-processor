// ============================================================
// model_test.h — riscv-arch-test (2.7.x) target macros for this core
//
// The core has no CSRs, traps or host interface, so:
//   - halt is the core's usual "jal x0, 0" self-loop; the testbench
//     stops when it reaches EX (address taken from the symbol table)
//   - the signature lives in data memory between begin_signature and
//     end_signature and is dumped by the testbench
// ============================================================
#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

#define RVMODEL_HALT                                              \
  .global rvmodel_halt;                                           \
  rvmodel_halt: j rvmodel_halt;

#define RVMODEL_BOOT

#define RVMODEL_DATA_BEGIN                                        \
  .align 4; .global begin_signature; begin_signature:

#define RVMODEL_DATA_END                                          \
  .align 4; .global end_signature; end_signature:

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif
