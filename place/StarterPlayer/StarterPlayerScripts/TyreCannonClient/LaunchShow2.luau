--!strict
-- TYRE CANNON :: LaunchShow2
-- The launch at your cannon, shot like a cutscene:
--   1 a dip from black onto a wide shot that eases into a low three-quarter hero shot, the barrel
--     up against the sky
--   2 your tyre is lobbed into the muzzle; it lands with a clunk and the barrel dips under it
--   3 while the dial runs the camera creeps in, the barrel shudders harder and the breech vents steam
--   4 the shot: a beat of stillness, then flame and a cone of smoke out of the muzzle, a smoke ring,
--     dust thrown off the ground, recoil, shake and an FOV punch. A PERFECT holds in slow motion.
--   5 a cut to a chase camera behind the tyre climbing into the sky on a smoke trail, and the sky
--     washes over the screen into the run
-- Plot signs, level plates and your character are hidden for it, and the yard is lit for the
-- afternoon whatever the clock says. Every emitter is built when the show starts, so nothing loads
-- at the shot.
-- The launch tells you how it went before the tyre leaves, like a summon: every shift of Rev & Shift
-- (LaunchTap) lands on the cannon (shift: a perfect throws gold sparks, the second lights flame
-- round the muzzle; a good one vents; a miss coughs black smoke), and the grade sets the build-up
-- before the shot (release): PERFECT charges for a second in gold (sparks pouring, the glow
-- swelling, the camera drawn in, a gold flash, the long slow-motion), GREAT half that in green,
-- GOOD a breath, WEAK straight out and short.
-- Same shape as LaunchShow, so Main can use either: new / takeCamera / pullLever / waitReady /
-- shift / release / destroy.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local PackFX = require(script.Parent:WaitForChild("PackFX"))
local Models = require(script.Parent:WaitForChild("Models"))
local Sound = require(script.Parent:WaitForChild("Sound"))
local TyreLook = require(script.Parent:WaitForChild("TyreLook"))
local DayNight = require(script.Parent:WaitForChild("DayNight"))
local MuzzleFX = require(script.Parent:WaitForChild("MuzzleFX"))

local LaunchShow2 = {}
LaunchShow2.__index = LaunchShow2

local TYRE_D = 7.4
local SMOKE = Color3.fromRGB(226, 222, 214)
local SKY = Color3.fromRGB(222, 236, 250)
local GRAVITY = Vector3.new(0, -60, 0)

-- the timeline, in show seconds
local LOB_START, LOB_END = 0.55, 0.98	-- the tyre's flight into the muzzle
local READY_AT = 1.5					-- the dial can come up
local CHASE_AT = 0.42					-- after the shot: cut to the chase camera
local WASH_AT, WASH_LEN = 0.92, 0.26	-- after the shot: the sky takes the screen
-- the build-up before the shot, by launch grade: how long, and its colour
local CHARGE = { perfect = 1.05, great = 0.55, good = 0.15, weak = 0 }
local GLOW = {
	perfect = Color3.fromRGB(255, 206, 84), great = Color3.fromRGB(96, 236, 128),
	good = Color3.fromRGB(255, 240, 214), weak = Color3.fromRGB(255, 160, 120),
}

-- low and out in front, between the ramp and the machines on that side, looking up into the muzzle
local HERO = Vector3.new(1.4, -0.08, 0.66)	-- the camera from the cannon's middle, in cannon sizes: along the lane, up, out to the side
local LOOK = Vector3.new(0.3, 0.04, 0)			-- what it looks at, the same way
local FOV = 64
-- the gunner's seat the camera creeps into as the shifts land: well behind the breech and above the
-- bore, a little to one side so the barrel is seen at an angle (in cannon sizes: back, up, out)
local GUNNER = Vector3.new(0.62, 0.34, 0.22)

