-- /game/modules/systems/rules_system.lua

local CardUtils = require("game.modules.card_utils")
local GameConfig = require("game.modules.game_config") -- Подключаем конфиг
local M = {}

local LESS_TABLE = {
	["K"] = "Q",
	["Q"] = "J",
	["J"] = "10",
	["10"] = "09",
	["09"] = "08",
	["08"] = "07",
	["07"] = "06",
	["06"] = "05",
	["05"] = "04",
	["04"] = "03",
	["03"] = "02",
	["02"] = "A",
}

function M.is_lawful(suit)
	return suit == "hearts" or suit == "diamonds"
end
function M.is_chaotic(suit)
	return suit == "spades" or suit == "clubs"
end

-- ПРОВЕРКА ДЛЯ СТОПОК ПОДЗЕМЕЛЬЯ
function M.is_valid_dungeon_move(dragged_card_data, target_pile_card_data)
	local dragged_card = CardUtils.get_card_info(dragged_card_data)

	-- Предметы (кроме Иллюзии, которая обрабатывается в is_valid_item_use) не могут быть положены в подземелье.
	if dragged_card.type == GameConfig.TYPE_ITEM then
		return false
	end

	if dragged_card.type ~= GameConfig.TYPE_ADVENTURER then
		return false
	end

	if not target_pile_card_data then
		return dragged_card.value == 10
	end

	local target_card = CardUtils.get_card_info(target_pile_card_data)

	if target_card.type ~= GameConfig.TYPE_ADVENTURER and target_card.type ~= GameConfig.TYPE_BOSS then
		return false
	end
	if target_card.type == GameConfig.TYPE_BOSS then
		return dragged_card.value == 10
	end

	local alignments_alternate = (M.is_lawful(dragged_card.suit) and M.is_chaotic(target_card.suit))
		or (M.is_chaotic(dragged_card.suit) and M.is_lawful(target_card.suit))
	if not alignments_alternate then
		return false
	end

	return LESS_TABLE[target_card.face] == dragged_card.face
end

