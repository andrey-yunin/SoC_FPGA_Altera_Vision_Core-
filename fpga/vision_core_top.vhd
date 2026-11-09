library ieee;
use ieee.std_logic_1164.all;

entity vision_core_top is
    port (
        CLOCK_50 : in    std_logic;
        RESET_N  : in    std_logic;

        DRAM_ADDR  : out   std_logic_vector(12 downto 0);
        DRAM_BA    : out   std_logic_vector(1 downto 0);
        DRAM_CAS_N : out   std_logic;
        DRAM_CKE   : out   std_logic;
        DRAM_CS_N  : out   std_logic;
        DRAM_DQ    : inout std_logic_vector(15 downto 0);
        DRAM_RAS_N : out   std_logic;
        DRAM_DQM   : out   std_logic_vector(1 downto 0);
        DRAM_WE_N  : out   std_logic;
        DRAM_CLK   : out   std_logic
    );
end entity vision_core_top;

architecture rtl of vision_core_top is

    component memory_subsystem is
        port (
            clk_clk                   : in    std_logic;
            pll_locked_export         : out   std_logic;
            pll_not_locked_reset      : in    std_logic;
            reset_reset_n             : in    std_logic;

            sdram_addr                : out   std_logic_vector(12 downto 0);
            sdram_ba                  : out   std_logic_vector(1 downto 0);
            sdram_cas_n               : out   std_logic;
            sdram_cke                 : out   std_logic;
            sdram_cs_n                : out   std_logic;
            sdram_dq                  : inout std_logic_vector(15 downto 0);
            sdram_ras_n               : out   std_logic;
            sdram_dqm                 : out   std_logic_vector(1 downto 0);
            sdram_we_n                : out   std_logic;

            sdram_access_address      : in    std_logic_vector(24 downto 0);
            sdram_access_byteenable_n : in    std_logic_vector(1 downto 0);
            sdram_access_chipselect   : in    std_logic;
            sdram_access_writedata    : in    std_logic_vector(15 downto 0);
            sdram_access_read_n       : in    std_logic;
            sdram_access_write_n      : in    std_logic;
            sdram_access_readdata     : out   std_logic_vector(15 downto 0);
            sdram_access_readdatavalid : out   std_logic;
            sdram_access_waitrequest  : out   std_logic;
            sdram_access_clk_clk      : out   std_logic;
            sdram_clk_clk             : out   std_logic
        );
    end component memory_subsystem;

    signal pll_locked     : std_logic;
    signal pll_not_locked : std_logic;

    -- Clock and responses for the future Avalon-MM master.
    signal memory_clk           : std_logic;
    signal memory_readdata      : std_logic_vector(15 downto 0);
    signal memory_readdatavalid : std_logic;
    signal memory_waitrequest   : std_logic;

begin

    -- Assert the controller reset while the PLL is not locked.
    -- Reset release is synchronized inside memory_subsystem.
    pll_not_locked <= not pll_locked;

    u_memory_subsystem : memory_subsystem
        port map (
            clk_clk                   => CLOCK_50,
            pll_locked_export         => pll_locked,
            pll_not_locked_reset      => pll_not_locked,
            reset_reset_n             => RESET_N,

            sdram_addr                => DRAM_ADDR,
            sdram_ba                  => DRAM_BA,
            sdram_cas_n               => DRAM_CAS_N,
            sdram_cke                 => DRAM_CKE,
            sdram_cs_n                => DRAM_CS_N,
            sdram_dq                  => DRAM_DQ,
            sdram_ras_n               => DRAM_RAS_N,
            sdram_dqm                 => DRAM_DQM,
            sdram_we_n                => DRAM_WE_N,

            -- No Avalon-MM requests until a master is connected.
            sdram_access_address      => (others => '0'),
            sdram_access_byteenable_n => (others => '1'),
            sdram_access_chipselect   => '0',
            sdram_access_writedata    => (others => '0'),
            sdram_access_read_n       => '1',
            sdram_access_write_n      => '1',

            sdram_access_readdata      => memory_readdata,
            sdram_access_readdatavalid => memory_readdatavalid,
            sdram_access_waitrequest  => memory_waitrequest,
            sdram_access_clk_clk      => memory_clk,
            sdram_clk_clk             => DRAM_CLK
        );

end architecture rtl;
