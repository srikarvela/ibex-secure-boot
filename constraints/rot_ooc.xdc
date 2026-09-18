# Out-of-context clock for the buildable root-of-trust blocks. 4.000 ns (250 MHz)
# matches the sibling repos' OOC target; tcl/rot_synth.tcl reads the period back
# from the clock object, so this is the only place it is written. No board or
# pin bring-up here -- these are block-level OOC boundary constraints only.
create_clock -name clk -period 4.000 [get_ports clk]
set_input_delay  -clock clk 0.300 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 0.300 [all_outputs]
