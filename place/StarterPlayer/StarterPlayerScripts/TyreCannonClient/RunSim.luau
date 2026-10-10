--!strict
-- TYRE CANNON :: RunSim
-- You are the tyre. A hand-rolled kinematic sim rather than Roblox physics:
-- deterministic, frame-rate independent, controllable at 1,400 studs/s.
--
-- Skill lives in three places:
--   steering   quirks, pads and coins are only worth what you can reach
--   heat       boost heats the casing; in the red it shoves harder, at the
--              top of the gauge the tyre blows and the run is over
--   the draft  at every checkpoint the world slows and you pick a quirk
--
-- On the road (trackId "road") the checkpoints are the zone lines: gravity, drag, light and the
-- world change zone by zone, a key waits in every zone, and the stats come from the plot and the
-- launch tyre (Game.runStats), including the tyre's trait.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)
local RunPhysics = require(Modules.RunPhysics)
local RunCamera = require(Modules.RunCamera)
local TrackGen = require(Modules.TrackGen)
local WheelAssembly = require(Modules:WaitForChild("WheelAssembly"))
local Game = require(Modules:WaitForChild("Game"))
local TyreLook = require(script.Parent:WaitForChild("TyreLook"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local TyreSkills = require(script.Parent:WaitForChild("TyreSkills"))
local SkillZones = require(script.Parent:WaitForChild("SkillZones"))
local WorldView = require(script.Parent.WorldView)
local WindFX = require(script.Parent.WindFX)
local VFX = require(script.Parent.VFX)
local Prefs = require(script.Parent.Prefs)
local Weather = require(script.Parent.Weather)
local Sound = require(script.Parent.Sound)
local PackFX = require(script.Parent.PackFX)

local P = Config.Physics
local STEP = 1 / 120

-- the ghost: your best run on this road, recorded as distance, height off the ground and
-- sideways position every half second of run time, so it replays on any road the seed makes
local GHOST_DT = 0.5
local GHOST_MAX_CHARS = 12000

local function decodeGhost(g: any)
	if type(g) ~= "table" or type(g.d) ~= "string" or #g.d == 0 then return nil end
	local samples = {}
	for chunk in string.gmatch(g.d, "[^;]+") do
		local x, a, z = string.match(chunk, "^(%-?%d+),(%-?%d+),(%-?%d+)$")
		if x then table.insert(samples, { tonumber(x) :: number, tonumber(a) :: number, tonumber(z) :: number }) end
	end
	if #samples < 2 then return nil end
	local splits = {}
	if type(g.s) == "table" then
		for i, v in ipairs(g.s) do splits[i] = tonumber(v) end
	end
	return { samples = samples, splits = splits }
end

local RunSim = {}
RunSim.__index = RunSim

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function playSound(id: string, vol: number, pitch: number)
	local s = Instance.new("Sound")
	s.SoundGroup = SoundService:FindFirstChild("Effects") :: SoundGroup?
	s.SoundId = id
	s.Volume = vol
	s.PlaybackSpeed = pitch
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 5)
end

local function anchorPart(parent: Instance, name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.one
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

--==============================================================
-- the tyre
--==============================================================
local function buildTyre(parent: Instance, opts)
	local model: Model
	if TyreLook.has(opts.tyreId) then
		model = TyreLook.model(opts.tyreId, P.TyreRadius * 2, "PlayerTyre", opts.design)
		if not model.PrimaryPart then
			model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
		end
		model.Parent = parent
	else
		model = WheelAssembly.build(parent, {
			diameter = P.TyreRadius * 2,
			skin = opts.skin,
			rim = opts.rim,
			stickers = opts.stickers,
			name = "PlayerTyre",
		})
	end
	local root = model.PrimaryPart :: BasePart
	local skin = Config.SkinsById[opts.skin or "stock"] or Config.SkinsById.stock

	local attach = Instance.new("Attachment")
	attach.Name = "DustPoint"
	attach.Parent = root
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.4, 0.9)
	dust.Speed = NumberRange.new(8, 26)
	dust.SpreadAngle = Vector2.new(28, 28)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 16) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	dust.Acceleration = Vector3.new(0, 12, 0)
	dust.Parent = attach

	local glow = Instance.new("PointLight")
	glow.Range = 26
	glow.Brightness = 0
	glow.Color = skin.glow
	glow.Parent = root

	-- a hot skin over the rubber that shows through as the heat climbs
	local carcass = model:FindFirstChild("Carcass") :: BasePart?
	local heatSkin = nil
	if carcass then
		heatSkin = carcass:Clone()
		heatSkin.Name = "HeatSkin"
		heatSkin.Size = carcass.Size * 1.015
		heatSkin.Material = Enum.Material.SmoothPlastic
		pcall(function() (heatSkin :: any).UsePartColor = true end)
		heatSkin.Color = Color3.fromRGB(255, 90, 20)
		heatSkin.Transparency = 1
		heatSkin.CastShadow = false
		heatSkin.Parent = model
	end
	return model, root, dust, glow, heatSkin, carcass
end

