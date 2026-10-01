module regfile (
    input  logic  clk,
    input  logic  wen, 
    input  logic [4:0] ad1,
    input  logic [4:0] ad2,
    input  logic [4:0] wrt,
    input  logic [31:0] din,
    output logic [31:0] out1,
    output logic [31:0] out2
);

logic [31:0] regs [0:31]; 

assign out1 = regs[ad1];
assign out2 = regs[ad2];

always_ff @(posedge clk) begin

    if(wen && wrt!=0)
        regs[wrt] <= din;
end
    
endmodule
