// -----------------------------------------------------------------------------
// Exciting Hour / Mat Mania - background playfield
//
// Two pages, each 16 columns x 32 rows of 16x16 tiles (256x512 pixels).
// CPU: $2000-$21ff tile0, $2200-$23ff attr0,
//      $2400-$25ff tile1, $2600-$27ff attr1.
// MAME draws tiles at sx=15-offs/32, sy=offs%32 and flips tile Y
// when sy >= 16. Screen copies the selected page scrolled by -scroll.
//
// Pixel X and Y are the same logical coordinates used by the working
// foreground. The tile ROM uses 512 x 32 bytes per plane (3 planes).
// -----------------------------------------------------------------------------

module jtmm_bg (
    input  wire         clk,

    input  wire         cpu_cen,
    input  wire         cpu_we,
    input  wire [10:0]  cpu_addr,
    input  wire [7:0]   cpu_din,
    output reg  [7:0]   cpu_dout,

    input  wire [7:0]   page_select,
    input  wire [7:0]   scroll,
    input  wire [7:0]   pixel_x,
    input  wire [7:0]   pixel_y,

    output wire [13:0]  bg_rom_addr,
    input  wire [7:0]   bg_plane0,
    input  wire [7:0]   bg_plane1,
    input  wire [7:0]   bg_plane2,

    output wire [2:0]   pen,
    output wire [1:0]   color,
    output wire         valid
);

    reg [7:0] tile0 [0:511];
    reg [7:0] attr0 [0:511];
    reg [7:0] tile1 [0:511];
    reg [7:0] attr1 [0:511];

    // Address is reversed in column order, matching MAME's sx=15-offs/32.
    // Logical source scroll wraps in the 512-line virtual bitmap.
    wire [8:0] scroll_y = {1'b0, pixel_y} + {1'b0, scroll};
    wire [3:0] tile_x = pixel_x[7:4];
    wire [4:0] tile_y = scroll_y[8:4];
    wire [8:0] video_addr = {~tile_x, tile_y};

    reg [7:0] video_code;
    reg [7:0] video_attr;

    // Both CPU and video ports have an entire 1.5/6 MHz bus cycle to settle.
    always @(posedge clk) begin
        if (page_select[0]) begin
            video_code <= tile1[video_addr];
            video_attr <= attr1[video_addr];
        end else begin
            video_code <= tile0[video_addr];
            video_attr <= attr0[video_addr];
        end

        case (cpu_addr[10:9])
            2'b00: cpu_dout <= tile0[cpu_addr[8:0]];
            2'b01: cpu_dout <= attr0[cpu_addr[8:0]];
            2'b10: cpu_dout <= tile1[cpu_addr[8:0]];
            2'b11: cpu_dout <= attr1[cpu_addr[8:0]];
        endcase

        if (cpu_cen && cpu_we) begin
            case (cpu_addr[10:9])
                2'b00: tile0[cpu_addr[8:0]] <= cpu_din;
                2'b01: attr0[cpu_addr[8:0]] <= cpu_din;
                2'b10: tile1[cpu_addr[8:0]] <= cpu_din;
                2'b11: attr1[cpu_addr[8:0]] <= cpu_din;
            endcase
        end
    end

    // 512 background tiles, bank bit supplied by attribute bit 3.
    wire [8:0] bg_code = {video_attr[3], video_code};

    // MAME flips Y for the second half of the virtual playfield.
    wire [3:0] rom_y = scroll_y[8] ? ~scroll_y[3:0] : scroll_y[3:0];

    // MAME tilelayout X offsets are 16*8+0..7, 0..7.
    // The first 8 screen pixels use the second 16-byte row group.
    wire rom_half = ~pixel_x[3];
    assign bg_rom_addr = {bg_code, rom_half, rom_y};

    // Consistent with the working foreground ROM pixel orientation.
    assign pen = {
        bg_plane2[~pixel_x[2:0]],
        bg_plane1[~pixel_x[2:0]],
        bg_plane0[~pixel_x[2:0]]
    };

    assign color = video_attr[5:4];
    assign valid = 1'b1; // The background is opaque (including pen zero).

endmodule
