module BCD #(
    parameter WIDTH = 4
)(
    input logic clk,
    input logic rst_n,
    input logic enable,
    output logic [WIDTH-1:0] Wy
);

always_ff@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        Wy <= '0;
    end
    else
    begin
        if(enable)
        begin
            if(Wy >= 'd9)
            begin
                Wy <= '0;
            end
            else
            begin
                Wy <= Wy + 1;
            end
        end
    end
end
endmodule
