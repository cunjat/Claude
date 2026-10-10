--!strict
-- TYRE CANNON :: PackFX
-- Particle presets built from the VFX packs' animated 4x4 sheets, shared by the run and the
-- launch. Particles only: no lights and no glow pulses.
--   PackFX.emitter(name, parent)        a switched-off emitter you drive with Rate/Enabled
--   PackFX.burst(name, cframe, count)   a one-off puff that cleans itself up

local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")

local PackFX = {}

PackFX.Sheet = {
	flame = "rbxassetid://11858203067",
	lick = "rbxassetid://11844017484",
	steam = "rbxassetid://13743483729",
	plume = "rbxassetid://13726321388",
}

local function ns(list: { { number } }): NumberSequence
	local k = {}
	for _, p in ipairs(list) do table.insert(k, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(k)
end

local function sheet(id: string)
	return { Texture = id, FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot }
end

local function with(base: { [string]: any }, extra: { [string]: any })
	local t = table.clone(base)
	for k, v in pairs(extra) do t[k] = v end
	return t
end

PackFX.Presets = {
	-- the boost: a short jet of flame out of the back of the hub
	boost = with(sheet(PackFX.Sheet.flame), {
		Lifetime = NumberRange.new(0.26, 0.34), Speed = NumberRange.new(34, 52), SpreadAngle = Vector2.new(9, 9),
		EmissionDirection = Enum.NormalId.Left, Rotation = NumberRange.new(-20, 20),
		Size = ns({ { 0, 4.6 }, { 0.5, 3.6 }, { 1, 1.6 } }), Transparency = ns({ { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } }),
		Color = ColorSequence.new(Color3.fromRGB(255, 214, 140), Color3.fromRGB(255, 110, 40)),
		LightEmission = 0.55, LightInfluence = 0.2, Brightness = 2.2, Rate = 60,
	}),
	-- tread smoke off a hot tyre: grey, thickening and darkening with the heat
	treadSmoke = with(sheet(PackFX.Sheet.plume), {
		Lifetime = NumberRange.new(0.9, 1.2), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 5, 0), Drag = 1.2,
		Rotation = NumberRange.new(-40, 40), RotSpeed = NumberRange.new(-20, 20),
		Size = ns({ { 0, 3 }, { 1, 9 } }), Transparency = ns({ { 0, 0.45 }, { 0.4, 0.4 }, { 1, 1 } }),
		Color = ColorSequence.new(Color3.fromRGB(120, 118, 116)), LightInfluence = 0.8, Rate = 18,
	}),
	-- ground dust thrown out in a ring (landings, the ramp lip)
	dustRing = with(sheet(PackFX.Sheet.plume), {
		Lifetime = NumberRange.new(0.8, 1.1), Speed = NumberRange.new(20, 36), SpreadAngle = Vector2.new(78, 78),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -2, 0), Drag = 3,
		Rotation = NumberRange.new(-60, 60), Size = ns({ { 0, 3 }, { 1, 10 } }), Transparency = ns({ { 0, 0.3 }, { 1, 1 } }),
		Color = ColorSequence.new(Color3.fromRGB(196, 170, 132)), LightInfluence = 0.9,
	}),
	-- a heavier puff kicked up and back (the shove, the ramp exit)
	dustPuff = with(sheet(PackFX.Sheet.steam), {
		Lifetime = NumberRange.new(0.9, 1.2), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(50, 50),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 3, 0), Drag = 1.5,
		Rotation = NumberRange.new(-40, 40), Size = ns({ { 0, 2 }, { 1, 7 } }), Transparency = ns({ { 0, 0.35 }, { 1, 1 } }),
		Color = ColorSequence.new(Color3.fromRGB(206, 184, 150)), LightInfluence = 0.9,
	}),
}

local function build(name: string): ParticleEmitter?
	local p = PackFX.Presets[name]
	if not p then return nil end
	local e = Instance.new("ParticleEmitter")
	e.Name = "Pack_" .. name
	for k, v in pairs(p) do
		if k ~= "Rate" then (e :: any)[k] = v end
	end
	e.Rate = 0
	e.Enabled = false
	return e
end

-- a switched-off emitter on `parent` (an Attachment or a part); its preset rate is kept on
-- the attribute BaseRate so callers can scale it
function PackFX.emitter(name: string, parent: Instance): ParticleEmitter?
	local e = build(name)
	if not e then return nil end
	e:SetAttribute("BaseRate", PackFX.Presets[name].Rate or 20)
	e.Parent = parent
	return e
end

-- a one-off puff at a place; `up` turns the emitter so its Top faces that way
function PackFX.burst(name: string, cf: CFrame, count: number, color: Color3?, scale: number?)
	local e = build(name)
	if not e then return end
	if color then e.Color = ColorSequence.new(color) end
	if scale and math.abs(scale - 1) > 1e-3 then
		local keys = {}
		for _, k in ipairs(e.Size.Keypoints) do table.insert(keys, NumberSequenceKeypoint.new(k.Time, k.Value * scale)) end
		e.Size = NumberSequence.new(keys)
		e.Speed = NumberRange.new(e.Speed.Min * scale, e.Speed.Max * scale)
	end
	local holder = Instance.new("Part")
	holder.Name = "PackFX"
	holder.Size = Vector3.one
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CFrame = cf
	holder.Parent = workspace
	local att = Instance.new("Attachment")
	att.Parent = holder
	e.Parent = att
	e:Emit(math.max(1, math.floor(count)))
	Debris:AddItem(holder, e.Lifetime.Max + 0.3)
end

task.spawn(function()
	local list = {}
	for _, id in pairs(PackFX.Sheet) do
		local d = Instance.new("Decal")
		d.Texture = id
		table.insert(list, d)
	end
	pcall(function() ContentProvider:PreloadAsync(list) end)
end)

return PackFX
