-- game/modules/pile.lua

local M = {}

local CONST = require("game.modules.constants")

M.LAYOUT_STACK = "stack"     -- Карты стопкой друг на друге (колода, сброс, дома)
M.LAYOUT_CASCADE = "cascade" -- Карты каскадом (игровые стопки)
M.LAYOUT_STACK_OFFSET = "stack_offset"


function M.new(config)
	local pile = {
		id = config.id,
		pos = config.pos,
		cards = {},
		layout = config.layout or M.LAYOUT_STACK,
		-- Добавляем поле для хранения "масти" стопки (для Отряда)
		suit = config.suit
	}

	-- Создаем плейсхолдер, ТОЛЬКО если его спрайт был указан в конфиге
	if config.placeholder_sprite then
		pile.placeholder_go = factory.create(
		"#card_factory",
		config.pos,
		nil,
		{ card = hash(config.placeholder_sprite) },
		CONST.CARD_SCALE
	) 
end

return pile
end

return M