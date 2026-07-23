local State = require("game.modules.state")

local M = {}

-- === КОНСТАНТЫ ===
local FLIP_SPEED = 3.0
local TILT_SPEED = 10.0
local INERTIA_STRENGTH = 0.005
local INERTIA_DECAY = 0.2
local HIT_DURATION = 1

local CARD_WIDTH = 138
local CARD_HEIGHT = 192
local HITBOX_MARGIN = 30

-- Таблицы лукапа
local FACE_LOOKUP = {
	[hash("A")] = "A",
	[hash("02")] = "02",
	[hash("03")] = "03",
	[hash("04")] = "04",
	[hash("05")] = "05",
	[hash("06")] = "06",
	[hash("07")] = "07",
	[hash("08")] = "08",
	[hash("09")] = "09",
	[hash("10")] = "10",
	[hash("J")] = "J",
	[hash("Q")] = "Q",
	[hash("K")] = "K",
}
local SUIT_LOOKUP = {
	[hash("clubs")] = "clubs",
	[hash("diamonds")] = "diamonds",
	[hash("hearts")] = "hearts",
	[hash("spades")] = "spades",
}

-- === ЛОКАЛЬНЫЕ ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===

local function get_anim_name(self)
	if self.hidden == hash("hidden") then
		return hash("card_back")
	elseif self.card ~= hash("") then
		return self.card
	elseif self.suit ~= hash("") and self.face ~= hash("") then
		return hash("card_" .. SUIT_LOOKUP[self.suit] .. "_" .. FACE_LOOKUP[self.face])
	end
	return hash("card_back")
end

local function is_mouse_over(mx, my)
	local pos = go.get_position()
	local scale = go.get_scale()

	local current_w = CARD_WIDTH * scale.x
	local current_h = CARD_HEIGHT * scale.y

	local hit_w = current_w - (HITBOX_MARGIN * 2)
	local hit_h = current_h - (HITBOX_MARGIN * 2)

	local left = pos.x - (hit_w / 2)
	local right = pos.x + (hit_w / 2)
	local bottom = pos.y - (hit_h / 2)
	local top = pos.y + (hit_h / 2)

	return mx > left and mx < right and my > bottom and my < top
end

local function find_card_in_state(my_go_id)
	for pile_id, pile in pairs(State.data.piles) do
		for i, card_data in ipairs(pile.cards) do
			if card_data.go_id == my_go_id then
				return pile, i, card_data
			end
		end
	end
	return nil, nil, nil
end

local function is_tilt_allowed_logic(pile, index, card_data)
	if not pile then
		return false
	end
	if card_data.is_hidden then
		return false
	end

	local pid = pile.id
	if pid == "explore" then
		return false
	elseif string.find(pid, "party") then
		return false
	elseif pid == "talon" then
		return index == #pile.cards
	elseif string.find(pid, "dungeon") then
		local minotaur_idx = -1
		for i, c in ipairs(pile.cards) do
			if c.face == "K" and c.suit == "spades" then
				minotaur_idx = i
				break
			end
		end
		if minotaur_idx ~= -1 and index < minotaur_idx then
			return false
		end
		return true
	elseif string.find(pid, "inventory") then
		return true
	elseif pid == "discard" then
		return index == #pile.cards
	end
	return false
end

-- === ЛОГИКА ОБНОВЛЕНИЯ ===

local function update_flip(self, dt)
	if self.current_rot ~= self.target_rot then
		local diff = self.target_rot - self.current_rot
		local step = FLIP_SPEED * dt
		if math.abs(diff) <= step then
			self.current_rot = self.target_rot
			if self.transform_full_turn and self.target_rot == -1.0 then
				self.current_rot = 1.0
				self.target_rot = 1.0
				self.transform_full_turn = false
			end
		else
			self.current_rot = self.current_rot + (diff > 0 and step or -step)
		end
	end
	if math.abs(self.current_rot) < 0.15 and self.pending_anim then
		sprite.play_flipbook("#sprite", self.pending_anim)
		self.pending_anim = nil
		if self.transform_full_turn and self.spawn_poof_on_flip then
			local pos = go.get_world_position()
			pos.z = 0.2
			factory.create("game:/game#magic_poof_factory", pos, nil, {}, 0.5)
		end
	end
	self.rot_vec.x = self.current_rot
end

local function update_inertia(self, dt)
	local pos = go.get_position()
	local dx = pos.x - self.last_pos.x
	self.last_pos = pos
	if math.abs(dx) > 100 then
		dx = 0
	end
	local target_def_x = 0
	if self.is_dragging then
		target_def_x = dx * INERTIA_STRENGTH
	end
	self.deformation_vec.x = vmath.lerp(INERTIA_DECAY, self.deformation_vec.x, target_def_x)
	self.rot_vec.y = pos.x
	self.rot_vec.z = pos.y
