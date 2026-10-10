--!strict
-- TYRE CANNON :: MuzzleFX
-- A cannon's shot, out of the muzzle: a short tight jet of flame down the bore line, flame tongues
-- licking out round the lip, a cone of smoke thrown forward, a ring of smoke square to the bore and
-- a cloud that hangs and rolls outward after. Built once (so nothing loads at the moment it fires)
-- from the packs' 4x4 sheets. Flame, not light: no glows.
--   MuzzleFX.new(muzzle, dir) -> fx ; fx:fire(q 0..1) ; fx.emitters (for TimeScale) ; fx:destroy(after)

local PackFX = require(script.Parent:WaitForChild("PackFX"))

local MuzzleFX = {}
MuzzleFX.__index = MuzzleFX

local SMOKE = Color3.fromRGB(226, 222, 214)

local function ns(list: { { number } }): NumberSequence
	local k = {}
	for _, p in ipairs(list) do table.insert(k, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(k)
end

local function cs(list: { { any } }): ColorSequence
	local k = {}
	for _, p in ipairs(list) do table.insert(k, ColorSequenceKeypoint.new(p[1], p[2])) end
	return ColorSequence.new(k)
end

MuzzleFX.Flame = cs({ { 0, Color3.fromRGB(255, 240, 200) }, { 0.35, Color3.fromRGB(255, 168, 72) }, { 1, Color3.fromRGB(176, 72, 32) } })
MuzzleFX.Smoke = SMOKE

-- a switched-off emitter from one of the packs' 4x4 sheets
function MuzzleFX.emitter(parent: Instance, sheet: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = sheet
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	e.Rotation = NumberRange.new(-180, 180)
	e.LightInfluence = 1
	e.Rate = 0
	e.Enabled = false
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

-- an invisible anchored holder with an attachment
function MuzzleFX.holder(name: string, cf: CFrame): (Part, Attachment)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = cf
	p.Parent = workspace
	local a = Instance.new("Attachment")
	a.Parent = p
	return p, a
end

function MuzzleFX.new(muzzle: Vector3, dir: Vector3)
	local self = setmetatable({}, MuzzleFX)
	self.muzzle, self.dir = muzzle, dir
	self.axle = dir:Cross(Vector3.yAxis).Unit
	self.up = self.axle:Cross(dir)
	local mcf = CFrame.lookAt(muzzle, muzzle + dir)
	local part, att = MuzzleFX.holder("MuzzleFX", mcf)
	local ringPart, ringAtt = MuzzleFX.holder("MuzzleRing", mcf)
	self.parts = { part, ringPart }
	self.ringAtt = ringAtt
	local S = PackFX.Sheet
	local E = MuzzleFX.emitter
	local fx = {}
	fx.flame = E(att, S.flame, {
		EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(0.12, 0.2), Speed = NumberRange.new(40, 80),
		Drag = 8, SpreadAngle = Vector2.new(12, 12), Size = ns({ { 0, 6 }, { 0.3, 10 }, { 1, 5 } }),
		Transparency = ns({ { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } }), Color = MuzzleFX.Flame, LightEmission = 0.15, LightInfluence = 0.3,
		Brightness = 1.6, ZOffset = 1,
	})
	fx.lick = E(ringAtt, S.lick, {
		EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(0.12, 0.22), Speed = NumberRange.new(24, 44),
		Drag = 6, SpreadAngle = Vector2.new(8, 8), Size = ns({ { 0, 2 }, { 0.4, 5 }, { 1, 3 } }),
		Transparency = ns({ { 0, 0 }, { 1, 1 } }), Color = MuzzleFX.Flame, LightEmission = 0.1, LightInfluence = 0.3, Brightness = 1.5, ZOffset = 1,
	})
	fx.cloud = E(att, S.plume, {
		EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(2.6, 3.6), Speed = NumberRange.new(4, 13),
		Drag = 1.4, SpreadAngle = Vector2.new(180, 180), Size = ns({ { 0, 4 }, { 0.3, 10 }, { 1, 16 } }),
		Transparency = ns({ { 0, 0.12 }, { 0.5, 0.5 }, { 1, 1 } }), RotSpeed = NumberRange.new(-14, 14), Color = ColorSequence.new(SMOKE),
		Acceleration = Vector3.new(0, 1.5, 0),
	})
	fx.smoke = E(att, S.plume, {
		EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(1.8, 2.8), Speed = NumberRange.new(30, 78),
		Drag = 2.4, SpreadAngle = Vector2.new(15, 15), Size = ns({ { 0, 5 }, { 0.25, 11 }, { 1, 19 } }),
		Transparency = ns({ { 0, 0.04 }, { 0.5, 0.4 }, { 1, 1 } }), RotSpeed = NumberRange.new(-25, 25),
		Color = cs({ { 0, Color3.fromRGB(236, 230, 220) }, { 1, Color3.fromRGB(204, 200, 194) } }),
		Acceleration = Vector3.new(0, 2.5, 0),
	})
	fx.ring = E(ringAtt, S.plume, {
		EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(1.1, 1.7), Speed = NumberRange.new(16, 24),
		Drag = 3.5, SpreadAngle = Vector2.new(4, 4), Size = ns({ { 0, 3 }, { 1, 11 } }),
		Transparency = ns({ { 0, 0.15 }, { 0.6, 0.5 }, { 1, 1 } }), RotSpeed = NumberRange.new(-30, 30), Color = ColorSequence.new(SMOKE),
		Acceleration = Vector3.new(0, 1.5, 0),
	})
	self.fx = fx
	self.emitters = { fx.flame, fx.lick, fx.cloud, fx.smoke, fx.ring }
	return self
end

-- the shot; q is how good it was, 0..1
function MuzzleFX:fire(q: number)
	local fx = self.fx
	fx.flame:Emit(math.floor(10 + q * 8))
	fx.smoke:Emit(math.floor(18 + q * 14))
	fx.cloud:Emit(math.floor(6 + q * 6))
	-- the ring: smoke thrown out square to the bore all the way round, flame tongues a little forward of it
	local n = 14
	for i = 1, n do
		local a = (i / n + math.random() * 0.03) * math.pi * 2
		local out = self.up * math.cos(a) + self.axle * math.sin(a)
		self.ringAtt.WorldCFrame = CFrame.lookAt(self.muzzle, self.muzzle + out + self.dir * 0.25)
		fx.ring:Emit(2)
		self.ringAtt.WorldCFrame = CFrame.lookAt(self.muzzle, self.muzzle + out + self.dir * 0.9)
		fx.lick:Emit(1)
	end
end

-- gone, after the smoke in the air has had time to thin out
function MuzzleFX:destroy(after: number?)
	for _, p in ipairs(self.parts) do
		if after and after > 0 then
			task.delay(after, function() p:Destroy() end)
		else
			p:Destroy()
		end
	end
end

return MuzzleFX
