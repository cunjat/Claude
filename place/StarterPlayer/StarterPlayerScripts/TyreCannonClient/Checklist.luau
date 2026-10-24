--!strict
-- TYRE CANNON :: Checklist
-- A card of things to do, ticked off as they're done: the tutorial's in the yard, and the yard tour's
-- in the editor. Each row is a box and a line; the one to do now is lit in the card's colour with a
-- marker beside it, a done one fills green, its tick pops in, a line strikes through it and a small
-- chime plays. A bar under the title fills as they go. When the last one's ticked the card flashes
-- and slides away.
--   Checklist.new(gui, { title, color, items = { { id, text } }, side = "left" | "right", y = 0.5, values = bool, w = number })
--   :set(id, done) ; :focus(id?) ; :show(on) ; :finish(after?) ; :destroy()
--   onClose = fn (a small X in the corner)
--   :setValue(id, text) (with values: a count on the right of each row) ; :setTitle(text) ; :setNote(text)

local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Sound = require(script.Parent.Sound)
local C = Kit.C

local Checklist = {}
Checklist.__index = Checklist

local ROW = 40
local TOP = 62

function Checklist.new(gui: ScreenGui, opts)
	local self = setmetatable({}, Checklist)
	local W = opts.w or 290
	self.W = W
	local items = opts.items
	local color = opts.color or C.accent
	self.color = color
	self.side = opts.side or "right"
	local h = TOP + #items * ROW + 12 + (if opts.note then 22 else 0)
	local right = self.side == "right"
	local root = UI.mk("Frame", {
		Name = "Checklist", AnchorPoint = Vector2.new(if right then 1 else 0, 0.5),
		-- (on a phone it sits lower, under the corner buttons)
		Position = UDim2.new(if right then 1 else 0, if right then -24 else 24, if UI.isPhone() then math.max(opts.y or 0.5, 0.62) else (opts.y or 0.5), 0), Size = UDim2.fromOffset(W, h),
		BackgroundTransparency = 1, Visible = false, ZIndex = 40, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.root = root
	self.rest = root.Position
	local face = UI.mk("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 40, Parent = root })
	self.face = face
	Kit.panel(face, color, 40)
	local title = Kit.text(string.upper(opts.title or "TO DO"), 19, C.white, 2)
	self.title = title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.fromOffset(W - 90, 22)
	Kit.fit(title, 19, 10)
	title.ZIndex = 43
	title.Parent = face
	local count = Kit.text("", 17, C.gold, 2)
	count.AnchorPoint = Vector2.new(1, 0)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Position = UDim2.new(1, if opts.onClose then -48 else -18, 0, 13)
	count.Size = UDim2.fromOffset(60, 20)
	count.ZIndex = 43
	count.Parent = face
	self.count = count
	-- (with onClose: a small X in the corner)
	if opts.onClose then
		local x = Kit.close(30)
		x.root.AnchorPoint = Vector2.new(1, 0)
		x.root.Position = UDim2.new(1, -12, 0, 8)
		x.root.ZIndex = 46
		x.face.ZIndex = 46
		x.root.Parent = face
		x.onClick = opts.onClose
	end
	local track, fill = Kit.bar(W - 36, 12, C.green)
	track.Position = UDim2.fromOffset(18, 40)
	track.ZIndex = 43
	track.Parent = face
	self.fill = fill

	self.rows = {}
	self.order = {}
	for i, it in ipairs(items) do
		local y = TOP + (i - 1) * ROW
		local row = UI.mk("Frame", { Position = UDim2.fromOffset(10, y), Size = UDim2.fromOffset(W - 20, ROW - 4), BackgroundTransparency = 1, ZIndex = 41, Parent = face })
		-- the light behind the row to do now
		local lit = UI.mk("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 41, Parent = row,
		}, { UI.corner(8) })
		UI.mk("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }), Parent = lit })
		local box = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 22, 0.5, 0), Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = C.well, BorderSizePixel = 0, ZIndex = 43, Parent = row,
		}, { UI.corner(7) })
		local stroke = UI.mk("UIStroke", { Color = C.line, Thickness = 2, Parent = box })
		-- the tick: two strokes, drawn as narrow bars turned about their middles
		local tick = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 44, Parent = box })
		UI.mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(8, 14), Size = UDim2.fromOffset(9, 4), Rotation = 45,
			BackgroundColor3 = C.white, BorderSizePixel = 0, ZIndex = 45, Parent = tick,
		}, { UI.corner(2) })
		UI.mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(14, 11), Size = UDim2.fromOffset(15, 4), Rotation = -50,
			BackgroundColor3 = C.white, BorderSizePixel = 0, ZIndex = 45, Parent = tick,
		}, { UI.corner(2) })
		local label = Kit.text(it.text, 16, C.muted, 1.5, Kit.Body)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(56, 0)
		label.Size = UDim2.new(1, if opts.values then -142 else -64, 1, 0)
		Kit.fit(label, 16, 9)
		label.ZIndex = 43
		label.Parent = row
		-- the strike through a done one, drawn across the words' own width
		local strike = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 56, 0.5, 1), Size = UDim2.fromOffset(0, 2),
			BackgroundColor3 = C.muted, BorderSizePixel = 0, ZIndex = 44, Parent = row,
		})
		local marker = Kit.text(">", 18, color, 2)
		marker.AnchorPoint = Vector2.new(0, 0.5)
		marker.Position = UDim2.new(0, 2, 0.5, 0)
		marker.Size = UDim2.fromOffset(14, 20)
		marker.TextTransparency = 1
		marker.ZIndex = 44
		marker.Parent = row
		local value = nil
		if opts.values then
			value = Kit.text("", 14, C.gold, 1.5, Kit.Body)
			value.AnchorPoint = Vector2.new(1, 0.5)
			value.TextXAlignment = Enum.TextXAlignment.Right
			value.Position = UDim2.new(1, -8, 0.5, 0)
			value.Size = UDim2.fromOffset(80, 18)
			Kit.fit(value, 14, 8)
			value.ZIndex = 44
			value.Parent = row
		end
		local r = { id = it.id, row = row, lit = lit, box = box, stroke = stroke, tick = tick, label = label, strike = strike, marker = marker, done = false, value = value }
		self.rows[it.id] = r
		table.insert(self.order, r)
	end
	if opts.note then
		local note = Kit.text(opts.note, 13, C.muted, 1.5, Kit.Body)
		note.TextXAlignment = Enum.TextXAlignment.Left
		note.Position = UDim2.new(0, 18, 1, -30)
		note.Size = UDim2.new(1, -36, 0, 18)
		Kit.fit(note, 13, 8)
		note.ZIndex = 43
		note.Parent = face
		self.note = note
	end
	self:refreshCount()
	-- the marker on the row to do now nudges along
	self.conn = game:GetService("RunService").RenderStepped:Connect(function()
		if not root.Visible then return end
		local f = self.focused
		if f and not f.done then
			local k = (math.sin(os.clock() * 5) + 1) / 2
			f.marker.Position = UDim2.new(0, 2 + k * 4, 0.5, 0)
			f.stroke.Transparency = 0.15 * k
		end
	end)
	return self
