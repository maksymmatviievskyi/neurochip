module datapath (
    input logic       clk,
    input logic [31:0] ins
);

logic [31:0] dat1;
logic [31:0] dat2;
logic [31:0] res;

logic [4:0] rs1;
logic [4:0] rs2;
logic [4:0] rd;
logic [2:0] alu_opcode;
logic       wen;
logic       flgz;

decoder decoder(
    .ins(ins), 
    .rs1(rs1), 
    .rs2(rs2),
    .rd(rd),
    .alu_opcode(alu_opcode),
    .wen(wen)
);

regfile regfile1(
    .clk(clk),
    .wen(wen),
    .ad1(rs1),
    .ad2(rs2),
    .wrt(rd),
    .din(res),
    .out1(dat1),
    .out2(dat2)
);

alu alu1 (
    .a(dat1),
    .b(dat2),
    .opcode(alu_opcode),
    .res(res),
    .flgz(flgz)
);


endmodule