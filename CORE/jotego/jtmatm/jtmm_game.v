// -----------------------------------------------------------------------------
// Mat Mania / Exciting Hour - main CPU, foreground and colour (Stage 6)
// Other video layers and sound CPU will follow once 6502 writes are verified.
// -----------------------------------------------------------------------------

module jtmm_game (
    input  wire         clk,
    input  wire         reset,
    input  wire         cen6,
    input  wire         cen1p5,
    input  wire         cen1p2,

    input  wire [7:0]   in0,
    input  wire [7:0]   in1,
    input  wire [7:0]   sw1,
    input  wire [7:0]   sw2,

    output wire [14:0]  sound_rom_addr,
    input  wire [7:0]   sound_rom_data,
    output wire         ay1_wr,
    output wire         ay1_addr_mode,
    output wire [7:0]   ay1_din,
    output wire         ay2_wr,
    output wire         ay2_addr_mode,
    output wire [7:0]   ay2_din,
    output wire signed [15:0] dac_pcm,

    output wire [15:0]  main_rom_addr,
    input  wire [7:0]   main_rom_data,

    output wire [12:0]  char_addr,
    input  wire [7:0]   char_plane0,
    input  wire [7:0]   char_plane1,
    input  wire [7:0]   char_plane2,

    output wire [13:0]  bg_rom_addr,
    input  wire [7:0]   bg_plane0,
    input  wire [7:0]   bg_plane1,
    input  wire [7:0]   bg_plane2,

    output wire [16:0]  obj_rom_addr,
    input  wire [7:0]   obj_plane0,
    input  wire [7:0]   obj_plane1,
    input  wire [7:0]   obj_plane2,

    output wire [3:0]   red,
    output wire [3:0]   green,
    output wire [3:0]   blue,
    output wire         LHBL,
    output wire         LVBL,
    output wire         HS,
    output wire         VS
);

    wire        fg_cpu_cen;
    wire        fg_cpu_we;
    wire [10:0] fg_cpu_addr;
    wire [7:0]  fg_cpu_din;
    wire [7:0]  fg_cpu_dout;
    wire        bg_cpu_cen;
    wire        bg_cpu_we;
    wire [10:0] bg_cpu_addr;
    wire [7:0]  bg_cpu_din;
    wire [7:0]  bg_cpu_dout;
    wire        obj_cpu_we;
    wire [6:0]  obj_cpu_addr;
    wire [7:0]  obj_cpu_din;
    wire [7:0]  page_select;
    wire [7:0]  scroll;

    wire        pal_we;
    wire [5:0]  pal_addr;
    wire [7:0]  pal_din;
    wire        cpu_vblank;
    wire        frame_irq;
    wire [7:0]  dsw1;
    wire [7:0]  dsw2;
    wire        sound_cmd_we;
    wire [7:0]  sound_cmd_data;
    wire [15:0] debug_pc;
    wire        debug_jam;

    jtmm_dip u_dip (
        .sw1           (sw1),
        .sw2           (sw2),
        .cpu_vblank    (cpu_vblank),
        .dsw1          (dsw1),
        .dsw2          (dsw2)
    );

    jtmm_main u_main (
        .clk           (clk),
        .reset         (reset),
        .cen1p5        (cen1p5),
        .frame_irq     (frame_irq),
        .in0           (in0),
        .in1           (in1),
        .dsw1          (dsw1),
        .dsw2          (dsw2),
        .rom_addr      (main_rom_addr),
        .rom_data      (main_rom_data),
        .fg_cpu_cen    (fg_cpu_cen),
        .fg_cpu_we     (fg_cpu_we),
        .fg_cpu_addr   (fg_cpu_addr),
        .fg_cpu_din    (fg_cpu_din),
        .fg_cpu_dout   (fg_cpu_dout),
        .bg_cpu_cen    (bg_cpu_cen),
        .bg_cpu_we     (bg_cpu_we),
        .bg_cpu_addr   (bg_cpu_addr),
        .bg_cpu_din    (bg_cpu_din),
        .bg_cpu_dout   (bg_cpu_dout),
        .obj_cpu_we    (obj_cpu_we),
        .obj_cpu_addr  (obj_cpu_addr),
        .obj_cpu_din   (obj_cpu_din),
        .page_select_o (page_select),
        .scroll_o      (scroll),
        .pal_we        (pal_we),
        .pal_addr      (pal_addr),
        .pal_din       (pal_din),
        .sound_cmd_we  (sound_cmd_we),
        .sound_cmd_data(sound_cmd_data),
        .debug_pc      (debug_pc),
        .debug_jam     (debug_jam)
    );

    jtmm_sound u_sound (
        .clk           (clk),
        .reset         (reset),
        .cen1p2        (cen1p2),
        .cen1p5        (cen1p5),
        .cmd_we        (sound_cmd_we),
        .cmd_data      (sound_cmd_data),
        .rom_addr      (sound_rom_addr),
        .rom_data      (sound_rom_data),
        .ay1_wr        (ay1_wr),
        .ay1_addr_mode (ay1_addr_mode),
        .ay1_din       (ay1_din),
        .ay2_wr        (ay2_wr),
        .ay2_addr_mode (ay2_addr_mode),
        .ay2_din       (ay2_din),
        .dac_pcm       (dac_pcm),
        .debug_pc      (),
        .debug_jam     ()
    );

    jtmm_video u_video (
        .clk           (clk),
        .reset         (reset),
        .cen6          (cen6),
        .fg_cpu_cen    (fg_cpu_cen),
        .fg_cpu_we     (fg_cpu_we),
        .fg_cpu_addr   (fg_cpu_addr),
        .fg_cpu_din    (fg_cpu_din),
        .fg_cpu_dout   (fg_cpu_dout),
        .cpu_vblank    (cpu_vblank),
        .frame_irq     (frame_irq),
        .pal_we        (pal_we),
        .pal_addr      (pal_addr),
        .pal_din       (pal_din),
        .char_addr     (char_addr),
        .char_plane0   (char_plane0),
        .char_plane1   (char_plane1),
        .char_plane2   (char_plane2),
        .bg_cpu_cen    (bg_cpu_cen),
        .bg_cpu_we     (bg_cpu_we),
        .bg_cpu_addr   (bg_cpu_addr),
        .bg_cpu_din    (bg_cpu_din),
        .bg_cpu_dout   (bg_cpu_dout),
        .obj_cpu_we    (obj_cpu_we),
        .obj_cpu_addr  (obj_cpu_addr),
        .obj_cpu_din   (obj_cpu_din),
        .page_select   (page_select),
        .scroll        (scroll),
        .bg_rom_addr   (bg_rom_addr),
        .bg_plane0     (bg_plane0),
        .bg_plane1     (bg_plane1),
        .bg_plane2     (bg_plane2),
        .obj_rom_addr  (obj_rom_addr),
        .obj_plane0    (obj_plane0),
        .obj_plane1    (obj_plane1),
        .obj_plane2    (obj_plane2),
        .red           (red),
        .green         (green),
        .blue          (blue),
        .LHBL          (LHBL),
        .LVBL          (LVBL),
        .HS            (HS),
        .VS            (VS)
    );

endmodule
