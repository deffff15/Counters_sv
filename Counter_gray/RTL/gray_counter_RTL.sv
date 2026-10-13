`timescale 1ns/1ps
module gray_counter #(parameter WIDTH = 4) (
    input logic clk,
    input logic rst_n,
    input logic enable,
    output logic [WIDTH-1:0] Wy
);

    logic [WIDTH-1:0] Wy_pos;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            Wy_pos <= '0;
        else
        if(enable)
        begin
            Wy_pos <= Wy_pos + 1;
        end
    end

    assign Wy = (Wy_pos >> 1) ^ Wy_pos;
endmodule
