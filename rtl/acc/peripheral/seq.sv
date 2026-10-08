module seq(
    input logic clk,
    input logic reset,
    input logic int1, // Interrupt signal. HIGH when ADXL345 has completed the measurement
    input logic done,

    output logic [7:0] tx_byte,
    output logic start,
    output logic cs,               // Active LOW: 0 = sensor selected
    output logic byte_assmbl_init
);

typedef enum logic [3:0] {
    BOOT,                                           // Wait 10ms after power-up
    C_CS, C_ADDR, C_ADDR_W, C_VAL, C_VAL_W, C_END,  // One 2-byte write per CONF_TABLE entry
    R_IDLE, R_CS, R_SEND, R_WAIT, R_END             // One 7-byte read per sample
} state_t;
state_t state;

logic [23:0] timer;

typedef struct packed {
    logic [7:0] addr;
    logic [7:0] val;
} conf_t;

localparam int CONF_N = 5;
logic [2:0] confidx;

// Config commands and data. Case used to fit Quartus
function automatic conf_t conf_table(input logic [2:0] i);
    case (i)
        0: conf_table = {8'h31, 8'h0B}; // DATA FORMAT
        1: conf_table = {8'h2C, 8'h0C}; // SAMPLE RATE
        2: conf_table = {8'h2F, 8'h00}; // INTERRUPTS
        3: conf_table = {8'h2E, 8'h80}; // INTERRUPT ENABLE
        4: conf_table = {8'h2D, 8'h08}; // MEASURE INIT SIGNAL
        default: conf_table = 16'h0000;
    endcase
endfunction

conf_t conf;
assign conf = conf_table(confidx);

localparam RDSIG = 8'hF2;  // DATA READ SIGNAL
localparam GAP   = 16;     // CS high time between transactions (>= 150ns)

logic [2:0] n;             // Byte index within a data read: 0 = RDSIG, 1..6 = X0..Z1
logic [1:0] int1_s;        // INT1 synchroniser

// Only the 6 data bytes of a read reach the assembler
assign byte_assmbl_init = !((state == R_SEND || state == R_WAIT) && n != 0);

always_ff @(posedge clk) begin
    if(reset) begin
        state <= BOOT;
        cs <= 1'b1;
        confidx <= 0;
        start <= 0;
        timer <= 0;
        tx_byte <= 0;
        n <= 0;
        int1_s <= 0;
    end else begin
        // Due to metastability. 
        // Reveal the determenistic value to the circuit once it had time to settle
        int1_s <= {int1_s[0], int1};
        
        start <= 0;

        case (state)
            BOOT: begin
                // Wait for 10ms
                if(timer == 500000) begin
                    state <= C_CS;
                    timer <= 0;
                end else timer <= timer + 1;

            // ---------------- CONFIG ----------------
            end C_CS: begin
                cs <= 0;
                state <= C_ADDR;
            end C_ADDR: begin
                tx_byte <= conf.addr;
                start <= 1;
                state <= C_ADDR_W;
            end C_ADDR_W: begin
                if(done) state <= C_VAL;
            end C_VAL: begin
                tx_byte <= conf.val;
                start <= 1;
                state <= C_VAL_W;
            end C_VAL_W: begin
                if(done) state <= C_END;
            end C_END: begin
                cs <= 1;
                if(timer == GAP) begin
                    timer <= 0;
                    if(confidx == CONF_N-1) state <= R_IDLE;
                    else begin
                        confidx <= confidx + 1;
                        state <= C_CS;
                    end
                end else timer <= timer + 1;

            // ---------------- DATA READ ----------------
            end R_IDLE: begin
                if(int1_s[1]) state <= R_CS;
            end R_CS: begin
                cs <= 0;
                n <= 0;
                state <= R_SEND;
            end R_SEND: begin
                tx_byte <= (n == 0) ? RDSIG : 8'h00;    // Garbage data after the command
                start <= 1;
                state <= R_WAIT;
            end R_WAIT: begin
                if(done) begin
                    if(n == 6) state <= R_END;
                    else begin
                        n <= n + 1;
                        state <= R_SEND;
                    end
                end
            end R_END: begin
                cs <= 1;
                if(timer == GAP) begin
                    timer <= 0;
                    state <= R_IDLE;
                end else timer <= timer + 1;
            end default: state <= BOOT;
        endcase
    end
end

endmodule
