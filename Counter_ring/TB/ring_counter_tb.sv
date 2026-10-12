`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface ring_counter_if #(parameter int WIDTH = 4) (input logic clk);

    logic rst_n;
    logic enable;
    logic [WIDTH-1:0] Wy;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, enable, Wy;
    endclocking

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class RingCounterTxn #(parameter int WIDTH = 4);

    rand bit enable;
    logic [WIDTH-1:0] Wy;

    constraint c_ctrl {
        enable dist {1 := 80, 0 := 20};
    }

endclass


// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class RingCounterScoreboard #(parameter int WIDTH = 4);

    logic [WIDTH-1:0] expected_wy =
        {{(WIDTH-1){1'b0}}, 1'b1};

    int checked = 0;
    int errors = 0;

    function void check(RingCounterTxn #(WIDTH) tr);

        if (tr.Wy !== expected_wy) begin
            $error("[SB] Wy mismatch: got %b, expected %b",
                   tr.Wy, expected_wy);
            errors++;
        end

        if (tr.enable)
            expected_wy = {expected_wy[WIDTH-2:0],
                           expected_wy[WIDTH-1]};

        checked++;

    endfunction

    function void report();
        $display("cycles checked: %0d", checked);
        $display("errors: %0d", errors);
    endfunction

endclass


// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class RingCounterMonitor #(parameter int WIDTH = 4);

    virtual ring_counter_if #(WIDTH) vif;
    RingCounterScoreboard #(WIDTH) sb;

    function new(
        virtual ring_counter_if #(WIDTH) vif,
        RingCounterScoreboard #(WIDTH) sb
    );
        this.vif = vif;
        this.sb = sb;
    endfunction

    task run();
        RingCounterTxn #(WIDTH) tr;

        forever begin
            @(vif.mon_cb);

            if (!vif.mon_cb.rst_n) begin
                sb.expected_wy = {{(WIDTH-1){1'b0}}, 1'b1};
            end
            else begin
                tr = new();
                tr.enable = vif.mon_cb.enable;
                tr.Wy = vif.mon_cb.Wy;
                sb.check(tr);
            end
        end
    endtask

endclass


// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class RingCounterDriver #(parameter int WIDTH = 4);

    virtual ring_counter_if #(WIDTH) vif;

    function new(virtual ring_counter_if #(WIDTH) vif);
        this.vif = vif;
    endfunction

    task drive(RingCounterTxn #(WIDTH) tr);
        @(negedge vif.clk);
        vif.enable <= tr.enable;
    endtask

endclass


// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class RingCounterGenerator #(parameter int WIDTH = 4);

    RingCounterDriver #(WIDTH) drv;
    int num_txn;

    function new(RingCounterDriver #(WIDTH) drv, int num_txn);
        this.drv = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        RingCounterTxn #(WIDTH) tr;

        repeat (num_txn) begin
            tr = new();

            if (!tr.randomize())
                $fatal(1, "Randomization failed");

            drv.drive(tr);
        end
    endtask

endclass


// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class RingCounterEnvironment #(parameter int WIDTH = 4);

    RingCounterGenerator  #(WIDTH) gen;
    RingCounterDriver     #(WIDTH) drv;
    RingCounterMonitor    #(WIDTH) mon;
    RingCounterScoreboard #(WIDTH) sb;

    virtual ring_counter_if #(WIDTH) vif;

    function new(
        virtual ring_counter_if #(WIDTH) vif,
        int num_txn = 200
    );
        this.vif = vif;

        sb = new();
        drv = new(vif);
        mon = new(vif, sb);
        gen = new(drv, num_txn);
    endfunction

    task run();
        fork
            mon.run();
        join_none

        gen.run();

        repeat (2) @(negedge vif.clk);
        #1;

        sb.report();

        if (sb.errors != 0)
            $fatal(1, "TEST FAILED");
        else
            $display("TEST PASSED");
    endtask

endclass


// ---------------------------------------------------------------------------
// Top
// ---------------------------------------------------------------------------
module tb_ring_counter;

    localparam int WIDTH = 4;

    logic clk = 1'b0;

    always #5 clk = ~clk;

    ring_counter_if #(WIDTH) vif(clk);

    ring_counter #(
        .WIDTH(WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(vif.rst_n),
        .enable(vif.enable),
        .Wy(vif.Wy)
    );

    RingCounterEnvironment #(WIDTH) env;

    initial begin
        $dumpfile("ring_counter.vcd");
        $dumpvars(0, tb_ring_counter);
    end

    initial begin
        vif.rst_n = 1'b0;
        vif.enable = 1'b0;

        repeat (2) @(negedge clk);
        vif.rst_n = 1'b1;

        env = new(vif);
        env.run();

        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "Timeout");
    end

endmodule //The last line must be empty so VS Code doesn't throw an error.

