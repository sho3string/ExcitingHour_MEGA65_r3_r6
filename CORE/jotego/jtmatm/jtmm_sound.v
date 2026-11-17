// -----------------------------------------------------------------------------
// Exciting Hour / Mat Mania sound CPU and sound register bus.
//
// MiST T65 (NMOS 6502 mode), 1.2 MHz enable from 48 MHz / 40.
// 0x0000-0x01ff : sound work RAM
// 0x2000       : AY1 data write; 0x2001 AY1 address write
// 0x2002       : AY2 data write; 0x2003 AY2 address write
// 0x2004       : 8-bit DAC write
// 0x2007       : sound latch read, clears pending IRQ
// 0x8000-0xffff : program ROM k4-0 then k5-0 (32 KiB)
//
// PSG bus writes are sampled at 48 MHz independently of the tone-generator
// clock enable. Strobe each write on the ending edge of the sound CPU cycle.
// cen1p5 remains on the port for compatibility; only the AY tone generators
// use it, in main.vhd.
// -----------------------------------------------------------------------------
module jtmm_sound (
    input  wire         clk,
    input  wire         reset,
    input  wire         cen1p2,
    input  wire         cen1p5,
    input  wire         cmd_we,
    input  wire [7:0]   cmd_data,
    output wire [14:0]  rom_addr,
    input  wire [7:0]   rom_data,
    output wire         ay1_wr,
    output wire         ay1_addr_mode,
    output wire [7:0]   ay1_din,
    output wire         ay2_wr,
    output wire         ay2_addr_mode,
    output wire [7:0]   ay2_din,
    output wire signed [15:0] dac_pcm,
    output wire [15:0]  debug_pc,
    output wire         debug_jam
);
    wire [15:0] cpu_addr;
    wire [7:0]  cpu_dout;
    reg  [7:0]  cpu_din;
    wire        cpu_rw_n;
    wire        cpu_sync;
    wire        cpu_vp_n;

    reg  [7:0]  cmd_latch = 8'd0;
    reg         cmd_pending = 1'b0;
    reg  [7:0]  dac_data = 8'h80;
    reg         nmi_pulse = 1'b0;
    reg  [20:0] nmi_accum = 21'd0;

    // MAME models a periodic sound NMI at 15 * 60 = 900 Hz.
    // Accumulate at the 1.2 MHz CPU enable to obtain an exact average 900 Hz.
    always @(posedge clk) begin
        if (reset) begin
            nmi_accum <= 21'd0;
            nmi_pulse <= 1'b0;
        end else if (cen1p2) begin
            nmi_pulse <= 1'b0;
            if (nmi_accum >= 21'd1199100) begin
                nmi_accum <= nmi_accum - 21'd1199100;
                nmi_pulse <= 1'b1;
            end else begin
                nmi_accum <= nmi_accum + 21'd900;
            end
        end
    end

    jtmm_t65 u_cpu (
        .clk        (clk),
        .cen        (cen1p2),
        .rst_n      (~reset),
        .rdy        (1'b1),
        .irq_n      (~cmd_pending),
        .nmi_n      (~nmi_pulse),
        .so_n       (1'b1),
        .addr       (cpu_addr),
        .din        (cpu_din),
        .dout       (cpu_dout),
        .rw_n       (cpu_rw_n),
        .sync       (cpu_sync),
        .vp_n       (cpu_vp_n),
        .debug_pc   (debug_pc)
    );

    // T65 does not export a JAM status signal.
    assign debug_jam = 1'b0;

    wire write_cycle = cen1p2 && !cpu_rw_n && !reset;
    wire latch_read = cen1p2 && cpu_rw_n && (cpu_addr == 16'h2007);
    assign rom_addr = cpu_addr[14:0];

    reg [7:0] ram [0:511];
    reg [7:0] ram_q;
    always @(posedge clk) begin
        ram_q <= ram[cpu_addr[8:0]];
        if (write_cycle && cpu_addr <= 16'h01ff)
            ram[cpu_addr[8:0]] <= cpu_dout;
    end

    always @* begin
        cpu_din = 8'hff;
        if (cpu_addr <= 16'h01ff)
            cpu_din = ram_q;
        else if (cpu_addr == 16'h2007)
            cpu_din = cmd_latch;
        else if (cpu_addr >= 16'h8000)
            cpu_din = rom_data;
    end

    // The JT49 bus interface samples writes at the 48 MHz clock.
    // The PSG tone/noise/envelope clock enable remains separate.
    assign ay1_wr        = write_cycle && (cpu_addr == 16'h2000 || cpu_addr == 16'h2001);
    assign ay1_addr_mode = cpu_addr[0];
    assign ay1_din       = cpu_dout;
    assign ay2_wr        = write_cycle && (cpu_addr == 16'h2002 || cpu_addr == 16'h2003);
    assign ay2_addr_mode = cpu_addr[0];
    assign ay2_din       = cpu_dout;

    always @(posedge clk) begin
        if (reset) begin
            cmd_latch <= 8'd0;
            cmd_pending <= 1'b0;
            dac_data <= 8'h80;
        end else begin
            if (latch_read)
                cmd_pending <= 1'b0;
            if (cmd_we) begin
                cmd_latch <= cmd_data;
                cmd_pending <= 1'b1;
            end

            if (write_cycle && cpu_addr == 16'h2004)
                dac_data <= cpu_dout;
        end
    end

    wire signed [8:0] dac_centered = $signed({1'b0, dac_data}) - 9'sd128;
    assign dac_pcm = {dac_centered, 7'b0};
endmodule
