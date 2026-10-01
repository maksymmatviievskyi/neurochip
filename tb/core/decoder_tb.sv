`timescale 1ns/1ps

module decoder_tb;

    import cpu_pkg::*;

    logic [31:0] ins;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rd;
    logic [2:0] alu_opcode;
    logic       wen;

    decoder dut (
        .ins(ins),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .alu_opcode(alu_opcode),
        .wen(wen)
    );

    task automatic check_instruction(
        input logic [31:0] instruction,
        input logic [2:0] expected_alu,
        input logic expected_wen,
        input logic [8*20-1:0] name
    );
        ins = instruction;
        #1;

        if (alu_opcode != expected_alu || wen != expected_wen) begin
            $error(
                "FAIL: %s | alu=%b expected=%b | wen=%b expected=%b",
                name, alu_opcode, expected_alu, wen, expected_wen
            );
        end
        else if (rs1 != 5'd9 || rs2 != 5'd17 || rd != 5'd24) begin
            $error(
                "FAIL: %s | rs1=%0d rs2=%0d rd=%0d",
                name, rs1, rs2, rd
            );
        end
        else begin
            $display("PASS: %s", name);
        end
    endtask

    initial begin
        $dumpfile("decoder.vcd");
        $dumpvars(0, decoder_tb);

        check_instruction(
            {7'b0100000, 5'd17, 5'd9, 3'b000, 5'd24, 7'b0110011},
            ALU_SUB,
            1'b1,
            "SUB"
        );

        check_instruction(
            {7'b0000000, 5'd17, 5'd9, 3'b000, 5'd24, 7'b0110011},
            ALU_ADD,
            1'b1,
            "ADD"
        );

        check_instruction(
            {7'b0000000, 5'd17, 5'd9, 3'b111, 5'd24, 7'b0110011},
            ALU_AND,
            1'b1,
            "AND"
        );

        check_instruction(
            {7'b0000000, 5'd17, 5'd9, 3'b110, 5'd24, 7'b0110011},
            ALU_OR,
            1'b1,
            "OR"
        );

        check_instruction(
            {7'b0000000, 5'd17, 5'd9, 3'b100, 5'd24, 7'b0110011},
            ALU_XOR,
            1'b1,
            "XOR"
        );

        check_instruction(
            {7'b1111111, 5'd17, 5'd9, 3'b000, 5'd24, 7'b0110011},
            ALU_ADD,
            1'b0,
            "INVALID"
        );

        $finish;
    end

endmodule