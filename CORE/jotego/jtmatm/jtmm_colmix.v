// -----------------------------------------------------------------------------
// Exciting Hour / Mat Mania - original colour hardware (Stage 6)
//
//   PROM colours  0..31: 8 foreground pens x 4 colour groups
//   PROM colours 32..63: 8 background pens x 4 colour groups
//   RAM colours  64..79: 8 sprite pens x 2 colour groups
//
// The 64x12-bit RGB444 lookup table is generated FROM THE USER'S OWN MAME
// PROM ROMs by build_matmania_palette.py. It is a Vivado memory-init file,
// not a new M2M SD-card ROM device. No proprietary data is bundled here.
//
// Priority: foreground nonzero > sprite nonzero > background > black.
// At this stage bg_valid and obj_valid are tied low in jtmm_video.v.
// -----------------------------------------------------------------------------

module jtmm_colmix (
    input  wire         clk,
    input  wire         reset,
    input  wire         video_on,

    input  wire [2:0]   fg_pen,
    input  wire [1:0]   fg_color,
    input  wire         fg_opaque,

    input  wire         bg_valid,
    input  wire [2:0]   bg_pen,
    input  wire [1:0]   bg_color,

    input  wire         obj_valid,
    input  wire [2:0]   obj_pen,
    input  wire         obj_color,

    input  wire         pal_we,
    input  wire [5:0]   pal_addr,
    input  wire [7:0]   pal_din,

    output reg  [3:0]   red,
    output reg  [3:0]   green,
    output reg  [3:0]   blue
);

    // Each line in jtmm_palette.mem holds one RGB444 value, red first.
    // Generated from the four original 32-byte colour PROMs.
    reg [11:0] prom_rgb [0:63];

    initial begin
        $readmemh("jtmm_palette.mem", prom_rgb);
    end

    wire [5:0] fg_index = {1'b0, fg_color, fg_pen};
    wire [5:0] bg_index = {1'b1, bg_color, bg_pen};

    wire [11:0] fg_rgb = prom_rgb[fg_index];
    wire [11:0] bg_rgb = prom_rgb[bg_index];

    // The RAM palette uses the same 0E/1F/43/8F resistor weights as
    // the PROM channels. Convert a written 4-bit component to RGB444.
    function [3:0] weighted4;
        input [3:0] bits;
        reg [7:0] intensity;
        begin
            intensity = (bits[0] ? 8'h0E : 8'h00) +
                        (bits[1] ? 8'h1F : 8'h00) +
                        (bits[2] ? 8'h43 : 8'h00) +
                        (bits[3] ? 8'h8F : 8'h00);
            weighted4 = intensity[7:4];
        end
    endfunction

    // CPU writes $3050-$305F red, $3060-$306F green,
    // $3070-$307F blue. Only the bottom four bits are colour data.
    reg [3:0] sprite_r [0:15];
    reg [3:0] sprite_g [0:15];
    reg [3:0] sprite_b [0:15];

    always @(posedge clk) begin
        if (pal_we) begin
            case (pal_addr[5:4])
                2'd0: sprite_r[pal_addr[3:0]] <= weighted4(pal_din[3:0]);
                2'd1: sprite_g[pal_addr[3:0]] <= weighted4(pal_din[3:0]);
                2'd2: sprite_b[pal_addr[3:0]] <= weighted4(pal_din[3:0]);
                default: ;
            endcase
        end
    end

    wire [3:0] obj_index = {obj_color, obj_pen};
    wire [11:0] obj_rgb = {
        sprite_r[obj_index],
        sprite_g[obj_index],
        sprite_b[obj_index]
    };

    reg [11:0] rgb;

    always @* begin
        rgb = 12'h000;
        if (!reset && video_on) begin
            if (fg_opaque)
                rgb = fg_rgb;
            else if (obj_valid && (|obj_pen))
                rgb = obj_rgb;
            else if (bg_valid)
                rgb = bg_rgb;
        end

        red   = rgb[11:8];
        green = rgb[7:4];
        blue  = rgb[3:0];
    end

endmodule
