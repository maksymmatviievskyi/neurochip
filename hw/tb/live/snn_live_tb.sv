`timescale 1ns/1ps
// Live pipeline testbench: whole recordings (1024 samples each) are streamed into snn_live as if
// from the accelerometer. Every window the hardware triggers on must start at the same sample and
// produce the same output spike counts as Python (data.hw_windows + data.encode + snn_int).
// Data from: snn/export.py --live recordings/*.mif   (files in tb/live/data/, weight ROM in syn/de10_snn/)
//
//   cd hw && iverilog -g2012 -o live.vvp rtl/common/snn_pkg.sv rtl/acc/mem/config_mem.sv \
//     rtl/acc/mem/conn_mem.sv rtl/acc/mem/meta_mem.sv rtl/acc/engine/*.sv rtl/live/*.sv \
//     tb/live/snn_live_tb.sv && vvp live.vvp
module snn_live_tb;
    localparam string DIR = "tb/live/data/";
    localparam int PERIOD = 500;                 // cycles between samples (real board: 125000)
    localparam int MAX_REC = 64, MAX_WIN = 256;

    logic clk = 0, reset = 1, sample_valid = 0;
    logic signed [15:0] x = 0, y = 0, z = 0;
    always #10 clk = ~clk;

    logic loaded, busy, cls_valid;
    logic [2:0] cls;
    logic [71:0] counts;
    logic [31:0] win_start;

    snn_live #(.ROM_FILE("syn/de10_snn/load.hex")) dut (
        .clk(clk), .reset(reset), .sample_valid(sample_valid), .x(x), .y(y), .z(z),
        .loaded(loaded), .busy(busy), .cls(cls), .cls_valid(cls_valid),
        .counts_flat(counts), .win_start(win_start)
    );

    logic [31:0]  params [0:1];
    logic [47:0]  raw    [0:MAX_REC*1024-1];
    logic [103:0] exp_w  [0:MAX_WIN-1];
    int n_rec, n_exp, next_exp = 0, cur_rec = 0, errors = 0, checked = 0;
    function automatic string cname(input logic [2:0] c);
        case (c) 0: return "idle"; 1: return "light_tap"; 2: return "hard_tap"; 3: return "double_tap";
                 default: return "shake"; endcase
    endfunction

    // compare every classified window with the next expected one
    always @(posedge clk) if (cls_valid) begin
        logic [103:0] e;
        e = exp_w[next_exp];
        if (next_exp >= n_exp || e[103:88] != cur_rec || e[87:72] != win_start[15:0] || e[71:0] != counts) begin
            errors++;
            $display("  FAIL rec %0d: hw window start %0d counts %h, expected rec %0d start %0d counts %h",
                     cur_rec, win_start, counts, e[103:88], e[87:72], e[71:0]);
        end else
            $display("  ok   rec %0d window @%0d -> %s", cur_rec, win_start, cname(cls));
        next_exp++; checked++;
    end

    initial begin
        $readmemh({DIR, "params.hex"}, params);
        n_rec = params[0]; n_exp = params[1];
        $readmemh({DIR, "raw.hex"}, raw);
        $readmemh({DIR, "expected.hex"}, exp_w);
        $display("snn_live_tb: %0d recordings, %0d expected windows", n_rec, n_exp);
        for (cur_rec = 0; cur_rec < n_rec; cur_rec++) begin
            @(negedge clk) reset = 1; repeat (3) @(negedge clk); reset = 0;   // fresh start per recording
            wait (loaded);
            for (int s = 0; s < 1024; s++) begin
                @(negedge clk);
                {x, y, z} = raw[cur_rec * 1024 + s];
                sample_valid = 1;
                @(negedge clk) sample_valid = 0;
                repeat (PERIOD - 2) @(negedge clk);
                // On the board a window is classified within ~6 samples. Here samples come 250x faster,
                // so pause the stream while classifying to keep the ring buffer from wrapping.
                while (dut.state >= dut.CLR_RST) @(negedge clk);
            end
            // let a window that ends inside the recording finish classifying
            while (busy && dut.state != dut.COLLECT) @(negedge clk);
            repeat (10) @(negedge clk);
        end
        if (next_exp != n_exp) begin
            errors++; $display("  FAIL: %0d windows classified, %0d expected", next_exp, n_exp);
        end
        $display("snn_live_tb: %0d windows checked, %0s", checked, errors ? "FAIL" : "PASS");
        $finish;
    end
endmodule
