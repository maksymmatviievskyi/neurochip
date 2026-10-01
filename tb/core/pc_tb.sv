module pc_tb;

logic clk;
logic reset;
logic [31:0] pcx;
logic [31:0] pcq;

pc dut (
    .clk(clk),
    .reset(reset),
    .pcx(pcx),
    .pcq(pcq)
);

initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, pc_tb);

    clk = 0;
    reset = 1;
    pcx = 0;

    #10

    reset = 0;
    pcx = 32'd100;

    #10

    pcx = 32'd200;

    #10

    $finish;
end

always #5 clk = ~clk;

endmodule