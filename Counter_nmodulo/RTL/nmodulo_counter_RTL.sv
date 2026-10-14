`timescale 1ns/1ps
module nmodule_counter#(parameter MODULO = 4)(
    input logic clk,
    input logic rst_n,
    input logic enable,
    output logic [$clog2(MODULO)-1:0] modulo_Wy
);

always_ff@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        modulo_Wy <= 0;
    end
    else
    begin
        if(enable)
        begin
            if(modulo_Wy == MODULO-1)
            begin
                modulo_Wy <= 0;
            end
            else
            begin
                modulo_Wy <= modulo_Wy + 1;
            end
        end
    end
end
endmodule
