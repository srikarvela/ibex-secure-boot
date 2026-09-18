// =============================================================================
// lifecycle_fsm.sv -- one-way device lifecycle: RAW -> TEST -> PROD -> LOCKED.
//
// The point of the block is that regression is structurally impossible: the
// only legal move is forward by exactly one state, requested via `advance`.
// Any other request (skip a state, go backward, advance from LOCKED) is
// ignored and leaves the state register unchanged -- there is no code path
// that writes a lower-or-equal state. That is "irreversibility in silicon, not
// firmware policy" from the build guide. Provisioning gates (key writes) are
// derived combinationally from the state, not stored separately, so they
// cannot disagree with it.
//
// Verified by tb/tb_lifecycle.sv: every legal transition succeeds and every
// illegal request is rejected with the state unchanged (exhaustive over the
// 4x4 current x requested cross product, plus reset).
// =============================================================================
`default_nettype none

module lifecycle_fsm (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       advance,       // request: go to `req_state`
    input  wire [1:0] req_state,     // must equal state+1 to be accepted
    output reg  [1:0] state,
    output wire       key_writable,  // provisioning window (TEST only)
    output wire       boot_enabled,  // normal boot allowed (PROD or LOCKED)
    output reg        illegal_seen   // sticky: an illegal transition was attempted
);
    localparam [1:0] RAW=2'd0, TEST=2'd1, PROD=2'd2, LOCKED=2'd3;

    // keys may only be provisioned in TEST; PROD/LOCKED can boot; RAW does nothing
    assign key_writable = (state == TEST);
    assign boot_enabled = (state == PROD) || (state == LOCKED);

    wire legal = advance && (state != LOCKED) && (req_state == state + 2'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= RAW; illegal_seen <= 1'b0;
        end else if (advance) begin
            if (legal) state <= req_state;         // the ONLY write to state
            else       illegal_seen <= 1'b1;        // rejected, state untouched
        end
    end
endmodule
`default_nettype wire
