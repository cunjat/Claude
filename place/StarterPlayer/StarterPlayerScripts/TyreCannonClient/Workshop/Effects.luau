--!strict
-- TYRE CANNON :: Workshop / Effects
-- How a part goes on:
--   tyres   rubber-type looks go on under the blow torch; metal, glass and
--           neon looks are sprayed on
--   rims    the old hub slides off the axle, the new one slides on, then the
--           lug nuts spin home one at a time
--   trails  ribbons peel off the tread while the wheel spins up
-- The spray can is Assets.Workshop.SprayCan (it sprays out of its top, along
-- its -X side). Mist, droplets and the splash on the rubber are built here,
-- tinted to the paint, with the can's hiss from the imported spray tool.
-- The press head is only a fallback for when Assets.Workshop.BlowTorch is missing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Config = require(Modules.Config)
local WheelAssembly = require(Modules.WheelAssembly)
local VFX = require(script.Parent.Parent.VFX)
local Assets = Root:WaitForChild("Assets")

local SPRAY_SOUND = "rbxassetid://78496487"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local Effects = {}
Effects.__index = Effects

local PRESSED = { Pebble = true, Sand = true, SmoothPlastic = true, Plastic = true, Fabric = true, Rubber = true }
local HOT = Color3.fromRGB(255, 118, 36)

