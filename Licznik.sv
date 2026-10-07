`timescale 1ns/1ps

module licznik #(
    parameter int WIDTH = 8
)(
    input  logic clk,
    input  logic rst_n,
    input  logic en,
    output logic [WIDTH-1:0] count
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= '0;
        else if (en)
            count <= count + 1'b1;
    end

endmodule

module tb_licznik;
    localparam int WIDTH = 4;

    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic en = 1'b0;
    logic [WIDTH-1:0] count;
    integer expected;

    licznik #(.WIDTH(WIDTH)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .count(count)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("licznik.vcd");
        $dumpvars(0, tb_licznik);

        #1 rst_n = 1'b0;
        #1;
        if (count !== '0)
            $fatal(1, "Reset failed: count=%0d, expected 0", count);

        @(negedge clk);
        rst_n = 1'b1;
        en = 1'b1;

        for (expected = 1; expected <= 16; expected = expected + 1) begin
            @(posedge clk);
            #1;
            if (count !== (expected % (1 << WIDTH)))
                $fatal(1, "Count mismatch: count=%0d, expected=%0d",
                       count, expected % (1 << WIDTH));
        end

        @(negedge clk);
        en = 1'b0;
        @(posedge clk);
        #1;
        if (count !== '0)
            $fatal(1, "Counter should hold at 0 when disabled, got %0d", count);

        $display("Test passed.");
        $finish;
    end
endmodule
