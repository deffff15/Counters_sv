`timescale 1ns/1ps
module counter_up_down #(
    parameter int WIDTH = 4 // we can change this parameter 
)(
    input  logic               clk,
    input  logic               rst_n,
    input  logic               enable,
    input  logic               up,
    output logic [WIDTH-1:0]   Wy,
    output logic               max_tick, 
    output logic               min_tick  
);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        Wy <= '0; 
    end else if (enable) begin
        if (up) begin
            Wy <= Wy + 1'b1;
        end else begin
            Wy <= Wy - 1'b1;
        end
    end
end

assign max_tick = (Wy == {WIDTH{1'b1}}) && enable && up;
assign min_tick = (Wy == '0) && enable && !up;

endmodule 

