`timescale 1ns/1ps
// Recorder testbench with a behavioural ADXL345 (3-wire SPI, DATA_READY on INT1).
// Checks: device ID, config order (3-wire before any read), and that a recorded window holds
// 1024 consecutive samples (no duplicates, none skipped). Timings scaled down.
// iverilog -g2012 -DSIM -o rec_tb.vvp ../../rtl/rec/*.sv recorder_tb.sv && vvp rec_tb.vvp
module adxl_model #(parameter real DR_NS = 20000.0) (
    input  logic cs_n, sclk,
    inout  wire  sdi,
    output logic int1,
    input  logic int_enable
);
    logic [7:0] regs [0:63];
    logic [7:0] cmd, wbyte;
    int bitcnt, sample, b, byten, raddr;
    logic drive, dval, measuring;
    assign sdi = drive ? dval : 1'bz;
    int errors = 0;

    initial begin
        for (int i = 0; i < 64; i++) regs[i] = 0;
        regs[0] = 8'hE5; int1 = 0; drive = 0; measuring = 0; sample = 0;
    end

    always @(negedge cs_n) begin bitcnt = 0; cmd = 0; end
    always @(posedge cs_n) begin
        drive = 0;
        if (cmd[7] && cmd[5:0] == 6'h32) int1 = 0;              // reading data clears DATA_READY
    end
    always @(posedge sclk) if (!cs_n) begin
        if (bitcnt < 8) cmd = {cmd[6:0], sdi};
        else if (!cmd[7]) begin
            wbyte = {wbyte[6:0], sdi};
            if (bitcnt == 15) begin
                regs[cmd[5:0]] = wbyte;
                if (cmd[5:0] == 6'h2D && wbyte[3]) measuring = 1;
            end
        end
        bitcnt++;
        if (bitcnt == 8 && cmd[7] && cmd[5:0] != 6'h31 && regs[8'h31][6] !== 1'b1) begin
            $display("FAIL: read before 3-wire mode was set"); errors++;
        end
    end
    always @(negedge sclk) if (!cs_n && bitcnt >= 8 && cmd[7]) begin
        b = bitcnt - 8;
        byten = b / 8;
        raddr = cmd[6] ? cmd[5:0] + byten : cmd[5:0];
        drive = 1;
        dval = regs[raddr][7 - (b % 8)];
    end

    // new sample every DR_NS: x = n, y = -n, z = 256 + n (little endian registers)
    always begin
        #(DR_NS);
        if (measuring) begin
            sample++;
            {regs[8'h33], regs[8'h32]} = 16'(sample);
            {regs[8'h35], regs[8'h34]} = 16'(-sample);
            {regs[8'h37], regs[8'h36]} = 16'(256 + sample);
            if (int_enable) int1 = 1;
        end
    end
endmodule

module recorder_tb;
    logic clk = 0, reset = 1, rec_req = 0, int_enable = 1;
    always #10 clk = ~clk;                                       // 50 MHz

    wire  sdi;
    logic cs_n, sclk, sdo, sdo_oe, int1, valid, timer_mode;
    logic signed [15:0] x, y, z;
    logic [7:0] devid;
    logic [4:0] windows;
    logic settling, recording, full;
    assign sdi = sdo_oe ? sdo : 1'bz;
    pullup (sdi);

    adxl_model #(.DR_NS(40000.0)) dev (.cs_n(cs_n), .sclk(sclk), .sdi(sdi), .int1(int1), .int_enable(int_enable));
    adxl345_ctrl #(.HALF(2), .BOOT_WAIT(50), .PERIOD(2000), .INT_WAIT(20000)) ctrl (
        .clk(clk), .reset(reset), .int1(int1), .x(x), .y(y), .z(z), .valid(valid), .devid(devid),
        .timer_mode(timer_mode), .cs_n(cs_n), .sclk(sclk), .sdo(sdo), .sdo_oe(sdo_oe), .sdi(sdi));
    recorder #(.SETTLE(100)) rec (
        .clk(clk), .reset(reset), .rec_req(rec_req), .x(x), .y(y), .z(z), .valid(valid),
        .windows(windows), .settling(settling), .recording(recording), .full(full));

    int errors = 0;

    task automatic record_window();
        @(negedge clk) rec_req = 1; @(negedge clk) rec_req = 0;
        wait (recording); wait (!recording);
    endtask

    task automatic check_window(input int w, input bit strict);
        logic [47:0] word;
        int bad = 0;
        for (int i = 0; i < 1024; i++) begin
            word = rec.mem[w * 1024 + i];
            if (word[15:0] !== 16'(256 + $signed(word[47:32])) || word[31:16] !== 16'(-$signed(word[47:32]))) bad++;
            if (strict && i > 0 && word[47:32] !== rec.mem[w * 1024 + i - 1][47:32] + 16'd1) bad++;
        end
        if (bad) begin $display("FAIL window %0d: %0d bad samples", w, bad); errors += bad; end
        else $display("ok   window %0d: first x=%0d last x=%0d", w, $signed(rec.mem[w*1024][47:32]),
                      $signed(rec.mem[w*1024+1023][47:32]));
    endtask

    initial begin
        repeat (5) @(negedge clk); reset = 0;
        wait (rec.state == rec.IDLE);
        wait (ctrl.state == ctrl.RUN);
        if (devid !== 8'hE5) begin $display("FAIL devid %h", devid); errors++; end
        else $display("ok   devid E5");
        record_window(); check_window(0, 1);
        record_window(); check_window(1, 1);
        if (rec.mem[2 * 1024] !== '0) begin $display("FAIL: window 2 not cleared"); errors++; end
        if (timer_mode) begin $display("FAIL: timer mode with INT1 working"); errors++; end
        if (windows !== 5'd2) begin $display("FAIL windows=%0d", windows); errors++; end

        // INT1 disconnected -> timer fallback must still record
        int_enable = 0;
        @(negedge clk) reset = 1; repeat (5) @(negedge clk); reset = 0;
        wait (rec.state == rec.IDLE); wait (ctrl.state == ctrl.RUN);
        record_window(); check_window(0, 0);
        if (!timer_mode) begin $display("FAIL: timer mode not entered"); errors++; end
        else $display("ok   timer fallback");

        if (errors == 0) $display("recorder_tb: PASS"); else $display("recorder_tb: FAIL (%0d)", errors);
        $finish;
    end
    initial begin #400ms; $display("recorder_tb: TIMEOUT"); $finish; end
endmodule
