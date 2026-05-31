-- /game/modules/geometry.lua

local CONST = require("game.modules.constants")

local M = {}

-- Получить границы прямоугольника
function M.get_bounds(pos, width, height)
	local half_w = width * 0.5
	local half_h = height * 0.5
	return {
		left = pos.x - half_w,
		right = pos.x + half_w,
		bottom = pos.y - half_h,
		top = pos.y + half_h,
	}
end

-- Рассчитать площадь пересечения
function M.get_overlap_area(rect_a, rect_b)
	local x_overlap = math.max(0, math.min(rect_a.right, rect_b.right) - math.max(rect_a.left, rect_b.left))
	local y_overlap = math.max(0, math.min(rect_a.top, rect_b.top) - math.max(rect_a.bottom, rect_b.bottom))
	return x_overlap * y_overlap
end

-- Найти стопку с максимальным перекрытием
function M.find_best_pile_overlap(card_pos, piles_table, ignore_id)
	-- Геометрия перетаскиваемой карты
	local card_rect = M.get_bounds(card_pos, CONST.CARD_WIDTH, CONST.CARD_HEIGHT)

	local best_pile = nil
	local max_area = 0

	-- Порог чувствительности (например, 15% площади карты)
	local threshold_area = (CONST.CARD_WIDTH * CONST.CARD_HEIGHT) * 0.15

	-- === DEBUG START (Раскомментируй, если снова будут проблемы) ===
	-- print("--- DRAG CHECK START ---")
	-- print("Card Pos: " .. tostring(card_pos))
	-- ==============================================================

	for _, pile in pairs(piles_table) do
		if pile.id ~= ignore_id then
			-- !!! ИСПРАВЛЕНИЕ ЛОГИКИ !!!
			-- Определяем, с чем именно мы ищем пересечение: с базой стопки или с последней картой.
			local target_pos = pile.pos

			-- Если это "Каскад" (подземелье) и там есть карты, целью является ПОСЛЕДНЯЯ КАРТА.
			-- Иначе игрок будет пытаться положить карту на пустое место вверху, а не на карту внизу.
			if pile.layout == "cascade" and #pile.cards > 0 then
				local last_card = pile.cards[#pile.cards]
				-- Если у карты есть GO, берем его точную позицию
				if last_card.go_id then
					target_pos = go.get_position(last_card.go_id)
				else
					-- Если вдруг GO нет (редкий случай рассинхрона), считаем математически
					local offset_y = (#pile.cards - 1) * CONST.OVERLAP_OFFSET
					target_pos = vmath.vector3(pile.pos.x, pile.pos.y - offset_y, pile.pos.z)
				end
			end
			-- Для "Stack" (инвентарь, отряд) карты лежат на pile.pos, поэтому менять target_pos не нужно.

			local pile_rect = M.get_bounds(target_pos, CONST.CARD_WIDTH, CONST.CARD_HEIGHT)
			local area = M.get_overlap_area(card_rect, pile_rect)

			-- === DEBUG INFO ===
			-- if area > 0 then
			-- 	print(string.format("Checking Pile [%s]: Area = %.2f (Need > %.2f)", pile.id, area, threshold_area))
			-- end
			-- ==================

			if area > max_area and area > threshold_area then
				max_area = area
				best_pile = pile
			end
		end
	end

	-- if best_pile then
	-- 	print(">>> WINNER: " .. best_pile.id .. " with area " .. max_area)
	-- end

	return best_pile
end

return M
