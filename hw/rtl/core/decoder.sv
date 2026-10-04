module decoder (
    input logic [31:0] ins,

    output logic [4:0] rs1,
    output logic [4:0] rs2,
    output logic [4:0] rd,

    output logic [2:0] alu_opcode,
    output logic       wen
);

import cpu_pkg::*;

logic [6:0] funct7;
logic [2:0] funct3;
logic [6:0] opcode;

assign funct7 = ins[31:25];
assign rs2    = ins[24:20];
assign rs1    = ins[19:15];
assign funct3 = ins[14:12];
assign rd     = ins[11:7];
assign opcode = ins[6:0];

always_comb begin
    alu_opcode = cpu_pkg::ALU_ADD;
    wen = 1'b0;

    if (opcode == 7'b0110011) begin
        case (funct3)

            3'b000: begin
                if (funct7 == 7'b0000000) begin
                    alu_opcode = cpu_pkg::ALU_ADD;
                    wen = 1'b1;
                end
                else if (funct7 == 7'b0100000) begin
                    alu_opcode = cpu_pkg::ALU_SUB;
                    wen = 1'b1;
                end
            end

            3'b111: begin
                if (funct7 == 7'b0000000) begin
                    alu_opcode = cpu_pkg::ALU_AND;
                    wen = 1'b1;
                end
            end

            3'b110: begin
                if (funct7 == 7'b0000000) begin
                    alu_opcode = cpu_pkg::ALU_OR;
                    wen = 1'b1;
                end
            end

            3'b100: begin
                if (funct7 == 7'b0000000) begin
                    alu_opcode = cpu_pkg::ALU_XOR;
                    wen = 1'b1;
                end
            end

            default: begin
                wen = 1'b0;
            end

        endcase
    end
end

endmodule