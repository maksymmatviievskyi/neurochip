import snn_pkg::*;

module spike_record #(
    parameter int STEP_N = 6,
    parameter int DATA_W = 16
) (
    input  logic                     clk,
    input  logic                     reset,

    input  logic                     sample_valid,  
    input  logic signed [DATA_W-1:0] x,
    input  logic signed [DATA_W-1:0] y,
    input  logic signed [DATA_W-1:0] z,

    output logic [MAX_NEURONS-1:0]   spikesIn,
    output logic                     enc_valid,     // 1-cycle pulse: spikesIn holds a new sample
    output logic                     snn_init,
    input  logic                     snn_done,
    input  logic                     snn_ready,     // snn idle and membrane potentials cleared
    input  logic                     run,           // HIGH: send encoded samples to the snn (gated mode)

    output logic                     busy,
    output logic                     err // Keep track of lost timesteps due to busy snn module
);

logic signed [DATA_W-1:0] sample [0:2];
logic                     first;         // Tracks if the sample is first since the run
logic                     enc_done;
logic                     pending;       // an encoded sample has not been sent to the snn yet

assign enc_valid = enc_done;

always_comb begin       // element by element: Icarus cannot assign an assignment pattern to a net
    sample[0] = x;
    sample[1] = y;
    sample[2] = z;
end

dencode #(
    .STEP_N (STEP_N),
    .DATA_Q (3),
    .DATA_W (DATA_W)
) dncd (
    .clk    (clk),
    .reset  (reset),
    .init   (first),
    .valid  (sample_valid),
    .sample (sample),
    .spikes (spikesIn),
    .done   (enc_done)
);

typedef enum logic { IDLE, WAIT_SNN } state_t;
state_t state;

assign busy = (state == WAIT_SNN);

always_ff @(posedge clk) begin
    if (reset) begin
        state    <= IDLE;
        first    <= 1'b1;
        snn_init <= 1'b0;
        err      <= 1'b0;
        pending  <= 1'b0;
    end else begin
        snn_init <= 1'b0;                                  // default: no pulse

        if (sample_valid) first <= 1'b0;                   // only the very first sample initialises
        if (sample_valid && state == WAIT_SNN) err <= 1'b1;
        if (enc_done) pending <= 1'b1;                     // newest sample replaces an unsent one

        // The encoder always runs (the motion detector needs it); the snn only gets samples while run.
        // The sample that triggered motion stays pending until the snn has been reset and is ready.

        case (state)
            IDLE: if ((pending || enc_done) && run && snn_ready) begin
                snn_init <= 1'b1;
                pending  <= 1'b0;
                state    <= WAIT_SNN;
            end
            WAIT_SNN: if (snn_done) state <= IDLE;
            default:  state <= IDLE;
        endcase
    end
end

endmodule
