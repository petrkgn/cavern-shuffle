-- /game/modules/systems/input_system.lua

local GameFlowSystem = require("game.modules.systems.game_flow_system")
local DragDropSystem = require("game.modules.systems.drag_drop_system")

local Coords = require("game.modules.coords")
local CONST = require("game.modules.constants")

local M = {}

-- Вспомогательная функция для определения цели клика
local function find_target_at(state, x, y)
	for id, pile in pairs(state.piles) do
		local card_w_half = CONST.CARD_WIDTH / 2
		local card_h_half = CONST.CARD_HEIGHT / 2

		-- Проверяем, попадает ли клик в область карты по ширине
		local pile_x = pile.pos.x
		if pile.layout == "stack_offset" and #pile.cards > 0 then
			-- Для Talon'а учитываем сдвиг последних карт
			local visual_index = math.min(3, #pile.cards)
			pile_x = pile.pos.x + (15 * (visual_index - 1))
		end

		if x > pile_x - card_w_half and x < pile_x + card_w_half then
			-- Если стопка пуста, ее область клика - это простой прямоугольник
			if #pile.cards == 0 then
				if y > pile.pos.y - card_h_half and y < pile.pos.y + card_h_half then
					return {pile = pile, card_index = 0}
				end
			else
				-- Проверяем разные типы стопок
				if pile.layout == "cascade" then
					for i = #pile.cards, 1, -1 do
						local card_pos_y = pile.pos.y - (i - 1) * CONST.OVERLAP_OFFSET
						local is_last_card = (i == #pile.cards)
						local top_boundary = card_pos_y + card_h_half
						local bottom_boundary =
						is_last_card and (card_pos_y - card_h_half) or
						(card_pos_y + card_h_half - CONST.OVERLAP_OFFSET)

						if y < top_boundary and y > bottom_boundary then
							return {pile = pile, card_index = i}
						end
					end
				elseif pile.layout == "stack_offset" then -- Talon
					local top_card_index = #pile.cards
					if y > pile.pos.y - card_h_half and y < pile.pos.y + card_h_half then
						return {pile = pile, card_index = top_card_index}
					end
				elseif pile.layout == "stack" then -- Explore, Party, Inventory, Discard
					if y > pile.pos.y - card_h_half and y < pile.pos.y + card_h_half then
						return {pile = pile, card_index = #pile.cards}
					end
				end
			end
		end
	end

	return nil -- Ничего не найдено
end


function M.on_input(state, action_id, action)
	if state.is_won or state.is_restarting then
		return
	end

	-- --- БЛОК КОНВЕРТАЦИИ КООРДИНАТ ---
	local corrected_action = action
	if action.x and action.y then
		local game_x, game_y = Coords.screen_to_game(action.screen_x, action.screen_y)

		state.mouse_x = game_x
		state.mouse_y = game_y

		corrected_action = {
			x = game_x,
			y = game_y,
			pressed = action.pressed,
			released = action.released,
			repeated = action.repeated,
			dx = action.dx,
			dy = action.dy,
			screen_x = action.screen_x,
			screen_y = action.screen_y
		}
	end

	-- --- ОСНОВНАЯ ЛОГИКА (использует corrected_action) ---

	state.click = state.click or {is_down = false, target = nil, has_moved = false}

	if action_id == hash("touch") then
		if corrected_action.pressed then
			state.click.is_down = true
			state.click.has_moved = false
			state.click.target = find_target_at(state, corrected_action.x, corrected_action.y)
		elseif corrected_action.released then
			if state.click.is_down then
				if state.dragging and #state.dragging.cards > 0 then
					local drop_target = find_target_at(state, corrected_action.x, corrected_action.y)
					DragDropSystem.end_drag(state, drop_target)
				elseif state.click.target and not state.click.has_moved then
					print("InputSystem: Pure click detected on pile:", state.click.target.pile.id)

					msg.post("/game#game_script", "pure_click", { 
						pile_id = state.click.target.pile.id, 
						card_index = state.click.target.card_index 
					})

					-- V-- НОВАЯ ЛОГИКА ДЛЯ КЛИКОВ ПО КАРТАМ --V
					local target_pile = state.click.target.pile

					if target_pile.id == "explore" then
						if not state.is_dealt then
							print("InputSystem: Dealing cards for the first time...")
							GameFlowSystem.deal(state)
						else
							print("InputSystem: Explore pile clicked...")
							GameFlowSystem.handle_explore_click(state)
						end
					else
						if state.click.target.card_index > 0 then
							-- Клик был по конкретной карте, а не по пустой стопке
							local clicked_card = target_pile.cards[state.click.target.card_index]
							GameFlowSystem.try_resolve_encounter(state, clicked_card, target_pile)
						else
							print("Clicked on an empty pile:", target_pile.id)
						end
					end
				end
			end
			state.click = {is_down = false, target = nil, has_moved = false}
		elseif state.click.is_down and not state.click.has_moved then
			if (math.abs(corrected_action.dx) > 5 or math.abs(corrected_action.dy) > 5) and #state.dragging.cards == 0 then
				state.click.has_moved = true
				if state.click.target and state.click.target.card_index > 0 then
					DragDropSystem.start_drag(
					state,
					state.click.target.pile,
					state.click.target.card_index,
					corrected_action
				)
			end
		end
	end
end

if state.dragging and #state.dragging.cards > 0 then
	DragDropSystem.update_drag(state, corrected_action)
end

if corrected_action.released and (not state.dragging or #state.dragging.cards == 0) then
	GameFlowSystem.check_win(state)
end
end

return M
