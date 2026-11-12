-- ============================================================================
-- Файл:        memory_autotest.vhd
-- Назначение:  Автоматические тесты внешней SDRAM для Vision Core.
--
-- Текущий тест: L1 — проверка шины данных DQ[15:0].
--
-- Идея L1:
--   Каждый паттерн записывается в одно слово SDRAM, затем читается обратно
--   и сравнивается с записанным значением. Используются:
--     16 паттернов walking-1  (0001, 0002, 0004, ... 8000);
--     16 паттернов walking-0  (FFFE, FFFD, FFFB, ... 7FFF);
--     0000 и FFFF.
--   walking-1 выявляет "залипание" линии в 0, walking-0 — в 1.
--
-- Адрес теста:
--   0x1F0300 (word address). В контроллере это bank 0, row 992,
--   column 768. Адрес выбран отдельно от ручных проверок
--   0x1F0000/0x1F0200/0x1F03FF, чтобы не затирать их результаты.
--
-- Запуск:
--   SW[2:0] = 000 (выбор L1), затем нажать KEY3.
--   Во время теста busy = '1', верхний уровень переключает Avalon-MM
--   на этот модуль. После завершения busy = '0', результат остаётся
--   на HEX-индикаторах благодаря sticky-флагу active.
--   KEY0 (reset) возвращает ручной режим KEY1/KEY2.
--
-- Индикация:
--   HEX5 = 8 — тест идёт;
--   HEX5 = 0 — PASS;
--   HEX5 = 1 — FAIL;
--   HEX5 = E — таймаут чтения;
--   HEX3..HEX0 — текущий/неисправный паттерн (при PASS показывается 0000);
--   HEX4 — погашен.
--
-- Ограничения:
--   L1 проверяет только линии данных. Адресные линии, bank/row,
--   LFSR-блок и байтовые маски (DQM) — это следующие тесты L2-L5.
--   Тест останавливается на первой ошибке; показанный паттерн
--   указывает, на какой комбинации DQ[15:0] получено расхождение.
--
-- Зависимости:
--   Модуль является Avalon-MM master и подключается к memory_subsystem
--   параллельно с memory_test_master. Арбитраж выполняет верхний уровень
--   по сигналу busy. Ручной режим и автоматический тест не должны
--   работать одновременно.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity memory_autotest is
  port (
    -- Тактирование и сброс в домене контроллера SDRAM (100 МГц).
    clk              : in  std_logic;
    reset_req        : in  std_logic;

    -- Импульс запуска (KEY3 после формирователя кнопки).
    start            : in  std_logic;

    -- Выбор теста: 000 = L1. Остальные значения зарезервированы под L2-L5.
    test_sel         : in  std_logic_vector(2 downto 0);

    -- Avalon-MM master.
    av_address       : out std_logic_vector(24 downto 0);
    av_writedata     : out std_logic_vector(15 downto 0);
    av_byteenable_n  : out std_logic_vector(1 downto 0);
    av_read_n        : out std_logic;
    av_write_n       : out std_logic;
    av_chipselect    : out std_logic;
    av_readdata      : in  std_logic_vector(15 downto 0);
    av_readdatavalid : in  std_logic;
    av_waitrequest   : in  std_logic;

    -- Состояние для верхнего уровня.
    busy             : out std_logic;  -- 1 = модуль владеет Avalon-MM
    active           : out std_logic;  -- 1 = на HEX показан результат теста

    -- Семисегментные индикаторы, активный низкий.
    hex0             : out std_logic_vector(6 downto 0);
    hex1             : out std_logic_vector(6 downto 0);
    hex2             : out std_logic_vector(6 downto 0);
    hex3             : out std_logic_vector(6 downto 0);
    hex4             : out std_logic_vector(6 downto 0);
    hex5             : out std_logic_vector(6 downto 0)
  );
end entity memory_autotest;

