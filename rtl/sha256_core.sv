// =============================================================================
// sha256_core.sv -- FIPS 180-4 SHA-256 compression, one 512-bit block at a time.
//
// Pure computation, no bus. Feed one 512-bit padded block per `start` pulse
// with the running hash `h_in`; after `done` the updated hash is on `h_out`.
// The message schedule is expanded 1 word/cycle (16 preload + 48 extend), then
// 64 compression rounds run 1/cycle, so a block takes ~64 cycles. That is the
// honest area/latency trade the guide asks for: hash in hardware, small and
// slow, signature math left to software.
//
// Verified bit-exact against the NIST SHA-256 short/long byte-oriented test
// vectors -- see tb/tb_sha256.sv and vectors/nist_sha256/.
// =============================================================================
`default_nettype none

module sha256_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,        // pulse: begin compressing `block` into `h_in`
    input  wire [511:0] block,        // one 512-bit message block, big-endian words
    input  wire [255:0] h_in,         // running hash (init constants for first block)
    output reg          done,         // pulse: `h_out` valid
    output reg  [255:0] h_out,
    output reg          busy
);
    // Round constants K[0..63]
    function [31:0] kconst(input [5:0] i);
        case (i)
            6'd0: kconst=32'h428a2f98; 6'd1: kconst=32'h71374491;
            6'd2: kconst=32'hb5c0fbcf; 6'd3: kconst=32'he9b5dba5;
            6'd4: kconst=32'h3956c25b; 6'd5: kconst=32'h59f111f1;
            6'd6: kconst=32'h923f82a4; 6'd7: kconst=32'hab1c5ed5;
            6'd8: kconst=32'hd807aa98; 6'd9: kconst=32'h12835b01;
            6'd10:kconst=32'h243185be; 6'd11:kconst=32'h550c7dc3;
            6'd12:kconst=32'h72be5d74; 6'd13:kconst=32'h80deb1fe;
            6'd14:kconst=32'h9bdc06a7; 6'd15:kconst=32'hc19bf174;
            6'd16:kconst=32'he49b69c1; 6'd17:kconst=32'hefbe4786;
            6'd18:kconst=32'h0fc19dc6; 6'd19:kconst=32'h240ca1cc;
            6'd20:kconst=32'h2de92c6f; 6'd21:kconst=32'h4a7484aa;
            6'd22:kconst=32'h5cb0a9dc; 6'd23:kconst=32'h76f988da;
            6'd24:kconst=32'h983e5152; 6'd25:kconst=32'ha831c66d;
            6'd26:kconst=32'hb00327c8; 6'd27:kconst=32'hbf597fc7;
            6'd28:kconst=32'hc6e00bf3; 6'd29:kconst=32'hd5a79147;
            6'd30:kconst=32'h06ca6351; 6'd31:kconst=32'h14292967;
            6'd32:kconst=32'h27b70a85; 6'd33:kconst=32'h2e1b2138;
            6'd34:kconst=32'h4d2c6dfc; 6'd35:kconst=32'h53380d13;
            6'd36:kconst=32'h650a7354; 6'd37:kconst=32'h766a0abb;
            6'd38:kconst=32'h81c2c92e; 6'd39:kconst=32'h92722c85;
            6'd40:kconst=32'ha2bfe8a1; 6'd41:kconst=32'ha81a664b;
            6'd42:kconst=32'hc24b8b70; 6'd43:kconst=32'hc76c51a3;
            6'd44:kconst=32'hd192e819; 6'd45:kconst=32'hd6990624;
            6'd46:kconst=32'hf40e3585; 6'd47:kconst=32'h106aa070;
            6'd48:kconst=32'h19a4c116; 6'd49:kconst=32'h1e376c08;
            6'd50:kconst=32'h2748774c; 6'd51:kconst=32'h34b0bcb5;
            6'd52:kconst=32'h391c0cb3; 6'd53:kconst=32'h4ed8aa4a;
            6'd54:kconst=32'h5b9cca4f; 6'd55:kconst=32'h682e6ff3;
            6'd56:kconst=32'h748f82ee; 6'd57:kconst=32'h78a5636f;
            6'd58:kconst=32'h84c87814; 6'd59:kconst=32'h8cc70208;
            6'd60:kconst=32'h90befffa; 6'd61:kconst=32'ha4506ceb;
            6'd62:kconst=32'hbef9a3f7; 6'd63:kconst=32'hc67178f2;
            default: kconst=32'h0;
        endcase
    endfunction

    function [31:0] rotr(input [31:0] x, input [4:0] n);
        rotr = (x >> n) | (x << (6'd32 - n));
    endfunction
    function [31:0] ssig0(input [31:0] x); ssig0 = rotr(x,7)  ^ rotr(x,18) ^ (x>>3);  endfunction
    function [31:0] ssig1(input [31:0] x); ssig1 = rotr(x,17) ^ rotr(x,19) ^ (x>>10); endfunction
    function [31:0] bsig0(input [31:0] x); bsig0 = rotr(x,2)  ^ rotr(x,13) ^ rotr(x,22); endfunction
    function [31:0] bsig1(input [31:0] x); bsig1 = rotr(x,6)  ^ rotr(x,11) ^ rotr(x,25); endfunction
    function [31:0] ch (input [31:0] x,y,z); ch  = (x & y) ^ (~x & z);        endfunction
    function [31:0] maj(input [31:0] x,y,z); maj = (x & y) ^ (x & z) ^ (y & z); endfunction

    localparam S_IDLE = 2'd0, S_RUN = 2'd1, S_FIN = 2'd2;
    reg [1:0]  state;
    reg [6:0]  rnd;               // 0..63
    reg [31:0] w [0:15];          // circular message-schedule window
    reg [31:0] a,b,c,d,e,f,g,h;   // working vars
    reg [31:0] h0,h1,h2,h3,h4,h5,h6,h7;

    wire [31:0] wt   = w[0];
    wire [31:0] wnew = ssig1(w[14]) + w[9] + ssig0(w[1]) + w[0];
    wire [31:0] t1   = h + bsig1(e) + ch(e,f,g) + kconst(rnd[5:0]) + wt;
    wire [31:0] t2   = bsig0(a) + maj(a,b,c);

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; done<=1'b0; busy<=1'b0; rnd<=7'd0; h_out<=256'd0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: if (start) begin
                    {h0,h1,h2,h3,h4,h5,h6,h7} <= h_in;
                    {a,b,c,d,e,f,g,h}         <= h_in;
                    for (i=0;i<16;i=i+1) w[i] <= block[511-32*i -: 32];
                    rnd<=7'd0; busy<=1'b1; state<=S_RUN;
                end
                S_RUN: begin
                    // one compression round + advance the schedule window
                    h<=g; g<=f; f<=e; e<=d + t1;
                    d<=c; c<=b; b<=a; a<=t1 + t2;
                    for (i=0;i<15;i=i+1) w[i] <= w[i+1];
                    w[15] <= wnew;
                    if (rnd==7'd63) state<=S_FIN; else rnd<=rnd+7'd1;
                end
                S_FIN: begin
                    h_out <= {h0+a, h1+b, h2+c, h3+d, h4+e, h5+f, h6+g, h7+h};
                    done<=1'b1; busy<=1'b0; state<=S_IDLE;
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
