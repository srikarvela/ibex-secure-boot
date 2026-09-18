// =============================================================================
// sha256_accel.sv -- sha256_core behind a tiny word-addressed register file so
// software on Ibex can drive it. Streaming hash: software writes 512-bit blocks
// (already padded by the ROM code), pulses START, polls STATUS.done, reads the
// 256-bit digest. The running-hash chaining across blocks lives in software so
// the accelerator stays a single-block engine (the honest hardware/software
// partition: hash acceleration in silicon, everything else in ROM code).
//
// Register map (32-bit words on a simple valid/ready-free bus):
//   0x00  CTRL   [0]=start(one-shot) [1]=init(load SHA-256 IV into H)
//   0x04  STATUS [0]=busy [1]=done
//   0x10..0x2c  BLOCK[0..15]   512-bit message block, word 0 = MSBs
//   0x40..0x5c  DIGEST[0..7]   256-bit result, read-only
// This is a skeleton bus wrapper: the bus is a direct decode, not AXI. The
// AXI/OBI adaptation to Ibex's data port is TODO (see rot_top.sv).
// =============================================================================
`default_nettype none

module sha256_accel (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sel,
    input  wire        we,
    input  wire [7:0]  addr,        // byte address, word aligned
    input  wire [31:0] wdata,
    output reg  [31:0] rdata
);
    localparam [255:0] IV = {32'h6a09e667,32'hbb67ae85,32'h3c6ef372,32'ha54ff53a,
                             32'h510e527f,32'h9b05688c,32'h1f83d9ab,32'h5be0cd19};
    reg  [31:0] blk_w [0:15];
    reg  [255:0] h_running;
    reg          start, init_iv;
    wire         core_done, core_busy;
    wire [255:0] core_h;
    reg  [255:0] digest;

    wire [511:0] block = { blk_w[0],blk_w[1],blk_w[2],blk_w[3],
                           blk_w[4],blk_w[5],blk_w[6],blk_w[7],
                           blk_w[8],blk_w[9],blk_w[10],blk_w[11],
                           blk_w[12],blk_w[13],blk_w[14],blk_w[15] };

    sha256_core u_core(.clk(clk),.rst_n(rst_n),.start(start),.block(block),
                       .h_in(h_running),.done(core_done),.h_out(core_h),.busy(core_busy));

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start<=1'b0; init_iv<=1'b0; h_running<=IV; digest<=256'd0;
            for (i=0;i<16;i=i+1) blk_w[i]<=32'd0;
        end else begin
            start<=1'b0;
            if (init_iv) begin h_running<=IV; init_iv<=1'b0; end
            if (core_done) begin digest<=core_h; h_running<=core_h; end
            if (sel && we) begin
                if (addr==8'h00) begin start<=wdata[0]; init_iv<=wdata[1]; end
                else if (addr>=8'h10 && addr<=8'h2c) blk_w[(addr-8'h10)>>2]<=wdata;
            end
        end
    end

    always @(*) begin
        rdata = 32'd0;
        if (addr==8'h04)                     rdata = {30'd0, core_done, core_busy};
        else if (addr>=8'h40 && addr<=8'h5c) rdata = digest[255 - 32*((addr-8'h40)>>2) -: 32];
    end
endmodule
`default_nettype wire
