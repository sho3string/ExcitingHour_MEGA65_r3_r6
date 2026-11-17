// -----------------------------------------------------------------------------
// Mat Mania / Exciting Hour - foreground 8x8 tilemap (Stage 3)
//
// CPU-visible memory, per original Mat Mania address map:
//   $1000-$13FF: 1024 bytes character video RAM
//   $1400-$17FF: 1024 bytes character colour/attribute RAM
//
// Screen tile index (MAME):  ((31 - tile_x) << 5) | tile_y
// Character index:          vram + 256 * (attribute & 7)
// Character ROM:            1024 chars; code wraps modulo 1024
// Palette group:            attribute bits 5:4
// Transparent pixel:        pen 0
//
// Stage 4: initialise both RAMs with an actual MAME title-screen capture.
// The main cpu will overwrite these bytes in later stages.
// -----------------------------------------------------------------------------

module jtmm_fg (
    input  wire         clk,

    input  wire         cpu_cen,
    input  wire         cpu_we,
    input  wire [10:0]  cpu_addr,
    input  wire [7:0]   cpu_din,
    output reg  [7:0]   cpu_dout,

    input  wire [7:0]   pixel_x,
    input  wire [7:0]   pixel_y,
    output wire [12:0]  char_addr,
    input  wire [7:0]   char_plane0,
    input  wire [7:0]   char_plane1,
    input  wire [7:0]   char_plane2,

    output wire [2:0]   pen,
    output wire [1:0]   color,
    output wire         opaque
);

    // Video and CPU memory ports read at 48 MHz. Only CPU writes are
    // Gated by the 1.5 MHz CPU enable. T65 advances its bus at cen.
    // and samples din on the next cen, so read data must settle between
    // those two enables.
    reg [7:0] vram [0:1023];
    reg [7:0] cram [0:1023];

    // Initialise CPU-visible RAM from the title screen captured in MAME.
    // The .mem files retain MAME's physical RAM byte order. Do not rotate
    // or rearrange them; video_addr below handles the column reversal.
    // Both memories remain writable when the main CPU is connected.
    initial begin
        $readmemh("title_fg_vram.mem", vram);
        $readmemh("title_fg_attr.mem", cram);
    end

    wire [4:0] tile_x = pixel_x[7:3];
    wire [4:0] tile_y = pixel_y[7:3];
    // column reversal from the MAME formula: ((31 - tile_x) << 5) | tile_y
    wire [9:0] video_addr = {~tile_x, tile_y};

    reg [7:0] video_code;
    reg [7:0] video_attr;

    always @(posedge clk) begin
        // Video port A. Pipelined through the 48 MHz clock; eight master
        // clock cycles are available per visible 6 MHz pixel.
        video_code <= vram[video_addr];
        video_attr <= cram[video_addr];

        // CPU read port: continuously prefetch the current bus address.
        // A write occurs on the enable ending the 6502 write bus cycle.
        if (cpu_addr[10]) begin
            cpu_dout <= cram[cpu_addr[9:0]];
            if (cpu_cen && cpu_we)
                cram[cpu_addr[9:0]] <= cpu_din;
        end else begin
            cpu_dout <= vram[cpu_addr[9:0]];
            if (cpu_cen && cpu_we)
                vram[cpu_addr[9:0]] <= cpu_din;
        end
    end

    // The ROM contains 1024 characters, so bit 2 of attr[2:0] is a wrap
    // bit and does not extend the physical character ROM past 1024 entries.
    wire [9:0] char_code = {video_attr[1:0], video_code};
    
    // native MAME row order; the 180° is already handled by pixel_x/pixel_y
    assign char_addr = {char_code, pixel_y[2:0]};

    // Match the working Stage-2 decoder and MAME gfx_layout bitplane order.
    assign pen = {
        char_plane2[~pixel_x[2:0]],
        char_plane1[~pixel_x[2:0]],
        char_plane0[~pixel_x[2:0]]
    };

    assign color  = video_attr[5:4];
    assign opaque = |pen;

endmodule
