-- /game/modules/systems/game_flow_system.lua

local CardUtils = require("game.modules.card_utils")
local RenderSystem = require("game.modules.systems.render_system")
local GameConfig = require("game.modules.game_config")
local RulesSystem = require("game.modules.systems.rules_system")
local CONST = require("game.modules.constants")

local M = {}

-- Вспомогательная функция создания карт-заполнителей (Сокровище / Иллюзия)
local function create_placeholder_card(state, target_pile, is_dungeon_pile)
	local top_card_data = target_pile.cards[#target_pile.cards]
	if not top_card_data then
		return false
	end
	local top_card_info = CardUtils.get_card_info(top_card_data)

	local next_face
	if is_dungeon_pile then
		next_face = CardUtils.LESS_TABLE[top_card_info.face]
	else
		local next_value = (GameConfig.DEFAULT_FACE_VALUES[top_card_info.face] or 0) + 1
		next_face = (next_value < 10) and ("0" .. next_value) or tostring(next_value)
		if next_value == 11 then
			next_face = "J"
		end -- Исправление для перехода 10 -> J
	end

	if not next_face then
		return false
	end

	local next_suit = is_dungeon_pile and (RulesSystem.is_lawful(top_card_info.suit) and "spades" or "hearts")
		or top_card_info.suit

	local new_card_data = { face = next_face, suit = next_suit, is_hidden = false }
	local card_key = new_card_data.face .. "_" .. new_card_data.suit
	state.created_cards[card_key] = true

	table.insert(target_pile.cards, new_card_data)
	return true
end

-- === ОСНОВНЫЕ ИГРОВЫЕ МЕХАНИКИ ===

-- Маршрутизатор использования предметов
function M.use_item(state, item_card_data, target_pile, source_slot_id)
	local item_info = CardUtils.get_card_info(item_card_data)

	-- ★★★ ПРОВЕРКА ДЖОКЕРА (бывший Short Rest) ★★★
	if item_info.is_joker then
		-- Джокер используется как Short Rest
		M.execute_short_rest_chain(state, item_card_data, source_slot_id, target_pile)
		return true
	elseif item_info.name == "Short Rest" then
		-- Специальная цепочка: Полет -> Трансформация -> Перетасовка
		M.execute_short_rest_chain(state, item_card_data, source_slot_id, target_pile)
		return true
	elseif item_info.name == "Potion of Strength" then
		return M.use_potion_of_strength(state, target_pile)
	elseif item_info.name == "Treasure" then
		return M.use_treasure(state, target_pile, source_slot_id)
	elseif item_info.name == "Minor Illusion" then
		return create_placeholder_card(state, target_pile, true)
	end

	return false
end

-- Цепочка "Короткого отдыха" (Fly -> Flip -> Joker -> Shuffle)
function M.execute_short_rest_chain(state, item_card_data, source_slot_id, explore_pile)
	local go_id = item_card_data.go_id
	local target_slot = state.piles[source_slot_id]

	-- 1. Визуальный полет обратно в инвентарь
	RenderSystem.move_card(item_card_data, target_slot, 1, 0, function()
		-- 4. По прибытии: обновляем данные на Джокера
		item_card_data.face = "joker"
		item_card_data.suit = nil
		item_card_data.is_wildcard = true
		table.insert(target_slot.cards, item_card_data)

		RenderSystem.redraw_pile(target_slot)
		-- 6. Запускаем перетасовку через небольшую паузу
		timer.delay(0.5, false, function()
			M.use_short_rest(state)
		end)
	end, go.EASING_OUTSINE)

	-- 2. В середине полета запускаем эффект переворота (с эффектом частиц)
	timer.delay(0.15, false, function()
		if go.exists(go_id) then
			msg.post(go_id, "transform_from", { anim = hash("item_joker"), spawn_poof = true })
		end
	end)
end

-- Логика восстановления предмета из Джокера
function M.restore_item_from_joker(state, joker_card, target_pile)
	local joker_def = GameConfig.CARD_DEFINITIONS["joker"]
	local restored_key = joker_def.restores_to[target_pile.id]
	if not restored_key then
		return
	end

	local face, suit = restored_key:match("^(%w+)_(%w+)$")

	-- Визуал трансформации ПЕРЕД сменой данных
	local target_anim = hash("card_" .. suit .. "_" .. face)
	-- Эффект частиц вызывается в card.script при перевороте карты (spawn_poof = true)
	msg.post(joker_card.go_id, "transform_from", { anim = target_anim, spawn_poof = true })

	-- Обновляем данные
	joker_card.face = face
	joker_card.suit = suit
	joker_card.is_wildcard = false
	table.insert(target_pile.cards, joker_card)

	-- ★★★ ВАЖНО: Помечаем карту как созданную, чтобы проверка дубликатов работала ★★★
	-- Это особенно критично для сокровищ (Treasure), так как при их повторном использовании
	-- должна срабатывать логика удаления дубликатов из подземелья.
	state.created_cards[restored_key] = true

	RenderSystem.redraw_pile(target_pile)
end

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

-- ФУНКЦИЯ: Вызывается, когда искатель приключений повышает уровень
function M.on_adventurer_leveled_up(state, card_data)
	-- Проверяем, действительно ли уровень повысился
	local leveled_up_card = CardUtils.get_card_info(card_data)
	if leveled_up_card.value <= state.party_levels[leveled_up_card.suit] then
		return
	end

	-- Обновляем уровень и силу отряда
	state.party_levels[leveled_up_card.suit] = leveled_up_card.value
	local total_power = 0
	for _, level in pairs(state.party_levels) do
		total_power = total_power + level
	end
	state.party_power = total_power
	print("LEVEL UP! Party Power is now: " .. state.party_power)

	if not state.is_won and state.party_power >= 30 then
		-- Отправляем сообщение главному скрипту, что игра выиграна
		-- msg.post("game:/game#game_script", "game_won")
		print("GAME WON!")
		state.is_won = true
		msg.post(".", "release_input_focus")
		M.trigger_win_animation(state)

		timer.delay(3, false, function()
			msg.post("/end_game_ui", "enable")
			msg.post("/end_game_ui#gui", "acquire_input_focus")
		end)
		return
	end

	-- 2. Двигаем Минотавра
	local minotaur_card = nil
	local minotaur_card_index = -1
	local source_pile = state.piles["dungeon_" .. state.minotaur_pos]

	for i, card in ipairs(source_pile.cards) do
		if CardUtils.get_card_info(card).type == GameConfig.TYPE_BOSS then
			minotaur_card = card
			minotaur_card_index = i
			break
		end
	end

	if not minotaur_card then
		print("ERROR: Minotaur not found in column " .. state.minotaur_pos)
		return
	end

	table.remove(source_pile.cards, minotaur_card_index)

	-- === НОВОЕ: ПРОВЕРКА ОСВОБОДИВШЕЙСЯ КАРТЫ ===
	-- Минотавр ушел. Проверяем, не лежит ли под ним дубликат?
	-- Делаем небольшую задержку, чтобы Минотавр успел визуально "отлипнуть"
	timer.delay(0.2, false, function()
		if #source_pile.cards > 0 then
			local card_under_minotaur = source_pile.cards[#source_pile.cards]
			-- Запускаем стандартную проверку. Если это дубликат, она сама его удалит и анимирует.
			M.check_for_duplicate(state, card_under_minotaur, source_pile)
		end
	end)
	-- ============================================

	-- Рассчитываем новую позицию
	state.minotaur_pos = state.minotaur_pos + state.minotaur_dir
	if state.minotaur_pos > 7 then
		state.minotaur_pos = 6
		state.minotaur_dir = -1
	elseif state.minotaur_pos < 1 then
		state.minotaur_pos = 2
		state.minotaur_dir = 1
	end

	local destination_pile = state.piles["dungeon_" .. state.minotaur_pos]

	-- V-- КЛЮЧЕВОЕ ИСПРАВЛЕНИЕ ЗДЕСЬ --V
	-- Вставляем Минотавра в самый КОНЕЦ новой стопки, чтобы он был снизу
	table.insert(destination_pile.cards, minotaur_card)

	-- Анимация и перерисовка
	RenderSystem.redraw_pile(source_pile)

	local on_arrival = function()
		RenderSystem.redraw_pile(destination_pile)
	end

	-- Анимируем Минотавра в его новую позицию (последнюю в стопке)
	RenderSystem.move_card(minotaur_card, destination_pile, #destination_pile.cards, 0, on_arrival, go.EASING_OUTSINE)

	print("Minotaur moved to column " .. state.minotaur_pos)
end

-- НОВАЯ ФУНКЦИЯ: Попытка "решить" столкновение по клику
function M.try_resolve_encounter(state, clicked_card_data, source_pile)
	-- Прежде чем что-либо делать, проверяем, не заблокирована ли стопка Минотавром.
	if not RulesSystem.is_drag_allowed(source_pile) then
		print("ENCOUNTER BLOCKED: Cannot resolve encounter in a pile blocked by the Minotaur.")
		return -- Немедленно выходим
	end

	local card_info = CardUtils.get_card_info(clicked_card_data)
	local success = false

	if card_info.type == GameConfig.TYPE_ENEMY then
		-- Это Враг. Проверяем, можем ли мы его победить.
		if RulesSystem.can_defeat_enemy(state, card_info) then
			print("GAME FLOW: Enemy defeated!")
			success = true
		end
	elseif card_info.type == GameConfig.TYPE_OBSTACLE then
		-- Это Препятствие. Проверяем, можем ли мы его пройти.
		if RulesSystem.can_clear_obstacle(state, card_info) then
			print("GAME FLOW: Obstacle cleared!")
			state.obstacles_cleared = state.obstacles_cleared + 1
			success = true
		end
	end

	if success then
		-- Если столкновение пройдено, перемещаем карту в "кладбище"

		-- 	-- 1. Удаляем карту из данных исходной стопки
		-- 	for i, card in ipairs(source_pile.cards) do
		-- 		if card == clicked_card_data then
		-- 			table.remove(source_pile.cards, i)
		-- 			break
		-- 		end
		-- 	end
		--
		-- 	-- 2. Добавляем карту в данные "кладбища"
		-- 	table.insert(state.graveyard.cards, clicked_card_data)
		--
		-- 	-- 3. Анимируем ее "улет" с поля и последующее удаление GO
		-- 	local final_pos = vmath.vector3(500, -200, 0) -- Точка за экраном
		-- 	go.animate(clicked_card_data.go_id, "position", go.PLAYBACK_ONCE_FORWARD, final_pos, go.EASING_INSINE, 0.4, 0, function()
		-- 		go.delete(clicked_card_data.go_id)
		-- 		clicked_card_data.go_id = nil
		-- 	end)
		--
		-- 	-- 4. Перерисовываем стопку И открываем нижележащую карту, если нужно
		-- 	RenderSystem.redraw_pile(source_pile)
		-- 	if #source_pile.cards > 0 then
		-- 		local new_top_card = source_pile.cards[#source_pile.cards]
		-- 		if new_top_card.is_hidden then
		-- 			new_top_card.is_hidden = false
		-- 			msg.post(new_top_card.go_id, "reveal")
		-- 		end
		-- 	end
		--
		-- 	if state.temporary_power_buff.amount > 0 then
		-- 		print("Potion of Strength buff has been used.")
		-- 		state.temporary_power_buff = { suit = nil, amount = 0 }
		-- 	end
		-- 1. ЗАПУСКАЕМ ЭФФЕКТ
		msg.post(clicked_card_data.go_id, "play_hit_effect")

		-- 2. === НОВОЕ: СПАВН СЛЕША ===
		if clicked_card_data.go_id then
			local pos = go.get_position(clicked_card_data.go_id)
			-- Чуть поднимаем Z, чтобы эффект был поверх карты
			pos.z = pos.z + 0.1

			-- Спавним эффект
			-- (Предполагаем, что factory висит на том же GO, где скрипт игры,
			-- или укажите полный URL, например "/game#slash_factory")
			factory.create("game:/game#slash_factory", pos, nil, {}, 2) -- 1.5 - масштаб, если нужно побольше
		end

		-- 2. ЖДЕМ ЗАВЕРШЕНИЯ ЭФФЕКТА ПЕРЕД УЛЕТОМ (0.5 сек)
		timer.delay(1, false, function()
			-- Проверяем, что карта еще существует
			if not clicked_card_data.go_id then
				return
			end

			-- Удаляем из стопки
			for i, card in ipairs(source_pile.cards) do
				if card == clicked_card_data then
					table.remove(source_pile.cards, i)
					break
				end
			end

			-- Добавляем в кладбище
			table.insert(state.graveyard.cards, clicked_card_data)

			-- Анимация улета
			local final_pos = vmath.vector3(500, -200, 0)
			go.animate(
				clicked_card_data.go_id,
				"position",
				go.PLAYBACK_ONCE_FORWARD,
				final_pos,
				go.EASING_INSINE,
				0.4,
				0,
				function()
					go.delete(clicked_card_data.go_id)
					clicked_card_data.go_id = nil
				end
			)

			-- Обновляем стопку и открываем следующую карту
			RenderSystem.redraw_pile(source_pile)
			if #source_pile.cards > 0 then
				local new_top_card = source_pile.cards[#source_pile.cards]
				if new_top_card.is_hidden then
					new_top_card.is_hidden = false
					msg.post(new_top_card.go_id, "reveal")
				end
			end
		end)

		-- Сброс баффа силы, если был
		if state.temporary_power_buff.amount > 0 then
			state.temporary_power_buff = { suit = nil, amount = 0 }
		end
	end
end

function M.use_potion_of_strength(state, target_party_pile)
	if #target_party_pile.cards == 0 then
		return false
	end
	local suit = target_party_pile.cards[#target_party_pile.cards].suit
	print("Using Potion of Strength on suit: " .. suit)
	state.temporary_power_buff.suit = suit
	state.temporary_power_buff.amount = 5

	-- Обновляем UI прогрессбара с учётом баффа
	msg.post("game:/game#game_script", "potion_used")

	return true
end

-- Использование сокровища: создаёт карту-заполнитель и повышает уровень отряда
function M.use_treasure(state, target_party_pile, source_slot_id)
	if #target_party_pile.cards == 0 then
		return false
	end

	-- Создаём карту-заполнитель (новая карта с повышенным значением)
	local created = create_placeholder_card(state, target_party_pile, false)
	if not created then
		return false
	end

	-- Получаем созданную карту
	local new_card = target_party_pile.cards[#target_party_pile.cards]
	if not new_card then
		return false
	end

	-- Отправляем сообщение о повышении уровня — это запустит перемещение дракона
	msg.post("game:/game#game_script", "adventurer_leveled_up", { card = new_card })

	-- После создания карты-заполнителя проверяем открытые карты в подземелье на дубликаты
	-- (кроме столбца, где находится Минотавр, потому что там карты закрыты)
	M.check_open_dungeon_duplicates(state)

	return true
end

-- Эффект "Короткого отдыха": перемешивает колоду после трансформации в Джокер
function M.use_short_rest(state)
	print("Short Rest transformed into Joker. Starting shuffle sequence...")
	local explore_pile = state.piles.explore
	local talon_pile = state.piles.talon
	local discard_pile = state.piles.discard

	-- === ЭТАП 1: Talon -> Discard (если нужно) ===
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

	-- Запускаем основную перетасовку после небольшой задержки
	timer.delay(0.4, false, function()
		-- === ЭТАП 2: Discard -> Explore (Первый проход) ===
		local cards_to_shuffle = {}
		local total_cards = #discard_pile.cards

		for i = total_cards, 1, -1 do
			local card = table.remove(discard_pile.cards, i)
			table.insert(cards_to_shuffle, card)
			RenderSystem.move_card(
				card,
				explore_pile,
				#cards_to_shuffle,
				(total_cards - i) * 0.03,
				nil,
				go.EASING_INOUTSINE,
				discard_pile
			)
		end

		-- Ждем, пока закончится первая анимация перелета
		timer.delay(total_cards * 0.02 + 0.4, false, function()
			-- === ЭТАП 3: Explore -> Discard (Имитация тасовки) ===
			for i = total_cards, 1, -1 do
				local card = table.remove(cards_to_shuffle, i)
				table.insert(discard_pile.cards, card)
				RenderSystem.move_card(
					card,
					discard_pile,
					#discard_pile.cards,
					(total_cards - i) * 0.03,
					nil,
					go.EASING_INOUTSINE,
					explore_pile
				)
			end

			-- Ждем, пока закончится вторая анимация перелета
			timer.delay(total_cards * 0.02 + 0.4, false, function()
				-- === ЭТАП 4: Финальный Discard -> Explore + Перемешивание данных ===
				CardUtils.shuffle(discard_pile.cards)

				local final_total_cards = #discard_pile.cards
				for i = final_total_cards, 1, -1 do
					local card = table.remove(discard_pile.cards, i)
					card.is_hidden = true
					table.insert(explore_pile.cards, card)
					RenderSystem.move_card(
						card,
						explore_pile,
						#explore_pile.cards,
						(final_total_cards - i) * 0.03,
						nil,
						go.EASING_INOUTSINE,
						discard_pile
					)
				end

				timer.delay(0.3, false, function()
					RenderSystem.update_explore_pile_sprite(explore_pile)
				end)
			end)
		end)
	end)
	return true
end

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
			-- continue не существует в Lua, просто пропускаем
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

-- НОВАЯ ФУНКЦИЯ-ЗАГЛУШКА: Проверка победы
function M.check_win(state)
	-- Пока ничего не делаем, чтобы игра не падала.
	-- print("Checking for win condition...")
end

function M.restart_game(state)
	if state.is_restarting then
		return
	end
	state.is_restarting = true

	local all_cards = {}
	for id, pile in pairs(state.piles) do
		for _, card in ipairs(pile.cards) do
			if card.go_id then
				table.insert(all_cards, card)
			end
		end
	end

	local max_delay = #all_cards * 0.02
	for i, card in ipairs(all_cards) do
		local delay = i * 0.02
		-- Используем существующую функцию, просто передаем ей другую цель
		RenderSystem.animate_and_delete(card, state.piles.explore.pos, delay)
	end

	timer.delay(max_delay + 0.5, false, function()
		msg.post("game:/game#game_script", "restart_animation_complete")
	end)
end

function M.restart_game_animation_fallback(state)
	if state.is_restarting then
		return
	end
	state.is_restarting = true -- Блокируем ввод

	local all_cards_on_field = {}
	local explore_pos = state.piles.explore.pos

	-- 1. Собираем в один массив ВСЕ карты, у которых есть игровой объект
	for id, pile in pairs(state.piles) do
		for _, card in ipairs(pile.cards) do
			if card.go_id then
				table.insert(all_cards_on_field, card)
			end
		end
	end

	-- 2. Запускаем анимацию "улета" для каждой карты
	local max_delay = 0
	for i, card in ipairs(all_cards_on_field) do
		local delay = (i - 1) * 0.02
		max_delay = math.max(max_delay, delay)

		-- Используем нашу новую универсальную функцию, чтобы анимировать полет в колоду
		RenderSystem.animate_and_delete(card, explore_pos, delay)
	end

	-- 3. После того, как ПОСЛЕДНЯЯ карта закончит анимацию,
	--    отправляем сообщение, что можно сбрасывать данные.
	timer.delay(max_delay + 0.5, false, function()
		msg.post("game:/game#game_script", "restart_animation_finished")
	end)
end

function M.trigger_win_animation(state)
	print("WIN: Moving cards data to vortex...")

	local cards_for_vortex = {}
	local minotaur_data = nil

	-- 1. Собираем карты, отделяя Минотавра
	for id, pile in pairs(state.piles) do
		for _, card in ipairs(pile.cards) do
			if card then
				if CardUtils.get_card_info(card).type == GameConfig.TYPE_BOSS then
					minotaur_data = card
				else
					table.insert(cards_for_vortex, card)
				end
			end
		end
	end

	-- 2. Удаляем старые GO и очищаем стопки
	for id, pile in pairs(state.piles) do
		for _, card in ipairs(pile.cards) do
			if card.go_id then
				go.delete(card.go_id)
				card.go_id = nil
			end
		end
		pile.cards = {}
	end
	msg.post(state.piles.explore.placeholder_go, "set_sprite", { id = "card_empty" })

	-- 3. Перемещаем ДАННЫЕ в state
	state.vortex_cards = cards_for_vortex
	state.win_minotaur_card = minotaur_data -- Используем старое поле, оно нам подходит
end

-- ЗАМЕНИТЕ СТАРУЮ restart_from_win_animation НА ЭТУ
function M.restart_from_win_animation(state)
	if not state.is_won then
		return
	end
	state.is_restarting = true

	-- 1. Собираем все карты, участвующие в анимации, в ОДИН массив
	local all_cards_to_animate = {}

	-- Сначала добавляем карты из хоровода
	for _, card_data in ipairs(state.vortex_cards) do
		table.insert(all_cards_to_animate, card_data)
	end

	-- V-- ИСПРАВЛЕНИЕ: ДОБАВЛЯЕМ МИНОТАВРА В СПИСОК --V
	if state.win_minotaur_card then
		table.insert(all_cards_to_animate, state.win_minotaur_card)
	end
	-- ^-- КОНЕЦ ИСПРАВЛЕНИЯ --^

	local explore_pos = state.piles.explore.pos
	local max_delay = 0

	for i, card in ipairs(all_cards_to_animate) do
		if card.go_id and go.exists(card.go_id) then
			-- Отключаем вращение в update(), если оно было
			card.is_in_vortex = false
			go.cancel_animations(card.go_id)

			local delay = (i - 1) * 0.02
			max_delay = math.max(max_delay, delay)

			RenderSystem.animate_and_delete(card, explore_pos, delay)
		end
	end

	-- После завершения всех анимаций отправляем сообщение
	timer.delay(max_delay + 0.5, false, function()
		msg.post("game:/game#game_script", "restart_animation_finished")
	end)
end

function M.check_for_game_over(state)
	local can_move, hint_message = RulesSystem.is_any_move_possible(state)

	if not can_move then
		msg.post("game:/game#game_script", "game_lost")
	else
		-- Отправляем сообщение в GUI, чтобы он показал подсказку
		msg.post("game:/game_ui#game_ui", "show_hint", { text = hint_message })
	end
end

return M
