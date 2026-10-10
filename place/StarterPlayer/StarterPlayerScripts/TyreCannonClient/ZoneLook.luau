--!strict
-- TYRE CANNON :: ZoneLook
-- How each zone looks beyond its ground: the hour and the angle of the sun, the grade, the haze,
-- a soft bloom, and the air itself (warm dust hanging in the Backroad's low sun, grit over the
-- Highway, sand blowing low across the Dunes). WorldView calls :enter(zoneId, instant) as the road
-- crosses into a zone and everything eases across; :frame() keeps the air round the camera;
-- :destroy() puts the yard's lighting back exactly as it was. No light rays, no glowing particles.
--   ZoneLook.new() ; :enter(id, instant) ; :frame(dt) ; :destroy()

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local ZoneLook = {}
ZoneLook.__index = ZoneLook

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function ns(list: { { number } }): NumberSequence
	local k = {}
	for _, p in ipairs(list) do table.insert(k, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(k)
end

-- per zone: Lighting, the grade, the bloom, the atmosphere, and the air
ZoneLook.Looks = {
	-- Punjab Backroad: late afternoon, a warm low sun throwing long shadows over dirt and mustard
	backroad = {
		light = { ClockTime = 16.3, GeographicLatitude = 24, Brightness = 2.6, ExposureCompensation = 0.12,
			Ambient = rgb(120, 104, 86), OutdoorAmbient = rgb(150, 132, 108), ColorShift_Top = rgb(255, 226, 180), ColorShift_Bottom = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0.6, EnvironmentSpecularScale = 0.6 },
		grade = { TintColor = rgb(255, 245, 228), Saturation = 0.14, Contrast = 0.1, Brightness = 0 },
		bloom = { Intensity = 0.3, Size = 24, Threshold = 1.8 },
		atmo = { Density = 0.3, Offset = 0.08, Color = rgb(222, 220, 208), Decay = rgb(188, 168, 136), Glare = 0.35, Haze = 1.1 },
		air = {
			{ kind = "motes", color = rgb(255, 238, 200), rate = 70, size = 0.28, drift = Vector3.new(-1.5, 0.6, 0.8) },
			{ kind = "fluff", color = rgb(250, 246, 236), rate = 10, size = 0.55, drift = Vector3.new(-3, 0.4, 1.4) },
		},
	},
	-- Grand Trunk Highway: midday heat, a bright hazy sky, the grey of concrete and diesel
	highway = {
		light = { ClockTime = 13.2, GeographicLatitude = 28, Brightness = 3.1, ExposureCompensation = 0.04,
			Ambient = rgb(124, 126, 132), OutdoorAmbient = rgb(150, 152, 158), ColorShift_Top = rgb(255, 250, 238), ColorShift_Bottom = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0.7, EnvironmentSpecularScale = 0.8 },
		grade = { TintColor = rgb(248, 250, 255), Saturation = -0.04, Contrast = 0.14, Brightness = 0 },
		bloom = { Intensity = 0.4, Size = 26, Threshold = 1.6 },
		atmo = { Density = 0.27, Offset = 0.1, Color = rgb(214, 212, 204), Decay = rgb(172, 160, 146), Glare = 0.3, Haze = 1.0 },
		air = {
			{ kind = "motes", color = rgb(210, 208, 204), rate = 55, size = 0.22, drift = Vector3.new(-2, 0.3, 2) },
		},
	},
	-- Thar Dunes: evening, an orange sun low over the crests, sand lifting off them in the wind
	dunes = {
		light = { ClockTime = 17.3, GeographicLatitude = 26, Brightness = 2.8, ExposureCompensation = 0.1,
			Ambient = rgb(140, 112, 84), OutdoorAmbient = rgb(166, 130, 96), ColorShift_Top = rgb(255, 206, 150), ColorShift_Bottom = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0.55, EnvironmentSpecularScale = 0.5 },
		grade = { TintColor = rgb(255, 236, 212), Saturation = 0.18, Contrast = 0.16, Brightness = 0 },
		bloom = { Intensity = 0.45, Size = 26, Threshold = 1.5 },
		atmo = { Density = 0.3, Offset = 0.12, Color = rgb(236, 210, 168), Decay = rgb(204, 148, 96), Glare = 0.45, Haze = 1.4 },
		air = {
			{ kind = "sand", color = rgb(236, 204, 150), rate = 140, size = 0.9, drift = Vector3.new(-26, 0, 34) },
			{ kind = "motes", color = rgb(250, 222, 176), rate = 45, size = 0.25, drift = Vector3.new(-4, 0.4, 6) },
		},
	},
}

local LIGHT_KEYS = { "ClockTime", "GeographicLatitude", "Brightness", "ExposureCompensation", "Ambient", "OutdoorAmbient",
	"ColorShift_Top", "ColorShift_Bottom", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" }
local ATMO_KEYS = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" }
local BLOOM_KEYS = { "Intensity", "Size", "Threshold" }

-- the air: emitters spread through a box that rides along in front of the camera
local function airEmitter(parent: Instance, a: any): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Brightness = 1
	e.Color = ColorSequence.new(a.color)
	e.Rate = a.rate
	e.Speed = NumberRange.new(0, 0.5)
	e.Acceleration = a.drift * 0.2
	e.Drag = 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-30, 30)
	if a.kind == "sand" then
		-- low streaks blown across the road, stretched along the wind
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(a.drift.Magnitude * 0.8, a.drift.Magnitude * 1.2)
		e.EmissionDirection = Enum.NormalId.Front
		e.SpreadAngle = Vector2.new(8, 4)
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Squash = ns({ { 0, -2.2 }, { 1, -2.2 } })
		e.Size = ns({ { 0, 0 }, { 0.2, a.size }, { 0.8, a.size }, { 1, 0 } })
		e.Transparency = ns({ { 0, 1 }, { 0.2, 0.55 }, { 0.8, 0.6 }, { 1, 1 } })
		e.RotSpeed = NumberRange.new(0, 0)
		e.Rotation = NumberRange.new(0, 0)
	elseif a.kind == "fluff" then
		-- seed fluff drifting off the fields
		e.Lifetime = NumberRange.new(5, 8)
		e.Size = ns({ { 0, 0 }, { 0.15, a.size }, { 0.85, a.size * 0.9 }, { 1, 0 } })
		e.Transparency = ns({ { 0, 1 }, { 0.15, 0.25 }, { 0.85, 0.35 }, { 1, 1 } })
	else
		-- dust hanging in the light: tiny, slow, fading in and out
		e.Lifetime = NumberRange.new(4, 7)
		e.Size = ns({ { 0, 0 }, { 0.2, a.size }, { 0.8, a.size }, { 1, 0 } })
		e.Transparency = ns({ { 0, 1 }, { 0.25, 0.35 }, { 0.75, 0.45 }, { 1, 1 } })
	end
	e.Parent = parent
	return e
end

function ZoneLook.new()
	local self = setmetatable({}, ZoneLook)
	-- everything this touches, as it was, to put back at the end
	self.saved = {}
	for _, k in ipairs(LIGHT_KEYS) do self.saved[k] = (Lighting :: any)[k] end
	self.atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if self.atmo then
		self.savedAtmo = {}
		for _, k in ipairs(ATMO_KEYS) do self.savedAtmo[k] = (self.atmo :: any)[k] end
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		self.savedBloom = {}
		for _, k in ipairs(BLOOM_KEYS) do self.savedBloom[k] = (bloom :: any)[k] end
	else
		bloom = Instance.new("BloomEffect")
		bloom.Name = "ZoneBloom"
		bloom.Intensity = 0
		bloom.Parent = Lighting
		self.ownBloom = true
	end
	self.bloom = bloom
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "ZoneGrade"
	grade.Parent = Lighting
	self.grade = grade
	-- the air's boxes: one round the camera, one low and flat for blowing sand
	local function box(name: string, size: Vector3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Size = size
		p.Parent = workspace
		return p
	end
	self.airBox = box("ZoneAir", Vector3.new(150, 46, 150))
	self.lowBox = box("ZoneAirLow", Vector3.new(170, 5, 170))
	self.emitters = {}
	return self
end

function ZoneLook:enter(id: string, instant: boolean?)
	local look = ZoneLook.Looks[id] or ZoneLook.Looks.backroad
	if self.zone == id then return end
	self.zone = id
	local ti = TweenInfo.new(instant and 0 or 2.4, Enum.EasingStyle.Sine)
	for _, tw in ipairs(self.tweens or {}) do tw:Cancel() end
	self.tweens = {}
	local function go(o: Instance, goal: { [string]: any })
		local tw = TweenService:Create(o, ti, goal)
		tw:Play()
		table.insert(self.tweens, tw)
	end
	go(Lighting, look.light)
	go(self.grade, look.grade)
	go(self.bloom, look.bloom)
	if self.atmo then go(self.atmo, look.atmo) end
	-- the old air thins out while the new comes in
	for _, e in ipairs(self.emitters) do
		e.Enabled = false
		task.delay(8, function() e:Destroy() end)
	end
	self.emitters = {}
	for _, a in ipairs(look.air) do
		local e = airEmitter(a.kind == "sand" and self.lowBox or self.airBox, a)
		if a.kind == "sand" then
			-- the wind blows from the box's front face
			e.EmissionDirection = Enum.NormalId.Front
		end
		table.insert(self.emitters, e)
	end
	self.wind = nil
	for _, a in ipairs(look.air) do
		if a.kind == "sand" then self.wind = a.drift end
	end
end

-- the air follows the camera, a little ahead so it's where you're looking
function ZoneLook:frame(_dt: number, groundY: number?)
	local cam = workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 1e-3 then flatLook.Unit else Vector3.xAxis
	local at = cam.CFrame.Position + flatLook * 55
	self.airBox.CFrame = CFrame.new(at)
	local gy = groundY or (cam.CFrame.Position.Y - 12)
	local wind = self.wind or Vector3.new(-1, 0, 1)
	local w = Vector3.new(wind.X, 0, wind.Z).Unit
	-- the low box faces down the wind so its emitters blow that way, skimming the ground
	self.lowBox.CFrame = CFrame.lookAt(Vector3.new(at.X, gy + 2.5, at.Z), Vector3.new(at.X, gy + 2.5, at.Z) + w)
end

function ZoneLook:destroy()
	for _, tw in ipairs(self.tweens or {}) do tw:Cancel() end
	for k, v in pairs(self.saved) do (Lighting :: any)[k] = v end
	if self.atmo and self.savedAtmo and self.atmo.Parent then
		for k, v in pairs(self.savedAtmo) do (self.atmo :: any)[k] = v end
	end
	if self.ownBloom then
		self.bloom:Destroy()
	elseif self.savedBloom and self.bloom.Parent then
		for k, v in pairs(self.savedBloom) do (self.bloom :: any)[k] = v end
	end
	self.grade:Destroy()
	self.airBox:Destroy()
	self.lowBox:Destroy()
end

return ZoneLook
