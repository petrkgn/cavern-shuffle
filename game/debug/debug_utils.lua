-- /game/debug/debug_utils.lua
-- Отладочные утилиты для тестирования специфичных игровых ситуаций

local M = {}

-- === ГЛОБАЛЬНЫЙ ФЛАГ ОТЛАДКИ ===
-- Установите в true, чтобы включить отладочные функции
M.DEBUG_MODE = false

local CONST = require("game.modules.constants")

-- Вспомогательная функция: создаёт GO для карты
local function create_card_go(card_data, pos, is_hidden)
	card_data.go_id = factory.create(
		"#card_factory",
		pos,
		nil,
		{
			face = hash(card_data.face),
			suit = hash(card_data.suit),
			hidden = is_hidden and hash("hidden") or hash("")
		},
		CONST.CARD_SCALE
	)
	if not is_hidden then
		-- Небольшая задержка чтобы reveal сработал после создания
		timer.delay(0.05, false, function()
			if card_data.go_id then
				msg.post(card_data.go_id, "reveal")
			end
		end)
	end
	return card_data.go_id
end

-- === СПЕЦИАЛЬНЫЕ РАСКЛАДКИ ===

-- Раскладка для проверки задачи #2 (дубликат под драконом)
--   - inventory_1: Treasure (J_hearts)
--   - dungeon_3: Dragon (K_spades) поверх закрытой 2_hearts
--   - party_1: Ace of Hearts (A_hearts)
function M.setup_debug_deal(state)
	if not M.DEBUG_MODE then return end

	print("=== DEBUG MODE: Setting up test layout for Task #2 ===")

	-- Очищаем все стопки
	for id, pile in pairs(state.piles) do
		pile.cards = {}
	end
	state.discard_pile.cards = {}
	state.graveyard.cards = {}
	state.created_cards = {}

	-- Очищаем explore pile
	state.piles.explore.cards = {}

	-- 1. Предметы: Treasure в inventory_1
	local treasure = { face = "J", suit = "hearts", is_hidden = false }
	table.insert(state.piles.inventory_1.cards, treasure)
	local inv1_pos = state.piles.inventory_1.pos
	create_card_go(treasure, vmath.vector3(inv1_pos.x, inv1_pos.y, 0.01), false)

	-- 2. Подземелье dungeon_3: закрытая 2_hearts + Dragon (Minotaur) сверху
	local two_hearts = { face = "02", suit = "hearts", is_hidden = true }
	local dragon = { face = "K", suit = "spades", is_hidden = false }
	table.insert(state.piles.dungeon_3.cards, two_hearts)
	table.insert(state.piles.dungeon_3.cards, dragon)

	local dung3_pos = state.piles.dungeon_3.pos
	local cascade_offset = CONST.OVERLAP_OFFSET
	-- Нижняя карта (2_hearts) - закрытая
	create_card_go(two_hearts, vmath.vector3(dung3_pos.x, dung3_pos.y, 0.01), true)
	-- Верхняя карта (dragon) - открытая, со сдвигом каскада
	create_card_go(dragon, vmath.vector3(dung3_pos.x, dung3_pos.y - cascade_offset, 0.02), false)

	-- Устанавливаем позицию Минотавра на 3 (dungeon_3)
	state.minotaur_pos = 3
	state.minotaur_dir = 1

	-- 3. Отряд: A_hearts в party_1
	local ace_hearts = { face = "A", suit = "hearts", is_hidden = false }
	table.insert(state.piles.party_1.cards, ace_hearts)
	local party1_pos = state.piles.party_1.pos
	create_card_go(ace_hearts, vmath.vector3(party1_pos.x, party1_pos.y, 0.01), false)

	-- Обновляем уровень и силу отряда
	state.party_levels.hearts = 1
	state.party_power = 1

	-- Помечаем игру как разданную
	state.is_dealt = true

	-- Блокируем explore чтобы обычный deal не сработал при клике
	state.piles.explore.can_use = false

	print("=== DEBUG LAYOUT READY ===")
	print("  - inventory_1: Treasure (J_hearts)")
	print("  - dungeon_3: Dragon (K_spades) over hidden 2_hearts")
	print("  - party_1: Ace of Hearts (A_hearts)")
	print("=== Use Treasure on A_hearts to test duplicate detection ===")
end

-- === СТАРЫЕ ФУНКЦИИ ПРОВЕРКИ ===

