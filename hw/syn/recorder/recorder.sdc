create_clock -name clk -period 20.000 [get_ports MAX10_CLK1_50]
create_clock -name altera_reserved_tck -period 100.000 [get_ports altera_reserved_tck]
set_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks altera_reserved_tck]
derive_clock_uncertainty
