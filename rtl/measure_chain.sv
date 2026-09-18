// =============================================================================
// measure_chain.sv -- PCR-style measured-boot register.
//
// One accumulating measurement, extended once per boot stage:
//     pcr <- SHA256( pcr(32B) || stage_hash(32B) )
// exactly the TPM/DICE "extend" primitive in miniature. The 64-byte message is
// two SHA-256 blocks after FIPS padding; both are fixed because the length is
// constant, so the padding words are hard constants here and the block is fed
// straight to an embedded sha256_core -- no CPU, no bus. `reset_pcr` clears to
// zero (the conventional PCR reset value); `extend` pulses one measurement.
//
// Verified by tb/tb_measure.sv against a software reference that computes the
// same SHA256(pcr||stage) chain, so the hardware extend is bit-exact and the
// chain is order-sensitive (swapping two stages changes the final PCR).
// =============================================================================
`default_nettype none

module measure_chain (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         reset_pcr,       // pulse: pcr <- 0
    input  wire         extend,          // pulse: fold stage_hash into pcr
    input  wire [255:0] stage_hash,      // measurement of the next stage
    output reg  [255:0] pcr,
    output reg          busy,
    output reg          done             // pulse: pcr updated
);
    localparam [255:0] IV = {32'h6a09e667,32'hbb67ae85,32'h3c6ef372,32'ha54ff53a,
                             32'h510e527f,32'h9b05688c,32'h1f83d9ab,32'h5be0cd19};
    // 64-byte message padding to two 512-bit blocks: block1 = pcr||stage_hash,
    // block0's tail 0x80 then zeros ... length = 512 bits = 0x200.
    localparam [255:0] PAD_HI = {8'h80, 248'd0};
    localparam [255:0] PAD_LO = {192'd0, 64'd512};

    reg         c_start;
    reg  [511:0] c_block;
    reg  [255:0] c_hin;
    wire         c_done, c_busy;
    wire [255:0] c_hout;
    sha256_core u_sha(.clk(clk),.rst_n(rst_n),.start(c_start),.block(c_block),
                      .h_in(c_hin),.done(c_done),.h_out(c_hout),.busy(c_busy));

    localparam S_IDLE=3'd0, S_B1=3'd1, S_W1=3'd2, S_B2=3'd3, S_W2=3'd4, S_FIN=3'd5;
    reg [2:0]  st;
    reg [255:0] h_mid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pcr<=256'd0; busy<=1'b0; done<=1'b0; c_start<=1'b0; st<=S_IDLE;
        end else begin
            done<=1'b0; c_start<=1'b0;
            case (st)
                S_IDLE: begin
                    busy<=1'b0;
                    if (reset_pcr) pcr<=256'd0;
                    else if (extend) begin
                        busy<=1'b1;
                        c_block <= {pcr, stage_hash};      // block 1: 64 message bytes
                        c_hin   <= IV; c_start<=1'b1; st<=S_B1;
                    end
                end
                S_B1: st<=S_W1;                            // start consumed
                S_W1: if (c_done) begin h_mid<=c_hout;
                        c_block <= {PAD_HI, PAD_LO};        // block 2: padding only
                        c_hin   <= c_hout; c_start<=1'b1; st<=S_B2; end
                S_B2: st<=S_W2;
                S_W2: if (c_done) begin pcr<=c_hout; st<=S_FIN; end
                S_FIN: begin done<=1'b1; busy<=1'b0; st<=S_IDLE; end
                default: st<=S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
