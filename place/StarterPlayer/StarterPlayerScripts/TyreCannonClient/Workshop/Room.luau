--!strict
-- TYRE CANNON :: Workshop / Room
-- The dark garage around the workbench. Built once per player, far above the
-- map, and only parented while the workbench is open (or warming up).
-- Real models: Assets.Workshop.Bench, Anvil, Hammer, HangingLamp.
-- PLACEHOLDER, swap for models: the walls, the tyre stand and the dust motes.
--
-- Layout, in the room's own frame (camera looks down -Z):
--   bench      centred at z -8, 19.2 long across X, worktop 4.5 up
--   wheel      on the stand at (0, 7.6, -7.3)
--   anvil      on the floor at x 16, clear of the bench end at x 9.6
--   lamps      hang from the ceiling (y 29.5): one over the wheel, one over the anvil

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Assets = Root:WaitForChild("Assets")
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))
local VFX = require(script.Parent.Parent.VFX)

local Room = {}
Room.__index = Room

local BENCH_SCALE = 1.6
local ANVIL_SCALE = 1.3
local HAMMER_SCALE = 2.2
local WHEEL_R = 2.5
local ANVIL_X = 16
local CEILING_Y = 29.5
local WARM = Color3.fromRGB(255, 200, 146)
local COOL = Color3.fromRGB(128, 160, 255)
local ORANGE = Color3.fromRGB(255, 138, 31)
local SHADE = Color3.fromRGB(34, 48, 40)
local LAMP_BRIGHT = 7