--==============================================================
-- start
--==============================================================
function RunSim.start(opts)
	local self = setmetatable({}, RunSim)
	self.trackId = opts.trackId
	self.track = TrackGen.get(opts.trackId)
	-- the hills grow with the stage, so a faster tyre still has hills to ride (TrackGen:rollerHeight)
	self.track.hillScale = (opts.stats.stage or 1) ^ 2
	self.tcfg = self.track:cfgAt(0)
	self.zone = 1
	self.keysGot = 0
	self.stats = opts.stats
	self.onTick = opts.onTick
	local onEvent = opts.onEvent or function() end
	-- the last thing that happened, for the NaN report
	self.onEvent = function(e)
		self.lastEventKind = e and e.kind
		onEvent(e)
	end
	self.onEnd = opts.onEnd

	local ang = math.rad(opts.launchAngleDeg or self.stats.launchAngle or 20)
	local spd = opts.launchSpeed or 260
	local startX = math.max(0, tonumber(opts.startX) or 0)
	self.x, self.z = startX, 0
	-- the zone you start in (no banner for it)
	if self.track.isRoad then self.zone = self.track:zoneIndex(startX) end
	self.y = self.track:heightAt(startX) + P.TyreRadius + 26

	-- the flight (v3.1): a heading (yaw about the road's +X axis, + is to the right; and pitch), a
	-- speed and a slow sink. The velocity vector rides in vx/vy/vz for the skills to read and set;
	-- anything they change there is picked up at the top of the next step.
	local F = Config.Run
	self.yaw, self.pitch, self.speed, self.fall = 0, ang, spd, 0
	self.aimYaw, self.aimPitch = 0, ang
	self.ctx = {
		radius = P.TyreRadius, turn = 1, gravity = 1, drag = 1, friction = 1, fatigue = 1,
		glide = self.stats.glide or 1, keep = self.stats.keep or 1, restitution = self.stats.restitution or 0.32,
		maxSpeed = P.MaxSpeed * (self.stats.maxSpeedScale or 1),
	}
	self.input = { aimYaw = 0, aimPitch = 0, tuck = false, thrust = 0 }
	local trk = self.track
	self.terrain = { heightAt = function(x: number) return trk:heightAt(x) end, slopeAt = function(x: number) return trk:slopeAt(x) end }
	self.idleT = 0
	self.vx, self.vy, self.vz = spd * math.cos(ang), spd * math.sin(ang), 0
	self.wvx, self.wvy, self.wvz = self.vx, self.vy, self.vz
	self.grounded = false
	self.roll = 0
	self.bank = 0
	self.view = (Prefs.get("camera") == "first") and "first" or "chase"

	-- nitro: a tank that skims and smooth landings fill and Space (or BOOST) drains
	self.nitroMax = self.stats.nitroMax or 100
	self.nitro = self.nitroMax * F.NitroStart
	self.nitroLeft = tonumber(opts.nitroStart) or 0     -- a PERFECT launch: free thrust for this long

	-- the chain: smooth landings, smashes and bounces in a row, and the cash multiplier they carry
	self.chain = 0
	self.chainTimer = 0
	self.peakChain = 0
	self.bounces = 0           -- targets bounced off (the server counts these)
	self.perfects = 0          -- smooth landings and skims
	self.skids = 0
	self.skimT = 0
	self.comboMetres = 0       -- metres travelled, each weighted by the multiplier you had then
	self.stepCount = 0
	self.bot = RunService:IsStudio() and workspace:GetAttribute("DebugBot") or nil

	self.fuel = self.nitro
	self.maxFuel = self.nitroMax
	self.heat = 0
	self.maxHeat = 0
	self.redlineSeconds = 0
	self.blown = false

	self.runTime = 0
	self.airTime = 0
	self.airStreak = 0
	self.longestAir = 0
	self.perkCount = 0
	self.spins = 0
	self.pads = 0
	self.bonus = 0
	self.multIntegral = 0
	self.combo = 1
	self.comboTimer = 0
	self.seen = {}
	self.seenSet = {}
	self.maxSpeed = 0
	self.maxHeight = 0
	self.tier = Config.TierAt(startX)
	self.smashes = 0
	self.hits = 0
	self.drafts = 0
	self.metals = { bronze = 0, silver = 0, gold = 0 }
	self.boosted = false
	self.flawless = opts.flawless == true

	self.active = {}
	self.usedTargets = {}
	self.hitObstacles = {}
	self.usedPads = {}
	self.usedHazards = {}
	self.found = {}

	self.keys = {}
	self.touch = {}
	self.steer = 0
	self.stopTimer = 0
	self.finished = false
	self.shake = 0
	self.hitFlash = 0
	self.draft = nil
	self.timeScale = 1
	self.gateLean = 0
	self.photo = nil
	-- a perfect push: time crawls for half a second while the camera swings round
	if opts.flawless == true then
		self.timeScale = 0.08
		self.slowUntil = os.clock() + 0.55
	end

	-- the skill zones' furniture goes on the road before any of it is built
	self.track:setSkillKind(SkillZones.kindOf(self.stats.skill))
	self.world = WorldView.new(opts.trackId)
	pcall(function() self.world:markBest(opts.best, opts.bestName) end)
	self.world:ensure(self.x)

	local folder = Instance.new("Folder")
	folder.Name = "TyreCannonRun"
	folder.Parent = workspace
	self.folder = folder

	self.skin = Config.SkinsById[opts.skin or "stock"] or Config.SkinsById.stock
	self.model, self.root, self.dust, self.glow, self.heatSkin, self.carcass = buildTyre(folder, opts)
	-- the tuck shows on the tyre itself: it glows gold when a tuck now pays, teal while it's tucked
	local tuckHl = Instance.new("Highlight")
	tuckHl.Name = "TuckGlow"
	tuckHl.Adornee = self.model
	tuckHl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	tuckHl.FillTransparency = 1
	tuckHl.OutlineTransparency = 1
	tuckHl.Enabled = false
	tuckHl.Parent = folder
	self.tuckHl = tuckHl
	self.wind = WindFX.new(folder)
	self.windTier = 0

	-- boost flame and heat smoke ride an unrotated anchor behind the hub
	self.fxAnchor = anchorPart(folder, "FXAnchor")
	-- the pack's flame sheets for the boost, its smoke sheets for a hot tread
	local function packHandle(name: string, offset: CFrame)
		local att = Instance.new("Attachment")
		att.CFrame = offset
		att.Parent = self.fxAnchor
		local e = PackFX.emitter(name, att)
		if not e then return nil, nil end
		local baseRate = (e:GetAttribute("BaseRate") :: number?) or 20
		return {
			set = function(on: boolean, mult: number?)
				e.Enabled = on
				e.Rate = baseRate * (mult or 1) * VFX.density()
			end,
		}, e
	end
	self.flame = VFX.attach("BoostFlame", self.fxAnchor, CFrame.new(-P.TyreRadius * 0.9, -P.TyreRadius * 0.35, 0) * CFrame.Angles(0, 0, math.rad(90)), 0.3)
	self.smoke, self.smokeEmitter = packHandle("treadSmoke", CFrame.new(-P.TyreRadius * 0.5, -P.TyreRadius * 0.85, 0))
	-- heat shows as smoke and on the gauge, not as a light
	self.glow.Enabled = false

	-- a crisp disc under the tyre while it's in the air, to judge the landing by
	local shadow = anchorPart(folder, "AirShadow")
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Size = Vector3.new(0.12, P.TyreRadius * 2, P.TyreRadius * 2)
	self.airShadow = shadow
	self.squash = 0

	self.savedLighting = {
		ClockTime = Lighting.ClockTime, FogColor = Lighting.FogColor, FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
	}
	Lighting.ClockTime = self.tcfg.clockTime
	Lighting.FogColor = self.tcfg.fog
	Lighting.FogEnd = self.tcfg.fogEnd
	Lighting.FogStart = self.tcfg.fogEnd * 0.35
	Lighting.Ambient = self.tcfg.ambient
	Lighting.OutdoorAmbient = self.tcfg.ambient
	-- the haze does the distance: the land fades into the road's own sky
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		self.savedAtmosphere = { inst = atm, Density = atm.Density, Offset = atm.Offset, Color = atm.Color, Decay = atm.Decay, Glare = atm.Glare, Haze = atm.Haze }
		local band = Config.BandFor(self.tcfg, Config.TierAt(startX))
		atm.Density = 0.2
		atm.Offset = 0
		atm.Color = band.fog
		atm.Decay = band.fog:Lerp(Color3.fromRGB(96, 112, 138), 0.35)
		atm.Glare = 0.15
		atm.Haze = 0.5
	end

	self.camera = workspace.CurrentCamera
	self.savedCamType = self.camera.CameraType
	self.savedFov = self.camera.FieldOfView
	self.camera.CameraType = Enum.CameraType.Scriptable
	self.camCF = CFrame.lookAt(Vector3.new(self.x - 60, self.y + 14, 0), Vector3.new(self.x + 120, self.y - 16, 0))
	if self.slowUntil then
		-- start side-on, close to the tyre, so the swing round to the chase camera shows
		self.camCF = CFrame.lookAt(Vector3.new(self.x + 6, self.y + 5, -34), Vector3.new(self.x, self.y, 0))
		self.introOffset = CFrame.new(self.x, self.y, self.z):ToObjectSpace(self.camCF)
	end
	self.weather = Weather.start(opts.trackId, folder)
	self.camera.CFrame = self.camCF
	self.dust.Color = ColorSequence.new(self.tcfg.ground)

	self.skills = TyreSkills.new(self, self.stats, opts.hudGui)
	self.zones = SkillZones.new(self, self.stats.skill)
	self:bindInput()
	self.accumulator = 0
	self.conn = RunService.RenderStepped:Connect(function(dt)
		self:frame(math.min(dt, 0.1))
	end)
	self:buildTrail(opts.trail)
	self.ghostRec = {}
	self.ghostChars = 0
	self.nextSample = 0
	self.splits = {}
	self.startX = startX
	self.ghost = decodeGhost(opts.ghost)
	if self.ghost then self:buildGhost(opts.tyreId) end
	-- the other players' best runs, racing alongside: it always feels like someone's out there
	self.rivals = {}
	for _, r in ipairs(type(opts.rivals) == "table" and opts.rivals or {}) do
		local g = decodeGhost(r.ghost)
		if g then
			local keep = { self.ghostModel, self.ghostHighlight, self.ghostPlate, self.ghostParts, self.ghostFade }
			self:buildGhost(r.tyre, tostring(r.name or "RIVAL"))
			table.insert(self.rivals, { ghost = g, model = self.ghostModel, hl = self.ghostHighlight, fade = 0.7 })
			self.ghostModel, self.ghostHighlight, self.ghostPlate, self.ghostParts, self.ghostFade = keep[1], keep[2], keep[3], keep[4], keep[5]
		end
	end

	local rumble = Instance.new("Sound")
	rumble.SoundId = "rbxassetid://9112854440"
	rumble.Looped = true
	rumble.SoundGroup = SoundService:FindFirstChild("Effects") :: SoundGroup?
	rumble.Volume = 0
	rumble.Parent = SoundService
	rumble:Play()
	self.rumble = rumble
	return self
end

--==============================================================
-- the ghost of the best run
--==============================================================
function RunSim:buildGhost(tyreId: string?, rivalName: string?)
	-- your own best in gold; another player's in blue, under their name
	local fillC = if rivalName then Color3.fromRGB(96, 196, 255) else Color3.fromRGB(255, 200, 70)
	local lineC = if rivalName then Color3.fromRGB(214, 240, 255) else Color3.fromRGB(255, 244, 200)
	-- the ghost is your own tyre as one clean gold silhouette: its parts all but invisible, a
	-- Highlight drawing the fill and a bright outline over the whole shape (so its insides never
	-- show through each other), a short gold trail behind it, and a YOUR BEST plate over it
	local ok, model = pcall(function()
		if tyreId and TyreLook.has(tyreId) then
			return TyreLook.model(tyreId, P.TyreRadius * 2, "GhostTyre")
		end
		return WheelAssembly.build(nil, { diameter = P.TyreRadius * 2, skin = "stock", rim = "steel", detail = "low", name = "GhostTyre" })
	end)
	if not ok or not model then return end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Light") or d:IsA("SurfaceGui") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
			d:Destroy()
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Material = Enum.Material.SmoothPlastic
			d.Color = fillC
			d.Transparency = 0.9
		end
	end
	model.Parent = self.folder
	local hl = Instance.new("Highlight")
	hl.FillColor = fillC
	hl.FillTransparency = if rivalName then 0.7 else 0.62
	hl.OutlineColor = lineC
	hl.OutlineTransparency = 0.05
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = model
	hl.Parent = model
	self.ghostHighlight = hl
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if root then
		-- the trail: two points across the tyre's middle, streaming gold behind it
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, P.TyreRadius * 0.55, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -P.TyreRadius * 0.55, 0)
		a1.Parent = root
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Lifetime = 0.35
		tr.LightEmission = 0.4
		tr.Color = ColorSequence.new(fillC)
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		tr.WidthScale = NumberSequence.new(1, 0.2)
		tr.FaceCamera = true
		tr.Parent = root
		-- the plate: the kit's pill in gold, YOUR BEST in Montserrat, the same size on screen at any distance
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(120, 30)
		bb.StudsOffsetWorldSpace = Vector3.new(0, P.TyreRadius + 3.2, 0)
		bb.MaxDistance = 900
		bb.LightInfluence = 0
		bb.AlwaysOnTop = true
		bb.Parent = root
		local plate = Instance.new("ImageLabel")
		plate.Size = UDim2.new(1, 24, 1, 24)
		plate.Position = UDim2.fromOffset(-12, -12)
		plate.BackgroundTransparency = 1
		plate.Image = Kit.Art.plate.id
		plate.ScaleType = Enum.ScaleType.Slice
		plate.SliceCenter = Kit.Art.plate.slice
		plate.SliceScale = 0.5
		plate.ImageColor3 = if rivalName then Color3.fromRGB(54, 150, 230) else Color3.fromRGB(246, 176, 40)
		plate.Parent = bb
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -16, 1, -8)
		l.Position = UDim2.fromOffset(8, 3)
		l.BackgroundTransparency = 1
		l.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
		l.Text = if rivalName then string.upper(rivalName) else "YOUR BEST"
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextScaled = true
		l.ZIndex = 2
		l.Parent = bb
		local s = Instance.new("UIStroke")
		s.Thickness = 2
		s.Color = Color3.fromRGB(14, 12, 18)
		s.Parent = l
		self.ghostPlate = bb
	end
	self.ghostModel = model
	self.ghostParts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(self.ghostParts, d) end
	end
	self.ghostFade = 0.62
