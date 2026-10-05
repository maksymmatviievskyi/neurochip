// SPI master for the ADXL345 in 3-wire mode (DE10-Lite: GSENSOR_SDI is the bidirectional data line).
// SPI mode 3: SCLK idles high, both sides change data on the falling edge, sample on the rising edge.
// One transaction = command byte {R/W, MB, addr[5:0]} followed by one write byte or nrd read bytes.
module adxl345_spi #(
    parameter int HALF = 25            // SCLK half period in clk cycles (50 MHz / 50 = 1 MHz)
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic        rw,            // 1 = read
    input  logic        mb,            // multi-byte
    input  logic [5:0]  addr,
    input  logic [7:0]  wdata,
    input  logic [2:0]  nrd,           // bytes to read (1..6)
    output logic        busy,
    output logic        done,          // 1-cycle pulse
    output logic [47:0] rdata,         // first byte received in rdata[47:40] (6-byte read) / rdata[7:0] (1-byte read)
    output logic        cs_n,
    output logic        sclk,
    output logic        sdo,           // value to drive on SDI
    output logic        sdo_oe,        // drive SDI when 1, release (tri-state) when 0
    input  logic        sdi            // SDI pin as input
);
    typedef enum logic [2:0] { IDLE, SETUP, LOW, HIGH, HOLD, GAP } state_t;
    state_t state;

    logic [$clog2(HALF)-1:0] cnt;
    logic        tick;
    logic [15:0] tx;
    logic [5:0]  nbits, bitn;
    logic        rd;

    assign tick = (cnt == HALF - 1);
    assign busy = (state != IDLE);

    // output for bit `bitn`: command bits always driven, data bits only for writes
    function automatic logic drive(input logic [5:0] b);
        return (b < 8) || !rd;
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            state  <= IDLE;
            cnt    <= '0;
            cs_n   <= 1'b1;
            sclk   <= 1'b1;
            sdo    <= 1'b1;
            sdo_oe <= 1'b0;
            done   <= 1'b0;
            rdata  <= '0;
        end else begin
            done <= 1'b0;
            cnt  <= (state == IDLE || tick) ? '0 : cnt + 1'b1;
            case (state)
                IDLE: if (start) begin
                    tx    <= {rw, mb, addr, wdata};
                    rd    <= rw;
                    nbits <= rw ? 6'(8 + 8 * nrd) : 6'd16;
                    bitn  <= '0;
                    rdata <= '0;
                    cs_n  <= 1'b0;
                    state <= SETUP;
                end
                SETUP: if (tick) begin                    // CS setup, then first falling edge
                    sclk   <= 1'b0;
                    sdo    <= tx[15];
                    sdo_oe <= 1'b1;
                    state  <= LOW;
                end
                LOW: if (tick) begin                      // rising edge: slave samples, we sample
                    sclk <= 1'b1;
                    if (!drive(bitn)) rdata <= {rdata[46:0], sdi};
                    state <= HIGH;
                end
                HIGH: if (tick) begin
                    if (bitn == nbits - 1) begin
                        sdo_oe <= 1'b0;
                        state  <= HOLD;
                    end else begin                        // falling edge: next bit
                        bitn   <= bitn + 1'b1;
                        sclk   <= 1'b0;
                        tx     <= {tx[14:0], 1'b1};
                        sdo    <= tx[14];
                        sdo_oe <= drive(bitn + 1'b1);
                        state  <= LOW;
                    end
                end
                HOLD: if (tick) begin cs_n <= 1'b1; state <= GAP; end
                GAP:  if (tick) begin done <= 1'b1; state <= IDLE; end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