local function prop(name: string, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	return p
end

local function frameWait(): number
	return RunService.RenderStepped:Wait()
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- fades a whole prop in or out from the transparency each of its parts started with
local function fader(inst: Instance): (number) -> ()
	local list = {}
	local all = inst:GetDescendants()
	table.insert(all, inst)
	for _, p in ipairs(all) do
		if p:IsA("BasePart") or p:IsA("Decal") then
			table.insert(list, { inst = p, base = (p :: any).Transparency })
		end
	end
	return function(alpha: number)
		local a = math.clamp(alpha, 0, 1)
		for _, e in ipairs(list) do
			if e.inst.Parent then (e.inst :: any).Transparency = e.base + (1 - e.base) * a end
		end
	end
end

function Effects.new(ws)
	local self = setmetatable({}, Effects)
	self.ws = ws
	self.anims = {}
	self.skinProps = {}
	self.skinToken = 0
	self.rimToken = 0
	self.holding = false
	self.trailRig = nil
	return self
end

--==============================================================
-- bookkeeping
--==============================================================
function Effects:release()
	if self.holding then
		self.holding = false
		self.ws.spinHold = math.max(0, self.ws.spinHold - 1)
	end
end

function Effects:dropSkinProps()
	for _, inst in ipairs(self.skinProps) do
		if inst.Parent then inst:Destroy() end
	end
	self.skinProps = {}
	self:release()
end

function Effects:finishRim()
	local wheel = self.ws.wheel
	local root = wheel and wheel.PrimaryPart
	for i = #self.anims, 1, -1 do
		local a = self.anims[i]
		table.remove(self.anims, i)
		if root then self:pose(a, root.CFrame, 1) end
		if a.done then a.done(true) end
	end
end

function Effects:clear()
	self.skinToken += 1
	self.rimToken += 1
	self:dropSkinProps()
	self:finishRim()
	self.anims = {}
	if self.trailRig then
		self.trailRig:Destroy()
		self.trailRig = nil
	end
end

function Effects:hasTrail(): boolean
	return self.trailRig ~= nil and self.trailRig.Parent ~= nil
end

function Effects:admire()
	self.ws.spinKick = 6
end

function Effects:cameraSide(): number
	local root = self.ws.wheel.PrimaryPart
	return root.CFrame:PointToObjectSpace(workspace.CurrentCamera.CFrame.Position).Z >= 0 and 1 or -1
end

--==============================================================
-- part animations that ride along with the rolling wheel
--==============================================================
function Effects:entry(list: { Instance }, root: BasePart, o)
	local parts = {}
	for _, p in ipairs(list) do
		if p:IsA("BasePart") then
			table.insert(parts, { part = p, rel = root.CFrame:ToObjectSpace(p.CFrame), base = p.Transparency, size = p.Size })
		end
	end
	return { parts = parts, t = -(o.delay or 0), dur = o.dur, z = o.z, fade = o.fade, spin = o.spin, scale = o.scale, done = o.done }
end

function Effects:pose(a, rootCF: CFrame, k: number)
	local z = a.z and a.z(k) or 0
	local spin = a.spin and a.spin(k) or 0
	local fade = a.fade and a.fade(k) or nil
	local sc = a.scale and math.max(0.001, a.scale(k)) or nil
	local shift = rootCF * CFrame.new(0, 0, z)
	for _, e in ipairs(a.parts) do
		local p = e.part
		if p.Parent then
			local rel = e.rel
			if sc then
				rel = CFrame.new(rel.Position * sc) * rel.Rotation
				p.Size = e.size * sc
			end
			local cf = shift * rel
			if spin ~= 0 then cf *= CFrame.Angles(spin, 0, 0) end
			p.CFrame = cf
			if fade then p.Transparency = e.base + (1 - e.base) * fade end
		end
	end
end

function Effects:step(dt: number)
	local wheel = self.ws.wheel
	local root = wheel and wheel.PrimaryPart
	if not root then return end
	local rootCF = root.CFrame
	for i = #self.anims, 1, -1 do
		local a = self.anims[i]
		a.t += dt
		self:pose(a, rootCF, math.clamp(a.t / a.dur, 0, 1))
		if a.t >= a.dur then
			table.remove(self.anims, i)
			if a.done then a.done(false) end
		end
	end
end

--==============================================================
-- tyres
--==============================================================
function Effects:skin(id: string, animate: boolean?)
	local wheel = self.ws.wheel
	if not wheel then return end
	self.skinToken += 1
	local token = self.skinToken
	self:dropSkinProps()
	local skin = Config.SkinsById[id] or Config.SkinsById.stock
	if not animate then
		WheelAssembly.setSkin(wheel, skin.id)
		return
	end
	if PRESSED[skin.material.Name] then
		task.spawn(function() self:torch(skin, token) end)
	else
		task.spawn(function() self:spray(skin, token) end)
	end
end

function Effects:makeCan(skin)
	local tpl = Assets:FindFirstChild("Workshop") and Assets.Workshop:FindFirstChild("SprayCan")
	local can: BasePart
	if tpl and tpl:IsA("BasePart") then
		can = tpl:Clone()
		for _, c in ipairs(can:GetChildren()) do
			if c:IsA("JointInstance") or c:IsA("WeldConstraint") then c:Destroy() end
		end
	else
		can = prop("SprayCan", Vector3.new(2, 0.9, 0.9), skin.tyre, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	can.Name = "SprayCan"
	can.Anchored = true
	can.CanCollide = false
	can.CanQuery = false
	can.CanTouch = false
	can.CastShadow = true
	local paint = skin.tyre:Lerp(Color3.new(1, 1, 1), 0.12)

	local nozzle = Instance.new("Attachment")
	nozzle.Name = "Nozzle"
	nozzle.CFrame = CFrame.new(0, can.Size.Y * 0.4, 0) * CFrame.Angles(0, math.pi / 2, 0)
	nozzle.Parent = can

	local mist = Instance.new("ParticleEmitter")
	mist.Name = "Mist"
	mist.Texture = SMOKE
	mist.EmissionDirection = Enum.NormalId.Front
	mist.Rate = 150
	mist.Lifetime = NumberRange.new(0.28, 0.42)
	mist.Speed = NumberRange.new(9, 13)
	mist.SpreadAngle = Vector2.new(9, 9)
	mist.Drag = 2.5
	mist.Acceleration = Vector3.new(0, -0.8, 0)
	mist.Rotation = NumberRange.new(0, 360)
	mist.RotSpeed = NumberRange.new(-90, 90)
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.35, 0.4), NumberSequenceKeypoint.new(1, 0.85),
	})
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.55, 0.55), NumberSequenceKeypoint.new(1, 1),
	})
	mist.Color = ColorSequence.new(paint)
	mist.LightInfluence = 0.9
	mist.LightEmission = 0.05
	mist.Enabled = false
	mist.Parent = nozzle

	local drops = Instance.new("ParticleEmitter")
	drops.Name = "Droplets"
	drops.Texture = SPARKLE
	drops.EmissionDirection = Enum.NormalId.Front
	drops.Rate = 70
	drops.Lifetime = NumberRange.new(0.12, 0.22)
	drops.Speed = NumberRange.new(15, 20)
	drops.SpreadAngle = Vector2.new(5, 5)
	drops.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.07), NumberSequenceKeypoint.new(1, 0.02) })
	drops.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	drops.Color = ColorSequence.new(paint)
	drops.LightInfluence = 1
	drops.Enabled = false
	drops.Parent = nozzle

	local hiss = Instance.new("Sound")
	hiss.Name = "Hiss"
	hiss.SoundId = SPRAY_SOUND
	hiss.Looped = true
	hiss.Volume = 0.45
	hiss.PlaybackSpeed = 1.05
	hiss.Parent = can

	can.Parent = self.ws.room.folder
	return can, { mist, drops }, hiss
