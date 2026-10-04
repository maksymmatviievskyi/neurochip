module alu(
    input logic [31:0] a, 
    input logic [31:0] b, 
    input logic [2:0] opcode,
    output logic [31:0] res,
    output logic flgz);

localparam [2:0] ADD =  3'b000;
localparam [2:0] SUB =  3'b001;
localparam [2:0] AND =  3'b010;
localparam [2:0] OR  =  3'b011;
localparam [2:0] XOR =  3'b100;

always_comb begin
    case (opcode)
        ADD: res = a+b;
        SUB: res = a-b;
        AND: res = a&b;
        OR: res = a|b;
        XOR: res = a^b;
        default: res = 0;
    endcase

    flgz = (res==0);
end

endmodule