local function tuned(name: string, default: any): any
	if RunService:IsStudio() then
		local v = workspace:GetAttribute(name)
		if v ~= nil then return v end
	end
	return default
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function ns(list: { { number } }): NumberSequence
	local k = {}
	for _, p in ipairs(list) do table.insert(k, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(k)
end


-- a switched-off emitter from one of the packs' 4x4 sheets
local function emitter(parent: Instance, sheet: string, props: { [string]: any }): ParticleEmitter
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

local function holder(name: string, cf: CFrame): (Part, Attachment)
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

-- the Blender cannon in the yard, its muzzle and the way the bore points
local function aim(cannon: Model, scale: number): (Model?, Vector3?, Vector3?, Vector3?)
	for _, child in ipairs(cannon:GetChildren()) do
		if child:IsA("Model") then
			local info = Models.info(child.Name) :: any
			if info and info.muzzle and info.elev then
				local pivot = child:GetPivot()
				local m = info.muzzle
				local muzzle = pivot * (Models.toRoblox(m[1], m[2], m[3]) * scale)
				local e = math.rad(info.elev)
				local dir = pivot:VectorToWorldSpace(Vector3.new(math.cos(e), math.sin(e), 0))
				-- the racing cannon names its trunnion (the barrel tilts round it)
				local t = info.pivot
				local trunnion = t and pivot * (Models.toRoblox(t[1], t[2], t[3]) * scale) or nil
				return child, muzzle, dir.Unit, trunnion
			end
		end
	end
	return nil, nil, nil
end

function LaunchShow2.new(_skinId: string?, plot: Instance?, cannon: Model?, scale: number?, tyreId: string?)
	if not (plot and cannon) then return nil end
	local base = plot:GetAttribute("BaseCFrame") :: CFrame?
	if not base then return nil end
	local model, muzzle, dir, pinned = aim(cannon, scale or 1)
	if not (model and muzzle and dir) then return nil end
	local self = setmetatable({}, LaunchShow2)
	self.plot = plot
	self.muzzle, self.dir = muzzle, dir
	local cf, size = model:GetBoundingBox()
	self.mid = cf.Position
	self.S = math.max(size.X, size.Y, size.Z)
	self.ground = cf.Position.Y - size.Y / 2
	self.fwd = Vector3.new(dir.X, 0, dir.Z).Unit
	-- the camera's side of the lane, whichever way the yard's launcher faces
	self.side = Vector3.yAxis:Cross(self.fwd)
	self.cannonModel = cannon
	self.axle = dir:Cross(Vector3.yAxis).Unit
	self.up = self.axle:Cross(dir)
	-- the barrel and everything bolted to it, turning about the middle of the barrel
	self.barrel = {}
	local trunnion = self.mid
	for _, d in ipairs(cannon:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:sub(1, 6) == "Barrel" then
			table.insert(self.barrel, { part = d, rest = d.CFrame })
			if d.Name == "Barrel" then trunnion = d.Position end
		end
	end
	self.trunnion = pinned or trunnion
	self.breech = trunnion - (muzzle - trunnion) * 0.85

	-- your tyre, lobbed in from above the muzzle
	self.tyre = TyreLook.model(tyreId, TYRE_D, "ShowTyre")
	for _, d in ipairs(self.tyre:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = true
		end
	end
	self.seat = muzzle - dir * (TYRE_D * 0.4)
	self.ramp = nil   -- (no launch ramp any more: the cannon fires straight out of its own barrel)
	self.lobFrom = self.seat + dir * 9 + Vector3.new(0, 26, 0) - self.side * 2
	self.spin = 0
	self:placeTyre(self.lobFrom, 0)
	self.tyre.Parent = workspace
	self:buildFX()

	self.camera = workspace.CurrentCamera
	self.savedCam = self.camera.CameraType
	self.savedFov = self.camera.FieldOfView
	self.stage = "load"
	self.t = 0
	self.slow = 1
	self.rumble = 0
	self.shake = 0
	self.fovKick = 0
	self.pitch, self.push = 0, 0
	self:hideClutter(true)
	self:light(true)
	self:cover(0, 1, nil, 0.45)
	self.conn = RunService.RenderStepped:Connect(function(dt) self:step(dt) end)
	return self
end

local function bez(a: Vector3, b: Vector3, c: Vector3, u: number): Vector3
	return a:Lerp(b, u):Lerp(b:Lerp(c, u), u)
end

-- everything the shot throws, built now so nothing loads at the moment it fires
function LaunchShow2:buildFX()
	local fx = {}
	self.fx = fx
	local mcf = CFrame.lookAt(self.muzzle, self.muzzle + self.dir)
	local muzzlePart, att = holder("LaunchMuzzle", mcf)
	local _, breechAtt = holder("LaunchBreech", CFrame.lookAt(self.breech, self.breech + Vector3.yAxis))
	local _, footAtt = holder("LaunchFoot", CFrame.new(self.mid.X, self.ground + 0.6, self.mid.Z))
	self.parts = { muzzlePart, breechAtt.Parent, footAtt.Parent }
	local S = PackFX.Sheet
	-- the blast itself (flame, smoke cone, smoke ring, the cloud after) is shared with the title's cannon
	self.blast = MuzzleFX.new(self.muzzle, self.dir)
	for k, e in pairs(self.blast.fx) do fx["blast_" .. k] = e end
	fx.puff = emitter(att, S.steam, {
		EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(0.45, 0.7), Speed = NumberRange.new(5, 11),
		Drag = 3, SpreadAngle = Vector2.new(60, 60), Size = ns({ { 0, 1.5 }, { 1, 5 } }),
		Transparency = ns({ { 0, 0.3 }, { 1, 1 } }), Color = ColorSequence.new(Color3.fromRGB(214, 200, 178)),
	})
	fx.steam = emitter(breechAtt, S.steam, {
		EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(0.7, 1.1), Speed = NumberRange.new(5, 11),
		Drag = 1, SpreadAngle = Vector2.new(22, 22), Size = ns({ { 0, 1.4 }, { 1, 6 } }),
		Transparency = ns({ { 0, 0.4 }, { 1, 1 } }), Color = ColorSequence.new(Color3.fromRGB(244, 244, 242)),
		Acceleration = Vector3.new(0, 4, 0),
	})
	fx.sparks = emitter(att, "rbxasset://textures/particles/sparkles_main.dds", {
		EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(18, 42),
		Drag = 2, SpreadAngle = Vector2.new(75, 75), Size = ns({ { 0, 0.9 }, { 1, 0 } }), Transparency = ns({ { 0, 0 }, { 1, 0.4 } }),
		Color = ColorSequence.new(Color3.fromRGB(255, 226, 120), Color3.fromRGB(255, 150, 40)), LightEmission = 1, LightInfluence = 0,
		Acceleration = Vector3.new(0, -40, 0), FlipbookLayout = Enum.ParticleFlipbookLayout.None,
	})
	fx.flare = emitter(att, S.flame, {
		EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(0.3, 0.45), Speed = NumberRange.new(2, 7),
		SpreadAngle = Vector2.new(180, 180), Size = ns({ { 0, 2.2 }, { 0.5, 4.2 }, { 1, 2 } }), Transparency = ns({ { 0, 0.1 }, { 1, 1 } }),
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 120, 40)), LightEmission = 0.7, LightInfluence = 0.2,
	})
	self.glow = Instance.new("PointLight")
	self.glow.Range = 16
	self.glow.Brightness = 0
	self.glow.Shadows = false
	self.glow.Parent = muzzlePart
	self.glowLevel = 0
	fx.dust = emitter(footAtt, S.plume, {
		EmissionDirection = Enum.NormalId.Top, Lifetime = NumberRange.new(1, 1.5), Speed = NumberRange.new(24, 42),
		Drag = 3.2, SpreadAngle = Vector2.new(86, 86), Size = ns({ { 0, 3 }, { 1, 12 } }),
		Transparency = ns({ { 0, 0.3 }, { 1, 1 } }), Color = ColorSequence.new(Color3.fromRGB(198, 178, 148)),
		Acceleration = Vector3.new(0, 1, 0),
	})
	-- the tyre's smoke trail, laid down evenly along its path a puff at a time
	local trailPart, trailAtt = holder("LaunchTrail", mcf)
	table.insert(self.parts, trailPart)
	self.trailAtt = trailAtt
	fx.trail = emitter(trailAtt, S.plume, {
		EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(0.9, 1.3), Speed = NumberRange.new(0, 2),
		Drag = 1, SpreadAngle = Vector2.new(180, 180), Size = ns({ { 0, 2.8 }, { 1, 9 } }),
		Transparency = ns({ { 0, 0.18 }, { 1, 1 } }), RotSpeed = NumberRange.new(-30, 30), Color = ColorSequence.new(SMOKE),
	})
end

-- plot signs, level plates, your character and the yard's own launch tyre: out of the shot
function LaunchShow2:hideClutter(on: boolean)
	if not on then
		for _, gui in ipairs(self.hidden or {}) do
			if gui.Parent then gui.Enabled = true end
		end
		for _, e in ipairs(self.faded or {}) do
			if e[1].Parent then e[1].LocalTransparencyModifier = e[2] end
		end
		self.hidden, self.faded = {}, {}
		return
	end
	local hidden, faded = {}, {}
	self.hidden, self.faded = hidden, faded
	local lp = Players.LocalPlayer
	local function off(gui: Instance)
		if (gui:IsA("BillboardGui") or gui:IsA("SurfaceGui")) and gui.Enabled then
			gui.Enabled = false
			table.insert(hidden, gui)
		end
	end
	for _, d in ipairs(lp.PlayerGui:GetDescendants()) do
		if d:IsA("BillboardGui") then off(d) end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BillboardGui") then off(d) end
	end
	local function fade(m: Instance?)
		if not m then return end
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") and p.LocalTransparencyModifier < 1 then
				table.insert(faded, { p, p.LocalTransparencyModifier })
				p.LocalTransparencyModifier = 1
			elseif p:IsA("SurfaceGui") then
				off(p)
			end
		end
	end
	local machines = self.plot:FindFirstChild("Machines2")
	if machines then
		for _, d in ipairs(machines:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name == "LevelPlate" or d.Name == "PlatePost") and d.LocalTransparencyModifier < 1 then
				table.insert(faded, { d, d.LocalTransparencyModifier })
				d.LocalTransparencyModifier = 1
				local sg = d:FindFirstChildOfClass("SurfaceGui")
				if sg then off(sg) end
			end
		end
	end
	fade(self.plot:FindFirstChild("LaunchTyre"))
	fade(lp.Character)
	self:clearView(faded)
end

-- anything on the yard between the camera and the cannon, or right up against the lens, fades for
-- the shot: a machine goes as a whole, a fence rail on its own
function LaunchShow2:clearView(faded: { any })
	local plot = self.plot
	local cams = { self:at(tuned("ShowHero", HERO)) }
	local look = self:at(tuned("ShowLook", LOOK))
	-- the crane down from above, sampled
	local wide = cams[1] + (cams[1] - look).Unit * (self.S * 0.2) + Vector3.new(0, self.S * 0.6, 0)
	table.insert(cams, cams[1]:Lerp(wide, 0.5))
	table.insert(cams, wide)
	local targets = { self.muzzle, self.mid, self.mid + self.side * (self.S * 0.2), Vector3.new(self.mid.X, self.ground + 1, self.mid.Z) }
	-- the gunner's seat, and the line down the barrel
	local g, glook = self:gunner()
	table.insert(cams, g)
	table.insert(targets, glook)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { plot }
	local gone: { [Instance]: boolean } = {}
	local function hide(part: BasePart)
		-- never the floor or anything slab-sized
		if part.Name:sub(1, 5) == "Floor" or part.Size.Magnitude > 60 then return end
		-- the whole machine or station it belongs to, or just this part
		local node: Instance = part
		while node.Parent and node.Parent ~= plot and node.Parent.Name ~= "Machines2" do
			node = node.Parent
		end
		local whole = node.Parent ~= nil and node ~= part and node:IsA("Model")
		if whole and (node == self.cannonModel or node:IsDescendantOf(self.cannonModel)) then return end
		if part:IsDescendantOf(self.cannonModel) then return end
		local list = whole and node:GetDescendants() or { part }
		if gone[node] then return end
		gone[node] = true
		for _, d in ipairs(list) do
			if d:IsA("BasePart") and d.LocalTransparencyModifier < 1 then
				table.insert(faded, { d, d.LocalTransparencyModifier })
				d.LocalTransparencyModifier = 1
			end
		end
	end
	for _, c in ipairs(cams) do
		for _, t in ipairs(targets) do
			local from = c
			for _ = 1, 4 do
				local hit = workspace:Raycast(from, t - from, params)
				if not hit then break end
				local p = hit.Instance
				if p:IsDescendantOf(self.cannonModel) then break end
				hide(p :: BasePart)
				from = hit.Position + (t - from).Unit * 0.05
			end
		end
		local near = OverlapParams.new()
		near.FilterType = Enum.RaycastFilterType.Include
		near.FilterDescendantsInstances = { plot }
		for _, p in ipairs(workspace:GetPartBoundsInRadius(c, 6, near)) do
			if not p:IsDescendantOf(self.cannonModel) then hide(p) end
		end
	end
	-- decor can't be hit by a ray (its parts aren't queryable): a piece whose box crosses a sight line,
	-- or stands near the lens, fades as a whole
	local decor = plot:FindFirstChild("Decor2")
	if decor then
		for _, m in ipairs(decor:GetChildren()) do
			if m:IsA("Model") then
				local cf, size = m:GetBoundingBox()
				local half = size / 2 + Vector3.new(1, 1, 1)
				local blocks = false
				for _, c in ipairs(cams) do
					if blocks then break end
					for _, t in ipairs(targets) do
						for k = 0, 20 do
							local q = cf:PointToObjectSpace(c:Lerp(t, k / 20))
							if math.abs(q.X) <= half.X and math.abs(q.Y) <= half.Y and math.abs(q.Z) <= half.Z then
								blocks = true
								break
							end
						end
						if blocks then break end
					end
					if (cf.Position - c).Magnitude < size.Magnitude / 2 + 8 then blocks = true end
				end
				if blocks then
					for _, d in ipairs(m:GetDescendants()) do
						if d:IsA("BasePart") and d.LocalTransparencyModifier < 1 then
							table.insert(faded, { d, d.LocalTransparencyModifier })
							d.LocalTransparencyModifier = 1
						end
					end
				end
			end
		end
	end
