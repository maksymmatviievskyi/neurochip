// DE10-Lite accelerometer recorder.
//   KEY0          reset: clears the RAM, reconfigures the sensor, window count -> 0
//   KEY1          record one window (2.56 s) starting 300 ms after the button is released
//   HEX1..HEX0    windows recorded (00..16); with SW0 up: ADXL345 device ID (must read E5)
//   LEDR0         recording        LEDR1  settling (do the gesture once LEDR0 lights)
//   LEDR7         timer fallback (INT1 not seen)   LEDR8  blinks ~1 Hz while samples arrive
//   LEDR9         memory full (16 windows) -> read out with the In-System Memory Content Editor
module de10_recorder_top (
    input  logic       MAX10_CLK1_50,
    input  logic [1:0] KEY,
    input  logic [9:0] SW,
    output logic [9:0] LEDR,
    output logic [7:0] HEX0, HEX1,
    output logic       GSENSOR_CS_N,
    output logic       GSENSOR_SCLK,
    inout  wire        GSENSOR_SDI,
    input  logic [2:1] GSENSOR_INT
);
    logic clk;
    assign clk = MAX10_CLK1_50;

    // ---------------- reset and button ----------------
    logic [2:0] rst_sync;
    logic       reset;
    always_ff @(posedge clk) rst_sync <= {rst_sync[1:0], ~KEY[0]};
    assign reset = rst_sync[2];

    logic [2:0]  k1_sync;
    logic        k1_stable, k1_prev;
    logic [19:0] k1_cnt;                                   // ~20 ms debounce
    logic        rec_req;
    always_ff @(posedge clk) begin
        k1_sync <= {k1_sync[1:0], KEY[1]};                 // KEY is active low: 1 = released
        if (reset) begin
            k1_stable <= 1'b1; k1_prev <= 1'b1; k1_cnt <= '0;
        end else begin
            if (k1_sync[2] != k1_stable) begin
                k1_cnt <= k1_cnt + 1'b1;
                if (&k1_cnt) k1_stable <= k1_sync[2];
            end else k1_cnt <= '0;
            k1_prev <= k1_stable;
        end
    end
    assign rec_req = k1_stable && !k1_prev;                // release edge

    logic [1:0] int_sync;
    always_ff @(posedge clk) int_sync <= {int_sync[0], GSENSOR_INT[1]};

    // ---------------- sensor ----------------
    logic signed [15:0] x, y, z;
    logic        valid, timer_mode, sdo, sdo_oe;
    logic [7:0]  devid;
    adxl345_ctrl sensor (
        .clk(clk), .reset(reset), .int1(int_sync[1]), .x(x), .y(y), .z(z), .valid(valid),
        .devid(devid), .timer_mode(timer_mode),
        .cs_n(GSENSOR_CS_N), .sclk(GSENSOR_SCLK), .sdo(sdo), .sdo_oe(sdo_oe), .sdi(GSENSOR_SDI)
    );
    assign GSENSOR_SDI = sdo_oe ? sdo : 1'bz;

    // ---------------- recorder ----------------
    logic [4:0] windows;
    logic       settling, recording, full;
    logic [47:0] q;
    recorder rec (
        .clk(clk), .reset(reset), .rec_req(rec_req), .x(x), .y(y), .z(z), .valid(valid),
        .windows(windows), .settling(settling), .recording(recording), .full(full), .q(q)
    );

    // ---------------- status ----------------
    logic [8:0] blink;
    always_ff @(posedge clk) if (reset) blink <= '0; else if (valid) blink <= blink + 1'b1;

    // LEDR2 = parity of the RAM output: meaningless, but gives the RAM a fan-out so synthesis keeps it
    assign LEDR = {full, blink[8], timer_mode, 4'b0, ^q, settling, recording};

    logic [3:0] tens, ones;
    always_comb begin
        if (SW[0]) begin
            tens = devid[7:4]; ones = devid[3:0];
        end else begin
            tens = (windows >= 5'd10) ? 4'd1 : 4'd0;
            ones = (windows >= 5'd10) ? 4'(windows - 5'd10) : windows[3:0];
        end
    end
    hex7 h1 (.d(tens), .seg(HEX1));
    hex7 h0 (.d(ones), .seg(HEX0));
endmodule
