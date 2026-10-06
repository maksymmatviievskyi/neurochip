package snn_pkg;

    parameter int MAX_CONNECTIONS = 4096;
    parameter int MAX_LAYERS      = 16;
    parameter int MAX_NEURONS    = 128;
    parameter int SPIKE_BUF_DEPTH    = 1024;

    parameter int WEIGHT_W = 16;
    parameter int THRESHOLD_W  = 16;
    parameter int LEAK_SHIFT_W  = 4; 

    localparam int CONN_ADDR_W =
        (MAX_CONNECTIONS <= 1) ? 1 : $clog2(MAX_CONNECTIONS);

    localparam int LAYER_ADDR_W =
        (MAX_LAYERS <= 1) ? 1 : $clog2(MAX_LAYERS);

    localparam int NEURON_ADDR_W =
        (MAX_NEURONS <= 1) ? 1 : $clog2(MAX_NEURONS);

    localparam int I_W = WEIGHT_W + NEURON_ADDR_W;

    localparam int CONN_W = 2*NEURON_ADDR_W + WEIGHT_W;
endpackage