end

-- the shot takes the yard as it is: the server's time of day, its lamps if it's dark, the street
-- behind. Only a touch of contrast is added.
function LaunchShow2:light(on: boolean)
	if on then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "LaunchGrade"
		cc.Contrast = 0.06
		cc.Saturation = 0.05
		cc.Parent = Lighting
		self.gradeFx = cc
	else
		if self.gradeFx then self.gradeFx:Destroy() end
	end
	local _ = DayNight
end

-- a full-screen colour over everything, faded from `from` to `to` transparency
function LaunchShow2:cover(from: number, to: number, colour: Color3?, time: number?)
	local f = self.coverFrame
	if not f then
		local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not pg then return end
		local sg = Instance.new("ScreenGui")
		sg.Name = "LaunchCover"
		sg.IgnoreGuiInset = true
		sg.DisplayOrder = 60
		sg.ResetOnSpawn = false
		f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BorderSizePixel = 0
		f.Parent = sg
		sg.Parent = pg
		self.coverGui, self.coverFrame = sg, f
	end
	local frame = f :: Frame
	frame.BackgroundColor3 = colour or Color3.new(0, 0, 0)
	frame.BackgroundTransparency = from
	TweenService:Create(frame, TweenInfo.new(time or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = to }):Play()
end

-- the tyre's axle runs across the lane; it rolls about it
function LaunchShow2:placeTyre(pos: Vector3, spin: number)
	self.tyre:PivotTo(CFrame.fromMatrix(pos, self.dir, self.up, self.axle) * CFrame.Angles(0, 0, spin))
