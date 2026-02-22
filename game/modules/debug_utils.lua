-- game/modules/debug_utils.lua

local CardUtils = require("game.modules.card_utils")

local M = {}

-- 1. Тест улета дубликатов из Талона
function M.deal_debug_talon_duplicate(state)
	if state.is_dealt then return end
	print("!!! DEBUG SETUP: RIGGING DECK FOR DUPLICATE CHECK !!!")

	local explore_pile = state.piles.explore

	CardUtils.shuffle(explore_pile.cards)

	local minotaur_card = CardUtils.find_and_remove_card(explore_pile.cards, "K", "spades")
	local short_rest_card = CardUtils.find_and_remove_card(explore_pile.cards, "J", "clubs")

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

	local cards_count = #explore_pile.cards
	local traps_count = math.min(3, cards_count)

	if traps_count > 0 then
		print("DEBUG: Setting traps on the next " .. traps_count .. " cards to be drawn...")
		for i = 0, traps_count - 1 do
			local card_trap = explore_pile.cards[cards_count - i]
			local key = card_trap.face .. "_" .. card_trap.suit
			state.created_cards[key] = true
			print("DEBUG: TRAP SET on [" .. key .. "] (Position from end: " .. i .. ")")
		end
		print("DEBUG: Click the deck to see them fly away one by one!")
	end
end

-- 2. Тест переворота карты в стопке (Reveal)
function M.deal_debug_dungeon_reveal(state)
	if state.is_dealt then return end
	print("!!! DEBUG SETUP: RIGGING DUNGEON (NUMBERED CARDS) !!!")

	local explore_pile = state.piles.explore
	CardUtils.shuffle(explore_pile.cards)
	CardUtils.find_and_remove_card(explore_pile.cards, "K", "spades") 

	for i = 1, 7 do
		local pile = state.piles["dungeon_" .. i]
		for c = 1, i do
			if #explore_pile.cards > 0 then
				local card = table.remove(explore_pile.cards)
				card.is_hidden = (c ~= i)
				table.insert(pile.cards, card)
			end
		end
	end

	local pile_2 = state.piles.dungeon_2
	pile_2.cards[#pile_2.cards] = { face = "05", suit = "hearts", is_hidden = false }

	local pile_3 = state.piles.dungeon_3
	pile_3.cards[#pile_3.cards] = { face = "04", suit = "clubs", is_hidden = false }

	local trap_index = #pile_3.cards - 1
	if trap_index > 0 then
		local trap_card = { face = "09", suit = "diamonds", is_hidden = true }
		pile_3.cards[trap_index] = trap_card

		local key = trap_card.face .. "_" .. trap_card.suit
		state.created_cards[key] = true

		print("DEBUG: Setup Complete.")
		print("ACTION: Drag [04 clubs] (Col 3) onto [05 hearts] (Col 2).")
		print("RESULT: [09 diamonds] will be revealed in Col 3 and should fly away.")
	end
end

-- 3. Тест разблокировки Минотавра (Unlock)
function M.deal_debug_minotaur_unlock(state)
	if state.is_dealt then return end
	print("!!! DEBUG SETUP: MINOTAUR UNLOCK DUPLICATE CHECK !!!")

	local explore_pile = state.piles.explore
	CardUtils.shuffle(explore_pile.cards)

	CardUtils.find_and_remove_card(explore_pile.cards, "K", "spades") 
	CardUtils.find_and_remove_card(explore_pile.cards, "J", "clubs")

	for i = 1, 7 do
		local pile = state.piles["dungeon_" .. i]
		for c = 1, i do
			if #explore_pile.cards > 0 then
				local card = table.remove(explore_pile.cards)
				card.is_hidden = (c ~= i)
				table.insert(pile.cards, card)
			end
		end
	end

	-- Настройка сцены
	state.minotaur_pos = 2 

	local pile_2 = state.piles.dungeon_2
	pile_2.cards[#pile_2.cards] = { face = "09", suit = "diamonds", is_hidden = false }
	table.insert(pile_2.cards, { face = "K", suit = "spades", is_hidden = false })

	state.created_cards["09_diamonds"] = true

	state.party_levels["clubs"] = 0 

	local pile_3 = state.piles.dungeon_3
	pile_3.cards[#pile_3.cards] = { face = "05", suit = "clubs", is_hidden = false }

	local pile_4 = state.piles.dungeon_4
	pile_4.cards[#pile_4.cards] = { face = "A", suit = "clubs", is_hidden = false }

	print("DEBUG: Setup Complete.")
	print("ACTION: Drag [04 clubs] from Col 4 to [05 clubs] in Col 3.")
	print("RESULT: Clubs Level Up -> Minotaur leaves Col 2 -> [09 diamonds] in Col 2 flies away.")
end

return M