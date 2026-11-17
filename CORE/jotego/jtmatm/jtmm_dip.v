// -----------------------------------------------------------------------------
// Exciting Hour / Mat Mania - original arcade DIP banks.
// OSD switch value 1 = physical ON; arcade input ON is active-low 0.
// Bit 0 = switch 1, bit 7 = switch 8.
// SW1:8 is NOT a real DIP input: DSW1[7] must carry live CPU VBlank.
// MAME defaults outside VBlank: DSW1 = 8'h5f, DSW2 = 8'hfe.
// -----------------------------------------------------------------------------
module jtmm_dip (
    input  wire [7:0] sw1,
    input  wire [7:0] sw2,
    input  wire       cpu_vblank,
    output wire [7:0] dsw1,
    output wire [7:0] dsw2
);
    assign dsw1 = {cpu_vblank, ~sw1[6:0]};
    assign dsw2 = ~sw2;
endmodule