end

-- the barrel pushed back along the bore, tipped about the trunnion, and shaken
function LaunchShow2:poseBarrel(back: number, pitch: number, jitter: number)
	local turn = CFrame.new(self.trunnion) * CFrame.fromAxisAngle(self.axle, pitch) * CFrame.new(-self.trunnion)
	local shift = -self.dir * back
	for _, b in ipairs(self.barrel) do
		local cf = turn * b.rest + shift
		if jitter > 0 then
			local n = self.t * 34
			cf += Vector3.new(math.noise(n, 1.3), math.noise(n, 7.1), math.noise(n, 13.7)) * jitter * 2
		end
		b.part.CFrame = cf
	end
end

function LaunchShow2:takeCamera()
	self.camera.CameraType = Enum.CameraType.Scriptable
	self.camOwned = true
end

function LaunchShow2:pullLever() end

-- blocks until the tyre is in and the dial can come up
function LaunchShow2:waitReady()
	local t0 = os.clock()
	while self.stage == "load" and self.t < READY_AT and os.clock() - t0 < 4 do
		RunService.RenderStepped:Wait()
	end
end

-- where the camera wants to be, what it looks at, and the field of view
function LaunchShow2:at(v: Vector3): Vector3
	local S = self.S
	return self.mid + self.fwd * (S * v.X) + Vector3.new(0, S * v.Y, 0) + self.side * (S * v.Z)
