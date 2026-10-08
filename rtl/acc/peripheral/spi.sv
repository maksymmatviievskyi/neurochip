// Technical documentation. Max SCLK is 5MHz.
// Page 14. https://www.analog.com/media/en/technical-documentation/data-sheets/adxl345.pdf
// Uses MODE 3, CPOL 1, CPHA 1

module spi(
    input logic miso,
    input logic clk,
    input logic reset,
    input logic transfer_init,
    input logic [7:0] tx_byte, // Command byte + garbage data
    
    output logic  sclk,
    output logic mosi,
    output logic [7:0] rx_byte,
    output logic done
);

// Clock Scaling
logic [4:0] clkc;

logic [4:0] bitc;

typedef enum logic { IDLE, RUN } state_t;
state_t state;

always_ff @(posedge clk) begin
    if(reset) begin
        sclk <= 1;
        done <= 0;
        bitc <= 8;
        state <= IDLE;
        clkc <= 0;
    end else begin
        done <= 0;
        case (state)
            IDLE: begin 
                if(transfer_init) state <= RUN;
                sclk <= 1'b1;
                clkc <= 0;
            end RUN: begin
                clkc <= clkc + 1;

                if(clkc == 24) begin 
                    if(!sclk) begin                      // sample on high edge
                    rx_byte <= {rx_byte[6:0], miso};
                    bitc    <= bitc - 1;
                    end else begin                       // drive on low edge
                        mosi <= tx_byte[bitc-1];
                    end
                    clkc <= 0;
                    sclk <= !sclk;
                end

                // Send a byte once 8 bits shifted
                if(!bitc) begin 
                    bitc <= 4'd8;
                    done <= 1'b1;
                    state <= IDLE;
                end
            end default: state <= IDLE;
        endcase
    end
end
    
endmodule