-- /game/modules/systems/tutorial_system.lua

local Config = require("game.modules.tutorial_config")
local CardUtils = require("game.modules.card_utils")
local RulesSystem = require("game.modules.systems.rules_system")
local M = {}

-- Внутренняя функция, которая выбирает случайную фразу и готовит таблицу для сообщения
local function prepare_balloon_message(target_go, text_config)
	if not target_go or not text_config or #text_config == 0 then
		return nil
	end

	local phrase = text_config[math.random(#text_config)]
	local target_position = go.get_position(target_go)

	return {
		pos = target_position,
		art_text = phrase.art,
		help_text = phrase.help,
	}
end

-- Функция для обработки "чистого клика"
function M.get_click_hint(state, target)
	if not target or not target.pile then
		return nil
	end

	if target.card_index > 0 then
		-- Клик по КАРТЕ
		local card = target.pile.cards[target.card_index]
		if not card then
			return nil
		end -- Защита на всякий случай

		local info = CardUtils.get_card_info(card)

		local text_table
		if info.type == "adventurer" then
			local alignment = RulesSystem.is_lawful(info.suit) and "lawful" or "chaotic"
			text_table = Config.ON_CLICK.adventurer[alignment]
		elseif Config.ON_CLICK[info.type] then
			text_table = Config.ON_CLICK[info.type]
			if info.name and text_table[info.name] then
				text_table = text_table[info.name]
			end
		end

		return prepare_balloon_message(card.go_id, text_table)
	else
		-- Клик по ПУСТОМУ МЕСТУ (ПЛЕЙСХОЛДЕРУ)
		local pile = target.pile
		local text_table
		if string.find(pile.id, "party") and pile.suit then
			text_table = Config.ON_CLICK.party_placeholder[pile.suit]
		elseif string.find(pile.id, "inventory") then
			text_table = Config.ON_CLICK.inventory_placeholder
		end

		return prepare_balloon_message(pile.placeholder_go, text_table)
	end
end

-- Функция для обработки неудачного перетаскивания
function M.get_drag_fail_hint(card_data, source_pile)
	local text_table
	if string.find(source_pile.id, "party") then
		text_table = Config.ON_DROP_FAIL.adventurer_from_party
	else
		text_table = Config.ON_DROP_FAIL.default
	end

	return prepare_balloon_message(card_data.go_id, text_table)
end

return M
