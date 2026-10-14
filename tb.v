`timescale 1ns/1ps
// Minimal testbench: 5 test cases
module tb_async_fifo;
    localparam DSIZE = 8, ASIZE = 4, DEPTH = 1 << ASIZE;

    reg              wclk = 0, rclk = 0, wrst_n = 0, rrst_n = 0;
    reg              winc = 0, rinc = 0;
    reg  [DSIZE-1:0] wdata = 0;
    wire [DSIZE-1:0] rdata;
    wire             wfull, rempty;

    integer errors = 0;
    integer i;
    reg [DSIZE-1:0] tmp;

    async_fifo #(DSIZE, ASIZE) dut (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wdata(wdata), .wfull(wfull),
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rdata(rdata), .rempty(rempty)
    );

    always #5 wclk = ~wclk;   // 100 MHz
    always #7 rclk = ~rclk;   // ~71 MHz

    task write_word(input [DSIZE-1:0] d);
    begin
        @(negedge wclk);
        while (wfull) @(negedge wclk);
        winc = 1; wdata = d;
        @(negedge wclk);
        winc = 0;
    end
    endtask

    task read_word(output [DSIZE-1:0] d);
    begin
        @(negedge rclk);
        while (rempty) @(negedge rclk);
        d = rdata; rinc = 1;
        @(negedge rclk);
        rinc = 0;
    end
    endtask

    task check(input cond, input [255:0] msg);
    begin
        if (!cond) begin
            errors = errors + 1;
            $display("FAIL: %0s (t=%0t)", msg, $time);
        end
    end
    endtask

    initial begin
        // Test 1: reset state
        #40; wrst_n = 1; rrst_n = 1; #40;
        check(rempty === 1'b1 && wfull === 1'b0, "T1 reset: empty=1, full=0");
        $display("T1 done");

        // Test 2: single write / read
        write_word(8'hA5);
        repeat (6) @(negedge rclk);
        check(rempty === 1'b0, "T2 empty deasserts after write");
        read_word(tmp);
        check(tmp === 8'hA5, "T2 data match");
        repeat (6) @(negedge rclk);
        check(rempty === 1'b1, "T2 empty reasserts");
        $display("T2 done");

        // Test 3: fill to full
        for (i = 0; i < DEPTH; i = i + 1) write_word(8'h10 + i);
        repeat (6) @(negedge wclk);
        check(wfull === 1'b1, "T3 full asserted");
        $display("T3 done");

        // Test 4: drain in order, check empty
        for (i = 0; i < DEPTH; i = i + 1) begin
            read_word(tmp);
            check(tmp === 8'h10 + i, "T4 data order");
        end
        repeat (6) @(negedge rclk);
        check(rempty === 1'b1, "T4 empty after drain");
        $display("T4 done");

        // Test 5: concurrent streaming across clock domains (wrap-around)
        fork
            begin : wr
                integer k;
                for (k = 0; k < 100; k = k + 1) write_word(k * 3 + 1);
            end
            begin : rd
                integer j;
                reg [DSIZE-1:0] t;
                for (j = 0; j < 100; j = j + 1) begin
                    read_word(t);
                    check(t === ((j * 3 + 1) & 8'hFF), "T5 stream data");
                end
            end
        join
        $display("T5 done");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d ERRORS", errors);
        $finish;
    end
endmodule