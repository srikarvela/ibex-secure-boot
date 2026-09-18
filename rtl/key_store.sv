// =============================================================================
// key_store.sv -- write-once, lockable 256-bit key, readable by the crypto
// block but NEVER by the CPU.
//
// This separation is the root of trust: a key the CPU can read is a variable,
// not a stored secret. Two ports:
//   - CPU port  (cpu_we/cpu_addr/cpu_wdata, cpu_rdata): may WRITE key words,
//     one time each, and only while `key_writable` (lifecycle == TEST). Reads
//     of the key region return ZERO, always -- there is no mux path from the
//     key registers to cpu_rdata.
//   - crypto port (crypto_key_o): the full 256-bit key, combinational, wired
//     only to the on-chip hash/verify block.
// `lock` is a sticky one-way bit; once set, no further writes are accepted even
// if the lifecycle re-opens the window.
//
// Verified by tb/tb_key_store.sv: after provisioning, cpu_rdata == 0 for every
// key word while crypto_key_o holds the real key (the single most important
// assertion in the project), writes are rejected once written or once locked,
// and writes outside the TEST window are rejected.
// =============================================================================
`default_nettype none

module key_store #(
    parameter integer NWORDS = 8            // 8 x 32b = 256b key
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_writable,        // from lifecycle_fsm (TEST window)
    input  wire        lock_req,            // pulse: latch the one-way lock
    input  wire        cpu_we,
    input  wire [2:0]  cpu_addr,            // which key word
    input  wire [31:0] cpu_wdata,
    output wire [31:0] cpu_rdata,           // key region reads ALWAYS 0
    output wire [255:0] crypto_key_o,
    output reg         locked
);
    reg [31:0] key   [0:NWORDS-1];
    reg        written[0:NWORDS-1];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            locked <= 1'b0;
            for (i=0;i<NWORDS;i=i+1) begin key[i]<=32'd0; written[i]<=1'b0; end
        end else begin
            if (lock_req) locked <= 1'b1;   // one-way; never cleared
            if (cpu_we && key_writable && !locked && !written[cpu_addr]) begin
                key[cpu_addr]     <= cpu_wdata;
                written[cpu_addr] <= 1'b1;   // write-once per word
            end
        end
    end

    // No path from key[] to the CPU read bus. This is deliberate, not an oversight.
    assign cpu_rdata = 32'd0;

    genvar w;
    generate for (w=0; w<NWORDS; w=w+1) begin : g_key
        assign crypto_key_o[32*w +: 32] = key[w];
    end endgenerate
endmodule
`default_nettype wire
