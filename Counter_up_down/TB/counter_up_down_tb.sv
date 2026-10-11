`timescale 1ns/1ps
// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface licznik_if #(parameter int WIDTH = 4) (input logic clk);
 
    logic             rst_n;
    logic             enable;
    logic             up;
    logic [WIDTH-1:0] Wy;
    logic             max_tick;
    logic             min_tick;
 
    clocking mon_cb @(posedge clk);
        default input #1step;
        input enable, up, Wy, max_tick, min_tick;
    endclocking
 
endinterface
 
 
// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class LicznikTxn #(parameter int WIDTH = 4);
 
    rand bit enable;
    rand bit up;
 
    logic [WIDTH-1:0] Wy;
    logic             max_tick;
    logic             min_tick;
 
    constraint c_ctrl {
        enable dist {1 := 80, 0 := 20};
        up     dist {1 := 50, 0 := 50};
    }
 
endclass
 
 
// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class LicznikScoreboard #(parameter int WIDTH = 4);
 
    logic [WIDTH-1:0] expected_wy = '0;
 
    int checked    = 0;
    int errors     = 0;
    int wrap_up    = 0;
    int wrap_down  = 0;
 
    function void check(LicznikTxn #(WIDTH) tr);
        bit exp_max, exp_min;
        bit ok = 1;
 
        if (tr.Wy !== expected_wy) begin
            $error("[SB] Wy mismatch @ %0t: got %0h, expected %0h",
                   $time, tr.Wy, expected_wy);
            ok = 0;
        end
 
        exp_max = (expected_wy == {WIDTH{1'b1}}) && tr.enable && tr.up;
        exp_min = (expected_wy == '0)            && tr.enable && !tr.up;
 
        if (tr.max_tick !== exp_max) begin
            $error("[SB] max_tick mismatch @ %0t: got %0b, expected %0b",
                   $time, tr.max_tick, exp_max);
            ok = 0;
        end
 
        if (tr.min_tick !== exp_min) begin
            $error("[SB] min_tick mismatch @ %0t: got %0b, expected %0b",
                   $time, tr.min_tick, exp_min);
            ok = 0;
        end
 
        if (tr.enable)
            expected_wy = tr.up ? expected_wy + 1'b1 : expected_wy - 1'b1;
 
        if (exp_max) wrap_up++;
        if (exp_min) wrap_down++;
 
        checked++;
        if (!ok) errors++;
    endfunction
 
    function void report();
        $display("---------------- scoreboard ----------------");
        $display("cycles checked : %0d", checked);
        $display("errors         : %0d", errors);
        $display("wrap up/down   : %0d / %0d", wrap_up, wrap_down);
        $display("--------------------------------------------");
 
        if (wrap_up == 0 || wrap_down == 0)
            $warning("[SB] wrap-around not covered in both directions, run more cycles");
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
 
            tr          = new();
            tr.enable   = vif.mon_cb.enable;
            tr.up       = vif.mon_cb.up;
            tr.Wy       = vif.mon_cb.Wy;
            tr.max_tick = vif.mon_cb.max_tick;
            tr.min_tick = vif.mon_cb.min_tick;
 
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
        vif.up     <= tr.up;
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
module tb_Licznik;
 
    localparam int WIDTH = 4;
 
    logic clk = 1'b0;
    always #5 clk = ~clk;
 
    licznik_if #(WIDTH) vif (clk);
 
    Licznik #(.WIDTH(WIDTH)) dut (
        .clk      (clk),
        .rst_n    (vif.rst_n),
        .enable   (vif.enable),
        .up       (vif.up),
        .Wy       (vif.Wy),
        .max_tick (vif.max_tick),
        .min_tick (vif.min_tick)
    );
 
    LicznikEnvironment #(WIDTH) env;
 
    initial begin
        $dumpfile("licznik.vcd");
        $dumpvars(0, tb_Licznik);
    end
 
    initial begin
        vif.rst_n  = 1'b0;
        vif.enable = 1'b0;
        vif.up     = 1'b0;
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

