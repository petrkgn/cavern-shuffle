-- /game/modules/systems/item_system.lua
-- Предметы: использование, трансформация, эффекты

local CardUtils = require("game.modules.card_utils")
local RenderSystem = require("game.modules.systems.render_system")
local GameConfig = require("game.modules.game_config")
local RulesSystem = require("game.modules.systems.rules_system")
local GameFlowSystem = require("game.modules.systems.game_flow_system")

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
	GameFlowSystem.check_open_dungeon_duplicates(state)

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

return M
