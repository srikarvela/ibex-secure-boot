// =============================================================================
// rot_top.sv -- root-of-trust top level: Ibex + boot ROM + SHA-256 accelerator
// + key store + lifecycle FSM + measurement chain on one simple bus.
//
// STATUS -- INTEGRATION SKELETON, NOT YET BUILT.
// The RoT peripheral blocks below are the verified ones (see tb/). The Ibex
// core instance and its OBI/data-bus adaptation to this decoder are the
// remaining integration work and are guarded by `ifdef IBEX_PRESENT until the
// vendored core (vendor/ibex, see README) is wired in. Nothing here has been
// synthesized yet; no area/timing numbers are claimed for this level.
//
// Address map (word decode on a valid/ready-free bus):
//   0x0000_0000  boot ROM (reset vector)
//   0x1000_0000  SHA-256 accelerator regs
//   0x2000_0000  lifecycle / key-store control
// =============================================================================
`default_nettype none
module rot_top (
    input  wire clk,
    input  wire rst_n,
    output wire tamper_o,          // raised by the failure path; never cleared
    output wire boot_ok_o
);
    // ---- RoT peripheral blocks (verified individually) ----------------------
    wire [1:0]  lc_state;
    wire        key_writable, boot_enabled, lc_illegal;
    wire [255:0] crypto_key;

    // Control wiring below is tied off in the skeleton; the CPU drives it once
    // Ibex is integrated. Kept explicit so the intent is legible.
    reg  lc_advance = 1'b0; reg [1:0] lc_req = 2'b0;
    lifecycle_fsm u_lc (.clk(clk),.rst_n(rst_n),.advance(lc_advance),.req_state(lc_req),
        .state(lc_state),.key_writable(key_writable),.boot_enabled(boot_enabled),.illegal_seen(lc_illegal));

    reg cpu_key_we = 1'b0; reg [2:0] cpu_key_addr = 3'b0; reg [31:0] cpu_key_wdata = 32'b0;
    reg key_lock = 1'b0; wire [31:0] key_cpu_rdata; wire key_locked;
    key_store u_ks (.clk(clk),.rst_n(rst_n),.key_writable(key_writable),.lock_req(key_lock),
        .cpu_we(cpu_key_we),.cpu_addr(cpu_key_addr),.cpu_wdata(cpu_key_wdata),
        .cpu_rdata(key_cpu_rdata),.crypto_key_o(crypto_key),.locked(key_locked));

    reg mc_reset = 1'b0, mc_extend = 1'b0; reg [255:0] mc_stage = 256'b0;
    wire [255:0] pcr; wire mc_busy, mc_done;
    measure_chain u_mc (.clk(clk),.rst_n(rst_n),.reset_pcr(mc_reset),.extend(mc_extend),
        .stage_hash(mc_stage),.pcr(pcr),.busy(mc_busy),.done(mc_done));

    // Failure path: once tamper is raised it latches; boot_ok requires a good
    // verify AND lifecycle boot_enabled AND no tamper. The verify result comes
    // from ROM software; tied to 0 in the skeleton so boot_ok is honestly 0.
    reg tamper_q = 1'b0;
    wire verify_ok = 1'b0;                       // TODO: from Ed25519 ROM routine
    assign tamper_o  = tamper_q;
    assign boot_ok_o = verify_ok & boot_enabled & ~tamper_q;

`ifdef IBEX_PRESENT
    // TODO: instantiate lowRISC Ibex (vendor/ibex) and adapt its instruction
    // and data OBI ports to the boot ROM and the peripheral decoder above.
`endif
endmodule
`default_nettype wire
