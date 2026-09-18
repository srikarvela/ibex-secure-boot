// tb_key_store.sv -- the project's most important assertion: after a key is
// provisioned in the TEST window, CPU reads of the key region return 0 while
// the crypto port carries the real key. Also: write-once per word, lock is
// one-way, and writes outside the window / after lock are rejected.
`timescale 1ns/1ps
`default_nettype none
module tb_key_store;
    reg clk=0, rst_n, key_writable, lock_req, cpu_we; reg [2:0] cpu_addr; reg [31:0] cpu_wdata;
    wire [31:0] cpu_rdata; wire [255:0] crypto_key_o; wire locked;
    key_store dut(.clk(clk),.rst_n(rst_n),.key_writable(key_writable),.lock_req(lock_req),
        .cpu_we(cpu_we),.cpu_addr(cpu_addr),.cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),.crypto_key_o(crypto_key_o),.locked(locked));
    always #5 clk=~clk;
    integer pass, fail, i; reg [31:0] kw [0:7]; reg [255:0] expect_key;
    task wr(input [2:0] a, input [31:0] d); begin cpu_addr=a; cpu_wdata=d; cpu_we=1; @(negedge clk); cpu_we=0; @(negedge clk); end endtask
    initial begin
        pass=0; fail=0; rst_n=0; key_writable=0; lock_req=0; cpu_we=0; cpu_addr=0; cpu_wdata=0;
        repeat(2) @(negedge clk); rst_n=1; @(negedge clk);
        for (i=0;i<8;i=i+1) kw[i]=32'hA5A50000 + i;
        // 1. write outside window rejected
        key_writable=0; wr(0, 32'hDEADBEEF);
        if (crypto_key_o[31:0]===32'd0) pass=pass+1; else begin fail=fail+1; $display("write leaked outside window"); end
        // 2. provision in TEST window
        key_writable=1; for (i=0;i<8;i=i+1) wr(i[2:0], kw[i]);
        expect_key=0; for (i=0;i<8;i=i+1) expect_key[32*i +: 32]=kw[i];
        if (crypto_key_o===expect_key) pass=pass+1; else begin fail=fail+1; $display("crypto key wrong: %h",crypto_key_o); end
        // 3. CPU reads of key region are ZERO regardless of address (THE assertion)
        for (i=0;i<8;i=i+1) begin cpu_addr=i[2:0]; #1; if (cpu_rdata===32'd0) pass=pass+1; else begin fail=fail+1; $display("CPU read leaked key word %0d = %h",i,cpu_rdata); end end
        // 4. write-once: second write to word 0 ignored
        wr(0, 32'hFFFFFFFF);
        if (crypto_key_o[31:0]===kw[0]) pass=pass+1; else begin fail=fail+1; $display("write-once violated"); end
        // 5. lock is one-way and blocks further writes
        lock_req=1; @(negedge clk); lock_req=0; @(negedge clk);
        wr(4, 32'h12345678);
        if (locked && crypto_key_o[32*4 +: 32]===kw[4]) pass=pass+1; else begin fail=fail+1; $display("locked write got through"); end
        $display("key_store: %0d passed, %0d failed", pass, fail);
        if (fail==0) $display("TEST PASSED"); else $display("TEST FAILED");
        $finish;
    end
endmodule
`default_nettype wire
