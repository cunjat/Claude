--!strict
-- TYRE CANNON :: LaunchShow
-- The launch, watched on your own plot: you pull the lever, the flywheel
-- winds up, the tyre spins in its cradle, the operator shoves it off with the
-- pole and it rolls up the ramp. Everything is worked out in the plot's own
-- frame and multiplied by its BaseCFrame, so it works on any of the eight
-- plots whichever way they face.

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))
local Assets = Root:WaitForChild("Assets")
local PackFX = require(script.Parent:WaitForChild("PackFX"))
local DUST = Color3.fromRGB(198, 172, 134)

local LaunchShow = {}
LaunchShow.__index = LaunchShow

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function sound(id: string, vol: number, pitch: number, looped: boolean?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol
	s.PlaybackSpeed = pitch
	s.Looped = looped == true
	s.Parent = SoundService
	s:Play()
	if not looped then Debris:AddItem(s, 6) end
	return s
end

local FLY_LOCAL = Vector3.new(3.6, 6.2, 0)
local TYRE_LOCAL = Vector3.new(19.5, 6.2, 0)
local TYRE_RADIUS = 3.9
local GROUND_Y = 2

--==============================================================
function LaunchShow.new(skinId: string?, plot: Instance?)
	if not plot then return nil end
	local base = plot:GetAttribute("BaseCFrame")
	if not base then return nil end

	local self = setmetatable({}, LaunchShow)
	self.plot = plot
	self.base = base
	self.rig = plot:FindFirstChild("LauncherRig")
	self.tyre = plot:FindFirstChild("LaunchTyre")
	self.ramp = plot:FindFirstChild("Ramp")
	if not (self.rig and self.tyre and self.ramp) then return nil end

	self.fly = self.rig:FindFirstChild("Flywheel")
	self.spokes = self.rig:FindFirstChild("Spokes")
	self.exhaust = self.rig:FindFirstChild("Exhaust")
	self.flyLocal = self.fly and base:ToObjectSpace(self.fly.CFrame)
	self.spokeLocal = {}
	if self.spokes then
		for _, s in ipairs(self.spokes:GetChildren()) do
			if s:IsA("BasePart") then self.spokeLocal[s] = base:ToObjectSpace(s.CFrame) end
		end
	end

	self.wheel = self.tyre:FindFirstChild("Wheel")
	if not self.wheel or not self.wheel.PrimaryPart then return nil end
	self.skin = Config.SkinsById[skinId or "stock"] or Config.SkinsById.stock

	-- the operator: swing both shoulders to shove the pole
	self.op = plot:FindFirstChild("Operator")
	self.shoulders = {}
	if self.op then
		local torso = self.op:FindFirstChild("Torso")
		for _, name in ipairs({ "Right Shoulder", "Left Shoulder" }) do
			local motor = torso and torso:FindFirstChild(name)
			if motor and motor:IsA("Motor6D") then
				table.insert(self.shoulders, { motor = motor, rest = motor.C0, sign = (name == "Right Shoulder") and 1 or -1 })
			end
		end
	end

	-- the lever
	local lc = plot:FindFirstChild("LaunchControl")
	local lever = lc and lc:FindFirstChild("Lever")
	self.lever = lever
	self.leverGrip = lever and lever:FindFirstChild("Lever")
	if self.leverGrip then
		self.leverRest = self.leverGrip.CFrame
		local pivot = lever:GetPivot()
		self.leverHinge = pivot * CFrame.new(lever:GetAttribute("Hinge") or Vector3.zero)
		self.leverAxis = pivot:VectorToWorldSpace(lever:GetAttribute("Axis") or Vector3.new(0, 0, 1))
		self.leverPull = math.rad(lever:GetAttribute("PullDegrees") or -60)
	end

	self.rampX0 = self.ramp:GetAttribute("X0") or 30
	self.rampLen = self.ramp:GetAttribute("Len") or 20
	self.rampH = self.ramp:GetAttribute("Height") or 5.54
	self.exitDeg = self.ramp:GetAttribute("ExitDeg") or 29

	self.spin, self.spinAngle, self.quality = 0, 0, 0.5
	self.emitters = {}
	self:buildEffects()

	self.camera = workspace.CurrentCamera
	self.savedCam = self.camera.CameraType
	self.savedFov = self.camera.FieldOfView
	self.conn = RunService.RenderStepped:Connect(function(dt) self:step(dt) end)
	return self
end

--==============================================================
function LaunchShow:buildEffects()
	local core = self.wheel.PrimaryPart
	local att = Instance.new("Attachment")
	att.Name = "ShowFX"
	att.Parent = core
	self.fxAtt = att

	local function emitter(name: string, cfg)
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.Texture = cfg.tex or "rbxasset://textures/particles/smoke_main.dds"
		e.Rate = 0
		e.Lifetime = cfg.life
		e.Speed = cfg.speed
		e.SpreadAngle = cfg.spread
		e.Size = cfg.size
		e.Transparency = cfg.trans
		e.Color = cfg.color
		e.LightEmission = cfg.glow or 0
		e.Acceleration = cfg.accel or Vector3.zero
		e.Parent = att
		return e
	end
	self.grit = emitter("Grit", {
		tex = "rbxassetid://84291297587243",
		life = NumberRange.new(0.25, 0.6), speed = NumberRange.new(6, 20), spread = Vector2.new(20, 8),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) }),
		trans = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		color = ColorSequence.new(Color3.fromRGB(198, 168, 124)), accel = Vector3.new(0, -22, 0),
	})
	self.spark = emitter("Spark", {
		tex = "rbxassetid://84291297587243",
		life = NumberRange.new(0.18, 0.4), speed = NumberRange.new(10, 26), spread = Vector2.new(35, 35),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) }),
		trans = NumberSequence.new(0.1), color = ColorSequence.new(Color3.fromRGB(255, 208, 120)),
		glow = 0.35, accel = Vector3.new(0, -34, 0),
	})
	-- a good wind-up kicks dust off the rollers (it used to be a green glow)
	self.halo = emitter("Halo", {
		life = NumberRange.new(0.5, 0.9), speed = NumberRange.new(3, 9), spread = Vector2.new(70, 70),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.4) }),
		trans = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		color = ColorSequence.new(DUST), accel = Vector3.new(0, 3, 0),
	})

	local light = Instance.new("PointLight")
	light.Range = 16
	light.Brightness = 0
	light.Color = self.skin.glow or Color3.fromRGB(255, 190, 110)
	light.Enabled = false
	light.Parent = core
	self.light = light

	if self.exhaust then
		local sp = self.exhaust:FindFirstChild("SmokePoint")
		if sp then
			local smoke = Instance.new("ParticleEmitter")
			smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
			smoke.Rate = 3
			smoke.Lifetime = NumberRange.new(0.9, 1.7)
			smoke.Speed = NumberRange.new(3, 7)
			smoke.SpreadAngle = Vector2.new(12, 12)
			smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 4.5) })
			smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
			smoke.Color = ColorSequence.new(Color3.fromRGB(58, 56, 54))
			smoke.Acceleration = Vector3.new(0.6, 4, 0)
			smoke.Parent = sp
			self.smoke = smoke
		end
	end
	self.engineLoop = sound("rbxassetid://9112854440", 0.22, 0.55, true)
