-- /game/modules/state.lua

local Pile = require("game.modules.pile")
local CardUtils = require("game.modules.card_utils")
local CONST = require("game.modules.constants")

local M = {}

M.data = {}

function M.init()
	-- Константы
	M.data.CARD_SCALE = CONST.CARD_SCALE
	M.data.CARD_WIDTH = CONST.CARD_WIDTH
	M.data.CARD_HEIGHT = CONST.CARD_HEIGHT
	M.data.OVERLAP_OFFSET = CONST.OVERLAP_OFFSET

	-- Игровое состояние
	M.data.mouse_x = 0
	M.data.mouse_y = 0
	M.data.is_dealt = false
	M.data.is_won = false
	M.data.piles = {} 
	M.data.discard_pile = { cards = {} }
	M.data.graveyard = { cards = {} }
	M.data.party_levels = { hearts = 0, diamonds = 0, spades = 0, clubs = 0 }
	M.data.party_power = 0
	M.data.minotaur_pos = 1
	M.data.minotaur_dir = 1
	M.data.obstacles_cleared = 0
	M.data.temporary_power_buff = { suit = nil, amount = 0 }
	M.data.created_cards = {}
	M.data.vortex_cards = {}     -- Карты, которые вращаются в хороводе
	M.data.restarting_cards = {} -- Карты, которые летят в колоду для перезапуска
	M.data.win_minotaur_card = nil   -- Будет хранить ОДНУ ТАБЛИЦУ карты Минотавра
	M.data.dragging = {
		cards = {},
		source_pile_id = nil,
		offset = vmath.vector3(0, 0, 0)
	}

	-- === РАССТАНОВКА СТОПОК ПО СЕТКЕ ===

-- 	-- 1. Левый блок (Столбец 1)
-- 	M.data.piles.explore = Pile.new({ id = "explore", pos = vmath.vector3(CONST.COLUMN_X[1], CONST.ROW_Y[1], 0), layout = Pile.LAYOUT_STACK })
-- 	for i = 1, 4 do
-- 		local id = "inventory_" .. i
-- 		M.data.piles[id] = Pile.new({ id = id, pos = vmath.vector3(CONST.COLUMN_X[1], CONST.ROW_Y[i + 1], 0), layout = Pile.LAYOUT_STACK })
-- 	end
-- 
-- 	-- 2. Центральный и правый блок
-- 	-- Talon (Столбец 2, Ряд 1)
-- 	M.data.piles.talon = Pile.new({ id = "talon", pos = vmath.vector3(CONST.COLUMN_X[2], CONST.ROW_Y[1], 0), layout = Pile.LAYOUT_STACK_OFFSET, face_up_by_default = true })
-- 	-- Discard (Столбец 3, Ряд 1)
-- 	M.data.piles.discard = Pile.new({ id = "discard", pos = vmath.vector3(CONST.COLUMN_X[3], CONST.ROW_Y[1], 0), layout = Pile.LAYOUT_STACK, face_up_by_default = true })
-- 
-- 	-- Отряд (Party) - Столбцы 5, 6, 7, 8 в Ряду 1
-- 	for i = 1, 4 do
-- 		local id = "party_" .. i
-- 		M.data.piles[id] = Pile.new({ id = id, pos = vmath.vector3(CONST.COLUMN_X[i + 4], CONST.ROW_Y[1], 0), layout = Pile.LAYOUT_STACK, face_up_by_default = true })
-- 	end
-- 
-- 	-- Подземелье (Dungeon) - Столбцы 2-8 в Ряду 2
-- 	for i = 1, 7 do
-- 		local id = "dungeon_" .. i
-- 		M.data.piles[id] = Pile.new({ id = id, pos = vmath.vector3(CONST.COLUMN_X[i + 1], CONST.ROW_Y[2], 0), layout = Pile.LAYOUT_CASCADE })
-- 	end

