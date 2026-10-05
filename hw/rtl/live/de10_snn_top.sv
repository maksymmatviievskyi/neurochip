// DE10-Lite live gesture classifier: ADXL345 -> trigger/window -> delta encoder -> snn -> class.
//   KEY0        reset (reloads the network from ROM, ~0.1 ms)
//   HEX0        last class:  -  idle   L  light tap   H  hard tap   d  double tap   S  shake
//   HEX1        number of windows classified (mod 16) -- changes every time a gesture is detected
//   LEDR4..0    last class, one-hot           LEDR6  network loaded
//   LEDR7       accelerometer timer fallback  LEDR8  blinks while samples arrive   LEDR9  window in progress
//   SW0 up      HEX1..HEX0 show the ADXL345 device ID (must be E5)
module de10_snn_top (
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

    logic [2:0] rst_sync;
    logic       reset;
    always_ff @(posedge clk) rst_sync <= {rst_sync[1:0], ~KEY[0]};
    assign reset = rst_sync[2];

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

    // ---------------- classifier ----------------
    logic        loaded, busy, cls_valid;
    logic [2:0]  cls;
    logic [71:0] counts;
    logic [31:0] wstart;
    snn_live #(.ROM_FILE("load.hex")) live (
        .clk(clk), .reset(reset), .sample_valid(valid), .x(x), .y(y), .z(z),
        .loaded(loaded), .busy(busy), .cls(cls), .cls_valid(cls_valid),
        .counts_flat(counts), .win_start(wstart)
    );

    // ---------------- display ----------------
    logic [3:0] n_win;
    logic       any;
    always_ff @(posedge clk) begin
        if (reset) begin n_win <= '0; any <= 1'b0; end
        else if (cls_valid) begin n_win <= n_win + 1'b1; any <= 1'b1; end
    end

    logic [8:0] blink;
    always_ff @(posedge clk) if (reset) blink <= '0; else if (valid) blink <= blink + 1'b1;

    logic [4:0] onehot;
    assign onehot = any ? (5'b1 << cls) : 5'b0;
    assign LEDR = {busy, blink[8], timer_mode, loaded, 1'b0, onehot};

    logic [7:0] letter, h1, h0, id1, id0;
    always_comb begin                                   // active low {dp, g, f, e, d, c, b, a}
        case (cls)
            3'd0:    letter = 8'hBF;                    // -  idle
            3'd1:    letter = 8'hC7;                    // L  light tap
            3'd2:    letter = 8'h89;                    // H  hard tap
            3'd3:    letter = 8'hA1;                    // d  double tap
            3'd4:    letter = 8'h92;                    // S  shake
            default: letter = 8'hFF;
        endcase
    end
    hex7 hw1 (.d(n_win), .seg(h1));
    hex7 hd1 (.d(devid[7:4]), .seg(id1));
    hex7 hd0 (.d(devid[3:0]), .seg(id0));
    assign HEX1 = SW[0] ? id1 : h1;
    assign HEX0 = SW[0] ? id0 : (any ? letter : 8'hFF);
endmodule
