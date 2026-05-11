-- /game/debug/debug_utils.lua
-- Отладочные утилиты для тестирования специфичных игровых ситуаций.
--
-- === АРХИТЕКТУРНЫЙ ПРИНЦИП ===
-- State (state.lua) — единственный источник истины.
-- Systems (systems/) — читают и изменяют state.
-- Render (render_system.lua) — читает state и отрисовывает.
-- Дебаг-функции ТОЛЬКО готовят state (snapshot) — игрок сам взаимодействует,
-- системы сами обрабатывают. Никаких автоматических действий.
--
-- === ИНСТРУКЦИЯ ПО ИСПОЛЬЗОВАНИЮ ===
-- 1. Установите DEBUG_MODE = true (строка ниже)
-- 2. Запустите игру
-- 3. Нажмите F7 для циклического выбора дебаг-функции (выводится в консоль)
-- 4. Нажмите F2 для создания раскладки (сбрасывает предыдущую)
-- 5. Играйте: кликайте/перетаскивайте карты — системы обработают как обычно
--
-- === ДОБАВЛЕНИЕ НОВОЙ ДЕБАГ-ФУНКЦИИ ===
-- В конце файла добавьте вызов M.register_function():
--
--   M.register_function(
--       "Короткое имя",           -- name: отображается в консоли при выборе
--       "Описание кейса",         -- description: что тестируем, какие шаги
--       function(state)           -- setup(state): подготовка состояния
--           -- State уже сброшен (State.reset() вызван перед setup),
--           -- все стопки пусты, explore содержит новую стандартную колоду.
--           --
--           -- 1. Заполните нужные стопки картами (данные):
--           --    table.insert(state.piles.<pile_id>.cards, card_data)
--           --
--           -- 2. Создайте GO для каждой карты:
--           --    create_card_go(card_data, position, is_hidden)
--           --    (create_card_go — локальная функция в этом файле)
--           --
--           -- 3. Установите флаги:
--           --    state.is_dealt = true
--           --    state.piles.explore.can_use = true/false
--           --
--           -- 4. При необходимости настройте:
--           --    state.minotaur_pos, state.minotaur_dir
--           --    state.party_levels, state.party_power
--           --    state.created_cards[key] = true (для ловушек)
--       end
--   )
--
-- Правила для setup:
--   - Используйте create_card_go(card_data, pos, is_hidden) для создания GO
--   - Для cascade-стопок (dungeon): карты снизу вверх,
--     Z = 0.01 + (index-1)*0.01,
--     Y = pile.pos.y - (index-1)*CONST.OVERLAP_OFFSET
--   - Для stack-стопок: все карты в позиции pile.pos, Z по порядку
--   - После setup обязательно state.is_dealt = true
--   - Не вызывайте GameFlowSystem или другие системы — только данные!

local M = {}

-- === ГЛОБАЛЬНЫЙ ФЛАГ ОТЛАДКИ ===
-- Установите в true, чтобы включить отладочные функции
M.DEBUG_MODE = true

local CONST = require("game.modules.constants")
local CardUtils = require("game.modules.card_utils")
local State = require("game.modules.state")

-- ============================================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================================================

-- Создаёт GO для карты и возвращает go_id
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
		timer.delay(0.05, false, function()
			if card_data.go_id then
				msg.post(card_data.go_id, "reveal")
			end
		end)
	end
	return card_data.go_id
end

-- Раскладывает карты из explore в dungeon_2..dungeon_7 трапецией
-- (как в обычной раздаче) и создаёт GO для каждой выложенной карты
local function deal_dungeon_trapezoid(state, explore_pile)
	for i = 2, 7 do
		local pile = state.piles["dungeon_" .. i]
		for c = 1, i do
			if #explore_pile.cards > 0 then
				local card = table.remove(explore_pile.cards)
				card.is_hidden = (c ~= i)
				table.insert(pile.cards, card)
				local pos_y = pile.pos.y - (c - 1) * CONST.OVERLAP_OFFSET
				local pos_z = 0.01 + (c - 1) * 0.01
				create_card_go(card, vmath.vector3(pile.pos.x, pos_y, pos_z), card.is_hidden)
			end
		end
	end