end

function LaunchShow:applyCharms(charmIds)
	for _, e in ipairs(self.emitters) do e:Destroy() end
	self.emitters = {}
	for _, id in ipairs(charmIds or {}) do
		local c = Config.CharmsById[id]
		if c then
			local e = Instance.new("ParticleEmitter")
			e.Texture = "rbxassetid://84291297587243"
			e.Rate = 0
			e.Lifetime = NumberRange.new(0.4, 0.85)
			e.Speed = NumberRange.new(5, 14)
			e.SpreadAngle = Vector2.new(150, 150)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			e.Color = ColorSequence.new(c.fx)
			e.LightEmission = 0.3
			e.Parent = self.fxAtt
			table.insert(self.emitters, e)
		end
	end
end

--==============================================================
-- the lever
--==============================================================
function LaunchShow:setLever(t: number)
	if not (self.leverGrip and self.leverRest) then return end
	local rot = CFrame.fromAxisAngle(self.leverAxis, self.leverPull * math.clamp(t, 0, 1))
	local h = self.leverHinge
	self.leverGrip.CFrame = CFrame.new(h.Position) * rot * CFrame.new(-h.Position) * self.leverRest
end

function LaunchShow:pullLever()
	if not self.leverGrip then return end
	sound("rbxassetid://9118823101", 0.5, 0.45)
	local t = 0
	while t < 0.28 do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		local u = math.clamp(t / 0.28, 0, 1)
		self:setLever(1 - (1 - u) ^ 3)
		self:frame("lever", dt)
	end
	self:setLever(1)
end