function M.is_valid_party_move(dragged_card_data, target_pile)
	local dragged_card = CardUtils.get_card_info(dragged_card_data)

	if dragged_card.type == GameConfig.TYPE_ADVENTURER then
		if #target_pile.cards == 0 then
			return dragged_card.value == 1
		else
			local target_card = CardUtils.get_card_info(target_pile.cards[#target_pile.cards])
			if target_card.name == "Treasure" then
				local placeholder_value = CardUtils.get_card_info(target_pile.cards[#target_pile.cards - 1]).value + 1
				return dragged_card.value == placeholder_value or dragged_card.value == placeholder_value + 1
			else
				if dragged_card.suit ~= target_card.suit then
					return false
				end
				return dragged_card.value == target_card.value + 1
			end
		end
	end

	return false -- По умолчанию другие типы карт класть в отряд нельзя (они ИСПОЛЬЗУЮТСЯ на нем)
end

function M.is_valid_inventory_move(dragged_card_data, target_pile)
	local dragged_card = CardUtils.get_card_info(dragged_card_data)

	-- ★★★ РАЗРЕШАЕМ ДЖОКЕРУ ПЕРЕМЕЩАТЬСЯ НА ПУСТЫЕ СЛОТЫ ИНВЕНТАРЯ ★★★
	if dragged_card.is_joker and #target_pile.cards == 0 then
		return true
	end

	-- Обычные предметы: только если это предмет И слот пустой
	if dragged_card.type ~= GameConfig.TYPE_ITEM then
		return false
	end
	if #target_pile.cards > 0 then
		return false
	end
	return true
end

function M.is_drag_allowed(pile, card_index)
	if not string.find(pile.id, "dungeon") then
		return true
	end
	for i, card_data in ipairs(pile.cards) do
		if CardUtils.get_card_info(card_data).type == GameConfig.TYPE_BOSS then
			return false
		end
	end
	return true
end

-- V-- НОВЫЕ ФУНКЦИИ ПРАВИЛ ДЛЯ СТОЛКНОВЕНИЙ --V

-- Проверяет, можно ли пройти Препятствие
function M.can_clear_obstacle(state, obstacle_card_info)
	-- Сложность зависит от количества уже пройденных препятствий
	local difficulty
	if state.obstacles_cleared == 0 then
		difficulty = 1
	elseif state.obstacles_cleared == 1 then
		difficulty = 3
	elseif state.obstacles_cleared == 2 then
		difficulty = 5
	elseif state.obstacles_cleared == 3 then
		difficulty = 7
	else
		return false -- Все препятствия уже пройдены
	end

	-- Получаем текущий уровень нужного Искателя приключений
	local adventurer_level = state.party_levels[obstacle_card_info.target_suit]

	if state.temporary_power_buff.suit == obstacle_card_info.target_suit then
		adventurer_level = adventurer_level + state.temporary_power_buff.amount
	end

	print(
		string.format(
			"RULE CHECK: Obstacle '%s'. Difficulty: %d, Adventurer Level (w/buff): %d",
			obstacle_card_info.name,
			difficulty,
			adventurer_level
		)
	)

	return adventurer_level >= difficulty
end

-- Проверяет, можно ли победить Врага
function M.can_defeat_enemy(state, enemy_card_info)
	local party_power = state.party_power

	-- Проверяем, активно ли Зелье Силы. Если да, оно дает бонус к ОБЩЕЙ силе отряда.
	-- Правила говорят: "добавьте пять (5) уровней Искателю приключений", но эффект
	-- применяется для прохождения Врага, который требует УРОВЕНЬ ОТРЯДА.
	-- Логичнее всего, что бафф применяется к общей силе.
	if state.temporary_power_buff.amount > 0 then
		party_power = party_power + state.temporary_power_buff.amount
	end

	print(
		string.format(
			"RULE CHECK: Enemy '%s'. Required Power: %d, Party Power (w/buff): %d",
			enemy_card_info.name,
			enemy_card_info.power,
			party_power
		)
	)

	return party_power >= enemy_card_info.power
end

-- Проверяет, можно ли использовать Предмет на цели
function M.is_valid_item_use(state, item_card_info, target_pile)
	-- ★★★ ПРОВЕРКА ДЖОКЕРА (бывший Short Rest) ★★★
	if item_card_info.is_joker then
		-- Джокер можно использовать только на пустую explore стопку (как Short Rest)
		return target_pile.id == "explore" and #state.piles.explore.cards == 0
	elseif item_card_info.name == "Short Rest" then
		-- Теперь 'state' доступен, и ошибки не будет
		return target_pile.id == "explore" and #state.piles.explore.cards == 0
	elseif item_card_info.name == "Potion of Strength" then
		return string.find(target_pile.id, "party") ~= nil and #target_pile.cards > 0
	elseif item_card_info.name == "Treasure" then
		return string.find(target_pile.id, "party") ~= nil
			and #target_pile.cards > 0
			and CardUtils.get_card_info(target_pile.cards[#target_pile.cards]).value < 10
	elseif item_card_info.name == "Minor Illusion" then
		if string.find(target_pile.id, "dungeon") and #target_pile.cards > 0 then
			local top_card = CardUtils.get_card_info(target_pile.cards[#target_pile.cards])
			return top_card.type == GameConfig.TYPE_ADVENTURER and top_card.value > 1
		end
	end
	return false
end

-- НОВАЯ ФУНКЦИЯ: Проверяет, есть ли хоть один возможный ход
function M.is_any_move_possible(state)
	local possible_moves = {}

	-- === Проверка 1: Колода ===
	if #state.piles.explore.cards > 0 then
		table.insert(possible_moves, "Можно взять новые карты из колоды.")
	elseif #state.piles.discard.cards > 0 then
		table.insert(possible_moves, "Можно перевернуть стопку сброса.")
	end

	-- === Проверка 2: Карты на столе ===
	local playable_sources = {}
	-- Talon
	if #state.piles.talon.cards > 0 then
		table.insert(playable_sources, {
			pile = state.piles.talon,
			card_indexes = { #state.piles.talon.cards }, -- Только верхняя
		})
	end
	-- Dungeon
	for i = 1, 7 do
		local pile = state.piles["dungeon_" .. i]
		if #pile.cards > 0 and M.is_drag_allowed(pile) then
			local open_card_indexes = {}
			for j = #pile.cards, 1, -1 do
				if not pile.cards[j].is_hidden then
					table.insert(open_card_indexes, j)
				else
					break
				end
			end
			if #open_card_indexes > 0 then
				table.insert(playable_sources, { pile = pile, card_indexes = open_card_indexes })
			end
		end
	end

	-- Теперь проверяем все возможные ходы
	for _, source in ipairs(playable_sources) do
		for _, card_index in ipairs(source.card_indexes) do
			local card_to_move = source.pile.cards[card_index]
			local card_info = CardUtils.get_card_info(card_to_move)
			local source_name = string.gsub(source.pile.id, "_", " ") -- "dungeon_1" -> "dungeon 1"

			if card_info.type == GameConfig.TYPE_ADVENTURER then
				-- В Dungeon
				for i = 1, 7 do
					local dest_pile = state.piles["dungeon_" .. i]
					if dest_pile ~= source.pile and M.is_drag_allowed(dest_pile) then
						if M.is_valid_dungeon_move(card_to_move, dest_pile.cards[#dest_pile.cards]) then
							local hint = string.format(
								"Можно переместить %s %s из '%s' в столбец %d.",
								card_info.suit,
								card_info.face,
								source_name,
								i
							)
							table.insert(possible_moves, hint)
						end
					end
				end
				-- В Party
				for i = 1, 4 do
					local dest_pile = state.piles["party_" .. i]
					if M.is_valid_party_move(card_to_move, dest_pile) then
						local hint = string.format(
							"Можно повысить уровень героя %s картой %s.",
							card_info.suit,
							card_info.face
						)
						table.insert(possible_moves, hint)
					end
				end
			elseif card_info.type == GameConfig.TYPE_ENEMY then
				if M.can_defeat_enemy(state, card_info) then
					table.insert(possible_moves, "Можно победить врага: " .. card_info.name .. "!")
				end
			elseif card_info.type == GameConfig.TYPE_OBSTACLE then
				if M.can_clear_obstacle(state, card_info) then
					table.insert(
						possible_moves,
						"Можно пройти препятствие: " .. card_info.name .. "!"
					)
				end
			elseif card_info.type == GameConfig.TYPE_ITEM then
				-- Проверяем все слоты инвентаря
				for i = 1, 4 do
					local dest_pile = state.piles["inventory_" .. i]
					if M.is_valid_inventory_move(card_to_move, dest_pile) then
						local hint = string.format(
							"Можно поместить предмет '%s' в инвентарь.",
							card_info.name
						)
						table.insert(possible_moves, hint)
						break -- Нашли один пустой слот, этого достаточно
					end
				end
			end
		end
	end

	-- === Финальное решение ===
	if #possible_moves > 0 then
		local random_hint = possible_moves[math.random(#possible_moves)]
		print("HINT:", random_hint)
		return true, random_hint
	else
		print("HINT: No moves possible.")
		return false, "Ходов больше нет. Вы проиграли."
	end
end

return M
