--------------------------------------------------------------------------------
-- memory_test_master.vhd
--
-- Ручной тест SDR SDRAM через Avalon-MM slave контроллера (Altera 14.0).
-- Никакой автоматики: нажал "запись" -- записал одно слово, нажал "чтение" --
-- прочитал его обратно и показал на HEX.
--
-- Адрес в интерфейсе контроллера -- номер 16-битного СЛОВА, не байта.
-- Тестовый регион вынесен в конец памяти: 0x1F0000..0x1F03FF.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity memory_test_master is
  generic (
    TEST_BASE : unsigned(24 downto 0) := to_unsigned(16#1F0000#, 25)
  );
  port (
    -- такт и сброс
    clk        : in  std_logic;                     -- memory_clk, 100 МГц
    reset_req  : in  std_logic;                     -- '1' = требование сброса

    -- управление с платы
    sw       : in  std_logic_vector(9 downto 0);    -- младшие 10 бит адреса
    wr_stb   : in  std_logic;                       -- '1' = записать (1 такт)
    rd_stb   : in  std_logic;                       -- '1' = прочитать (1 такт)

    -- индикация (активный низкий)
    hex0       : out std_logic_vector(6 downto 0);  -- слово, биты 3..0
    hex1       : out std_logic_vector(6 downto 0);  -- слово, биты 7..4
    hex2       : out std_logic_vector(6 downto 0);  -- слово, биты 11..8
    hex3       : out std_logic_vector(6 downto 0);  -- слово, биты 15..12
    hex4       : out std_logic_vector(6 downto 0);  -- погашен
    hex5       : out std_logic_vector(6 downto 0);  -- код состояния

    -- Avalon-MM master
    av_address       : out std_logic_vector(24 downto 0);
    av_writedata     : out std_logic_vector(15 downto 0);
    av_byteenable_n  : out std_logic_vector(1 downto 0);
    av_read_n        : out std_logic;
    av_write_n       : out std_logic;
    av_chipselect    : out std_logic;
    av_readdata      : in  std_logic_vector(15 downto 0);
    av_readdatavalid : in  std_logic;
    av_waitrequest   : in  std_logic
  );
end entity memory_test_master;

architecture rtl of memory_test_master is

  ------------------------------------------------------------------------------
  -- Коды состояния для HEX5
  ------------------------------------------------------------------------------
  constant ST_IDLE    : std_logic_vector(3 downto 0) := "0000"; -- 0: простой
  constant ST_WR_DONE : std_logic_vector(3 downto 0) := "0001"; -- 1: запись сделана
  constant ST_RD_DONE : std_logic_vector(3 downto 0) := "0010"; -- 2: чтение сделано
  constant ST_TIMEOUT : std_logic_vector(3 downto 0) := "1110"; -- E: нет ответа
  constant ST_BLANK   : std_logic_vector(3 downto 0) := "1111"; -- -: погашен

  -- Слово, которое мастер пишет по кнопке "запись"
  constant TEST_PATTERN : std_logic_vector(15 downto 0) := x"A5A5";

  -- Таймаут ожидания данных чтения (при 100 МГц)
  constant TMO_MAX : unsigned(15 downto 0) := (others => '1');          -- 655 мкс

  ------------------------------------------------------------------------------
  -- Сброс: асинхронное утверждение, синхронное снятие в домене clk
  ------------------------------------------------------------------------------
  signal rst_sync : std_logic_vector(1 downto 0) := (others => '1');
  signal rst      : std_logic;

  ------------------------------------------------------------------------------
  -- Автомат ручных операций
  ------------------------------------------------------------------------------
  type state_t is (S_IDLE, S_WR, S_RD_REQ, S_RD_WAIT);
  signal state : state_t := S_IDLE;
  signal tmo   : unsigned(15 downto 0) := (others => '0');

  -- Внутренние линии запроса. Начальное значение '1' важно: до первого такта
  -- после конфигурации запрос не должен быть активен.
  signal wr_n_i : std_logic := '1';
  signal rd_n_i : std_logic := '1';

  ------------------------------------------------------------------------------
  -- Данные и состояние
  ------------------------------------------------------------------------------
  signal word_addr : unsigned(24 downto 0);      -- TEST_BASE + sw
  signal data_reg  : std_logic_vector(15 downto 0) := (others => '0');
  signal status    : std_logic_vector(3 downto 0) := ST_BLANK;

  ------------------------------------------------------------------------------
  -- Функция: 4 бита -> 7 сегментов, активный низкий (0 = сегмент горит)
  -- порядок бит: g f e d c b a
  ------------------------------------------------------------------------------
  function hex_to_seg (v : std_logic_vector(3 downto 0))
    return std_logic_vector is
  begin
    case v is
      when "0000" => return "1000000"; -- 0
      when "0001" => return "1111001"; -- 1
      when "0010" => return "0100100"; -- 2
      when "0011" => return "0110000"; -- 3
      when "0100" => return "0011001"; -- 4
      when "0101" => return "0010010"; -- 5
      when "0110" => return "0000010"; -- 6
      when "0111" => return "1111000"; -- 7
      when "1000" => return "0000000"; -- 8
      when "1001" => return "0010000"; -- 9
      when "1010" => return "0001000"; -- A
      when "1011" => return "0000011"; -- b
      when "1100" => return "1000110"; -- C
      when "1101" => return "0100001"; -- d
      when "1110" => return "0000110"; -- E
      when "1111" => return "0001110"; -- F
    end case;
  end function;

begin

  ------------------------------------------------------------------------------
  -- Сброс: ставим асинхронно, снимаем синхронно в домене clk
  ------------------------------------------------------------------------------
  process (clk, reset_req)
  begin
    if reset_req = '1' then
      rst_sync <= (others => '1');
    elsif rising_edge(clk) then
      rst_sync <= rst_sync(0) & '0';
    end if;
  end process;

  rst <= rst_sync(1);

  ------------------------------------------------------------------------------
  word_addr <= TEST_BASE(24 downto 10) & unsigned(sw);

  ------------------------------------------------------------------------------
  -- Автомат: одна операция по нажатию, с ожиданием waitrequest и таймаутом
  ------------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state      <= S_IDLE;
        wr_n_i <= '1';
        rd_n_i <= '1';
        tmo        <= (others => '0');
        data_reg   <= (others => '0');
        status     <= ST_BLANK;
      else
        case state is

          -- простой: ждём нажатия
          when S_IDLE =>
            wr_n_i <= '1';
            rd_n_i <= '1';
            tmo    <= (others => '0');
            if wr_stb = '1' then
              wr_n_i <= '0';              -- выставляем запрос на запись
              state  <= S_WR;
            elsif rd_stb = '1' then
              rd_n_i <= '0';              -- выставляем запрос на чтение
              state  <= S_RD_REQ;
            end if;

          -- запрос записи висит, пока контроллер не примет
          when S_WR =>
            if av_waitrequest = '0' then
              wr_n_i <= '1';            -- принято, снимаем запрос
              status <= ST_WR_DONE;
              state  <= S_IDLE;
            end if;

          -- запрос чтения висит, пока контроллер не примет
          when S_RD_REQ =>
            if av_waitrequest = '0' then
              rd_n_i <= '1';            -- принято, снимаем запрос
              tmo    <= (others => '0');
              state  <= S_RD_WAIT;
            end if;

          -- ждём данные; если не пришли за TMO_MAX -- таймаут
          when S_RD_WAIT =>
            if av_readdatavalid = '1' then
              data_reg <= av_readdata;
              status   <= ST_RD_DONE;
              state    <= S_IDLE;
            elsif tmo = TMO_MAX then
              status   <= ST_TIMEOUT;
              state    <= S_IDLE;
            else
              tmo <= tmo + 1;
            end if;

        end case;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- Постоянные уровни шины
  ------------------------------------------------------------------------------
  av_address      <= std_logic_vector(word_addr);
  av_writedata    <= TEST_PATTERN;
  av_byteenable_n <= "00";      -- пишем оба байта
  av_chipselect   <= '0';       -- в RTL контроллера не используется
  av_write_n      <= wr_n_i;    -- запросы формирует автомат
  av_read_n       <= rd_n_i;

  ------------------------------------------------------------------------------
  -- Индикация: HEX3..HEX0 -- слово, HEX5 -- состояние, HEX4 погашен
  ------------------------------------------------------------------------------
  hex0 <= hex_to_seg(data_reg(3 downto 0));
  hex1 <= hex_to_seg(data_reg(7 downto 4));
  hex2 <= hex_to_seg(data_reg(11 downto 8));
  hex3 <= hex_to_seg(data_reg(15 downto 12));
  hex4 <= (others => '1');

  hex5 <= (others => '1') when status = ST_BLANK
          else hex_to_seg(status);

end architecture rtl;