--==============================================================
function LaunchShow:step(dt: number)
	local spin = self.spin
	self.spinAngle += spin * 40 * dt
	local base = self.base

	-- spin on the flywheel's own axle, not the world's
	if self.fly and self.flyLocal then
		self.fly.CFrame = base * (self.flyLocal * CFrame.Angles(self.spinAngle, 0, 0))
	end
	local axle = self.flyLocal and self.flyLocal.RightVector or Vector3.new(0, 0, 1)
	for s, Lc in pairs(self.spokeLocal) do
		s.CFrame = base * (CFrame.new(FLY_LOCAL) * CFrame.fromAxisAngle(axle, self.spinAngle) * CFrame.new(-FLY_LOCAL) * Lc)
	end

	if not self.released then
		self.wheel:PivotTo(base * CFrame.new(TYRE_LOCAL) * CFrame.Angles(0, 0, -self.spinAngle * 0.72))
	end

	local q = self.quality
	self.grit.Rate = spin * 70
	self.spark.Rate = (spin > 0.55) and (spin - 0.55) * 200 * (0.4 + q) or 0
	self.halo.Rate = (q > 0.6) and (q - 0.6) * 300 * spin or 0
	self.light.Brightness = spin * (0.6 + q * 2.2)
	for _, e in ipairs(self.emitters) do e.Rate = spin * 45 end
	if self.smoke then self.smoke.Rate = 3 + spin * 34 end
	if self.engineLoop then
		self.engineLoop.Volume = 0.18 + spin * 0.5
		self.engineLoop.PlaybackSpeed = 0.5 + spin * 1.5
	end
end

function LaunchShow:setSpin(v: number, quality: number?)
	self.spin = math.clamp(v, 0, 1.25)
	if quality then self.quality = math.clamp(quality, 0, 1) end
end

function LaunchShow:setQuality(q: number)
	self.quality = math.clamp(q, 0, 1)
end

-- 0 = drawn back, 1 = shoved through
function LaunchShow:setSwing(t: number)
	local phi = lerp(-0.55, 1.15, math.clamp(t, 0, 1))
	for _, s in ipairs(self.shoulders) do
		s.motor.C0 = s.rest * CFrame.Angles(0, 0, phi * s.sign)
	end
end

function LaunchShow:burst(_color: Color3, n: number)
	self.halo:Emit(math.floor(n * 0.5))
	self.spark:Emit(math.floor(n * 0.6))
end

