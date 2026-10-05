// Configures the ADXL345 (3-wire SPI, full resolution +-16 g, 400 Hz, DATA_READY on INT1)
// and reads X/Y/Z whenever a new sample is ready.
module adxl345_ctrl #(
    parameter int HALF       = 25,          // SCLK half period (clk cycles)
    parameter int BOOT_WAIT  = 500_000,     // 10 ms after reset before configuring
    parameter int PERIOD     = 125_000,     // 2.5 ms = 400 Hz (timer fallback if INT1 never arrives)
    parameter int INT_WAIT   = 1_000_000    // 20 ms: no INT1 by then -> timer fallback
) (
    input  logic               clk,
    input  logic               reset,
    input  logic               int1,        // GSENSOR_INT[1], already synchronised
    output logic signed [15:0] x, y, z,
    output logic               valid,       // 1-cycle pulse per sample
    output logic [7:0]         devid,       // should read 0xE5
    output logic               timer_mode,  // 1 = INT1 never seen, sampling on the internal timer
    output logic               cs_n, sclk, sdo, sdo_oe,
    input  logic               sdi
);
    typedef enum logic [2:0] { BOOT, CFG, CFG_W, ID, ID_W, RUN, RD_W } state_t;
    state_t state;

    logic        start, rw, mb, done, busy;
    logic [5:0]  addr;
    logic [7:0]  wdata;
    logic [2:0]  nrd;
    logic [47:0] rdata;
    logic [2:0]  step;
    logic [$clog2(INT_WAIT+1)-1:0] t;
    logic        int_seen;

    adxl345_spi #(.HALF(HALF)) spi (
        .clk(clk), .reset(reset), .start(start), .rw(rw), .mb(mb), .addr(addr), .wdata(wdata),
        .nrd(nrd), .busy(busy), .done(done), .rdata(rdata),
        .cs_n(cs_n), .sclk(sclk), .sdo(sdo), .sdo_oe(sdo_oe), .sdi(sdi)
    );

    // {register, value}; DATA_FORMAT first so every later read uses 3-wire mode
    function automatic logic [13:0] cfg(input logic [2:0] i);
        case (i)
            3'd0:    return {6'h31, 8'h4B};   // DATA_FORMAT: 3-wire SPI, full res, +-16 g
            3'd1:    return {6'h2C, 8'h0C};   // BW_RATE: 400 Hz
            3'd2:    return {6'h2F, 8'h00};   // INT_MAP: all to INT1
            3'd3:    return {6'h2E, 8'h80};   // INT_ENABLE: DATA_READY
            default: return {6'h2D, 8'h08};   // POWER_CTL: measure (last)
        endcase
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= BOOT; step <= '0; t <= '0; start <= 1'b0; valid <= 1'b0;
            devid <= '0; int_seen <= 1'b0; timer_mode <= 1'b0;
            x <= '0; y <= '0; z <= '0;
        end else begin
            start <= 1'b0;
            valid <= 1'b0;
            t     <= t + 1'b1;
            if (int1) int_seen <= 1'b1;
            case (state)
                BOOT: if (t == BOOT_WAIT) state <= CFG;
                CFG: begin
                    {addr, wdata} <= cfg(step);
                    rw <= 1'b0; mb <= 1'b0; start <= 1'b1;
                    state <= CFG_W;
                end
                CFG_W: if (done) begin
                    step  <= step + 1'b1;
                    state <= (step == 3'd4) ? ID : CFG;
                end
                ID: begin
                    addr <= 6'h00; rw <= 1'b1; mb <= 1'b0; nrd <= 3'd1; start <= 1'b1;
                    t <= '0;
                    state <= ID_W;
                end
                ID_W: if (done) begin devid <= rdata[7:0]; t <= '0; state <= RUN; end
                RUN: begin
                    if (!int_seen && t >= INT_WAIT) timer_mode <= 1'b1;
                    // INT1 path: ignore INT1 for half a period after a read, so a slow-clearing flag can't cause a duplicate
                    if ((!timer_mode && int1 && t >= PERIOD / 2) || (timer_mode && t >= PERIOD)) begin
                        addr <= 6'h32; rw <= 1'b1; mb <= 1'b1; nrd <= 3'd6; start <= 1'b1;
                        t <= '0;
                        state <= RD_W;
                    end
                end
                RD_W: if (done) begin                        // bytes: X0 X1 Y0 Y1 Z0 Z1 (little endian)
                    x <= {rdata[39:32], rdata[47:40]};
                    y <= {rdata[23:16], rdata[31:24]};
                    z <= {rdata[7:0],   rdata[15:8]};
                    valid <= 1'b1;
                    state <= RUN;
                end
                default: state <= BOOT;
            endcase
        end
    end
endmodule
