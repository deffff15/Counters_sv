`timescale 1ns/1ps
module ring_counter #(parameter WIDTH = 4)(
    input logic clk,
    input logic rst_n,
    input logic enable,
    output logic [WIDTH-1:0] Wy
);

always_ff@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        Wy <= {{(WIDTH-1){1'b0}}, 1'b1};
    end
    else
    begin
        if(enable)
        begin
            Wy <= {Wy[WIDTH-2:0], Wy[WIDTH-1]};
        end
    end
end
endmodule