local function part(parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

local function settle(model: Instance)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = true
		end
	end
end

local function texture(name: string): string?
	local vfx = Assets:FindFirstChild("VFX")
	local f = vfx and vfx:FindFirstChild("Textures")
	local v = f and f:FindFirstChild(name)
	if not (v and v:IsA("StringValue")) or v.Value == "" then return nil end
	if tonumber(v.Value) then return "rbxassetid://" .. v.Value end
	return v.Value
end

--==============================================================
-- a lamp hanging from the ceiling, able to swing about its mount
--==============================================================
local function hangLamp(parent: Instance, name: string, shadeAt: Vector3, aim: Vector3, scale: number, ceilingY: number)
	local lamp = { rest = {}, phase = math.random() * 6.28 }
	local model = Instance.new("Model")
	model.Name = name
	local shade: BasePart? = nil
	local mount: BasePart? = nil
	local assetSpot: SpotLight? = nil
	local a0: Attachment? = nil
	local a1: Attachment? = nil
	local rope: RopeConstraint? = nil

	local tpl = Assets.Workshop:FindFirstChild("HangingLamp")
	if tpl and tpl:IsA("Model") then
		model = tpl:Clone()
		model.Name = name
		if scale ~= 1 then model:ScaleTo(model:GetScale() * scale) end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("AlignPosition") or d:IsA("AlignOrientation") or d:IsA("Camera") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("SpotLight") and d.Parent and d.Parent:IsA("BasePart") then
				shade = d.Parent :: BasePart
				assetSpot = d
			end
		end
		for _, d in ipairs(model:GetChildren()) do
			if d:IsA("BasePart") and d ~= shade then mount = d end
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("RopeConstraint") then
				if d.Attachment0 and d.Attachment1 then
					rope = d
					a0, a1 = d.Attachment0, d.Attachment1
				else
					d:Destroy()
				end
			end
		end
	end

	if not shade then
		-- no lamp model: a plain drum shade on a cord
		shade = part(model, "Shade", Vector3.new(1.5, 3, 3) * scale, CFrame.new(shadeAt) * CFrame.Angles(0, 0, math.pi / 2), SHADE, Enum.Material.Metal, Enum.PartType.Cylinder)
		mount = part(model, "Mount", Vector3.new(0.6, 0.4, 0.6), CFrame.new(shadeAt.X, ceilingY, shadeAt.Z), Color3.fromRGB(30, 30, 30), Enum.Material.Metal)
		a1 = Instance.new("Attachment")
		a1.Parent = shade
		a1.WorldPosition = shadeAt + Vector3.new(0, 0.75 * scale, 0)
		a0 = Instance.new("Attachment")
		a0.Parent = mount
		a0.WorldPosition = Vector3.new(shadeAt.X, ceilingY - 0.2, shadeAt.Z)
		local r = Instance.new("RopeConstraint")
		r.Attachment0 = a0
		r.Attachment1 = a1
		r.Visible = true
		r.Parent = mount
		rope = r
		local sp = Instance.new("SpotLight")
		sp.Face = Enum.NormalId.Left
		sp.Parent = shade
		assetSpot = sp
	else
		model:PivotTo(model:GetPivot() + (shadeAt - (shade :: BasePart).Position))
	end
	local sh = shade :: BasePart

	-- the mount goes flush with the ceiling, straight above the shade
	local top = a1 and a1.WorldPosition or (sh.Position + Vector3.new(0, sh.Size.Y / 2, 0))
	if mount then
		local off = a0 and (a0.WorldPosition - mount.Position) or Vector3.new(0, -mount.Size.Y / 2, 0)
		mount.CFrame = (mount.CFrame - mount.Position) + (Vector3.new(top.X, ceilingY, top.Z) - off)
		mount.Color = Color3.fromRGB(36, 36, 38)
		mount.Material = Enum.Material.Metal
		mount.CastShadow = false
	end
	if rope and a0 and a1 then
		rope.Length = (a0.WorldPosition - a1.WorldPosition).Magnitude
		rope.Visible = true
		rope.Thickness = 0.07
		rope.Color = BrickColor.new("Really black")
	end

	-- enamel shade, warm bulb, and a hidden key light aimed at the work
	pcall(function() (sh :: any).UsePartColor = true end)
	sh.Color = SHADE
	sh.Material = Enum.Material.Metal
	sh.CastShadow = false
	local down = Vector3.new(0, -1, 0)
	if assetSpot then
		down = sh.CFrame:VectorToWorldSpace(Vector3.FromNormalId(assetSpot.Face))
		assetSpot.Brightness = 1.6
		assetSpot.Range = 14 * scale
		assetSpot.Angle = 80
		assetSpot.Shadows = false
		assetSpot.Color = WARM
	end
	local bulbPos = sh.Position + down * (sh.Size.Y * 0.3)
	local bulb = part(model, "Bulb", Vector3.new(0.6, 0.6, 0.6) * scale / 0.75, CFrame.new(bulbPos), WARM, Enum.Material.Neon, Enum.PartType.Ball)
	bulb.CastShadow = false
	local glow = Instance.new("PointLight")
	glow.Range = 3 * scale / 0.75
	glow.Brightness = 0.8
	glow.Color = WARM
	glow.Shadows = false
	glow.Parent = bulb
	local emitter = part(model, "KeyLight", Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(bulbPos + down * 0.3, aim), WARM, Enum.Material.SmoothPlastic)
	emitter.Transparency = 1
	emitter.CastShadow = false
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Color = WARM
	spot.Shadows = true
	spot.Parent = emitter

	model.Parent = parent
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= mount then lamp.rest[d] = d.CFrame end
	end
	lamp.model = model
	lamp.shade = sh
	lamp.bulb = bulb
	lamp.spot = spot
	lamp.glow = assetSpot
	lamp.emitter = emitter
	lamp.pivot = a0 and a0.WorldPosition or Vector3.new(top.X, ceilingY, top.Z)
	local length = math.max(2, (lamp.pivot - sh.Position).Magnitude)
	lamp.omega = math.sqrt(workspace.Gravity / length)
	return lamp
end

--==============================================================
function Room.build(origin: CFrame)
	local self = setmetatable({}, Room)
	self.origin = origin
	local folder = Instance.new("Model")
	folder.Name = "WorkshopRoom"
	self.folder = folder
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	local function pos(x: number, y: number, z: number): Vector3
		return origin * Vector3.new(x, y, z)
	end
	local ceiling = origin.Y + CEILING_Y

	-- shell
	local shell = Instance.new("Model")
	shell.Name = "Shell"
	shell.Parent = folder
	part(shell, "Floor", Vector3.new(96, 1, 84), at(0, -0.5, -6), Color3.fromRGB(38, 36, 34), Enum.Material.Concrete)
	part(shell, "BackWall", Vector3.new(96, 40, 1), at(0, 19.5, -12.6), Color3.fromRGB(30, 27, 25), Enum.Material.Brick)
	part(shell, "WallL", Vector3.new(1, 40, 84), at(-36, 19.5, -6), Color3.fromRGB(16, 15, 14), Enum.Material.Concrete)
	part(shell, "WallR", Vector3.new(1, 40, 84), at(36, 19.5, -6), Color3.fromRGB(16, 15, 14), Enum.Material.Concrete)
	part(shell, "WallFront", Vector3.new(96, 40, 1), at(0, 19.5, 30), Color3.fromRGB(12, 12, 12), Enum.Material.Concrete)
	part(shell, "Ceiling", Vector3.new(96, 1, 84), at(0, 30, -6), Color3.fromRGB(12, 12, 12), Enum.Material.Concrete)

	-- the bench, front facing the camera
	local benchTpl = Assets.Workshop.Bench
	local bench = benchTpl:Clone()
	bench:ScaleTo(bench:GetScale() * BENCH_SCALE)
	local lift = ((benchTpl:GetAttribute("PivotAboveFloor") :: number?) or 3.7) * BENCH_SCALE
	bench:PivotTo(at(0, lift, -8) * CFrame.Angles(0, math.pi / 2, 0))
	settle(bench)
	bench.Parent = folder
	local topAttr = benchTpl:GetAttribute("TopHeight") :: number?
	local top = ((topAttr and topAttr > 0) and topAttr or 2.81) * BENCH_SCALE
	self.benchTop = top
	self.bench = bench

	-- the stand the wheel sits on (PLACEHOLDER)
	local restYaw = math.rad(-40)
	local centreY = top + 0.3 + WHEEL_R + 0.3
	self.wheelBase = at(0, centreY, -7.3) * CFrame.Angles(0, restYaw, 0)
	local centreW = self.wheelBase.Position
	self.wheelCentre = centreW
	local zv = self.wheelBase.ZVector
	local W = 1.57 * (WHEEL_R * 2 / 6)
	local stand = Instance.new("Model")
	stand.Name = "Stand"
	stand.Parent = folder
	local baseY = origin.Y + top
	local postP = centreW - zv * (W / 2 + 0.55)
	local postH = centreW.Y - baseY
	local steel = Color3.fromRGB(44, 46, 50)
	part(stand, "Foot", Vector3.new(0.3, 2.2, 2.2), CFrame.new(postP.X, baseY + 0.15, postP.Z) * CFrame.Angles(0, 0, math.pi / 2), steel, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(stand, "Post", Vector3.new(0.42, postH, 0.42), CFrame.new(postP.X, baseY + postH / 2, postP.Z), steel, Enum.Material.Metal)
	part(stand, "Band", Vector3.new(0.46, 0.16, 0.46), CFrame.new(postP.X, baseY + postH * 0.55, postP.Z), ORANGE, Enum.Material.SmoothPlastic)
	local mid = (postP + centreW) / 2
	part(stand, "Spindle", Vector3.new((centreW - postP).Magnitude + 0.2, 0.3, 0.3), CFrame.lookAt(mid, mid + zv) * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(150, 154, 160), Enum.Material.Metal, Enum.PartType.Cylinder)
	part(stand, "Collar", Vector3.new(0.2, 0.8, 0.8), CFrame.lookAt(postP + zv * 0.35, postP + zv) * CFrame.Angles(0, math.pi / 2, 0),
		steel, Enum.Material.Metal, Enum.PartType.Cylinder)
	settle(stand)

	-- lamp over the wheel: in front of it and just above, so it lights the face
	-- and peeks in at the top of the frame without covering the tyre
	self.lamps = {}
	local main = hangLamp(folder, "MainLamp", pos(0.9, top + 6.1, -3.0), centreW, 0.75, ceiling)
	main.spot.Angle = 62
	main.spot.Range = 26
	main.spot.Brightness = LAMP_BRIGHT
	table.insert(self.lamps, main)
	self.mainLamp = main
	self.spot = main.spot
	self.bulb = main.bulb

	-- dim warm fill from behind the camera, cool rim from the back right
	local fill = part(folder, "Fill", Vector3.new(0.2, 0.2, 0.2), at(-4, 9, 6), WARM, Enum.Material.SmoothPlastic)
	fill.Transparency = 1
	fill.CastShadow = false
	local fl = Instance.new("PointLight")
	fl.Brightness = 0.3
	fl.Range = 22
	fl.Color = Color3.fromRGB(255, 226, 196)
	fl.Shadows = false
	fl.Parent = fill
	local rimPos = pos(8, 11, -9.4)
	local rimEm = part(folder, "RimLight", Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(rimPos, centreW), COOL, Enum.Material.SmoothPlastic)
	rimEm.Transparency = 1
	rimEm.CastShadow = false
	local rim = Instance.new("SpotLight")
	rim.Face = Enum.NormalId.Front
	rim.Angle = 36
	rim.Range = 18
	rim.Brightness = 2.2
	rim.Color = COOL
	rim.Shadows = false
	rim.Parent = rimEm

	-- your models, sized and set down on the floor (or on baseY) at room (x, z)
	local function dressTpl(tpl: Instance?, name: string, x: number, z: number, yaw: number, size: { [string]: number }, baseY: number?): Model?
		if not tpl then return nil end
		local mdl: Model
		if tpl:IsA("BasePart") then
			mdl = Instance.new("Model")
			local p = tpl:Clone()
			p.Parent = mdl
			mdl.WorldPivot = CFrame.new(p.Position - Vector3.new(0, p.Size.Y / 2, 0))
		elseif tpl:IsA("Model") then
			mdl = tpl:Clone()
		else
			return nil
		end
		mdl.Name = name
		for _, d in ipairs(mdl:GetDescendants()) do
			if d:IsA("Seat") or d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("Camera") or d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		settle(mdl)
		local _, s0 = mdl:GetBoundingBox()
		local k = (size.height and size.height / s0.Y)
			or (size.width and size.width / math.max(s0.X, s0.Z))
			or (size.length and size.length / math.max(s0.X, s0.Y, s0.Z)) or 1
		if math.abs(k - 1) > 0.001 then mdl:ScaleTo(mdl:GetScale() * k) end
		mdl:PivotTo(CFrame.new(mdl:GetPivot().Position) * CFrame.Angles(0, yaw, 0))
		local bb, s = mdl:GetBoundingBox()
		local target = pos(x, baseY or 0, z)
		mdl:PivotTo(mdl:GetPivot() + Vector3.new(target.X - bb.Position.X, target.Y - (bb.Position.Y - s.Y / 2), target.Z - bb.Position.Z))
		mdl.Parent = folder
		return mdl
	end
	local function dress(name: string, x: number, z: number, yaw: number, size: { [string]: number }, baseY: number?): Model?
		return dressTpl(Assets.Workshop:FindFirstChild(name), name, x, z, yaw, size, baseY)
	end

	-- the anvil sits on a tree stump, clear of the bench end at x 9.6
	local stump = dress("TreeStump", ANVIL_X, -6.2, 0, { width = 3.4 })
	local stumpTop = 0
	if stump then
		local sbb, ss = stump:GetBoundingBox()
		stumpTop = (sbb.Position.Y + ss.Y / 2) - origin.Y - 0.05
	end
	local anvil = Assets.Workshop.Anvil:Clone()
	anvil:ScaleTo(anvil:GetScale() * ANVIL_SCALE)
	local _, asize = anvil:GetBoundingBox()
	anvil:PivotTo(at(ANVIL_X, stumpTop + asize.Y / 2, -6.2))
	settle(anvil)
	anvil.Parent = folder
	self.anvil = anvil
	local anvilTop = stumpTop + asize.Y
	self.anvilTop = anvilTop
	self.strikePoint = pos(ANVIL_X - 0.35 * ANVIL_SCALE, anvilTop + 0.02, -6.2)

	-- the smithy corner: furnace behind, quench bucket in front, tongs leaning on the stump
	local furnace = dress("Furnace", ANVIL_X + 8.6, -7.6, math.rad(43), { height = 10 })
	-- the mouth is an arch in the side the furnace mesh faces: 2.3 out from the middle at
	-- this size, its floor 1.25 under half height. Work goes in along `out`.
	local body = furnace and furnace:FindFirstChild("Furnace") :: BasePart?
	if furnace and body then
		local fcf, fs = furnace:GetBoundingBox()
		local look = body.CFrame.LookVector
		local out = Vector3.new(look.X, 0, look.Z).Unit
		local k = fs.Y / 10
		self.furnace = {
			centre = fcf.Position,
			out = out,
			mouth = fcf.Position + out * (2.3 * k) - Vector3.new(0, 0.2 * k, 0),
			floorY = fcf.Position.Y - 1.25 * k,
			lip = 2.3 * k,
			top = fcf.Position + Vector3.new(0, fs.Y / 2, 0),
		}
		-- a warm work light on the furnace face, like the anvil lamp, so the corner reads
		-- while you're at the anvil and brightens while something is in the fire
		local lightAt = self.furnace.mouth + out * (3.5 * k) + Vector3.new(0, 5.5 * k, 0)
		local fem = part(folder, "FurnaceLight", Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(lightAt, self.furnace.mouth - Vector3.new(0, 0.5 * k, 0)), WARM, Enum.Material.SmoothPlastic)
		fem.Transparency = 1
		fem.CastShadow = false
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 70
		spot.Range = 16 * k
		spot.Brightness = 0
		spot.Color = WARM
		spot.Shadows = true
		spot.Parent = fem
		self.furnaceSpot = spot
	end
	local bucket = dress("QuenchBucket", ANVIL_X + 4.8, -2.4, 0, { height = 2.2 })
	if bucket then
		local bb, s = bucket:GetBoundingBox()
		self.quenchTop = bb.Position + Vector3.new(0, s.Y / 2, 0)
	end
	-- long enough, and so thick enough, to read in the dim light while they carry things
	local tongs = dress("Tongs", ANVIL_X - 2.1, -4.1, 0, { length = 4.8 })
	if tongs then
		tongs:PivotTo(tongs:GetPivot() * CFrame.Angles(0, 0, math.rad(-14)))
		self.tongs = tongs
		self.tongsRest = tongs:GetPivot()
		-- where the jaw tips meet, in the tongs' own frame: the lowest bit of each arm (the
		-- arms sit apart along Z). The forge holds things by this point.
		local piv = tongs:GetPivot()
		local parts = {}
		for _, d in ipairs(tongs:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(parts, piv:PointToObjectSpace(d.Position)) end
		end
		table.sort(parts, function(x, y) return x.Y < y.Y end)
		local tipA = parts[1]
		local tipB = nil
		for i = 2, #parts do
			if tipA and math.abs(parts[i].Z - tipA.Z) > 0.12 then tipB = parts[i] break end
		end
		self.tongsJaw = tipA and (tipB and (tipA + tipB) / 2 or tipA) or Vector3.zero
	end
	dress("Shelves", -15, -8.6, math.rad(18), { height = 9 })
	local props = Assets:FindFirstChild("World") and Assets.World:FindFirstChild("Props")
	dressTpl(props and props:FindFirstChild("OilDrum_2"), "OilDrum", 12.0, -10.1, math.rad(15), { height = 5.4 })

	local hammer = (Assets.Workshop.Hammer :: BasePart):Clone()
	hammer.Size *= HAMMER_SCALE
	hammer.Anchored = true
	hammer.CanCollide = false
	hammer.CanQuery = false
	hammer.CanTouch = false
	hammer.CastShadow = true
	hammer.CFrame = CFrame.new(pos(7.2, top + hammer.Size.Z / 2, -6.9)) * CFrame.Angles(0, math.rad(25), 0)
		* CFrame.Angles(0, 0, -math.pi / 2) * CFrame.Angles(0, math.pi / 2, 0)
	hammer.Parent = folder
	self.hammer = hammer
	self.hammerRest = hammer.CFrame

	local anvilLamp = hangLamp(folder, "AnvilLamp", pos(ANVIL_X - 0.6, anvilTop + 5.4, -4.8), self.strikePoint, 0.55, ceiling)
	anvilLamp.spot.Angle = 55
	anvilLamp.spot.Range = 18
	anvilLamp.spot.Brightness = 0
	table.insert(self.lamps, anvilLamp)
	self.anvilLampRig = anvilLamp
	self.anvilSpot = anvilLamp.spot
	self.anvilBulb = anvilLamp.bulb

	-- dust hanging in the lamp light (PLACEHOLDER)
	local motes = part(folder, "Motes", Vector3.new(6, 6, 6), CFrame.new((main.shade.Position + centreW) / 2), WARM, Enum.Material.SmoothPlastic)
	motes.Transparency = 1
	motes.CastShadow = false
	local pe = Instance.new("ParticleEmitter")
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pe.Rate = 9
	pe.Lifetime = NumberRange.new(6, 10)
	pe.Speed = NumberRange.new(0.05, 0.22)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new(0.045)
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.45),
		NumberSequenceKeypoint.new(0.8, 0.45), NumberSequenceKeypoint.new(1, 1),
	})
	pe.LightInfluence = 1
	pe.LightEmission = 0.2
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 236, 210))
	pe.Acceleration = Vector3.new(0, -0.01, 0)
	pe.RotSpeed = NumberRange.new(-20, 20)
	local glowTex = texture("glow")
	if glowTex then pe.Texture = glowTex end
	pe.Parent = motes

	-- light rays for legendary moments, from the lamp to the wheel
	local rayTex = texture("light ray") or texture("light rays")
	local target = part(folder, "RayTarget", Vector3.new(0.2, 0.2, 0.2), CFrame.new(centreW - Vector3.new(0, WHEEL_R * 0.8, 0)), WARM, Enum.Material.SmoothPlastic)
	target.Transparency = 1
	target.CastShadow = false
	local ra0 = Instance.new("Attachment")
	ra0.Parent = main.emitter
	local ra1 = Instance.new("Attachment")
	ra1.Parent = target
	self.rays = {}
	for i = 1, 2 do
		local b = Instance.new("Beam")
		b.Attachment0 = ra0
		b.Attachment1 = ra1
		b.Width0 = 0.6
		b.Width1 = i == 1 and 6.5 or 4.2
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		b.Color = ColorSequence.new(WARM)
		if rayTex then
			b.Texture = rayTex
			b.TextureMode = Enum.TextureMode.Stretch
			b.TextureSpeed = i == 1 and 0.08 or -0.05
		end
		b.Enabled = false
		b.Parent = main.emitter
		table.insert(self.rays, b)
	end

	-- the parts wall: a pegboard down the left wall, lit by its own lamp when you look at it
	do
		local board = part(folder, "Pegboard", Vector3.new(0.3, 13, 30), at(-35.3, 11.5, 8), Color3.fromRGB(96, 76, 54), Enum.Material.Cardboard)
		board.CastShadow = false
		local sg = Instance.new("SurfaceGui")
		sg.Name = "Holes"
		sg.Face = Enum.NormalId.Right
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 20
		sg.LightInfluence = 1
		sg.Parent = board
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(4, 4)
		grid.CellPadding = UDim2.fromOffset(21, 21)
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
		grid.VerticalAlignment = Enum.VerticalAlignment.Center
		grid.Parent = sg
		for _ = 1, 24 * 10 do
			local hole = Instance.new("Frame")
			hole.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
			hole.BackgroundTransparency = 0.25
			hole.BorderSizePixel = 0
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = hole
			hole.Parent = sg
		end
		-- a steel batten along the top and bottom edges
		part(folder, "BattenTop", Vector3.new(0.4, 0.35, 30.4), at(-35.15, 18.1, 8), Color3.fromRGB(58, 60, 64), Enum.Material.Metal)
		part(folder, "BattenBottom", Vector3.new(0.4, 0.35, 30.4), at(-35.15, 4.9, 8), Color3.fromRGB(58, 60, 64), Enum.Material.Metal)
		self.wall = { x = origin.X - 35.15, z = origin.Z + 8, top = origin.Y + 18, width = 30 }
		local lampPos = pos(-20, 22, 8)
		local em = part(folder, "WallLight", Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(lampPos, pos(-35, 10.5, 8)), WARM, Enum.Material.SmoothPlastic)
		em.Transparency = 1
		em.CastShadow = false
		local ws = Instance.new("SpotLight")
		ws.Face = Enum.NormalId.Front
		ws.Angle = 90
		ws.Range = 40
		ws.Brightness = 0
		ws.Color = WARM
		ws.Shadows = true
		ws.Parent = em
		self.wallSpot = ws
	end

	-- camera stations: slightly under the work and tilted up at it
	local function station(eye: Vector3, look: Vector3, fov: number, focus: Vector3)
		return { cf = CFrame.lookAt(eye, look), fov = fov, focus = focus, look = look }
	end
	self.stations = {
		Fit = station(pos(-1.8, top + 0.6, 8.3), pos(0, top + 1.3, -7.3), 42, centreW),
		Stickers = station(pos(-0.8, centreY - 1.1, 3.5), pos(0, centreY - 0.85, -7.3), 42, centreW),
		Retread = station(pos(ANVIL_X - 3.4, anvilTop + 3.4, 3.2), self.strikePoint - Vector3.new(0, 0.6, 0), 44, self.strikePoint),
		Wall = station(pos(-18.6, 12.4, 8), pos(-35.15, 12.3, 8), 46, pos(-35.15, 12.3, 8)),
	}
	-- boxes the camera stays out of, so no shot or move ever ends up inside a prop
	self.solids = {}
	for _, n in ipairs({ "Furnace", "QuenchBucket", "Anvil", "TreeStump", "OilDrum", "Shelves", "Bench" }) do
		local m = folder:FindFirstChild(n)
		if m and m:IsA("Model") then
			local cf, s = m:GetBoundingBox()
			table.insert(self.solids, { cf = cf, half = s / 2 })
		end
	end
	self.wallLevel = 0
	self.wallGoal = 0

	-- lamp state
	self.color = WARM
	self.tint = WARM
	self.tintHold = 0
	self.flicker = 0
	self.kick = 0
	self.raysOn = false
	self.mainLevel = LAMP_BRIGHT
	self.mainGoal = LAMP_BRIGHT
	self.anvilLevel = 0
	self.anvilGoal = 0
	self.fireLevel = 0
	self.fireGoal = 0
	self.swingT = 99
	self.swingAmp = 0
	return self