-- Explore (создается с плейсхолдером рубашки)
M.data.piles.explore = Pile.new({ id = "explore", pos = vmath.vector3(CONST.COLUMN_X[1], CONST.ROW_Y[1], 0), layout = Pile.LAYOUT_STACK, placeholder_sprite = "card_back" })

-- Inventory (создаются с персональными плейсхолдерами)
local inventory_placeholders = { "item_placeholder_1", "item_placeholder_2", "item_placeholder_3", "item_placeholder_4" }
for i = 1, 4 do
	local id = "inventory_" .. i
	M.data.piles[id] = Pile.new({ id = id, pos = vmath.vector3(CONST.COLUMN_X[1], CONST.ROW_Y[i + 1], 0), layout = Pile.LAYOUT_STACK, placeholder_sprite = inventory_placeholders[i] })
end

-- Talon (БЕЗ плейсхолдера)
M.data.piles.talon = Pile.new({ id = "talon", pos = vmath.vector3(CONST.COLUMN_X[2], CONST.ROW_Y[1], 0), layout = Pile.LAYOUT_STACK_OFFSET })
-- Discard (БЕЗ плейсхолдера)
M.data.piles.discard = Pile.new({ id = "discard", pos = vmath.vector3(CONST.COLUMN_X[3] + 50, CONST.ROW_Y[1], 0), layout = Pile.LAYOUT_STACK })

-- Party (создаются с персональными плейсхолдерами по мастям)
local party_suits = { "hearts", "diamonds", "spades", "clubs" }
for i, suit in ipairs(party_suits) do
	local id = "party_" .. i
	M.data.piles[id] = Pile.new({ id = id, pos = vmath.vector3(CONST.COLUMN_X[i + 4], CONST.ROW_Y[1], 0), layout = Pile.LAYOUT_STACK, suit = suit, placeholder_sprite = "party_placeholder_"..suit })
end

-- Dungeon (создаются БЕЗ плейсхолдеров)
for i = 1, 7 do
	local id = "dungeon_" .. i
	M.data.piles[id] = Pile.new({ id = id, pos = vmath.vector3(CONST.COLUMN_X[i + 1], CONST.ROW_Y[2], 0), layout = Pile.LAYOUT_CASCADE })
end

	-- Заполняем колоду добора картами
	M.data.piles.explore.cards = CardUtils.create_standard_deck()
end


function M.reset(state_data)
	-- 1. Очищаем все видимые стопки
	for id, pile in pairs(state_data.piles) do
		-- Удаляем все игровые объекты, связанные со стопкой
		for _, card in ipairs(pile.cards) do
			if card.go_id then
				go.delete(card.go_id)
				card.go_id = nil
			end
		end
		pile.cards = {}
	end
	-- Очищаем невидимые стопки
	state_data.discard_pile.cards = {}
	state_data.graveyard.cards = {}
	state_data.created_cards = {}

	-- 2. Сбрасываем состояние перетаскивания
	state_data.dragging = { cards = {}, source_pile_id = nil, offset = vmath.vector3() }

	-- 3. Сбрасываем игровые флаги и счетчики
	state_data.is_dealt = false
	state_data.is_won = false
	state_data.party_levels = { hearts = 0, diamonds = 0, spades = 0, clubs = 0 }
	state_data.party_power = 0
	state_data.minotaur_pos = 1
	state_data.minotaur_dir = 1
	state_data.obstacles_cleared = 0
	M.data.created_cards = {}
	state_data.vortex_cards = {}     -- <<-- Добавьте эту строку
	state_data.restarting_cards = {} -- <<-- И эту
	state_data.win_minotaur_card = nil
	state_data.temporary_power_buff = { suit = nil, amount = 0 }
	state_data.is_restarting = false -- "Размораживаем" игру

	-- 4. Заново создаем колоду
	state_data.piles.explore.cards = CardUtils.create_standard_deck()
end

return M