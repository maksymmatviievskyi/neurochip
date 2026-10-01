module pc(
    input logic clk,
    input logic reset,
    input logic [31:0] pcx,
    output logic [31:0] pcq
);

always_ff @(posedge clk) begin
    if(reset)
        pcq<='0;
    else
        pcq<=pcx;
end

endmodule
