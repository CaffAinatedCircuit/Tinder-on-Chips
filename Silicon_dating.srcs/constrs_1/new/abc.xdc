set_property PACKAGE_PIN AB30 [get_ports rst_n]
set_property PACKAGE_PIN AD29 [get_ports clk_global]
set_property IOSTANDARD LVDCI_DV2_15 [get_ports clk_global]
set_property PACKAGE_PIN AC33 [get_ports {debug_leds[7]}]
set_property PACKAGE_PIN V32 [get_ports {debug_leds[6]}]
set_property PACKAGE_PIN V33 [get_ports {debug_leds[5]}]
set_property PACKAGE_PIN U30 [get_ports {debug_leds[4]}]
set_property PACKAGE_PIN AB32 [get_ports {debug_leds[3]}]
set_property PACKAGE_PIN AB31 [get_ports {debug_leds[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports rst_n]

create_clock -period 10.000 -name clk_gbl -waveform {0.000 5.000} [get_ports clk_global]
set_switching_activity -deassert_resets 

set_output_delay -clock [get_clocks -regexp -nocase .*] -rise -min -add_delay 5.000 [get_ports -regexp -nocase -filter { NAME =~  ".*" && DIRECTION == "OUT" }]
set_input_delay -clock [get_clocks -regexp -nocase .*] 0.000 [get_ports rst_n]
