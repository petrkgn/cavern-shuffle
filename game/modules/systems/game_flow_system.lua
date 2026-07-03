-- /game/modules/systems/game_flow_system.lua
-- Ядро игрового потока: раздача, добор, проверка дубликатов

local CardUtils = require("game.modules.card_utils")
local RenderSystem = require("game.modules.systems.render_system")
local CONST = require("game.modules.constants")

local M = {}

-- === РАЗДАЧА И ДОБОР ===

-- Эта функция вызывается из input_system, когда мы кликаем по пустой колоде
function M.deal(state)
	if state.is_dealt then
		return
	end
	print("Cavern Shuffle: Dealing the dungeon...")
	local explore_pile = state.piles.explore

	-- ЭТАП 1: Подготовка данных (Карты раскладываются по виртуальным стопкам)
	-- >> ОБЫЧНАЯ ИГРА <<
	local minotaur_card = CardUtils.find_and_remove_card(explore_pile.cards, "K", "spades")
	local short_rest_card = CardUtils.find_and_remove_card(explore_pile.cards, "J", "clubs")
	CardUtils.shuffle(explore_pile.cards)

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

	-- ЭТАП 2: Анимация (Одинаковая для обоих режимов)
	-- Теперь, когда данные на местах, запускаем красивый разлет карт

	local total_cards_to_animate = 0
	for id, pile in pairs(state.piles) do
		if id ~= "explore" and id ~= "talon" and id ~= "discard" then
			total_cards_to_animate = total_cards_to_animate + #pile.cards
		end
	end

	local animation_delay = 0
	local animated_count = 0
	local piles_to_animate =
		{ "dungeon_1", "inventory_1", "dungeon_2", "dungeon_3", "dungeon_4", "dungeon_5", "dungeon_6", "dungeon_7" }

	for _, pile_id in ipairs(piles_to_animate) do
		local pile = state.piles[pile_id]
		if pile then
			for i, card in ipairs(pile.cards) do
				animated_count = animated_count + 1
				local on_complete = nil

				if animated_count == total_cards_to_animate then
					on_complete = function()
						print("DEAL FINISHED: Creating placeholders.")
						for i = 1, 7 do
							local p = state.piles["dungeon_" .. i]
							if not p.placeholder_go then
								p.placeholder_go = factory.create(
									"#card_factory",
									vmath.vector3(p.pos.x, p.pos.y, -0.1),
									nil,
									{ card = hash("card_empty") },
									CONST.CARD_SCALE
								)
							end
						end
					end
				end

				RenderSystem.move_card(card, pile, i, animation_delay, on_complete, go.EASING_OUTSINE, explore_pile)
				animation_delay = animation_delay + 0.02
			end
		end
	end

	state.is_dealt = true
	RenderSystem.update_explore_pile_sprite(explore_pile)
end

