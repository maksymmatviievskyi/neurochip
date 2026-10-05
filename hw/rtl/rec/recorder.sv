// Records accelerometer windows into a 16384 x 48-bit RAM readable over JTAG
// (Quartus: Tools > In-System Memory Content Editor, instance "REC").
// RAM word = {x, y, z}; window w (0..15) = addresses w*1024 .. w*1024+1023.
// After reset the RAM is cleared (never-recorded windows read as zero).
module recorder #(
    parameter int SETTLE = 15_000_000       // 300 ms after KEY1 release before recording
) (
    input  logic               clk,
    input  logic               reset,
    input  logic               rec_req,     // 1-cycle pulse on KEY1 release
    input  logic signed [15:0] x, y, z,
    input  logic               valid,
    output logic [4:0]         windows,     // windows recorded (0..16)
    output logic               settling,
    output logic               recording,
    output logic               full,
    output logic [47:0]        q            // RAM read port (only used to keep the RAM from being optimised away)
);
    typedef enum logic [2:0] { CLEAR, IDLE, SETTLE_S, ARM, REC } state_t;
    state_t state;

    logic [13:0] addr;
    logic [47:0] wdata;
    logic        wren;
    logic [9:0]  idx;
    logic [$clog2(SETTLE+1)-1:0] t;

    assign full      = (windows == 5'd16);
    assign settling  = (state == SETTLE_S || state == ARM);
    assign recording = (state == REC);

    always_comb begin
        if (state == CLEAR) begin
            addr = {windows[3:0], idx};  // windows/idx sweep all 16384 addresses during CLEAR
            wdata = '0; wren = 1'b1;
        end else begin
            addr = {windows[3:0], idx};
            wdata = {x, y, z};
            wren = (state == REC) && valid;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= CLEAR; windows <= '0; idx <= '0; t <= '0;
        end else begin
            case (state)
                CLEAR: begin
                    {windows, idx} <= {windows, idx} + 1'b1;
                    if ({windows[3:0], idx} == 14'h3FFF) begin
                        windows <= '0; idx <= '0; state <= IDLE;
                    end
                end
                IDLE: if (rec_req && !full) begin t <= '0; state <= SETTLE_S; end
                SETTLE_S: begin
                    t <= t + 1'b1;
                    if (t == SETTLE) state <= ARM;
                end
                ARM: if (valid) state <= REC;           // start on a sample boundary
                REC: if (valid) begin
                    idx <= idx + 1'b1;
                    if (idx == 10'd1023) begin windows <= windows + 1'b1; state <= IDLE; end
                end
                default: state <= IDLE;
            endcase
        end
    end

`ifdef SIM
    logic [47:0] mem [0:16383];
    always_ff @(posedge clk) begin
        if (wren) mem[addr] <= wdata;
        q <= mem[addr];
    end
`else
    // Same configuration the IP Catalog "RAM: 1-PORT" wizard generates, with In-System Memory
    // Content Editor access enabled (instance ID "REC").
    altsyncram #(
        .operation_mode                ("SINGLE_PORT"),
        .width_a                       (48),
        .widthad_a                     (14),
        .numwords_a                    (16384),
        .width_byteena_a               (1),
        .outdata_reg_a                 ("UNREGISTERED"),   // q_a is still registered at the RAM input
        .clock_enable_input_a          ("BYPASS"),
        .clock_enable_output_a         ("BYPASS"),
        .read_during_write_mode_port_a ("NEW_DATA_NO_NBE_READ"),
        .power_up_uninitialized        ("FALSE"),
        .ram_block_type                ("M9K"),
        .intended_device_family        ("MAX 10"),
        .lpm_hint                      ("ENABLE_RUNTIME_MOD=YES,INSTANCE_NAME=REC"),
        .lpm_type                      ("altsyncram")
    ) ram (
        .clock0 (clk),
        .address_a (addr),
        .data_a (wdata),
        .wren_a (wren),
        .q_a (q)
    );
`endif
endmodule
