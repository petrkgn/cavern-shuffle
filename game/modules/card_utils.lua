-- game/modules/card_utils.lua
local GameConfig = require("game.modules.game_config")

local M = {}

M.FACES = { "A", "02", "03", "04", "05", "06", "07", "08", "09", "10", "J", "Q", "K" }
M.SUITS = { "clubs", "diamonds", "hearts", "spades" }

-- Какая карта идет перед текущей (для правил пасьянса)
M.LESS_TABLE = {
	["K"] = "Q",
	["Q"] = "J",
	["J"] = "10",
	["10"] = "09",
	["09"] = "08",
	["08"] = "07",
	["07"] = "06",
	["06"] = "05",
	["05"] = "04",
	["04"] = "03",
	["03"] = "02",
	["02"] = "A",
}

function M.create_standard_deck()
	local cards = {}
	for _, s in ipairs(M.SUITS) do
		for _, f in ipairs(M.FACES) do
			-- Каждая карта теперь просто таблица с данными
			table.insert(cards, { face = f, suit = s, go_id = nil, is_hidden = true })
		end
	end
	return cards
end

function M.shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

-- Находит карту по имени/масти и удаляет ее из колоды, возвращая саму карту
function M.find_and_remove_card(deck_cards, face, suit)
	for i = #deck_cards, 1, -1 do
		local card = deck_cards[i]
		if card.face == face and card.suit == suit then
			return table.remove(deck_cards, i)
		end
	end
	return nil -- Карта не найдена
end

-- ВОЗВРАЩАЕТ ПОЛНУЮ ИНФОРМАЦИЮ О КАРТЕ
function M.get_card_info(card)
	-- ★★★ КРИТИЧЕСКИ ВАЖНО: СПЕЦИАЛЬНАЯ ОБРАБОТКА ДЖОКЕРА ★★★
	if card.face == "joker" then
		return {
			face = "joker",
			suit = nil,
			go_id = card.go_id,
			is_hidden = card.is_hidden,
			value = nil, -- Джокер не имеет числового значения
			type = GameConfig.TYPE_ITEM, -- Это предмет
			name = "Joker",
			is_joker = true, -- Флаг для идентификации в правилах
		}
	end

	-- ... остальной код без изменений ...

	local info = {
		face = card.face,
		suit = card.suit,
		go_id = card.go_id,
		is_hidden = card.is_hidden,
		value = GameConfig.DEFAULT_FACE_VALUES[card.face],
		type = GameConfig.TYPE_ADVENTURER,
	}

	local key = card.face .. "_" .. card.suit
	local definition = GameConfig.CARD_DEFINITIONS[key]

	if definition then
		for k, v in pairs(definition) do
			info[k] = v
		end
	end

	return info
end

return M
