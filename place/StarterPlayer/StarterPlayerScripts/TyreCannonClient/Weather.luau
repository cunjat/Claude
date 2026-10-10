--!strict
-- TYRE CANNON :: Weather
-- Each road has its own weather, riding along with the camera for the whole run.
-- Particles only, no lights, and every emitter follows the Particles setting.
--   backroad   drizzle slanting down, a wet grey haze, spray thrown up on every landing
--   dunes      sand streaming along the ground and a hot, glaring haze over the crests
--   highway    grit and paper scraps blowing across the lanes in a dusty afternoon haze

local Lighting = game:GetService("Lighting")

local Prefs = require(script.Parent.Prefs)

local Weather = {}
Weather.__index = Weather

local function density(): number
	return math.clamp(tonumber(Prefs.get("particles")) or 1, 0.2, 1)
end

local ParticleTex = require(script.Parent:WaitForChild("Icons")).Particle

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	-- soft smoke unless told otherwise, never Roblox's default star
	e.Texture = ParticleTex.smoke
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local function box(parent: Instance, name: string, size: Vector3): (Part, Attachment)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	local a = Instance.new("Attachment")
	a.Parent = p
	return p, a
end

function Weather.start(trackId: string, parent: Instance)
	local self = setmetatable({}, Weather)
	self.trackId = trackId
	self.rates = {}
	self.parts = {}
	local d = density()

	-- the sky's haze changes with the weather; it's put back when the run ends
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		self.atmo = atmo
		self.savedAtmo = { Density = atmo.Density, Haze = atmo.Haze, Glare = atmo.Glare, Color = atmo.Color, Decay = atmo.Decay }
	end

	if trackId == "backroad" then
		-- drizzle: a wide sheet above the camera, streaks stretched along their fall
		local sky, _ = box(parent, "Drizzle", Vector3.new(180, 1, 180))
		self.sky = sky
		local rain = emitter(sky, {
			Name = "Rain", Texture = ParticleTex.streak, Rate = 520 * d, Lifetime = NumberRange.new(0.7, 0.9), Speed = NumberRange.new(150, 190),
			EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(4, 4), Acceleration = Vector3.new(-30, 0, 0),
			Size = NumberSequence.new(0.45), Squash = NumberSequence.new(-3),
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.7) }),
			Color = ColorSequence.new(Color3.fromRGB(204, 214, 222)), LightInfluence = 0.6, Shape = Enum.ParticleEmitterShape.Box,
		})
		self.rates[rain] = 520
		if atmo then
			atmo.Density = atmo.Density + 0.05
			atmo.Haze = atmo.Haze + 0.6
			atmo.Color = atmo.Color:Lerp(Color3.fromRGB(170, 176, 182), 0.6)
			atmo.Glare = 0
		end
		self.splash = true
	elseif trackId == "dunes" then
		local ground, _ = box(parent, "SandStream", Vector3.new(40, 8, 240))
		self.ground = ground
		local sand = emitter(ground, {
			Name = "Sand", Rate = 160 * d, Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(40, 80),
			EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(10, 25),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.78), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromRGB(226, 194, 136)), LightInfluence = 1, Shape = Enum.ParticleEmitterShape.Box,
			RotSpeed = NumberRange.new(-40, 40),
		})
		self.rates[sand] = 160
		local grit = emitter(ground, {
			Name = "Grit", Texture = ParticleTex.dot, Rate = 220 * d, Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(90, 140),
			EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(4, 8),
			Size = NumberSequence.new(0.12), Squash = NumberSequence.new(-1.6), Orientation = Enum.ParticleOrientation.VelocityParallel,
			Transparency = NumberSequence.new(0.45), Color = ColorSequence.new(Color3.fromRGB(236, 212, 164)),
			LightInfluence = 1, Shape = Enum.ParticleEmitterShape.Box,
		})
		self.rates[grit] = 220
		if atmo then
			atmo.Haze = atmo.Haze + 0.9
			atmo.Glare = math.max(atmo.Glare, 0.5)
			atmo.Color = atmo.Color:Lerp(Color3.fromRGB(236, 206, 158), 0.6)
		end
	elseif trackId == "highway" then
		local ground, _ = box(parent, "Litter", Vector3.new(40, 6, 240))
		self.ground = ground
		local dust = emitter(ground, {
			Name = "Dust", Rate = 60 * d, Lifetime = NumberRange.new(1.4, 2.2), Speed = NumberRange.new(20, 40),
			EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(20, 30),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.84), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromRGB(176, 168, 150)), LightInfluence = 1, Shape = Enum.ParticleEmitterShape.Box,
		})
		self.rates[dust] = 60
		local scraps = emitter(ground, {
			Name = "Scraps", Texture = ParticleTex.dot, Rate = 16 * d, Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(30, 60),
			EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(15, 40), Acceleration = Vector3.new(0, -6, 0),
			Size = NumberSequence.new(0.7), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300),
			Transparency = NumberSequence.new(0.1), Color = ColorSequence.new(Color3.fromRGB(232, 228, 214), Color3.fromRGB(170, 160, 140)),
			LightInfluence = 1, Shape = Enum.ParticleEmitterShape.Box,
		})
		self.rates[scraps] = 16
		if atmo then
			atmo.Haze = atmo.Haze + 0.5
			atmo.Color = atmo.Color:Lerp(Color3.fromRGB(214, 196, 168), 0.5)
		end
	end
	return self
end

-- follows the tyre: the rain sheet overhead, the ground streams blowing across the road
function Weather:update(pos: Vector3, camPos: Vector3)
	if self.sky then
		-- over the camera, a little ahead, so the streaks fall past the lens
		self.sky.CFrame = CFrame.new(camPos.X + 50, camPos.Y + 55, camPos.Z * 0.5 + pos.Z * 0.5)
	end
	if self.ground then
		-- blows in from the left of the road, low over the ground
		self.ground.CFrame = CFrame.lookAt(Vector3.new(pos.X + 70, pos.Y - 2, pos.Z - 70), Vector3.new(pos.X + 70, pos.Y - 2, pos.Z + 10))
	end
end

-- spray off the road on a hard landing (the backroad only)
function Weather:landed(at: Vector3, impact: number)
	if not self.splash or impact < 60 then return end
	local parent = self.sky and self.sky.Parent
	if not parent then return end
	local p, _ = box(parent, "Splash", Vector3.new(10, 1, 10))
	p.CFrame = CFrame.new(at)
	local e = emitter(p, {
		Texture = ParticleTex.dot, Rate = 0, Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(30, 70), SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -160, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(180, 196, 206)), LightInfluence = 1, Shape = Enum.ParticleEmitterShape.Box,
	})
	e:Emit(math.floor(math.clamp(impact / 6, 10, 60) * density()))
	task.delay(1, function() p:Destroy() end)
end

function Weather:stop()
	local atmo, saved = self.atmo, self.savedAtmo
	if atmo and saved and atmo.Parent then
		for k, v in pairs(saved) do (atmo :: any)[k] = v end
	end
	if self.sky then self.sky:Destroy() end
	if self.ground then self.ground:Destroy() end
end

return Weather
