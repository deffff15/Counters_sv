`timescale 1ns/1ps
package Paczka;
typedef enum logic [1:0]{
    START = 2'b00,
    FIRST = 2'b01,
    END_POSITIVE = 2'b10,
    END_NEGATIVE = 2'b11
}Stany;
endpackage
import Paczka::*;
module One_hot (
    input logic clk,
    input logic rst_n,
    input logic enable,
    input logic error_maker,
    output logic [3:0] Hot_Wy
);

Stany current_s, next_s;

always_ff@(posedge clk or negedge rst_n) begin
    if(!rst_n)
    begin
        current_s <= START;
    end
    else
    begin
        if(enable)
        begin
            current_s <= next_s;
        end
    end
end

always_comb begin
    next_s = current_s;
    Hot_Wy = 4'b0000;
    unique case(current_s)
        START: begin
            Hot_Wy = 4'b0001;
            next_s = FIRST;
        end
        FIRST: begin
            Hot_Wy = 4'b0010;
            if(error_maker)
            begin
                next_s = END_NEGATIVE;
            end
            else
            begin
                next_s = END_POSITIVE;
            end
        end
        END_POSITIVE: begin
            Hot_Wy = 4'b0100;
            next_s = START;
        end
        END_NEGATIVE: begin
            Hot_Wy = 4'b1000;
            next_s = START;
        end
    endcase
end
endmodule 
