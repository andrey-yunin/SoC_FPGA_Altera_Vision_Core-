--------------------------------------------------------------------------------
-- reset_conditioner.vhd
--
-- Единая точка формирования сброса для всей FPGA-части проекта.
--
--   вход:  key_reset_n (пин RESET_N, активный низкий) + pll_locked
--   выход: reset_n_out   -- для подсистемы памяти (активный низкий)
--          reset_req_out -- для собственного мастера (активный высокий)
--
-- Почему тактируется CLOCK_50, а не memory_clk: сброс обязан действовать,
-- когда PLL ещё не залочена и памяти ещё нет такта. CLOCK_50 -- кварцевый
-- генератор, он есть всё время, пока на плате есть питание.
--
-- Что делает:
--   1) ставит сброс асинхронно (без ожидания такта) и снимает синхронно;
--   2) фильтрует дребезг кнопки: сброс снимается только после того, как
--      вход продержался в неактивном состоянии DB_MAX тактов подряд;
--   3) выдаёт наружу уже зарегистрированный, чистый сигнал.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity reset_conditioner is
  generic (
    -- 500 000 тактов CLOCK_50 (50 МГц) = 10 мс
    DB_MAX : unsigned(18 downto 0) := to_unsigned(500000, 19)
  );
  port (
    clk           : in  std_logic;   -- CLOCK_50, 50 МГц
    key_reset_n   : in  std_logic;   -- пин RESET_N: 0 = кнопка нажата
    pll_locked    : in  std_logic;   -- 1 = PLL захватила частоту

    reset_n_out   : out std_logic;   -- для подсистемы, активный низкий
    reset_req_out : out std_logic    -- для мастера, активный высокий
  );
end entity reset_conditioner;

architecture rtl of reset_conditioner is

  -- '1' = требование сброса: кнопка нажата или PLL не залочена
  signal raw      : std_logic;

  -- двухкаскадный синхронизатор: гасит метастабильность
  signal sync     : std_logic_vector(1 downto 0) := (others => '1');

  -- счётчик подтверждения уровня
  signal cnt      : unsigned(18 downto 0) := (others => '0');

  -- сброс активен, пока вход не подтверждён DB_MAX тактов
  signal filtered : std_logic;

  -- зарегистрированный выход
  signal req      : std_logic := '1';

begin
 
 raw <= not key_reset_n;

  -- Каскад 1..2. Установка асинхронная (сброс не ждёт такта),
  -- снятие синхронное (уходим от recovery/removal).
  process (clk, raw)
  begin
    if raw = '1' then
      sync <= (others => '1');
    elsif rising_edge(clk) then
      sync <= sync(0) & '0';
    end if;
  end process;

  -- Фильтр дребезга. Пока sync(1) = '1' -- счётчик держим в нуле.
  -- Как только уровень снялся, считаем до DB_MAX. Любой новый
  -- импульс сброса снова обнуляет счётчик через ветку raw.
  process (clk, raw)
  begin
    if raw = '1' then
      cnt <= (others => '0');
    elsif rising_edge(clk) then
      if sync(1) = '1' then
        cnt <= (others => '0');
      elsif cnt /= DB_MAX then
        cnt <= cnt + 1;
      end if;
    end if;
  end process;

  filtered <= '1' when (sync(1) = '1' or cnt /= DB_MAX) else '0';

  -- Наружу -- только значение триггера, без комбинационных выбросов.
  process (clk, raw)
  begin
    if raw = '1' then
      req <= '1';
    elsif rising_edge(clk) then
      req <= filtered;
    end if;
  end process;
  
  reset_req_out <= req or (not pll_locked);  -- мастеру: кнопка ИЛИ PLL не залочена
  reset_n_out   <= not req;                  -- подсистеме (и PLL): только кнопка

end architecture rtl;
