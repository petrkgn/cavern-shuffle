-- /game/modules/systems/render_system.lua (ПОЛНАЯ ПРАВИЛЬНАЯ ВЕРСИЯ)

local CONST = require("game.modules.constants")
local M = {}


-- Рассчитывает позицию карты в стопке
function M.get_card_pos(pile, card_index)
	local z = (card_index or 0) * 0.01 -- Z-step

	if pile.layout == "stack" then
		return vmath.vector3(pile.pos.x, pile.pos.y, z)

	elseif pile.layout == "cascade" then
		-- Каскад для подземелья
		return vmath.vector3(pile.pos.x, pile.pos.y - (CONST.OVERLAP_OFFSET * ((card_index or 1) - 1)), z)

	elseif pile.layout == "stack_offset" then
		-- Сдвиг для Талона (показываем последние 3 карты)
		-- Но реально позиционируем все, просто сдвигаем визуально? 
		-- Обычно в пасьянсах в талоне сдвинуты только 2-3 верхние.
		-- Упрощенная логика: сдвигаем всех (или доработайте под визуализацию 3-х последних)
		local x_offset = 25 * ((card_index or 1) - 1)
		return vmath.vector3(pile.pos.x + x_offset, pile.pos.y, z)
	end
	return vmath.vector3(pile.pos.x, pile.pos.y, z)
end