end

local function update_tilt(self, dt, mx, my)
	local target_tilt_x, target_tilt_y, target_intensity = 0, 0, 0.0
	local is_hovering = false

	local basic_check = mx and my and not self.is_dragging and self.hidden == hash("")
	local allowed_by_rules = false

	if basic_check then
		local pile, idx, data = find_card_in_state(go.get_id())
		if pile then
			allowed_by_rules = is_tilt_allowed_logic(pile, idx, data)
		end
	end

	if basic_check and allowed_by_rules and is_mouse_over(mx, my) then
		is_hovering = true
		target_intensity = 1.0
		local scale = go.get_scale()
		local pos = go.get_position()
		target_tilt_x = (mx - pos.x) / ((CARD_WIDTH * scale.x) / 2)
		target_tilt_y = (my - pos.y) / ((CARD_HEIGHT * scale.y) / 2)
	end

	local speed = is_hovering and TILT_SPEED or (TILT_SPEED * 2.0)
	self.current_tilt.x = vmath.lerp(dt * speed, self.current_tilt.x, target_tilt_x)
	self.current_tilt.y = vmath.lerp(dt * speed, self.current_tilt.y, target_tilt_y)
	self.current_tilt.z = vmath.lerp(dt * speed, self.current_tilt.z, target_intensity)
	self.cursor_vec.x, self.cursor_vec.y, self.cursor_vec.z =
		self.current_tilt.x, self.current_tilt.y, self.current_tilt.z
end

local function update_hit(self, dt)
	self.time = self.time + dt
	self.time_vec.x = self.time
	if self.is_hit then
		self.hit_timer = self.hit_timer - dt
		if self.hit_timer <= 0 then
			self.is_hit = false
			self.hit_vec.x = 0.0
		else
			self.hit_vec.y = self.hit_timer / HIT_DURATION
		end
	end
end

-- === ОСНОВНЫЕ МЕТОДЫ (PUBLIC) ===

function M.init(self)
	self.rot_vec = vmath.vector4(1, 0, 0, 0)
	self.deformation_vec = vmath.vector4(0, 0, 0, 0)
	self.cursor_vec = vmath.vector4(0, 0, 0, 0)
	self.hit_vec = vmath.vector4(0, 0, 0, 0)
	self.time_vec = vmath.vector4(0, 0, 0, 0)
	self.time = 0
	self.is_hit = false
	self.hit_timer = 0
	self.current_rot = 1.0
	self.target_rot = 1.0
	self.last_pos = go.get_position()
	self.current_tilt = vmath.vector3(0, 0, 0)
	self.is_dragging = false
	self.pending_anim = nil
	self.is_highlighted = false
	self.transform_full_turn = false
	self.spawn_poof_on_flip = false
end

function M.update(self, dt, mx, my)
	update_flip(self, dt)
	update_inertia(self, dt)
	update_tilt(self, dt, mx, my)
	update_hit(self, dt)

	go.set("#sprite", "settings", self.rot_vec)
	go.set("#sprite", "deformation", self.deformation_vec)
	go.set("#sprite", "cursor_data", self.cursor_vec)
	go.set("#sprite", "time_vec", self.time_vec)
	go.set("#sprite", "hit_params", self.hit_vec)
end

function M.set_flip_target(self, instant)
	local anim = get_anim_name(self)
	self.pending_anim = anim
	if instant then
		sprite.play_flipbook("#sprite", anim)
		self.current_rot = 1.0
		self.target_rot = 1.0
		self.rot_vec.x = 1.0
		go.set("#sprite", "settings", self.rot_vec)
		self.pending_anim = nil
	else
		self.current_rot = 1.0
		self.target_rot = -1.0
	end
end

function M.start_drag(self)
	self.is_dragging = true
	self.is_highlighted = false
	go.set("#sprite", "hit_params", vmath.vector4(0, 0, 0, 0))
end

function M.stop_drag(self)
	self.is_dragging = false
end

function M.play_hit_effect(self)
	self.is_highlighted = false
	self.is_hit = true
	self.hit_timer = HIT_DURATION
	self.hit_vec.x = 1.0
	self.hit_vec.y = 1.0
	self.hit_vec.z = 20.0
end

function M.transform_from(self, message)
	self.pending_anim = message.anim
	self.current_rot = 1.0
	self.target_rot = -1.0
	self.transform_full_turn = true
	self.spawn_poof_on_flip = (message.spawn_poof ~= false)
end

return M
