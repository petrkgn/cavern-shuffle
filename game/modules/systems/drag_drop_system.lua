-- /game/modules/systems/drag_drop_system.lua

local RenderSystem = require("game.modules.systems.render_system")
local RulesSystem = require("game.modules.systems.rules_system")
local GameFlowSystem = require("game.modules.systems.game_flow_system")
local CardUtils = require("game.modules.card_utils")
local GameConfig = require("game.modules.game_config")
local CONST = require("game.modules.constants")
local Geometry = require("game.modules.geometry")

local M = {}

-- Вспомогательная функция: Выбираем, ЧТО именно подсвечивать в стопке
local function get_highlight_target_go(pile)
	if not pile then return nil end
	if #pile.cards > 0 then
		return pile.cards[#pile.cards].go_id
	end
	return pile.placeholder_go
end

function M.start_drag(state, source_pile, card_index, action)
	if card_index == 0 then return end
	if string.find(source_pile.id, "party") then return end

	local card = source_pile.cards[card_index]
	local info = CardUtils.get_card_info(card)

	if not info.is_joker and not RulesSystem.is_drag_allowed(source_pile, card_index) then return end
	if source_pile.id == "talon" and card_index ~= #source_pile.cards then return end

	local cards_to_drag = {}
	for i = card_index, #source_pile.cards do
		table.insert(cards_to_drag, source_pile.cards[i])
	end

	state.dragging.cards = cards_to_drag
	state.dragging.source_pile_id = source_pile.id
	state.dragging.hovered_go_id = nil

	local clicked_card_pos = go.get_position(card.go_id)
	state.dragging.offset = vmath.vector3(clicked_card_pos.x - action.x, clicked_card_pos.y - action.y, 0)

	for i, c in ipairs(state.dragging.cards) do
		if c.go_id then
			msg.post(c.go_id, "start_drag")
			go.set_position(vmath.vector3(clicked_card_pos.x, clicked_card_pos.y, 0.9 + i * 0.01), c.go_id)
		end
	end
end

function M.update_drag(state, action)
	if #state.dragging.cards == 0 then return end

	for i, card in ipairs(state.dragging.cards) do
		if card.go_id then
			local new_pos = vmath.vector3(
				action.x + state.dragging.offset.x,
				action.y + state.dragging.offset.y - ((i-1) * CONST.OVERLAP_OFFSET),
				0.9 + i * 0.01
			)
			go.set_position(new_pos, card.go_id)
		end
	end

	local top_dragged_card = state.dragging.cards[1]
	local candidate_go_id = nil

	if top_dragged_card and top_dragged_card.go_id then
		local card_pos = go.get_position(top_dragged_card.go_id)
		local target_pile = Geometry.find_best_pile_overlap(card_pos, state.piles, state.dragging.source_pile_id)

		if target_pile then
			local can_drop = false
			local info = CardUtils.get_card_info(top_dragged_card)

			if info.is_joker then
				can_drop = string.find(target_pile.id, "inventory") and #target_pile.cards == 0
			elseif info.type == GameConfig.TYPE_ITEM and string.find(state.dragging.source_pile_id, "inventory") then
				can_drop = RulesSystem.is_valid_item_use(state, info, target_pile)
			elseif string.find(target_pile.id, "inventory") then
				can_drop = RulesSystem.is_valid_inventory_move(top_dragged_card, target_pile)
			elseif string.find(target_pile.id, "party") then
				can_drop = RulesSystem.is_valid_party_move(top_dragged_card, target_pile)
			elseif string.find(target_pile.id, "dungeon") then
				can_drop = RulesSystem.is_valid_dungeon_move(top_dragged_card, target_pile.cards[#target_pile.cards])
			end

			if can_drop then candidate_go_id = get_highlight_target_go(target_pile) end
		end
	end

	if candidate_go_id ~= state.dragging.hovered_go_id then
		if state.dragging.hovered_go_id and go.exists(state.dragging.hovered_go_id) then
			msg.post(state.dragging.hovered_go_id, "highlight_off")
		end
		if candidate_go_id then msg.post(candidate_go_id, "highlight_on") end
		state.dragging.hovered_go_id = candidate_go_id
	end
end

function M.end_drag(state, mouse_target)
	if #state.dragging.cards == 0 then return end

	if state.dragging.hovered_go_id and go.exists(state.dragging.hovered_go_id) then
		msg.post(state.dragging.hovered_go_id, "highlight_off")
	end
	state.dragging.hovered_go_id = nil

	local dragged_cards = state.dragging.cards
	local top_dragged_card = dragged_cards[1]
	for _, c in ipairs(dragged_cards) do if c.go_id then msg.post(c.go_id, "stop_drag") end end

	local card_pos = go.get_position(top_dragged_card.go_id)
	local target_pile = Geometry.find_best_pile_overlap(card_pos, state.piles, state.dragging.source_pile_id)
	local source_pile = state.piles[state.dragging.source_pile_id]
	local source_id = state.dragging.source_pile_id

	state.dragging.cards, state.dragging.source_pile_id = {}, nil
	local can_drop = false

	if target_pile then
		local info = CardUtils.get_card_info(top_dragged_card)

		if info.is_joker and string.find(target_pile.id, "inventory") and #target_pile.cards == 0 then
			for _ in ipairs(dragged_cards) do table.remove(source_pile.cards) end
			GameFlowSystem.restore_item_from_joker(state, top_dragged_card, target_pile)
			RenderSystem.redraw_pile(source_pile)
			return
		end

		if string.find(target_pile.id, "inventory") then
			can_drop = RulesSystem.is_valid_inventory_move(top_dragged_card, target_pile)
		elseif info.type == GameConfig.TYPE_ITEM and string.find(source_id, "inventory") then
			can_drop = RulesSystem.is_valid_item_use(state, info, target_pile)
		elseif string.find(target_pile.id, "party") then
			can_drop = RulesSystem.is_valid_party_move(top_dragged_card, target_pile)
		elseif string.find(target_pile.id, "dungeon") then
			can_drop = RulesSystem.is_valid_dungeon_move(top_dragged_card, target_pile.cards[#target_pile.cards])
		end
	end

	if can_drop and target_pile then
		local info = CardUtils.get_card_info(top_dragged_card)
		local is_item_use = info.type == GameConfig.TYPE_ITEM and string.find(source_id, "inventory")

		-- Удаляем из источника
		for _ in ipairs(dragged_cards) do table.remove(source_pile.cards) end

		if is_item_use then
			local original_go_id = top_dragged_card.go_id

			-- Вызываем логику применения предмета
			if not GameFlowSystem.use_item(state, top_dragged_card, target_pile, source_id) then
				table.insert(source_pile.cards, top_dragged_card)
				RenderSystem.animate_return(dragged_cards, source_pile)
			else
				-- ★★★ ВОССТАНОВЛЕНИЕ МАГИЧЕСКОГО ВИЗУАЛА ★★★
				if info.name == "Potion of Strength" then
					-- Зелье просто улетает
					table.insert(state.graveyard.cards, top_dragged_card)
					RenderSystem.animate_and_delete(top_dragged_card)
				elseif info.name == "Short Rest" then
					-- Короткий отдых уже управляет своим GO внутри GameFlow
				else
					-- Для Сокровища и Иллюзии: передаем GO новой карте
					local new_card = target_pile.cards[#target_pile.cards]
					if new_card and original_go_id then
						new_card.go_id = original_go_id
						-- Запускаем трансформацию
						local target_anim = hash("card_" .. new_card.suit .. "_" .. new_card.face)
						msg.post(new_card.go_id, "transform_from", { anim = target_anim })
					end
				end
			end
		else
			-- Обычное перемещение
			for _, c in ipairs(dragged_cards) do table.insert(target_pile.cards, c) end
			if string.find(target_pile.id, "party") then
				msg.post("game:/game#game_script", "adventurer_leveled_up", { card = top_dragged_card })
			end
		end

		RenderSystem.redraw_pile(source_pile)
		RenderSystem.redraw_pile(target_pile)

		if source_id == "talon" then GameFlowSystem.check_talon(state)
		elseif #source_pile.cards > 0 then
			GameFlowSystem.check_for_duplicate(state, source_pile.cards[#source_pile.cards], source_pile)
		end
	else
		msg.post("/game#game_script", "drag_failed", { card_data = top_dragged_card, source_pile_id = source_id })
		RenderSystem.animate_return(dragged_cards, source_pile)
	end

	state.dragging.offset = vmath.vector3()
end

return M