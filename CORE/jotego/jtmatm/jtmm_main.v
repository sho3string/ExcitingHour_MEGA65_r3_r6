// -----------------------------------------------------------------------------
// Exciting Hour / Mat Mania - main 6502 and memory map (Stage 5)
//
// CPU: MiST T65 in NMOS 6502 mode, 1.5 MHz enable.
// ROM: e29 + e28 + e27, contiguous CPU $4000-$FFFF (48 KiB).
// All memory is accessed in the 48 MHz system domain; read data has
// an entire CPU cycle to settle before T65 samples it.
// -----------------------------------------------------------------------------

module jtmm_main (
    input  wire         clk,
    input  wire         reset,
    input  wire         cen1p5,

    input  wire         frame_irq,
    input  wire [7:0]   in0,
    input  wire [7:0]   in1,
    input  wire [7:0]   dsw1,
    input  wire [7:0]   dsw2,

    output wire [15:0]  rom_addr,
    input  wire [7:0]   rom_data,

    output wire         fg_cpu_cen,
    output wire         fg_cpu_we,
    output wire [10:0]  fg_cpu_addr,
    output wire [7:0]   fg_cpu_din,
    input  wire [7:0]   fg_cpu_dout,

    // CPU background tile/attribute RAM: $2000-$27FF.
    output wire         bg_cpu_cen,
    output wire         bg_cpu_we,
    output wire [10:0]  bg_cpu_addr,
    output wire [7:0]   bg_cpu_din,
    input  wire [7:0]   bg_cpu_dout,

    // CPU sprite RAM: $0780-$07DF, 24 entries of 4 bytes.
    output wire         obj_cpu_we,
    output wire [6:0]   obj_cpu_addr,
    output wire [7:0]   obj_cpu_din,

    // Video controls.
    output wire [7:0]   page_select_o,
    output wire [7:0]   scroll_o,

    // CPU $3050-$307F sprite palette writes to jtmm_colmix.
    output wire         pal_we,
    output wire [5:0]   pal_addr,
    output wire [7:0]   pal_din,

    output wire         sound_cmd_we,
    output wire [7:0]   sound_cmd_data,

    output wire [15:0]  debug_pc,
    output wire         debug_jam
);

    wire [15:0] cpu_addr;
    wire [7:0]  cpu_dout;
    reg  [7:0]  cpu_din;
    wire        cpu_rw_n;
    wire        cpu_sync;
    wire        cpu_vp_n;
    reg         irq_pending = 1'b0;

    jtmm_t65 u_cpu (
        .clk        (clk),
        .cen        (cen1p5),
        .rst_n      (~reset),
        .rdy        (1'b1),
        .irq_n      (~irq_pending),
        .nmi_n      (1'b1),
        .so_n       (1'b1),
        .addr       (cpu_addr),
        .din        (cpu_din),
        .dout       (cpu_dout),
        .rw_n       (cpu_rw_n),
        .sync       (cpu_sync),
        .vp_n       (cpu_vp_n),
        .debug_pc   (debug_pc)
    );

    // T65 has no JAM diagnostic output.
    assign debug_jam = 1'b0;

    // Commit writes on the CPU enable. The active bus address, data and
    // R/W are presented throughout the cycle for 48 MHz BRAM access.
    wire cpu_write = cen1p5 && !cpu_rw_n && !reset;
    assign sound_cmd_we   = cpu_write && (cpu_addr == 16'h3010);
    assign sound_cmd_data = cpu_dout;

    // Original sprite palette: 48 write-only bytes (16 R + 16 G + 16 B).
    // Drive the mixer directly; no duplicate RAM is needed in the CPU module.
    assign pal_we   = cpu_write && (cpu_addr >= 16'h3050) &&
                                   (cpu_addr <= 16'h307f);
    assign pal_addr = cpu_addr[5:0] - 6'h10;
    assign pal_din  = cpu_dout;

    // ROM is downloaded as a 48 KiB file into a BRAM whose address
    // zero corresponds to CPU $4000. ROM data is clocked at 48 MHz.
    assign rom_addr    = cpu_addr - 16'h4000;
    assign fg_cpu_cen  = cen1p5;
    assign fg_cpu_we   = !cpu_rw_n && !reset && (cpu_addr[15:11] == 5'b00010);
    assign fg_cpu_addr = cpu_addr[10:0];
    assign fg_cpu_din  = cpu_dout;

    assign bg_cpu_cen  = cen1p5;
    assign bg_cpu_we   = !cpu_rw_n && !reset && (cpu_addr[15:11] == 5'b00100);
    assign bg_cpu_addr = cpu_addr[10:0];
    assign bg_cpu_din  = cpu_dout;

    assign obj_cpu_we   = cpu_write && (cpu_addr >= 16'h0780) &&
                                       (cpu_addr <= 16'h07df);
    assign obj_cpu_addr = cpu_addr[6:0];
    assign obj_cpu_din  = cpu_dout;
    assign page_select_o = page_select;
    assign scroll_o = scroll;

    // Work RAM: $0000-$077F. Sprite RAM $0780-$07DF is write-only
    // on the original PCB. Allocate the full 2 KiB so write timing
    // and later sprite integration can reuse the same backing RAM.
    reg [7:0] work_ram [0:2047];
    reg [7:0] work_q;

    // Background memory is now implemented in jtmm_bg.v.
    // This preserves CPU-visible read/write behaviour and allows video reads.

    reg [7:0] page_select = 8'd0;
    reg [7:0] scroll = 8'd0;

    always @(posedge clk) begin
        // Read during each 48 MHz cycle, not only on cen1p5.
        work_q <= work_ram[cpu_addr[10:0]];

        if (reset) begin
            page_select <= 8'd0;
            scroll      <= 8'd0;
        end else if (cpu_write) begin
            if (cpu_addr <= 16'h07df)
                work_ram[cpu_addr[10:0]] <= cpu_dout;

            case (cpu_addr)
                16'h3000: page_select <= cpu_dout;
                16'h3020: scroll      <= cpu_dout;
                default:  ;
            endcase
        end
    end

    // Keep IRQ pending until the CPU fetches its IRQ/BRK vector.
    // T65 provides vp_n (low on vector reads) for this purpose.
    always @(posedge clk) begin
        if (reset)
            irq_pending <= 1'b0;
        else if (frame_irq)
            irq_pending <= 1'b1;
        else if (cen1p5 && !cpu_vp_n && cpu_addr == 16'hfffe)
            irq_pending <= 1'b0;
    end

    // DIP banks now come from jtmm_dip through jtmm_game.
    // DSW1 bit 7 remains the live CPU VBlank signal.

    always @* begin
        cpu_din = 8'hff;

        if (cpu_addr <= 16'h077f)
            cpu_din = work_q;
        else if (cpu_addr >= 16'h1000 && cpu_addr <= 16'h17ff)
            cpu_din = fg_cpu_dout;
        else if (cpu_addr >= 16'h2000 && cpu_addr <= 16'h27ff)
            cpu_din = bg_cpu_dout;
        else if (cpu_addr >= 16'h4000)
            cpu_din = rom_data;
        else begin
            case (cpu_addr)
                16'h3000: cpu_din = in0;
                16'h3010: cpu_din = in1;
                16'h3020: cpu_din = dsw2;
                16'h3030: cpu_din = dsw1;
                default:  cpu_din = 8'hff;
            endcase
        end
    end

endmodule
