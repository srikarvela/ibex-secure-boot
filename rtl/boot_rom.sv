// =============================================================================
// boot_rom.sv -- immutable initialized ROM at the reset vector.
//
// Runs before anything else. Its contents (the ROM code: hash the application
// image, Ed25519-verify against the key store, extend the measurement chain,
// jump or halt) are assembled from sw/boot/ and loaded here at elaboration via
// $readmemh. Immutability is the root: there is no write port, and synthesis
// maps this to initialized fabric (BRAM/LUTROM), not to anything the running
// system can change.
//
// STATUS: the module is real and synthesizable; the ROM *image* it loads
// (sw/boot/boot.hex) is a placeholder until the Ed25519 verify routine is
// written and built for Ibex. See sw/boot/README and the top-level README's
// "What IS NOT implemented".
// =============================================================================
`default_nettype none
module boot_rom #(
    parameter integer AW   = 12,                 // 16 KiB / 4 = 4096 words
    parameter         INIT = "sw/boot/boot.hex"
) (
    input  wire            clk,
    input  wire [AW-1:0]   addr,                 // word address
    output reg  [31:0]     rdata
);
    reg [31:0] mem [0:(1<<AW)-1];
    initial $readmemh(INIT, mem);
    always @(posedge clk) rdata <= mem[addr];
endmodule
`default_nettype wire