end

--==============================================================
function Room:focus(station: string)
	self.mainGoal = (station == "Retread" or station == "Wall") and 1.6 or LAMP_BRIGHT
	self.anvilGoal = station == "Retread" and 6 or 0
	self.fireGoal = station == "Retread" and 2 or 0
	self.wallGoal = station == "Wall" and 5 or 0
end

-- every lamp straight to where its station wants it, with no fade: used behind the
-- shutter so the room is never caught half-lit when the door lifts
function Room:snap()
	self.mainLevel = self.mainGoal
	self.anvilLevel = self.anvilGoal
	self.fireLevel = self.fireGoal or 0
	self.wallLevel = self.wallGoal or 0
	self.color = WARM
	self.tint = WARM
	self.tintHold = 0
	self.flicker = 0
	self.kick = 0
	self:step(0)
end

-- a nudge to the lamps: 1 is the swing you get when the workbench opens
function Room:swing(strength: number)
	self.swingT = 0
	self.swingAmp = 3.5 * strength
end

-- Rare and up changes the colour of the light; everyday parts just swell it
function Room:celebrate(tier: string?, big: boolean?)
	local colors = {
		Rare = Config.TierColor("Rare"),
		Epic = Config.TierColor("Epic"),
		Legendary = Config.TierColor("Legendary"),
		Premium = Config.PremiumColor,
	}
	local c = tier and colors[tier]
	if not c then
		self.kick = big and 1 or 0.6
		return
	end
	local level = (tier == "Rare" and 1) or (tier == "Epic" and 2) or 3
	self:pulse(c, level, self.wheelCentre)
