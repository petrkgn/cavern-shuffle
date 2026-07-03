-- /game/modules/systems/endgame_system.lua
-- Завершение игры: победа, поражение, перезапуск

local CardUtils = require("game.modules.card_utils")
local RenderSystem = require("game.modules.systems.render_system")
local GameConfig = require("game.modules.game_config")
local RulesSystem = require("game.modules.systems.rules_system")

local M = {}

-- Заглушка: Проверка победы
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
	-- 3.5. Сбрасываем состояние атак в хороводе
	state.vortex_attack_in_progress = false
	state.vortex_slash_go = nil
	state.vortex_cards = cards_for_vortex
	state.win_minotaur_card = minotaur_data -- Используем старое поле, оно нам подходит
end

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
