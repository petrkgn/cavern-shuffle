-- /game/modules/coords.lua
local M = {}

local scale = 1
local offset_x = 0
local offset_y = 0

-- Эта функция будет вызываться при каждом изменении размера окна
function M.recalculate(game_w, game_h, win_w, win_h)
	local scale_w = win_w / game_w
	local scale_h = win_h / game_h
	scale = math.min(scale_w, scale_h)
	offset_x = (win_w - (game_w * scale)) / 2
	offset_y = (win_h - (game_h * scale)) / 2
end

function M.screen_to_game(screen_x, screen_y)
	local game_x = (screen_x - offset_x) / scale
	local game_y = (screen_y - offset_y) / scale
	return game_x, game_y
end

return M