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
local NIGHT_AMBIENT = Color3.fromRGB(88, 92, 112)
local NIGHT_OUTDOOR = Color3.fromRGB(104, 110, 138)

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function DayNight.clock(): number
	return ((workspace:GetServerTimeNow() / (DAY_MINUTES * 60)) * 24 + START_HOUR) % 24
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
	Lighting.Brightness = lerp(b.Brightness, 1.1, n)
	Lighting.Ambient = b.Ambient:Lerp(NIGHT_AMBIENT, n)
	Lighting.OutdoorAmbient = b.OutdoorAmbient:Lerp(NIGHT_OUTDOOR, n)
	Lighting.ExposureCompensation = lerp(b.ExposureCompensation, 0.45, n)
	local atmo = self.atmo
	if atmo and atmo.Parent then
		atmo.Color = b.atmoColor:Lerp(Color3.fromRGB(58, 70, 104), n)
		atmo.Decay = b.atmoDecay:Lerp(Color3.fromRGB(40, 46, 70), n)
		atmo.Glare = lerp(b.atmoGlare, 0, n)
	end
	self:setLamps(n > 0.35)
end

return DayNight
