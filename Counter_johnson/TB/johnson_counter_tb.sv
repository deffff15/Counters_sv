`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface licznik_if #(parameter int WIDTH = 4) (input logic clk);

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
class LicznikTxn #(parameter int WIDTH = 4);

    rand bit enable;

    logic [WIDTH-1:0] Wy;

    constraint c_ctrl {
        enable dist {1 := 80, 0 := 20};
    }

endclass


// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class LicznikScoreboard #(parameter int WIDTH = 4);

    logic [WIDTH-1:0] expected_wy = '0;

    int checked     = 0;
    int errors      = 0;
    int full_cycles = 0;

    function void check(LicznikTxn #(WIDTH) tr);
        bit ok = 1;

        if (tr.Wy !== expected_wy) begin
            $error("[SB] Wy mismatch @ %0t: got %0b, expected %0b",
                   $time, tr.Wy, expected_wy);
            ok = 0;
        end

        if (tr.enable) begin
            expected_wy = {expected_wy[WIDTH-2:0], ~expected_wy[WIDTH-1]};
            if (expected_wy == '0) full_cycles++;
        end

        checked++;
        if (!ok) errors++;
    endfunction

    function void report();
        $display("---------------- scoreboard ----------------");
        $display("cycles checked : %0d", checked);
        $display("errors         : %0d", errors);
        $display("full cycles    : %0d", full_cycles);
        $display("--------------------------------------------");

        if (full_cycles == 0)
            $warning("[SB] no full Johnson cycle completed, run more cycles");
    endfunction

endclass


// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class LicznikMonitor #(parameter int WIDTH = 4);

    virtual licznik_if #(WIDTH) vif;
    LicznikScoreboard  #(WIDTH) sb;

    function new(virtual licznik_if #(WIDTH) vif,
                 LicznikScoreboard #(WIDTH) sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        LicznikTxn #(WIDTH) tr;

        forever begin
            @(vif.mon_cb);

            tr        = new();
            tr.enable = vif.mon_cb.enable;
            tr.Wy     = vif.mon_cb.Wy;

            sb.check(tr);
        end
    endtask

endclass


// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class LicznikDriver #(parameter int WIDTH = 4);

    virtual licznik_if #(WIDTH) vif;

    function new(virtual licznik_if #(WIDTH) vif);
        this.vif = vif;
    endfunction

    task drive(LicznikTxn #(WIDTH) tr);
        @(negedge vif.clk);
        vif.enable <= tr.enable;
    endtask

endclass


// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class LicznikGenerator #(parameter int WIDTH = 4);

    LicznikDriver #(WIDTH) drv;
    int                    num_txn;

    function new(LicznikDriver #(WIDTH) drv, int num_txn);
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        LicznikTxn #(WIDTH) tr;

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
class LicznikEnvironment #(parameter int WIDTH = 4);

    LicznikGenerator  #(WIDTH) gen;
    LicznikDriver     #(WIDTH) drv;
    LicznikMonitor    #(WIDTH) mon;
    LicznikScoreboard #(WIDTH) sb;

    virtual licznik_if #(WIDTH) vif;

    function new(virtual licznik_if #(WIDTH) vif, int num_txn = 200);
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
module tb_Licznik_Johnson;

    localparam int WIDTH = 4;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    licznik_if #(WIDTH) vif (clk);

    JohnsonCounter #(.WIDTH(WIDTH)) dut (
        .clk    (clk),
        .rst_n  (vif.rst_n),
        .enable (vif.enable),
        .Wy     (vif.Wy)
    );

    LicznikEnvironment #(WIDTH) env;

    initial begin
        $dumpfile("Counter_johnson_waveform.vcd");
        $dumpvars(0, tb_Licznik_Johnson);
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

