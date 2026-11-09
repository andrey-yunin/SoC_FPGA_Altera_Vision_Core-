# Vision Core: base clock constraints
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

derive_pll_clocks

# ---------------------------------------------------------------------------
# SDRAM I/O timing: ISSI IS42S16320D-7TL, speed grade -7, CL3
# Board delays below are ESTIMATES (~3 cm FR-4, ~0.2 ns each), not from layout.
# Replace with measured/layout values when available.
# ---------------------------------------------------------------------------
set t_d 0.200
set t_c 0.200

set sdram_clk [get_clocks {*divclk*}]

# Write: FPGA -> SDRAM. External skew = t_d - t_c.
# DQ/DQM: tDS/tDH = 1.5/0.8 ns. Address/command: tCMS/tCMH = 1.5/0.8 ns.
set_output_delay -clock $sdram_clk -max [expr {$t_d - $t_c + 1.500}] [get_ports {DRAM_DQ[*] DRAM_DQM[*] DRAM_ADDR[*] DRAM_BA[*] DRAM_CAS_N DRAM_CKE DRAM_CS_N DRAM_RAS_N DRAM_WE_N}]
set_output_delay -clock $sdram_clk -min [expr {$t_d - $t_c - 0.800}] [get_ports {DRAM_DQ[*] DRAM_DQM[*] DRAM_ADDR[*] DRAM_BA[*] DRAM_CAS_N DRAM_CKE DRAM_CS_N DRAM_RAS_N DRAM_WE_N}]

# Read: SDRAM -> FPGA, DQ only. tAC max = 5.4 ns, tOH min = 2.7 ns.
set_input_delay -clock $sdram_clk -max [expr {$t_c + 5.400 + $t_d}] [get_ports {DRAM_DQ[*]}]
set_input_delay -clock $sdram_clk -min [expr {$t_c + 2.700 + $t_d}] [get_ports {DRAM_DQ[*]}]

derive_clock_uncertainty