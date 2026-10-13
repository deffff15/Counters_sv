`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface gray_if #(parameter int WIDTH = 4) (input logic clk);
    logic             rst_n;
    logic             enable;
    logic [WIDTH-1:0] Wy;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, enable, Wy;
    endclocking
endinterface


// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class GrayTxn #(parameter int WIDTH = 4);
    rand bit enable;
    logic [WIDTH-1:0] Wy;

    constraint c_ctrl {
        enable dist {1 := 80, 0 := 20};
    }
endclass


// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class GrayScoreboard #(parameter int WIDTH = 4);
    logic [WIDTH-1:0] expected_bin = '0;
    logic [WIDTH-1:0] expected_wy  = '0;

    int checked = 0;
    int errors  = 0;
    int increments = 0;
    int holds = 0;
    int wraps = 0;

    function void check(GrayTxn #(WIDTH) tr);
        bit ok = 1;

        if (tr.Wy !== expected_wy) begin
            $error("[SB] Wy mismatch @ %0t: got %b, expected %b",
                   $time, tr.Wy, expected_wy);
            ok = 0;
        end

        if (tr.enable) begin
            if (expected_bin == {WIDTH{1'b1}})
                wraps++;

            expected_bin = expected_bin + 1'b1;
            expected_wy = (expected_bin >> 1) ^ expected_bin;

            increments++;
        end
        else begin
            holds++;
        end

        checked++;

        if (!ok)
            errors++;
    endfunction

    function void reset();
        expected_bin = '0;
        expected_wy  = '0;
    endfunction

    function void report();
        $display("------------- Gray counter scoreboard -------------");
        $display("cycles checked : %0d", checked);
        $display("errors         : %0d", errors);
        $display("increments     : %0d", increments);
        $display("holds          : %0d", holds);
        $display("wraps          : %0d", wraps);
        $display("----------------------------------------------------");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class GrayMonitor #(parameter int WIDTH = 4);
    virtual gray_if #(WIDTH) vif;
    GrayScoreboard #(WIDTH) sb;

    function new(
        virtual gray_if #(WIDTH) vif,
        GrayScoreboard #(WIDTH) sb
    );
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        GrayTxn #(WIDTH) tr;

        forever begin
            @(vif.mon_cb);

            if (!vif.mon_cb.rst_n) begin
                sb.reset();
            end
            else begin
                tr = new();
                tr.enable = vif.mon_cb.enable;
                tr.Wy     = vif.mon_cb.Wy;

                sb.check(tr);
            end
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class GrayDriver #(parameter int WIDTH = 4);
    virtual gray_if #(WIDTH) vif;

    function new(virtual gray_if #(WIDTH) vif);
        this.vif = vif;
    endfunction

    task drive(GrayTxn #(WIDTH) tr);
        @(negedge vif.clk);
        vif.enable <= tr.enable;
    endtask
endclass


// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class GrayGenerator #(parameter int WIDTH = 4);
    GrayDriver #(WIDTH) drv;
    int num_txn;

    function new(GrayDriver #(WIDTH) drv, int num_txn);
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        GrayTxn #(WIDTH) tr;

        repeat (num_txn) begin
            tr = new();

            if (!tr.randomize())
                $fatal(1, "[GEN] Randomization failed");

            drv.drive(tr);
        end
    endtask
endclass


// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class GrayEnvironment #(parameter int WIDTH = 4);
    GrayGenerator  #(WIDTH) gen;
    GrayDriver     #(WIDTH) drv;
    GrayMonitor    #(WIDTH) mon;
    GrayScoreboard #(WIDTH) sb;

    virtual gray_if #(WIDTH) vif;

    function new(
        virtual gray_if #(WIDTH) vif,
        int num_txn = 150
    );
        this.vif = vif;

        sb  = new();
        drv = new(vif);
        mon = new(vif, sb);
        gen = new(drv, num_txn);
    endfunction

    task run();
        fork
            mon.run();
        join_none

        gen.run();

        repeat (2) @(posedge vif.clk);
        #1;
        sb.report();

        if (sb.errors != 0)
            $fatal(1, "[ENV] TEST FAILED (%0d errors)", sb.errors);
        else
            $display("[ENV] TEST PASSED");
    endtask
endclass


// ---------------------------------------------------------------------------
// Top
// ---------------------------------------------------------------------------
module tb_gray_counter;
    localparam int WIDTH = 4;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    gray_if #(WIDTH) vif(clk);

    gray_counter #(
        .WIDTH(WIDTH)
    ) dut (
        .clk    (clk),
        .rst_n  (vif.rst_n),
        .enable (vif.enable),
        .Wy     (vif.Wy)
    );

    GrayEnvironment #(WIDTH) env;

    initial begin
        $dumpfile("Gray_counter_waveform.vcd");
        $dumpvars(0, tb_gray_counter);
    end

    initial begin
        vif.rst_n  = 1'b0;
        vif.enable = 1'b0;

        repeat (2) @(negedge clk);
        vif.rst_n = 1'b1;
        @(negedge clk);

        env = new(vif);
        env.run();

        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "[TB] Timeout");
    end
endmodule //The last line must be empty so VS Code doesn't throw an error.

