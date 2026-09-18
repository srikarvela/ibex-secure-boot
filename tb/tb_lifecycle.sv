// tb_lifecycle.sv -- exhaustive check of the one-way lifecycle FSM.
// For every (current state, requested state) pair, drive `advance` and assert:
// the move is taken iff requested == current+1 and current != LOCKED; otherwise
// state is unchanged and illegal_seen latches. Also checks reset -> RAW and the
// key_writable/boot_enabled derivations. Prints TEST PASSED iff all pass.
`timescale 1ns/1ps
`default_nettype none
module tb_lifecycle;
    reg clk=0, rst_n, advance; reg [1:0] req_state;
    wire [1:0] state; wire key_writable, boot_enabled, illegal_seen;
    lifecycle_fsm dut(.clk(clk),.rst_n(rst_n),.advance(advance),.req_state(req_state),
        .state(state),.key_writable(key_writable),.boot_enabled(boot_enabled),.illegal_seen(illegal_seen));
    always #5 clk=~clk;
    integer pass, fail, cur, req;
    task force_state(input [1:0] s);
        integer k;
        begin
            rst_n=0; advance=0; @(negedge clk); rst_n=1; @(negedge clk);
            for (k=0;k<s;k=k+1) begin req_state=k+1; advance=1; @(negedge clk); advance=0; @(negedge clk); end
        end
    endtask
    initial begin
        pass=0; fail=0;
        for (cur=0; cur<4; cur=cur+1) begin
            for (req=0; req<4; req=req+1) begin
                force_state(cur[1:0]);
                if (state!==cur[1:0]) begin fail=fail+1; $display("SETUP FAIL cur=%0d got=%0d",cur,state); end
                req_state=req[1:0]; advance=1; @(negedge clk); advance=0; @(negedge clk);
                if (cur!=3 && req==cur+1) begin // legal
                    if (state===req[1:0]) pass=pass+1;
                    else begin fail=fail+1; $display("LEGAL REJECTED cur=%0d req=%0d state=%0d",cur,req,state); end
                end else begin // illegal
                    if (state===cur[1:0] && illegal_seen) pass=pass+1;
                    else begin fail=fail+1; $display("ILLEGAL TOOK cur=%0d req=%0d state=%0d ill=%b",cur,req,state,illegal_seen); end
                end
            end
        end
        // derivation checks
        force_state(2'd1); if (key_writable && !boot_enabled) pass=pass+1; else begin fail=fail+1; $display("TEST gates wrong"); end
        force_state(2'd2); if (!key_writable && boot_enabled) pass=pass+1; else begin fail=fail+1; $display("PROD gates wrong"); end
        $display("lifecycle: %0d passed, %0d failed", pass, fail);
        if (fail==0) $display("TEST PASSED"); else $display("TEST FAILED");
        $finish;
    end
endmodule
`default_nettype wire