architecture rtl of memory_autotest is

  -- Адрес слова, по которому выполняется L1.
  -- 0x1F0300 = bank 0, row 992 (0x3E0), column 768 (0x300).
  constant TEST_ADDR : unsigned(24 downto 0) := to_unsigned(16#1F0300#, 25);

  -- Таймаут ожидания readdatavalid: 65535 тактов = 655.35 мкс при 100 МГц.
  constant TMO_MAX : unsigned(15 downto 0) := (others => '1');

  -- Коды состояния, выводимые на HEX5.
  constant ST_BLANK   : std_logic_vector(3 downto 0) := "1111"; -- индикатор погашен
  constant ST_BUSY    : std_logic_vector(3 downto 0) := "1000"; -- тест идёт
  constant ST_PASS    : std_logic_vector(3 downto 0) := "0000"; -- все паттерны прошли
  constant ST_FAIL    : std_logic_vector(3 downto 0) := "0001"; -- расхождение данных
  constant ST_TIMEOUT : std_logic_vector(3 downto 0) := "1110"; -- чтение не завершилось

  -- Состояния автомата одного паттерна: запись -> запрос чтения ->
  -- ожидание данных -> завершение теста.
  type state_t is (S_IDLE, S_WR, S_RD_REQ, S_RD_WAIT, S_DONE);
  signal state : state_t := S_IDLE;

  -- Сброс: асинхронно ставится по reset_req, синхронно снимается в clk.
  signal rst_sync : std_logic_vector(1 downto 0) := "11";
  signal rst      : std_logic;

  -- Синхронизатор SW[2:0]: переключатели асинхронны к clk.
  -- Значение test_sel_sync фиксируется в момент start.
  signal test_sel_meta : std_logic_vector(2 downto 0) := (others => '0');
  signal test_sel_sync : std_logic_vector(2 downto 0) := (others => '0');

  -- Активные низкие запросы Avalon-MM; в простое оба равны '1'.
  signal wr_n_i : std_logic := '1';
  signal rd_n_i : std_logic := '1';

  -- Таймер ожидания readdatavalid.
  signal tmo : unsigned(15 downto 0) := (others => '0');

  -- Индекс текущего паттерна: 0..33, всего 34 паттерна.
  signal idx : integer range 0 to 33 := 0;

  -- Текущий паттерн: записывается, затем с ним сравнивается прочитанное слово.
  signal pattern : std_logic_vector(15 downto 0) := (others => '0');

  -- Значение, выводимое на HEX3..HEX0.
  signal disp_data : std_logic_vector(15 downto 0) := (others => '0');

  -- Код состояния, выводимый на HEX5.
  signal status : std_logic_vector(3 downto 0) := ST_BLANK;

  -- busy = 1, пока тест выполняется; верхний уровень переключает Avalon-MM.
  signal busy_i : std_logic := '0';

  -- active = 1 после первого запуска и до сброса; удерживает результат на HEX.
  signal active_i : std_logic := '0';

  -- Таблица паттернов L1.
  -- 0..15   — walking-1;
  -- 16..31  — walking-0;
  -- 32      — 0000;
  -- 33      — FFFF;
  -- 34      — фиктивный элемент, чтобы обращение PATTERNS(idx + 1)
  --           при idx = 32 не выходило за границы массива.
  type pattern_array_t is array (0 to 34) of std_logic_vector(15 downto 0);
  constant PATTERNS : pattern_array_t := (
    x"0001", x"0002", x"0004", x"0008",
    x"0010", x"0020", x"0040", x"0080",
    x"0100", x"0200", x"0400", x"0800",
    x"1000", x"2000", x"4000", x"8000",
    x"FFFE", x"FFFD", x"FFFB", x"FFF7",
    x"FFEF", x"FFDF", x"FFBF", x"FF7F",
    x"FEFF", x"FDFF", x"FBFF", x"F7FF",
    x"EFFF", x"DFFF", x"BFFF", x"7FFF",
    x"0000", x"FFFF", x"0000"
  );

  -- Преобразование 4 бит в семисегментный код.
  -- Активный низкий: 0 = сегмент горит. Порядок бит: g f e d c b a.
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

  -- --------------------------------------------------------------------------
  -- Сброс модуля.
  -- reset_req приходит из reset_conditioner (KEY0 или потеря PLL).
  -- Асинхронно устанавливаем два бита в '1', затем сдвигаем '0':
  -- rst удерживается два такта и снимается синхронно с clk.
  -- --------------------------------------------------------------------------
  process (clk, reset_req)
  begin
    if reset_req = '1' then
      rst_sync <= (others => '1');
    elsif rising_edge(clk) then
      rst_sync <= rst_sync(0) & '0';
    end if;
  end process;

  rst <= rst_sync(1);

  -- --------------------------------------------------------------------------
  -- Синхронизатор выбора теста.
  -- SW[2:0] — асинхронные входы. Два триггера защищают от метастабильности.
  -- Значение test_sel_sync используется только в состоянии S_IDLE
  -- в момент прихода start.
  -- --------------------------------------------------------------------------
  process (clk, reset_req)
  begin
    if reset_req = '1' then
      test_sel_meta <= (others => '0');
      test_sel_sync <= (others => '0');
    elsif rising_edge(clk) then
      test_sel_meta <= test_sel;
      test_sel_sync <= test_sel_meta;
    end if;
  end process;

  -- --------------------------------------------------------------------------
  -- Основной автомат L1.
  --
  -- Один паттерн:
  --   S_IDLE   — ждём start и test_sel_sync = "000";
  --   S_WR     — выставляем write, ждём waitrequest = '0';
  --   S_RD_REQ — выставляем read, ждём waitrequest = '0';
  --   S_RD_WAIT— ждём readdatavalid, сравниваем данные, считаем таймаут;
  --   S_DONE   — фиксируем результат, снимаем busy, возвращаемся в S_IDLE.
  --
  -- При совпадении и idx < 33 переходим к следующему паттерну.
  -- При idx = 33 все 34 паттерна прошли: PASS.
  -- При расхождении: FAIL и паттерн, на котором произошла ошибка.
  -- При tmo = TMO_MAX: TIMEOUT.
  -- --------------------------------------------------------------------------
  process (clk, reset_req)
  begin
    if reset_req = '1' then
      state <= S_IDLE;
      wr_n_i <= '1';
      rd_n_i <= '1';
      tmo <= (others => '0');
      idx <= 0;
      pattern <= (others => '0');
      disp_data <= (others => '0');
      status <= ST_BLANK;
      busy_i <= '0';
      active_i <= '0';

    elsif rising_edge(clk) then
      if rst = '1' then
        state <= S_IDLE;
        wr_n_i <= '1';
        rd_n_i <= '1';
        tmo <= (others => '0');
        idx <= 0;
        pattern <= (others => '0');
        disp_data <= (others => '0');
        status <= ST_BLANK;
        busy_i <= '0';
        active_i <= '0';

      else
        case state is

          -- Ожидание запуска. В простое запросы сняты, busy = '0'.
          when S_IDLE =>
            wr_n_i <= '1';
            rd_n_i <= '1';
            busy_i <= '0';

            if start = '1' and test_sel_sync = "000" then
              idx <= 0;
              pattern <= PATTERNS(0);
              disp_data <= PATTERNS(0);
              status <= ST_BUSY;
              busy_i <= '1';
              active_i <= '1';
              tmo <= (others => '0');
              wr_n_i <= '0';          -- начать запись первого паттерна
              state <= S_WR;
            end if;

          -- Запись принята контроллером: снимаем write, сразу выдаём read.
          -- Контроллер хранит команды в FIFO и сам выдерживает тайминги
          -- SDRAM между записью и чтением.
          when S_WR =>
            if av_waitrequest = '0' then
              wr_n_i <= '1';
              rd_n_i <= '0';
              tmo <= (others => '0');
              state <= S_RD_REQ;
            end if;

          -- Запрос чтения принят: снимаем read, ждём данные.
          when S_RD_REQ =>
            if av_waitrequest = '0' then
              rd_n_i <= '1';
              tmo <= (others => '0');
              state <= S_RD_WAIT;
            end if;

          -- Ожидание прочитанного слова.
          when S_RD_WAIT =>
            if av_readdatavalid = '1' then
              if av_readdata = pattern then
                if idx = 33 then
                  -- Все 34 паттерна совпали.
                  status <= ST_PASS;
                  disp_data <= x"0000";
                  busy_i <= '0';
                  state <= S_DONE;
                else
                  -- Переход к следующему паттерну.
                  idx <= idx + 1;
                  pattern <= PATTERNS(idx + 1);
                  disp_data <= PATTERNS(idx + 1);
                  status <= ST_BUSY;
                  tmo <= (others => '0');
                  wr_n_i <= '0';
                  state <= S_WR;
                end if;
              else
                -- Данные не совпали: фиксируем паттерн и останавливаемся.
                status <= ST_FAIL;
                disp_data <= pattern;
                busy_i <= '0';
                state <= S_DONE;
              end if;
            elsif tmo = TMO_MAX then
              -- Контроллер не выдал readdatavalid за отведённое время.
              status <= ST_TIMEOUT;
              disp_data <= pattern;
              busy_i <= '0';
              state <= S_DONE;
            else
              tmo <= tmo + 1;
            end if;

          -- Результат зафиксирован. busy = '0', top возвращает ручной master.
          -- active_i остаётся '1', поэтому HEX продолжает показывать результат
          -- до сброса KEY0.
          when S_DONE =>
            wr_n_i <= '1';
            rd_n_i <= '1';
            busy_i <= '0';
            state <= S_IDLE;

          when others =>
            state <= S_IDLE;
        end case;
      end if;
    end if;
  end process;

  -- --------------------------------------------------------------------------
  -- Avalon-MM master.
  -- Адрес постоянный: тест L1 проверяет данные, а не адресацию.
  -- byteenable_n = "00" — разрешены оба байта.
  -- chipselect = '0' — контроллер не использует этот сигнал для выбора;
  -- активность определяется read/write, как и в manual master.
  -- --------------------------------------------------------------------------
  av_address <= std_logic_vector(TEST_ADDR);
  av_writedata <= pattern;
  av_byteenable_n <= "00";
  av_read_n <= rd_n_i;
  av_write_n <= wr_n_i;
  av_chipselect <= '0';

  busy <= busy_i;
  active <= active_i;

  -- --------------------------------------------------------------------------
  -- Индикация.
  -- HEX3..HEX0 — 16-битное значение disp_data (старший полубайт на HEX3).
  -- HEX4 — погашен.
  -- HEX5 — код состояния; при ST_BLANK погашен.
  -- --------------------------------------------------------------------------
  hex0 <= hex_to_seg(disp_data(3 downto 0));
  hex1 <= hex_to_seg(disp_data(7 downto 4));
  hex2 <= hex_to_seg(disp_data(11 downto 8));
  hex3 <= hex_to_seg(disp_data(15 downto 12));
  hex4 <= (others => '1');
  hex5 <= (others => '1') when status = ST_BLANK else hex_to_seg(status);

end architecture rtl;