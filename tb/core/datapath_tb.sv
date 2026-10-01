module datapath_tb;

timeunit 1ns;
timeprecision 1ps;

logic clk;
logic [31:0] ins;

datapath dut (
    .clk(clk),
    .ins(ins)
);

always #5 clk = ~clk;

task automatic run_cpu(
    input logic [31:0] instruction,
    input logic [4:0] expected_rd,
    input logic [31:0] expected
);
    ins = instruction;

    @(posedge clk);
    #1;

    if (dut.regfile1.regs[expected_rd] == expected)
        $display("PASS: x%0d = %0d", expected_rd, expected);
    else
        $display(
            "FAIL: x%0d = %0d, expected = %0d",
            expected_rd,
            dut.regfile1.regs[expected_rd],
            expected
        );
endtask


initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, datapath_tb);

    clk = 0;
    ins = 32'b0;

    dut.regfile1.regs[1] = 32'd10;
    dut.regfile1.regs[2] = 32'd20;

    run_cpu({7'b0000000, 5'd1, 5'd2, 3'b000, 5'd3, 7'b0110011}, 5'd3,
    32'd30 );

    $finish;
end

endmodule