end

-- the lens never sits inside the barrel: if a spot is within it, back off along the bore and up
-- until it's clear (a cannon of any size, at any gear)
function LaunchShow2:clearOfBarrel(pos: Vector3): Vector3
	local margin = self.S * 0.05
	local moved = 0
	for _ = 1, 40 do
		local inside = false
		for _, b in ipairs(self.barrel) do
			local rel = b.rest:PointToObjectSpace(pos)
			local h = b.part.Size / 2 + Vector3.one * margin
			if math.abs(rel.X) < h.X and math.abs(rel.Y) < h.Y and math.abs(rel.Z) < h.Z then
				inside = true
				break
			end
		end
		if not inside or moved > self.S * 0.8 then break end
		local step = self.S * 0.04
		pos = pos - self.dir * step + Vector3.new(0, step * 0.6, 0)
		moved += step
	end
	return pos
end

-- the gunner's seat: well behind the breech and above the bore, looking along it past the tyre
-- and out of the muzzle into the sky: you're the one aiming this
function LaunchShow2:gunner(): (Vector3, Vector3)
	local S = self.S
	local gb = tuned("ShowGunner", GUNNER)   -- back along the bore, up, out to the side, in cannon sizes
	local pos = self.breech - self.dir * (S * gb.X) + Vector3.new(0, S * gb.Y, 0) + self.side * (S * gb.Z)
	pos = Vector3.new(pos.X, math.max(pos.Y, self.ground + 3), pos.Z)
	pos = self:clearOfBarrel(pos)
	local look = self.muzzle + self.dir * (S * 1.3) + Vector3.new(0, S * tuned("ShowGunnerLook", 0.16), 0)
	return pos, look
end

