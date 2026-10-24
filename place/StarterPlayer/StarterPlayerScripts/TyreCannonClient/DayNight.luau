--!strict
-- TYRE CANNON :: DayNight
-- A slow day over the yard, the same for everyone in the server because it runs off
-- the server clock. One day lasts DAY_MINUTES. After dark the lamps in
-- Workspace.Lobby.NightLamps come on, the sky turns deep blue, and the ambient light
-- stays high enough that every plot, sign and door still reads. It only drives the
-- yard: the workbench and the runs light themselves, and this steps aside for them.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local DayNight = {}
DayNight.__index = DayNight

local DAY_MINUTES = 16
local START_HOUR = 9.5
local DAWN, DUSK = 6.4, 18.2
local DAY_SHARE = 0.75          -- of each cycle, the part from dawn to dusk
local EVENING = 18.05           -- the hub's fixed hour: sun just down, the sky going deep (2026-10-23: a touch darker)
local NIGHT_AMBIENT = Color3.fromRGB(88, 92, 112)
local NIGHT_OUTDOOR = Color3.fromRGB(104, 110, 138)

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- (2026-10-22, the owner: "make the map more spooky ... fix it so we can revert it when halloween is
-- over") Halloween is a season, not an edit: everything spooky (this light, PlazaLife's pumpkins,
-- graves, bats and bunting) asks this one switch, so nothing has to be undone afterwards. On through
-- October and the first two days of November (UTC); workspace attribute Halloween = true / false
-- forces it either way (set it in Studio, or from the server, to preview or to end it early).
function DayNight.halloween(): boolean
	local forced = workspace:GetAttribute("Halloween")
	if forced ~= nil then return forced == true end
	local t = os.date("!*t")
	return t.month == 10 or (t.month == 11 and t.day <= 2)
end

