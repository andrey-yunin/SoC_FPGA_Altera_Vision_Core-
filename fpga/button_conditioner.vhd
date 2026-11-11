--------------------------------------------------------------------------------
-- button_conditioner.vhd
--
-- Приведение механической кнопки к виду, пригодному для логики:
--   * два триггера снимают метастабильность;
--   * счётчик отбрасывает дребезг: уровень принимается, только если
--     продержался DB_MAX тактов подряд;
--   * наружу выдаются подтверждённый уровень и импульс на один такт
--     в момент подтверждения нажатия.
--
-- Полярность входа -- как на пине DE1-SoC: 1 = отпущена, 0 = нажата.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity button_conditioner is
  port (
    clk   : in  std_logic;   -- такт домена, в котором работает потребитель
    rst   : in  std_logic;   -- сброс, активный высокий, уже синхронный clk

    btn_n : in  std_logic;   -- вход с пина: '0' = нажата

    level : out std_logic;   -- '1' = нажата (подтверждённый уровень)
    stb   : out std_logic    -- '1' один такт в момент подтверждения нажатия
  );
end entity button_conditioner;

architecture rtl of button_conditioner is
  -- здесь будут константа, сигналы и процессы
  -- Порог фильтра: 1 000 000 тактов = 10 мс при 100 МГц (memory_clk)
  constant DB_MAX : unsigned(19 downto 0) := to_unsigned(1000000, 20);

  signal meta : std_logic := '1';   -- 1-й каскад синхронизатора
  signal sync : std_logic := '1';   -- 2-й каскад: устойчивый уровень
  signal prev : std_logic := '1';   -- последнее подтверждённое состояние
  signal cnt  : unsigned(19 downto 0) := (others => '0'); -- окно фильтра
  
  begin
  -- здесь будут процессы
  
  -- Два триггера: снимают метастабильность с асинхронного входа
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        meta <= '1';
        sync <= '1';
      else
        meta <= btn_n;   -- 1-й каскад
        sync <= meta;    -- 2-й каскад: устойчивый уровень
      end if;
    end if;
  end process;
  
  -- Фильтр дребезга: верим уровню, продержавшемуся DB_MAX тактов подряд
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        prev <= '1';
        cnt  <= (others => '0');
      else
        if sync /= prev then
          if cnt = DB_MAX then
            prev <= sync;              -- уровень подтверждён
            cnt  <= (others => '0');
          else
            cnt <= cnt + 1;            -- отсчитываем окно
          end if;
        else
          cnt <= (others => '0');      -- вернулось к подтверждённому
        end if;
      end if;
    end if;
  end process;
  
    -- Подтверждённый уровень и импульс на один такт в момент нажатия
  level <= prev;
  stb   <= '1' when (prev = '1' and sync = '0' and cnt = DB_MAX) else '0';
  
end architecture rtl;