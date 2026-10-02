import snn_pkg::*;

module lif_eng (
    input logic                         clk,
    input logic                         reset,
    input logic                         syn_ready,
    input logic [NEURON_ADDR_W-1:0] layer_range_start,
    input logic [NEURON_ADDR_W:0] layer_range_spread,
    input logic [MAX_NEURONS*I_W-1:0] I_flat,
    input logic [LEAK_SHIFT_W-1:0]           decay_shift, 
    input logic signed [THRESHOLD_W-1:0] threshold, 
    input logic signed [THRESHOLD_W-1:0] reset_value,
    output logic                        done,
    output logic                        cleared,
    output logic [MAX_NEURONS-1:0]      spikes
);

typedef enum logic [1:0] { CLEAR, IDLE, RUN } state_t;
state_t state;

localparam int V_W = I_W + 1; // Extra safeguard bit added
localparam logic signed [V_W:0] V_REST = '0;

logic signed [V_W:0] VRAM [0:MAX_NEURONS-1];
logic signed [I_W-1:0] I [0:MAX_NEURONS-1];

logic [NEURON_ADDR_W-1:0] vwaddr;
logic signed [V_W:0]      vwdata;
logic                     vwen;

logic [NEURON_ADDR_W-1:0] vraddr;
logic signed [V_W:0]      V;

logic [NEURON_ADDR_W:0]   nidx;      
logic [NEURON_ADDR_W-1:0] clridx;    // CLEAR sweep pointer

logic [NEURON_ADDR_W-1:0] calcidx;
logic                     calcvld;

logic signed [V_W:0] VNXT;

assign vraddr = (state == IDLE) ? layer_range_start  
                : nidx;

// Degrades decay precision
// FEAT:  Change once floating operations are implemented
assign VNXT = V - (V >>> decay_shift) + I[calcidx];

always_comb begin
    for (int n = 0; n < MAX_NEURONS; n++) I[n] = I_flat[n*I_W +: I_W];
end

// Control
always_ff @(posedge clk) begin
    if (reset) begin
        spikes   <= '0;
        done     <= 1'b0;
        cleared  <= 1'b0;
        nidx     <= '0;
        clridx   <= '0;
        calcidx <= '0;
        calcvld <= 1'b0;
        vwaddr   <= '0;
        vwdata   <= V_REST;
        vwen     <= 1'b0;
        state    <= CLEAR;
    end else begin
        done <= 1'b0;
        case (state)
            CLEAR : begin
                vwaddr <= clridx;
                vwdata <= V_REST;
                vwen   <= 1'b1;
                if (clridx == NEURON_ADDR_W'(MAX_NEURONS-1)) begin 
                    state <= IDLE;
                    cleared <= 1'b1;
                end else clridx <= clridx + 1'b1;
            end IDLE : begin
                vwen <= 1'b0;

                if (syn_ready) begin
                    spikes   <= '0;
                    if (!layer_range_spread) begin
                        done <= 1'b1;
                    end else begin
                        calcidx <= layer_range_start;
                        calcvld <= 1'b1;
                        nidx    <= layer_range_start + 1;
                        state   <= RUN;
                    end
                end
            end RUN : begin
                if (calcvld) begin
                    vwaddr <= calcidx;
                    vwen   <= 1'b1;

                    if (VNXT >= threshold) begin
                        spikes[calcidx] <= 1'b1;
                        vwdata           <= reset_value;
                    end else begin
                        spikes[calcidx] <= 1'b0;
                        vwdata           <= VNXT;
                    end
                end else vwen <= 1'b0;

                if (nidx < layer_range_start + layer_range_spread) begin
                    calcidx <= nidx[NEURON_ADDR_W-1:0];
                    calcvld <= 1'b1;
                    nidx     <= nidx + 1'b1;
                end else begin
                    calcvld <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

// Memory
always_ff @(posedge clk) begin
    if (vwen) VRAM[vwaddr] <= vwdata;
    V <= VRAM[vraddr];
end

endmodule
