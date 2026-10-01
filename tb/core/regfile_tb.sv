module regfile_tb;

timeunit 1ns;
timeprecision 1ps;

logic clk;
logic wen;
logic [4:0] ad1;
logic [4:0] ad2;
logic [4:0] wrt;
logic [31:0] din;
logic [31:0] out1;
logic [31:0] out2;

regfile dut(
    .clk(clk),
    .wen(wen),
    .ad1(ad1),
    .ad2(ad2),
    .wrt(wrt),
    .din(din),
    .out1(out1),
    .out2(out2)
    );

initial begin
    
    $dumpfile("dump.vcd");
    $dumpvars(0, dut);

    clk = 0;
wen = 0;
ad1 = 5'd12;
ad2 = 5'd13;
wrt = 5'd0;
din = 32'd0;

    #10;

    wen = '1;
    wrt = 5'd1;
    din = 32'd14;

    #10;

    ad1 = 5'd1;
ad2 = 5'd1;

#10;

    $finish;
end

always #5 clk = ~clk;


endmodule