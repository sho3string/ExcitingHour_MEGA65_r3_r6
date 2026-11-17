----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Wrapper for the MiSTer core that runs exclusively in the core's clock domanin
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_modes_pkg.all;
use work.globals.all;
library xpm;
use xpm.vcomponents.all;

    
entity main is
   generic (
      G_VDNUM                 : natural                     -- amount of virtual drives
   );
   port (
      clk_main_i              : in  std_logic;
      clk24_i                 : in  std_logic;
      reset_soft_i            : in  std_logic;
      reset_hard_i            : in  std_logic;
      pause_i                 : in  std_logic;

      -- MiSTer core main clock speed:
      -- Make sure you pass very exact numbers here, because they are used for avoiding clock drift at derived clocks
      clk_main_speed_i        : in  natural;

      -- Video output
      video_ce_o              : out std_logic;
      video_ce_ovl_o          : out std_logic;
      video_red_o             : out std_logic_vector(3 downto 0);
      video_green_o           : out std_logic_vector(3 downto 0);
      video_blue_o            : out std_logic_vector(3 downto 0);
      video_vs_o              : out std_logic;
      video_hs_o              : out std_logic;
      video_hblank_o          : out std_logic;
      video_vblank_o          : out std_logic;

      -- Audio output (Signed PCM)
      audio_left_o            : out signed(15 downto 0);
      audio_right_o           : out signed(15 downto 0);

      -- M2M Keyboard interface
      kb_key_num_i            : in  integer range 0 to 79;    -- cycles through all MEGA65 keys
      kb_key_pressed_n_i      : in  std_logic;                -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- MEGA65 joysticks and paddles/mouse/potentiometers
      joy_1_up_n_i            : in  std_logic;
      joy_1_down_n_i          : in  std_logic;
      joy_1_left_n_i          : in  std_logic;
      joy_1_right_n_i         : in  std_logic;
      joy_1_fire_n_i          : in  std_logic;

      joy_2_up_n_i            : in  std_logic;
      joy_2_down_n_i          : in  std_logic;
      joy_2_left_n_i          : in  std_logic;
      joy_2_right_n_i         : in  std_logic;
      joy_2_fire_n_i          : in  std_logic;

      pot1_x_i                : in  std_logic_vector(7 downto 0);
      pot1_y_i                : in  std_logic_vector(7 downto 0);
      pot2_x_i                : in  std_logic_vector(7 downto 0);
      pot2_y_i                : in  std_logic_vector(7 downto 0);
      
       -- ROM download bus from QNICE
      dn_clk_i                : in  std_logic;
      dn_addr_i               : in  std_logic_vector(24 downto 0);
      dn_data_i               : in  std_logic_vector(7 downto 0);
      dn_wr_i                 : in  std_logic;
      
      osm_control_i           : in  std_logic_vector(255 downto 0)
   );
end entity main;

architecture synthesis of main is

-- JTFRAME clock enables, derived from the existing 48 MHz clock.
signal cen12             : std_logic;
signal cen8              : std_logic;
signal cen6              : std_logic;
signal cen3              : std_logic;
signal cen1p5            : std_logic;
signal cen1p2            : std_logic;
signal cen1p2_count      : integer range 0 to 39 := 0;

signal reset             : std_logic;

-- Mat Mania character ROMs: three 8 KiB bitplanes, no graphics pre-sorting.
signal char_row_addr     : std_logic_vector(12 downto 0);
signal char_plane0       : std_logic_vector(7 downto 0);
signal char_plane1       : std_logic_vector(7 downto 0);
signal char_plane2       : std_logic_vector(7 downto 0);

signal dn_char0_we       : std_logic;
signal dn_char1_we       : std_logic;
signal dn_char2_we       : std_logic;

