`timescale 1ns/1ps

import snn_pkg::*;

module lif_tb;

    logic clk;
    logic reset;
    logic signed [I_W-1:0] I [0:MAX_NEURONS-1];
    logic [LEAK_SHIFT_W-1:0]       decay_shift;
    logic signed [THRESHOLD_W-1:0] threshold;
    logic [MAX_NEURONS-1:0] spikes;

    lif dut (
        .clk         (clk),
        .reset       (reset),
        .I           (I),
        .decay_shift (decay_shift),
        .threshold   (threshold),
        .spikes      (spikes)
    );

    initial begin
        $dumpfile("lif_tb.vcd");
        $dumpvars(0, lif_tb);

        clk         = 0;
        reset       = 1;
        decay_shift = 4'd2;
        threshold   = 8'sd100;

        for (int i = 0; i < MAX_NEURONS; i++) I[i] = '0;

        #10;
        reset = 0;

        // Accumulation and spike test
        I[0] = 23'sd20;

        #190;

        // Remove input and test leakage
        I[0] = '0;

        #50;

        $finish;
    end

    always #5 clk = ~clk;

    always @(posedge clk) begin
        #1;
        $display("t=%0t I=%0d V=%0d spike=%b", $time, I[0], dut.V[0], spikes[0]);
    end

endmodule
