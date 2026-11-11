library ieee;
use ieee.std_logic_1164.all;

entity vision_core_top is
    port (
        CLOCK_50 : in    std_logic;
        RESET_N  : in    std_logic;
        
        SW       : in    std_logic_vector(9 downto 0);
        KEY      : in    std_logic_vector(3 downto 1);  -- KEY0 физически занят под RESET_N

        HEX0     : out   std_logic_vector(6 downto 0);
        HEX1     : out   std_logic_vector(6 downto 0);
        HEX2     : out   std_logic_vector(6 downto 0);
        HEX3     : out   std_logic_vector(6 downto 0);
        HEX4     : out   std_logic_vector(6 downto 0);
        HEX5     : out   std_logic_vector(6 downto 0);        

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
    
    
    component reset_conditioner is
        port (
            clk           : in  std_logic;
            key_reset_n   : in  std_logic;
            pll_locked    : in  std_logic;
            reset_n_out   : out std_logic;
            reset_req_out : out std_logic
        );
    end component reset_conditioner;
    
    --------------------------------------------------------------------------
    -- Формирователь кнопки: синхронизация, антидребезг, строб на один такт
    --------------------------------------------------------------------------
    component button_conditioner is
        port (
            clk   : in  std_logic;
            rst   : in  std_logic;
            btn_n : in  std_logic;
            level : out std_logic;
            stb   : out std_logic
        );
    end component button_conditioner;

    component memory_test_master is
        port (
            clk              : in    std_logic;
            reset_req        : in    std_logic;
            sw               : in    std_logic_vector(9 downto 0);
            wr_stb           : in    std_logic;
            rd_stb           : in    std_logic;

            hex0             : out   std_logic_vector(6 downto 0);
            hex1             : out   std_logic_vector(6 downto 0);
            hex2             : out   std_logic_vector(6 downto 0);
            hex3             : out   std_logic_vector(6 downto 0);
            hex4             : out   std_logic_vector(6 downto 0);
            hex5             : out   std_logic_vector(6 downto 0);

            av_address       : out   std_logic_vector(24 downto 0);
            av_writedata     : out   std_logic_vector(15 downto 0);
            av_byteenable_n  : out   std_logic_vector(1 downto 0);
            av_read_n        : out   std_logic;
            av_write_n       : out   std_logic;
            av_chipselect    : out   std_logic;
            av_readdata      : in    std_logic_vector(15 downto 0);
            av_readdatavalid : in    std_logic;
            av_waitrequest   : in    std_logic
        );
        end component memory_test_master;
        
        
    signal pll_locked     : std_logic;
    signal pll_not_locked : std_logic;
    signal reset_n_sys    : std_logic;  -- очищенный сброс для подсистемы
    signal reset_req_sys  : std_logic;  -- сброс для тестера, активный высокий

    -- Сброс кнопочных фильтров в домене памяти
    signal rst_mem_sync : std_logic_vector(1 downto 0) := (others => '1');
    signal rst_mem      : std_logic;

    -- Стробы нажатий после антидребезга, домен memory_clk
    signal btn_w_stb : std_logic;
    signal btn_r_stb : std_logic;

    -- Clock and responses for the future Avalon-MM master.
    signal memory_clk           : std_logic;
    signal memory_readdata      : std_logic_vector(15 downto 0);
    signal memory_readdatavalid : std_logic;
    signal memory_waitrequest   : std_logic;
    
    signal av_address      : std_logic_vector(24 downto 0);
    signal av_writedata    : std_logic_vector(15 downto 0);
    signal av_byteenable_n : std_logic_vector(1 downto 0);
    signal av_read_n       : std_logic;
    signal av_write_n      : std_logic;
    signal av_chipselect   : std_logic;

begin

    -- Assert the controller reset while the PLL is not locked.
    -- Reset release is synchronized inside memory_subsystem.
    pll_not_locked <= not pll_locked;

    u_memory_subsystem : memory_subsystem
        port map (
            clk_clk                   => CLOCK_50,
            pll_locked_export         => pll_locked,
            pll_not_locked_reset      => pll_not_locked,
            reset_reset_n             => reset_n_sys,

            sdram_addr                => DRAM_ADDR,
            sdram_ba                  => DRAM_BA,
            sdram_cas_n               => DRAM_CAS_N,
            sdram_cke                 => DRAM_CKE,
            sdram_cs_n                => DRAM_CS_N,
            sdram_dq                  => DRAM_DQ,
            sdram_ras_n               => DRAM_RAS_N,
            sdram_dqm                 => DRAM_DQM,
            sdram_we_n                => DRAM_WE_N,

            -- Avalon-MM master: memory test generator.
            sdram_access_address      => av_address,
            sdram_access_byteenable_n => av_byteenable_n,
            sdram_access_chipselect   => av_chipselect,
            sdram_access_writedata    => av_writedata,
            sdram_access_read_n       => av_read_n,
            sdram_access_write_n      => av_write_n,

            sdram_access_readdata      => memory_readdata,
            sdram_access_readdatavalid => memory_readdatavalid,
            sdram_access_waitrequest  => memory_waitrequest,
            sdram_access_clk_clk      => memory_clk,
            sdram_clk_clk             => DRAM_CLK
        );
    u_reset_conditioner : reset_conditioner
        port map (
            clk           => CLOCK_50,
            key_reset_n   => RESET_N,
            pll_locked    => pll_locked,
            reset_n_out   => reset_n_sys,
            reset_req_out => reset_req_sys
        );
        
        
        u_memory_test_master : memory_test_master
        port map (
            clk              => memory_clk,
            reset_req        => reset_req_sys,
            sw               => SW,
            wr_stb           => btn_w_stb,
            rd_stb           => btn_r_stb,
            hex0             => HEX0,
            hex1             => HEX1,
            hex2             => HEX2,
            hex3             => HEX3,
            hex4             => HEX4,
            hex5             => HEX5,
            av_address       => av_address,
            av_writedata     => av_writedata,
            av_byteenable_n  => av_byteenable_n,
            av_read_n        => av_read_n,
            av_write_n       => av_write_n,
            av_chipselect    => av_chipselect,
            av_readdata      => memory_readdata,
            av_readdatavalid => memory_readdatavalid,
            av_waitrequest   => memory_waitrequest
        );     

    --------------------------------------------------------------------------
    -- Сброс фильтров кнопок: домен memory_clk
    --------------------------------------------------------------------------
    process (memory_clk, reset_req_sys)
    begin
        if reset_req_sys = '1' then
            rst_mem_sync <= (others => '1');
        elsif rising_edge(memory_clk) then
            rst_mem_sync <= rst_mem_sync(0) & '0';
        end if;
    end process;

    rst_mem <= rst_mem_sync(1);

    --------------------------------------------------------------------------
    -- Формирователи кнопок: антидребезг 10 мс, строб на один такт
    --------------------------------------------------------------------------
    u_btn_write : button_conditioner
        port map (
            clk   => memory_clk,
            rst   => rst_mem,
            btn_n => KEY(1),
            level => open,
            stb   => btn_w_stb
        );

    u_btn_read : button_conditioner
        port map (
            clk   => memory_clk,
            rst   => rst_mem,
            btn_n => KEY(2),
            level => open,
            stb   => btn_r_stb
        );

end architecture rtl;
