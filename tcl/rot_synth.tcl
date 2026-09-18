# =============================================================================
# rot_synth.tcl -- out-of-context synth + place & route of the buildable
# root-of-trust blocks, one per invocation, on the PYNQ-Z2 part.
#
#   vivado -mode batch -source tcl/rot_synth.tcl -tclargs sha256_core key_store ...
#   (default list if none given: the four verified blocks)
#
# Each block is synthesized, placed and routed on its own with the OOC clock in
# constraints/rot_ooc.xdc, so utilization.rpt / timing_summary.rpt hold real
# post-route numbers. scripts/ppa_table.py then builds reports/ppa.csv from
# those committed reports -- no number is entered by hand. rot_top (full Ibex
# integration) is intentionally NOT in the default list; it needs the vendored
# core wired in first.
# =============================================================================
set part "xc7z020clg400-1"
set here [file normalize [file dirname [info script]]]
set root [file normalize [file join $here ..]]
set rdir [file join $root reports]
file mkdir $rdir

set blocks $argv
if {[llength $blocks] == 0} {
    set blocks {sha256_core key_store lifecycle_fsm measure_chain}
}

foreach top $blocks {
    puts "=== OOC: $top part=$part ==="
    set out [file join $rdir $top]
    file mkdir $out
    create_project -in_memory -part $part
    foreach f [lsort [glob -directory [file join $root rtl] *.sv]] { read_verilog -sv $f }
    read_xdc -mode out_of_context [file join $root constraints rot_ooc.xdc]
    synth_design -top $top -part $part -mode out_of_context -include_dirs [file join $root rtl]
    opt_design
    place_design
    phys_opt_design
    route_design
    report_timing_summary -file [file join $out timing_summary.rpt]
    report_utilization    -file [file join $out utilization.rpt]
    set clk_period [get_property PERIOD [get_clocks clk]]
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
    puts "=== $top: WNS=$wns WHS=$whs period=$clk_period (see utilization.rpt for Slice LUTs) ==="
    close_project
}
puts "=== reports under $rdir; run scripts/ppa_table.py to build ppa.csv ==="
