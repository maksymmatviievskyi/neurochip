# 50 MHz board clock
create_clock -name clk -period 20.000 [get_ports MAX10_CLK1_50]
create_clock -name altera_reserved_tck -period 100.000 [get_ports -nowarn altera_reserved_tck]
set_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks -nowarn altera_reserved_tck]
derive_clock_uncertainty

# Slow, asynchronous board I/O: timing is set by the RTL (synchronisers, 1 MHz SCLK from a counter)
set_false_path -from [get_ports {KEY[*] GSENSOR_SDO GSENSOR_INT[*]}]
set_false_path -to   [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*] GSENSOR_CS_N GSENSOR_SCLK GSENSOR_SDI}]
