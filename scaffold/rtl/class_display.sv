// [SCAFFOLD: written by Claude, not part of the main design]
// Writes a gesture class name on the six 7-segment displays (HEX5 = leftmost).
//   0 idle        "IdLE  "
//   1 light tap   "L-tAP "
//   2 hard tap    "H-tAP "
//   3 double tap  "d-tAP "
//   4 shake       "SHAKE "
//   blank = 1     "------"   (e.g. network not loaded yet)
// Segments are active LOW, bit order {dp, g, f, e, d, c, b, a} as on the DE10-Lite.
module class_display (
    input  logic [2:0] cls,
    input  logic       blank,
    output logic [7:0] hex5, hex4, hex3, hex2, hex1, hex0
);

// character codes
localparam logic [3:0] C_SP = 0, C_DASH = 1, C_A = 2, C_d = 3, C_E = 4, C_H = 5,
                       C_I  = 6, C_K = 7, C_L = 8, C_P = 9, C_S = 10, C_t = 11;

function automatic logic [7:0] seg(input logic [3:0] ch);
    logic [6:0] on;                                     // {g, f, e, d, c, b, a}, 1 = lit
    case (ch)
        C_DASH:  on = 7'b1000000;
        C_A:     on = 7'b1110111;
        C_d:     on = 7'b1011110;
        C_E:     on = 7'b1111001;
        C_H:     on = 7'b1110110;
        C_I:     on = 7'b0110000;
        C_K:     on = 7'b1110101;                       // closest 7-segment shape to K
        C_L:     on = 7'b0111000;
        C_P:     on = 7'b1110011;
        C_S:     on = 7'b1101101;
        C_t:     on = 7'b1111000;
        default: on = 7'b0000000;
    endcase
    seg = {1'b1, ~on};                                  // dp off, active LOW
endfunction

logic [3:0] c5, c4, c3, c2, c1, c0;

always_comb begin
    {c5, c4, c3, c2, c1, c0} = {C_SP, C_SP, C_SP, C_SP, C_SP, C_SP};
    if (blank) {c5, c4, c3, c2, c1, c0} = {C_DASH, C_DASH, C_DASH, C_DASH, C_DASH, C_DASH};
    else case (cls)
        3'd0: {c5, c4, c3, c2} = {C_I, C_d, C_L, C_E};
        3'd1: {c5, c4, c3, c2, c1} = {C_L, C_DASH, C_t, C_A, C_P};
        3'd2: {c5, c4, c3, c2, c1} = {C_H, C_DASH, C_t, C_A, C_P};
        3'd3: {c5, c4, c3, c2, c1} = {C_d, C_DASH, C_t, C_A, C_P};
        3'd4: {c5, c4, c3, c2, c1} = {C_S, C_H, C_A, C_K, C_E};
        default: ;
    endcase
end

assign hex5 = seg(c5);
assign hex4 = seg(c4);
assign hex3 = seg(c3);
assign hex2 = seg(c2);
assign hex1 = seg(c1);
assign hex0 = seg(c0);

endmodule