signal main_rom_addr     : std_logic_vector(15 downto 0);
signal main_rom_data     : std_logic_vector(7 downto 0);
signal dn_main_we        : std_logic;
signal dn_main_addr      : std_logic_vector(15 downto 0);
signal sound_rom_addr    : std_logic_vector(14 downto 0);
signal sound_rom_data    : std_logic_vector(7 downto 0);
signal dn_sound_we       : std_logic;
signal dn_sound_addr     : std_logic_vector(14 downto 0);
signal ay1_wr            : std_logic;
signal ay1_addr_mode     : std_logic;
signal ay1_din           : std_logic_vector(7 downto 0);
signal ay2_wr            : std_logic;
signal ay2_addr_mode     : std_logic;
signal ay2_din           : std_logic_vector(7 downto 0);
signal dac_pcm           : signed(15 downto 0);
signal ay1_raw           : std_logic_vector(9 downto 0);
signal ay2_raw           : std_logic_vector(9 downto 0);
signal ay1_pcm           : signed(15 downto 0);
signal ay2_pcm           : signed(15 downto 0);
signal mm_audio          : signed(15 downto 0);
signal in0               : std_logic_vector(7 downto 0);
signal p1_game_n         : std_logic_vector(5 downto 0);
signal in1               : std_logic_vector(7 downto 0);
signal dip_sw1           : std_logic_vector(7 downto 0);
signal dip_sw2           : std_logic_vector(7 downto 0);
signal keyboard_n        : std_logic_vector(79 downto 0);
signal joy1_n            : std_logic_vector(4 downto 0);
signal joy2_n            : std_logic_vector(4 downto 0);
signal p1_joy_n          : std_logic_vector(4 downto 0);
signal p2_joy_n          : std_logic_vector(4 downto 0);
signal pot1_val          : std_logic_vector(7 downto 0);
signal pot2_val          : std_logic_vector(7 downto 0);
signal pot1_button_n     : std_logic;
signal pot2_button_n     : std_logic;
signal p1_button2_n      : std_logic;
signal p2_button2_n      : std_logic;

-- Exciting Hour background ROM (3 x 16 KiB) and sprite ROM (3 x 112 KiB).
signal bg_rom_addr       : std_logic_vector(13 downto 0);
signal bg_plane0         : std_logic_vector(7 downto 0);
signal bg_plane1         : std_logic_vector(7 downto 0);
signal bg_plane2         : std_logic_vector(7 downto 0);
signal obj_rom_addr      : std_logic_vector(16 downto 0);
signal obj_plane0        : std_logic_vector(7 downto 0);
signal obj_plane1        : std_logic_vector(7 downto 0);
signal obj_plane2        : std_logic_vector(7 downto 0);
signal dn_bg0_we         : std_logic;
signal dn_bg1_we         : std_logic;
signal dn_bg2_we         : std_logic;
signal dn_obj0_we        : std_logic;
signal dn_obj1_we        : std_logic;
signal dn_obj2_we        : std_logic;
signal dn_bg0_addr       : std_logic_vector(13 downto 0);
signal dn_bg1_addr       : std_logic_vector(13 downto 0);
signal dn_bg2_addr       : std_logic_vector(13 downto 0);
signal dn_obj0_addr      : std_logic_vector(16 downto 0);
signal dn_obj1_addr      : std_logic_vector(16 downto 0);
signal dn_obj2_addr      : std_logic_vector(16 downto 0);

