import snn_pkg::*;

module syn_eng(
    input logic clk, 
    input logic reset,
    input logic init,
    input logic [MAX_NEURONS-1:0] spikes,
    
    input logic [CONN_ADDR_W-1:0] conn_meta_rstart,
    input logic [CONN_ADDR_W:0] conn_meta_rcount,

    input logic [NEURON_ADDR_W-1:0] layer_range_rstart,
    input logic [NEURON_ADDR_W:0] layer_range_rcount,

    input logic [NEURON_ADDR_W-1:0] conn_rsource,
    input logic [NEURON_ADDR_W-1:0] conn_rdest,
    input logic signed [WEIGHT_W-1:0] conn_rweight,

    output logic [LAYER_ADDR_W-1:0] layer_range_raddr,
    output logic [NEURON_ADDR_W-1:0] conn_meta_raddr,
    output logic [CONN_ADDR_W-1:0] conn_raddr,

    output logic [MAX_NEURONS*I_W-1:0] I_flat,

    output logic done
);
// FSM, 3 Operational Cycles
typedef enum logic [1:0] { IDLE, SCAN, FETCH, CALC } state_t;
state_t state;

logic signed [I_W-1:0] I [0:MAX_NEURONS-1];

always_comb begin
    for (int n = 0; n < MAX_NEURONS; n++) I_flat[n*I_W +: I_W] = I[n];
end

logic [NEURON_ADDR_W:0] idx; // Extra bit wiggle room for tracking finished state
logic [CONN_ADDR_W:0] counter;
logic [CONN_ADDR_W-1:0] caddr; 
assign conn_meta_raddr = idx;
assign conn_raddr = (state == FETCH) ? conn_meta_rstart : caddr; // Optimises readout to 1 cycle

always_ff @(posedge clk) begin
     if(reset) begin 
        idx <= layer_range_rstart;
        counter <= '0;
        done <= '0;
        state <= IDLE;
     end
     else begin
        done <= '0;
        case (state)
            IDLE: begin
                if(init) begin 
                    idx <= layer_range_rstart;
                    state <= SCAN;
                    for (int n = 0; n < MAX_NEURONS; n++) I[n] <= '0; // I only holds this pass's currents
                end
            end SCAN : begin
                if(idx == layer_range_rstart+layer_range_rcount) begin 
                    done <= 1;
                    state <= IDLE;
                end else if(spikes[idx]) state <= FETCH;
                idx <= idx + 1;
            end FETCH : begin
                if(conn_meta_rcount) begin // EDGE CASE: If spiked neuron doesn't have outgoing connections
                    counter <= conn_meta_rcount;
                    caddr <= conn_meta_rstart + 1;
                    state <= CALC;
                end else state <= SCAN;  
            end CALC : begin
                I[conn_rdest] <= I[conn_rdest] + conn_rweight;
                if(counter==1) state <= SCAN;
                caddr <= caddr + 1;
                counter <= counter - 1;
            end default: state <= IDLE;
        endcase
     end
end

endmodule