function LaunchShow2:shot(): (Vector3, Vector3, number, boolean)
	local S = self.S
	local look = self:at(tuned("ShowLook", LOOK))
	local hero = self:at(tuned("ShowHero", HERO))
	hero = Vector3.new(hero.X, math.max(hero.Y, self.ground + 3.5), hero.Z)
	local fov0 = tuned("ShowFov", FOV)
	local gpos, glook = self:gunner()
	if self.stage == "chase" then
		local at = self.tyreAt :: Vector3
		local v = (self.tyreVel :: Vector3).Unit
		-- directly behind the tyre, a little above: the same framing the run opens on
		return at - v * 20 + Vector3.new(0, 6, 0), at + v * 16, 68, false
	end
	if self.stage == "fire" then
		-- dragged out after the tyre: from the gunner's seat along the barrel, then it's the tyre's
		-- own wake
		local at = self.tyreAt :: Vector3
		local v = (self.tyreVel :: Vector3).Unit
		local k = smooth((self.fireT or 0) / 0.34)
		local follow = at - v * 20 + Vector3.new(0, 6, 0)
		return gpos:Lerp(follow, k), glook:Lerp(at + v * 16, k), lerp(60, 74, k) + 8 * self.push, false
	end
	-- the move in from a wide shot to the hero angle, then, as the shifts land, round and in to the
	-- gunner's seat: tighter with every gear
	local k = smooth(self.t / 1.2)
	local wide = hero + (hero - look).Unit * (S * 0.2) + Vector3.new(0, S * 0.6, 0)
	local pos = wide:Lerp(hero, k)
	local fov = lerp(fov0 + 6, fov0, k)
	local e = smooth(self.engage or 0)
	pos = pos:Lerp(gpos, e)
	look = look:Lerp(glook, e)
	fov = lerp(fov, 60, e)
	self.push = e
	return pos, look, fov - 3 * e, false
end

function LaunchShow2:frame(rdt: number)
	if not self.camOwned then return end
	local pos, look, fov, cut = self:shot()
	local desired = CFrame.lookAt(pos, look)
	if cut or not self.camCF then
		self.camCF = desired
	else
		self.camCF = (self.camCF :: CFrame):Lerp(desired, math.min(1, rdt * 6))
	end
	local cf = self.camCF :: CFrame
	if self.shake > 0.01 and rdt > 0 then
		local sh = self.shake
		cf *= CFrame.new((math.random() - 0.5) * sh, (math.random() - 0.5) * sh, 0) * CFrame.Angles(0, 0, (math.random() - 0.5) * sh * 0.025)
		self.shake = sh * math.exp(-rdt * 7)
	end
	self.camera.CFrame = cf
	if self.glow then
		self.glowLevel *= math.exp(-rdt * (self.stage == "charge" and 0.5 or 3))
		self.glow.Brightness = self.glowLevel
	end
	if self.stage ~= "charge" then self.fovKick *= math.exp(-rdt * 6) end
	self.camera.FieldOfView = fov + self.fovKick
end

function LaunchShow2:step(rdt: number)
	-- the hit-stop: everything holds for a beat before the shot
	if os.clock() < (self.holdUntil or 0) then return end
	if self.holdUntil and not self.fired then self:fire() end
	local dbg = RunService:IsStudio() and tonumber(workspace:GetAttribute("ShowTimeScale")) or 1
	-- Studio: hold the shot at a moment after firing to look at it
	local freeze = RunService:IsStudio() and tonumber(workspace:GetAttribute("ShowFreezeAt"))
	if freeze and self.fireT and self.fireT >= freeze then dbg = 0 end
	local scale = self.slow * (dbg :: number)
	if scale ~= self.fxScale then
		self.fxScale = scale
		for _, e in pairs(self.fx) do e.TimeScale = scale end
	end
	-- quick fire (Main sets it on repeat launches): the whole show plays faster
	local dt = rdt * scale * (self.quick or 1)
	self.t += dt
	-- the camera's creep into the gunner's seat: eased towards where the shifts have got it
	self.engage = (self.engage or 0) + ((self.engageTo or 0.06) - (self.engage or 0)) * math.min(1, rdt * 2.6)
	if self.stage == "load" then
		self:stepLoad(dt)
	elseif self.stage == "charge" then
		self:stepCharge(dt)
	else
		self:stepShot(dt)
	end
	self:frame(rdt * (dbg :: number))
end

