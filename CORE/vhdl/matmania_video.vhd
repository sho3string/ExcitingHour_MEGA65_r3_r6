----------------------------------------------------------------------------------
-- Mat Mania - native video timing test
--
-- 48 MHz JTFRAME master clock, 6 MHz pixel enable (cen6).
-- 384 pixels x 264 lines = 59.185606 Hz, 15.625 kHz horizontal.
-- 256x240 native picture: asymmetric colour bars and corner markers.
--
-- This is a temporary pattern generator. The Mat Mania game video will
-- replace it after the rotation and video timing have been verified.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity matmania_video is
   port (
      clk          : in  std_logic;
      reset        : in  std_logic;
      cen6         : in  std_logic;

      red          : out std_logic_vector(3 downto 0);
      green        : out std_logic_vector(3 downto 0);
      blue         : out std_logic_vector(3 downto 0);
      LHBL         : out std_logic;
      LVBL         : out std_logic;
      HS           : out std_logic;
      VS           : out std_logic
   );
end entity matmania_video;

architecture rtl of matmania_video is

constant C_H_TOTAL        : integer := 384;
constant C_V_TOTAL        : integer := 264;
constant C_H_SYNC         : integer := 28;
constant C_V_SYNC         : integer := 2;
constant C_H_ACTIVE_START : integer := 64;
constant C_V_ACTIVE_START : integer := 12;
constant C_H_ACTIVE       : integer := 256;
constant C_V_ACTIVE       : integer := 240;

signal h_count             : integer range 0 to C_H_TOTAL - 1 := 0;
signal v_count             : integer range 0 to C_V_TOTAL - 1 := 0;
signal h_active            : std_logic;
signal v_active            : std_logic;

begin

    -- Raster counters run on 6 MHz enables; no divided/gated clock.
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                h_count <= 0;
                v_count <= 0;
            elsif cen6 = '1' then
                if h_count = C_H_TOTAL - 1 then
                    h_count <= 0;

                    if v_count = C_V_TOTAL - 1 then
                        v_count <= 0;
                    else
                        v_count <= v_count + 1;
                    end if;
                else
                    h_count <= h_count + 1;
                end if;
            end if;
        end if;
    end process;

    -- Positive-going sync; LHBL/LVBL are active-picture enables to match
    -- the existing 1943 wrapper (mega65.vhd inverts them to M2M blanking).
    HS <= '1' when h_count < C_H_SYNC else '0';
    VS <= '1' when v_count < C_V_SYNC else '0';

    h_active <= '1' when h_count >= C_H_ACTIVE_START and
                         h_count < C_H_ACTIVE_START + C_H_ACTIVE else '0';
    v_active <= '1' when v_count >= C_V_ACTIVE_START and
                         v_count < C_V_ACTIVE_START + C_V_ACTIVE else '0';

    LHBL <= h_active;
    LVBL <= v_active;

    -- Eight 32-pixel colour bars, fine grid, centre cross and unique corners.
    -- After rotation the bars become horizontal and the four corner markers
    -- move to distinct locations, making rotation/mirroring easy to diagnose.
    process(all)
        variable x : integer;
        variable y : integer;
        variable r : std_logic_vector(3 downto 0);
        variable g : std_logic_vector(3 downto 0);
        variable b : std_logic_vector(3 downto 0);
    begin
        r := x"0";
        g := x"0";
        b := x"0";
        x := 0;
        y := 0;

        if h_active = '1' and v_active = '1' then
            x := h_count - C_H_ACTIVE_START;
            y := v_count - C_V_ACTIVE_START;

            case x / 32 is
                when 0 => r := x"F"; g := x"2"; b := x"2";  -- red
                when 1 => r := x"F"; g := x"F"; b := x"2";  -- yellow
                when 2 => r := x"2"; g := x"F"; b := x"2";  -- green
                when 3 => r := x"2"; g := x"F"; b := x"F";  -- cyan
                when 4 => r := x"2"; g := x"2"; b := x"F";  -- blue
                when 5 => r := x"F"; g := x"2"; b := x"F";  -- magenta
                when 6 => r := x"F"; g := x"9"; b := x"2";  -- orange
                when others => r := x"C"; g := x"C"; b := x"C";  -- grey
            end case;

            -- Black single-pixel grid every 32 pixels.
            if x mod 32 = 0 or y mod 32 = 0 then
                r := x"0";
                g := x"0";
                b := x"0";
            end if;

            -- White centre cross (2 pixels wide).
            if x = 127 or x = 128 or y = 119 or y = 120 then
                r := x"F";
                g := x"F";
                b := x"F";
            end if;

            -- 20x20 corner markers, intentionally all different colours.
            if x < 20 and y < 20 then
                r := x"F"; g := x"0"; b := x"0";  -- top left: red
            elsif x >= 236 and y < 20 then
                r := x"0"; g := x"F"; b := x"0";  -- top right: green
            elsif x < 20 and y >= 220 then
                r := x"0"; g := x"0"; b := x"F";  -- bottom left: blue
            elsif x >= 236 and y >= 220 then
                r := x"F"; g := x"F"; b := x"0";  -- bottom right: yellow
            end if;
        end if;

        red   <= r;
        green <= g;
        blue  <= b;
    end process;

end architecture rtl;