-- Vivado requires component instantiation (not direct entity instantiation)
-- when a VHDL unit instantiates a Verilog module.
component jtmm_game is
    port (
        clk          : in  std_logic;
        reset        : in  std_logic;
        cen6         : in  std_logic;
        cen1p5       : in  std_logic;
        cen1p2       : in  std_logic;

        sound_rom_addr : out std_logic_vector(14 downto 0);
        sound_rom_data : in  std_logic_vector(7 downto 0);
        ay1_wr        : out std_logic;
        ay1_addr_mode : out std_logic;
        ay1_din       : out std_logic_vector(7 downto 0);
        ay2_wr        : out std_logic;
        ay2_addr_mode : out std_logic;
        ay2_din       : out std_logic_vector(7 downto 0);
        dac_pcm       : out signed(15 downto 0);

        in0          : in  std_logic_vector(7 downto 0);
        in1          : in  std_logic_vector(7 downto 0);
        sw1          : in  std_logic_vector(7 downto 0);
        sw2          : in  std_logic_vector(7 downto 0);

        main_rom_addr : out std_logic_vector(15 downto 0);
        main_rom_data : in  std_logic_vector(7 downto 0);

        char_addr    : out std_logic_vector(12 downto 0);
        char_plane0  : in  std_logic_vector(7 downto 0);
        char_plane1  : in  std_logic_vector(7 downto 0);
        char_plane2  : in  std_logic_vector(7 downto 0);

        bg_rom_addr  : out std_logic_vector(13 downto 0);
        bg_plane0    : in  std_logic_vector(7 downto 0);
        bg_plane1    : in  std_logic_vector(7 downto 0);
        bg_plane2    : in  std_logic_vector(7 downto 0);

        obj_rom_addr : out std_logic_vector(16 downto 0);
        obj_plane0   : in  std_logic_vector(7 downto 0);
        obj_plane1   : in  std_logic_vector(7 downto 0);
        obj_plane2   : in  std_logic_vector(7 downto 0);

        red          : out std_logic_vector(3 downto 0);
        green        : out std_logic_vector(3 downto 0);
        blue         : out std_logic_vector(3 downto 0);
        LHBL         : out std_logic;
        LVBL         : out std_logic;
        HS           : out std_logic;
        VS           : out std_logic
    );
end component jtmm_game;

-- JT49 AY-3-8910 bus interface by Jose Tejada (GPLv3+).
-- Original register/data strobes from jtmm_game are preserved.
component jt49_bus
   port (
      rst_n   : in  std_logic;
      clk     : in  std_logic;
      clk_en  : in  std_logic;
      bdir    : in  std_logic;
      bc1     : in  std_logic;
      din     : in  std_logic_vector(7 downto 0);
      sel     : in  std_logic;
      dout    : out std_logic_vector(7 downto 0);
      sound   : out std_logic_vector(9 downto 0);
      A       : out std_logic_vector(7 downto 0);
      B       : out std_logic_vector(7 downto 0);
      C       : out std_logic_vector(7 downto 0);
      sample  : out std_logic;
      IOA_in  : in  std_logic_vector(7 downto 0);
      IOA_out : out std_logic_vector(7 downto 0);
      IOA_oe  : out std_logic;
      IOB_in  : in  std_logic_vector(7 downto 0);
      IOB_out : out std_logic_vector(7 downto 0);
      IOB_oe  : out std_logic
   );
end component jt49_bus;

-- The same four-channel JTFRAME mixer interface used in Black Tiger.
component jtframe_mixer
   generic (
      W0   : integer := 16;
      W1   : integer := 16;
      W2   : integer := 16;
      W3   : integer := 16;
      WOUT : integer := 16
   );
   port (
      rst   : in  std_logic;
      clk   : in  std_logic;
      cen   : in  std_logic;
      ch0   : in  signed(W0-1 downto 0);
      ch1   : in  signed(W1-1 downto 0);
      ch2   : in  signed(W2-1 downto 0);
      ch3   : in  signed(W3-1 downto 0);
      gain0 : in  std_logic_vector(7 downto 0);
      gain1 : in  std_logic_vector(7 downto 0);
      gain2 : in  std_logic_vector(7 downto 0);
      gain3 : in  std_logic_vector(7 downto 0);
      mixed : out signed(WOUT-1 downto 0);
      peak  : out std_logic
   );
end component jtframe_mixer;