function LaunchShow2:stepLoad(dt: number)
	local t = self.t
	-- the lob: a curve from above the muzzle down into the bore, tumbling
	if t >= LOB_START and t < LOB_END then
		local u = (t - LOB_START) / (LOB_END - LOB_START)
		local p1 = self.seat + self.dir * 7 + Vector3.new(0, 5, 0)
		local a = self.lobFrom:Lerp(p1, u)
		local b = p1:Lerp(self.seat, u)
		self.spin += dt * 9
		self:placeTyre(a:Lerp(b, u * u), self.spin)
	elseif t >= LOB_END then
		if not self.landed then
			self.landed = true
			self.landT = t
			Sound.play("land", { volume = 0.55, pitch = 1.25 })
			self.fx.puff:Emit(8)
			self.shake = 0.45
		end
		local lt = t - self.landT
		-- the barrel dips under the weight and springs back; the tyre settles with it
		local dip = -math.rad(2.2) * math.exp(-lt * 6) * math.cos(lt * 18)
		-- each shift kicks the barrel back up a touch
		self.shiftKick = (self.shiftKick or 0) * math.exp(-dt * 7)
		dip += math.rad(1.6) * (self.shiftKick or 0)
		self.pitch = dip
		local settle = math.sin(lt * 20) * math.exp(-lt * 9) * 0.35
		self:placeTyre(self.seat - self.dir * settle, self.spin)
		-- the shot builds: the barrel shudders harder and the breech vents
		local charge = math.max(0, t - READY_AT)
		self.rumble = math.min(1, charge / 4)
		self:poseBarrel(0, dip, self.rumble > 0 and 0.03 + self.rumble * 0.1 or 0)
		self.fx.steam.Rate = charge > 0 and (3 + self.rumble * 24) or 0
		self.fx.steam.Enabled = charge > 0
	end
end

-- a shift of Rev & Shift lands on the cannon: the barrel kicks, the camera punches in, and the
-- shift's rating shows (the perfects build on each other)
function LaunchShow2:shift(_gear: number, rating: string)
	if self.fired or not self.fx then return end
	self.shifts = (self.shifts or 0) + 1
	self.engageTo = math.min(1, self.shifts / 3 + 0.02)
	local fx = self.fx
	self.shiftKick = (rating == "perfect" and 1 or 0.6)
	self.fovKick -= (rating == "perfect" and 4 or 2.5)
	if rating == "perfect" then
		self.perfects = (self.perfects or 0) + 1
		fx.sparks:Emit(12 + self.perfects * 10)
		if self.perfects >= 2 then fx.flare:Emit(8 + self.perfects * 4) end
		self.glow.Color = GLOW.perfect
		self.glowLevel = math.max(self.glowLevel, 0.4 + self.perfects * 0.3)
		self.shake = math.max(self.shake, 0.55)
		Sound.play("land", { volume = 0.45, pitch = 1.5 + self.perfects * 0.12 })
	elseif rating == "good" then
		fx.puff:Emit(7)
		self.glow.Color = GLOW.great
		self.glowLevel = math.max(self.glowLevel, 0.35)
		self.shake = math.max(self.shake, 0.35)
		Sound.play("land", { volume = 0.35, pitch = 1.3 })
	else
		PackFX.burst("dustPuff", CFrame.lookAt(self.muzzle, self.muzzle + self.dir), 6, Color3.fromRGB(58, 56, 60), 1.1)
		self.shake = math.max(self.shake, 0.25)
		Sound.play("land", { volume = 0.3, pitch = 0.8 })
	end
end

-- the build-up between the last shift and the shot (its length and colour are the launch grade)
function LaunchShow2:stepCharge(dt: number)
	self.chargeT += dt
	local k = math.clamp(self.chargeT / self.chargeLen, 0, 1)
	local hot = self.grade == "perfect"
	-- the barrel shudders harder, the breech vents, sparks pour and the glow swells
	self.rumble = 1
	self:poseBarrel(0, -math.rad(0.6) * k, 0.06 + k * (hot and 0.16 or 0.1))
	self.fx.steam.Enabled = true
	self.fx.steam.Rate = 6 + k * 10
	self.sparkAcc = (self.sparkAcc or 0) + dt * (hot and 90 or 40) * k
	while self.sparkAcc >= 1 do
		self.sparkAcc -= 1
		self.fx.sparks:Emit(1)
	end
	if hot and k > 0.45 then
		self.flareAcc = (self.flareAcc or 0) + dt * 30
		while self.flareAcc >= 1 do
			self.flareAcc -= 1
			self.fx.flare:Emit(1)
		end
	end
	self.glow.Color = GLOW[self.grade] or GLOW.good
	self.glowLevel = math.max(self.glowLevel, (hot and 1.5 or 0.9) * k)
	self.fovKick = -(hot and 10 or 6) * k
	self.shake = math.max(self.shake, 0.15 + k * (hot and 0.5 or 0.3))
	if hot and k >= 0.82 and not self.flashed then
		self.flashed = true
		self:cover(0.35, 1, GLOW.perfect, 0.35)
	end
	if k >= 1 then
		self.stage = "hold"
		self.holdUntil = os.clock() + (hot and 0.16 or 0.07)
	end
