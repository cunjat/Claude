--!strict
-- TYRE CANNON :: Settings2
-- How the game feels, in the kit's own style: two columns of rows, every control applying the
-- moment it moves and saving a beat later (Prefs).
--   Sound      music, effects
--   Controls   steering sensitivity, invert up/down, camera (chase or first person)
--   Display    camera shake, particles, UI size, performance readout
--   Fun        the victory dance
--   Settings2.new(gui, previewDance) · :open() · :close() · :isOpen()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Config"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Prefs = require(script.Parent.Prefs)
local C = Kit.C

local Settings2 = {}
Settings2.__index = Settings2

local PARTICLES = {
	{ id = "low", label = "Low", value = 0.35 },
	{ id = "medium", label = "Med", value = 0.65 },
	{ id = "high", label = "High", value = 1 },
}

local COL_W = 408

function Settings2.new(gui: ScreenGui, previewDance: (() -> ())?)
	local self = setmetatable({}, Settings2)
	self.gui = gui
	local root = UI.mk("Frame", {
		Name = "Settings2", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(900, 520),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.root = root
	local holder, face = Kit.card(UDim2.fromOffset(900, 510), C.cream)
	holder.Parent = root
	Kit.header(face, "Settings", C.blue, 56)
	local close = Kit.close(52)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, 12, 0, -14)
	close.root.ZIndex = 40
	close.root.Parent = root
	close.onClick = function() self:close() end

	-- one column builds down from the top: a heading, then rows
	local function column(x: number)
		local y = 60
		local col = {}
		function col.heading(text: string)
			local sec = Kit.section(face, text, UDim2.fromOffset(x, y), UDim2.fromOffset(COL_W, 30), 5)
			sec.Name = "Section"
			y += 38
		end
		function col.row(label: string): Frame
			local r = UI.mk("Frame", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(COL_W, 50), BackgroundTransparency = 1, ZIndex = 5, Parent = face })
			local l = Kit.text(label, 18, C.text, 2)
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Position = UDim2.fromOffset(10, 0)
			l.Size = UDim2.fromOffset(150, 50)
			Kit.fit(l, 18, 11)
			l.ZIndex = 6
			l.Parent = r
			local control = UI.mk("Frame", { Name = "Control", Position = UDim2.fromOffset(164, 0), Size = UDim2.fromOffset(COL_W - 170, 50), BackgroundTransparency = 1, ZIndex = 6, Parent = r })
			y += 52
			return control
		end
		function col.gap(n: number) y += n end
		return col
	end

	-- a slider row with its value printed beside it
	local function slider(control: Frame, key: string, fmt: (number) -> string, toValue: ((number) -> number)?, fromValue: ((number) -> number)?)
		local readout = Kit.text("", 16, C.gold, 2)
		readout.AnchorPoint = Vector2.new(1, 0.5)
		readout.Position = UDim2.fromScale(1, 0.5)
		readout.Size = UDim2.fromOffset(56, 24)
		readout.TextXAlignment = Enum.TextXAlignment.Right
		readout.ZIndex = 8
		readout.Parent = control
		local s, show = Kit.slider(COL_W - 170 - 64, fromValue and fromValue(Prefs.get(key)) or Prefs.get(key) or 0, function(t)
			local v = if toValue then toValue(t) else t
			readout.Text = fmt(v)
			Prefs.set(key, v)
		end, C.accent)
		s.AnchorPoint = Vector2.new(0, 0.5)
		s.Position = UDim2.fromScale(0, 0.5)
		s.ZIndex = 8
		s.Parent = control
		Prefs.watch(key, function(v)
			readout.Text = fmt(v)
			show(if fromValue then fromValue(v) else v)
		end)
	end
	local function pct(v: number): string
		return math.floor(v * 100 + 0.5) .. "%"
	end

	-- left: sound and controls
	local left = column(26)
	left.heading("Sound")
	slider(left.row("Music"), "music", pct)
	slider(left.row("Effects"), "sfx", pct)
	left.gap(6)
	left.heading("Controls")
	slider(left.row("Steering"), "sens", pct)
	do
		local c = left.row("Invert up/down")
		local t, set = Kit.toggle(Prefs.get("invertpitch") == true, function(v) Prefs.set("invertpitch", v, true) end)
		t.AnchorPoint = Vector2.new(0, 0.5)
		t.Position = UDim2.fromScale(0, 0.5)
		t.ZIndex = 8
		t.Parent = c
		Prefs.watch("invertpitch", function(v) set(v == true) end)
	end
	do
		local c = left.row("Camera")
		local seg, set = Kit.segment({ { id = "chase", label = "Chase" }, { id = "first", label = "1st Person" } }, Prefs.get("camera") or "chase", 115, 38, function(id)
			Prefs.set("camera", id, true)
		end)
		seg.AnchorPoint = Vector2.new(0, 0.5)
		seg.Position = UDim2.fromScale(0, 0.5)
		seg.ZIndex = 8
		seg.Parent = c
		Prefs.watch("camera", function(v) set(v or "chase") end)
	end

	-- right: display and the dance
	local right = column(466)
	right.heading("Display")
	slider(right.row("Camera shake"), "shake", pct)
	do
		local c = right.row("Particles")
		local current = "high"
		for _, p in ipairs(PARTICLES) do
			if math.abs((Prefs.get("particles") or 1) - p.value) < 0.1 then current = p.id end
		end
		local seg, set = Kit.segment(PARTICLES :: any, current, 74, 38, function(id)
			for _, p in ipairs(PARTICLES) do
				if p.id == id then Prefs.set("particles", p.value, true) end
			end
		end)
		seg.AnchorPoint = Vector2.new(0, 0.5)
		seg.Position = UDim2.fromScale(0, 0.5)
		seg.ZIndex = 8
		seg.Parent = c
		Prefs.watch("particles", function(v)
			for _, p in ipairs(PARTICLES) do
				if math.abs((v or 1) - p.value) < 0.1 then set(p.id) end
			end
		end)
	end
	slider(right.row("UI size"), "uiScale", pct, function(t) return 0.85 + t * 0.3 end, function(v) return ((v or 1) - 0.85) / 0.3 end)
	do
		local c = right.row("Performance")
		local t, set = Kit.toggle(Prefs.get("perf") == true, function(v) Prefs.set("perf", v, true) end)
		t.AnchorPoint = Vector2.new(0, 0.5)
		t.Position = UDim2.fromScale(0, 0.5)
		t.ZIndex = 8
		t.Parent = c
		Prefs.watch("perf", function(v) set(v == true) end)
	end
	right.gap(6)
	right.heading("Fun")
	do
		local c = right.row("Victory dance")
		local function index(id: string): number
			for i, d in ipairs(Config.VictoryDances) do
				if d.id == id then return i end
			end
			return 1
		end
		local function step(dir: number)
			local n = #Config.VictoryDances
			Prefs.set("dance", Config.VictoryDances[((index(Prefs.get("dance")) - 1 + dir) % n) + 1].id, true)
		end
		local prev = Kit.button("<", C.grey, UDim2.fromOffset(36, 38), 20)
		prev.root.AnchorPoint = Vector2.new(0, 0.5)
		prev.root.Position = UDim2.fromScale(0, 0.5)
		prev.root.ZIndex = 8
		prev.root.Parent = c
		prev.onClick = function() step(-1) end
		local name = Kit.text("", 15, C.white, 2)
		name.AnchorPoint = Vector2.new(0, 0.5)
		name.Position = UDim2.new(0, 40, 0.5, 0)
		name.Size = UDim2.fromOffset(150, 38)
		Kit.fit(name, 15, 9)
		name.ZIndex = 8
		name.Parent = c
		local nextB = Kit.button(">", C.grey, UDim2.fromOffset(36, 38), 20)
		nextB.root.AnchorPoint = Vector2.new(0, 0.5)
		nextB.root.Position = UDim2.new(0, 194, 0.5, 0)
		nextB.root.ZIndex = 8
		nextB.root.Parent = c
		nextB.onClick = function() step(1) end
		Prefs.watch("dance", function(id)
			local d = Config.VictoryDancesById[id] or Config.VictoryDances[1]
			name.Text = string.upper(d.name)
		end)
	end
	if previewDance then
		local c = right.row("Preview")
		local pv = Kit.button("Play it", C.accent, UDim2.fromOffset(238, 40), 18)
		pv.root.AnchorPoint = Vector2.new(0, 0.5)
		pv.root.Position = UDim2.fromScale(0, 0.5)
		pv.root.ZIndex = 8
		pv.root.Parent = c
		pv.onClick = function()
			self:close()
			task.delay(0.25, previewDance)
		end
	end
	-- the playtest's notes (Feedback)
	local fb = Kit.button("Send Feedback", C.green, UDim2.fromOffset(220, 44), 18)
	fb.root.AnchorPoint = Vector2.new(1, 0)
	fb.root.Position = UDim2.new(1, -28, 0, 448)
	fb.root.ZIndex = 8
	fb.root.Parent = face
	fb.onClick = function()
		self:close()
		if self.onFeedback then task.delay(0.25, self.onFeedback) end
	end
	-- (2026-10-16) what everything does, and the tutorial again (Help)
	local help = Kit.button("Help & Tutorial", C.blue, UDim2.fromOffset(220, 44), 18)
	help.root.Position = UDim2.fromOffset(28, 448)
	help.root.ZIndex = 8
	help.root.Parent = face
	help.onClick = function()
		self:close()
		if self.onHelp then task.delay(0.25, self.onHelp) end
	end
	local tip = Kit.text("Shift lock: press Ctrl in the yard.", 14, C.muted, 1.5, Kit.Body)
	tip.Position = UDim2.fromOffset(0, 462)
	tip.Size = UDim2.new(1, 0, 0, 22)
	tip.ZIndex = 6
	tip.Parent = face
	return self
end

function Settings2:open()
	Kit.dim(self.gui, self, true)
	Kit.open(self.root)
end

function Settings2:close()
	Kit.dim(self.gui, self, false)
	if not self.root.Visible then return end
	Kit.close_(self.root)
end

function Settings2:isOpen(): boolean
	return self.root.Visible
end

return Settings2
