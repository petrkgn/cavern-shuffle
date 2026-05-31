-- /game/modules/game_config.lua

local M = {}

-- ===============================================
-- === КОНФИГУРАЦИЯ ДЛЯ "DRAGON'S SOLITAIRE" ===
-- ===============================================

-- 1. Типы карт
M.TYPE_ADVENTURER = "adventurer"
M.TYPE_OBSTACLE = "obstacle"
M.TYPE_ENEMY = "enemy"
M.TYPE_ITEM = "item"
M.TYPE_BOSS = "boss"

-- 2. "Маппинг" карт на их игровые роли
M.CARD_DEFINITIONS = {
	-- === БОСС ===
	["K_spades"] = { type = M.TYPE_BOSS, name = "Minotaur", power = 30 },

	-- === ВРАГИ (Короли) ===
	["K_hearts"] = { type = M.TYPE_ENEMY, name = "Goblin Champion", power = 15 },
	["K_diamonds"] = { type = M.TYPE_ENEMY, name = "Giant Spider", power = 12 },
	["K_clubs"] = { type = M.TYPE_ENEMY, name = "Ogre", power = 20 },

	-- === ПРЕПЯТСТВИЯ (Дамы) ===
	["Q_spades"] = { type = M.TYPE_OBSTACLE, name = "Spike Trap", target_suit = "spades" },
	["Q_hearts"] = { type = M.TYPE_OBSTACLE, name = "Rushing Water", target_suit = "hearts" },
	["Q_diamonds"] = { type = M.TYPE_OBSTACLE, name = "Locked Door", target_suit = "diamonds" },
	["Q_clubs"] = { type = M.TYPE_OBSTACLE, name = "Dense Webbing", target_suit = "clubs" },

	-- === ПРЕДМЕТЫ (Валеты) ===
	["J_spades"] = { type = M.TYPE_ITEM, name = "Potion of Strength" },
	["J_hearts"] = { type = M.TYPE_ITEM, name = "Treasure", is_placeholder = true },
	["J_diamonds"] = { type = M.TYPE_ITEM, name = "Minor Illusion", is_placeholder = true },
	["J_clubs"] = {
		type = M.TYPE_ITEM,
		name = "Short Rest",
		transforms_to = "joker", -- Флаг: после использования становится джокером
	},

	-- === СПЕЦИАЛЬНАЯ КАРТА: ДЖОКЕР ===
	["joker"] = {
		type = M.TYPE_ITEM,
		name = "Joker",
		is_joker = true,
		sprite_id = "item_joker", -- Имя анимации в атласе (проверь его!)
		restores_to = {
			["inventory_1"] = "J_clubs", -- Слот 1 -> Возвращает Short Rest
			["inventory_2"] = "J_hearts", -- Слот 2 -> Возвращает Treasure
			["inventory_3"] = "J_diamonds", -- Слот 3 -> Возвращает Minor Illusion
			["inventory_4"] = "J_spades", -- Слот 4 -> Возвращает Potion
		},
	},
}

-- 3. Стандартные значения рангов
M.DEFAULT_FACE_VALUES = {
	["A"] = 1,
	["02"] = 2,
	["03"] = 3,
	["04"] = 4,
	["05"] = 5,
	["06"] = 6,
	["07"] = 7,
	["08"] = 8,
	["09"] = 9,
	["10"] = 10,
	["J"] = 11,
	["Q"] = 12,
	["K"] = 13,
}

return M