function DayNight.clock(): number
	-- (2026-10-23, the owner: "set the time to always evening so the lights always pop") one fixed
	-- golden-hour evening, just past the lamps coming on (Halloween's grade still applies); workspace
	-- attribute EveningHour sets another hour, or false brings the old cycle back
	-- (2026-10-24, the owner: "readd the daylight cycle with renewed shaders and lighting") the cycle is
	-- back; a number in workspace attribute EveningHour still pins the hour (for screenshots)
	local fixed = workspace:GetAttribute("EveningHour")
	if type(fixed) == "number" then return fixed end
	local hour = ((workspace:GetServerTimeNow() / (DAY_MINUTES * 60)) * 24 + START_HOUR) % 24
	if false and DayNight.halloween() then
		-- the spooky day never reaches noon: late afternoon, a long orange dusk, into the night and
		-- back, smoothly, once a cycle (2026-10-23: from 16:00 rather than 17:12, so a new player more
		-- often meets the hub in warm light, and the night is a third of the cycle, not half)
		return 16.0 + 3.4 * (0.5 - 0.5 * math.cos(hour / 24 * math.pi * 2))
	end
	-- (2026-10-23, launch week) the night passes quickly: daylight (dawn to dusk) takes three quarters of
	-- each cycle and the night a quarter, so most players arrive to a lit hub (it was half and half)
	local cyc = ((workspace:GetServerTimeNow() / (DAY_MINUTES * 60)) + (START_HOUR - DAWN) / (DUSK - DAWN) * DAY_SHARE) % 1
	if cyc < DAY_SHARE then
		return DAWN + (DUSK - DAWN) * cyc / DAY_SHARE
	end
	return (DUSK + (24 - DUSK + DAWN) * (cyc - DAY_SHARE) / (1 - DAY_SHARE)) % 24
end

-- 0 in full day, 1 in full night, easing over an hour and a half either side
function DayNight.nightness(hour: number): number
	local function ramp(x: number, a: number, b: number): number
		local t = math.clamp((x - a) / (b - a), 0, 1)
		return t * t * (3 - 2 * t)
	end
	if hour < 12 then
		return 1 - ramp(hour, DAWN - 0.75, DAWN + 0.75)
	end
	return ramp(hour, DUSK - 0.75, DUSK + 0.75)
end

-- the keys: { hour, values }. Colours are Color3s; `nil` fields take the place's own (base) value
local C = Color3.fromRGB
local KEYS = {
	{ h = 0, bright = 1.2, amb = C(84, 90, 118), out = C(98, 108, 142), exp = 0.42, top = C(0, 0, 0), tint = C(214, 226, 255), sat = -0.08, con = 0.04, haze = 1.3, dens = 0.3, atmo = C(54, 66, 104), decay = C(36, 44, 72), glare = 0, rays = 0, bloom = 0.5, thresh = 1.6 },
	{ h = 4.8, bright = 1.2, amb = C(84, 90, 118), out = C(98, 108, 142), exp = 0.42, top = C(0, 0, 0), tint = C(214, 226, 255), sat = -0.08, con = 0.04, haze = 1.3, dens = 0.3, atmo = C(54, 66, 104), decay = C(36, 44, 72), glare = 0, rays = 0, bloom = 0.5, thresh = 1.6 },
	{ h = 6.3, bright = 1.9, amb = C(122, 104, 112), out = C(170, 138, 132), exp = 0.26, top = C(120, 72, 48), tint = C(255, 228, 216), sat = 0.04, con = 0.04, haze = 1.6, dens = 0.3, atmo = C(232, 178, 158), decay = C(178, 112, 116), glare = 0.6, rays = 0.06, bloom = 0.5, thresh = 2.0 },
	{ h = 8.2, bright = 2.7, amb = C(118, 114, 106), out = C(150, 148, 138), exp = 0.14, top = C(36, 24, 10), tint = C(255, 248, 238), sat = 0.08, con = 0.05, haze = 0.9, dens = 0.24, atmo = C(226, 218, 204), decay = C(176, 164, 150), glare = 0.2, rays = 0.03, bloom = 0.42, thresh = 2.4 },
	{ h = 12, bright = 3.0, amb = C(118, 116, 108), out = C(150, 150, 142), exp = 0.12, top = C(0, 0, 0), tint = C(255, 253, 248), sat = 0.1, con = 0.05, haze = 0.6, dens = 0.22, atmo = C(226, 220, 206), decay = C(170, 165, 150), glare = 0, rays = 0.02, bloom = 0.4, thresh = 2.4 },
	{ h = 15.4, bright = 3.0, amb = C(120, 116, 106), out = C(152, 150, 138), exp = 0.12, top = C(20, 12, 0), tint = C(255, 250, 240), sat = 0.1, con = 0.05, haze = 0.7, dens = 0.22, atmo = C(228, 218, 200), decay = C(176, 162, 140), glare = 0.1, rays = 0.03, bloom = 0.4, thresh = 2.4 },
	{ h = 17.3, bright = 2.5, amb = C(132, 112, 96), out = C(176, 146, 116), exp = 0.18, top = C(150, 92, 40), tint = C(255, 234, 204), sat = 0.14, con = 0.06, haze = 1.2, dens = 0.26, atmo = C(240, 196, 150), decay = C(204, 136, 92), glare = 0.7, rays = 0.09, bloom = 0.5, thresh = 2.0 },
	{ h = 18.5, bright = 1.6, amb = C(108, 94, 112), out = C(132, 118, 150), exp = 0.32, top = C(90, 44, 40), tint = C(244, 224, 240), sat = 0.04, con = 0.05, haze = 1.6, dens = 0.3, atmo = C(176, 126, 142), decay = C(104, 66, 100), glare = 0.3, rays = 0.04, bloom = 0.55, thresh = 1.7 },
	{ h = 19.8, bright = 1.2, amb = C(84, 90, 118), out = C(98, 108, 142), exp = 0.42, top = C(0, 0, 0), tint = C(214, 226, 255), sat = -0.08, con = 0.04, haze = 1.3, dens = 0.3, atmo = C(54, 66, 104), decay = C(36, 44, 72), glare = 0, rays = 0, bloom = 0.5, thresh = 1.6 },
	{ h = 24, bright = 1.2, amb = C(84, 90, 118), out = C(98, 108, 142), exp = 0.42, top = C(0, 0, 0), tint = C(214, 226, 255), sat = -0.08, con = 0.04, haze = 1.3, dens = 0.3, atmo = C(54, 66, 104), decay = C(36, 44, 72), glare = 0, rays = 0, bloom = 0.5, thresh = 1.6 },
}
local function grade(hour: number, _base: any): any
	local a, b = KEYS[1], KEYS[#KEYS]
	for i = 1, #KEYS - 1 do
		if hour >= KEYS[i].h and hour <= KEYS[i + 1].h then a, b = KEYS[i], KEYS[i + 1]; break end
	end
	local t = math.clamp((hour - a.h) / math.max(0.001, b.h - a.h), 0, 1)
	t = t * t * (3 - 2 * t)
	local out = {}
	for key, v in pairs(a) do
		local w = (b :: any)[key]
		if typeof(v) == "Color3" then out[key] = (v :: Color3):Lerp(w, t) else out[key] = v + (w - v) * t end
	end
	return out
end

function DayNight.new()
	local self = setmetatable({}, DayNight)
	DayNight.current = self
	self.active = true
	self.base = {
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ExposureCompensation = Lighting.ExposureCompensation,
	}
	local rays0 = Lighting:FindFirstChildOfClass("SunRaysEffect")
	local bloom0 = Lighting:FindFirstChildOfClass("BloomEffect")
	self.base.rays = rays0 and rays0.Intensity
	self.base.bloom = bloom0 and bloom0.Intensity
	self.base.thresh = bloom0 and bloom0.Threshold
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		self.atmo = atmo
		self.base.atmoColor = atmo.Color
		self.base.atmoDecay = atmo.Decay
		self.base.atmoGlare = atmo.Glare
	end
	self.lamps = {}
	self.lampsOn = nil
	task.spawn(function()
		local lobby = workspace:WaitForChild("Lobby", 30)
		local folder = lobby and lobby:WaitForChild("NightLamps", 10)
		if not folder then return end
		task.wait(1)
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("Light") then
				table.insert(self.lamps, { light = d, brightness = d.Brightness })
			elseif d:IsA("BasePart") and (d.Name == "Neon" or d.Name == "Glass") then
				table.insert(self.lamps, { part = d, material = d.Material, color = d.Color })
			end
		end
		self.lampsOn = nil
	end)
	local acc = 1
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then return end
		acc = 0
		self:update()
	end)
	return self
end

function DayNight:setActive(on: boolean)
	self.active = on
	-- (the season's grade is the yard's: the runs and the workbench light themselves without it)
	if self.grade then self.grade.Enabled = on and DayNight.halloween() end
	if self.dayGrade then self.dayGrade.Enabled = on end
	if not on then
		-- (2026-10-24) the run lights its own road: the hub's hour (a golden tint, night exposure) stays behind
		local b = self.base
		Lighting.Brightness = b.Brightness
		Lighting.ExposureCompensation = b.ExposureCompensation
		Lighting.ColorShift_Top = Color3.new(0, 0, 0)
		local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
		if rays and b.rays then rays.Intensity = b.rays end
		local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
		if bloom and b.bloom then bloom.Intensity, bloom.Threshold = b.bloom, b.thresh end
	end
	if on then self:update() end
end

-- a light built after the lobby loaded (a yard's lamps as it grows): it follows the cycle from now on
function DayNight:addLamp(light: Light)
	table.insert(self.lamps, { light = light, brightness = light.Brightness })
	if self.lampsOn ~= nil then
		light.Enabled = self.lampsOn
		if self.lampsOn then light.Brightness = math.max(light.Brightness, 1.2) end
	else
		light.Enabled = false
	end
end

function DayNight:setLamps(on: boolean)
	if self.lampsOn == on then return end
	self.lampsOn = on
	for i, l in ipairs(self.lamps) do
		-- a little stagger, so they don't all snap on together
		task.delay(on and (i % 8) * 0.15 or 0, function()
			if self.lampsOn ~= on then return end
			if l.light then
				l.light.Enabled = on
				l.light.Brightness = on and math.max(l.brightness, 1.2) or l.brightness
			elseif l.part then
				l.part.Material = on and Enum.Material.Neon or Enum.Material.Glass
				l.part.Color = on and l.color or l.color:Lerp(Color3.fromRGB(60, 56, 52), 0.55)
			end
		end)
	end
end

function DayNight:update()
	if not self.active then return end
	self:apply(DayNight.clock())
end

-- the yard's look at a given hour; cutscenes use it to light a shot whatever the clock says
function DayNight:apply(hour: number)
	local n = DayNight.nightness(hour)
	local b = self.base
	Lighting.ClockTime = hour
	-- (2026-10-24) the light graded through the day: a cool blue night, a pink-gold dawn, a clean warm
	-- noon, a long golden hour, a violet dusk. Each key sets the sky haze, the ambient, the exposure,
	-- the sun's tint on the tops of things and a colour grade; between keys everything eases.
	local k = grade(hour, b)
	Lighting.Brightness = k.bright
	Lighting.Ambient = k.amb
	Lighting.OutdoorAmbient = k.out
	Lighting.ExposureCompensation = k.exp
	Lighting.ColorShift_Top = k.top
	if not self.dayGrade then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "DayGrade"
		cc.Parent = Lighting
		self.dayGrade = cc
	end
	local dg = self.dayGrade :: ColorCorrectionEffect
	dg.Enabled = self.active
	if self.grade then self.grade.Enabled = false end
	dg.TintColor = k.tint
	dg.Saturation = k.sat
	dg.Contrast = k.con
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then rays.Intensity = k.rays end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then bloom.Intensity = k.bloom; bloom.Threshold = k.thresh end
	local atmo = self.atmo
	local spooky = DayNight.halloween()
	if atmo and atmo.Parent then
		atmo.Haze = k.haze
		atmo.Density = k.dens
		if spooky and n > 0.01 then
			-- (the season only colours the night now: a plum dark instead of the blue one)
			atmo.Color = k.atmo:Lerp(Color3.fromRGB(72, 54, 108), n)
			atmo.Decay = k.decay:Lerp(Color3.fromRGB(38, 28, 66), n)
			atmo.Glare = k.glare
		else
			atmo.Color = k.atmo
			atmo.Decay = k.decay
			atmo.Glare = k.glare
		end
	end
	if spooky and n > 0.01 then
		-- a touch cooler and moodier; the night's ambient stays high enough that plots and signs read
		if not self.grade then
			local cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "SeasonGrade"
			cc.Parent = Lighting
			self.grade = cc
		end
		local cc = self.grade :: ColorCorrectionEffect
		cc.Enabled = self.active
		cc.Saturation = lerp(0, -0.12, n)
		cc.Contrast = 0.04 * n
		cc.TintColor = Color3.fromRGB(255, 236, 214):Lerp(Color3.fromRGB(226, 216, 255), n)
		Lighting.Ambient = Lighting.Ambient:Lerp(Color3.fromRGB(92, 78, 118), 0.4 * n)
		Lighting.OutdoorAmbient = Lighting.OutdoorAmbient:Lerp(Color3.fromRGB(118, 96, 146), 0.4 * n)
	elseif self.grade then
		self.grade.Enabled = false
	end
	-- (in the season the lamps and jack-o'-lanterns come on early, at dusk)
	self:setLamps(n > (if spooky then 0.15 else 0.35))
end

return DayNight
