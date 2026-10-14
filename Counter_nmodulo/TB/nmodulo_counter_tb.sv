`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface nmodule_counter_if #(parameter int MODULO = 4) (input logic clk);
    logic rst_n;
    logic enable;
    logic [$clog2(MODULO)-1:0] modulo_Wy;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, enable, modulo_Wy;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class CounterTxn #(parameter int MODULO = 4);
    rand bit enable;
    logic [$clog2(MODULO)-1:0] modulo_Wy;

    constraint c_enable {
        enable dist {1 := 80, 0 := 20};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class CounterScoreboard #(parameter int MODULO = 4);
    logic [$clog2(MODULO)-1:0] expected = '0;

    int checked = 0;
    int errors  = 0;
    int counts  = 0;
    int holds   = 0;

    function void check(CounterTxn #(MODULO) tr);
        bit ok = 1;

        if (tr.modulo_Wy !== expected) begin
            $error("[SB] modulo_Wy mismatch @ %0t: got %0d, expected %0d",
                   $time, tr.modulo_Wy, expected);
            ok = 0;
        end

        if (tr.enable) begin
            if (expected == MODULO-1)
                expected = '0;
            else
                expected = expected + 1'b1;

            counts++;
        end
        else begin
            holds++;
        end

        checked++;

        if (!ok)
            errors++;
    endfunction

    function void reset();
        expected = '0;
    endfunction

    function void report();
        $display("------------ Counter scoreboard ------------");
        $display("cycles checked : %0d", checked);
        $display("errors         : %0d", errors);
        $display("counts         : %0d", counts);
        $display("holds          : %0d", holds);
        $display("--------------------------------------------");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class CounterMonitor #(parameter int MODULO = 4);
    virtual nmodule_counter_if #(MODULO) vif;
    CounterScoreboard #(MODULO) sb;

    function new(
        virtual nmodule_counter_if #(MODULO) vif,
        CounterScoreboard #(MODULO) sb
    );
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        CounterTxn #(MODULO) tr;

        forever begin
            @(vif.mon_cb);

            if (!vif.mon_cb.rst_n) begin
                sb.reset();
            end
            else begin
                tr = new();
                tr.enable    = vif.mon_cb.enable;
                tr.modulo_Wy = vif.mon_cb.modulo_Wy;

                sb.check(tr);
            end
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class CounterDriver #(parameter int MODULO = 4);
    virtual nmodule_counter_if #(MODULO) vif;

    function new(virtual nmodule_counter_if #(MODULO) vif);
        this.vif = vif;
    endfunction

    task drive(CounterTxn #(MODULO) tr);
        @(negedge vif.clk);
        vif.enable <= tr.enable;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class CounterGenerator #(parameter int MODULO = 4);
    CounterDriver #(MODULO) drv;
    int num_txn;

    function new(CounterDriver #(MODULO) drv, int num_txn);
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        CounterTxn #(MODULO) tr;

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
class CounterEnvironment #(parameter int MODULO = 4);
    CounterGenerator  #(MODULO) gen;
    CounterDriver     #(MODULO) drv;
    CounterMonitor    #(MODULO) mon;
    CounterScoreboard #(MODULO) sb;

    virtual nmodule_counter_if #(MODULO) vif;

    function new(
        virtual nmodule_counter_if #(MODULO) vif,
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
        #2;
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
module tb_nmodule_counter;
    localparam int MODULO = 4;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    nmodule_counter_if #(MODULO) vif(clk);

    nmodule_counter #(
        .MODULO(MODULO)
    ) dut (
        .clk       (clk),
        .rst_n     (vif.rst_n),
        .enable    (vif.enable),
        .modulo_Wy (vif.modulo_Wy)
    );

    CounterEnvironment #(MODULO) env;

    initial begin
        $dumpfile("nmodule_counter_waveform.vcd");
        $dumpvars(0, tb_nmodule_counter);
    end

    initial begin
        vif.rst_n  = 1'b0;
        vif.enable = 1'b0;

        repeat (2) @(negedge clk);
        vif.rst_n = 1'b1;
        @(negedge clk);

        env = new(vif, 150);
        env.run();

        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "[TB] Timeout");
    end
endmodule //The last line must be empty so VS Code doesn't throw an error.