end

function Room:pulse(_color: Color3, level: number, _at: Vector3?)
	self.kick = math.min(1, 0.4 + level * 0.2)
	self:swing(0.35 + level * 0.2)
end

function Room:step(dt: number)
	-- swing
	self.swingT += dt
	local amp = math.rad(self.swingAmp) * math.exp(-self.swingT / 2.6)
	local idle = math.rad(0.35)
	local now = os.clock()
	for i, lamp in ipairs(self.lamps) do
		local w = lamp.omega
		local k = i == 1 and 1 or 0.5
		-- the open swing runs sideways along the bench (rotation about Z moves the
		-- shade along X); only a little of it goes toward or away from the tyre
		local az = (amp * math.sin(self.swingT * w) + idle * math.sin(now * w * 0.5 + lamp.phase)) * k
		local ax = (amp * 0.2 * math.sin(self.swingT * w * 1.07 + 1.2) + idle * 0.4 * math.cos(now * w * 0.43 + lamp.phase)) * k
		local P = lamp.pivot
		local rot = CFrame.new(P) * CFrame.Angles(ax, 0, az) * CFrame.new(-P)
		for p, rest in pairs(lamp.rest) do
			p.CFrame = rot * rest
		end
	end

	-- colour, flicker, brightness
	local holding = self.tintHold > 0
	if holding then self.tintHold -= dt end
	local want = holding and self.tint or WARM
	self.color = self.color:Lerp(want, 1 - math.exp(-dt * (holding and 6 or 1.6)))
	self.kick = math.max(0, self.kick - dt * 1.5)
	local flick = 1
	if self.flicker > 0 then
		self.flicker -= dt
		flick = math.noise(now * 38, 0.3) > -0.05 and 1 or 0.25
	end
	self.mainLevel += (self.mainGoal - self.mainLevel) * (1 - math.exp(-dt * 3))
	self.anvilLevel += (self.anvilGoal - self.anvilLevel) * (1 - math.exp(-dt * 3))
	self.wallLevel += ((self.wallGoal or 0) - (self.wallLevel or 0)) * (1 - math.exp(-dt * 3))
	if self.wallSpot then self.wallSpot.Brightness = self.wallLevel * flick end
	self.fireLevel = (self.fireLevel or 0) + ((self.fireGoal or 0) - (self.fireLevel or 0)) * (1 - math.exp(-dt * 4))
	if self.furnaceSpot then self.furnaceSpot.Brightness = self.fireLevel * flick end
	local swell = self.kick * 2 + (holding and 1.5 or 0)
	local main, anvil = self.mainLamp, self.anvilLampRig
	main.spot.Color = self.color
	main.spot.Brightness = (self.mainLevel + swell) * flick
	main.bulb.Color = self.color
	main.bulb.Transparency = flick < 1 and 0.6 or 0
	if main.glow then
		main.glow.Color = self.color
		main.glow.Brightness = 1.6 * flick * (self.mainLevel / LAMP_BRIGHT)
	end
	anvil.spot.Color = self.color
	anvil.spot.Brightness = (self.anvilLevel + (self.anvilGoal > 0 and swell or 0)) * flick
	anvil.bulb.Transparency = self.anvilLevel < 0.3 and 0.85 or 0
	anvil.bulb.Color = self.color
	if anvil.glow then
		anvil.glow.Color = self.color
		anvil.glow.Brightness = 1.2 * math.clamp(self.anvilLevel / 6, 0, 1) * flick
	end
	local rays = holding and self.raysOn
	for _, b in ipairs(self.rays) do
		b.Enabled = rays
		if rays then b.Color = ColorSequence.new(self.color) end
	end
end

return Room
