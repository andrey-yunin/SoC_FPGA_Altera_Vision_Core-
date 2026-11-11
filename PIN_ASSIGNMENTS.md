# Назначения выводов Vision Core для DE1-SoC

Подготовлено 2026-11-06. Основание: руководство Terasic DE1-SoC User Manual, 28 January 2019, редакция для rev.F/G. Ревизия экземпляра пользователя ещё не подтверждена; сверка 9 ноября. Таблица импортирована пользователем через CSV; в основном QSF проверены 41 Location и 41 IO_STANDARD.

Источник: [руководство Terasic, копия на сайте Altera](https://community.altera.com/t5/s/jgyke29768/attachments/jgyke29768/fpga-device/73098/1/DE1-SoC_User_manual_revf.pdf).

Таблицы 3-5 (с.22, такт), 3-7 (с.25, кнопки), 3-20 (с.39–40, SDRAM). Назначения SDRAM и CLOCK_50 прочитаны из руководства и совпали с локальным донорским SDRAM.qsf. Донор не используется как единственный источник.

Проектное предложение: RESET_N подключить к пользовательской кнопке KEY[0]. Нажатие даёт низкий уровень, что соответствует активному низким уровнем сбросу верхнего модуля. Это выбранная функция пользовательской кнопки, а не отдельный штатный вывод сброса всей платы или HPS.

В руководстве DRAM_LDQM и DRAM_UDQM переименованы для нашего верха в DRAM_DQM[0] и DRAM_DQM[1]. Для SDRAM руководство указывает 3.3-V LVCMOS; для CLOCK_50 и KEY[0] в таблицах указано 3.3 V. При подготовке QSF электрический стандарт указывать явно с учётом исходного reference project и банков; не ограничиваться только номерами выводов. Эта таблица не задаёт SDC, фазу PLL или параметры выходных драйверов.

| Порт нашего верха | Вывод FPGA |
|---|---|
| `CLOCK_50` | `PIN_AF14` |
| `RESET_N` | `PIN_AA14` |
| `DRAM_ADDR[0]` | `PIN_AK14` |
| `DRAM_ADDR[1]` | `PIN_AH14` |
| `DRAM_ADDR[2]` | `PIN_AG15` |
| `DRAM_ADDR[3]` | `PIN_AE14` |
| `DRAM_ADDR[4]` | `PIN_AB15` |
| `DRAM_ADDR[5]` | `PIN_AC14` |
| `DRAM_ADDR[6]` | `PIN_AD14` |
| `DRAM_ADDR[7]` | `PIN_AF15` |
| `DRAM_ADDR[8]` | `PIN_AH15` |
| `DRAM_ADDR[9]` | `PIN_AG13` |
| `DRAM_ADDR[10]` | `PIN_AG12` |
| `DRAM_ADDR[11]` | `PIN_AH13` |
| `DRAM_ADDR[12]` | `PIN_AJ14` |
| `DRAM_BA[0]` | `PIN_AF13` |
| `DRAM_BA[1]` | `PIN_AJ12` |
| `DRAM_CAS_N` | `PIN_AF11` |
| `DRAM_CKE` | `PIN_AK13` |
| `DRAM_CLK` | `PIN_AH12` |
| `DRAM_CS_N` | `PIN_AG11` |
| `DRAM_DQ[0]` | `PIN_AK6` |
| `DRAM_DQ[1]` | `PIN_AJ7` |
| `DRAM_DQ[2]` | `PIN_AK7` |
| `DRAM_DQ[3]` | `PIN_AK8` |
| `DRAM_DQ[4]` | `PIN_AK9` |
| `DRAM_DQ[5]` | `PIN_AG10` |
| `DRAM_DQ[6]` | `PIN_AK11` |
| `DRAM_DQ[7]` | `PIN_AJ11` |
| `DRAM_DQ[8]` | `PIN_AH10` |
| `DRAM_DQ[9]` | `PIN_AJ10` |
| `DRAM_DQ[10]` | `PIN_AJ9` |
| `DRAM_DQ[11]` | `PIN_AH9` |
| `DRAM_DQ[12]` | `PIN_AH8` |
| `DRAM_DQ[13]` | `PIN_AH7` |
| `DRAM_DQ[14]` | `PIN_AJ6` |
| `DRAM_DQ[15]` | `PIN_AJ5` |
| `DRAM_DQM[0]` | `PIN_AB13` |
| `DRAM_RAS_N` | `PIN_AE13` |
| `DRAM_DQM[1]` | `PIN_AK12` |
| `DRAM_WE_N` | `PIN_AA13` |

Всего 41 физический сигнал текущего верхнего уровня. Avalon, pll_locked и pll_not_locked остаются внутренними и пинов не требуют. Рабочий файл импорта — `fpga/de1_soc_pins.csv`; в `fpga/vision_core_top.qsf` проверено совпадение всех назначений и стандартов, конфликтов нет. Импорт выполняет пользователь через GUI. Для дополнений редактировать CSV и повторять импорт. Проверка ревизии платы, ограничений и тайминга ещё предстоит.

## Пользовательские вводы-выводы — 2026-11-11

Добавлено 55 назначений: переключатели, кнопки и семисегментные индикаторы.
Источник — официальный baseline pinout Terasic, поставляемый с Quartus
(`quartus/common/devplatforms/DE1_SoC_Board/DE1_SoC_Board.qar`, внутри `platform_setup.tcl`).
Перекрёстная проверка: `KEY[0] = PIN_AA14` совпал с уже используемым `RESET_N`.

Стандарт всех новых выводов — `3.3-V LVCMOS`, как у DRAM (у Terasic в baseline указан `3.3-V LVTTL`;
смешивать стандарты в одном банке нежелательно).

| Порт нашего верха | Вывод FPGA |
|---|---|
| `SW[0]` | `PIN_AB12` |
| `SW[1]` | `PIN_AC12` |
| `SW[2]` | `PIN_AF9` |
| `SW[3]` | `PIN_AF10` |
| `SW[4]` | `PIN_AD11` |
| `SW[5]` | `PIN_AD12` |
| `SW[6]` | `PIN_AE11` |
| `SW[7]` | `PIN_AC9` |
| `SW[8]` | `PIN_AD10` |
| `SW[9]` | `PIN_AE12` |
| `KEY[1]` | `PIN_AA15` |
| `KEY[2]` | `PIN_W15` |
| `KEY[3]` | `PIN_Y16` |
| `HEX0[0]` | `PIN_AE26` |
| `HEX0[1]` | `PIN_AE27` |
| `HEX0[2]` | `PIN_AE28` |
| `HEX0[3]` | `PIN_AG27` |
| `HEX0[4]` | `PIN_AF28` |
| `HEX0[5]` | `PIN_AG28` |
| `HEX0[6]` | `PIN_AH28` |
| `HEX1[0]` | `PIN_AJ29` |
| `HEX1[1]` | `PIN_AH29` |
| `HEX1[2]` | `PIN_AH30` |
| `HEX1[3]` | `PIN_AG30` |
| `HEX1[4]` | `PIN_AF29` |
| `HEX1[5]` | `PIN_AF30` |
| `HEX1[6]` | `PIN_AD27` |
| `HEX2[0]` | `PIN_AB23` |
| `HEX2[1]` | `PIN_AE29` |
| `HEX2[2]` | `PIN_AD29` |
| `HEX2[3]` | `PIN_AC28` |
| `HEX2[4]` | `PIN_AD30` |
| `HEX2[5]` | `PIN_AC29` |
| `HEX2[6]` | `PIN_AC30` |
| `HEX3[0]` | `PIN_AD26` |
| `HEX3[1]` | `PIN_AC27` |
| `HEX3[2]` | `PIN_AD25` |
| `HEX3[3]` | `PIN_AC25` |
| `HEX3[4]` | `PIN_AB28` |
| `HEX3[5]` | `PIN_AB25` |
| `HEX3[6]` | `PIN_AB22` |
| `HEX4[0]` | `PIN_AA24` |
| `HEX4[1]` | `PIN_Y23` |
| `HEX4[2]` | `PIN_Y24` |
| `HEX4[3]` | `PIN_W22` |
| `HEX4[4]` | `PIN_W24` |
| `HEX4[5]` | `PIN_V23` |
| `HEX4[6]` | `PIN_W25` |
| `HEX5[0]` | `PIN_V25` |
| `HEX5[1]` | `PIN_AA28` |
| `HEX5[2]` | `PIN_Y27` |
| `HEX5[3]` | `PIN_AB27` |
| `HEX5[4]` | `PIN_AB26` |
| `HEX5[5]` | `PIN_AA26` |
| `HEX5[6]` | `PIN_AA25` |

`KEY[0]` занят под `RESET_N` и в этот список не входит. `KEY[3]` назначен, но логикой не используется:
в верхнем уровне задействованы только `KEY[1]` (запись) и `KEY[2]` (чтение).

Особенность инструмента: импорт CSV подхватывает колонку `I/O Standard`, но колонку `Location Pin`
Quartus не понимает — назначения при этом молча не применяются (`Critical Warning 169085`).
Рабочий путь — `set_location_assignment` прямо в `fpga/vision_core_top.qsf` и переоткрытие проекта.
