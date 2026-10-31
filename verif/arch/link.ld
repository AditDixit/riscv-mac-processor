/* riscv-arch-test link script for this core: everything from address 0
   (the core's reset PC). The same image is loaded into both instruction
   and data memory, so PC-relative data addresses resolve in either. */
OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

SECTIONS
{
  . = 0x00000000;
  .text.init : { *(.text.init) }
  .text      : { *(.text) }
  . = ALIGN(16);
  .data      : { *(.data) }
  .data.string : { *(.data.string) }
  .bss       : { *(.bss) }
  _end = .;
}
