-- /game/modules/systems/encounter_system.lua
-- Боевые столкновения: разрешение кликов по врагам/препятствиям и level-up с перемещением Минотавра

local CardUtils = require("game.modules.card_utils")
local RenderSystem = require("game.modules.systems.render_system")
local GameConfig = require("game.modules.game_config")
local RulesSystem = require("game.modules.systems.rules_system")
local GameFlowSystem = require("game.modules.systems.game_flow_system")
local EndgameSystem = require("game.modules.systems.endgame_system")

local M = {}

-- Вызывается, когда искатель приключений повышает уровень
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
		print("GAME WON!")
		state.is_won = true
		msg.post(".", "release_input_focus")
		EndgameSystem.trigger_win_animation(state)

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
			GameFlowSystem.check_for_duplicate(state, card_under_minotaur, source_pile)
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

-- Попытка "решить" столкновение по клику
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
		-- 1. ЗАПУСКАЕМ ЭФФЕКТ
		msg.post(clicked_card_data.go_id, "play_hit_effect")

		-- 2. === НОВОЕ: СПАВН СЛЕША ===
		if clicked_card_data.go_id then
			local pos = go.get_position(clicked_card_data.go_id)
			-- Чуть поднимаем Z, чтобы эффект был поверх карты
			pos.z = pos.z + 0.1

			-- Спавним эффект
			factory.create("game:/game#slash_factory", pos, nil, {}, 2)
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

return M
