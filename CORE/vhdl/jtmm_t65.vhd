-------------------------------------------------------------------------------
-- Exciting Hour / Mat Mania - T65 bus adapter
--
-- Keeps the original MiST T65 source files unchanged and provides a lowercase,
-- Verilog-safe interface for jtmm_game.v and jtmm_sound.v.
--
-- T65 expects its own data output to be looped back to DI during writes for
-- correct execution of certain undocumented 6502 instructions.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity jtmm_t65 is
    port (
        clk          : in  std_logic;
        cen          : in  std_logic;
        rst_n        : in  std_logic;
        irq_n        : in  std_logic;
        nmi_n        : in  std_logic;
        so_n         : in  std_logic;
        rdy          : in  std_logic;
        addr         : out std_logic_vector(15 downto 0);
        din          : in  std_logic_vector(7 downto 0);
        dout         : out std_logic_vector(7 downto 0);
        rw_n         : out std_logic;
        sync         : out std_logic;
        vp_n         : out std_logic;
        debug_pc     : out std_logic_vector(15 downto 0)
    );
end entity jtmm_t65;

architecture rtl of jtmm_t65 is

    signal t65_addr     : std_logic_vector(23 downto 0);
    signal t65_din      : std_logic_vector(7 downto 0);
    signal t65_dout     : std_logic_vector(7 downto 0);
    signal t65_rw_n     : std_logic;
    signal t65_regs     : std_logic_vector(63 downto 0);

begin

    addr    <= t65_addr(15 downto 0);
    dout    <= t65_dout;
    rw_n    <= t65_rw_n;
    debug_pc <= t65_regs(63 downto 48);

    -- Required by T65 for certain undocumented NMOS 6502 instructions.
    t65_din <= t65_dout when t65_rw_n = '0' else din;

    i_t65 : entity work.T65
        port map (
            Mode     => "00",    -- NMOS 6502
            BCD_en   => '1',     -- MOS 6502 decimal mode enabled
            Res_n    => rst_n,
            Enable   => cen,
            Clk      => clk,
            Rdy      => rdy,
            Abort_n  => '1',
            IRQ_n    => irq_n,
            NMI_n    => nmi_n,
            SO_n     => so_n,
            R_W_n    => t65_rw_n,
            Sync     => sync,
            EF       => open,
            MF       => open,
            XF       => open,
            ML_n     => open,
            VP_n     => vp_n,
            VDA      => open,
            VPA      => open,
            A        => t65_addr,
            DI       => t65_din,
            DO       => t65_dout,
            Regs     => t65_regs,
            DEBUG    => open,
            NMI_ack  => open
        );

end architecture rtl;