end

function Effects:spray(skin, token: number)
	local ws = self.ws
	local wheel = ws.wheel
	local carcass = wheel and wheel:FindFirstChild("Carcass") :: BasePart?
	if not (wheel and carcass) then return end
	local d = WheelAssembly.dims(wheel)
	local paint = skin.tyre:Lerp(Color3.new(1, 1, 1), 0.12)

	local coat = carcass:Clone()
	coat.Name = "Coat"
	coat.Size = carcass.Size * 1.012
	coat.Color = skin.tyre
	coat.Material = skin.material
	coat.Reflectance = skin.reflect or 0
	coat.Transparency = 1
	coat.CastShadow = false
	coat.Parent = wheel
	table.insert(self.skinProps, coat)

	local can, emitters, hiss = self:makeCan(skin)
	table.insert(self.skinProps, can)
	local fade = fader(can)
	fade(1)
	local rates = {}
	for _, e in ipairs(emitters) do rates[e] = e.Rate end

	-- where the mist lands on the rubber
	local splash = prop("Splash", Vector3.new(0.2, 0.2, 0.2), paint, Enum.Material.SmoothPlastic)
	splash.Transparency = 1
	splash.CastShadow = false
	local settleFx = Instance.new("ParticleEmitter")
	settleFx.Texture = SMOKE
	settleFx.Rate = 45
	settleFx.Lifetime = NumberRange.new(0.35, 0.6)
	settleFx.Speed = NumberRange.new(0.4, 1.4)
	settleFx.SpreadAngle = Vector2.new(180, 180)
	settleFx.Rotation = NumberRange.new(0, 360)
	settleFx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.8) })
	settleFx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	settleFx.Color = ColorSequence.new(paint)
	settleFx.LightInfluence = 1
	settleFx.Enabled = false
	settleFx.Parent = splash
	splash.Parent = ws.room.folder
	table.insert(self.skinProps, splash)

	-- In, spray, out. The can swings in fading up, and pulls away while its sweep is
	-- still going, so it never stops dead: the mist tails off, the can picks up speed,
	-- tips its nozzle up and fades out.
	local IN, SPRAY, OUT = 0.22, 1.15, 0.55
	local outAt = SPRAY - 0.2
	local total = outAt + OUT
	local t = 0
	local skinned = false
	while t < total do
		t += frameWait()
		if token ~= self.skinToken or not wheel.Parent or not wheel.PrimaryPart or not can.Parent then return end
		local qIn = smooth(t / IN)
		local qOut = math.clamp((t - outAt) / OUT, 0, 1)
		if not skinned then
			coat.Transparency = 1 - math.clamp((t - 0.12) / (SPRAY - 0.32), 0, 1)
			if t >= SPRAY - 0.2 then
				skinned = true
				WheelAssembly.setSkin(wheel, skin.id)
				coat:Destroy()
			end
		end
		local flow = (qIn > 0.8 and 1 or 0) * (1 - smooth(qOut / 0.45))
		for _, e in ipairs(emitters) do
			e.Enabled = flow > 0.02
			e.Rate = rates[e] * flow
		end
		settleFx.Enabled = flow > 0.3
		if hiss then
			if flow > 0.02 and not hiss.IsPlaying then hiss:Play() end
			hiss.Volume = 0.45 * flow
		end

		local k = t / SPRAY
		local cam = workspace.CurrentCamera.CFrame
		local centre = wheel.PrimaryPart.Position
		local toCam = (cam.Position - centre).Unit
		local sweep = math.sin(k * math.pi * 3)
		local aim = centre + cam.UpVector * (sweep * d.R * 0.75) + toCam * (d.W * 0.2)
		local nozzlePos = centre + cam.RightVector * (d.R + 2.1) + toCam * 1.8 + cam.UpVector * (sweep * d.R * 0.35)
		local away = cam.RightVector * 2.4 + toCam * 1.3 + cam.UpVector * 1.0
		local offset = away * ((1 - qIn) + qOut * qOut)
		local tilt = math.rad(14) * (1 - qIn) + math.rad(28) * smooth(qOut)
		local shake = CFrame.Angles(math.sin(t * 47) * 0.03 * flow, 0, math.sin(t * 39) * 0.03 * flow)
		can.CFrame = CFrame.lookAt(nozzlePos + offset, aim + offset * 0.5) * CFrame.Angles(tilt, 0, 0) * shake
			* CFrame.Angles(0, -math.pi / 2, 0) * CFrame.new(0, -can.Size.Y * 0.4, 0)
		fade(math.max(1 - qIn, smooth((qOut - 0.2) / 0.8)))
		local hit = WheelAssembly.raycast(wheel, nozzlePos, (aim - nozzlePos).Unit * 20)
		splash.CFrame = CFrame.new(hit and hit.point or aim)
	end
	if not skinned then
		WheelAssembly.setSkin(wheel, skin.id)
		coat:Destroy()
	end
	for _, e in ipairs(emitters) do e.Enabled = false end
	settleFx.Enabled = false
	if hiss then hiss:Stop() end
	can:Destroy()
	-- the last of the mist settles before its emitter goes
	task.delay(0.7, function()
		if splash.Parent then splash:Destroy() end
	end)
