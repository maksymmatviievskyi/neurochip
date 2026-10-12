//   SNN only runs while a gesture is being classified.

//   IDLE     wait for a sample with motion
//   CLEAR    reset the snn (membrane potentials cleared by the LIF sweep) and the class counters
//   WAIT_RDY wait until the snn accepts a timestep (the motion sample is still pending in spike_record)
//   COLLECT  run = 1: T timesteps go through the snn, starting with the motion sample
//   DECIDE   counters are final -> decide pulse
//   HOLD     result stays; re-arm after Q samples in a row without motion
//
// One movement -> exactly one classification.
module gesture_ctrl #(
    parameter int T = 256,                 // timesteps per classification
    parameter int Q = 80                   // quiet samples before re-arming
) (
    input  logic clk,
    input  logic reset,

    input  logic tick,
    input  logic motion,

    input  logic snn_ready,
    input  logic snn_done,

    output logic snn_rst,
    output logic run,
    output logic count_clear,
    output logic decide, // mark the sample window as finished
    output logic busy
);

typedef enum logic [2:0] { IDLE, CLEAR, WAIT_RDY, COLLECT, DECIDE, HOLD } state_t;
state_t state;

logic [$clog2(T+1)-1:0] steps;
logic [$clog2(Q+1)-1:0] quiet;

assign busy = (state == CLEAR) || (state == WAIT_RDY) || (state == COLLECT) || (state == DECIDE);

always_ff @(posedge clk) begin
    if (reset) begin
        state       <= IDLE;
        snn_rst     <= 1'b0;
        run         <= 1'b0;
        count_clear <= 1'b0;
        decide      <= 1'b0;
        steps       <= '0;
        quiet       <= '0;
    end else begin
        snn_rst     <= 1'b0;
        count_clear <= 1'b0;
        decide      <= 1'b0;

        case (state)
            IDLE: if (tick && motion) begin
                snn_rst     <= 1'b1;
                count_clear <= 1'b1;
                state       <= CLEAR;
            end
            CLEAR: state <= WAIT_RDY;       // snn sees the reset this cycle; ready drops next cycle
            WAIT_RDY: if (snn_ready) begin
                run   <= 1'b1;
                steps <= '0;
                state <= COLLECT;
            end
            COLLECT: if (snn_done) begin
                if (steps == T - 1) begin   // this was the T-th timestep
                    run   <= 1'b0;
                    state <= DECIDE;
                end else steps <= steps + 1'b1;
            end
            DECIDE: begin
                decide <= 1'b1;
                quiet  <= '0;
                state  <= HOLD;
            end
            HOLD: if (tick) begin
                if (motion)              quiet <= '0;
                else if (quiet == Q - 1) state <= IDLE;
                else                     quiet <= quiet + 1'b1;
            end
            default: state <= IDLE;
        endcase
    end
end

endmodule
