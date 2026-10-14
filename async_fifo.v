// Asynchronous FIFO (dual-clock) - synthesizable Verilog-2001
// Gray-code pointers + 2-FF synchronizers (Cummings style)
// Depth = 2**ASIZE. Read data is valid whenever rempty = 0 (first-word fall-through).

module async_fifo #(
    parameter DSIZE = 8,   // data width
    parameter ASIZE = 4    // address width -> depth = 16
)(
    // write domain
    input  wire             wclk,
    input  wire             wrst_n,
    input  wire             winc,
    input  wire [DSIZE-1:0] wdata,
    output wire             wfull,
    // read domain
    input  wire             rclk,
    input  wire             rrst_n,
    input  wire             rinc,
    output wire [DSIZE-1:0] rdata,
    output wire             rempty
);

    wire [ASIZE-1:0] waddr, raddr;
    wire [ASIZE:0]   wptr, rptr, wq2_rptr, rq2_wptr;

    // read pointer -> write clock domain
    sync_2ff #(ASIZE+1) sync_r2w (
        .clk(wclk), .rst_n(wrst_n), .d(rptr), .q(wq2_rptr)
    );

    // write pointer -> read clock domain
    sync_2ff #(ASIZE+1) sync_w2r (
        .clk(rclk), .rst_n(rrst_n), .d(wptr), .q(rq2_wptr)
    );

    fifo_mem #(DSIZE, ASIZE) mem (
        .wclk(wclk), .wen(winc & ~wfull),
        .waddr(waddr), .wdata(wdata),
        .raddr(raddr), .rdata(rdata)
    );

    rptr_empty #(ASIZE) rptr_inst (
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc),
        .rq2_wptr(rq2_wptr),
        .rempty(rempty), .raddr(raddr), .rptr(rptr)
    );

    wptr_full #(ASIZE) wptr_inst (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc),
        .wq2_rptr(wq2_rptr),
        .wfull(wfull), .waddr(waddr), .wptr(wptr)
    );

endmodule


// 2-flop synchronizer
module sync_2ff #(parameter WIDTH = 5)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);
    reg [WIDTH-1:0] q1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {q, q1} <= {2*WIDTH{1'b0}};
        else        {q, q1} <= {q1, d};
    end
endmodule


// Dual-port memory: write on wclk, asynchronous read
module fifo_mem #(
    parameter DSIZE = 8,
    parameter ASIZE = 4
)(
    input  wire             wclk,
    input  wire             wen,
    input  wire [ASIZE-1:0] waddr,
    input  wire [DSIZE-1:0] wdata,
    input  wire [ASIZE-1:0] raddr,
    output wire [DSIZE-1:0] rdata
);
    localparam DEPTH = 1 << ASIZE;
    reg [DSIZE-1:0] mem [0:DEPTH-1];

    assign rdata = mem[raddr];

    always @(posedge wclk)
        if (wen) mem[waddr] <= wdata;
endmodule


// Read pointer and empty flag (read clock domain)
module rptr_empty #(parameter ASIZE = 4)(
    input  wire             rclk,
    input  wire             rrst_n,
    input  wire             rinc,
    input  wire [ASIZE:0]   rq2_wptr,   // synchronized gray write pointer
    output reg              rempty,
    output wire [ASIZE-1:0] raddr,
    output reg  [ASIZE:0]   rptr        // gray read pointer
);
    reg  [ASIZE:0] rbin;
    wire [ASIZE:0] rbin_next, rgray_next;

    assign raddr      = rbin[ASIZE-1:0];
    assign rbin_next  = rbin + (rinc & ~rempty);
    assign rgray_next = (rbin_next >> 1) ^ rbin_next;

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) {rbin, rptr} <= 0;
        else         {rbin, rptr} <= {rbin_next, rgray_next};
    end

    // empty when next read gray pointer equals synchronized write gray pointer
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) rempty <= 1'b1;
        else         rempty <= (rgray_next == rq2_wptr);
    end
endmodule


// Write pointer and full flag (write clock domain)
module wptr_full #(parameter ASIZE = 4)(
    input  wire             wclk,
    input  wire             wrst_n,
    input  wire             winc,
    input  wire [ASIZE:0]   wq2_rptr,   // synchronized gray read pointer
    output reg              wfull,
    output wire [ASIZE-1:0] waddr,
    output reg  [ASIZE:0]   wptr        // gray write pointer
);
    reg  [ASIZE:0] wbin;
    wire [ASIZE:0] wbin_next, wgray_next;

    assign waddr      = wbin[ASIZE-1:0];
    assign wbin_next  = wbin + (winc & ~wfull);
    assign wgray_next = (wbin_next >> 1) ^ wbin_next;

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) {wbin, wptr} <= 0;
        else         {wbin, wptr} <= {wbin_next, wgray_next};
    end

    // full when the two MSBs of the gray pointer differ and the rest match
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) wfull <= 1'b0;
        else         wfull <= (wgray_next ==
                              {~wq2_rptr[ASIZE:ASIZE-1], wq2_rptr[ASIZE-2:0]});
    end
endmodule