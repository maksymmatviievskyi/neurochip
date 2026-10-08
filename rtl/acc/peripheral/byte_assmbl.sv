module byte_assmbl(
    input logic done,
    input logic clk,
    input logic reset,
    input logic init,
    input logic [7:0] rx_byte,
    output logic sample_valid,
    output logic [47:0] data
);

logic [2:0] c;

always_ff @(posedge clk) begin
    if(reset) begin 
        c <= 0;
        sample_valid <= 0;
    end else begin
        sample_valid <= 0;
        if(init) c <= 0;
        else begin
            if(done && !init) begin
                c <= c+1;

                data[8*c +: 8] <= rx_byte;

                if(c==5) begin 
                    sample_valid <= 1;
                    c <= 0;
                end
            end
        end
    end
end


endmodule