end

function Checklist:refreshCount()
	local n = 0
	for _, r in ipairs(self.order) do
		if r.done then n += 1 end
	end
	self.count.Text = ("%d/%d"):format(n, #self.order)
	self.fill.Size = UDim2.fromScale(n / math.max(1, #self.order), 1)
	return n
end

-- ticks one off (quietly when `quiet`: catching up on what was done before the card was up)
function Checklist:set(id: string, done: boolean, quiet: boolean?)
	local r = self.rows[id]
	if not r or r.done == done then return end
	r.done = done
	-- (the words' width on screen, back into the card's own units: the card is scaled to the screen)
	local sc = math.max(0.1, r.row.AbsoluteSize.X / (self.W - 20))
	local w = math.min(r.label.TextBounds.X, r.label.AbsoluteSize.X) / sc
	if done then
		r.box.BackgroundColor3 = C.green
		r.stroke.Color = Color3.fromRGB(150, 230, 120)
		r.stroke.Transparency = 0
		r.tick.Visible = true
		r.label.TextColor3 = C.muted
		r.marker.TextTransparency = 1
		Kit.tween(r.lit, 0.25, { BackgroundTransparency = 1 })
		if quiet then
			r.strike.Size = UDim2.fromOffset(w, 2)
		else
			Kit.pop(r.box, 0.4, 0.35)
			Kit.tween(r.strike, 0.3, { Size = UDim2.fromOffset(w, 2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			Sound.play("medal", { volume = 0.45, pitch = 1.25 + self:refreshCount() * 0.04, length = 0.8 })
			if self.root.Visible then Kit.pop(self.face, 0.97, 0.2) end
		end
	else
		r.box.BackgroundColor3 = C.well
		r.stroke.Color = C.line
		r.tick.Visible = false
		r.strike.Size = UDim2.fromOffset(0, 2)
	end
	self:refreshCount()
	if self.focused == r and done then self.focused = nil end
end

function Checklist:setValue(id: string, text: string)
	local r = self.rows[id]
	if r and r.value then r.value.Text = text end
end

function Checklist:setTitle(text: string)
	self.title.Text = string.upper(text)
end

function Checklist:setNote(text: string)
	if self.note then self.note.Text = text end
end

-- lights the row to do now (nil: none)
function Checklist:focus(id: string?)
	local r = id and self.rows[id] or nil
	if self.focused == r then return end
	local old = self.focused
	if old and not old.done then
		Kit.tween(old.lit, 0.2, { BackgroundTransparency = 1 })
		old.label.TextColor3 = C.muted
		old.marker.TextTransparency = 1
		old.stroke.Color = C.line
		old.stroke.Transparency = 0
	end
	self.focused = r
	if r and not r.done then
		Kit.tween(r.lit, 0.25, { BackgroundTransparency = 0 })
		r.label.TextColor3 = C.white
		r.marker.TextTransparency = 0
		r.stroke.Color = self.color
	end
end

function Checklist:show(on: boolean)
	if self.shown == on then return end
	self.shown = on
	local root = self.root
	if on then
		root.Visible = true
		local off = if self.side == "right" then 340 else -340
		root.Position = self.rest + UDim2.fromOffset(off, 0)
		Kit.tween(root, 0.45, { Position = self.rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		local off = if self.side == "right" then 340 else -340
		Kit.tween(root, 0.3, { Position = self.rest + UDim2.fromOffset(off, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.3, function()
			if not self.shown then root.Visible = false end
		end)
	end
end

-- all done: the card flashes gold and slides away
function Checklist:finish(after: (() -> ())?)
	local face = self.face
	local flash = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.gold, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 48, Parent = face }, { UI.corner(14) })
	Kit.tween(flash, 0.6, { BackgroundTransparency = 1 })
	Kit.pop(face, 0.9, 0.3)
	Sound.play("cheer", { volume = 0.5 })
	task.delay(1.6, function()
		self:show(false)
		task.delay(0.4, function()
			flash:Destroy()
			if after then after() end
		end)
	end)
end

function Checklist:destroy()
	if self.conn then self.conn:Disconnect() end
	self.root:Destroy()
end

return Checklist
