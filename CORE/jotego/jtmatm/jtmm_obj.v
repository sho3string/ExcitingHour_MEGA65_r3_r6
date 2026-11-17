// -----------------------------------------------------------------------------
// Exciting Hour / Mat Mania - 16x16 sprite renderer
//
// 24 entries x 4 bytes in write-only CPU sprite RAM at $0780-$07DF.
// 3584 sprite codes, 3 bitplanes x 112 KiB = 336 KiB ROM (0x54000).
// MAME order: later sprite entries overwrite earlier nonzero pixels.
//
// Sprite RAM is stored as four 32-deep byte arrays (attr, code, y, x),
// indexed by entry number. The CPU writes the live arrays. Once per frame
// (just before the first visible line) the 24 entries are copied into a
// shadow set which the line builder reads, so a CPU update that lands
// mid-frame can never tear a character across two animation frames.
//
// One 256-pixel line buffer is cleared and rebuilt during horizontal blank.
// At 48 MHz, the blank interval is 128 * 8 = 1024 clocks; the scan needs
// <= 256 + 24*(6 + 16 + 1) = 808 clocks, without ROM port duplication.
// The ROM has a synchronous 48 MHz read port per bitplane.
// -----------------------------------------------------------------------------

module jtmm_obj (
    input  wire         clk,
    input  wire         reset,
    input  wire         cen6,
    input  wire [8:0]   H,
    input  wire [8:0]   vdump,
    input  wire [7:0]   pixel_x,

    input  wire         cpu_we,
    input  wire [6:0]   cpu_addr,
    input  wire [7:0]   cpu_din,

    output reg  [16:0]  obj_rom_addr,
    input  wire [7:0]   obj_plane0,
    input  wire [7:0]   obj_plane1,
    input  wire [7:0]   obj_plane2,

    output wire [2:0]   pen,
    output wire         color,
    output wire         valid
);

    // ------------------------------------------------------------------
    // Live sprite RAM (CPU write side) and per-frame shadow (render side).
    // One array per byte lane keeps every array single-write / single-read,
    // which maps directly onto distributed RAM with no feedback logic.
    // ------------------------------------------------------------------
    (* ram_style = "distributed" *) reg [7:0] ram_attr [0:31];
    (* ram_style = "distributed" *) reg [7:0] ram_code [0:31];
    (* ram_style = "distributed" *) reg [7:0] ram_y    [0:31];
    (* ram_style = "distributed" *) reg [7:0] ram_x    [0:31];

    (* ram_style = "distributed" *) reg [7:0] shd_attr [0:31];
    (* ram_style = "distributed" *) reg [7:0] shd_code [0:31];
    (* ram_style = "distributed" *) reg [7:0] shd_y    [0:31];
    (* ram_style = "distributed" *) reg [7:0] shd_x    [0:31];

    // CPU address $0780 + n: n[1:0] selects the byte lane, n[6:2] the entry.
    wire [4:0] cpu_entry = cpu_addr[6:2];

    always @(posedge clk) begin
        if (cpu_we) begin
            case (cpu_addr[1:0])
                2'd0: ram_attr[cpu_entry] <= cpu_din;
                2'd1: ram_code[cpu_entry] <= cpu_din;
                2'd2: ram_y   [cpu_entry] <= cpu_din;
                2'd3: ram_x   [cpu_entry] <= cpu_din;
            endcase
        end
    end

    // Snapshot at the start of the last blanked line before the picture
    // (same point used for the background scroll latch), 24 clocks long.
    reg       copying  = 1'b0;
    reg [4:0] copy_idx = 5'd0;

    always @(posedge clk) begin
        if (reset) begin
            copying <= 1'b0;
        end else if (cen6 && H == 9'd0 && vdump == 9'd11) begin
            copying  <= 1'b1;
            copy_idx <= 5'd0;
        end else if (copying) begin
            shd_attr[copy_idx] <= ram_attr[copy_idx];
            shd_code[copy_idx] <= ram_code[copy_idx];
            shd_y   [copy_idx] <= ram_y   [copy_idx];
            shd_x   [copy_idx] <= ram_x   [copy_idx];
            if (copy_idx == 5'd23)
                copying <= 1'b0;
            else
                copy_idx <= copy_idx + 5'd1;
        end
    end

    // Per-pixel line buffer: {valid, palette_group, pen[2:0]}.
    reg [4:0] linebuf [0:255];
    wire [4:0] linepixel = linebuf[pixel_x];
    assign valid = linepixel[4];
    assign color = linepixel[3];
    assign pen   = linepixel[2:0];

    localparam [3:0] IDLE    = 4'd0;
    localparam [3:0] CLEAR   = 4'd1;
    localparam [3:0] NEXT    = 4'd2;
    localparam [3:0] FETCH_L = 4'd3;
    localparam [3:0] WAIT_L  = 4'd4;
    localparam [3:0] LATCH_L = 4'd5;
    localparam [3:0] FETCH_R = 4'd6;
    localparam [3:0] WAIT_R  = 4'd7;
    localparam [3:0] LATCH_R = 4'd8;
    localparam [3:0] DRAW    = 4'd9;

    reg [3:0] state = IDLE;
    reg [7:0] clear_x = 8'd0;
    reg [4:0] sprite_index = 5'd0;
    reg [4:0] draw_x = 5'd0;
    reg [7:0] line_y = 8'd0;
    reg [3:0] sprite_row = 4'd0;
    reg [11:0] sprite_code = 12'd0;
    reg [7:0] sprite_sx_byte;
    reg sprite_flipx;
    reg sprite_color;

    reg [7:0] l0, l1, l2;
    reg [7:0] r0, r1, r2;

    wire [7:0] spr_attr = shd_attr[sprite_index];
    wire [7:0] spr_code = shd_code[sprite_index];
    wire [7:0] spr_y    = shd_y   [sprite_index];
    wire [7:0] spr_x    = shd_x   [sprite_index];

    wire [7:0] sprite_sy = 8'd240 - spr_y;
    wire [7:0] sprite_dy = line_y - sprite_sy;
    wire [11:0] raw_sprite_code = {spr_attr[7:4], spr_code};
    wire [11:0] bounded_sprite_code =
        (raw_sprite_code >= 12'd3584) ? (raw_sprite_code - 12'd3584) : raw_sprite_code;

    // sx = 239 - sprram[offset+3]; values can be negative.
    wire signed [9:0] sprite_sx = $signed({2'b00, 8'd239}) -
                                  $signed({2'b00, sprite_sx_byte});
    wire signed [9:0] dest_x = sprite_sx + $signed({5'b00000, draw_x});
    wire [3:0] gfx_x = sprite_flipx ? (4'd15 - draw_x[3:0]) : draw_x[3:0];
    wire [7:0] gfx_byte0 = gfx_x[3] ? r0 : l0;
    wire [7:0] gfx_byte1 = gfx_x[3] ? r1 : l1;
    wire [7:0] gfx_byte2 = gfx_x[3] ? r2 : l2;
    wire [2:0] gfx_pen = {
        gfx_byte2[~gfx_x[2:0]],
        gfx_byte1[~gfx_x[2:0]],
        gfx_byte0[~gfx_x[2:0]]
    };

    // At the beginning of horizontal blank, construct the *next* visible
    // scanline. jtframe_vtimer advances V during H blank, after H=320.
    wire [7:0] next_line_y = vdump[7:0] - 8'd11;

    always @(posedge clk) begin
        if (reset) begin
            state        <= IDLE;
            clear_x      <= 8'd0;
            sprite_index <= 5'd0;
            draw_x       <= 5'd0;
            obj_rom_addr <= 17'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (cen6 && H == 9'd320) begin
                        line_y  <= next_line_y;
                        clear_x <= 8'd0;
                        state   <= CLEAR;
                    end
                end

                CLEAR: begin
                    linebuf[clear_x] <= 5'd0;
                    if (clear_x == 8'd255) begin
                        sprite_index <= 5'd0;
                        state <= NEXT;
                    end else begin
                        clear_x <= clear_x + 8'd1;
                    end
                end

                NEXT: begin
                    if (sprite_index >= 5'd24) begin
                        state <= IDLE;
                    end else if (spr_attr[0] && sprite_dy < 8'd16) begin
                        sprite_code    <= bounded_sprite_code;
                        sprite_row     <= spr_attr[1] ? (4'd15 - sprite_dy[3:0]) : sprite_dy[3:0];
                        sprite_sx_byte <= spr_x;
                        sprite_flipx   <= spr_attr[2];
                        sprite_color   <= spr_attr[3];
                        state          <= FETCH_L;
                    end else begin
                        sprite_index <= sprite_index + 5'd1;
                    end
                end

                FETCH_L: begin
                    obj_rom_addr <= {sprite_code, 1'b1, sprite_row};
                    state <= WAIT_L;
                end
                WAIT_L: begin
                    state <= LATCH_L;
                end
                LATCH_L: begin
                    l0 <= obj_plane0;
                    l1 <= obj_plane1;
                    l2 <= obj_plane2;
                    state <= FETCH_R;
                end
                FETCH_R: begin
                    obj_rom_addr <= {sprite_code, 1'b0, sprite_row};
                    state <= WAIT_R;
                end
                WAIT_R: begin
                    state <= LATCH_R;
                end
                LATCH_R: begin
                    r0 <= obj_plane0;
                    r1 <= obj_plane1;
                    r2 <= obj_plane2;
                    draw_x <= 5'd0;
                    state <= DRAW;
                end
                DRAW: begin
                    if (dest_x >= 0 && dest_x < 256 && gfx_pen != 3'b000)
                        linebuf[dest_x[7:0]] <= {1'b1, sprite_color, gfx_pen};

                    if (draw_x == 5'd15) begin
                        sprite_index <= sprite_index + 5'd1;
                        state <= NEXT;
                    end else begin
                        draw_x <= draw_x + 5'd1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule