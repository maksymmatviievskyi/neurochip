import snn_pkg::*;

module spike_buffer #(
    parameter  int DEPTH = SPIKE_BUF_DEPTH,
    localparam int BUF_ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
    )
(
    input logic clk,
    input logic reset,
    input logic push,
    input logic pop,
    input logic [NEURON_ADDR_W-1:0] wdata,

    output logic pop_valid,
    output logic [BUF_ADDR_W-1:0] occ,
    output logic [NEURON_ADDR_W-1:0] saddr
);

logic [BUF_ADDR_W-1:0] head, tail, occnxt;
logic [NEURON_ADDR_W-1:0] buffer [0:DEPTH-1];
logic full, do_wrt, do_pop;

assign full = (occ == DEPTH-1);
assign do_wrt = push && !full;
assign do_pop   = pop && (occ != 0);

always_comb begin
    occnxt = occ;
    if (do_wrt) occnxt++;
    if (do_pop) occnxt--;
end


// control state
always_ff @(posedge clk) begin
    if (reset) begin
        head      <= '0;
        tail      <= '0;
        occ       <= '0;
        pop_valid <= '0;
    end else begin
        if (do_wrt) head <= head + 1;
        if (do_pop) tail <= tail + 1;
        occ       <= occnxt;
        pop_valid <= do_pop;
    end
end

// memory
always_ff @(posedge clk) begin
    if (do_wrt) buffer[head] <= wdata;
    if (do_pop) saddr        <= buffer[tail];
end
    
endmodule