# Timing constraints for riscv_pipeline (Quartus TimeQuest)
# 50 MHz target; TimeQuest still reports the true Fmax in the
# "Fmax Summary" table even if the design misses this target.
create_clock -name clk -period 20.000 [get_ports clk]
derive_clock_uncertainty

# Program-load port, reset and PC output are board/testbench I/O, not
# part of the core's register-to-register timing.
set_false_path -from [get_ports {rst prog_*}]
set_false_path -to   [get_ports {pc_out*}]