-- 1. Тест улета дубликатов из Талона
function M.deal_debug_talon_duplicate(state)
	if state.is_dealt then return end
	print("!!! DEBUG SETUP: RIGGING DECK FOR DUPLICATE CHECK !!!")

	local CardUtils = require("game.modules.card_utils")
	local explore_pile = state.piles.explore

	CardUtils.shuffle(explore_pile.cards)

	local minotaur_card = CardUtils.find_and_remove_card(explore_pile.cards, "K", "spades")
	local short_rest_card = CardUtils.find_and_remove_card(explore_pile.cards, "J", "clubs")

	if minotaur_card then
		minotaur_card.is_hidden = false
		table.insert(state.piles.dungeon_1.cards, minotaur_card)
	end
	if short_rest_card then
		short_rest_card.is_hidden = false
		table.insert(state.piles.inventory_1.cards, short_rest_card)
	end

	for i = 2, 7 do
		local pile = state.piles["dungeon_" .. i]
		for c = 1, i do
			if #explore_pile.cards > 0 then
				local card = table.remove(explore_pile.cards)
				card.is_hidden = (c ~= i)
				table.insert(pile.cards, card)
			end
		end
	end

	local cards_count = #explore_pile.cards
	local traps_count = math.min(3, cards_count)

	if traps_count > 0 then
		print("DEBUG: Setting traps on the next " .. traps_count .. " cards to be drawn...")
		for i = 0, traps_count - 1 do
			local card_trap = explore_pile.cards[cards_count - i]
			local key = card_trap.face .. "_" .. card_trap.suit
			state.created_cards[key] = true
			print("DEBUG: TRAP SET on [" .. key .. "] (Position from end: " .. i .. ")")
		end
		print("DEBUG: Click the deck to see them fly away one by one!")
	end
end

-- 2. Тест переворота карты в стопке (Reveal)
function M.deal_debug_dungeon_reveal(state)
	if state.is_dealt then return end
	print("!!! DEBUG SETUP: RIGGING DUNGEON (NUMBERED CARDS) !!!")

	local CardUtils = require("game.modules.card_utils")
	local explore_pile = state.piles.explore
	CardUtils.shuffle(explore_pile.cards)
	CardUtils.find_and_remove_card(explore_pile.cards, "K", "spades")

	for i = 1, 7 do
		local pile = state.piles["dungeon_" .. i]
		for c = 1, i do
			if #explore_pile.cards > 0 then
				local card = table.remove(explore_pile.cards)
				card.is_hidden = (c ~= i)
				table.insert(pile.cards, card)
			end
		end
	end

	local pile_2 = state.piles.dungeon_2
	pile_2.cards[#pile_2.cards] = { face = "05", suit = "hearts", is_hidden = false }

	local pile_3 = state.piles.dungeon_3
	pile_3.cards[#pile_3.cards] = { face = "04", suit = "clubs", is_hidden = false }

	local trap_index = #pile_3.cards - 1
	if trap_index > 0 then
		local trap_card = { face = "09", suit = "diamonds", is_hidden = true }
		pile_3.cards[trap_index] = trap_card

		local key = trap_card.face .. "_" .. trap_card.suit
		state.created_cards[key] = true

		print("DEBUG: Setup Complete.")
		print("ACTION: Drag [04 clubs] (Col 3) onto [05 hearts] (Col 2).")
		print("RESULT: [09 diamonds] will be revealed in Col 3 and should fly away.")
	end
end

-- 3. Тест разблокировки Минотавра (Unlock)
function M.deal_debug_minotaur_unlock(state)
	if state.is_dealt then return end
	print("!!! DEBUG SETUP: MINOTAUR UNLOCK DUPLICATE CHECK !!!")

	local CardUtils = require("game.modules.card_utils")
	local explore_pile = state.piles.explore
	CardUtils.shuffle(explore_pile.cards)

	CardUtils.find_and_remove_card(explore_pile.cards, "K", "spades")
	CardUtils.find_and_remove_card(explore_pile.cards, "J", "clubs")

	for i = 1, 7 do
		local pile = state.piles["dungeon_" .. i]
		for c = 1, i do
			if #explore_pile.cards > 0 then
				local card = table.remove(explore_pile.cards)
				card.is_hidden = (c ~= i)
				table.insert(pile.cards, card)
			end
		end
	end

	-- Настройка сцены
	state.minotaur_pos = 2

	local pile_2 = state.piles.dungeon_2
	pile_2.cards[#pile_2.cards] = { face = "09", suit = "diamonds", is_hidden = false }
	table.insert(pile_2.cards, { face = "K", suit = "spades", is_hidden = false })

	state.created_cards["09_diamonds"] = true

	state.party_levels["clubs"] = 0

	local pile_3 = state.piles.dungeon_3
	pile_3.cards[#pile_3.cards] = { face = "05", suit = "clubs", is_hidden = false }

	local pile_4 = state.piles.dungeon_4
	pile_4.cards[#pile_4.cards] = { face = "A", suit = "clubs", is_hidden = false }

	print("DEBUG: Setup Complete.")
	print("ACTION: Drag [04 clubs] from Col 4 to [05 clubs] in Col 3.")
	print("RESULT: Clubs Level Up -> Minotaur leaves Col 2 -> [09 diamonds] in Col 2 flies away.")
end

return M