end

-- the shot itself; the hit-stop has just ended
function LaunchShow2:fire()
	self.fired = true
	self.stage = "fire"
	self.fireT = 0
	local q = self.q
	local fx = self.fx
	fx.steam.Enabled = false
	Sound.play("land", { volume = 1, pitch = 0.75 })
	Sound.play("gateWhoosh", { volume = 0.75, pitch = 0.85 })
	self.blast:fire(q)
	if self.glow then
		self.glow.Color = GLOW[self.grade or "good"] or GLOW.good
		self.glowLevel = 1.2 + q * 1.3
	end
	fx.dust:Emit(math.floor(22 + q * 16))
	self.shake = 1.6 + q * 1.4
	self.fovKick = 0
	self.tyreVel = self.dir * (160 + q * 100)
	self.tyreAt = self.seat
	if q >= 0.99 then self.slow = 0.22 end
end

function LaunchShow2:stepShot(dt: number)
	local q = self.q
	self.fireT += dt
	local t = self.fireT
	-- a PERFECT holds the moment, then eases back to speed
	if self.slow < 1 and t > 0.09 then
		self.slow = math.min(1, self.slow + dt * 9)
	end
	-- the kick: back fast, nose up, home slower with a wobble
	local kick = 1.4 + q * 1.6
	local back = if t < 0.04 then kick * (t / 0.04) else kick * math.exp(-(t - 0.04) * 5.5) * math.cos((t - 0.04) * 9)
	local nose = math.rad(2.5 + q * 2) * math.exp(-t * 6) * math.cos(t * 11)
	self:poseBarrel(back, nose, 0)
	-- the tyre: out of the bore and away, tumbling forward
	local from = self.tyreAt
	self.tyreVel += GRAVITY * dt * 0.35
	self.tyreAt += self.tyreVel * dt
	local n = math.min(12, math.ceil((self.tyreAt - from).Magnitude / 1.6))
	for i = 1, n do
		self.trailAtt.WorldPosition = from:Lerp(self.tyreAt, i / n)
		self.fx.trail:Emit(1)
	end
	self.spin -= dt * 26
	self:placeTyre(self.tyreAt, self.spin)
	local chaseAt, washAt = CHASE_AT, WASH_AT
	if t >= chaseAt and self.stage ~= "chase" then
		self.stage = "chase"
		self.shake = 0.25
		self.fovKick = 0
	end
	if t >= washAt and not self.washed then
		self.washed = true
		self:cover(1, 0, SKY, WASH_LEN)
	end
	if t >= washAt + WASH_LEN + 0.04 then
		self.done = true
	end
end

-- the shot: a beat of stillness, then the blast; blocks until the screen is washed out
function LaunchShow2:release(_power: number, quality: number, grade: string?)
	self.q = math.clamp(quality, 0, 1)
	self.grade = grade or (quality >= 0.99 and "perfect" or "good")
	-- if the dial is fired before the tyre's in, it's in now
	if self.stage == "load" and self.t < LOB_END then
		self.t = LOB_END
	end
	self.chargeLen = CHARGE[self.grade] or 0
	self.engageTo = 1
	if self.chargeLen > 0 then
		self.stage = "charge"
		self.chargeT = 0
	else
		self.stage = "hold"
		self.holdUntil = os.clock() + 0.07
	end
	local t0 = os.clock()
	local studioHold = RunService:IsStudio() and workspace:GetAttribute("ShowFreezeAt") ~= nil
	while not self.done and (studioHold or os.clock() - t0 < 8) do
		RunService.RenderStepped:Wait()
	end
end

function LaunchShow2:destroy()
	if self.conn then self.conn:Disconnect() end
	for _, b in ipairs(self.barrel) do
		if b.part.Parent then b.part.CFrame = b.rest end
	end
	if self.tyre then self.tyre:Destroy() end
	if self.blast then self.blast:destroy(3) end
	for _, p in ipairs(self.parts or {}) do
		-- the smoke is left to drift and thin out over the yard
		p.Parent = workspace
		task.delay(3, function() p:Destroy() end)
	end
	self:hideClutter(false)
	self:light(false)
	-- the wash clears over the run's first moments
	local gui, f = self.coverGui, self.coverFrame
	if gui and f then
		task.delay(0.1, function()
			TweenService:Create(f, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
			task.delay(0.6, function() gui:Destroy() end)
		end)
	end
	if self.camOwned then
		self.camera.CameraType = self.savedCam
		self.camera.FieldOfView = self.savedFov
	end
end

return LaunchShow2