end

-- ============================================================================
-- СОСТОЯНИЕ ДЕБАГГЕРА
-- ============================================================================

-- Индекс выбранной функции в реестре (0 = ничего не выбрано)
M.selected_index = 0

-- true если setup текущей выбранной функции был выполнен
M.is_setup = false

-- Реестр дебаг-функций: массив объектов {name, description, setup}
M.functions = {}

-- ============================================================================
-- API ДЕБАГГЕРА
-- ============================================================================

-- Регистрирует новую дебаг-функцию в реестре
function M.register_function(name, description, setup_fn)
	table.insert(M.functions, {
		name = name,
		description = description,
		setup = setup_fn,
	})
	print("DEBUG: Registered function [" .. #M.functions .. "] " .. name)
end

-- Циклический выбор следующей дебаг-функции (F7)
function M.select_next()
	if #M.functions == 0 then
		print("DEBUG: No debug functions registered!")
		return
	end

	M.selected_index = M.selected_index + 1
	if M.selected_index > #M.functions then
		M.selected_index = 1
	end
	M.is_setup = false

	local fn = M.functions[M.selected_index]
	print("")
	print("=== DEBUG SELECT [" .. M.selected_index .. "/" .. #M.functions .. "] ===")
	print("  Name: " .. fn.name)
	print("  Description: " .. fn.description)
	print("  Press F2 to set up this layout")
	print("==========================================")
end

-- Выполняет setup выбранной функции (F2)
function M.run_setup(state)
	if M.selected_index <= 0 then
		print("DEBUG: No function selected! Press F7 first.")
		return
	end

	local fn = M.functions[M.selected_index]

	-- Всегда сбрасываем предыдущее состояние перед новым setup
	print("DEBUG: Resetting previous debug state...")
	State.reset(state)

	print("")
	print("=== DEBUG SETUP [" .. M.selected_index .. "/" .. #M.functions .. "] ===")
	print("  Name: " .. fn.name)
	print("  Setting up layout...")

	-- Вызываем setup-функцию (только готовит state)
	fn.setup(state)
	M.is_setup = true

	print("  Setup complete! Play the game to test.")
	print("==============================================")
end

-- ============================================================================
-- === ЗАРЕГИСТРИРОВАННЫЕ ДЕБАГ-ФУНКЦИИ ===
-- ============================================================================

-- ---------------------------------------------------------------------------
-- #1: Talon Duplicate Check
-- Проверка дубликатов в Talon после добора из Explore.
-- Состояние: dungeon разложен, в explore установлены ловушки на верхних картах.
-- Игрок кликает Explore → 3 карты перелетят в Talon → check_talon найдёт дубликаты.
-- ---------------------------------------------------------------------------
M.register_function(
	"Talon Duplicate Check",
	"Проверка дубликатов в Talon после добора из Explore.\n"
	.. "  Состояние: разложены dungeon 1-7, на верхних картах explore — ловушки.\n"
	.. "  Игрок кликает Explore → 3 карты в Talon → check_talon() находит дубликаты.",
	function(state)
		local explore_pile = state.piles.explore

		-- Убираем Минотавра и Short Rest из колоды
		local minotaur_card = CardUtils.find_and_remove_card(explore_pile.cards, "K", "spades")
		local short_rest_card = CardUtils.find_and_remove_card(explore_pile.cards, "J", "clubs")

		CardUtils.shuffle(explore_pile.cards)

		if minotaur_card then
			minotaur_card.is_hidden = false
			table.insert(state.piles.dungeon_1.cards, minotaur_card)
			local d1_pos = state.piles.dungeon_1.pos
			create_card_go(minotaur_card, vmath.vector3(d1_pos.x, d1_pos.y, 0.01), false)
		end
		if short_rest_card then
			short_rest_card.is_hidden = false
			table.insert(state.piles.inventory_1.cards, short_rest_card)
			local inv1_pos = state.piles.inventory_1.pos
			create_card_go(short_rest_card, vmath.vector3(inv1_pos.x, inv1_pos.y, 0.01), false)
		end

		-- Раскладываем dungeon 2..7 трапецией
		deal_dungeon_trapezoid(state, explore_pile)

		-- Устанавливаем ловушки на последние 3 карты explore
		local cards_count = #explore_pile.cards
		local traps_count = math.min(3, cards_count)

		if traps_count > 0 then
			print("DEBUG: Setting traps on " .. traps_count .. " cards in explore...")
			for i = 0, traps_count - 1 do
				local card_trap = explore_pile.cards[cards_count - i]
				local key = card_trap.face .. "_" .. card_trap.suit
				state.created_cards[key] = true
				print("DEBUG: TRAP SET on [" .. key .. "]")
			end
		end

		state.is_dealt = true
		explore_pile.can_use = true
	end
)

-- ---------------------------------------------------------------------------
-- #2: Dungeon Reveal Duplicate
-- Проверка дубликата при открытии карты в подземелье.
-- Состояние: все dungeon разложены, в dungeon_3 под 04_clubs спрятан 09_diamonds (ловушка).
-- Игрок перетаскивает 04_clubs на 05_hearts (dungeon_2) → открывается 09_diamonds → улетает.
-- ---------------------------------------------------------------------------
M.register_function(
	"Dungeon Reveal Duplicate",
	"Проверка дубликата при открытии карты в подземелье.\n"
	.. "  Состояние: dungeon 1-7 разложены, в dungeon_3 под 04_clubs спрятан 09_diamonds (ловушка).\n"
	.. "  Drag [04_clubs] (Col 3) → [05_hearts] (Col 2) → откроется [09_diamonds] → улетит.",
	function(state)
		local explore_pile = state.piles.explore

		-- Убираем K_spades
		CardUtils.find_and_remove_card(explore_pile.cards, "K", "spades")
		CardUtils.shuffle(explore_pile.cards)

		-- Раскладываем dungeon 2..7 трапецией
		deal_dungeon_trapezoid(state, explore_pile)

		-- Заполняем dungeon_1 одной картой для полноты
		if #explore_pile.cards > 0 then
			local pile = state.piles.dungeon_1
			local card = table.remove(explore_pile.cards)
			card.is_hidden = false
			table.insert(pile.cards, card)
			create_card_go(card, vmath.vector3(pile.pos.x, pile.pos.y, 0.01), false)
		end

		-- Подменяем верхние карты согласно сценарию
		local pile_2 = state.piles.dungeon_2
		if pile_2.cards[#pile_2.cards] and pile_2.cards[#pile_2.cards].go_id then
			go.delete(pile_2.cards[#pile_2.cards].go_id)
			pile_2.cards[#pile_2.cards].go_id = nil
		end
		local card_05_hearts = { face = "05", suit = "hearts", is_hidden = false }
		pile_2.cards[#pile_2.cards] = card_05_hearts
		local pos_2_y = pile_2.pos.y - (#pile_2.cards - 1) * CONST.OVERLAP_OFFSET
		local pos_2_z = 0.01 + (#pile_2.cards - 1) * 0.01
		create_card_go(card_05_hearts, vmath.vector3(pile_2.pos.x, pos_2_y, pos_2_z), false)

		local pile_3 = state.piles.dungeon_3
		if pile_3.cards[#pile_3.cards] and pile_3.cards[#pile_3.cards].go_id then
			go.delete(pile_3.cards[#pile_3.cards].go_id)
			pile_3.cards[#pile_3.cards].go_id = nil
		end
		local card_04_clubs = { face = "04", suit = "clubs", is_hidden = false }
		pile_3.cards[#pile_3.cards] = card_04_clubs
		local pos_3_y = pile_3.pos.y - (#pile_3.cards - 1) * CONST.OVERLAP_OFFSET
		local pos_3_z = 0.01 + (#pile_3.cards - 1) * 0.01
		create_card_go(card_04_clubs, vmath.vector3(pile_3.pos.x, pos_3_y, pos_3_z), false)

		-- Ловушка: скрытый 09_diamonds под верхней картой dungeon_3
		local trap_index = #pile_3.cards - 1
		if trap_index > 0 then
			if pile_3.cards[trap_index] and pile_3.cards[trap_index].go_id then
				go.delete(pile_3.cards[trap_index].go_id)
				pile_3.cards[trap_index].go_id = nil
			end
			local trap_card = { face = "09", suit = "diamonds", is_hidden = true }
			pile_3.cards[trap_index] = trap_card

			local key = trap_card.face .. "_" .. trap_card.suit
			state.created_cards[key] = true

			local trap_y = pile_3.pos.y - (trap_index - 1) * CONST.OVERLAP_OFFSET
			local trap_z = 0.01 + (trap_index - 1) * 0.01
			create_card_go(trap_card, vmath.vector3(pile_3.pos.x, trap_y, trap_z), true)
		end

		state.is_dealt = true
		state.piles.explore.can_use = true
	end
)

-- ---------------------------------------------------------------------------
-- #3: Minotaur Unlock Duplicate
-- Проверка дубликата при уходе Минотавра (повышение уровня отряда).
-- Состояние: Минотавр на позиции 2 над 09_diamonds (ловушка),
-- в dungeon_3 — 05_clubs, в dungeon_4 — A_clubs.
-- Игрок drag A_clubs → 05_clubs → Clubs Level Up → Минотавр уходит → 09_diamonds улетает.
-- ---------------------------------------------------------------------------
M.register_function(
	"Minotaur Unlock Duplicate",
	"Проверка дубликата при уходе Минотавра (повышение уровня отряда).\n"
	.. "  Состояние: Минотавр на Col 2 над 09_diamonds (ловушка), Col 3 = 05_clubs, Col 4 = A_clubs.\n"
	.. "  Drag [A_clubs] (Col 4) → [05_clubs] (Col 3) → Clubs Level Up → Минотавр уходит → 09_diamonds улетает.",
	function(state)
		local explore_pile = state.piles.explore

		-- Убираем Минотавра и Short Rest
		CardUtils.find_and_remove_card(explore_pile.cards, "K", "spades")
		CardUtils.find_and_remove_card(explore_pile.cards, "J", "clubs")
		CardUtils.shuffle(explore_pile.cards)

		-- Раскладываем dungeon 2..7
		deal_dungeon_trapezoid(state, explore_pile)

		-- Заполняем dungeon_1
		if #explore_pile.cards > 0 then
			local pile = state.piles.dungeon_1
			local card = table.remove(explore_pile.cards)
			card.is_hidden = false
			table.insert(pile.cards, card)
			create_card_go(card, vmath.vector3(pile.pos.x, pile.pos.y, 0.01), false)
		end

		-- Минотавр на позиции 2
		state.minotaur_pos = 2

		-- Пересобираем dungeon_2: скрытая карта → 09_diamonds → Минотавр
		local pile_2 = state.piles.dungeon_2
		for _, c in ipairs(pile_2.cards) do
			if c.go_id then go.delete(c.go_id); c.go_id = nil end
		end
		pile_2.cards = {}

		-- Скрытая карта (низ)
		local hidden_card = { face = "03", suit = "hearts", is_hidden = true }
		table.insert(pile_2.cards, hidden_card)
		create_card_go(hidden_card, vmath.vector3(pile_2.pos.x, pile_2.pos.y, 0.01), true)

		-- Открытая карта = 09_diamonds (ловушка)
		local top_card_2 = { face = "09", suit = "diamonds", is_hidden = false }
		table.insert(pile_2.cards, top_card_2)
		local pos_2_y = pile_2.pos.y - CONST.OVERLAP_OFFSET
		create_card_go(top_card_2, vmath.vector3(pile_2.pos.x, pos_2_y, 0.02), false)
		state.created_cards["09_diamonds"] = true

		-- Минотавр поверх
		local minotaur = { face = "K", suit = "spades", is_hidden = false }
		table.insert(pile_2.cards, minotaur)
		local pos_2_mino_y = pile_2.pos.y - 2 * CONST.OVERLAP_OFFSET
		create_card_go(minotaur, vmath.vector3(pile_2.pos.x, pos_2_mino_y, 0.03), false)

		-- Подменяем dungeon_3: верхняя карта = 05_clubs
		local pile_3 = state.piles.dungeon_3
		if pile_3.cards[#pile_3.cards] and pile_3.cards[#pile_3.cards].go_id then
			go.delete(pile_3.cards[#pile_3.cards].go_id)
			pile_3.cards[#pile_3.cards].go_id = nil
		end
		local card_05_clubs = { face = "05", suit = "clubs", is_hidden = false }
		pile_3.cards[#pile_3.cards] = card_05_clubs
		local pos_3_y = pile_3.pos.y - (#pile_3.cards - 1) * CONST.OVERLAP_OFFSET
		local pos_3_z = 0.01 + (#pile_3.cards - 1) * 0.01
		create_card_go(card_05_clubs, vmath.vector3(pile_3.pos.x, pos_3_y, pos_3_z), false)

		-- Подменяем dungeon_4: верхняя карта = A_clubs
		local pile_4 = state.piles.dungeon_4
		if pile_4.cards[#pile_4.cards] and pile_4.cards[#pile_4.cards].go_id then
			go.delete(pile_4.cards[#pile_4.cards].go_id)
			pile_4.cards[#pile_4.cards].go_id = nil
		end
		local card_A_clubs = { face = "A", suit = "clubs", is_hidden = false }
		pile_4.cards[#pile_4.cards] = card_A_clubs
		local pos_4_y = pile_4.pos.y - (#pile_4.cards - 1) * CONST.OVERLAP_OFFSET
		local pos_4_z = 0.01 + (#pile_4.cards - 1) * 0.01
		create_card_go(card_A_clubs, vmath.vector3(pile_4.pos.x, pos_4_y, pos_4_z), false)

		state.party_levels["clubs"] = 0

		state.is_dealt = true
		state.piles.explore.can_use = true
	end
)

-- ---------------------------------------------------------------------------
-- #4: Duplicate Under Dragon (бывшая setup_debug_deal)
-- Проверка дубликата при использовании Treasure на party.
-- Состояние: inventory_1 = Treasure (J_hearts), dungeon_3 = Dragon (K_spades) на 2_hearts,
-- party_1 = A_hearts, Минотавр на позиции 3.
-- Игрок использует Treasure на A_hearts → создаётся дубликат → check_open_dungeon_duplicates.
-- ---------------------------------------------------------------------------
M.register_function(
	"Duplicate Under Dragon",
	"Проверка дубликата при использовании Treasure на party.\n"
	.. "  Состояние: inventory_1 = Treasure, dungeon_3 = Dragon на 2_hearts, party_1 = A_hearts.\n"
	.. "  Используйте Treasure на A_hearts → дубликат → check_open_dungeon_duplicates.",
	function(state)
		-- 1. Предметы: Treasure (J_hearts) в inventory_1
		local treasure = { face = "J", suit = "hearts", is_hidden = false }
		table.insert(state.piles.inventory_1.cards, treasure)
		local inv1_pos = state.piles.inventory_1.pos
		create_card_go(treasure, vmath.vector3(inv1_pos.x, inv1_pos.y, 0.01), false)

		-- 2. dungeon_3: закрытая 2_hearts + Dragon (K_spades) сверху
		local two_hearts = { face = "02", suit = "hearts", is_hidden = true }
		local dragon = { face = "K", suit = "spades", is_hidden = false }
		table.insert(state.piles.dungeon_3.cards, two_hearts)
		table.insert(state.piles.dungeon_3.cards, dragon)

		local dung3_pos = state.piles.dungeon_3.pos
		create_card_go(two_hearts, vmath.vector3(dung3_pos.x, dung3_pos.y, 0.01), true)
		create_card_go(dragon, vmath.vector3(dung3_pos.x, dung3_pos.y - CONST.OVERLAP_OFFSET, 0.02), false)

		state.minotaur_pos = 3
		state.minotaur_dir = 1

		-- 3. Отряд: A_hearts в party_1
		local ace_hearts = { face = "A", suit = "hearts", is_hidden = false }
		table.insert(state.piles.party_1.cards, ace_hearts)
		local party1_pos = state.piles.party_1.pos
		create_card_go(ace_hearts, vmath.vector3(party1_pos.x, party1_pos.y, 0.01), false)

		state.party_levels.hearts = 1
		state.party_power = 1

		state.is_dealt = true
		-- Блокируем explore — обычный deal не должен сработать при клике
		state.piles.explore.can_use = false
	end
)

return M