function M.move_card(card, to_pile, to_index, delay, on_complete, easing, from_pile)
	delay = delay or 0
	easing = easing or go.EASING_OUTSINE
	local dest_pos = M.get_card_pos(to_pile, to_index)

	-- Определяем, является ли это действием "Раздача из колоды" (карта открывается, вылетая из explore)
	local is_drawing_from_deck = from_pile and from_pile.id == "explore" and not card.is_hidden

	-- Шаг 1: Создаем GO, если его нет
	if not card.go_id then
		local start_pos
		if from_pile then
			local start_index = (from_pile.id == "talon" and #from_pile.cards + 1) or 1
			start_pos = M.get_card_pos(from_pile, start_index)
		else
			start_pos = dest_pos
		end

		-- V-- ИЗМЕНЕНИЕ: Если раздаем из колоды, спавним карту ЗАКРЫТОЙ --V
		local spawn_hidden = card.is_hidden
		if is_drawing_from_deck then
			spawn_hidden = true
		end

		card.go_id = factory.create(
		"#card_factory",
		start_pos,
		nil,
		{
			face = hash(card.face), 
			suit = hash(card.suit), 
			hidden = spawn_hidden and hash("hidden") or hash("")
		},
		CONST.CARD_SCALE
	)
end

-- Шаг 2: Управляем визуалом (лицо/рубашка) с учетом анимации
if not card.is_hidden then
	if is_drawing_from_deck then
		-- V-- ИЗМЕНЕНИЕ: Отложенный переворот --V
		-- Карта создана рубашкой. Мы ждем начала движения и запускаем флип.
		-- delay + 0.05 — запускаем чуть позже начала движения, чтобы было видно, как она летит
		timer.delay(delay + 0.01, false, function()
			if card.go_id then -- Проверка на случай, если карту успели удалить
				msg.post(card.go_id, "reveal")
			end
		end)
	else
		-- Обычное поведение (сразу показываем лицо, если это не раздача)
		msg.post(card.go_id, "reveal")
	end
else
	msg.post(card.go_id, "hide")
end

-- Шаг 3: Перед анимацией ВСЕГДА поднимаем карту наверх.
local current_pos = go.get_position(card.go_id)
go.set_position(vmath.vector3(current_pos.x, current_pos.y, 0.8), card.go_id)

-- Шаг 4: Анимируем в точку с высоким Z.
local animation_target_pos = vmath.vector3(dest_pos.x, dest_pos.y, 0.9)

-- Шаг 5: Колбэк.
local final_callback = function()
	go.set_position(dest_pos, card.go_id)
	if on_complete then
		on_complete()
	end
end

-- Шаг 6: Запускаем анимацию.
go.animate(card.go_id, "position", go.PLAYBACK_ONCE_FORWARD, animation_target_pos, easing, 0.5, delay, final_callback)
end


function M.redraw_pile(pile)
	-- Просто расставляем все существующие GO по их правильным местам.
	-- Эта функция больше НЕ отвечает за открытие карт.

	for i, card in ipairs(pile.cards) do
		local pos = M.get_card_pos(pile, i)
		if card.go_id then
			go.set_position(pos, card.go_id)
		else
			-- Создаем, если GO по какой-то причине отсутствует
			card.go_id = factory.create(
			"#card_factory",
			pos, nil,
			{face = hash(card.face), suit = hash(card.suit), hidden = card.is_hidden and hash("hidden") or hash("")},
			CONST.CARD_SCALE
		)
	end
end
end

function M.update_explore_pile_sprite(explore_pile)
if not explore_pile or not explore_pile.placeholder_go then return end
if #explore_pile.cards > 0 then
	msg.post(explore_pile.placeholder_go, "set_sprite", { id = "card_back", instant = true })
else
	msg.post(explore_pile.placeholder_go, "set_sprite", { id = "card_empty", instant = true })
end
end

-- Новая функция для отрисовки доступных карт
function M.redraw_talon_pile(pile)
	-- Удаляем старые, если они есть
	for _, card in ipairs(pile.cards) do
		if card.go_id then go.delete(card.go_id) card.go_id = nil end
	end

	-- Рисуем новые (максимум 3)
	for i, card in ipairs(pile.cards) do
		-- Теперь visual_index - это просто i!
		local dest_pos = M.get_card_pos(pile, i)
		card.go_id = factory.create(
		"#card_factory",
		dest_pos, nil,
		{face = hash(card.face), suit = hash(card.suit), hidden = hash("")},
		CONST.CARD_SCALE
	)
	end
end

-- НОВАЯ ФУНКЦИЯ для красивого возврата карт
function M.animate_return(cards_to_return, to_pile)
	for i, card in ipairs(cards_to_return) do
		local original_index = -1
		for j, pile_card in ipairs(to_pile.cards) do
			if pile_card == card then
				original_index = j
				break
			end
		end

		if original_index ~= -1 then
			-- 1. Рассчитываем финальную, "родную" позицию карты с правильным низким Z.
			local final_pos = M.get_card_pos(to_pile, original_index)

			-- 2. Перед анимацией мгновенно поднимаем карту наверх.
			local current_pos = go.get_position(card.go_id)
			go.set_position(vmath.vector3(current_pos.x, current_pos.y, 0.9), card.go_id) -- Самый высокий Z

			-- 3. Анимируем в точку с высоким Z, чтобы полет был "поверх".
			local anim_dest = vmath.vector3(final_pos.x, final_pos.y, 0.8)

			-- 4. Создаем колбэк, который "приземлит" карту на ее правильный Z.
			local on_complete = function()
				go.set_position(final_pos, card.go_id)
			end

			-- 5. Запускаем анимацию.
			go.animate(card.go_id, "position", go.PLAYBACK_ONCE_FORWARD, anim_dest, go.EASING_OUTBACK, 0.3, (i-1)*0.05, on_complete)
		end
	end
end

-- НОВАЯ ФУНКЦИЯ для красивого "улета" карты на кладбище
function M.animate_to_graveyard(card, on_complete)
	if not card or not card.go_id then
		if on_complete then on_complete() end
		return
	end

	-- Поднимаем карту наверх
	local pos = go.get_position(card.go_id)
	go.set_position(vmath.vector3(pos.x, pos.y, 0.9), card.go_id)

	-- Анимируем улет вниз за экран
	local final_pos = vmath.vector3(pos.x, -200, 0.9)

	local final_callback = function()
		go.delete(card.go_id)
		card.go_id = nil -- Важно
		if on_complete then on_complete() end
	end

	go.animate(card.go_id, "position", go.PLAYBACK_ONCE_FORWARD, final_pos, go.EASING_INSINE, 0.4, 0, final_callback)
end

function M.animate_and_delete(card_or_go_id, destination, delay, on_complete)
	-- V-- ДЕЛАЕМ ФУНКЦИЮ УМНОЙ --V
	local go_id
	local card_data = nil

	if type(card_or_go_id) == "table" then
		-- Если передали таблицу карты
		go_id = card_or_go_id.go_id
		card_data = card_or_go_id
	else
		-- Если передали просто go_id
		go_id = card_or_go_id
	end
	-- ^-- КОНЕЦ УМНОЙ ЧАСТИ --^

	if not go_id or not go.exists(go_id) then
		if on_complete then on_complete() end
		return
	end

	local pos = go.get_position(go_id)
	go.set_position(vmath.vector3(pos.x, pos.y, 0.9), go_id)

	local final_pos = destination or vmath.vector3(pos.x, -200, 0.9)

	local final_callback = function()
		go.delete(go_id)
		-- Если у нас есть ссылка на данные карты, обнуляем в ней go_id
		if card_data then
			card_data.go_id = nil
		end
		if on_complete then on_complete() end
	end

	go.animate(go_id, "position", go.PLAYBACK_ONCE_FORWARD, final_pos, go.EASING_INOUTSINE, 0.4, delay or 0, final_callback)
end

function M.update_animations(state, dt)
	if state.is_restarting then return end
	local screen_center = vmath.vector3(1024/2, 768/2, 0.5)
	
	if state.is_won then
		-- === 0. АНИМАЦИЯ МИНОТАВРА ===
		if state.win_minotaur_card and not state.win_minotaur_card.go_id then
			-- Создаем GO для Минотавра, если его еще нет
			local card = state.win_minotaur_card
			card.go_id = factory.create("#card_factory", screen_center, nil, {
				face = hash(card.face), suit = hash(card.suit)
			}, CONST.CARD_SCALE * 1.2) -- Сразу делаем его большим
		end

		-- === 1. АНИМАЦИЯ ХОРОВОДА (VORTEX) ===
		if #state.vortex_cards > 0 then
			local orbits = {200, 260, 320}
			local rotation_speed = math.pi / 10 -- Скорость вращения

			for i, card in ipairs(state.vortex_cards) do
				if not card.is_attacking then
					-- Если у карты нет go_id, значит, она только что попала в vortex. Создаем его.
					if not card.go_id then
						-- Создаем в центре, чтобы она "вылетала" оттуда
						card.go_id = factory.create("#card_factory", screen_center, nil, {
							face = hash(card.face), suit = hash(card.suit)
						}, CONST.CARD_SCALE)
						msg.post(card.go_id, "reveal")

						-- Задаем ей уникальные параметры для вращения
						card.vortex_radius = orbits[((i-1) % #orbits) + 1]
						card.vortex_angle = (i-1) * (2 * math.pi) / #state.vortex_cards
					end

					-- Обновляем угол вращения
					card.vortex_angle = card.vortex_angle + rotation_speed * dt

					-- Рассчитываем новую позицию на орбите
					local target_x = screen_center.x + card.vortex_radius * math.cos(card.vortex_angle)
					local target_y = screen_center.y + card.vortex_radius * math.sin(card.vortex_angle)
					local target_pos = vmath.vector3(target_x, target_y, 0.4 - i * 0.001)

					-- Плавно двигаем карту к ее точке на орбите
					local current_pos = go.get_position(card.go_id)
					local new_pos = vmath.lerp(0.1, current_pos, target_pos) -- 0.1 - скорость "притяжения"
					go.set_position(new_pos, card.go_id)
				end
			end
		end


-- === 2. ЛОГИКА АТАКИ (ИЗМЕНЕНО) ===
state.vortex_attack_timer = (state.vortex_attack_timer or 0) - dt
if state.vortex_attack_timer <= 0 then
	state.vortex_attack_timer = 0.5 + math.random() * 1.0 -- Атаки чуть чаще для динамики

	if #state.vortex_cards > 0 then
		local attacker_card = state.vortex_cards[math.random(#state.vortex_cards)]

		-- Убедимся, что карта существует и она еще не в атаке
		if attacker_card and attacker_card.go_id and not attacker_card.is_attacking then
			attacker_card.is_attacking = true 

			-- Запоминаем исходную позицию (хотя она пересчитается в цикле, но для старта анимации полезно)
			local start_pos = go.get_position(attacker_card.go_id)

			-- 1. ПОДНИМАЕМ Z (чтобы карта была НАД минотавром)
			-- Минотавр на 0.5, ставим атакующего на 0.6
			start_pos.z = 0.6
			go.set_position(start_pos, attacker_card.go_id)

			-- Точка удара (центр экрана, Z=0.6)
			local hit_pos = vmath.vector3(screen_center.x, screen_center.y, 0.6)

			-- ЭТАП 1: РЫВОК К ЦЕНТРУ
			go.animate(attacker_card.go_id, "position", go.PLAYBACK_ONCE_FORWARD, hit_pos, go.EASING_INBACK, 0.2, 0, function()
				if not go.exists(attacker_card.go_id) then return end

				-- ЭТАП 2: МОМЕНТ УДАРА (Callback)

				-- А. Эффекты на Минотавре (Вспышка + Тряска)
				if state.win_minotaur_card and state.win_minotaur_card.go_id then
					msg.post(state.win_minotaur_card.go_id, "play_hit_effect")
				end

				-- Б. Спавн Слэша (Поверх всего, Z=0.7)
				local slash_pos = vmath.vector3(screen_center.x, screen_center.y, 0.7)
				-- Используем абсолютный URL к фабрике, так как RenderSystem - это Lua модуль
				factory.create("game:/game#slash_factory", slash_pos, nil, {}, 2)

				-- ЭТАП 3: ВОЗВРАТ ОБРАТНО
				-- Мы просто отпускаем флаг через небольшую паузу или анимацию отлета.
				-- Карта сама вернется на орбиту благодаря Lerp в цикле vortex выше,
				-- но чтобы это было красиво, анимируем отлет чуть-чуть назад.

				-- Вычисляем примерную точку возврата (просто откидываем назад по вектору атаки)
				local retreat_dir = vmath.normalize(start_pos - hit_pos)
				local retreat_pos = hit_pos + retreat_dir * 100 -- Откидываем на 100px

				go.animate(attacker_card.go_id, "position", go.PLAYBACK_ONCE_FORWARD, retreat_pos, go.EASING_OUTQUAD, 0.3, 0, function()
					attacker_card.is_attacking = false
					-- Z-индекс сам исправится в следующем кадре в цикле vortex
				end)
			end)
		end
	end
end
end
	-- === 2. АНИМАЦИЯ ПЕРЕЗАПУСКА ===
	if #state.restarting_cards > 0 then
		local explore_pos = state.piles.explore.pos

		for i = #state.restarting_cards, 1, -1 do
			local card = state.restarting_cards[i]

			if not card.go_id then -- На всякий случай, если что-то пошло не так
				table.remove(state.restarting_cards, i)
			else
				local current_pos = go.get_position(card.go_id)
				local target_pos = vmath.vector3(explore_pos.x, explore_pos.y, current_pos.z)

				-- Двигаем карту в сторону колоды
				local new_pos = vmath.lerp(0.1, current_pos, target_pos)
				go.set_position(new_pos, card.go_id)

				-- Если карта почти долетела, удаляем ее
				if vmath.length(target_pos - new_pos) < 5 then
					go.delete(card.go_id)
					table.remove(state.restarting_cards, i)
				end
			end
		end

		-- Если все карты улетели, сообщаем об этом
		if #state.restarting_cards == 0 then
			msg.post("game:/game#game_script", "restart_animation_finished")
		end
	end
end

return M