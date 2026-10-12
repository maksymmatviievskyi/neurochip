import snn_pkg::*;

module conn_mem #(
    parameter        INIT_FILE = ""  // untyped: Icarus cannot pass a parameter into a string-typed one
) (
    input  logic clk,
    input  logic wen,
    input  logic [CONN_ADDR_W-1:0] raddr,
    input  logic [CONN_ADDR_W-1:0] waddr,
    input  logic [CONN_W-1:0]      data,
    output logic [NEURON_ADDR_W-1:0]   rsource, // if meta_mem is used to store synaptic ranges relative to a neuron, this becomes redundant, doesn't it?
    output logic [NEURON_ADDR_W-1:0]   rdest,
    output logic signed [WEIGHT_W-1:0] rweight
);
    logic [CONN_W-1:0] mem [0:MAX_CONNECTIONS-1];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    always_ff @(posedge clk) begin
        if (wen) mem[waddr] <= data;
        {rsource, rdest, rweight} <= mem[raddr];
    end

endmodule
