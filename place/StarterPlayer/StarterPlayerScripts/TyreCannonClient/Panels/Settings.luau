--!strict
-- TYRE CANNON :: Panels / Settings
-- One place for how the game feels: the victory dance, sound, camera shake,
-- particles, UI size and the performance readout. Everything applies the moment it
-- changes and saves to the profile a beat later.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))
local UI = require(script.Parent.Parent.UI)
local Prefs = require(script.Parent.Parent.Prefs)
local T = UI.Theme

local PARTICLES = {
	{ id = "low", label = "Low", value = 0.35 },
	{ id = "medium", label = "Medium", value = 0.65 },
	{ id = "high", label = "High", value = 1 },
}

return function(hub)
	local m = hub:modal("Settings", "SETTINGS", "Changes apply straight away and save to your profile.", 760, 620)
	local body = m.body
	local list = UI.mk("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 11, Parent = body,
	}, { UI.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center) })

	local LABEL_W = 190
	local order = 0
	local function row(label: string, tip: string, h: number?): Frame
		order += 1
		local r = UI.mk("Frame", {
			Size = UDim2.new(1, 0, 0, h or 44), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 11, Parent = list,
		})
		local l = UI.text(string.upper(label), 15, "displayMed", T.text)
		l.Size = UDim2.new(0, LABEL_W, 1, 0)
		l.Position = UDim2.fromOffset(16, 0)
		l.ZIndex = 12
		l.Parent = r
		UI.tooltip(l, tip)
		local control = UI.mk("Frame", {
			Name = "Control", Position = UDim2.fromOffset(LABEL_W + 24, 0), Size = UDim2.new(1, -(LABEL_W + 40), 1, 0),
			BackgroundTransparency = 1, ZIndex = 12, Parent = r,
		})
		return control
	end
	local function divider()
		order += 1
		UI.plate("divider", { Size = UDim2.new(1, -24, 0, 10), LayoutOrder = order, ZIndex = 11, Parent = list })
	end

	-- a slider with its value printed beside it
	local function slider(control: Frame, key: string, fmt: (number) -> string, toValue: ((number) -> number)?, fromValue: ((number) -> number)?)
		local readout = UI.text("", 14, "monoBold", T.dim)
		readout.AnchorPoint = Vector2.new(1, 0.5)
		readout.Position = UDim2.fromScale(1, 0.5)
		readout.Size = UDim2.fromOffset(64, 20)
		readout.TextXAlignment = Enum.TextXAlignment.Right
		readout.ZIndex = 13
		readout.Parent = control
		local start = Prefs.get(key)
		local s, show = UI.slider(360, fromValue and fromValue(start) or start, function(t)
			local v = toValue and toValue(t) or t
			readout.Text = fmt(v)
			Prefs.set(key, v)
		end)
		s.AnchorPoint = Vector2.new(0, 0.5)
		s.Position = UDim2.fromScale(0, 0.5)
		s.ZIndex = 13
		s.Parent = control
		Prefs.watch(key, function(v)
			readout.Text = fmt(v)
			show(fromValue and fromValue(v) or v)
		end)
	end
	local function pct(v: number): string
		return math.floor(v * 100 + 0.5) .. "%"
	end

	-- victory dance
	do
		local control = row("Victory dance", "What your character does after a personal best. PREVIEW plays it now.", 44)
		-- step through the dances: < NAME >
		local function index(id: string): number
			for i, d in ipairs(Config.VictoryDances) do
				if d.id == id then return i end
			end
			return 1
		end
		local prev = UI.button("<", "ghost", 34, 34)
		prev.Name = "PrevDance"
		prev.AnchorPoint = Vector2.new(0, 0.5)
		prev.Position = UDim2.fromScale(0, 0.5)
		prev.Parent = control
		local plate = UI.plate("slot", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 40, 0.5, 0), Size = UDim2.fromOffset(210, 34), ZIndex = 12, Parent = control,
		})
		local name = UI.text("", 15, "display", T.text)
		name.Size = UDim2.fromScale(1, 1)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.ZIndex = 13
		name.Parent = plate
		local nextB = UI.button(">", "ghost", 34, 34)
		nextB.Name = "NextDance"
		nextB.AnchorPoint = Vector2.new(0, 0.5)
		nextB.Position = UDim2.new(0, 256, 0.5, 0)
		nextB.Parent = control
		local function step(dir: number)
			local n = #Config.VictoryDances
			local i = ((index(Prefs.get("dance")) - 1 + dir) % n) + 1
			Prefs.set("dance", Config.VictoryDances[i].id, true)
		end
		prev.Activated:Connect(function() step(-1) end)
		nextB.Activated:Connect(function() step(1) end)
		Prefs.watch("dance", function(id)
			local d = Config.VictoryDancesById[id] or Config.VictoryDances[1]
			name.Text = string.upper(d.name)
		end)
		local preview = UI.button("PREVIEW", "ghost", 92, 34)
		preview.Name = "PreviewDance"
		preview.TextSize = 13
		preview.AnchorPoint = Vector2.new(1, 0.5)
		preview.Position = UDim2.fromScale(1, 0.5)
		preview.Parent = control
		preview.Activated:Connect(function()
			if hub.anims then
				hub:closeAll()
				task.delay(0.15, function() hub.anims:victory() end)
			end
		end)
	end
	divider()

	slider(row("Music", "Radio and background music."), "music", pct)
	slider(row("Effects", "Engines, sparks, doors and everything else you hear."), "sfx", pct)
	divider()
	slider(row("Camera shake", "How hard the camera jolts on landings, hits, the garage door and the forge."), "shake", pct)
	do
		local control = row("Particles", "Smoke, sparks, dust and weather. Lower it if the game stutters.")
		local current = "high"
		for _, p in ipairs(PARTICLES) do
			if math.abs((Prefs.get("particles") or 1) - p.value) < 0.1 then current = p.id end
		end
		local picker, set = UI.choices(PARTICLES :: any, current, 110, 34, function(id)
			for _, p in ipairs(PARTICLES) do
				if p.id == id then Prefs.set("particles", p.value, true) end
			end
		end)
		picker.AnchorPoint = Vector2.new(0, 0.5)
		picker.Position = UDim2.fromScale(0, 0.5)
		picker.Parent = control
		Prefs.watch("particles", function(v)
			for _, p in ipairs(PARTICLES) do
				if math.abs((v or 1) - p.value) < 0.1 then set(p.id) end
			end
		end)
	end
	slider(row("UI size", "Makes every menu and the HUD bigger or smaller."), "uiScale", pct,
		function(t) return 0.85 + t * 0.3 end,
		function(v) return ((v or 1) - 0.85) / 0.3 end)
	divider()
	do
		local control = row("Performance", "Shows frame time, frames per second and memory in the corner.")
		local picker, set = UI.choices({ { id = "off", label = "Off" }, { id = "on", label = "On" } }, Prefs.get("perf") and "on" or "off", 110, 34, function(id)
			Prefs.set("perf", id == "on", true)
		end)
		picker.AnchorPoint = Vector2.new(0, 0.5)
		picker.Position = UDim2.fromScale(0, 0.5)
		picker.Parent = control
		Prefs.watch("perf", function(v) set(v and "on" or "off") end)
	end
	do
		local control = row("Shift lock", "Locks the camera behind your shoulder. Shift is sprint, so it lives on Ctrl.", 30)
		local l = UI.text("PRESS CTRL IN THE YARD", 14, "monoBold", T.dim)
		l.Size = UDim2.fromScale(1, 1)
		l.ZIndex = 13
		l.Parent = control
	end

	hub:register("Settings", { frame = m.frame, noAutoRefresh = true })
end
