// =============================================================================
// tb_sha256.sv -- bit-exact check of sha256_core against golden vectors.
//
// Reads vectors/nist_sha256/sha256_blocks.txt: per message, "<nblk> <digest>"
// then <nblk> pre-padded 512-bit blocks (128 hex each). Chains the core from
// the SHA-256 IV across blocks and requires every output bit to equal the
// golden digest. Padding was done by the vector generator; the RTL core is the
// only thing under test here. Prints TEST PASSED iff all vectors match.
//   iverilog -g2012 -o build/tb_sha256.vvp rtl/sha256_core.sv tb/tb_sha256.sv
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_sha256;
    localparam [255:0] IV = {32'h6a09e667,32'hbb67ae85,32'h3c6ef372,32'ha54ff53a,
                             32'h510e527f,32'h9b05688c,32'h1f83d9ab,32'h5be0cd19};
    reg          clk=0, rst_n=0, start=0;
    reg  [511:0] block;
    reg  [255:0] h_in;
    wire         done, busy;
    wire [255:0] h_out;

    sha256_core dut(.clk(clk),.rst_n(rst_n),.start(start),.block(block),
                    .h_in(h_in),.done(done),.h_out(h_out),.busy(busy));
    always #5 clk = ~clk;

    integer fd;
    integer r;
    integer nblk;
    integer bi;
    integer pass;
    integer fail;
    integer nvec;
    reg [255:0] exp_md;
    reg [255:0] h;
    initial begin
        pass=0; fail=0; nvec=0;
        rst_n=0; repeat(3) @(negedge clk); rst_n=1; @(negedge clk);
        fd=$fopen("vectors/nist_sha256/sha256_blocks.txt","r");
        if (fd==0) begin $display("cannot open sha256_blocks.txt"); $finish; end
        while ($fscanf(fd,"%d %h\n", nblk, exp_md)==2) begin
            nvec=nvec+1; h=IV;
            for (bi=0; bi<nblk; bi=bi+1) begin
                r=$fscanf(fd,"%h\n", block);
                h_in=h; @(negedge clk); start=1; @(negedge clk); start=0;
                wait(done); @(negedge clk); h=h_out;
            end
            if (h===exp_md) pass=pass+1;
            else begin fail=fail+1; $display("MISMATCH vec %0d exp=%h got=%h", nvec, exp_md, h); end
        end
        $fclose(fd);
        $display("SHA-256 vectors: %0d passed, %0d failed", pass, fail);
        if (fail==0 && pass>0) $display("TEST PASSED"); else $display("TEST FAILED");
        $finish;
    end
endmodule
`default_nettype wire