end

-- the torch: your BlowTorch model sweeps across the tread with a small flame, the
-- new rubber comes up behind it. Assets.Workshop.BlowTorch carries NozzleDir (which
-- way the nozzle points in its own space) and NozzleHeight (fraction of its height).
local NOZZLE_TURN = {
	["0,0,1"] = CFrame.new(),
	["0,0,-1"] = CFrame.Angles(0, math.pi, 0),
	["1,0,0"] = CFrame.Angles(0, -math.pi / 2, 0),
	["-1,0,0"] = CFrame.Angles(0, math.pi / 2, 0),
}

function Effects:torch(skin, token: number)
	local ws = self.ws
	local wheel = ws.wheel
	local carcass = wheel and wheel:FindFirstChild("Carcass") :: BasePart?
	if not (wheel and carcass) then return end
	local tpl = Assets:FindFirstChild("Workshop") and Assets.Workshop:FindFirstChild("BlowTorch")
	if not (tpl and tpl:IsA("Model")) then
		self:press(skin, token)
		return
	end
	local d = WheelAssembly.dims(wheel)

	local coat = carcass:Clone()
	coat.Name = "Coat"
	coat.Size = carcass.Size * 1.012
	coat.Color = skin.tyre
	coat.Material = skin.material
	coat.Reflectance = skin.reflect or 0
	coat.Transparency = 1
	coat.CastShadow = false
	coat.Parent = wheel
	table.insert(self.skinProps, coat)

	local torch = tpl:Clone()
	local _, s0 = torch:GetBoundingBox()
	torch:ScaleTo(torch:GetScale() * (d.R * 0.95 / math.max(s0.Y, 0.01)))
	for _, p in ipairs(torch:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	local fade = fader(torch)
	fade(1)
	torch.Parent = ws.room.folder
	table.insert(self.skinProps, torch)

	local nd = tpl:GetAttribute("NozzleDir")
	if typeof(nd) ~= "Vector3" then nd = Vector3.new(0, 0, 1) end
	local key = ("%d,%d,%d"):format(math.round(nd.X), math.round(nd.Y), math.round(nd.Z))
	local turn = NOZZLE_TURN[key] or CFrame.new()
	local nh = tpl:GetAttribute("NozzleHeight")
	if type(nh) ~= "number" then nh = 0.8 end
	local bb, size = torch:GetBoundingBox()
	local pivot = torch:GetPivot()
	local centreL = pivot:PointToObjectSpace(bb.Position)
	local tipL = Vector3.new(centreL.X + nd.X * size.X / 2, size.Y * nh, centreL.Z + nd.Z * size.Z / 2)

	-- the flame: your BoostFlame emitters, shrunk to torch size and shortened
	local host = torch:FindFirstChildWhichIsA("BasePart", true)
	local flame = nil
	if host and VFX.has("BoostFlame") then
		local tipCF = CFrame.fromMatrix(tipL, Vector3.xAxis, Vector3.new(nd.X, nd.Y, nd.Z).Unit)
		local offset = host.CFrame:ToObjectSpace(pivot * tipCF)
		flame = VFX.attach("BoostFlame", host, offset, 0.05)
		if flame then
			for _, e in ipairs(flame.emitters) do
				e.Lifetime = NumberRange.new(e.Lifetime.Min * 0.14, e.Lifetime.Max * 0.14)
			end
		end
	end

	-- In, work, out. The torch swings in fading up, and pulls away while its sweep is
	-- still going, so it never stops dead: the flame tails off first, then the torch
	-- picks up speed, tips its nozzle off the rubber and fades out.
	local IN, BURN, OUT = 0.24, 1.8, 0.6
	local outAt = BURN - 0.25
	local total = outAt + OUT
	local t, lastSmoke = 0, 0
	local skinned, flameOn = false, false
	while t < total do
		t += frameWait()
		if token ~= self.skinToken or not wheel.Parent or not wheel.PrimaryPart or not torch.Parent then
			if flame then flame.set(false) end
			return
		end
		local qIn = smooth(t / IN)
		local qOut = math.clamp((t - outAt) / OUT, 0, 1)
		local k = t / BURN
		local cam = workspace.CurrentCamera.CFrame
		local centre = wheel.PrimaryPart.Position
		local axle = wheel.PrimaryPart.CFrame.ZVector
		local toCam = (cam.Position - centre).Unit
		local near = axle:Dot(toCam) >= 0 and 1 or -1
		-- work the upper right of the tread, where the camera sees it clear of the top bar,
		-- rocking along the arc and across the width while the wheel turns under the flame
		local ang = math.rad(10 + 15 * math.sin(k * math.pi * 2.2))
		local side = cam.RightVector * math.cos(ang) + cam.UpVector * math.sin(ang)
		side = (side - axle * side:Dot(axle)).Unit
		local across = axle * near * (d.W * 0.18 * math.sin(k * math.pi * 5))
		local aim = centre + side * (d.R * 0.97) + across
		local tip = aim + side * 0.55 + toCam * 0.25

		if not skinned then
			coat.Transparency = 1 - math.clamp((t - 0.15) / (BURN - 0.45), 0, 1)
			if t >= BURN - 0.25 then
				skinned = true
				WheelAssembly.setSkin(wheel, skin.id)
				coat:Destroy()
			end
		end
		local heat = (qIn > 0.7 and 1 or 0) * (1 - smooth(qOut / 0.35))
		if flame then
			if heat > 0.03 then
				flame.set(true, 2.5 * heat)
				flameOn = true
			elseif flameOn then
				flame.set(false)
				flameOn = false
			end
		end

		local aimDir = (aim - tip).Unit
		local up = Vector3.yAxis - aimDir * aimDir:Dot(Vector3.yAxis)
		if up.Magnitude < 0.1 then up = cam.RightVector end
		up = up.Unit
		local right = up:Cross(aimDir).Unit
		local away = side * 2.8 + toCam * 1.3 + cam.UpVector * 0.9
		local offset = away * ((1 - qIn) + qOut * qOut)
		local tilt = math.rad(-14) * (1 - qIn) + math.rad(-32) * smooth(qOut)
		local frame = CFrame.fromMatrix(tip + offset, right, up, aimDir) * CFrame.Angles(tilt, 0, 0)
		torch:PivotTo(frame * turn * CFrame.new(-tipL))
		fade(math.max(1 - qIn, smooth((qOut - 0.15) / 0.85)))
		if heat > 0.5 and t - lastSmoke > 0.22 and VFX.has("LandSmoke") then
			lastSmoke = t
			VFX.emit("LandSmoke", CFrame.new(aim), { scale = 0.2, color = Color3.fromRGB(70, 68, 66), countMult = 0.3, parent = ws.room.folder })
		end
	end
	if flame then flame.set(false) end
	if not skinned then
		WheelAssembly.setSkin(wheel, skin.id)
		coat:Destroy()
	end
	torch:Destroy()
end

local function slide(model: Model, from: CFrame, to: CFrame, dur: number, easeIn: boolean, alive: () -> boolean): boolean
	local t = 0
	while t < dur do
		t += frameWait()
		if not alive() or not model.Parent then return false end
		local k = math.clamp(t / dur, 0, 1)
		k = easeIn and k * k or 1 - (1 - k) * (1 - k)
		model:PivotTo(from:Lerp(to, k))
	end
	return true
end

function Effects:press(skin, token: number)
	local ws = self.ws
	local wheel = ws.wheel
	local carcass = wheel and wheel:FindFirstChild("Carcass") :: BasePart?
	if not (wheel and carcass) then return end
	local function alive(): boolean
		return token == self.skinToken and wheel.Parent ~= nil and wheel.PrimaryPart ~= nil
	end
	ws.spinHold += 1
	self.holding = true
	local waited = 0
	while waited < 0.4 do
		waited += frameWait()
		if not alive() then
			self:release()
			return
		end
	end

	local d = WheelAssembly.dims(wheel)
	local root = wheel.PrimaryPart
	local up = Vector3.yAxis
	local axle = root.CFrame.ZVector
	local frame = CFrame.fromMatrix(Vector3.zero, axle, up)
	local top = root.Position + up * d.R

	local head = Instance.new("Model")
	head.Name = "PressHead"
	local block = prop("Block", Vector3.new(d.W * 1.5, 0.55, 2.2), Color3.fromRGB(48, 50, 54), Enum.Material.DiamondPlate)
	block.CFrame = frame * CFrame.new(0, 0.08 + 0.275, 0)
	block.Parent = head
	local plate = prop("Plate", Vector3.new(d.W * 1.35, 0.08, 1.95), HOT, Enum.Material.Neon)
	plate.CFrame = frame * CFrame.new(0, 0.04, 0)
	plate.CastShadow = false
	plate.Parent = head
	local ram = prop("Ram", Vector3.new(0.35, 8, 0.35), Color3.fromRGB(150, 154, 160), Enum.Material.Metal)
	ram.CFrame = frame * CFrame.new(0, 0.63 + 4, 0)
	ram.Parent = head
	local heat = Instance.new("PointLight")
	heat.Color = HOT
	heat.Range = 5
	heat.Brightness = 2
	heat.Shadows = false
	heat.Parent = plate
	head.WorldPivot = frame
	head.Parent = ws.room.folder
	table.insert(self.skinProps, head)

	local hi = CFrame.new(top + up * 6) * frame.Rotation
	local contact = CFrame.new(top + up * 0.02) * frame.Rotation
	head:PivotTo(hi)
	if not slide(head, hi, contact, 0.24, true, alive) then
		self:dropSkinProps()
		return
	end

	WheelAssembly.setSkin(wheel, skin.id)
	local glow = carcass:Clone()
	glow.Name = "PressGlow"
	glow.Size = carcass.Size * 1.01
	glow.Material = Enum.Material.Neon
	glow.Color = HOT
	glow.Transparency = 0.35
	glow.CastShadow = false
	glow.Parent = wheel
	table.insert(self.skinProps, glow)
	if VFX.has("LandSmoke") then
		VFX.emit("LandSmoke", CFrame.new(top), { scale = 0.45, color = Color3.fromRGB(236, 236, 236), countMult = 0.8, parent = ws.room.folder })
	end
	if VFX.has("Sparks") then
		VFX.emit("Sparks", CFrame.new(top), { scale = 0.3, countMult = 0.4, parent = ws.room.folder })
	end

	local t = 0
	while t < 0.45 do
		t += frameWait()
		if not alive() then
			self:dropSkinProps()
			return
		end
		glow.Transparency = 0.35 + 0.35 * (t / 0.45)
	end
	if not slide(head, contact, hi, 0.35, false, alive) then
		self:dropSkinProps()
		return
	end
	head:Destroy()
	self:release()
	t = 0
	while t < 0.6 and glow.Parent do
		t += frameWait()
		glow.Transparency = 0.7 + 0.3 * (t / 0.6)
	end
	glow:Destroy()
end

--==============================================================
-- rims
--==============================================================
function Effects:shadows(model: Instance?)
	if not model then return end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.CastShadow = true end
	end
end

function Effects:rim(id: string, animate: boolean?)
	local ws = self.ws
	local wheel = ws.wheel
	if not wheel or not wheel.PrimaryPart then return end
	self:finishRim()
	self.rimToken += 1
	if not animate then
		WheelAssembly.setRim(wheel, id)
		self:shadows(wheel:FindFirstChild("Hub"))
		return
	end
	local root = wheel.PrimaryPart
	local side = self:cameraSide()
	local folder = ws.room.folder

	-- the old hub: the nuts spin loose, then the hub shrinks back into the axle
	local old = wheel:FindFirstChild("Hub")
	if old then
		old.Name = "HubOut"
		local oldNuts, oldBody = {}, {}
		for _, d in ipairs(old:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "Nut" then table.insert(oldNuts, d) else table.insert(oldBody, d) end
			end
		end
		for _, n in ipairs(oldNuts) do
			local rel = root.CFrame:ToObjectSpace(n.CFrame)
			local outward = rel.Position.Z >= 0 and 1 or -1
			table.insert(self.anims, self:entry({ n }, root, {
				dur = 0.14,
				z = function(k: number) return outward * k * 0.6 end,
				spin = function(k: number) return -k * math.pi * 4 end,
				scale = function(k: number) return 1 - k end,
			}))
		end
		table.insert(self.anims, self:entry(oldBody, root, {
			delay = 0.1,
			dur = 0.22,
			scale = function(k: number) return 1 - k * k end,
			done = function() if old.Parent then old:Destroy() end end,
		}))
	end

	-- the new hub grows out of the axle with a little overshoot, then the nuts spin home
	WheelAssembly.setRim(wheel, id)
	local hub = wheel:FindFirstChild("Hub")
	if not hub then return end
	self:shadows(hub)
	local body, nuts = {}, {}
	for _, d in ipairs(hub:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Nut" then table.insert(nuts, d) else table.insert(body, d) end
		end
	end
	local function backOut(k: number): number
		local c1, c3 = 1.4, 2.4
		return 1 + c3 * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
	end
	table.insert(self.anims, self:entry(body, root, {
		delay = 0.3,
		dur = 0.38,
		scale = function(k: number) return backOut(k) end,
	}))
	local nearCount = 0
	for _, n in ipairs(nuts) do
		local rel = root.CFrame:ToObjectSpace(n.CFrame)
		local out = rel.Position.Z >= 0 and 1 or -1
		local near = out == side
		if near then nearCount += 1 end
		table.insert(self.anims, self:entry({ n }, root, {
			delay = 0.68 + (near and nearCount * 0.08 or 0),
			dur = near and 0.2 or 0.05,
			z = function(k: number) return out * (1 - k) * 0.7 end,
			scale = function(k: number) return k > 0 and 1 or 0 end,
			spin = near and function(k: number) return (1 - k) * math.pi * 6 end or nil,
			done = near and function(instant: boolean)
				if instant or not n.Parent or not VFX.has("Sparks") then return end
				VFX.emit("Sparks", n.CFrame, { scale = 0.18, countMult = 0.25, parent = folder })
			end or nil,
		}))
	end
	-- pose everything now, so the new hub never renders a frame at full size before it grows
	local rootCF = root.CFrame
	for _, a in ipairs(self.anims) do
		self:pose(a, rootCF, math.clamp(a.t / a.dur, 0, 1))
	end
end

--==============================================================
-- trails
--==============================================================
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 190, 70)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(240, 255, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(90, 255, 150)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 170, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 110, 255)),
})

