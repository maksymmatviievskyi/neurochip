`timescale 1ns/1ps
// Runs a trained network on the RTL and checks it against the Python integer model.
// Inputs come from snn/export.py (files in tb/acc/data/). For every example:
//   reset (clears membrane potentials), then T timesteps: drive spikesIn, pulse init, wait snn_done,
//   count output spikes per output neuron. Counts must equal the integer model's exactly.
//
//   cd hw && iverilog -g2012 -o infer.vvp rtl/common/snn_pkg.sv rtl/acc/mem/config_mem.sv \
//     rtl/acc/mem/conn_mem.sv rtl/acc/mem/meta_mem.sv rtl/acc/engine/*.sv tb/acc/snn_infer_tb.sv && vvp infer.vvp
import snn_pkg::*;

module snn_infer_tb;
    localparam string DIR = "tb/acc/data/";
    localparam int MAX_EX = 512, MAX_T = 256, MAX_OUT = 8;

    logic clk = 0, reset = 1, init = 0;
    always #10 clk = ~clk;

    logic [MAX_NEURONS-1:0] spikesIn = '0, spikesOut;
    logic snn_done;
    logic [LAYER_ADDR_W:0] num_layers;

    logic config_wen = 0, neuron_meta_wen = 0, layer_meta_wen = 0, conn_wen = 0;
    logic [LAYER_ADDR_W-1:0] config_waddr, layer_meta_waddr;
    logic [THRESHOLD_W-1:0] config_wthreshold, config_wreset;
    logic [LEAK_SHIFT_W-1:0] config_wdecay;
    logic [LAYER_ADDR_W:0] config_wnum_layers;
    logic [NEURON_ADDR_W-1:0] neuron_meta_waddr, layer_meta_wstart;
    logic [CONN_ADDR_W-1:0] neuron_meta_wstart, conn_waddr;
    logic [CONN_ADDR_W:0] neuron_meta_wcount;
    logic [NEURON_ADDR_W:0] layer_meta_wcount;
    logic [CONN_W-1:0] conn_wdata;

    snn dut (.*, .config_raddr('0));

    logic [31:0]  params   [0:5];
    logic [63:0]  layers   [0:MAX_LAYERS-1];
    logic [24:0]  nmeta    [0:MAX_NEURONS-1];
    logic [29:0]  conn     [0:MAX_CONNECTIONS-1];
    logic [127:0] stim     [0:MAX_EX*MAX_T-1];
    logic [79:0]  expected [0:MAX_EX-1];

    int n_layers, n_conn, n_ex, T, n_out, out_start;
    int errors = 0, correct_pred = 0;
    longint total_cycles = 0, cycles, steps = 0;
    int counts [0:MAX_OUT-1];

    task automatic load();
        for (int l = 0; l < n_layers; l++) begin
            @(negedge clk);
            config_wen = 1; config_waddr = l; config_wnum_layers = n_layers;
            config_wthreshold = layers[l][43:28]; config_wdecay = layers[l][27:24]; config_wreset = layers[l][23:8];
            layer_meta_wen = 1; layer_meta_waddr = l;
            layer_meta_wstart = layers[l][59:52]; layer_meta_wcount = layers[l][51:44];
        end
        @(negedge clk) config_wen = 0; layer_meta_wen = 0;
        for (int n = 0; n < MAX_NEURONS; n++) begin
            @(negedge clk);
            neuron_meta_wen = 1; neuron_meta_waddr = n;
            neuron_meta_wstart = nmeta[n][24:13]; neuron_meta_wcount = nmeta[n][12:0];
        end
        @(negedge clk) neuron_meta_wen = 0;
        for (int c = 0; c < n_conn; c++) begin
            @(negedge clk);
            conn_wen = 1; conn_waddr = c; conn_wdata = conn[c];
        end
        @(negedge clk) conn_wen = 0;
    endtask

    initial begin
        $readmemh({DIR, "params.hex"}, params);
        n_layers = params[0]; n_conn = params[1]; n_ex = params[2]; T = params[3];
        n_out = params[4]; out_start = params[5];
        $readmemh({DIR, "layers.hex"}, layers);
        $readmemh({DIR, "nmeta.hex"}, nmeta);
        $readmemh({DIR, "conn.hex"}, conn);
        $readmemh({DIR, "stim.hex"}, stim);
        $readmemh({DIR, "expected.hex"}, expected);
        $display("snn_infer_tb: %0d layers, %0d connections, %0d examples x %0d timesteps", n_layers, n_conn, n_ex, T);

        repeat (3) @(negedge clk); reset = 0;
        load();

        for (int e = 0; e < n_ex; e++) begin
            int bad, best;
            @(negedge clk) reset = 1;                       // new example: clear membrane potentials
            @(negedge clk) reset = 0;
            wait (dut.lif_cleared); @(negedge clk);
            for (int c = 0; c < n_out; c++) counts[c] = 0;
            for (int t = 0; t < T; t++) begin
                spikesIn = stim[e * T + t];
                init = 1; @(negedge clk); init = 0;
                cycles = 1;
                while (!snn_done) begin @(negedge clk); cycles++; end
                total_cycles += cycles; steps++;
                @(negedge clk);
                for (int c = 0; c < n_out; c++) counts[c] += spikesOut[out_start + c];
            end
            bad = 0; best = 0;
            for (int c = 0; c < n_out; c++) begin
                if (counts[c] != expected[e][16*c +: 16]) bad++;
                if (counts[c] > counts[best]) best = c;
            end
            if (bad) begin
                errors++;
                $write("  FAIL example %0d: rtl counts", e);
                for (int c = 0; c < n_out; c++) $write(" %0d", counts[c]);
                $write("  expected");
                for (int c = 0; c < n_out; c++) $write(" %0d", expected[e][16*c +: 16]);
                $display("");
            end
        end
        $display("snn_infer_tb: %0d/%0d examples bit-exact with the integer model, avg %0.1f cycles/timestep (%0.2f us at 50 MHz)",
                 n_ex - errors, n_ex, real'(total_cycles) / steps, real'(total_cycles) / steps / 50.0);
        if (errors == 0) $display("snn_infer_tb: PASS"); else $display("snn_infer_tb: FAIL");
        $finish;
    end
endmodule
