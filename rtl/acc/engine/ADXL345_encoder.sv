import snn_pkg::*;

module ADXL345_ctrl(
    input logic clk,
    input logic reset,

    input logic signed [15:0] x, 
    input logic signed [15:0] y, 
    input logic signed [15:0] z,
    input logic snn_ready,

    output logic init,
    output logic [MAX_NEURONS-1:0] spikes
);

localparam INPUT_LAYER_SIZE = 36;

logic signed [15:0] sample [0:2];
logic               enc_valid;
logic               enc_done;

assign sample = '{x, y, z};

dencode #(
    .STEP_N (6),
    .DATA_Q (3),
    .DATA_W (16)
) dncd (
    .clk    (clk),
    .reset  (reset),
    .init   (init),
    .valid  (enc_valid),
    .sample (sample),
    .spikes (spikes),
    .done   (enc_done)
);

typedef enum logic { IDLE, INIT } state_t;
state_t state;

always_ff @(posedge clk) begin
    if(reset) begin
        init <= 0;
    end else begin
        case (state)
            IDLE: begin
                init <= 0;
                if(snn_ready) state <= INIT;
            end INIT: begin
                init <= 1'b1;
                if(enc_done) begin
                    init <= 1'b1;
                    state <= IDLE;
                end
            end default: state <= IDLE;
        endcase
    end
end

endmodule