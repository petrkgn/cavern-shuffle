-- /game/modules/constants.lua

local M = {}

-- === 1. БАЗОВЫЕ НАСТРОЙКИ ===
local DESIGN_WIDTH = 1024
local DESIGN_HEIGHT = 768

-- ГЛОБАЛЬНЫЙ МАСШТАБ
-- Попробуй 0.85. Если нужно больше места под кнопки -> ставь 0.8.
local GLOBAL_SCALE = 0.80

local BASE_CARD_WIDTH = 96
local BASE_CARD_HEIGHT = 138

-- Применяем масштаб
M.CARD_SCALE = 1.0 * GLOBAL_SCALE
M.CARD_WIDTH = BASE_CARD_WIDTH * M.CARD_SCALE
M.CARD_HEIGHT = BASE_CARD_HEIGHT * M.CARD_SCALE

M.OVERLAP_OFFSET = 24 * GLOBAL_SCALE -- Для каскада
local PADDING_X = 14 * GLOBAL_SCALE
local PADDING_Y = 15 * GLOBAL_SCALE

-- === 2. РАСЧЕТ ГОРИЗОНТАЛИ (X) ===
-- Ширина поля = 8 карт + 7 отступов
local TOTAL_BOARD_WIDTH = (8 * M.CARD_WIDTH) + (7 * PADDING_X)

-- Центрируем по X
local START_X = (DESIGN_WIDTH - TOTAL_BOARD_WIDTH) / 2 + (M.CARD_WIDTH / 2)

M.COLUMN_X = {}
local current_x = START_X
for i = 1, 8 do
	M.COLUMN_X[i] = current_x
	current_x = current_x + M.CARD_WIDTH + PADDING_X
end

-- === 3. РАСЧЕТ ВЕРТИКАЛИ (Y) С АВТО-ЦЕНТРИРОВАНИЕМ ===

-- У нас в игре максимальная высота структуры задается левой колонкой.
-- Там 5 слотов: 1 (Explore) + 4 (Inventory).
local NUM_ROWS = 5

-- Считаем полную высоту контента (Карты + Промежутки)
local TOTAL_CONTENT_HEIGHT = (NUM_ROWS * M.CARD_HEIGHT) + ((NUM_ROWS - 1) * PADDING_Y)

-- Считаем, сколько всего свободного места осталось на экране
local TOTAL_FREE_SPACE_Y = DESIGN_HEIGHT - TOTAL_CONTENT_HEIGHT

-- Делим свободное место пополам: половина пойдет наверх, половина вниз.
local MARGIN_TOP = TOTAL_FREE_SPACE_Y / 2

-- === 4. УСТАНОВКА КООРДИНАТ РЯДОВ ===
M.ROW_Y = {}

-- Ряд 1 (Самый верхний)
-- Координата Y в Defold (0 внизу).
-- Позиция = ВысотаЭкрана - ОтступСверху - ПоловинаКарты
M.ROW_Y[1] = DESIGN_HEIGHT - MARGIN_TOP - (M.CARD_HEIGHT / 2)

-- Остальные ряды строятся относительно первого вниз
for i = 2, 5 do
	M.ROW_Y[i] = M.ROW_Y[i-1] - M.CARD_HEIGHT - PADDING_Y
end

-- === ДЕБАГ ИНФО (Можно убрать потом) ===
print("--- CONSTANTS CALCULATION ---")
print("Scale:", GLOBAL_SCALE)
print("Content Height:", TOTAL_CONTENT_HEIGHT)
print("Free Space Total:", TOTAL_FREE_SPACE_Y)
print("Top/Bottom Margin:", MARGIN_TOP)
print("-----------------------------")

return M