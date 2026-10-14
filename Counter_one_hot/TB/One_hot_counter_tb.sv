`timescale 1ns/1ps
 
import Paczka::*;
 
// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface one_hot_if (input logic clk);
    logic       rst_n;
    logic       enable;
    logic       error_maker;
    logic [3:0] Hot_Wy;
 
    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, enable, error_maker, Hot_Wy;
    endclocking
endinterface
 
// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class OneHotTxn;
    rand bit rst_n;
    rand bit enable;
    rand bit error_maker;
 
    logic [3:0] Hot_Wy;
 
    constraint c_ctrl {
        rst_n       dist {1 := 95, 0 := 5};
        enable      dist {1 := 80, 0 := 20};
        error_maker dist {1 := 50, 0 := 50};
    }
endclass
 
// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class OneHotScoreboard;
    Stany state = START;
 
    int checked   = 0;
    int errors    = 0;
    int pos_paths = 0;
    int neg_paths = 0;
    int resets    = 0;
 
    function logic [3:0] hot_of(Stany s);
        case (s)
            START:        return 4'b0001;
            FIRST:        return 4'b0010;
            END_POSITIVE: return 4'b0100;
            END_NEGATIVE: return 4'b1000;
            default:      return 4'b0000;
        endcase
    endfunction
 
    function void check(OneHotTxn tr);
        bit ok = 1;
 
        if (!tr.rst_n) begin
            if (state != START) resets++;
            state = START;
        end
 
        if (tr.Hot_Wy !== hot_of(state)) begin
            $error("[SB] Hot_Wy mismatch @ %0t: got %04b, expected %04b (%s)",
                   $time, tr.Hot_Wy, hot_of(state), state.name());
            ok = 0;
        end
 
        if (tr.rst_n && tr.enable) begin
            case (state)
                START: state = FIRST;
                FIRST: begin
                    if (tr.error_maker) begin
                        state = END_NEGATIVE;
                        neg_paths++;
                    end
                    else begin
                        state = END_POSITIVE;
                        pos_paths++;
                    end
                end
                default: state = START;
            endcase
        end
 
        checked++;
        if (!ok) errors++;
    endfunction
 
    function void report();
        $display("---------------- scoreboard ----------------");
        $display("cycles checked      : %0d", checked);
        $display("errors              : %0d", errors);
        $display("FIRST -> POSITIVE   : %0d", pos_paths);
        $display("FIRST -> NEGATIVE   : %0d", neg_paths);
        $display("resets mid-sequence : %0d", resets);
        $display("--------------------------------------------");
 
        if (pos_paths == 0 || neg_paths == 0)
            $warning("[SB] not both end states were reached, run more cycles");
        if (resets == 0)
            $warning("[SB] asynchronous reset was never exercised mid-sequence");
    endfunction
endclass
 
// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class OneHotMonitor;
    virtual one_hot_if vif;
    OneHotScoreboard   sb;
 
    function new(virtual one_hot_if vif, OneHotScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction
 
    task run();
        OneHotTxn tr;
        forever begin
            @(vif.mon_cb);
            tr = new();
            tr.rst_n       = vif.mon_cb.rst_n;
            tr.enable      = vif.mon_cb.enable;
            tr.error_maker = vif.mon_cb.error_maker;
            tr.Hot_Wy      = vif.mon_cb.Hot_Wy;
            sb.check(tr);
        end
    endtask
endclass
 
// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class OneHotDriver;
    virtual one_hot_if vif;
 
    function new(virtual one_hot_if vif);
        this.vif = vif;
    endfunction
 
    task drive(OneHotTxn tr);
        @(negedge vif.clk);
        vif.rst_n       <= tr.rst_n;
        vif.enable      <= tr.enable;
        vif.error_maker <= tr.error_maker;
    endtask
endclass
 
// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class OneHotGenerator;
    OneHotDriver drv;
    int          num_txn;
 
    function new(OneHotDriver drv, int num_txn);
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction
 
    task run();
        OneHotTxn tr;
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
class OneHotEnvironment;
    OneHotGenerator  gen;
    OneHotDriver     drv;
    OneHotMonitor    mon;
    OneHotScoreboard sb;
 
    virtual one_hot_if vif;
 
    function new(virtual one_hot_if vif, int num_txn = 300);
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
module tb_One_hot;
 
    logic clk = 1'b0;
    always #5 clk = ~clk;
 
    one_hot_if vif (clk);
 
    One_hot dut (
        .clk         (clk),
        .rst_n       (vif.rst_n),
        .enable      (vif.enable),
        .error_maker (vif.error_maker),
        .Hot_Wy      (vif.Hot_Wy)
    );
 
    OneHotEnvironment env;
 
    initial begin
        $dumpfile("One_hot_waveform.vcd");
        $dumpvars(0, tb_One_hot);
    end
 
    initial begin
        vif.rst_n       = 1'b0;
        vif.enable      = 1'b0;
        vif.error_maker = 1'b0;
 
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

