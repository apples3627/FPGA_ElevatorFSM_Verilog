#************************************************************
# THIS IS A WIZARD-GENERATED FILE.                           
#
# Version 13.0.1 Build 232 06/12/2013 Service Pack 1 SJ Web Edition
#
#************************************************************

# Copyright (C) 1991-2013 Altera Corporation
# Your use of Altera Corporation's design tools, logic functions 
# and other software and tools, and its AMPP partner logic 
# functions, and any output files from any of the foregoing 
# (including device programming or simulation files), and any 
# associated documentation or information are expressly subject 
# to the terms and conditions of the Altera Program License 
# Subscription Agreement, Altera MegaCore Function License 
# Agreement, or other applicable license agreement, including, 
# without limitation, that your use is for the sole purpose of 
# programming logic devices manufactured by Altera and sold by 
# Altera or its authorized distributors.  Please refer to the 
# applicable agreement for further details.



# Clock constraints

create_clock -name "CLK" -period 20.000ns [get_ports {CLK}]

set_false_path -from [get_ports {RST_N}]
set_false_path -from [get_ports {BTN_OPEN}]
set_false_path -from [get_ports {BTN_CLOSE}]
set_false_path -from [get_ports {EMG_STOP}]
set_false_path -from [get_ports {BTN_TX_STOP}]
set_false_path -from [get_ports {UART_RXD}]

set uart_tx_regs [get_registers {i_controller|i_uart_tx|*}]
set_multicycle_path -setup 434 -from $uart_tx_regs -to $uart_tx_regs
set_multicycle_path -hold 433 -from $uart_tx_regs -to $uart_tx_regs


# Automatically constrain PLL and other generated clocks
derive_pll_clocks -create_base_clocks

# Automatically calculate clock uncertainty to jitter and other effects.
#derive_clock_uncertainty
# Not supported for family Cyclone II

# tsu/th constraints


# tco constraints
set_output_delay -clock {CLK} -max 10.0 [all_outputs]
set_output_delay -clock {CLK} -min 0.0 [all_outputs]

# tpd constraints

