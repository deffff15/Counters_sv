`timescale 1ns/1ps
module LFSR #(
    parameter WIDTH = 4
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic             enable,
    output logic [WIDTH-1:0] Wy
);

    logic bit_in; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            Wy <= '1; 
        end else begin
            if (enable) begin
                Wy <= {Wy[WIDTH-2:0], bit_in};
            end
        end
    end

    assign bit_in = Wy[WIDTH-1] ^ Wy[WIDTH-2];

endmodule