begin

    reset <= reset_soft_i or reset_hard_i;

    -- M2M native video: one pixel per 6 MHz enable.
    video_ce_o     <= cen6;
    video_ce_ovl_o <= '0';

    -- Exciting Hour: two 1.5 MHz AY-3-8910s and the existing 8-bit DAC.
    -- JT49 bus cycles: BDIR/BC1 = 11 address, 10 data, 00 inactive.
    -- Address and write strobes are generated by jtmm_game; no change there.
    i_ay1 : jt49_bus
    port map (
        rst_n   => not reset,
        clk     => clk_main_i,
        clk_en  => cen1p5,
        bdir    => ay1_wr,
        bc1     => ay1_wr and ay1_addr_mode,
        din     => ay1_din,
        sel     => '1',
        dout    => open,
        sound   => ay1_raw,
        A       => open,
        B       => open,
        C       => open,
        sample  => open,
        IOA_in  => x"FF",
        IOA_out => open,
        IOA_oe  => open,
        IOB_in  => x"FF",
        IOB_out => open,
        IOB_oe  => open
    );

    i_ay2 : jt49_bus
    port map (
        rst_n   => not reset,
        clk     => clk_main_i,
        clk_en  => cen1p5,
        bdir    => ay2_wr,
        bc1     => ay2_wr and ay2_addr_mode,
        din     => ay2_din,
        sel     => '1',
        dout    => open,
        sound   => ay2_raw,
        A       => open,
        B       => open,
        C       => open,
        sample  => open,
        IOA_in  => x"FF",
        IOA_out => open,
        IOA_oe  => open,
        IOB_in  => x"FF",
        IOB_out => open,
        IOB_oe  => open
    );

    -- JT49 produces 10-bit unsigned audio (up to 3 x 255).
    -- 12-bit unsigned sum (up to 3 x 1023). Gain shift +4 instead of +2.
    -- Do not subtract a DC offset: zero is the silent output level.
    ay1_pcm <= shift_left(resize(signed('0' & ay1_raw), 16), 4);
    ay2_pcm <= shift_left(resize(signed('0' & ay2_raw), 16), 4);

    i_mm_audio_mixer : jtframe_mixer
    generic map (
        W0   => 16,
        W1   => 16,
        W2   => 16,
        W3   => 16,
        WOUT => 16
    )
    port map (
        rst   => reset,
        clk   => clk_main_i,
        cen   => '1',
        ch0   => ay1_pcm,
        ch1   => ay2_pcm,
        ch2   => dac_pcm,
        ch3   => to_signed(0, 16),
        gain0 => x"20",
        gain1 => x"20",
        gain2 => x"80",
        gain3 => x"00",
        mixed => mm_audio,
        peak  => open
    );

    audio_left_o   <= mm_audio;
    audio_right_o  <= mm_audio;

    i_jtframe_cen48 : entity work.jtframe_cen48
    port map (
        clk     => clk_main_i,
        cen12   => cen12,
        cen8    => cen8,
        cen6    => cen6,
        cen3    => cen3,
        cen1p5  => cen1p5
    );

    -- Prepared for the sound 6502: 48 MHz / 40 = 1.2 MHz.
    process(clk_main_i)
    begin
        if rising_edge(clk_main_i) then
            cen1p2 <= '0';

            if reset = '1' then
                cen1p2_count <= 0;
            elsif cen1p2_count = 39 then
                cen1p2_count <= 0;
                cen1p2 <= '1';
            else
                cen1p2_count <= cen1p2_count + 1;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- DIP switches: OSD 1 = physical ON; jtmm_dip makes them active-low.
    -- SW1-8 is deliberately not wired to a DIP: it is CPU VBlank.
    ---------------------------------------------------------------------------
    dip_sw1 <= osm_control_i(C_MENU_SW1_7) &
               osm_control_i(C_MENU_SW1_6) &
               osm_control_i(C_MENU_SW1_5) &
               osm_control_i(C_MENU_SW1_4) &
               osm_control_i(C_MENU_SW1_3) &
               osm_control_i(C_MENU_SW1_2) &
               osm_control_i(C_MENU_SW1_1) &
               osm_control_i(C_MENU_SW1_0);

    dip_sw2 <= osm_control_i(C_MENU_SW2_7) &
               osm_control_i(C_MENU_SW2_6) &
               osm_control_i(C_MENU_SW2_5) &
               osm_control_i(C_MENU_SW2_4) &
               osm_control_i(C_MENU_SW2_3) &
               osm_control_i(C_MENU_SW2_2) &
               osm_control_i(C_MENU_SW2_1) &
               osm_control_i(C_MENU_SW2_0);

    ---------------------------------------------------------------------------
    -- MEGA65 keyboard / two-button controls, as on the 1943 M2M port.
    -- 1/2 = Start, 6/5 = Coin 1/2, Z = Button 1, X = Button 2.
    -- Cursor keys control P1. Joystick directions and fire are active-low.
    ---------------------------------------------------------------------------
    i_keyboard : entity work.keyboard
    port map (
        clk_main_i       => clk_main_i,
        key_num_i        => kb_key_num_i,
        key_pressed_n_i  => kb_key_pressed_n_i,
        example_n_o      => keyboard_n
    );

    joy1_n <= joy_1_fire_n_i & joy_1_down_n_i & joy_1_up_n_i &
              joy_1_left_n_i & joy_1_right_n_i;
    joy2_n <= joy_2_fire_n_i & joy_2_down_n_i & joy_2_up_n_i &
              joy_2_left_n_i & joy_2_right_n_i;

    p1_joy_n <= joy2_n when osm_control_i(C_FLIP_JOYS) = '1' else joy1_n;
    p2_joy_n <= joy1_n when osm_control_i(C_FLIP_JOYS) = '1' else joy2_n;

    -- OSD 0 = POTX, 1 = POTY. Each port has independent polarity.
    pot1_val <= pot1_x_i when osm_control_i(C_MENU_SECOND_FIRE_1) = '0' else pot1_y_i;
    pot2_val <= pot2_x_i when osm_control_i(C_MENU_SECOND_FIRE_2) = '0' else pot2_y_i;

    -- Polarity 1: active-low (< $80). Polarity 0: active-high (>= $80).
    pot1_button_n <= '0' when
        (osm_control_i(C_MENU_POTPOL_1) = '1' and unsigned(pot1_val) <  16#80#) or
        (osm_control_i(C_MENU_POTPOL_1) = '0' and unsigned(pot1_val) >= 16#80#)
        else '1';
    pot2_button_n <= '0' when
        (osm_control_i(C_MENU_POTPOL_2) = '1' and unsigned(pot2_val) <  16#80#) or
        (osm_control_i(C_MENU_POTPOL_2) = '0' and unsigned(pot2_val) >= 16#80#)
        else '1';

    p1_button2_n <= pot2_button_n when osm_control_i(C_FLIP_JOYS) = '1' else pot1_button_n;
    p2_button2_n <= pot1_button_n when osm_control_i(C_FLIP_JOYS) = '1' else pot2_button_n;

    -- Exclusive Player 1 controls, as in Oscar. Keyboard mode uses
    -- cursor keys + Z/X; joystick mode uses directions + Fire/POT.
    -- Both are active-low. Coin and Start remain keyboard controls.
    p1_game_n <= keyboard_n(23) &
                 keyboard_n(12) &
                 keyboard_n(7)  &
                 keyboard_n(73) &
                 keyboard_n(74) &
                 keyboard_n(2)
                 when osm_control_i(C_MENU_MODE_1) = '1' else
                 p1_button2_n & p1_joy_n;

    -- MAME $3000: coin1,coin2,button2,button1,down,up,left,right.
    in0 <= keyboard_n(19) & keyboard_n(16) & p1_game_n;

    -- MAME $3010: P2 right,left,up,down,button1,button2,start1,start2.
    in1 <= keyboard_n(59) &
           keyboard_n(56) &
           p2_button2_n &
           p2_joy_n(4) &
           p2_joy_n(3) &
           p2_joy_n(2) &
           p2_joy_n(1) &
           p2_joy_n(0);

    -- Main T65 at 1.5 MHz. Raster timing remains 384 x 264 / 59.185606 Hz.
    i_jtmm_game : jtmm_game
    port map (
        clk          => clk_main_i,
        reset        => reset,
        cen6         => cen6,
        cen1p5       => cen1p5,
        cen1p2       => cen1p2,

        sound_rom_addr => sound_rom_addr,
        sound_rom_data => sound_rom_data,
        ay1_wr        => ay1_wr,
        ay1_addr_mode => ay1_addr_mode,
        ay1_din       => ay1_din,
        ay2_wr        => ay2_wr,
        ay2_addr_mode => ay2_addr_mode,
        ay2_din       => ay2_din,
        dac_pcm       => dac_pcm,

        in0          => in0,
        in1          => in1,
        sw1          => dip_sw1,
        sw2          => dip_sw2,

        main_rom_addr => main_rom_addr,
        main_rom_data => main_rom_data,

        char_addr    => char_row_addr,
        char_plane0  => char_plane0,
        char_plane1  => char_plane1,
        char_plane2  => char_plane2,

        bg_rom_addr  => bg_rom_addr,
        bg_plane0    => bg_plane0,
        bg_plane1    => bg_plane1,
        bg_plane2    => bg_plane2,

        obj_rom_addr => obj_rom_addr,
        obj_plane0   => obj_plane0,
        obj_plane1   => obj_plane1,
        obj_plane2   => obj_plane2,

        red          => video_red_o,
        green        => video_green_o,
        blue         => video_blue_o,
        LHBL         => video_hblank_o,
        LVBL         => video_vblank_o,
        HS           => video_hs_o,
        VS           => video_vs_o
    );

    -- QNICE delivers the concatenated, unmodified three-plane ROM:
    -- $0000-$1FFF e30; $2000-$3FFF e31; $4000-$5FFF e32 (Exciting Hour).
    dn_char0_we <= dn_wr_i when unsigned(dn_addr_i) < 16#02000# else '0';
    dn_char1_we <= dn_wr_i when unsigned(dn_addr_i) >= 16#02000# and
                                unsigned(dn_addr_i) <  16#04000# else '0';
    dn_char2_we <= dn_wr_i when unsigned(dn_addr_i) >= 16#04000# and
                                unsigned(dn_addr_i) <  16#06000# else '0';

    -- A: 48 MHz synchronous read, B: QNICE falling-edge download write.
    i_rom_char_0 : entity work.dualport_2clk_ram
    generic map (
        ADDR_WIDTH => 13,
        DATA_WIDTH => 8,
        FALLING_A  => false,
        FALLING_B  => true
    )
    port map (
        clock_a    => clk_main_i,
        address_a  => char_row_addr,
        data_a     => (others => '0'),
        wren_a     => '0',
        q_a        => char_plane0,

        clock_b    => dn_clk_i,
        address_b  => dn_addr_i(12 downto 0),
        data_b     => dn_data_i,
        wren_b     => dn_char0_we,
        q_b        => open
    );

    i_rom_char_1 : entity work.dualport_2clk_ram
    generic map (
        ADDR_WIDTH => 13,
        DATA_WIDTH => 8,
        FALLING_A  => false,
        FALLING_B  => true
    )
    port map (
        clock_a    => clk_main_i,
        address_a  => char_row_addr,
        data_a     => (others => '0'),
        wren_a     => '0',
        q_a        => char_plane1,

        clock_b    => dn_clk_i,
        address_b  => dn_addr_i(12 downto 0),
        data_b     => dn_data_i,
        wren_b     => dn_char1_we,
        q_b        => open
    );

    i_rom_char_2 : entity work.dualport_2clk_ram
    generic map (
        ADDR_WIDTH => 13,
        DATA_WIDTH => 8,
        FALLING_A  => false,
        FALLING_B  => true
    )
    port map (
        clock_a    => clk_main_i,
        address_a  => char_row_addr,
        data_a     => (others => '0'),
        wren_a     => '0',
        q_a        => char_plane2,

        clock_b    => dn_clk_i,
        address_b  => dn_addr_i(12 downto 0),
        data_b     => dn_data_i,
        wren_b     => dn_char2_we,
        q_b        => open
    );

    -- Main program occupies CPU $4000-$FFFF (48 KiB). The SD card loader
    -- maps this ROM to QNICE download offsets $06000-$11FFF so it does not
    -- overlap the three character bitplane ROMs ($00000-$05FFF).
    dn_main_we <= dn_wr_i when unsigned(dn_addr_i) >= 16#06000# and
                               unsigned(dn_addr_i) <  16#12000# else '0';
    dn_main_addr <= std_logic_vector(
        resize(unsigned(dn_addr_i) - to_unsigned(16#06000#, dn_addr_i'length),
               dn_main_addr'length)
    );

    i_rom_main : entity work.dualport_2clk_ram
    generic map (
        ADDR_WIDTH => 16,
        DATA_WIDTH => 8,
        FALLING_A  => false,
        FALLING_B  => true
    )
    port map (
        clock_a    => clk_main_i,
        address_a  => main_rom_addr,
        data_a     => (others => '0'),
        wren_a     => '0',
        q_a        => main_rom_data,

        clock_b    => dn_clk_i,
        address_b  => dn_main_addr,
        data_b     => dn_data_i,
        wren_b     => dn_main_we,
        q_b        => open
    );

    -- QNICE offset layout, all files loaded independently:
    -- $00000-$05FFF CHAR (24 KiB)
    -- $06000-$11FFF MAIN (48 KiB)
    -- $12000-$1DFFF BG   (48 KiB)
    -- $1E000-$71FFF OBJ (336 KiB)
    -- Read ports run at 48 MHz; write ports run on the QNICE download clock.

    dn_bg0_we <= dn_wr_i when unsigned(dn_addr_i) >= 16#12000# and
                                    unsigned(dn_addr_i) <  16#16000# else '0';
    dn_bg0_addr <= std_logic_vector(
        resize(unsigned(dn_addr_i) - to_unsigned(16#12000#, dn_addr_i'length),
               dn_bg0_addr'length)
    );

    i_rom_bg_0 : entity work.dualport_2clk_ram
    generic map (
        ADDR_WIDTH => 14,
        DATA_WIDTH => 8,
        FALLING_A  => false,
        FALLING_B  => true
    )
    port map (
        clock_a   => clk_main_i,
        address_a => bg_rom_addr,
        data_a    => (others => '0'),
        wren_a    => '0',
        q_a       => bg_plane0,

        clock_b   => dn_clk_i,
        address_b => dn_bg0_addr,
        data_b    => dn_data_i,
        wren_b    => dn_bg0_we,
        q_b       => open
    );

    dn_bg1_we <= dn_wr_i when unsigned(dn_addr_i) >= 16#16000# and
                                    unsigned(dn_addr_i) <  16#1A000# else '0';
    dn_bg1_addr <= std_logic_vector(
        resize(unsigned(dn_addr_i) - to_unsigned(16#16000#, dn_addr_i'length),
               dn_bg1_addr'length)
    );

    i_rom_bg_1 : entity work.dualport_2clk_ram
    generic map (
        ADDR_WIDTH => 14,
        DATA_WIDTH => 8,
        FALLING_A  => false,
        FALLING_B  => true
    )
    port map (
        clock_a   => clk_main_i,
        address_a => bg_rom_addr,
        data_a    => (others => '0'),
        wren_a    => '0',
        q_a       => bg_plane1,

        clock_b   => dn_clk_i,
        address_b => dn_bg1_addr,
        data_b    => dn_data_i,
        wren_b    => dn_bg1_we,
        q_b       => open
    );

    dn_bg2_we <= dn_wr_i when unsigned(dn_addr_i) >= 16#1A000# and
                                    unsigned(dn_addr_i) <  16#1E000# else '0';
    dn_bg2_addr <= std_logic_vector(
        resize(unsigned(dn_addr_i) - to_unsigned(16#1A000#, dn_addr_i'length),
               dn_bg2_addr'length)
    );

    i_rom_bg_2 : entity work.dualport_2clk_ram
    generic map (
        ADDR_WIDTH => 14,
        DATA_WIDTH => 8,
        FALLING_A  => false,
        FALLING_B  => true
    )
    port map (
        clock_a   => clk_main_i,
        address_a => bg_rom_addr,
        data_a    => (others => '0'),
        wren_a    => '0',
        q_a       => bg_plane2,

        clock_b   => dn_clk_i,
        address_b => dn_bg2_addr,
        data_b    => dn_data_i,
        wren_b    => dn_bg2_we,
        q_b       => open
    );

    dn_obj0_we <= dn_wr_i when unsigned(dn_addr_i) >= 16#1E000# and
                                    unsigned(dn_addr_i) <  16#3A000# else '0';
    dn_obj0_addr <= std_logic_vector(
        resize(unsigned(dn_addr_i) - to_unsigned(16#1E000#, dn_addr_i'length),
               dn_obj0_addr'length)
    );

    i_rom_obj_0 : entity work.dualport_2clk_ram
    generic map (
        ADDR_WIDTH => 17,
        DATA_WIDTH => 8,
        FALLING_A  => false,
        FALLING_B  => true
    )
    port map (
        clock_a   => clk_main_i,
        address_a => obj_rom_addr,
        data_a    => (others => '0'),
        wren_a    => '0',
        q_a       => obj_plane0,

        clock_b   => dn_clk_i,
        address_b => dn_obj0_addr,
        data_b    => dn_data_i,
        wren_b    => dn_obj0_we,
        q_b       => open
    );

    dn_obj1_we <= dn_wr_i when unsigned(dn_addr_i) >= 16#3A000# and
                                    unsigned(dn_addr_i) <  16#56000# else '0';
    dn_obj1_addr <= std_logic_vector(
        resize(unsigned(dn_addr_i) - to_unsigned(16#3A000#, dn_addr_i'length),
               dn_obj1_addr'length)
    );

    i_rom_obj_1 : entity work.dualport_2clk_ram
    generic map (
        ADDR_WIDTH => 17,
        DATA_WIDTH => 8,
        FALLING_A  => false,
        FALLING_B  => true
    )
    port map (
        clock_a   => clk_main_i,
        address_a => obj_rom_addr,
        data_a    => (others => '0'),
        wren_a    => '0',
        q_a       => obj_plane1,

        clock_b   => dn_clk_i,
        address_b => dn_obj1_addr,
        data_b    => dn_data_i,
        wren_b    => dn_obj1_we,
        q_b       => open
    );

    dn_obj2_we <= dn_wr_i when unsigned(dn_addr_i) >= 16#56000# and
                                    unsigned(dn_addr_i) <  16#72000# else '0';
    dn_obj2_addr <= std_logic_vector(
        resize(unsigned(dn_addr_i) - to_unsigned(16#56000#, dn_addr_i'length),
               dn_obj2_addr'length)
    );

    i_rom_obj_2 : entity work.dualport_2clk_ram
    generic map (
        ADDR_WIDTH => 17,
        DATA_WIDTH => 8,
        FALLING_A  => false,
        FALLING_B  => true
    )
    port map (
        clock_a   => clk_main_i,
        address_a => obj_rom_addr,
        data_a    => (others => '0'),
        wren_a    => '0',
        q_a       => obj_plane2,

        clock_b   => dn_clk_i,
        address_b => dn_obj2_addr,
        data_b    => dn_data_i,
        wren_b    => dn_obj2_we,
        q_b       => open
    );

    -- Sound CPU ROM: $8000-$FFFF, 32 KiB, loaded after sprite graphics.
    -- QNICE combined download offset $72000..$79FFF.
    dn_sound_we <= dn_wr_i when unsigned(dn_addr_i) >= 16#72000# and
                                unsigned(dn_addr_i) <  16#7A000# else '0';
    dn_sound_addr <= std_logic_vector(
        resize(unsigned(dn_addr_i) - to_unsigned(16#72000#, dn_addr_i'length),
               dn_sound_addr'length)
    );

    i_rom_sound : entity work.dualport_2clk_ram
    generic map (
        ADDR_WIDTH => 15,
        DATA_WIDTH => 8,
        FALLING_A  => false,
        FALLING_B  => true
    )
    port map (
        clock_a    => clk_main_i,
        address_a  => sound_rom_addr,
        data_a     => (others => '0'),
        wren_a     => '0',
        q_a        => sound_rom_data,

        clock_b    => dn_clk_i,
        address_b  => dn_sound_addr,
        data_b     => dn_data_i,
        wren_b     => dn_sound_we,
        q_b        => open
    );

end architecture synthesis;