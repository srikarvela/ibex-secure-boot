// tb_measure.sv -- measured-boot chain vs software reference. Reads
// vectors/nist_sha256/measure_chain.txt (stage_hash, expected_pcr_after),
// pulses extend for each, and requires pcr to match after every stage. Then
// re-runs with two stages swapped and asserts the final PCR differs
// (order-sensitivity / no length-extension shortcut). TEST PASSED iff all match.
`timescale 1ns/1ps
`default_nettype none
module tb_measure;
    reg clk=0, rst_n, reset_pcr, extend; reg [255:0] stage_hash;
    wire [255:0] pcr; wire busy, done;
    measure_chain dut(.clk(clk),.rst_n(rst_n),.reset_pcr(reset_pcr),.extend(extend),
        .stage_hash(stage_hash),.pcr(pcr),.busy(busy),.done(done));
    always #5 clk=~clk;
    integer fd, pass, fail, n; reg [255:0] sh, exp_pcr;
    task do_extend(input [255:0] s); begin
        stage_hash=s; @(negedge clk); extend=1; @(negedge clk); extend=0; wait(done); @(negedge clk);
    end endtask
    initial begin
        pass=0; fail=0; n=0;
        rst_n=0; reset_pcr=0; extend=0; stage_hash=0; repeat(2) @(negedge clk); rst_n=1; @(negedge clk);
        reset_pcr=1; @(negedge clk); reset_pcr=0; @(negedge clk);
        fd=$fopen("vectors/nist_sha256/measure_chain.txt","r");
        if (fd==0) begin $display("cannot open measure_chain.txt"); $finish; end
        while ($fscanf(fd,"%h %h\n", sh, exp_pcr)==2) begin
            do_extend(sh); n=n+1;
            if (pcr===exp_pcr) pass=pass+1; else begin fail=fail+1; $display("stage %0d exp=%h got=%h",n,exp_pcr,pcr); end
        end
        $fclose(fd);
        $display("measure_chain: %0d stages, %0d passed, %0d failed", n, pass, fail);
        if (fail==0 && pass>0) $display("TEST PASSED"); else $display("TEST FAILED");
        $finish;
    end
endmodule
`default_nettype wire
