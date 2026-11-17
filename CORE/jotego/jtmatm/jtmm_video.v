// -----------------------------------------------------------------------------
// Mat Mania / Exciting Hour - video integration (Stage 6: PROM colour)
//
// Clock:          48 MHz, cen6 one cycle every 8 clocks
// Pixel timing:   6 MHz / 384 / 264 = 59.185606 Hz
// Visible source: 256 x 240, x=64..319, y=12..251
//
// The foreground tilemap is 32 x 32, drawn as an 8x8 character layer.
// Original foreground PROM colour; background and sprites to follow.
// -----------------------------------------------------------------------------

module jtmm_video (
    input  wire         clk,
    input  wire         reset,
    input  wire         cen6,

    // Foreground CPU port. Address bit 10 selects character/attribute RAM:
    // 0x000..0x3ff = CPU $1000..$13ff (character RAM)
    // 0x400..0x7ff = CPU $1400..$17ff (attribute RAM)
    input  wire         fg_cpu_cen,
    input  wire         fg_cpu_we,
    input  wire [10:0]  fg_cpu_addr,
    input  wire [7:0]   fg_cpu_din,
    output wire [7:0]   fg_cpu_dout,

    // Background CPU and video interfaces.
    input  wire         bg_cpu_cen,
    input  wire         bg_cpu_we,
    input  wire [10:0]  bg_cpu_addr,
    input  wire [7:0]   bg_cpu_din,
    output wire [7:0]   bg_cpu_dout,
    input  wire [7:0]   page_select,
    input  wire [7:0]   scroll,
    output wire [13:0]  bg_rom_addr,
    input  wire [7:0]   bg_plane0,
    input  wire [7:0]   bg_plane1,
    input  wire [7:0]   bg_plane2,

    // Sprite RAM and ROM interfaces.
    input  wire         obj_cpu_we,
    input  wire [6:0]   obj_cpu_addr,
    input  wire [7:0]   obj_cpu_din,
    output wire [16:0]  obj_rom_addr,
    input  wire [7:0]   obj_plane0,
    input  wire [7:0]   obj_plane1,
    input  wire [7:0]   obj_plane2,

    // Sprite palette RAM writes at CPU $3050..$307F.
    // All CPU accesses are clock-enabled on the 48 MHz system clock.
    input  wire         pal_we,
    input  wire [5:0]   pal_addr,
    input  wire [7:0]   pal_din,

    // CPU-visible four-scanline status and an IRQ event per frame.
    output wire         cpu_vblank,
    output wire         frame_irq,

    output wire [12:0]  char_addr,
    input  wire [7:0]   char_plane0,
    input  wire [7:0]   char_plane1,
    input  wire [7:0]   char_plane2,

    output wire [3:0]   red,
    output wire [3:0]   green,
    output wire [3:0]   blue,
    output wire         LHBL,
    output wire         LVBL,
    output wire         HS,
    output wire         VS
);

    reg [7:0] scroll_q = 8'd0, page_q = 8'd0;
    always @(posedge clk)
        if (cen6 && H == 9'd0 && vdump == 9'd11) begin   // last blank line before the picture
            scroll_q <= scroll;
            page_q   <= page_select;
        end


    wire [8:0] H;
    wire [8:0] vdump;

    // JTFRAME's horizontal/vertical timer. The wrap parameters MUST be
    // supplied explicitly: with a wrapped blanking interval, its default
    // HCNT_END / VCNT_END deductions would otherwise give the wrong totals.
    //
    // LHBL is high for H=64..319 (256 pixels).
    // LVBL is high for vdump=12..251 (240 lines).
    // HS is high for H=0..27 (28 pixels).
    // VS is high for 2 lines around the frame boundary.
    jtframe_vtimer #(
        .HCNT_START    (9'd0),
        .HCNT_END      (9'd383),
        .HB_START      (9'd320),
        .HB_END        (9'd63),
        .HS_START      (9'd383),
        .HS_END        (9'd27),
        .H_VB          (9'd320),
        .H_VNEXT       (9'd383),
        .V_START       (9'd0),
        .VCNT_END      (9'd263),
        .VB_START      (9'd251),
        .VB_END        (9'd11),
        .VS_START      (9'd0),
        .VS_END        (9'd2)
    ) u_vtimer (
        .clk           (clk),
        .pxl_cen       (cen6),
        .vdump         (vdump),
        .vrender       (),
        .vrender1      (),
        .H             (H),
        .Hinit         (),
        .Vinit         (),
        .LHBL          (LHBL),
        .LVBL          (LVBL),
        .HS            (HS),
        .VS            (VS)
    );

    // Original hardware's short CPU-visible VBlank flag, independent
    // from the LVBL signal used to blank the video output.
    assign cpu_vblank = !((vdump >= 9'd128) && (vdump <= 9'd131));

    // Interrupt event once per frame as the visible image ends.
    assign frame_irq = cen6 && (H == 9'd383) && (vdump == 9'd251);

    // Native raster position. Valid when LHBL and LVBL are high.
    // The current foreground appears rotated 180 degrees relative to MAME.
    // Reverse both visible coordinates without changing sync or M2M rotation.
    // Values outside the visible area are still blanked by LHBL / LVBL.
    wire [7:0] pixel_x = H[7:0] - 8'd64;
    wire [7:0] pixel_y = vdump[7:0] - 8'd12;

    wire [2:0] fg_pen;
    wire [1:0] fg_color;
    wire       fg_opaque;

    jtmm_fg u_fg (
        .clk           (clk),
        .cpu_cen       (fg_cpu_cen),
        .cpu_we        (fg_cpu_we),
        .cpu_addr      (fg_cpu_addr),
        .cpu_din       (fg_cpu_din),
        .cpu_dout      (fg_cpu_dout),
        .pixel_x       (pixel_x),
        .pixel_y       (pixel_y),
        .char_addr     (char_addr),
        .char_plane0   (char_plane0),
        .char_plane1   (char_plane1),
        .char_plane2   (char_plane2),
        .pen           (fg_pen),
        .color         (fg_color),
        .opaque        (fg_opaque)
    );

    // Background is opaque; sprites use pen 0 as transparency.
    wire [2:0] bg_pen;
    wire [1:0] bg_color;
    wire       bg_valid;
    wire [2:0] obj_pen;
    wire       obj_color;
    wire       obj_valid;

    jtmm_bg u_bg (
        .clk           (clk),
        .cpu_cen       (bg_cpu_cen),
        .cpu_we        (bg_cpu_we),
        .cpu_addr      (bg_cpu_addr),
        .cpu_din       (bg_cpu_din),
        .cpu_dout      (bg_cpu_dout),
        .page_select   (page_q),
        .scroll        (scroll_q),
        .pixel_x       (pixel_x),
        .pixel_y       (pixel_y),
        .bg_rom_addr   (bg_rom_addr),
        .bg_plane0     (bg_plane0),
        .bg_plane1     (bg_plane1),
        .bg_plane2     (bg_plane2),
        .pen           (bg_pen),
        .color         (bg_color),
        .valid         (bg_valid)
    );


    jtmm_obj u_obj (
        .clk           (clk),
        .reset         (reset),
        .cen6          (cen6),
        .H             (H),
        .vdump         (vdump),
        .pixel_x       (pixel_x),
        .cpu_we        (obj_cpu_we),
        .cpu_addr      (obj_cpu_addr),
        .cpu_din       (obj_cpu_din),
        .obj_rom_addr  (obj_rom_addr),
        .obj_plane0    (obj_plane0),
        .obj_plane1    (obj_plane1),
        .obj_plane2    (obj_plane2),
        .pen           (obj_pen),
        .color         (obj_color),
        .valid         (obj_valid)
    );
        

    // Shared colour mixer: foreground over sprites over background.
    jtmm_colmix u_colmix (
        .clk           (clk),
        .reset         (reset),
        .video_on      (LHBL && LVBL && (pixel_x != 8'd0)),

        .fg_pen        (fg_pen),
        .fg_color      (fg_color),
        .fg_opaque     (fg_opaque),

        .bg_valid      (bg_valid),
        .bg_pen        (bg_pen),
        .bg_color      (bg_color),

        .obj_valid     (obj_valid),
        .obj_pen       (obj_pen),
        .obj_color     (obj_color),

        .pal_we        (pal_we),
        .pal_addr      (pal_addr),
        .pal_din       (pal_din),

        .red           (red),
        .green         (green),
        .blue          (blue)
    );

    // The timer counters are available here for future CPU video status,
    // scroll fetch timing, sprite evaluation and sound interrupts.

endmodule
