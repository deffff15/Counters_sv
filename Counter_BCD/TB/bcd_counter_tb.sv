`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface bcd_if #(parameter int WIDTH = 4) (input logic clk);
    logic             rst_n;
    logic             enable;
    logic [WIDTH-1:0] Wy;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input enable, Wy;
    endclocking
endinterface


// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class BcdTxn #(parameter int WIDTH = 4);
    rand bit enable;
    logic [WIDTH-1:0] Wy;

    constraint c_ctrl {
        enable dist {1 := 85, 0 := 15};
    }
endclass


// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class BcdScoreboard #(parameter int WIDTH = 4);
    logic [WIDTH-1:0] expected_wy = '0;

    int checked = 0;
    int errors  = 0;
    int wraps   = 0;

    function void check(BcdTxn #(WIDTH) tr);
        bit ok = 1;

        if (tr.Wy !== expected_wy) begin
            $error("[SB] Wy mismatch @ %0t: got %0d (0x%0h), expected %0d (0x%0h)",
                   $time, tr.Wy, tr.Wy, expected_wy, expected_wy);
            ok = 0;
        end

        if (tr.enable) begin
            if (expected_wy >= 9) begin
                expected_wy = '0;
                wraps++;
            end
            else
                expected_wy = expected_wy + 1'b1;
        end

        checked++;
        if (!ok) errors++;
    endfunction

    function void report();
        $display("---------------- scoreboard ----------------");
        $display("cycles checked : %0d", checked);
        $display("errors         : %0d", errors);
        $display("wraps (9 -> 0) : %0d", wraps);
        $display("--------------------------------------------");

        if (wraps == 0)
            $warning("[SB] wrap-around 9 -> 0 never happened, run more cycles");
    endfunction
endclass


// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class BcdMonitor #(parameter int WIDTH = 4);
    virtual bcd_if #(WIDTH) vif;
    BcdScoreboard  #(WIDTH) sb;

    function new(virtual bcd_if #(WIDTH) vif, BcdScoreboard #(WIDTH) sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        BcdTxn #(WIDTH) tr;
        forever begin
            @(vif.mon_cb);
            tr = new();
            tr.enable = vif.mon_cb.enable;
            tr.Wy     = vif.mon_cb.Wy;
            sb.check(tr);
        end
    endtask
endclass


// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class BcdDriver #(parameter int WIDTH = 4);
    virtual bcd_if #(WIDTH) vif;

    function new(virtual bcd_if #(WIDTH) vif);
        this.vif = vif;
    endfunction

    task drive(BcdTxn #(WIDTH) tr);
        @(negedge vif.clk);
        vif.enable <= tr.enable;
    endtask
endclass


// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class BcdGenerator #(parameter int WIDTH = 4);
    BcdDriver #(WIDTH) drv;
    int                num_txn;

    function new(BcdDriver #(WIDTH) drv, int num_txn);
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        BcdTxn #(WIDTH) tr;
        repeat (num_txn) begin
            tr = new();
            if (!tr.randomize())
                $fatal(1, "[GEN] randomization failed");
            drv.drive(tr);
        end
    endtask
endclass


// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class BcdEnvironment #(parameter int WIDTH = 4);
    BcdGenerator  #(WIDTH) gen;
    BcdDriver     #(WIDTH) drv;
    BcdMonitor    #(WIDTH) mon;
    BcdScoreboard #(WIDTH) sb;

    virtual bcd_if #(WIDTH) vif;

    function new(virtual bcd_if #(WIDTH) vif, int num_txn = 150);
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
module tb_BCD;
    localparam int WIDTH = 4;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    bcd_if #(WIDTH) vif (clk);

    BCD #(.WIDTH(WIDTH)) dut (
        .clk    (clk),
        .rst_n  (vif.rst_n),
        .enable (vif.enable),
        .Wy     (vif.Wy)
    );

    BcdEnvironment #(WIDTH) env;

    initial begin
        $dumpfile("Counter_BCD_waveform.vcd");
        $dumpvars(0, tb_BCD);
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
        $fatal(1, "[TB] timeout");
    end
endmodule //The last line must be empty so VS Code doesn't throw an error.