end

-- where the best run was at a moment of run time: distance, height off the ground, sideways
function RunSim:ghostAt(t: number, ghost: any?): (number, number, number)
	local s = (ghost or self.ghost).samples
	local f = t / GHOST_DT + 1
	local i = math.clamp(math.floor(f), 1, #s)
	local j = math.min(i + 1, #s)
	local k = math.clamp(f - i, 0, 1)
	local a, b = s[i], s[j]
	return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
end

--==============================================================
-- airtime trail (shop cosmetic)
--==============================================================
function RunSim:buildTrail(trailId: string?)
	local def = Config.TrailsById[trailId or "none"]
	if not def or def.id == "none" then return end
	self.trailDef = def
	local anchor = anchorPart(self.folder, "TrailAnchor")
	self.trailAnchor = anchor
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, def.width * 0.5, 0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -def.width * 0.5, 0)
	a1.Parent = anchor
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(def.a, def.b)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = def.life
	trail.LightEmission = def.glow or 0
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = anchor
	self.trail = trail
	if def.sparks then
		local att = Instance.new("Attachment")
		att.Parent = anchor
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxassetid://84291297587243"
		e.Rate = 0
		e.Lifetime = NumberRange.new(0.25, 0.6)
		e.Speed = NumberRange.new(4, 22)
		e.SpreadAngle = Vector2.new(140, 140)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new(0.1)
		e.Color = ColorSequence.new(def.a, def.b)
		e.LightEmission = 1
		e.Parent = att
		self.trailSparks = e
	end
end

--==============================================================
-- input
--==============================================================
function RunSim:bindInput()
	local K = Enum.KeyCode
	local UIS = UserInputService
	self.mouseDX, self.mouseDY = 0, 0
	self.padAim = Vector2.zero
	self.touchAim = Vector2.zero
	self.mouseLook = false
	local function down(input: InputObject, gpe: boolean)
		if self.finished then return end
		local k = input.KeyCode
		if k == K.V then
			self:toggleView()
			return
		end
		if gpe then return end
		if k == K.Space or k == K.ButtonR2 or k == K.ButtonA then self.keys.boost = true
		elseif k == K.LeftShift or k == K.LeftControl or k == K.ButtonL2 or k == K.ButtonB then self.keys.tuck = true
		elseif k == K.W or k == K.Up then self.keys.climb = true
		elseif k == K.S or k == K.Down then self.keys.dive = true
		elseif k == K.A or k == K.Left then self.keys.left = true
		elseif k == K.D or k == K.Right then self.keys.right = true
		elseif k == K.Q or k == K.ButtonSelect then self:bail()
		elseif k == K.E or k == K.ButtonY then self.skills:input(true)
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 then self.keys.boost = true
		elseif t == Enum.UserInputType.MouseButton2 then self.keys.tuck = true end
	end
	local function up(input: InputObject)
		local k = input.KeyCode
		if k == K.Space or k == K.ButtonR2 or k == K.ButtonA then self.keys.boost = false
		elseif k == K.LeftShift or k == K.LeftControl or k == K.ButtonL2 or k == K.ButtonB then self.keys.tuck = false
		elseif k == K.W or k == K.Up then self.keys.climb = false
		elseif k == K.S or k == K.Down then self.keys.dive = false
		elseif k == K.A or k == K.Left then self.keys.left = false
		elseif k == K.D or k == K.Right then self.keys.right = false
		elseif k == K.E or k == K.ButtonY then self.skills:input(false)
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 then self.keys.boost = false
		elseif t == Enum.UserInputType.MouseButton2 then self.keys.tuck = false end
	end
	local function changed(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement and self.mouseLook then
			self.mouseDX += input.Delta.X
			self.mouseDY += input.Delta.Y
		elseif input.KeyCode == K.Thumbstick1 then
			local p = input.Position
			self.padAim = Vector2.new(math.abs(p.X) > 0.15 and p.X or 0, math.abs(p.Y) > 0.15 and p.Y or 0)
		end
	end
	-- mouse look: the cursor is held at the centre, and how far you move it is where you're aiming
	if Prefs.get("mouselook") ~= false and not (UIS.TouchEnabled and not UIS.KeyboardEnabled) then
		self.mouseLook = true
		self.savedMouse, self.savedIcon = UIS.MouseBehavior, UIS.MouseIconEnabled
		UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
		UIS.MouseIconEnabled = false
	end
	self.inConns = {
		UserInputService.InputBegan:Connect(down),
		UserInputService.InputEnded:Connect(up),
		UserInputService.InputChanged:Connect(changed),
	}
end

function RunSim:unbindInput()
	for _, c in ipairs(self.inConns or {}) do c:Disconnect() end
	self.inConns = {}
	if self.mouseLook then
		UserInputService.MouseBehavior = self.savedMouse or Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = self.savedIcon ~= false
		self.mouseLook = false
	end
end

function RunSim:setTouch(field: string, on: boolean)
	self.touch[field] = on
	if field == "skill" and self.skills then self.skills:input(on) end
end

-- the on-screen stick: x right, y up, each -1..1
function RunSim:setTouchAim(v: Vector2)
	self.touchAim = v
end

-- first person and the chase camera (V)
function RunSim:toggleView()
	self.view = self.view == "first" and "chase" or "first"
	local hide = self.view == "first"
	if self.model then
		for _, d in ipairs(self.model:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = hide and 1 or 0 end
		end
	end
	self.onEvent({ kind = "view", view = self.view })
end

-- the aim: mouse movement and the keys, stick or thumb move it; it holds where you leave it
function RunSim:updateAim(dt: number)
	local F = Config.Run
	local inv = (Prefs.get("invertpitch") == true) and -1 or 1
	local sens = 0.4 + (tonumber(Prefs.get("sens")) or 0.5) * 1.2
	local pitchTouched = self.mouseDY ~= 0
	if self.mouseLook and (self.mouseDX ~= 0 or self.mouseDY ~= 0) then
		self.aimYaw += self.mouseDX * F.MouseSens * sens
		self.aimPitch += -self.mouseDY * F.MouseSens * sens * inv
		self.mouseDX, self.mouseDY = 0, 0
		self.idleT = 0
	end
	local k = self.keys
	local ix = (k.right and 1 or 0) - (k.left and 1 or 0) + self.padAim.X + self.touchAim.X
	local iy = ((k.climb and 1 or 0) - (k.dive and 1 or 0) + self.padAim.Y + self.touchAim.Y) * inv
	if ix ~= 0 or iy ~= 0 then
		self.aimYaw += math.clamp(ix, -1, 1) * F.KeyRate * dt
		self.aimPitch += math.clamp(iy, -1, 1) * F.KeyRate * dt
		self.idleT = 0
	else
		self.idleT += dt
	end
	-- the nose (float / dive, in the air) comes back to level when nothing is holding it
	if iy == 0 and not pitchTouched then
		self.aimPitch += (0 - self.aimPitch) * math.min(1, dt * 2.5)
	end
	self.aimYaw = math.clamp(self.aimYaw, -F.YawLimit, F.YawLimit)
	if self.grounded then self.aimPitch += (0 - self.aimPitch) * math.min(1, dt * 4) end
	self.aimPitch = math.clamp(self.aimPitch, -0.6, 0.6)
end

function RunSim:steerInput(): number
	return math.clamp(self.aimYaw - self.yaw, -1, 1)
end

function RunSim:bail()
	self:finish("bailed")
end

-- a chain link: a ring, a bounce, a skim
function RunSim:link()
	local F = Config.Run
	self.chain += 1
	self.peakChain = math.max(self.peakChain, self.chain)
	self.combo = math.min(F.ComboMax, 1 + F.ComboStep * self.chain)
	self.chainTimer = F.ChainDecay
end

function RunSim:breakChain(why: string)
	if self.chain >= 3 then self.onEvent({ kind = "chainlost", chain = self.chain, why = why }) end
	self.chain, self.combo, self.chainTimer = 0, 1, 0
end

-- Studio's bot (workspace DebugBot = "good" | "ok" | "none"): flies the next ring so the run can
-- be tuned: "good" is clean, "ok" is a hand that wanders, "none" lets go of everything
function RunSim:botStep()
	local mode = self.bot
	if mode == "none" or self.finished then return end
	local F = Config.Run
	local track = self.track
	local R = P.TyreRadius
	local t = os.clock()
	local wantYaw = math.clamp(-self.z * 0.01, -0.5, 0.5)
	if mode == "ok" then wantYaw += math.sin(t * 1.7) * 0.18 + math.sin(t * 4.3) * 0.06 end
	self.aimYaw = math.clamp(wantYaw, -F.YawLimit, F.YawLimit)
	local clearance = self.y - R - track:heightAt(self.x)
	local aim = 0
	if not self.grounded then
		-- flare to soften a long fall
		local vy = math.sin(self.pitch) * self.speed
		if clearance < 90 and vy < -50 then aim = 0.5 end
		if mode == "ok" then aim += math.sin(t * 1.3) * 0.25 end
	end
	self.aimPitch = aim
	self.idleT = 0
	local slope = track:slopeAt(self.x)
	self.keys.boost = self.nitro > 20 and (self.grounded and slope > -0.02) and self.speed < 300
	-- tuck as the road drops away (a PERFECT), let go before the legs cramp
	if (self.perfectT or 0) > 0 then
		self.keys.tuck = true
	elseif not self.tucking or (self.tuckT or 0) > F.TuckWindow * 0.8 or slope > -0.02 then
		self.keys.tuck = false
	end
end

--==============================================================
-- quirks and the draft
--==============================================================
function RunSim:resolveMods()
	local m = {
		thrust = 0, gravityMult = 1, dragMult = 1, frictionMult = 1,
		bounceMult = 1, creditMult = 1, magnetMult = 1, controlMult = 1,
		phase = false, boostFree = false,
	}
	for _, a in ipairs(self.active) do
		local mods = a.perk.mods
		if mods.thrust then m.thrust += mods.thrust end
		if mods.gravityMult then m.gravityMult *= mods.gravityMult end
		if mods.dragMult then m.dragMult *= mods.dragMult end
		if mods.frictionMult then m.frictionMult *= mods.frictionMult end
		if mods.bounceMult then m.bounceMult *= mods.bounceMult end
		if mods.creditMult then m.creditMult *= mods.creditMult end
		if mods.magnetMult then m.magnetMult *= mods.magnetMult end
		if mods.controlMult then m.controlMult *= mods.controlMult end
		if mods.phase then m.phase = true end
		if mods.boostFree then m.boostFree = true end
	end
	return m
end

function RunSim:applyPerk(perk, source: string)
	local inst = perk.instant or {}
	if inst.up then
		self.vy = math.max(self.vy, -25) + inst.up
		self.grounded = false
	end
	if inst.fwd then self.vx += inst.fwd end
	if inst.boost then self.fuel = math.min(self.maxFuel * 1.5, self.fuel + inst.boost) end
	if inst.credits then self.bonus += inst.credits end
	if (perk.duration or 0) > 0 then
		local found = false
		for _, a in ipairs(self.active) do
			if a.perk.id == perk.id then
				a.expires = self.runTime + perk.duration
				found = true
				break
			end
		end
		if not found then
			if #self.active >= self.stats.perkSlots then table.remove(self.active, 1) end
			table.insert(self.active, { perk = perk, expires = self.runTime + perk.duration })
		end
	end
	self.combo = math.min(Config.Economy.ComboMax, self.combo + Config.Economy.ComboStep)
	self.comboTimer = Config.Economy.ComboWindow
	self.perkCount += 1
	if not self.seenSet[perk.id] then
		self.seenSet[perk.id] = true
		table.insert(self.seen, perk.id)
	end
	local info = Config.Rarity[perk.rarity]
	self.glow.Brightness = 3
	self.glow.Color = info.color
	playSound("rbxassetid://9125402735", 0.6, 0.9 + info.order * 0.16)
	self.onEvent({ kind = "perk", perk = perk, combo = self.combo, rarity = perk.rarity, source = source })
end

--==============================================================
-- one physics step
--==============================================================
-- what a landing does beyond the physics (which RunPhysics has done): dust, the camera's thump, and
-- the chain. A long hang that comes down soft is a link; a slam breaks the chain.
function RunSim:onLanding(land)
	local F = Config.Run
	local R = P.TyreRadius
	local impact = land.impact
	local hang = self.airStreak
	local at = Vector3.new(self.x, self.y - R + 0.4, self.z)
	local dustCol = self.track:cfgAt(self.x).ground:Lerp(Color3.new(1, 1, 1), 0.3)
	if self.cam then RunCamera.thump(self.cam, math.min(impact, 400) * (if land.braced then 0.05 else 0.1)) end
	local pounding = self.skills.pounding == true
	if land.soft and land.braced and impact >= F.SoftImpact * 0.6 and not pounding then
		-- a timed tuck took a landing that would have hurt: it rolls on, and it's a link
		PackFX.burst("dustRing", CFrame.new(at), 10, dustCol, 1.1)
		self.perfects += 1
		self.nitro = math.min(self.nitroMax, self.nitro + F.LandNitro)
		self:link()
		Sound.play("land", { volume = 0.45, pitch = 1.15 })
		self.onEvent({ kind = "braced", chain = self.chain, combo = self.combo })
		local skillPitch = self.skills:landed(impact)
		if skillPitch then
			self.grounded = false
			self.pitch = math.clamp(math.rad(skillPitch), 0.3, 1.0)
			self.speed += 40
		end
		return
	end
	if land.soft then
		PackFX.burst("dustRing", CFrame.new(at), 6, dustCol, 0.9)
		if pounding then
			-- Meteor comes down braced: the slam is the point, never a crash
			local skillPitch = self.skills:landed(impact)
			if skillPitch then
				self.grounded = false
				self.pitch = math.clamp(math.rad(skillPitch), 0.3, 1.0)
				self.speed += 40
			end
			return
		end
		if hang > F.SmoothHang and impact < F.SoftImpact * 0.5 then
			self.perfects += 1
			self.nitro = math.min(self.nitroMax, self.nitro + F.LandNitro)
			self:link()
			self.hitStopUntil = os.clock() + 0.03
			self.onEvent({ kind = "smooth", chain = self.chain, combo = self.combo })
		end
		return
	end
	self.squash = math.max(self.squash or 0, math.clamp(impact / 380, 0.25, 1))
	self.shake = math.min(2.6, self.shake + impact * 0.004)
	if land.bounced and not pounding then
		self.skids += 1
		if self.chain > 0 then self:breakChain("crash") end
	elseif self.chain > 0 and impact > F.HardImpact * 0.7 and not pounding then
		self:breakChain("ground")
	end
	if impact > 90 then
		VFX.emit("LandSmoke", CFrame.new(at), { scale = math.clamp(impact / 90, 1.2, 4) })
		PackFX.burst("dustRing", CFrame.new(at), math.floor(math.clamp(impact / 25, 6, 22)), dustCol, math.clamp(impact / 260, 0.8, 2))
	end
	if impact > 130 and os.clock() - (self.lastThud or 0) > 0.25 then
		self.lastThud = os.clock()
		Sound.play("land", { volume = math.clamp(impact / 380, 0.35, 1), pitch = 0.9 + math.random() * 0.2 })
	end
	local skillPitch = self.skills:landed(impact)
	if skillPitch then
		-- Meteor: the whole landing is a launch
		self.grounded = false
		self.pitch = math.clamp(math.rad(skillPitch), 0.3, 1.0)
		self.speed += 40
		return
	end
	-- a bounce off the ground is a crash; anything less is only rough
	self.onEvent({ kind = if land.bounced then "crash" else "rough", impact = impact })
end

-- the target the tyre has come down onto this step, or nil: its top, from above
function RunSim:targetHit(px: number, py: number, vyTot: number)
	local R = P.TyreRadius
	local ci = math.floor(self.x / TrackGen.ChunkSize)
	for c = ci - 1, ci + 1 do
		if c >= 0 then
			for _, t in ipairs(self.track:targetsForChunk(c)) do
				if not self.usedTargets[t.key] and math.abs(self.x - t.x) <= t.len / 2 + 3
					and math.abs(self.z - t.z) <= math.max(8, t.h * 0.8) + 3 then
					local top = t.y + t.h
					if self.y - R <= top and self.y + R > t.y then
						self.usedTargets[t.key] = true
						if py - R >= top - 5 and vyTot < -8 then return t, true end
						return t, false
					end
				end
			end
		end
	end
	return nil, false
end

-- one physics step
function RunSim:step(dt: number)
	local track, stats, sk = self.track, self.stats, self.skills
	local mods = self.mods
	local F = Config.Run
	local R = P.TyreRadius
	self.stepCount += 1
	if self.bot then self:botStep() end

	-- pick up anything the skills did to the velocity
	local vx, vy, vz = self.vx, self.vy, self.vz
	if math.abs(vx - self.wvx) + math.abs(vy - self.wvy) + math.abs(vz - self.wvz) > 0.05 then
		local wy = vy + self.fall
		local sp = math.sqrt(vx * vx + wy * wy + vz * vz)
		if sp > 1 then
			self.speed = sp
			self.pitch = math.asin(math.clamp(wy / sp, -1, 1))
			self.yaw = math.clamp(math.atan2(vz, math.max(vx, 1)), -F.YawLimit, F.YawLimit)
			self.aimYaw, self.aimPitch = self.yaw, self.pitch
			if self.grounded and self.pitch > 0.2 then self.grounded = false end
		end
	end

	self:updateAim(dt)
	-- the tuck, with its timing window (RunPhysics.tuck)
	local tuck, tuckEvent = RunPhysics.tuck(self, self.keys.tuck == true or self.touch.tuck == true, self.terrain, F, dt)
	if tuckEvent == "perfect" then
		-- the kick is fed in over a moment, a surge rather than a jolt
		self.kickLeft = (self.kickLeft or 0) + F.PerfectKick * (stats.stage or 1)
		self.kickRate = self.kickLeft / (F.PerfectKickTime or 0.4)
		self.perfects += 1
		self:link()
	end
	if (self.kickLeft or 0) > 0 then
		local add = math.min(self.kickLeft, (self.kickRate or 0) * dt)
		self.kickLeft -= add
		self.speed += add
	end
	if tuckEvent then self.onEvent({ kind = "tuck", what = tuckEvent, chain = self.chain, combo = self.combo }) end

	-- nitro: a tank that Space (or BOOST) drains, and a free burst for a PERFECT launch
	local nitroOn = false
	if self.nitroLeft > 0 then
		self.nitroLeft -= dt
		nitroOn = true
	elseif (self.keys.boost or self.touch.boost) and self.nitro > 0 and not self.nitroDry then
		self.nitro = math.max(0, self.nitro - F.NitroDrain * dt)
		nitroOn = true
		self.boosted = true
		if self.nitro <= 0 then self.nitroDry = true end
	end
	self.usingBoost = nitroOn
	if nitroOn then
		self.regenWait = 0.8
	else
		self.regenWait = math.max(0, (self.regenWait or 0) - dt)
		if self.regenWait <= 0 then
			self.nitro = math.min(self.nitroMax, self.nitro + (stats.nitroRegen or 2) * dt)
		end
	end
	if self.nitroDry and self.nitro >= self.nitroMax * 0.3 then self.nitroDry = false end
	local thrust = nitroOn and F.NitroThrust * (stats.nitroPower or 1) * (self.nitroLeft > 0 and 1.25 or 1) or 0

	-- the run gets harder to keep going the longer it lasts, so no run is endless
	local ctx = self.ctx
	ctx.turn = (stats.turn or 1) * sk.control * mods.controlMult
	ctx.gravity = sk.gravity * mods.gravityMult * (stats.gravityScale or 1)
	ctx.drag = stats.dragScale * sk.drag * mods.dragMult
	ctx.friction = stats.frictionScale
	ctx.fatigue = 1
	if self.runTime > F.FatigueStart then
		ctx.fatigue = 1 + (self.runTime - F.FatigueStart) * F.FatigueRate
		self.fatigued = true
	end

	local px, py = self.x, self.y
	local inp = self.input
	inp.aimYaw, inp.aimPitch, inp.tuck, inp.thrust = self.aimYaw, self.aimPitch, tuck, thrust + mods.thrust
	inp.tuckAmt = self.tuckAmt
	-- braced for the landing: tucked as it touches down, or a skill's slam (Meteor)
	inp.brace = tuck or (sk.pounding == true)
	inp.slam = sk.pounding == true
	local res = RunPhysics.step(self, inp, ctx, self.terrain, F, dt)
	if res.landing then self:onLanding(res.landing) end
	local s = self.speed
	local vyTot = math.sin(self.pitch) * s
	self.fall = 0

	-- a soft wall of wind either side
	local za = math.abs(self.z)
	if za > F.CorridorSoft then
		local push = math.clamp((za - F.CorridorSoft) / 25, 0, 1)
		local dirIn = (self.z > 0) and -1 or 1
		self.yaw += dirIn * push * 1.6 * dt
		self.aimYaw += dirIn * push * 1.6 * dt
		if za > 215 then self.z = (self.z > 0) and 215 or -215 end
	end
	self.yaw = math.clamp(self.yaw, -F.YawLimit, F.YawLimit)
	self.aimYaw = math.clamp(self.aimYaw, -F.YawLimit, F.YawLimit)
	self.comboMetres += (self.x - px) * P.StudsToMetres * self.combo

	-- in the air: hang time, and the skim (low and fast pays)
	if not self.grounded then
		self.airTime += dt
		self.airStreak += dt
		local clearance = self.y - R - track:heightAt(self.x)
		local alt = clearance
		local ph = self.photo
		if alt > 30 and (not ph or alt > ph.alt) then
			if not ph then
				ph = {}
				self.photo = ph
			end
			ph.alt, ph.x, ph.y, ph.z = alt, self.x, self.y, self.z
			ph.vx, ph.vy, ph.roll, ph.air, ph.speed = self.vx, self.vy, self.roll, self.airStreak, self.speed
		end
		if clearance < F.SkimHeight and clearance > -1 and self.speed > F.SkimSpeed then
			self.skimT += dt
			if self.skimT >= F.SkimEvery then
				self.skimT = 0
				self.nitro = math.min(self.nitroMax, self.nitro + F.SkimNitro)
				self.perfects += 1
				self:link()
				PackFX.burst("dustRing", CFrame.new(self.x, self.y - R + 0.5, self.z), 6, self.track:cfgAt(self.x).ground:Lerp(Color3.new(1, 1, 1), 0.3), 0.9)
				self.onEvent({ kind = "skim", chain = self.chain, combo = self.combo })
			end
		else
			self.skimT = math.max(0, self.skimT - dt * 2)
		end
	else
		if self.airStreak > 0.6 then self.onEvent({ kind = "land", air = self.airStreak }) end
		self.longestAir = math.max(self.longestAir, self.airStreak)
		self.airStreak = 0
		self.skimT = 0
	end
	if self.chain > 0 then
		self.chainTimer -= dt
		if self.chainTimer <= 0 then self:breakChain("timeout") end
	end

	local ci = math.floor(self.x / TrackGen.ChunkSize)

	-- targets: land on one from above and it throws you back up; clip one from the side and it slows you
	local tgt, fromAbove = self:targetHit(px, py, vyTot)
	if tgt then
		if fromAbove then
			local impact = math.max(0, -vyTot)
			local k = math.clamp(impact / 160, 0.35, 1.4)
			local hs = math.max(math.cos(self.pitch) * s, 1) * 0.99
			local up = F.TargetKick * tgt.bounce * (stats.stage or 1) * k * (stats.glide or 1) ^ 0.3
			self.speed = math.sqrt(hs * hs + up * up)
			self.pitch = math.clamp(math.atan2(up, hs), 0.3, 1.0)
			self.aimPitch = math.max(self.aimPitch, self.pitch * 0.6)
			self.y = tgt.y + tgt.h + R
			self.fall = 0
			self.grounded = false
			self.nitro = math.min(self.nitroMax, self.nitro + 8)
			self.bounces += 1
			local clean = impact > 140
			if clean then self.perfects += 1 end
			self:link()
			self.squash = 0.8
			self.shake = math.min(2.6, self.shake + 0.8)
			self.hitStopUntil = os.clock() + 0.05
			self.world:targetHit(tgt.key, clean)
			Sound.play("land", { volume = 0.8, pitch = 1.0 + math.min(self.chain, 12) * 0.03 })
			self.onEvent({ kind = "bounce", perfect = clean, chain = self.chain, combo = self.combo, target = tgt.kind })
		else
			self.speed *= 0.88
			self.shake = math.min(3, self.shake + 1.2)
			self.hits += 1
			self.hitFlash = 1
			self.z += ((self.z >= tgt.z) and 1 or -1) * 6
			if self.chain > 0 then self:breakChain("hit") end
			playSound("rbxassetid://9114065998", 0.7, 0.8)
			self.onEvent({ kind = "hit" })
		end
	end

	-- smashables on the road: they pay and barely slow you
	for c = ci - 1, ci + 1 do
		if c >= 0 then
			local objs = track:objectsForChunk(c)
			for _, o in ipairs(objs.obstacles) do
				if not self.hitObstacles[o.key] and math.abs(self.x - o.x) < (o.d / 2 + R)
					and math.abs(self.z - o.z) < (o.w / 2 + R)
					and (self.y - R) < (o.y + o.h) and (self.y + R) > o.y then
					self.hitObstacles[o.key] = true
					local vel = Vector3.new(math.max(self.speed, 200), 0, 0)
					self.smashes += 1
					self:link()
					self.hitStopUntil = os.clock() + 0.05
					self.bonus += Config.Economy.CreditsPerSmash
					if self.zones then self.zones:smashed() end
					self.speed *= Config.Run.SmashKeep
					self.shake = math.min(3, self.shake + 0.7)
					self.world:shatter(o.key, vel)
					self.skills:smashOverride(o)
					self.skills:smashed(o, Vector3.new(o.x, o.y + o.h / 2, o.z))
					if o.breaks == "vending" then
						self.metals.bronze += 3
						self.onEvent({ kind = "metal", metal = "bronze", amount = 3 })
					end
					playSound("rbxassetid://9114065998", 0.8, 1.25)
					self.onEvent({ kind = "smash", total = self.smashes })
				end
			end
			for _, d in ipairs(objs.pads) do
				if not self.usedPads[d.key] and math.abs(self.x - d.x) < 18
					and math.abs(self.z - d.z) < (d.w / 2 + R) and (self.y - R - track:heightAt(d.x)) < 22 then
					self.usedPads[d.key] = true
					self.speed += (if self.zones then self.zones:padMult() else 1) * d.power * (stats.stage or 1) ^ 0.5 * math.clamp(1.25 - self.speed / F.KickFade, 0.15, 1)
					self.pitch = math.max(self.pitch, 0.32)
					self.aimPitch = math.max(self.aimPitch, 0.25)
					self.grounded = false
					self.pads += 1
					self.world:padFX(d.key)
					playSound("rbxassetid://9120386436", 0.6, 1.35)
					self.onEvent({ kind = "pad" })
				end
			end
		end
	end

	-- dust devils: a column of rising air
	for key, node in pairs(self.world.hazardNodes) do
		local d = node.data
		if not self.usedHazards[key] and math.abs(self.x - d.x) < d.radius * 1.4 and math.abs(self.z - node.z) < d.radius * 1.4
			and (self.y - track:heightAt(self.x)) < 120 then
			self.usedHazards[key] = true
			local hsD, vyD = math.cos(self.pitch) * self.speed, math.sin(self.pitch) * self.speed + d.lift * 0.7
			self.speed = math.sqrt(hsD * hsD + vyD * vyD)
			self.pitch = math.atan2(vyD, math.max(hsD, 1))
			self.grounded = false
			self.shake = math.min(3, self.shake + 1.2)
			self.onEvent({ kind = "dustdevil" })
		end
	end

	-- coins
	local coinReach = R + 14 + stats.magnetRadius * 0.5 * mods.magnetMult
	for key, node in pairs(self.world.metalNodes) do
		local d = node.data
		local ddx = d.x - self.x
		if ddx > -40 and ddx < 90 then
			local ddy, ddz = d.y - self.y, d.z - self.z
			if ddx * ddx + ddy * ddy + ddz * ddz <= coinReach * coinReach then
				self.world:markMetalCollected(key)
				self.metals[d.kind] = (self.metals[d.kind] or 0) + d.amount
				playSound("rbxassetid://9125402735", 0.55, d.kind == "gold" and 1.7 or (d.kind == "silver" and 1.4 or 1.15))
				self.onEvent({ kind = "metal", metal = d.kind, amount = d.amount })
			end
		end
	end

	-- keys: on the route, a little off the ring line
	local keyReach = R + 20 + stats.magnetRadius * 0.4 * mods.magnetMult
	for key, node in pairs(self.world.keyNodes or {}) do
		local d = node.data
		local ddx = d.x - self.x
		if ddx > -40 and ddx < 90 then
			local ddy, ddz = d.y - self.y, d.z - self.z
			if ddx * ddx + ddy * ddy + ddz * ddz <= keyReach * keyReach then
				self.world:markKeyCollected(key)
				self.keysGot += 1
				playSound("rbxassetid://9125402735", 0.9, 1.5)
				self.onEvent({ kind = "key", total = self.keysGot })
			end
		end
	end

	for i = #self.active, 1, -1 do
		if self.runTime >= self.active[i].expires then
			local gone = table.remove(self.active, i)
			self.onEvent({ kind = "expire", perk = gone.perk })
		end
	end
	self.multIntegral += (self.combo * mods.creditMult) * dt
	self.roll += (self.speed / R) * dt

	-- a difficulty tier (quiet: it only times the splits)
	local tier = Config.TierAt(self.x)
	if tier > (self.tier or 0) then
		self.tier = tier
		self.splits[tier] = math.floor(self.runTime * 10 + 0.5) / 10
	end
	-- a zone line: the gate, the banner, the new world
	local zi = if self.track.isRoad then self.track:zoneIndex(self.x) else self.zone
	if zi > (self.zone or 1) then
		self.zone = zi
		local zone = Game.Zones[zi]
		local line = self.track:zoneStart(zi)
		self.world:gateFX(Vector3.new(line, track:heightAt(line) + 18, self.z))
		self.gateLean = 1
		self.shake = math.min(3, self.shake + 0.8)
		Sound.play("gateWhoosh")
		local bestSplit = self.ghost and self.ghost.splits[tier] or nil
		if zone then self.dust.Color = ColorSequence.new(self.track:cfgAt(self.x).ground) end
		self.onEvent({ kind = "checkpoint", tier = tier, metres = self.x * P.StudsToMetres, split = self.runTime, bestSplit = bestSplit,
			zone = zi, zoneName = zone and zone.name or nil })
	end

	self.maxSpeed = math.max(self.maxSpeed, self.speed)
	if workspace:GetAttribute("PaceLog") and self.runTime >= (self.paceNext or 0) then
		self.paceNext = self.runTime + 1
		self.paceLog = self.paceLog or {}
		table.insert(self.paceLog, ("%.0fs %.0fm h%.0f v%.0f %s p%.0f z%.0f"):format(self.runTime, self.x * P.StudsToMetres, self.y - track:heightAt(self.x) - R, self.speed, self.grounded and "G" or "A", math.deg(self.pitch), self.z))
	end
	self.maxHeight = math.max(self.maxHeight, self.y - track:heightAt(self.x))
	self.runTime += dt
	if self.runTime >= self.nextSample and self.ghostChars < GHOST_MAX_CHARS then
		self.nextSample += GHOST_DT
		local entry = string.format("%d,%d,%d", math.floor(self.x + 0.5), math.floor(self.y - track:heightAt(self.x) - R + 0.5), math.floor(self.z + 0.5))
		table.insert(self.ghostRec, entry)
		self.ghostChars += #entry + 1
	end

	-- the run ends when it's rolling on the ground too slowly to take off again
	if self.grounded and self.speed < F.MinSpeed then
		self.stopTimer += dt
		if self.stopTimer >= F.StopGrace then
			if self.skills:rebirth("stop") then self.stopTimer = 0 else self:finish("stopped") end
		end
	else
		self.stopTimer = 0
	end
	if self.runTime > Config.Economy.MaxRunSeconds then self:finish("timeout") end

	-- the velocity the skills see, and a guard against a NaN freezing the run for good
	local cp3 = math.cos(self.pitch)
	self.vx = cp3 * math.cos(self.yaw) * self.speed
	self.vy = math.sin(self.pitch) * self.speed - self.fall
	self.vz = cp3 * math.sin(self.yaw) * self.speed
	if self.vx ~= self.vx or self.vy ~= self.vy or self.vz ~= self.vz or self.y ~= self.y or self.x ~= self.x then
		if not self.nanWarned then
			self.nanWarned = true
			warn(("[RunSim] NaN: x=%s y=%s speed=%s pitch=%s yaw=%s fall=%s grounded=%s last=%s"):format(
				tostring(self.x), tostring(self.y), tostring(self.speed), tostring(self.pitch), tostring(self.yaw),
				tostring(self.fall), tostring(self.grounded), tostring(self.lastEventKind)))
		end
		if self.x ~= self.x then self.x = self.lastGoodX or 0 end
		self.speed, self.pitch, self.yaw, self.fall = 60, 0.2, 0, 0
		self.y = track:heightAt(self.x) + R + 20
		self.vx, self.vy, self.vz = 60, 12, 0
		self.grounded = false
	else
		self.lastGoodX = self.x
	end
	self.wvx, self.wvy, self.wvz = self.vx, self.vy, self.vz
	-- the skills run after the velocity is set: whatever they add to it (Mini-Turbo, Drill Dash) is
	-- picked up at the top of the next step instead of being written over
	self.skills:step(dt)
	if self.zones then self.zones:step(dt) end
end

--==============================================================
-- frame
--==============================================================
-- the tyre's tuck glow: gold and pulsing when a tuck now pays (the road dropping away, or a hard
-- landing coming), a faint gold edge as one comes up, teal while it's tucked, a red flicker on a
-- cramp. It fades between them rather than switching.
local GLOW_GOLD = Color3.fromRGB(255, 205, 60)
local GLOW_TUCK = Color3.fromRGB(80, 230, 210)
local GLOW_CRAMP = Color3.fromRGB(230, 70, 60)
function RunSim:paintTuck(cue: string?, dt: number)
	local hl = self.tuckHl
	if not hl then return end
	local t = os.clock()
	local pulse = 0.5 + 0.5 * math.sin(t * 13)
	local col, fill, line = GLOW_GOLD, 1, 1
	if cue == "perfect" or cue == "land" then
		col, fill, line = GLOW_GOLD, 0.45 + 0.25 * pulse, 0
	elseif cue == "soon" then
		col, fill, line = GLOW_GOLD, 0.92, 0.45 + 0.3 * pulse
	elseif cue == "late" then
		col, fill, line = GLOW_CRAMP, 1, 0.5
	elseif self.tucking or cue == "braced" or cue == "tucked" then
		col, fill, line = GLOW_TUCK, 1 - 0.3 * (self.tuckAmt or 0), 0.15
	elseif (self.tuckCd or 0) > 0.25 then
		col, fill, line = GLOW_CRAMP, 1, 0.75
	end
	local k = math.min(1, dt * 14)
	self.glowFill = (self.glowFill or 1) + (fill - (self.glowFill or 1)) * k
	self.glowLine = (self.glowLine or 1) + (line - (self.glowLine or 1)) * k
	self.glowCol = (self.glowCol or col):Lerp(col, k)
	-- (not in first person: the camera's inside the tyre there)
	local on = (self.glowFill < 0.98 or self.glowLine < 0.98) and self.view ~= "first"
	if hl.Enabled ~= on then hl.Enabled = on end
	if on then
		hl.FillColor = self.glowCol
		hl.OutlineColor = self.glowCol
		hl.FillTransparency = self.glowFill
		hl.OutlineTransparency = self.glowLine
	end
end

function RunSim:frame(dt: number)
	if self.finished then return end
	-- the watchdog: a run that hasn't moved a stud in 6 real seconds is over, whatever caused it
	if math.abs(self.x - (self.wdX or -1)) > 1 then
		self.wdX = self.x
		self.wdAt = os.clock()
	elseif os.clock() - (self.wdAt or os.clock()) > 6 then
		self:finish("stalled")
		return
	end
	if self.timeScale < 1 and os.clock() >= (self.slowUntil or 0) then
		self.timeScale = math.min(1, self.timeScale + dt * 3)
	end

	self.mods = self:resolveMods()
	-- hit-stop: a smash or a ring freezes the world for a few frames so it lands
	if os.clock() >= (self.hitStopUntil or 0) then
		self.accumulator += dt * self.timeScale * self.skills.timeScale
	end
	local guard = 0
	while self.accumulator >= STEP and not self.finished and guard < 24 do
		self.accumulator -= STEP
		guard += 1
		self:step(STEP)
	end
	if self.finished then return end

	self.world:ensure(self.x)
	self.world:update(dt, self.x)
	self.skills:frame(dt)
	if self.zones then self.zones:frame(dt) end

	local R = P.TyreRadius
	local F = Config.Run
	local speedT = math.clamp(self.speed / 700, 0, 1.3)
	local airborne = not self.grounded
	local pos = Vector3.new(self.x, self.y, self.z)
	local groundHere = self.track:heightAt(self.x)
	local alt = math.max(0, self.y - groundHere - R)

	-- the tyre: heading, a lean into turns, rolling on its axle, sitting down on a hard landing
	self.squash = math.max(0, (self.squash or 0) - dt * 5)
	local sit = R * 0.16 * math.sin(math.min(self.squash, 1) * math.pi * 0.5)
	self.model:PivotTo(CFrame.new(pos - Vector3.new(0, sit, 0)) * CFrame.Angles(0, -self.yaw, 0)
		* CFrame.Angles(self.bank * 0.4, 0, 0) * CFrame.Angles(0, 0, -self.roll))
	self.fxAnchor.CFrame = CFrame.new(pos) * CFrame.Angles(0, -self.yaw, 0) * CFrame.Angles(0, 0, self.pitch)

	-- the shadow disc: where the tyre will come down
	if self.airShadow then
		if airborne and alt > 3 then
			local k = math.clamp(alt / 320, 0, 1)
			local d = R * 2 * (1 - k * 0.35)
			local slopeHere = math.atan(self.track:slopeAt(self.x))
			self.airShadow.Size = Vector3.new(0.12, d, d)
			self.airShadow.Transparency = 0.45 + k * 0.3
			self.airShadow.CFrame = CFrame.new(self.x, groundHere + 0.2, self.z) * CFrame.Angles(0, 0, slopeHere) * CFrame.Angles(0, 0, math.rad(90))
		else
			self.airShadow.Transparency = 1
		end
	end

	-- the ghost rolls along its own line on this road
	local ghostX = nil
	if self.ghost and self.ghostModel then
		local gx, ga, gz = self:ghostAt(self.runTime)
		ghostX = gx
		local gy = self.track:heightAt(gx) + R + math.max(0, ga)
		self.ghostModel:PivotTo(CFrame.new(gx, gy, gz) * CFrame.Angles(0, 0, -(gx / R)))
		local toCam = (Vector3.new(gx, gy, gz) - self.camera.CFrame.Position).Magnitude
		local fade = 0.62 + 0.33 * math.clamp(1 - (toCam - 30) / 60, 0, 1)
		if math.abs(fade - self.ghostFade) > 0.02 and self.ghostHighlight then
			self.ghostFade = fade
			self.ghostHighlight.FillTransparency = fade
			self.ghostHighlight.OutlineTransparency = math.clamp((fade - 0.62) * 2.5, 0.05, 0.9)
		end
	end

	for _, rv in ipairs(self.rivals or {}) do
		if rv.model then
			local gx, ga, gz = self:ghostAt(self.runTime, rv.ghost)
			local gy = self.track:heightAt(gx) + R + math.max(0, ga)
			rv.model:PivotTo(CFrame.new(gx, gy, gz) * CFrame.Angles(0, 0, -(gx / R)))
			local toCam = (Vector3.new(gx, gy, gz) - self.camera.CFrame.Position).Magnitude
			local fade = 0.7 + 0.27 * math.clamp(1 - (toCam - 30) / 60, 0, 1)
			if rv.hl and math.abs(fade - rv.fade) > 0.02 then
				rv.fade = fade
				rv.hl.FillTransparency = fade
				rv.hl.OutlineTransparency = math.clamp((fade - 0.7) * 2.5, 0.1, 0.9)
			end
		end
	end

	local windTier = self.wind:update(pos, -self.yaw, self.speed)
	if windTier > self.windTier then self.onEvent({ kind = "windTier", tier = windTier }) end
	self.windTier = windTier

	-- the nitro flame
	if self.flame then self.flame.set(self.usingBoost == true, 1.0) end
	if self.smoke then self.smoke.set(false) end
	if self.heatSkin then self.heatSkin.Transparency = 1 end

	if self.trailAnchor then
		self.trailAnchor.CFrame = CFrame.new(pos)
		self.trail.Enabled = airborne
		if self.trailSparks then self.trailSparks.Rate = airborne and (40 + speedT * 130) or 0 end
		if self.trailDef.rainbow then
			local h = (os.clock() * 0.25) % 1
			self.trail.Color = ColorSequence.new(Color3.fromHSV(h, 0.75, 1), Color3.fromHSV((h + 0.35) % 1, 0.8, 1))
		end
	end
	self.dust.Rate = (self.grounded) and (30 + speedT * 260) or 0
	if self.rumble then
		local target = math.clamp(0.08 + speedT * 0.5, 0, 0.7) * (self.grounded and 1 or 0.6)
		self.rumble.Volume += (target - self.rumble.Volume) * math.min(1, dt * 5)
		self.rumble.PlaybackSpeed = (0.62 + speedT * 0.95) * (0.4 + 0.6 * self.timeScale)
	end

	-- the camera (RunCamera): where it sits, where it looks and how wide it sees all come from the
	-- tyre's heading, speed, height over the road and the road around it, and ease as they change.
	self.shake = math.max(0, self.shake - dt * 3.2)
	local cs = self.cam
	if not cs then
		cs = RunCamera.new()
		self.cam = cs
	end
	local co = RunCamera.step(cs, {
		x = self.x, y = self.y, z = self.z, yaw = self.yaw, pitch = self.pitch, speed = self.speed,
		grounded = self.grounded, alt = alt, bank = self.bank, boosting = self.usingBoost == true,
		first = self.view == "first", radius = R,
	}, self.terrain, Config.Camera, dt)
	local eyeAt = Vector3.new(co.ex, co.ey, co.ez)
	local desired = CFrame.lookAt(eyeAt, Vector3.new(co.lx, co.ly, co.lz)) * CFrame.Angles(0, 0, co.roll)
	local fov = co.fov
	if self.introOffset then
		-- the perfect-launch swing: from side-on round to the chase, riding along with the tyre
		self.introT = (self.introT or 0) + dt
		local k = math.clamp((self.introT - 0.3) / 1.1, 0, 1)
		k = k * k * (3 - 2 * k)
		self.camCF = (CFrame.new(pos) * self.introOffset):Lerp(desired, k)
		if k >= 1 then self.introOffset = nil end
	else
		self.camCF = desired
	end
	self.gateLean = math.max(0, (self.gateLean or 0) - dt * 1.4)
	if self.weather then self.weather:update(pos, self.camCF.Position) end
	local sh = self.shake * (Prefs.get("shake") or 1) + (self.usingBoost and 0.18 or 0)
	local shakeCF = CFrame.new((math.random() - 0.5) * sh * 2.0, (math.random() - 0.5) * sh * 2.0, 0)
		* CFrame.Angles(0, 0, (math.random() - 0.5) * sh * 0.012 + math.sin((1 - self.gateLean) * math.pi) * self.gateLean * 0.14)
	self.camera.CFrame = self.camCF * shakeCF
	fov += self.gateLean * 8 + (self.skills and self.skills.fovAdd or 0)
	self.camera.FieldOfView += (fov - self.camera.FieldOfView) * math.min(1, dt * 6)

	-- the tuck cue: when a tuck now pays. On the ground, the road about to drop away (a PERFECT
	-- tuck); in the air, about to touch down hard enough to hurt (tuck to brace)
	local cue: string? = nil
	local tuckFree = not self.tucking and (self.tuckCd or 0) <= 0
	if self.grounded then
		-- the same test the tuck itself makes (and its grace), so the glow never lies
		if (self.perfectT or 0) > 0 then
			cue = if tuckFree then "perfect" elseif self.tucking then "tucked" else nil
		elseif self.speed > 60 and RunPhysics.perfectAhead(self, self.terrain, F, 2) then
			cue = "soon"
		elseif self.tucking then
			cue = "tucked"
		end
	else
		local vyNow = math.sin(self.pitch) * self.speed
		local hsNow = math.cos(self.pitch) * self.speed
		if vyNow < -5 and alt < 400 then
			local t = alt / -vyNow
			local tp = math.atan(self.track:slopeAt(self.x + hsNow * t))
			local impact = math.max(0, hsNow * math.sin(tp) - vyNow * math.cos(tp))
			if t < (F.BraceCue or 0.55) and impact > F.SoftImpact * 0.9 then
				cue = if self.tucking then "braced" elseif tuckFree then "land" else "late"
			end
		end
	end
	self.tuckCue = cue
	self:paintTuck(cue, dt)

	if self.onTick then
		local sk = self.skills
		local skCd = (sk and sk.skill and (sk.skill.cooldown or 0) > 0) and math.clamp(sk.cooldown / sk.skill.cooldown, 0, 1) or 0
		self.onTick({
			tuckCue = cue, tucking = self.tucking == true,
			skillName = sk and sk.skill and sk.skill.name or nil, skillKey = sk and sk.skill and sk.skill.key or nil,
			skillCd = skCd, skillLeft = sk and sk.cooldown or 0, skillActive = sk and sk:isActive() or false,
			skillCharge = sk and sk.turboTier or 0,
			floating = (self.aimPitch or 0) > 0.15 and not self.grounded, diving = (self.aimPitch or 0) < -0.15 and not self.grounded,
			x = self.x, y = self.y, z = self.z, roll = self.roll,
			trackId = self.trackId, seed = self.track.runSeed,
			speed = self.speed, distance = self.x, metres = self.x * P.StudsToMetres,
			altitude = alt, pitch = self.pitch, yaw = self.yaw,
			tuckFrac = if self.tucking then 1 - (self.tuckT or 0) / F.TuckWindow elseif (self.tuckCd or 0) > 0 then 0 else 1, tuckCool = (self.tuckCd or 0) > 0,
			nitro = self.nitro, nitroMax = self.nitroMax, nitroFrac = self.nitro / math.max(1, self.nitroMax), nitroDry = self.nitroDry == true,
			fuel = self.nitro, maxFuel = self.nitroMax,
			heat = 0, heatFrac = 0, redline = false, blown = false,
			combo = self.combo, comboTimer = self.chainTimer, chain = self.chain,
			active = self.active, slots = self.stats.perkSlots,
			grounded = self.grounded, airStreak = self.airStreak, runTime = self.runTime,
			boosting = self.usingBoost, stopping = self.stopTimer > 0.2, fatigued = self.fatigued == true,
			tier = self.tier or 0, stopFrac = self.stopTimer / F.StopGrace, hitFlash = self.hitFlash,
			windTier = windTier, metals = self.metals, tyrePos = pos,
			drafting = false, ghostX = ghostX, keys = self.keysGot,
			zone = if self.track.isRoad then self.track:zoneIndex(math.max(0, self.x)) else self.zone,
			draftLeft = 0,
			perfects = self.perfects, bounces = self.bounces,
			aimPoint = pos + Vector3.new(math.cos(self.pitch) * math.cos(self.yaw), math.sin(self.pitch), math.cos(self.pitch) * math.sin(self.yaw)) * 240,
			view = self.view, nitroOn = self.usingBoost == true,
		})
	end
	self.hitFlash = math.max(0, self.hitFlash - dt * 2.5)
end

--==============================================================
-- finish
--==============================================================
function RunSim:finish(reason: string)
	if self.finished then return end
	self.finished = true
	if workspace:GetAttribute("PaceLog") then
		print(("[PACE] %s bot=%s %.0fm %.1fs max=%.0f air=%.1fs chain=%d"):format(reason, tostring(self.bot), self.x * P.StudsToMetres, self.runTime, self.maxSpeed, self.longestAir, self.peakChain))
		workspace:SetAttribute("PaceResult", ("%s %s %.0fm %.1fs max%.0f chain%d | "):format(reason, tostring(self.bot), self.x * P.StudsToMetres, self.runTime, self.maxSpeed, self.peakChain) .. table.concat(self.paceLog or {}, " ; "))
	end
	self.draft = nil
	if self.skills then self.skills:destroy() end
	if self.zones then self.zones:destroy(); self.zones = nil end
	pcall(function() self.track:setSkillKind(nil) end)
	if self.conn then self.conn:Disconnect() end
	self:unbindInput()
	if self.rumble then self.rumble:Destroy(); self.rumble = nil end
	if self.focusFx then
		self.focusFx.dof:Destroy()
		self.focusFx.cc:Destroy()
		self.focusFx = nil
	end

	local avgMult = 1
	if self.runTime > 0.2 then avgMult = math.clamp(self.multIntegral / self.runTime, 1, 6) end
	local summary = {
		trackId = self.trackId,
		reason = reason,
		keys = self.keysGot,
		zone = self.track:zoneIndex(self.x),
		blowout = reason == "overheat",
		runTime = self.runTime,
		distance = self.x,
		metres = self.x * P.StudsToMetres,
		airTime = self.airTime,
		tier = self.tier or 0,
		perks = self.perkCount,
		spins = self.spins,
		pads = self.pads,
		bonus = self.bonus,
		avgMult = avgMult,
		maxSpeed = self.maxSpeed,
		maxHeight = self.maxHeight,
		seen = self.seen,
		found = self.found,
		smashes = self.smashes,
		hits = self.hits,
		longestAir = math.max(self.longestAir, self.airStreak),
		drafts = self.drafts,
		metals = self.metals,
		boosted = self.boosted,
		flawless = self.flawless,
		redlineSeconds = self.redlineSeconds,
		maxHeat = self.maxHeat,
		overheated = reason == "overheat",
		ghost = table.concat(self.ghostRec, ";"),
		splits = self.splits,
		startX = self.startX,
		bounces = self.bounces, perfects = self.perfects, goods = self.goods, skids = self.skids,
		peakChain = self.peakChain, comboMetres = self.comboMetres,
		photo = self.photo and {
			x = self.photo.x, y = self.photo.y, z = self.photo.z, vx = self.photo.vx, vy = self.photo.vy,
			roll = self.photo.roll, air = self.photo.air, speed = self.photo.speed,
		} or nil,
	}

	task.delay(0.05, function()
		if self.wind then self.wind:destroy() end
		if self.weather then self.weather:stop() end
		if self.world then self.world:destroy() end
		if self.folder then self.folder:Destroy() end
		for k, v in pairs(self.savedLighting) do (Lighting :: any)[k] = v end
		local a = self.savedAtmosphere
		if a and a.inst.Parent then
			for k, v in pairs(a) do
				if k ~= "inst" then (a.inst :: any)[k] = v end
			end
		end
		-- hand back only a camera the run took from the player; when the launch cutscene had it
		-- (Scriptable), Main's restoreCamera puts it back, and putting Scriptable back here a
		-- beat later would freeze the camera over the empty road
		if self.savedCamType ~= Enum.CameraType.Scriptable then
			self.camera.CameraType = self.savedCamType
			self.camera.FieldOfView = self.savedFov
		end
	end)
	if self.onEnd then task.spawn(self.onEnd, summary) end
end

function RunSim:abort()
	self:finish("aborted")
end

return RunSim