function Effects:trail(id: string, animate: boolean?)
	local ws = self.ws
	local wheel = ws.wheel
	if self.trailRig then
		self.trailRig:Destroy()
		self.trailRig = nil
	end
	local def = Config.TrailsById[id]
	if not wheel or not wheel.PrimaryPart or not def or not def.a then return end
	local root = wheel.PrimaryPart
	local d = WheelAssembly.dims(wheel)
	local rig = Instance.new("Folder")
	rig.Name = "TrailRig"
	rig.Parent = wheel
	local color = def.rainbow and RAINBOW or ColorSequence.new(def.a, def.b or def.a)
	local trails = {}
	for i = 0, 1 do
		local carrier = prop("TrailCarrier", Vector3.new(0.1, 0.1, 0.1), def.a, Enum.Material.SmoothPlastic)
		carrier.Transparency = 1
		carrier.CastShadow = false
		carrier.CFrame = root.CFrame * CFrame.Angles(0, 0, i * math.pi) * CFrame.new(0, d.R + 0.04, 0)
		carrier.Parent = rig
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0, -d.W * 0.45)
		a0.Parent = carrier
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, 0, d.W * 0.45)
		a1.Parent = carrier
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Color = color
		tr.LightEmission = def.glow or 0
		tr.LightInfluence = (def.glow or 0) > 0.5 and 0 or 0.6
		tr.Lifetime = math.clamp((def.life or 0.8) * 0.7, 0.25, 1.1)
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.3) })
		tr.MinLength = 0.02
		tr.FaceCamera = false
		tr.Enabled = false
		tr.Parent = carrier
		table.insert(trails, tr)
		if def.sparks and i == 0 and VFX.has("Sparks") then
			local h = VFX.attach("Sparks", carrier, nil, 0.22)
			if h then h.set(true, 0.35) end
		end
	end
	self.trailRig = rig
	-- start drawing a moment later, or the ribbon streaks in from wherever the part was made
	task.delay(0.06, function()
		for _, t in ipairs(trails) do
			if t.Parent then
				t:Clear()
				t.Enabled = true
			end
		end
	end)
	if animate then self:admire() end
end

return Effects
