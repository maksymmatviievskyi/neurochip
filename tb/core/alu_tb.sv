module alu_tb;

logic [31:0] a;
logic [31:0] b;
logic [2:0] opcode;
logic [31:0] res;
logic flgz;

alu dut (
    .a(a),
    .b(b),
    .opcode(opcode),
    .res(res),
    .flgz(flgz)
);

initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, alu_tb);

    a = 32'd10;
    b = 32'd3;
    opcode = 3'b000;

    #10;

    a = 32'd10;
    b = 32'd3;
    opcode = 3'b001;

    #10;

    a = 32'b0101;
    b = 32'b0011;
    opcode = 3'b010;

    #10;

    a = 32'b0101;
    b = 32'b0011;
    opcode = 3'b011;

    #10;

    a = 32'b0101;
    b = 32'b0011;
    opcode = 3'b100;
    
    #10;
    $finish;
end
    
endmodule