-- НОВАЯ ФУНКЦИЯ: Обработка клика по колоде добора
function M.handle_explore_click(state)
	local explore_pile = state.piles.explore
	local talon_pile = state.piles.talon
	local discard_pile = state.piles.discard

	-- Блокируем повторные клики во время анимации
	explore_pile.can_use = false

	-- 1. Сначала убираем старые карты из Талона в Сброс
	if #talon_pile.cards > 0 then
		for i, card in ipairs(talon_pile.cards) do
			card.is_hidden = true
			table.insert(discard_pile.cards, card)

			RenderSystem.move_card(card, discard_pile, #discard_pile.cards, (i - 1) * 0.05, function()
				if card.go_id then
					msg.post(card.go_id, "hide")
				end
			end, go.EASING_INOUTSINE, talon_pile)
		end
		talon_pile.cards = {}
	end

	-- Задержка перед добором новых карт
	timer.delay(0.3, false, function()
		if #explore_pile.cards > 0 then
			-- 2. ДОБОР ИЗ КОЛОДЫ (Explore -> Talon)
			local cards_to_add_to_talon = {}
			local num_to_draw = math.min(3, #explore_pile.cards)

			for i = 1, num_to_draw do
				local card = table.remove(explore_pile.cards)
				if card then
					card.is_hidden = false
					table.insert(cards_to_add_to_talon, card)
				end
			end

			-- Анимация добора
			for i, card in ipairs(cards_to_add_to_talon) do
				table.insert(talon_pile.cards, card)
				local easing_type = (i == #cards_to_add_to_talon) and go.EASING_OUTBACK or go.EASING_OUTSINE

				-- === ВАЖНЫЙ МОМЕНТ ===
				-- Мы вешаем проверку (check_talon) на завершение полета ПОСЛЕДНЕЙ карты
				local on_complete
				if i == #cards_to_add_to_talon then
					on_complete = function()
						print("ANIMATION COMPLETE: Triggering check_talon now...") -- << ОТЛАДКА
						-- Разблокируем стопку после завершения анимации
						explore_pile.can_use = true
						M.check_talon(state)
					end
				end
				-- =====================

				RenderSystem.move_card(
					card,
					talon_pile,
					#talon_pile.cards,
					(i - 1) * 0.05,
					on_complete,
					easing_type,
					explore_pile
				)
			end
		elseif #discard_pile.cards > 0 then
			-- 3. Если колода пуста, перевернуть сброс (Discard -> Explore)
			local total_cards = #discard_pile.cards
			for i = total_cards, 1, -1 do
				local card = table.remove(discard_pile.cards, i)
				card.is_hidden = true
				table.insert(explore_pile.cards, card)
				RenderSystem.move_card(
					card,
					explore_pile,
					#explore_pile.cards,
					(total_cards - i) * 0.02,
					nil,
					go.EASING_INOUTSINE,
					discard_pile
				)
			end
			-- Разблокируем стопку после завершения анимации переброса
			timer.delay(total_cards * 0.02 + 0.1, false, function()
				explore_pile.can_use = true
			end)
		end

		timer.delay(0.1, false, function()
			RenderSystem.update_explore_pile_sprite(explore_pile)
		end)
	end)
end

-- === ПРОВЕРКА ДУБЛИКАТОВ ===

function M.check_talon(state)
	-- Проверяем, есть ли что проверять
	if #state.piles.talon.cards == 0 then
		print("CHECK TALON: Talon is empty, nothing to check.")
		return
	end

	local talon_pile = state.piles.talon
	local top_card = talon_pile.cards[#talon_pile.cards]
	local card_key = top_card.face .. "_" .. top_card.suit

	print("CHECK TALON: Inspecting top card: " .. card_key)

	if state.created_cards[card_key] then
		-- ЭТО ДУБЛИКАТ!
		print("!!! DUPLICATE DETECTED in Talon:", card_key, "!!! Starting removal sequence.")

		-- 1. Удаляем его из данных
		table.remove(talon_pile.cards)
		table.insert(state.graveyard.cards, top_card)
		state.created_cards[card_key] = nil

		-- 2. Анимируем улет и в коллбэке снова вызываем проверку
		RenderSystem.animate_to_graveyard(top_card, function()
			print("DUPLICATE FLOWN AWAY. Redrawing talon and checking next card...")
			-- Когда карта улетела, перерисовываем talon, чтобы сдвинуть оставшиеся
			RenderSystem.redraw_talon_pile(talon_pile)

			-- И рекурсивно проверяем новую верхнюю карту (вдруг там серия дубликатов)
			M.check_talon(state)
		end)
	else
		print("CHECK TALON: Card is unique. All good.")
	end
end

function M.check_for_duplicate(state, card_to_check, source_pile)
	if not card_to_check then
		return false
	end

	local needs_reveal = card_to_check.is_hidden
	if needs_reveal then
		card_to_check.is_hidden = false
		if card_to_check.go_id then
			msg.post(card_to_check.go_id, "reveal")
		end
	end

	local card_key = card_to_check.face .. "_" .. card_to_check.suit
	if state.created_cards[card_key] then
		print("DUPLICATE FOUND:", card_key, ". Removing.")

		-- ИСПРАВЛЕНИЕ: Увеличиваем задержку.
		-- Анимация переворота (скорость 3.0, диапазон 2.0) занимает ~0.66 сек.
		-- Ставим 0.7, чтобы карта успела полностью лечь лицом вверх перед полетом.
		local delay = needs_reveal and 0.7 or 0.2

		timer.delay(delay, false, function()
			-- Проверяем, существует ли еще объект карты
			if not card_to_check.go_id or not go.exists(card_to_check.go_id) then
				return
			end

			-- Удаляем дубликат из списка созданных
			state.created_cards[card_key] = nil

			-- Добавляем в данные кладбища
			table.insert(state.graveyard.cards, card_to_check)

			-- Удаляем из исходной стопки (данные)
			for i, card in ipairs(source_pile.cards) do
				if card == card_to_check then
					table.remove(source_pile.cards, i)
					break
				end
			end

			-- Запускаем анимацию улета
			RenderSystem.animate_to_graveyard(card_to_check, function()
				-- Этот колбэк сработает, когда карта ПОЛНОСТЬЮ улетит за экран

				-- Перерисовываем стопку, чтобы "схлопнуть" пустое место
				RenderSystem.redraw_pile(source_pile)

				-- И теперь проверяем и открываем новую верхнюю карту, если она есть
				if #source_pile.cards > 0 then
					local new_top_card = source_pile.cards[#source_pile.cards]
					if new_top_card.is_hidden then
						new_top_card.is_hidden = false
						if new_top_card.go_id then
							msg.post(new_top_card.go_id, "reveal")
						end

						-- Рекурсивная проверка: вдруг под ней ТОЖЕ дубликат?
						-- Небольшая задержка, чтобы анимации не склеились
						timer.delay(0.1, false, function()
							M.check_for_duplicate(state, new_top_card, source_pile)
						end)
					end
				end
			end)
		end)

		return true -- Сообщаем, что это был дубликат
	end

	return false -- Это была обычная карта
end

-- Проверка открытых карт в подземелье на дубликаты (кроме столбца с Минотавром)
function M.check_open_dungeon_duplicates(state)
	local minotaur_column = state.minotaur_pos
	print("Checking open dungeon duplicates, excluding column " .. minotaur_column)

	for i = 1, 7 do
		if i == minotaur_column then
			-- Карты в этом столбце закрыты Минотавром, не проверяем
		else
			local pile = state.piles["dungeon_" .. i]
			if pile and #pile.cards > 0 then
				-- Проверяем только открытые карты (верхняя карта в столбце всегда открыта?)
				-- В подземелье карты скрыты, кроме верхней. Поэтому проверяем верхнюю карту.
				local top_card = pile.cards[#pile.cards]
				if top_card and not top_card.is_hidden then
					-- Проверяем дубликат
					M.check_for_duplicate(state, top_card, pile)
				end
			end
		end
	end
end

return M
