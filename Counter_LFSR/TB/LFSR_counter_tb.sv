`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface lfsr_if #(parameter int WIDTH = 4) (input logic clk);
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
class LfsrTxn #(parameter int WIDTH = 4);
    rand bit enable;
    logic [WIDTH-1:0] Wy;

    constraint c_ctrl {
        enable dist {1 := 80, 0 := 20};
    }
endclass


// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class LfsrScoreboard #(parameter int WIDTH = 4);
    logic [WIDTH-1:0] expected_wy = '1;

    int checked = 0;
    int errors  = 0;
    int shifts  = 0;
    int holds   = 0;

    function void check(LfsrTxn #(WIDTH) tr);
        bit ok = 1;
        logic [WIDTH-1:0] next_wy;

        if (tr.Wy !== expected_wy) begin
            $error("[SB] Wy mismatch @ %0t: got %b, expected %b",
                   $time, tr.Wy, expected_wy);
            ok = 0;
        end

        if (tr.enable) begin
            next_wy = {expected_wy[WIDTH-2:0],
                       expected_wy[WIDTH-1] ^ expected_wy[WIDTH-2]};
            expected_wy = next_wy;
            shifts++;
        end
        else begin
            holds++;
        end

        checked++;
        if (!ok)
            errors++;
    endfunction

    function void reset();
        expected_wy = '1;
    endfunction

    function void report();
        $display("--------------- LFSR scoreboard ---------------");
        $display("cycles checked : %0d", checked);
        $display("errors         : %0d", errors);
        $display("shifts         : %0d", shifts);
        $display("holds          : %0d", holds);
        $display("-----------------------------------------------");
    endfunction
endclass


// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class LfsrMonitor #(parameter int WIDTH = 4);
    virtual lfsr_if #(WIDTH) vif;
    LfsrScoreboard #(WIDTH) sb;

    function new(
        virtual lfsr_if #(WIDTH) vif,
        LfsrScoreboard #(WIDTH) sb
    );
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        LfsrTxn #(WIDTH) tr;

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
class LfsrDriver #(parameter int WIDTH = 4);
    virtual lfsr_if #(WIDTH) vif;

    function new(virtual lfsr_if #(WIDTH) vif);
        this.vif = vif;
    endfunction

    task drive(LfsrTxn #(WIDTH) tr);
        @(negedge vif.clk);
        vif.enable <= tr.enable;
    endtask
endclass


// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class LfsrGenerator #(parameter int WIDTH = 4);
    LfsrDriver #(WIDTH) drv;
    int num_txn;

    function new(LfsrDriver #(WIDTH) drv, int num_txn);
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        LfsrTxn #(WIDTH) tr;

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
class LfsrEnvironment #(parameter int WIDTH = 4);
    LfsrGenerator  #(WIDTH) gen;
    LfsrDriver     #(WIDTH) drv;
    LfsrMonitor    #(WIDTH) mon;
    LfsrScoreboard #(WIDTH) sb;

    virtual lfsr_if #(WIDTH) vif;

    function new(
        virtual lfsr_if #(WIDTH) vif,
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
module tb_LFSR;
    localparam int WIDTH = 4;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    lfsr_if #(WIDTH) vif(clk);

    LFSR #(
        .WIDTH(WIDTH)
    ) dut (
        .clk    (clk),
        .rst_n  (vif.rst_n),
        .enable (vif.enable),
        .Wy     (vif.Wy)
    );

    LfsrEnvironment #(WIDTH) env;

    initial begin
        $dumpfile("LFSR_waveform.vcd");
        $dumpvars(0, tb_LFSR);
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