-- a flawless launch: the operator throws his arms up and the stars come out
function LaunchShow:celebrate()
	if not self.op then return end
	local head = self.op:FindFirstChild("Head")
	-- no star burst over his head any more; the cheer animation carries it
	local vfx = nil
	if head and vfx then
		local c = vfx:Clone()
		c.Anchored = true
		c.CanCollide = false
		c.Transparency = 1
		c.CFrame = head.CFrame * CFrame.new(0, 1.5, 0)
		c.Parent = workspace
		for _, e in ipairs(c:GetDescendants()) do
			if e:IsA("ParticleEmitter") then e:Emit(tonumber(e:GetAttribute("EmitCount")) or 10) end
		end
		Debris:AddItem(c, 3)
	end
	local hum = self.op:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	local id = Config.Animations.victory
	if animator and type(id) == "string" and id ~= "" then
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(function() return animator:LoadAnimation(a) end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action2
			track.Looped = false
			track:Play(0.15)
		end
	end
end

function LaunchShow:rampYAt(x: number): number
	local t = math.clamp((x - self.rampX0) / self.rampLen, 0, 1)
	return self.rampH * t * t
end

--==============================================================
function LaunchShow:takeCamera()
	self.camera.CameraType = Enum.CameraType.Scriptable
	self.camOwned = true
end

function LaunchShow:frame(stage: string, dt: number)
	if not self.camOwned then return end
	local base = self.base
	local tyreLocal = self.rollLocal or TYRE_LOCAL
	local target, look
	if stage == "lever" then
		target = Vector3.new(2, 9, 23)
		look = Vector3.new(8, 5, 6)
	elseif stage == "spin" then
		local t = os.clock() * 0.3
		local c = (FLY_LOCAL + TYRE_LOCAL) / 2
		target = c + Vector3.new(-2 + math.sin(t) * 4, 9, 22)
		look = c + Vector3.new(1, -0.5, 0)
	elseif stage == "push" then
		target = tyreLocal + Vector3.new(-7, 6, 17)
		look = tyreLocal + Vector3.new(-2, 0, -4)
	elseif stage == "roll" then
		-- low beside the ramp, so the tyre climbs toward the lens and past it
		target = Vector3.new(self.rampX0 + self.rampLen * 0.55, GROUND_Y + 2.6, 14)
		look = tyreLocal + Vector3.new(2, 1, 0)
	else
		-- off the lip: fall in behind and ride along
		target = tyreLocal + Vector3.new(-16, 5, 11)
		look = tyreLocal + Vector3.new(10, 1, 0)
	end
	local desired = CFrame.lookAt((base * CFrame.new(target)).Position, (base * CFrame.new(look)).Position)
	local rate = (stage == "roll" and 7) or (stage == "air" and 9) or 5
	self.camCF = self.camCF and self.camCF:Lerp(desired, math.min(1, dt * rate)) or desired
	self.camera.CFrame = self.camCF
	local fov = (stage == "roll" and 62) or (stage == "air" and 80) or (stage == "push" and 58) or 64
	self.camera.FieldOfView = lerp(self.camera.FieldOfView, fov, math.min(1, dt * 4))
end

--==============================================================
-- roll-off: out of the cradle, across the deck, up the ramp, off the lip
--==============================================================
function LaunchShow:release(power: number, quality: number)
	self.released = true
	local base = self.base
	local startX = TYRE_LOCAL.X
	local endX = self.rampX0 + self.rampLen
	local restY = GROUND_Y + TYRE_RADIUS
	local z = TYRE_LOCAL.Z
	local duration = lerp(1.9, 0.8, math.clamp(quality, 0, 1))
	local wobble = (1 - math.clamp(quality, 0, 1)) * 0.5
	sound("rbxassetid://9118823101", 1, 0.55 + quality * 0.5)
	-- the shove lands: a beat's hold and a puff of dust off the cradle
	local from = base * CFrame.new(TYRE_LOCAL - Vector3.new(0, TYRE_RADIUS - 0.4, 0))
	PackFX.burst("dustPuff", from, math.floor(10 + quality * 12), DUST, 1.1)
	local hold = 0
	while hold < 0.08 do hold += RunService.RenderStepped:Wait() end

	local t, angle = 0, 0
	while t < duration do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		local u = math.clamp(t / duration, 0, 1)
		local eased = u * u * (3 - 2 * u)
		local x = lerp(startX, endX, eased)
		local y = restY + self:rampYAt(x) + math.sin(t * 22) * wobble
		angle -= ((endX - startX) / duration / TYRE_RADIUS) * dt
		self.rollLocal = Vector3.new(x, y, z)
		self.wheel:PivotTo(base * CFrame.new(self.rollLocal) * CFrame.Angles(0, 0, angle))
		self.grit.Rate = 160 * (0.4 + quality)
		self.spark.Rate = 90 * quality
		for _, e in ipairs(self.emitters) do e.Rate = 70 end
		self:frame("roll", dt)
	end

	-- off the lip in a ring of dust
	PackFX.burst("dustRing", base * CFrame.new(endX, GROUND_Y + self.rampH, z), math.floor(8 + quality * 10), DUST, 0.9)
	local exit = math.rad(self.exitDeg)
	local speed = 26 + power * 0.05
	local vx, vy = math.cos(exit) * speed, math.sin(exit) * speed
	local px, py = endX, restY + self.rampH
	local airT = 0
	while airT < 0.5 do
		local dt = RunService.RenderStepped:Wait()
		airT += dt
		px += vx * dt
		py += vy * dt
		vy -= 40 * dt
		angle -= 7 * dt
		self.rollLocal = Vector3.new(px, py, z)
		self.wheel:PivotTo(base * CFrame.new(self.rollLocal) * CFrame.Angles(0, 0, angle))
		self:frame("air", dt)
	end
end

--==============================================================
function LaunchShow:reset()
	self.released = false
	self.rollLocal = nil
	self.spin, self.spinAngle = 0, 0
	if self.wheel and self.wheel.Parent then
		self.wheel:PivotTo(self.base * CFrame.new(TYRE_LOCAL))
	end
	for s, Lc in pairs(self.spokeLocal) do s.CFrame = self.base * Lc end
	if self.fly and self.flyLocal then self.fly.CFrame = self.base * self.flyLocal end
	for _, s in ipairs(self.shoulders) do s.motor.C0 = s.rest end
	self:setLever(0)
end

function LaunchShow:destroy()
	if self.conn then self.conn:Disconnect() end
	self:reset()
	if self.engineLoop then self.engineLoop:Destroy() end
	for _, e in ipairs(self.emitters) do e:Destroy() end
	if self.fxAtt then self.fxAtt:Destroy() end
	if self.light then self.light:Destroy() end
	if self.smoke then self.smoke:Destroy() end
	if self.camOwned then
		self.camera.CameraType = self.savedCam
		self.camera.FieldOfView = self.savedFov
	end
end

return LaunchShow
