--!strict
-- TYRE CANNON :: WorldView
-- Streams the visual road around the tyre: chunks are built ahead and torn
-- down behind, so an endless road costs a steady number of parts. Nothing
-- here decides physics; RunSim reads TrackGen directly and tells this module
-- what happened (a hit, a smash, a pickup) so it can show it.
-- On the road (TrackGen.get("road")) every chunk is built in its own zone's world: its land,
-- road markings, props, decor and obstacles; the light, fog and far hills change as you cross
-- each zone line. The Blender models (Models.luau) are used wherever they've been imported.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Config = require(Modules.Config)
local TrackGen = require(Modules.TrackGen)
local Assets = Root:WaitForChild("Assets")
local VFX = require(script.Parent.VFX)
local ZoneLook = require(script.Parent.ZoneLook)
local Icons = require(script.Parent.Icons)
local PackFX = require(script.Parent.PackFX)
local Models = require(script.Parent.Models)
local Game = require(Modules.Game)

local CHUNK = TrackGen.ChunkSize
local SEG = 25
local SEGS_PER_CHUNK = CHUNK / SEG
local GROUND_THICK = 70
local AHEAD_GROUND = 9
local AHEAD_DECOR = 6
local BEHIND = 2

-- the land beside the road
local LAND_SEG = 300
local MILESTONE = 100 / Config.Physics.StudsToMetres
local LAND_SINK = 1.8
local LAND_THICK = 40
local LAND_NEAR = 225
local LAND_FAR = 5200
local HORIZON_LOOP = 9600
local WHITE_PAINT = Color3.fromRGB(232, 232, 224)

-- what grows either side of each kind of road: strips of fields running alongside it,
-- a plain sheet past them, and low hills out in the haze
local LANDS = {
	fields = {
		road = "dirt",
		strip = { 90, 210 },
		fieldLen = { 450, 1100 },
		reach = 1900,
		-- Punjab in spring: mustard in flower, ripe wheat, green fodder, fresh-ploughed earth
		-- (MaterialVariants from art/blender/textures.py; the colour tints them a touch)
		palette = {
			{ Color3.fromRGB(255, 255, 255), Enum.Material.Grass, 4, "TC_Mustard" },
			{ Color3.fromRGB(255, 250, 240), Enum.Material.Grass, 3, "TC_Wheat" },
			{ Color3.fromRGB(255, 255, 255), Enum.Material.Grass, 3, "TC_Fodder" },
			{ Color3.fromRGB(245, 240, 235), Enum.Material.Ground, 2, "TC_Soil" },
		},
		-- far off the fields fade to a dusty olive (a flat green read as sea through the haze)
		far = { Color3.fromRGB(176, 168, 118), Enum.Material.Grass },
		roadVariant = "TC_Dirt",
		lane = 84,
		vergeVariant = "TC_Verge",
		countryside = "backroad",
		hills = { color = Color3.fromRGB(92, 110, 66), mat = Enum.Material.Grass, height = { 70, 170 } },
	},
	highway = {
		road = "highway",
		strip = { 140, 320 },
		fieldLen = { 700, 1600 },
		reach = 1900,
		-- the plains either side of the Grand Trunk: cane, dry scrub, fields left fallow after harvest
		palette = {
			{ Color3.fromRGB(255, 255, 255), Enum.Material.Grass, 3, "TC_Cane" },
			{ Color3.fromRGB(255, 255, 255), Enum.Material.Grass, 4, "TC_Scrub" },
			{ Color3.fromRGB(255, 250, 244), Enum.Material.Ground, 3, "TC_Fallow" },
			{ Color3.fromRGB(240, 250, 235), Enum.Material.Grass, 1, "TC_Wheat" },
		},
		far = { Color3.fromRGB(230, 226, 210), Enum.Material.Grass, "TC_Scrub" },
		roadVariant = "TC_Asphalt",
		vergeVariant = "TC_Scrub",
		countryside = "highway",
		hills = { color = Color3.fromRGB(124, 112, 90), mat = Enum.Material.Ground, height = { 140, 330 } },
	},
	desert = {
		road = "sand",
		strip = { 200, 420 },
		fieldLen = { 900, 2000 },
		reach = 1900,
		-- the Thar: rippled dune sand, hard gravel pans between
		palette = {
			{ Color3.fromRGB(255, 255, 255), Enum.Material.Sand, 5, "TC_Dune" },
			{ Color3.fromRGB(250, 244, 236), Enum.Material.Sand, 2, "TC_Dune" },
			{ Color3.fromRGB(255, 255, 255), Enum.Material.Ground, 2, "TC_Gravel" },
		},
		far = { Color3.fromRGB(255, 250, 240), Enum.Material.Sand, "TC_Dune" },
		roadVariant = "TC_Gravel",
		vergeVariant = "TC_Dune",
		countryside = "dunes",
		hills = { color = Color3.fromRGB(204, 160, 100), mat = Enum.Material.Sand, height = { 90, 240 } },
	},
	quarry = {
		road = "gravel",
		strip = { 120, 260 },
		fieldLen = { 500, 1200 },
		reach = 1900,
		palette = {
			{ Color3.fromRGB(150, 138, 122), Enum.Material.Slate, 3 },
			{ Color3.fromRGB(128, 116, 104), Enum.Material.Rock, 3 },
			{ Color3.fromRGB(170, 150, 120), Enum.Material.Ground, 2 },
			{ Color3.fromRGB(112, 104, 96), Enum.Material.Slate, 2 },
		},
		far = { Color3.fromRGB(140, 128, 112), Enum.Material.Rock },
		hills = { color = Color3.fromRGB(150, 132, 112), mat = Enum.Material.Rock, height = { 200, 420 } },
	},
	docks = {
		road = "dock",
		strip = { 160, 340 },
		fieldLen = { 800, 1800 },
		reach = 1900,
		palette = {
			{ Color3.fromRGB(44, 98, 146), Enum.Material.SmoothPlastic, 6 },
			{ Color3.fromRGB(58, 112, 156), Enum.Material.SmoothPlastic, 2 },
			{ Color3.fromRGB(128, 128, 134), Enum.Material.Concrete, 2 },
		},
		far = { Color3.fromRGB(38, 90, 138), Enum.Material.SmoothPlastic },
		hills = { color = Color3.fromRGB(98, 104, 118), mat = Enum.Material.Concrete, height = { 120, 260 } },
	},
	salt = {
		road = "salt",
		strip = { 300, 600 },
		fieldLen = { 900, 2200 },
		reach = 1900,
		palette = {
			{ Color3.fromRGB(242, 240, 234), Enum.Material.Salt, 4 },
			{ Color3.fromRGB(232, 230, 224), Enum.Material.Salt, 3 },
			{ Color3.fromRGB(220, 228, 236), Enum.Material.Salt, 2 },
		},
		far = { Color3.fromRGB(238, 238, 232), Enum.Material.Salt },
		hills = { color = Color3.fromRGB(176, 164, 178), mat = Enum.Material.Rock, height = { 80, 200 } },
	},
	mountain = {
		road = "snow",
		strip = { 150, 320 },
		fieldLen = { 600, 1400 },
		reach = 1900,
		palette = {
			{ Color3.fromRGB(242, 246, 252), Enum.Material.Snow, 4 },
			{ Color3.fromRGB(226, 232, 242), Enum.Material.Snow, 3 },
			{ Color3.fromRGB(72, 98, 82), Enum.Material.Grass, 1 },
			{ Color3.fromRGB(132, 138, 148), Enum.Material.Slate, 1 },
		},
		far = { Color3.fromRGB(232, 238, 246), Enum.Material.Snow },
		hills = { color = Color3.fromRGB(208, 218, 234), mat = Enum.Material.Snow, height = { 380, 760 } },
	},
	moon = {
		road = "moon",
		strip = { 200, 500 },
		fieldLen = { 700, 1600 },
		reach = 1900,
		palette = {
			{ Color3.fromRGB(150, 150, 156), Enum.Material.Basalt, 3 },
			{ Color3.fromRGB(132, 132, 140), Enum.Material.Basalt, 3 },
			{ Color3.fromRGB(168, 168, 174), Enum.Material.Slate, 2 },
		},
		far = { Color3.fromRGB(140, 140, 148), Enum.Material.Basalt },
		hills = { color = Color3.fromRGB(112, 112, 120), mat = Enum.Material.Basalt, height = { 140, 320 } },
	},
}

local function hash01(a: number, b: number): number
	local n = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return n - math.floor(n)
end

local function pickWeighted(list, h: number)
	local total = 0
	for _, p in ipairs(list) do total += p[3] end
	local r = h * total
	for _, p in ipairs(list) do
		r -= p[3]
		if r <= 0 then return p end
	end
	return list[#list]
end

local WorldView = {}
WorldView.__index = WorldView

local rng = Random.new()

local function newPart(parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Parent = parent
	return p
end

-- a MaterialVariant on a part; the colour stays as a tint, eased toward white so the texture's
-- own colours show
local MaterialService = game:GetService("MaterialService")
local function textured(p: BasePart, variant: string?, tint: Color3?)
	if not variant then return end
	-- a variant only shows on its own base material
	local v = MaterialService:FindFirstChild(variant)
	if not (v and v:IsA("MaterialVariant")) then return end
	p.Material = v.BaseMaterial
	p.MaterialVariant = variant
	p.Color = Color3.new(1, 1, 1):Lerp(tint or p.Color, 0.35)
end

--==============================================================
-- model helpers
--==============================================================
local function partsOf(inst: Instance): { BasePart }
	local list = {}
	if inst:IsA("BasePart") then table.insert(list, inst) end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(list, d) end
	end
	return list
end

local function asModel(inst: Instance): Model
	if inst:IsA("Model") then return inst end
	local m = Instance.new("Model")
	m.Name = inst.Name
	inst.Parent = m
	if inst:IsA("BasePart") then m.PrimaryPart = inst end
	return m
end

-- uniform scale about the pivot, including file-mesh scales
local function scaleModel(m: Model, s: number)
	if math.abs(s - 1) < 1e-3 then return end
	local pivot = m:GetPivot()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d.Size *= s
			d.CFrame = pivot * (CFrame.new(rel.Position * s) * rel.Rotation)
		elseif d:IsA("SpecialMesh") and d.MeshType == Enum.MeshType.FileMesh then
			d.Scale *= s
			d.Offset *= s
		elseif d:IsA("Attachment") then
			d.Position *= s
		end
	end
end

-- place so the bounding box bottom sits on `ground` at (x, z)
local function plant(m: Model, x: number, ground: number, z: number, yaw: number, sink: number?)
	local cf, size = m:GetBoundingBox()
	local offset = m:GetPivot():ToObjectSpace(cf)
	local target = CFrame.new(x, ground + size.Y / 2 - (sink or 0), z) * CFrame.Angles(0, yaw, 0)
	m:PivotTo(target * offset:Inverse())
end

local function settle(inst: Instance, shadows: boolean)
	for _, p in ipairs(partsOf(inst)) do
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = shadows
	end
end

local function fling(p: BasePart, vel: Vector3, spin: number)
	p.Anchored = false
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.AssemblyLinearVelocity = vel
	p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-spin, spin), rng:NextNumber(-spin, spin), rng:NextNumber(-spin, spin))
end

local function fadeAndClear(inst: Instance, after: number)
	task.delay(after, function()
		if not inst.Parent then return end
		for _, p in ipairs(partsOf(inst)) do
			TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(inst, after + 0.7)
end

--==============================================================
-- parent: where the world goes (a ViewportFrame's WorldModel for a photo). opts.scenery builds
-- only the road, props, decor and obstacles: no pickups, pads or gate labels. opts.backdrop is the
-- same road with its land, horizon and light all round it (the loading scene): no pickups, pads,
-- targets or gate labels either.
function WorldView.new(trackId: string, parent: Instance?, opts: { [string]: any }?)
	local self = setmetatable({}, WorldView)
	self.backdrop = opts ~= nil and opts.backdrop == true
	self.sceneryOnly = opts ~= nil and (opts.scenery == true or opts.backdrop == true)
	self.track = TrackGen.get(trackId)
	self.cfg = self.track.cfg
	self.land = LANDS[self.cfg.scenery] or LANDS.fields
	self.strips = {}
	self.keyNodes = {}
	self.chunks = {}
	self.perkNodes = {}
	self.padNodes = {}
	self.toolNodes = {}
	self.metalNodes = {}
	self.obstacleNodes = {}
	self.hazardNodes = {}
	self.targetNodes = {}
	self.collected = {}
	self.t = 0

	local root = Instance.new("Folder")
	root.Name = "TyreCannonWorld"
	root.Parent = parent or workspace
	self.root = root
	local debris = Instance.new("Folder")
	debris.Name = "Debris"
	debris.Parent = root
	self.debris = debris

	if not self.sceneryOnly or self.backdrop then
		self:buildApron()
		self:buildHorizon()
		if self.track.isRoad then self:buildSkirt() end
	end
	-- the road's zones each bring their own light, grade, haze and air
	if self.track.isRoad and (not self.sceneryOnly or self.backdrop) then self.look = ZoneLook.new() end
	return self
end

-- builds every chunk that covers x0..x1, for a still of one stretch of road
-- the world under x: the zone's config and the land that goes with it
function WorldView:cfgAt(x: number)
	return self.track:cfgAt(x)
end

function WorldView:landAt(x: number)
	return LANDS[self.track:cfgAt(x).scenery] or LANDS.fields
end

-- how deep into its own zone a chunk is, as a band step (the palette darkens a little as you go)
function WorldView:bandFor(ci: number)
	local x = ci * CHUNK + CHUNK / 2
	if self.track.isRoad then
		return Config.BandFor(self:cfgAt(x), math.floor(self.track:zoneFrac(x) * 4))
	end
	return Config.BandFor(self.cfg, Config.TierAt(ci * CHUNK))
end

function WorldView:buildRange(x0: number, x1: number)
	for ci = math.max(0, math.floor(x0 / CHUNK)), math.max(0, math.floor(x1 / CHUNK)) do
		self:buildChunk(ci, true)
	end
end

function WorldView:buildApron()
	local cfg = self.cfg
	local half = Config.Physics.CorridorHalfWidth
	local land = self.land
	local shoulder = newPart(self.root, "ApronShoulder", Vector3.new(430, GROUND_THICK, half * 2 + 190),
		CFrame.new(-180, -GROUND_THICK / 2 - 1.2, 0), cfg.ground:Lerp(Color3.fromRGB(90, 110, 60), 0.32), cfg.groundMaterial, true)
	textured(shoulder, land.vergeVariant, Color3.new(1, 1, 1))
	local apron = newPart(self.root, "Apron", Vector3.new(430, GROUND_THICK, half * 2),
		CFrame.new(-180, -GROUND_THICK / 2, 0), cfg.ground, cfg.groundMaterial, true)
	textured(apron, land.roadVariant, Color3.new(1, 1, 1))
	-- the land carries on behind the launch too
	local far = land.far
	local behind = newPart(self.root, "ApronLand", Vector3.new(1650, LAND_THICK, LAND_FAR * 2),
		CFrame.new(-825, -LAND_SINK - LAND_THICK / 2, 0), far[1], far[2])
	textured(behind, far[3], far[1])
end

--==============================================================
-- the land and the horizon
--==============================================================
function WorldView:landStrips(side: number, land)
	land = land or self.land
	self.strips[land] = self.strips[land] or {}
	local cached = self.strips[land][side]
	if cached then return cached end
	local r = Random.new(self.track.runSeed * 7919 + (side > 0 and 1 or 2))
	local list = {}
	local z = LAND_NEAR
	local i = 0
	while z < land.reach do
		i += 1
		local w = r:NextNumber(land.strip[1], land.strip[2])
		table.insert(list, {
			z0 = z, z1 = math.min(land.reach, z + w),
			len = r:NextNumber(land.fieldLen[1], land.fieldLen[2]), phase = r:NextNumber(0, 1),
			salt = r:NextInteger(1, 999999), lift = (i % 2) * 0.12,
		})
		z += w
	end
	self.strips[land][side] = list
	return list
end

-- fields in long strips beside the road, each strip cut into fields of its own length, and
-- one sheet past them out to the haze. Deeper in, the land takes on the band's colour.
function WorldView:buildLand(f: Instance, ci: number, band, land)
	land = land or self.land
	local track = self.track
	local t = math.clamp(band.tier, 0, 7) / 7
	local deep = band.ground
	local function sheet(x0: number, x1: number): (CFrame, number)
		local y0, y1 = track:baseHeight(x0) - LAND_SINK, track:baseHeight(x1) - LAND_SINK
		local run = x1 - x0
		return CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0) * CFrame.Angles(0, 0, math.atan2(y1 - y0, run)), math.sqrt(run * run + (y1 - y0) ^ 2) + 0.6
	end
	for s = 0, math.floor(CHUNK / LAND_SEG) - 1 do
		local x0 = ci * CHUNK + s * LAND_SEG
		local top, len = sheet(x0, x0 + LAND_SEG)
		local xm = x0 + LAND_SEG / 2
		for _, side in ipairs({ -1, 1 }) do
			for _, st in ipairs(self:landStrips(side, land)) do
				local p = pickWeighted(land.palette, hash01(st.salt, math.floor(xm / st.len + st.phase)))
				local field = newPart(f, "Field", Vector3.new(len, LAND_THICK, st.z1 - st.z0), top * CFrame.new(0, -LAND_THICK / 2 + st.lift, side * (st.z0 + st.z1) / 2),
					p[1]:Lerp(deep, t * 0.4), p[2])
				textured(field, p[4], p[1]:Lerp(deep, t * 0.4))
			end
		end
	end
	local top, len = sheet(ci * CHUNK, (ci + 1) * CHUNK)
	for _, side in ipairs({ -1, 1 }) do
		local farLand = newPart(f, "FarLand", Vector3.new(len, LAND_THICK, LAND_FAR - land.reach), top * CFrame.new(0, -LAND_THICK / 2 - 0.4, side * (land.reach + LAND_FAR) / 2),
			land.far[1]:Lerp(deep, t * 0.4), land.far[2])
		textured(farLand, land.far[3], land.far[1]:Lerp(deep, t * 0.4))
	end
end

-- low hills out in the haze: lying cylinders sunk so only their crowns show. They're real
-- scenery, so they slide past, and the ones left behind are carried round to the front.
function WorldView:buildHorizon()
	local hills = self.land.hills
	local folder = Instance.new("Folder")
	folder.Name = "Horizon"
	folder.Parent = self.root
	local r = Random.new(self.track.runSeed * 131 + 17)
	self.hills = {}
	local count = 18
	for i = 1, count do
		local side = (i % 2 == 0) and 1 or -1
		local d = r:NextNumber(1500, 2040)
		local hill = {
			x = (i - 1) / count * HORIZON_LOOP - 1800 + r:NextNumber(-250, 250),
			z = side * r:NextNumber(2500, 4300),
			h = r:NextNumber(hills.height[1], hills.height[2]),
			d = d,
		}
		local p = newPart(folder, "Hill", Vector3.new(r:NextNumber(1100, 2040), d, d), CFrame.new(), hills.color:Lerp(Color3.new(0, 0, 0), r:NextNumber(0, 0.12)), hills.mat)
		p.Shape = Enum.PartType.Cylinder
		hill.part = p
		self.hills[i] = hill
		self:placeHill(hill)
	end
end

-- the ground out to the horizon, under everything: big tiles that ride along with the tyre, so
-- there is never an edge to the world however high the tyre goes
local SKIRT_TILE = 2048
local SKIRT_COLS, SKIRT_ROWS = 7, 5
function WorldView:buildSkirt()
	local folder = Instance.new("Folder")
	folder.Name = "Skirt"
	folder.Parent = self.root
	self.skirt = {}
	for i = 1, SKIRT_COLS * SKIRT_ROWS do
		local p = newPart(folder, "SkirtTile", Vector3.new(SKIRT_TILE, 8, SKIRT_TILE), CFrame.new(), self.land.far[1], self.land.far[2])
		table.insert(self.skirt, p)
	end
	self.skirtAt = nil
	self:placeSkirt(0)
	self:paintSkirt(self.land)
end

function WorldView:placeSkirt(x: number)
	local cx = math.floor(x / SKIRT_TILE + 0.5) * SKIRT_TILE
	if self.skirtAt == cx then return end
	self.skirtAt = cx
	local i = 0
	for c = 1, SKIRT_COLS do
		local tx = cx + (c - (SKIRT_COLS + 1) / 2) * SKIRT_TILE
		-- sit below the lowest land across the tile, so it never shows through the fields
		local low = math.huge
		for k = 0, 20 do
			low = math.min(low, self.track:baseHeight(math.max(0, tx - SKIRT_TILE / 2 + k * SKIRT_TILE / 20)))
		end
		for r = 1, SKIRT_ROWS do
			i += 1
			local tz = (r - (SKIRT_ROWS + 1) / 2) * SKIRT_TILE
			self.skirt[i].CFrame = CFrame.new(tx, low - LAND_SINK - 6, tz)
		end
	end
end

function WorldView:paintSkirt(land)
	for _, p in ipairs(self.skirt or {}) do
		p.Material = land.far[2]
		p.MaterialVariant = ""
		p.Color = land.far[1]
		textured(p, land.far[3], land.far[1])
	end
end

function WorldView:recolourHills(land)
	if not self.hills or self.hillLand == land then return end
	self.hillLand = land
	self:paintSkirt(land)
	local r = Random.new(self.track.runSeed * 17 + 3)
	for _, hill in ipairs(self.hills) do
		local p = hill.part
		p.Material = land.hills.mat
		TweenService:Create(p, TweenInfo.new(1.4), { Color = land.hills.color:Lerp(Color3.new(0, 0, 0), r:NextNumber(0, 0.12)) }):Play()
		hill.h = r:NextNumber(land.hills.height[1], land.hills.height[2])
		self:placeHill(hill)
	end
end

function WorldView:placeHill(hill)
	local base = self.track:baseHeight(math.max(0, hill.x)) - LAND_SINK - 2
	hill.part.CFrame = CFrame.new(hill.x, base + hill.h - hill.d / 2, hill.z)
end

-- The road is drawn as straight slabs between samples every SEG studs, so anything that
-- sits on it has to sit on the slab, not on the smooth curve under it: on a steep kicker the
-- two are studs apart. Returns the slab's height and its pitch at x.
function WorldView:roadY(x: number): (number, number)
	local s0 = math.floor(x / SEG) * SEG
	local y0, y1 = self.track:heightAt(s0), self.track:heightAt(s0 + SEG)
	return y0 + (y1 - y0) * ((x - s0) / SEG), math.atan2(y1 - y0, SEG)
end

-- the ground a thing stands on at (x, z): the shoulder by the road, the fields past it
function WorldView:groundAt(x: number, z: number): number
	if math.abs(z) <= LAND_NEAR then
		return (self:roadY(x)) - 1.2
	end
	return self.track:baseHeight(x) - LAND_SINK
end

-- one flat triangle from two wedges
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, color: Color3, mat: Enum.Material)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	if ac:Cross(ab).Magnitude < 1e-4 then return end
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	for i = 1, 2 do
		local w = Instance.new("WedgePart")
		w.Name = "RampSide"
		w.Anchored = true
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.CastShadow = false
		w.Color = color
		w.Material = mat
		if i == 1 then
			w.Size = Vector3.new(0.2, height, math.abs(ab:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
		else
			w.Size = Vector3.new(0.2, height, math.abs(ac:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
		end
		w.Parent = parent
	end
end

-- a bank down each side of a raised stretch of road: from the shoulder's edge, exactly where
-- the slab ends, down to the fields. Each stretch is two triangles, so neighbours share edges
-- and nothing floats or gaps.
function WorldView:rampSides(f: Instance, x0: number, x1: number, y0: number, y1: number, b0: number, b1: number, _theta: number, color: Color3, land)
	local t0, t1 = y0 - 1.2, y1 - 1.2
	local g0, g1 = b0 - LAND_SINK - 0.4, b1 - LAND_SINK - 0.4
	local h0, h1 = t0 - g0, t1 - g1
	if math.max(h0, h1) < 0.5 then return end
	local r0 = math.clamp(math.max(h0, 0) * 2.3, 1, 160)
	local r1 = math.clamp(math.max(h1, 0) * 2.3, 1, 160)
	local mat = (land or self.land).far[2]
	for side = -1, 1, 2 do
		local a = Vector3.new(x0, t0, side * LAND_NEAR)
		local b = Vector3.new(x1, t1, side * LAND_NEAR)
		local c = Vector3.new(x1, g1, side * (LAND_NEAR + r1))
		local d = Vector3.new(x0, g0, side * (LAND_NEAR + r0))
		triangle(f, a, b, c, color, mat)
		triangle(f, a, c, d, color, mat)
	end
end

-- red and white blocks painted across a kicker's lip
function WorldView:rampLip(f: Instance, x: number)
	local half = Config.Physics.CorridorHalfWidth
	local gy, pitch = self:roadY(x)
	local cf = CFrame.new(x, gy, 0) * CFrame.Angles(0, 0, pitch)
	local cells = 13
	local cw = half * 2 / cells
	for c = 0, cells - 1 do
		newPart(f, "Lip", Vector3.new(3.2, 0.24, cw), cf * CFrame.new(0, 0.12, -half + (c + 0.5) * cw),
			c % 2 == 0 and Color3.fromRGB(206, 36, 40) or WHITE_PAINT, Enum.Material.SmoothPlastic)
	end
end

-- a milestone at the roadside: white stone, yellow cap, the distance painted on its face
function WorldView:milestone(f: Instance, x: number, metres: number)
	local half = Config.Physics.CorridorHalfWidth
	local z = half + 9
	local gy = self:groundAt(x, z)
	local stone = newPart(f, "Milestone", Vector3.new(1.8, 4.2, 3), CFrame.new(x, gy + 2.1, z), Color3.fromRGB(236, 234, 226), Enum.Material.SmoothPlastic)
	stone.CastShadow = true
	local cap = newPart(f, "MilestoneCap", Vector3.new(1.8, 3, 3), CFrame.new(x, gy + 4.2, z), Color3.fromRGB(242, 190, 40), Enum.Material.SmoothPlastic)
	cap.Shape = Enum.PartType.Cylinder
	cap.CastShadow = true
	newPart(f, "MilestoneBase", Vector3.new(2.4, 0.5, 3.6), CFrame.new(x, gy + 0.25, z), Color3.fromRGB(150, 146, 138), Enum.Material.Concrete)
	if self.sceneryOnly then return end
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Left
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0.6
	sg.MaxDistance = 700
	sg.Parent = stone
	local function line(text: string, y: number, h: number, weight: Enum.FontWeight)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.new(0, 8, y, 0)
		l.Size = UDim2.new(1, -16, h, 0)
		l.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", weight)
		l.Text = text
		l.TextColor3 = Color3.fromRGB(30, 30, 32)
		l.TextScaled = true
		l.Parent = sg
	end
	local shown = metres >= 1000 and string.format("%.1f", metres / 1000) or tostring(metres)
	line(shown, 0.2, 0.36, Enum.FontWeight.ExtraBold)
	line(metres >= 1000 and "KM" or "M", 0.58, 0.2, Enum.FontWeight.Bold)
end

-- where your best run on this road ended: a gold and black line across the road and a sign
-- at each side with your name on it
function WorldView:markBest(best: number?, name: string?)
	if not best or best < 300 then return end
	local half = Config.Physics.CorridorHalfWidth
	local f = Instance.new("Folder")
	f.Name = "BestLine"
	f.Parent = self.root
	local gy, pitch = self:roadY(best)
	local cf = CFrame.new(best, gy, 0) * CFrame.Angles(0, 0, pitch)
	local gold = Color3.fromRGB(246, 196, 64)
	newPart(f, "BestLine", Vector3.new(8, 0.2, half * 2), cf * CFrame.new(0, 0.13, 0), gold, Enum.Material.SmoothPlastic)
	local cells = 26
	local cw = half * 2 / cells
	for row = 0, 1 do
		for c = 0, cells - 1 do
			if (c + row) % 2 == 0 then
				newPart(f, "BestCheck", Vector3.new(4, 0.24, cw), cf * CFrame.new(-2 + row * 4, 0.15, -half + (c + 0.5) * cw), Color3.fromRGB(22, 22, 24), Enum.Material.SmoothPlastic)
			end
		end
	end
	local steel = Color3.fromRGB(62, 64, 70)
	for side = -1, 1, 2 do
		local z = side * (half + 12)
		local sy = self:groundAt(best, z)
		for _, dz in ipairs({ -9, 9 }) do
			newPart(f, "BestPost", Vector3.new(0.8, 16, 0.8), CFrame.new(best, sy + 8, z + dz), steel, Enum.Material.Metal).CastShadow = true
		end
		local board = newPart(f, "BestBoard", Vector3.new(0.6, 7, 22), CFrame.new(best - 0.2, sy + 12.5, z), Color3.fromRGB(24, 24, 28), Enum.Material.SmoothPlastic)
		board.CastShadow = true
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Left
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 24
		sg.LightInfluence = 0.5
		sg.MaxDistance = 1600
		sg.Parent = board
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(1, 0, 0, 12)
		stripe.BackgroundColor3 = gold
		stripe.BorderSizePixel = 0
		stripe.Parent = sg
		local function line(text: string, y: number, h: number, color: Color3, weight: Enum.FontWeight)
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Position = UDim2.new(0, 16, y, 0)
			l.Size = UDim2.new(1, -32, h, 0)
			l.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", weight)
			l.Text = text
			l.TextColor3 = color
			l.TextScaled = true
			l.Parent = sg
		end
		line(string.upper(name or "YOUR") .. "'S BEST", 0.16, 0.34, Color3.fromRGB(246, 244, 238), Enum.FontWeight.ExtraBold)
		local m = math.floor(best * Config.Physics.StudsToMetres)
		line(tostring(m):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") .. " M", 0.56, 0.3, gold, Enum.FontWeight.Bold)
	end
end

-- the painted and worn marks on one stretch of road, by the kind of road it is
function WorldView:markRoad(f: Instance, s: number, top: CFrame, len: number, band, verge: Color3, land)
	local half = Config.Physics.CorridorHalfWidth
	local style = (land or self.land).road
	if style == "highway" then
		-- six lanes: dashes between them, a double line down the middle, solid edges
		if s % 2 == 0 then
			for _, lz in ipairs({ -86, -43, 43, 86 }) do
				newPart(f, "Lane", Vector3.new(len * 0.5, 0.2, 1.4), top * CFrame.new(0, 0.1, lz), WHITE_PAINT, Enum.Material.SmoothPlastic)
			end
		end
		for _, lz in ipairs({ -1.4, 1.4 }) do
			newPart(f, "Centre", Vector3.new(len + 0.4, 0.2, 1), top * CFrame.new(0, 0.1, lz), band.accent, Enum.Material.SmoothPlastic)
		end
		for side = -1, 1, 2 do
			newPart(f, "EdgeLine", Vector3.new(len + 0.4, 0.2, 2), top * CFrame.new(0, 0.1, side * (half - 6)), WHITE_PAINT, Enum.Material.SmoothPlastic)
			-- (2026-10-23, speed you can feel) white delineator posts with an amber reflector every 50 studs
			if s % 2 == 0 then
				newPart(f, "Delineator", Vector3.new(0.7, 3.6, 0.7), top * CFrame.new(0, 1.8, side * (half - 2)), WHITE_PAINT, Enum.Material.SmoothPlastic)
				newPart(f, "Reflector", Vector3.new(0.75, 0.7, 0.75), top * CFrame.new(0, 3.1, side * (half - 2)), Color3.fromRGB(255, 150, 30), Enum.Material.SmoothPlastic)
			end
		end
	elseif style == "dirt" then
		-- worn wheel ruts, and the verge creeping in along the edges
		local rut = band.ground:Lerp(Color3.new(0, 0, 0), 0.16)
		for _, rz in ipairs({ -74, -58, 58, 74 }) do
			newPart(f, "Rut", Vector3.new(len + 0.4, 0.12, 7), top * CFrame.new(0, 0.06, rz), rut, Enum.Material.Ground)
		end
		for side = -1, 1, 2 do
			newPart(f, "Verge", Vector3.new(len + 0.4, 0.14, 26), top * CFrame.new(0, 0.07, side * (half - 13)), verge, Enum.Material.Grass)
		end
		-- (2026-10-23, speed you can feel) whitewashed edge stones with a red band, every 50 studs along
		-- the lane, as on village roads: low enough to roll over, close enough to stream past
		local laneW = (land or self.land).lane
		if laneW and s % 2 == 0 then
			for side = -1, 1, 2 do
				local z = side * (laneW / 2 + 3)
				newPart(f, "EdgeStone", Vector3.new(2.2, 1.6, 2.2), top * CFrame.new(0, 0.7, z), WHITE_PAINT, Enum.Material.Concrete)
				newPart(f, "EdgeBand", Vector3.new(2.26, 0.45, 2.26), top * CFrame.new(0, 1.2, z), Color3.fromRGB(196, 52, 40), Enum.Material.SmoothPlastic)
			end
		end
	elseif style == "gravel" then
		-- a haul road: deep truck ruts and a gravel berm along each edge
		local rut = band.ground:Lerp(Color3.new(0, 0, 0), 0.2)
		for _, rz in ipairs({ -66, -46, 46, 66 }) do
			newPart(f, "Rut", Vector3.new(len + 0.4, 0.14, 9), top * CFrame.new(0, 0.07, rz), rut, Enum.Material.Ground)
		end
		for side = -1, 1, 2 do
			newPart(f, "Berm", Vector3.new(len + 0.4, 1.6, 8), top * CFrame.new(0, 0.6, side * (half - 4)), band.ground:Lerp(Color3.fromRGB(90, 84, 78), 0.4), Enum.Material.Slate)
		end
	elseif style == "dock" then
		-- a quay: yellow edge lines, and a bollard every so often
		for side = -1, 1, 2 do
			newPart(f, "EdgeLine", Vector3.new(len + 0.4, 0.2, 2.4), top * CFrame.new(0, 0.1, side * (half - 7)), band.accent, Enum.Material.SmoothPlastic)
			if s % 4 == 0 then
				local b = newPart(f, "Bollard", Vector3.new(3.4, 3.2, 3.4), top * CFrame.new(0, 1.6, side * (half - 2.5)), Color3.fromRGB(40, 42, 46), Enum.Material.Metal)
				b.Shape = Enum.PartType.Cylinder
				b.CFrame = top * CFrame.new(0, 1.6, side * (half - 2.5)) * CFrame.Angles(0, 0, math.rad(90))
				b.CastShadow = true
			end
		end
		if s % 2 == 0 then
			newPart(f, "Dash", Vector3.new(len * 0.5, 0.2, 1.4), top * CFrame.new(0, 0.1, 0), WHITE_PAINT, Enum.Material.SmoothPlastic)
		end
	elseif style == "salt" then
		-- a speed course: a blue line down the middle, blue marker dashes either side
		newPart(f, "Course", Vector3.new(len + 0.4, 0.16, 3), top * CFrame.new(0, 0.08, 0), band.accent, Enum.Material.SmoothPlastic)
		if s % 2 == 0 then
			for _, lz in ipairs({ -70, 70 }) do
				newPart(f, "Marker", Vector3.new(len * 0.4, 0.16, 1.6), top * CFrame.new(0, 0.08, lz), band.accent, Enum.Material.SmoothPlastic)
			end
		end
	elseif style == "snow" then
		-- packed snow: grey slush tracks and banks of snow along the edges
		local slush = band.ground:Lerp(Color3.fromRGB(120, 128, 140), 0.35)
		for _, rz in ipairs({ -60, -44, 44, 60 }) do
			newPart(f, "Slush", Vector3.new(len + 0.4, 0.12, 8), top * CFrame.new(0, 0.06, rz), slush, Enum.Material.Ice)
		end
		for side = -1, 1, 2 do
			newPart(f, "Bank", Vector3.new(len + 0.4, 2.2, 10), top * CFrame.new(0, 0.8, side * (half - 5)), Color3.fromRGB(246, 248, 252), Enum.Material.Snow)
		end
	elseif style == "moon" then
		-- regolith: faint rover tracks
		if s % 3 ~= 1 then
			for _, rz in ipairs({ -24, -12 }) do
				newPart(f, "Track", Vector3.new(len + 0.4, 0.1, 3), top * CFrame.new(0, 0.05, rz), band.ground:Lerp(Color3.new(0, 0, 0), 0.18), Enum.Material.Basalt)
			end
		end
	else
		-- (2026-10-23, speed you can feel) a wooden stake marking the track every 75 studs
		if s % 3 == 0 then
			for side = -1, 1, 2 do
				newPart(f, "Stake", Vector3.new(0.6, 2.6, 0.6), top * CFrame.new(0, 1.2, side * 58) * CFrame.Angles(0, 0, side * 0.08), Color3.fromRGB(120, 88, 58), Enum.Material.Wood)
			end
		end
		-- sand: old tracks half blown over
		if s % 3 ~= 2 then
			local rut = band.ground:Lerp(Color3.fromRGB(120, 90, 60), 0.14)
			for _, rz in ipairs({ -40, -26 }) do
				newPart(f, "Rut", Vector3.new(len + 0.4, 0.1, 6), top * CFrame.new(0, 0.05, rz), rut, Enum.Material.Sand)
			end
		end
	end
end

-- a checkpoint is a gantry over the road: two lattice towers, a truss, a banner facing the
-- road coming in, and a chequered line across the ground
function WorldView:makeGate(f: Instance, n: number, dist: number, band)
	local half = Config.Physics.CorridorHalfWidth
	local gy = self:roadY(dist)
	local steel = Color3.fromRGB(62, 64, 70)
	local span = half + 12
	local H = 46
	local function steelPart(name: string, size: Vector3, cf: CFrame): Part
		local p = newPart(f, name, size, cf, steel, Enum.Material.Metal)
		p.CastShadow = true
		return p
	end
	for side = -1, 1, 2 do
		local z = side * span
		newPart(f, "GateFoot", Vector3.new(9, 2.4, 9), CFrame.new(dist, gy + 1.2, z), Color3.fromRGB(128, 126, 120), Enum.Material.Concrete).CastShadow = true
		for _, o in ipairs({ { -1.8, -1.8 }, { 1.8, -1.8 }, { -1.8, 1.8 }, { 1.8, 1.8 } }) do
			steelPart("GateLeg", Vector3.new(0.8, H, 0.8), CFrame.new(dist + o[1], gy + 2.4 + H / 2, z + o[2]))
		end
		for k = 1, 5 do
			local y = gy + 2.4 + k * (H / 6)
			steelPart("GateRung", Vector3.new(4.4, 0.45, 0.45), CFrame.new(dist, y, z - 1.8))
			steelPart("GateRung", Vector3.new(4.4, 0.45, 0.45), CFrame.new(dist, y, z + 1.8))
			steelPart("GateRung", Vector3.new(0.45, 0.45, 4.4), CFrame.new(dist - 1.8, y, z))
			steelPart("GateRung", Vector3.new(0.45, 0.45, 4.4), CFrame.new(dist + 1.8, y, z))
		end
	end
	local topY = gy + 2.4 + H
	for _, y in ipairs({ topY, topY - 6 }) do
		for _, dx in ipairs({ -1.8, 1.8 }) do
			steelPart("GateChord", Vector3.new(0.7, 0.7, span * 2 + 4), CFrame.new(dist + dx, y, 0))
		end
	end
	local bays = 14
	local bay = span * 2 / bays
	for b = 0, bays do
		local z = -span + b * bay
		for _, dx in ipairs({ -1.8, 1.8 }) do
			steelPart("GateStrut", Vector3.new(0.45, 6, 0.45), CFrame.new(dist + dx, topY - 3, z))
			if b < bays then
				local a, c = Vector3.new(dist + dx, topY - 6, z), Vector3.new(dist + dx, topY, z + bay)
				steelPart("GateBrace", Vector3.new(0.4, 0.4, (c - a).Magnitude), CFrame.lookAt((a + c) / 2, c))
			end
		end
	end
	local banner = newPart(f, "GateBanner", Vector3.new(1, 15, 96), CFrame.new(dist - 2.6, topY - 14.5, 0), Color3.fromRGB(24, 24, 28), Enum.Material.SmoothPlastic)
	banner.CastShadow = true
	for _, bz in ipairs({ -40, 40 }) do
		steelPart("GateHanger", Vector3.new(0.3, 7, 0.3), CFrame.new(dist - 2.2, topY - 3.5, bz))
	end
	if not self.sceneryOnly then
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Left
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 10
		sg.LightInfluence = 0.5
		sg.MaxDistance = 2000
		sg.Parent = banner
		local stripe = Instance.new("Frame")
		stripe.AnchorPoint = Vector2.new(0, 1)
		stripe.Position = UDim2.fromScale(0, 1)
		stripe.Size = UDim2.new(1, 0, 0, 14)
		stripe.BackgroundColor3 = band.accent
		stripe.BorderSizePixel = 0
		stripe.Parent = sg
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(20, 10)
		title.Size = UDim2.new(1, -40, 0, 82)
		title.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
		local entering = self.track.isRoad and Game.Zones[n + 1]
		title.Text = entering and string.upper(entering.name) or ("CHECKPOINT " .. n)
		title.TextColor3 = Color3.fromRGB(246, 244, 238)
		title.TextScaled = true
		title.Parent = sg
		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromOffset(20, 94)
		sub.Size = UDim2.new(1, -40, 0, 30)
		sub.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
		sub.Text = string.format("%d M", math.floor(dist * Config.Physics.StudsToMetres))
		sub.TextColor3 = Color3.fromRGB(190, 188, 182)
		sub.TextScaled = true
		sub.Parent = sg
	end
	local _, gatePitch = self:roadY(dist)
	local roadCF = CFrame.new(dist, gy, 0) * CFrame.Angles(0, 0, gatePitch)
	newPart(f, "FinishLine", Vector3.new(8, 0.2, half * 2), roadCF * CFrame.new(0, 0.12, 0), WHITE_PAINT, Enum.Material.SmoothPlastic)
	local cells = 26
	local cw = half * 2 / cells
	for row = 0, 1 do
		for c = 0, cells - 1 do
			if (c + row) % 2 == 0 then
				newPart(f, "FinishCheck", Vector3.new(4, 0.22, cw), roadCF * CFrame.new(-2 + row * 4, 0.14, -half + (c + 0.5) * cw), Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic)
			end
		end
	end
end

--==============================================================
-- quirk tokens: a steel disc standing on edge with a rarity-coloured rim, the quirk's glyph
-- on both faces, turning slowly so you catch the face as you come in
--==============================================================
function WorldView:makePerkIcon(parent: Instance, data)
	local perk = Config.PerksById[data.perkId]
	if not perk then return nil end
	local info = Config.Rarity[perk.rarity]
	local m = Instance.new("Model")
	m.Name = "Quirk_" .. perk.id
	m.Parent = parent
	local origin = CFrame.new(data.x, data.y, data.z)

	local core = newPart(m, "Core", Vector3.new(2.4, 15, 15), origin, Color3.fromRGB(40, 42, 47), Enum.Material.Metal)
	core.Shape = Enum.PartType.Cylinder
	core.CastShadow = true
	local ring = newPart(m, "Ring", Vector3.new(2, 17.4, 17.4), origin, info.color, Enum.Material.SmoothPlastic)
	ring.Shape = Enum.PartType.Cylinder
	ring.Reflectance = 0.12
	ring.CastShadow = true

	for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		sg.CanvasSize = Vector2.new(256, 256)
		sg.LightInfluence = 0.25
		sg.Brightness = 1.4
		sg.MaxDistance = 1600
		sg.Parent = core
		local disc = Instance.new("ImageLabel")
		disc.Size = UDim2.fromScale(1, 1)
		disc.BackgroundTransparency = 1
		disc.Image = Icons.Hud.tokenFace
		disc.Parent = sg
		local glyph = Instance.new("ImageLabel")
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromScale(0.64, 0.64)
		glyph.BackgroundTransparency = 1
		glyph.Image = Icons.forPerk(perk)
		glyph.ImageColor3 = info.color
		glyph.ZIndex = 2
		glyph.Parent = sg
	end

	-- its name, small, once it's close enough to matter
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(20, 2.6)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 12.5, 0)
	bb.MaxDistance = 240
	bb.LightInfluence = 0
	bb.Parent = core
	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(1, 1)
	name.BackgroundTransparency = 1
	name.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
	name.Text = string.upper(perk.name)
	name.TextColor3 = info.color
	name.TextScaled = true
	name.Parent = bb
	local edge = Instance.new("UIStroke")
	edge.Thickness = 2
	edge.Transparency = 0.2
	edge.Parent = name

	return { model = m, core = core, ring = ring, data = data, perk = perk, baseY = data.y, info = info }
end

--==============================================================
-- toolboxes (code-built, waiting on models)
--==============================================================
local TOOL_SHAPES = {
	drum = function(m, cf, col, mat)
		local body = newPart(m, "Body", Vector3.new(13, 9, 9), cf * CFrame.Angles(0, 0, math.rad(90)), col, mat)
		body.Shape = Enum.PartType.Cylinder
		for _, o in ipairs({ -3.4, 3.4 }) do
			local h = newPart(m, "Band", Vector3.new(0.9, 10, 10), cf * CFrame.new(0, o, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 42, 46), Enum.Material.Metal)
			h.Shape = Enum.PartType.Cylinder
		end
		return body
	end,
	trophy = function(m, cf, col, mat)
		newPart(m, "Plinth", Vector3.new(12, 2.4, 12), cf * CFrame.new(0, -5, 0), Color3.fromRGB(58, 44, 32), Enum.Material.WoodPlanks)
		local body = newPart(m, "Body", Vector3.new(10, 11, 10), cf, col, mat)
		body.Transparency = 0.18
		newPart(m, "Cup", Vector3.new(3.2, 6, 3.2), cf * CFrame.new(0, -0.5, 0), Color3.fromRGB(240, 200, 90), Enum.Material.Metal)
		return body
	end,
	stake = function(m, cf, col, mat)
		newPart(m, "Post", Vector3.new(1.6, 16, 1.6), cf * CFrame.new(0, -1, 0), Color3.fromRGB(150, 120, 84), Enum.Material.Wood)
		return newPart(m, "Body", Vector3.new(1.1, 7, 12), cf * CFrame.new(0, 4.5, 5), col, mat)
	end,
}

-- the same boxes the workbench forges, by kind
local KIND_MODEL = { drum = "Toolbox", trophy = "ToolboxRed", stake = "ToolboxBlue" }

function WorldView:makeToolbox(parent: Instance, data)
	local kind = Config.ToolboxKindsById[data.kind]
	local rar = Config.ToolboxRaritiesById[data.rarity]
	if not kind or not rar then return nil end
	local workshop = Assets:FindFirstChild("Workshop")
	local tpl = workshop and workshop:FindFirstChild(KIND_MODEL[kind.id] or "Toolbox")
	if tpl then
		local box = asModel(tpl:Clone())
		for _, d in ipairs(box:GetDescendants()) do
			if d:IsA("LuaSourceContainer") or d:IsA("Light") then d:Destroy() end
		end
		local _, size = box:GetBoundingBox()
		scaleModel(box, 11 / math.max(size.X, size.Y, size.Z, 0.1))
		settle(box, true)
		box:PivotTo(CFrame.new(data.x, data.y, data.z))
		box.Name = "Toolbox_" .. kind.id
		-- rarity reads as an outline, the way the workbench shows it
		local h = Instance.new("Highlight")
		h.FillTransparency = 1
		h.OutlineColor = rar.color
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = box
		box.Parent = parent
		local cf = box:GetBoundingBox()
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.one
		body.Transparency = 1
		body.Anchored = true
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
		body.CFrame = CFrame.new(cf.Position)
		body.Parent = box
		return { model = box, body = body, data = data, kind = kind, rarity = rar, baseY = data.y }
	end
	local m = Instance.new("Model")
	m.Name = "Toolbox_" .. kind.id
	m.Parent = parent
	local origin = CFrame.new(data.x, data.y, data.z)
	local mat = rar.glow > 0.5 and Enum.Material.Neon or Enum.Material.Metal
	local body = (TOOL_SHAPES[kind.id] or TOOL_SHAPES.trophy)(m, origin, rar.color, mat)
	if rar.glow > 0 then
		local light = Instance.new("PointLight")
		light.Color = rar.color
		light.Range = 26
		light.Brightness = rar.glow * 2.4
		light.Parent = body
	end
	local beam = newPart(m, "ToolBeacon", Vector3.new(4, 300, 4), origin * CFrame.new(0, 150, 0), rar.color, Enum.Material.Neon)
	beam.Transparency = 0.9
	return { model = m, body = body, data = data, kind = kind, rarity = rar, baseY = data.y }
end

--==============================================================
-- keys (the road): one per zone, standing over the road, turning
--==============================================================
local KEY_GOLD = Color3.fromRGB(255, 200, 52)

function WorldView:makeKey(parent: Instance, data)
	local m: Model
	local tpl = Models.get("Run/Key")
	if tpl then
		m = Models.place(tpl, parent, CFrame.new(data.x, data.y - 3, data.z), 1.3)
	else
		m = Instance.new("Model")
		m.Name = "Key"
		local function gold(name: string, size: Vector3, cf: CFrame, shape: Enum.PartType?): Part
			local p = newPart(m, name, size, cf, KEY_GOLD, Enum.Material.Metal)
			if shape then p.Shape = shape end
			p.Reflectance = 0.2
			p.CastShadow = true
			return p
		end
		-- a bow (a tyre: black ring on a gold rim), a shaft and two teeth
		local tyre = newPart(m, "Bow", Vector3.new(1.4, 7.2, 7.2), CFrame.new(-4, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic)
		tyre.Shape = Enum.PartType.Cylinder
		gold("Rim", Vector3.new(1.6, 4.4, 4.4), CFrame.new(-4, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Enum.PartType.Cylinder)
		gold("Shaft", Vector3.new(8, 1.3, 1.3), CFrame.new(2, 0, 0))
		gold("ToothA", Vector3.new(1.3, 2.4, 1.1), CFrame.new(4.6, -1.6, 0))
		gold("ToothB", Vector3.new(1.3, 1.6, 1.1), CFrame.new(2.6, -1.2, 0))
		m.PrimaryPart = m:FindFirstChild("Shaft") :: BasePart
		m:PivotTo(CFrame.new(data.x, data.y, data.z))
		m.Parent = parent
	end
	-- seen from far off: a tall pole at the road's edge with a gold pennant on top (a thing, not a light)
	-- the far side of the lane from the camera (which sits on +Z), so the pole never hides the key
	local side = data.z > 0 and 1 or -1
	local poleZ = data.z + side * 11
	local gy = self:groundAt(data.x, poleZ)
	local marker = Instance.new("Model")
	marker.Name = "KeyMarker"
	local pole = newPart(marker, "Pole", Vector3.new(0.5, 46, 0.5), CFrame.new(data.x, gy + 23, poleZ), Color3.fromRGB(40, 38, 36), Enum.Material.Metal)
	pole.CastShadow = true
	newPart(marker, "Knob", Vector3.new(1.1, 1.1, 1.1), CFrame.new(data.x, gy + 46.4, poleZ), KEY_GOLD, Enum.Material.Metal).Shape = Enum.PartType.Ball
	local flag = newPart(marker, "Pennant", Vector3.new(9, 5, 0.2), CFrame.new(data.x - 4.5, gy + 43, poleZ), KEY_GOLD, Enum.Material.Fabric)
	flag.CastShadow = true
	-- a key stencilled on it
	newPart(marker, "Stencil", Vector3.new(4.6, 0.8, 0.24), CFrame.new(data.x - 4.2, gy + 43, poleZ), Color3.fromRGB(70, 50, 14), Enum.Material.Fabric)
	newPart(marker, "StencilBow", Vector3.new(0.24, 2, 2), CFrame.new(data.x - 7, gy + 43, poleZ) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(70, 50, 14), Enum.Material.Fabric).Shape = Enum.PartType.Cylinder
	marker.PrimaryPart = pole
	marker.Parent = parent
	local box = m:GetBoundingBox()
	return { model = m, beam = marker, flag = flag, flagRest = flag.CFrame, data = data, baseCF = box, offset = box:ToObjectSpace(m:GetPivot()) }
end

function WorldView:markKeyCollected(key: string)
	self.collected[key] = true
	local n = self.keyNodes[key]
	if not n then return end
	self.keyNodes[key] = nil
	PackFX.burst("dustPuff", CFrame.new(n.data.x, n.data.y, n.data.z), 12, KEY_GOLD:Lerp(Color3.new(1, 1, 1), 0.5), 1.6)
	if n.beam then n.beam:Destroy() end
	task.spawn(function()
		local ti = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		pcall(function()
			for _, p in ipairs(n.model:GetDescendants()) do
				if p:IsA("BasePart") then TweenService:Create(p, ti, { Transparency = 1, Size = p.Size * 0.2 }):Play() end
			end
		end)
		task.wait(0.34)
		if n.model and n.model.Parent then n.model:Destroy() end
	end)
end

--==============================================================
-- coins (metal)
--==============================================================
function WorldView:makeMetal(parent: Instance, data)
	local def = Config.MetalsById[data.kind]
	if not def then return nil end
	-- (2026-10-23: the Blender coin (hubkit.coin) files as a Model holding one mesh; the old stock disc
	-- was a bare MeshPart. Either lies flat and is stood up by Upright; its baked look is dropped so
	-- the Metal colour below shows)
	local found = Assets.Props:FindFirstChild("Coin")
	local tpl: BasePart? = nil
	if found and found:IsA("Model") then
		tpl = found.PrimaryPart or found:FindFirstChildWhichIsA("BasePart")
	elseif found and found:IsA("BasePart") then
		tpl = found
	end
	local coin: BasePart
	local upright = CFrame.new()
	if tpl then
		coin = tpl:Clone()
		local sa = coin:FindFirstChildOfClass("SurfaceAppearance")
		if sa then sa:Destroy() end
		coin.Size = tpl.Size * 2.4
		upright = (found :: Instance):GetAttribute("Upright") or tpl:GetAttribute("Upright") or CFrame.Angles(math.pi / 2, 0, 0)
	else
		coin = newPart(nil, "Coin", Vector3.new(6.7, 1.1, 7), CFrame.new(), def.color, Enum.Material.Metal)
		coin.Shape = Enum.PartType.Cylinder
	end
	coin.Name = "Coin_" .. def.id
	coin.Color = def.color
	coin.Material = Enum.Material.Metal
	coin.Reflectance = 0.25
	coin.Anchored = true
	coin.CanCollide = false
	coin.CanQuery = false
	coin.CanTouch = false
	coin.CastShadow = false
	coin.CFrame = CFrame.new(data.x, data.y, data.z) * upright
	coin.Parent = parent
	local light = Instance.new("PointLight")
	light.Color = def.color
	light.Range = 14
	light.Brightness = 1
	light.Parent = coin
	return { model = coin, data = data, def = def, upright = upright }
end

function WorldView:markMetalCollected(key: string)
	self.collected[key] = true
	local n = self.metalNodes[key]
	if not n then return end
	self.metalNodes[key] = nil
	local coin = n.model
	TweenService:Create(coin, TweenInfo.new(0.2), { Transparency = 1, Size = coin.Size * 0.3 }):Play()
	Debris:AddItem(coin, 0.25)
end

--==============================================================
-- sonic pads
--==============================================================
function WorldView:makePad(parent: Instance, d)
	local tpl = Assets.Props:FindFirstChild("SonicPad") :: BasePart?
	local pad: BasePart
	if tpl then
		pad = tpl:Clone()
		local s = d.w / tpl.Size.X
		pad.Size = tpl.Size * s
	else
		pad = newPart(nil, "Pad", Vector3.new(d.w, 1.2, 30), CFrame.new(), Color3.fromRGB(90, 250, 255), Enum.Material.Neon)
	end
	pad.Name = "SonicPad"
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false
	pad.CastShadow = false
	pad.CFrame = CFrame.new(d.x, d.y + pad.Size.Y / 2 + 0.1, d.z) * CFrame.Angles(0, math.rad(90) + (d.yaw or 0), 0)
	pad.Parent = parent
	-- no glow: the pad is hardware, and using it throws dust
	if pad.Material == Enum.Material.Neon then pad.Material = Enum.Material.Metal end
	return { pad = pad, data = d }
end

function WorldView:padFX(key: string)
	local n = self.padNodes[key]
	if not n then return end
	PackFX.burst("dustPuff", CFrame.new(n.pad.Position + Vector3.new(0, 1, 0)), 14, self.cfg.ground:Lerp(Color3.new(1, 1, 1), 0.35), 2.2)
end

--==============================================================
-- obstacles
--==============================================================
function WorldView:makeObstacle(parent: Instance, o)
	local tpl = o.runModel and Models.get("Run/" .. o.runModel)
	local blender = tpl ~= nil
	if not tpl and o.model then
		local src = Assets.World:FindFirstChild(o.folder or "Obstacles")
		tpl = src and src:FindFirstChild(o.model)
	end
	local m: Model
	if tpl then
		-- Blender pieces face the oncoming tyre: their front (+Z in the model frame) turned to -X
		m = blender and Models.copy(tpl) or asModel(tpl:Clone())
		if blender then Models.turn(m, CFrame.Angles(0, -math.pi / 2, 0)) end
		local _, size = m:GetBoundingBox()
		scaleModel(m, o.h / math.max(size.Y, 0.1))
		plant(m, o.x, (self:roadY(o.x)), o.z, o.yaw, 0.2)
		settle(m, true)
	else
		m = Instance.new("Model")
		m.Name = o.kind
		local p = newPart(m, "Body", Vector3.new(o.d, o.h, o.w), CFrame.new(o.x, o.y + o.h / 2, o.z) * CFrame.Angles(0, o.yaw, 0), o.color, o.mat)
		p.CastShadow = true
		m.PrimaryPart = p
	end
	m.Parent = parent
	return { model = m, data = o }
end

-- slower than smash speed: it gets knocked out of the way and tumbles
function WorldView:knock(key: string, velocity: Vector3)
	self.collected[key] = true
	local n = self.obstacleNodes[key]
	if not n then return end
	self.obstacleNodes[key] = nil
	local m = n.model
	m.Parent = self.debris
	local parts = partsOf(m)
	local main = parts[1]
	for _, p in ipairs(parts) do
		if p.Size.Magnitude > main.Size.Magnitude then main = p end
	end
	for _, p in ipairs(parts) do
		if p ~= main then
			p.Anchored = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = main
			w.Part1 = p
			w.Parent = p
		end
	end
	fling(main, Vector3.new(velocity.X * 0.55 + 30, rng:NextNumber(45, 80), velocity.Z * 0.5 + rng:NextNumber(-60, 60)), 9)
	VFX.emit("LandSmoke", CFrame.new(main.Position - Vector3.new(0, n.data.h * 0.4, 0)), { scale = 3 })
	fadeAndClear(m, 3)
end

-- at smash speed it comes apart; what that looks like depends on what it is
function WorldView:shatter(key: string, velocity: Vector3)
	self.collected[key] = true
	local n = self.obstacleNodes[key]
	if not n then return end
	self.obstacleNodes[key] = nil
	local o = n.data
	local m = n.model
	local cf, size = m:GetBoundingBox()
	local centre = cf.Position
	local push = Vector3.new(velocity.X * 0.7, 0, velocity.Z * 0.3)
	VFX.emit("Shatter", CFrame.new(centre), { scale = math.clamp(o.h / 9, 0.8, 2.2) })

	local breaks = o.breaks or "chunks"
	if breaks == "vending" or breaks == "trash" then
		self:knockModel(m, push * 0.8 + Vector3.new(0, 70, 0), 14)
		if breaks == "vending" then
			local coin = Assets.Props:FindFirstChild("Coin") :: BasePart?
			for _ = 1, 10 do
				local c = coin and coin:Clone() or newPart(nil, "Coin", Vector3.new(2.8, 0.5, 2.9), CFrame.new(), Config.MetalsById.bronze.color, Enum.Material.Metal)
				c.Color = Config.MetalsById.bronze.color
				c.Material = Enum.Material.Metal
				c.CFrame = CFrame.new(centre + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(0, 4), rng:NextNumber(-2, 2)))
				c.Parent = self.debris
				fling(c, push * rng:NextNumber(0.4, 0.9) + Vector3.new(0, rng:NextNumber(50, 110), rng:NextNumber(-60, 60)), 20)
				fadeAndClear(c, 2)
			end
		end
		return
	end

	m:Destroy()
	if breaks == "rocks" then
		local rock = Assets.World.Obstacles:FindFirstChild("Rock_1")
		local rockPart = rock and rock:FindFirstChildWhichIsA("BasePart")
		for _ = 1, 7 do
			local bit: BasePart
			if rockPart then
				bit = (rockPart :: BasePart):Clone()
				bit.Size = (rockPart :: BasePart).Size * (o.h / 7.6) * rng:NextNumber(0.25, 0.45)
			else
				local s = o.h * rng:NextNumber(0.2, 0.35)
				bit = newPart(nil, "Rock", Vector3.new(s, s, s), CFrame.new(), o.color, o.mat)
			end
			bit.CFrame = CFrame.new(centre + Vector3.new(rng:NextNumber(-1, 1) * size.X * 0.3, rng:NextNumber(-0.2, 0.4) * size.Y, rng:NextNumber(-1, 1) * size.Z * 0.3))
				* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
			bit.CastShadow = true
			bit.Parent = self.debris
			fling(bit, push * rng:NextNumber(0.5, 1) + Vector3.new(0, rng:NextNumber(40, 110), rng:NextNumber(-80, 80)), 14)
			fadeAndClear(bit, 2.2)
		end
	elseif breaks == "log" then
		local log = Assets.World.Obstacles:FindFirstChild("Log")
		local logPart = log and (log:IsA("BasePart") and log or log:FindFirstChildWhichIsA("BasePart"))
		for _, side in ipairs({ -1, 1 }) do
			local half: BasePart
			if logPart then
				half = (logPart :: BasePart):Clone()
				local k = o.h / (logPart :: BasePart).Size.Y
				half.Size = Vector3.new(logPart.Size.X * k, logPart.Size.Y * k, logPart.Size.Z * k * 0.5)
			else
				half = newPart(nil, "Log", Vector3.new(o.d, o.h, o.w * 0.5), CFrame.new(), o.color, o.mat)
			end
			half.CFrame = CFrame.new(centre + Vector3.new(0, 0, side * o.w * 0.25)) * CFrame.Angles(0, o.yaw, 0)
			half.CastShadow = true
			half.Parent = self.debris
			fling(half, push * 0.6 + Vector3.new(0, rng:NextNumber(50, 80), side * rng:NextNumber(60, 110)), 10)
			fadeAndClear(half, 2.5)
		end
	else
		for ix = -1, 1, 2 do
			for iy = -1, 1, 2 do
				for iz = -1, 1, 2 do
					local s = Vector3.new(o.d, o.h, o.w) * 0.5
					local chunk = newPart(nil, "Chunk", s, cf * CFrame.new(ix * s.X * 0.5, iy * s.Y * 0.5, iz * s.Z * 0.5), o.color, o.mat)
					chunk.CastShadow = true
					chunk.Parent = self.debris
					fling(chunk, push * rng:NextNumber(0.5, 1) + Vector3.new(0, rng:NextNumber(40, 100) + iy * 20, iz * rng:NextNumber(30, 90)), 12)
					fadeAndClear(chunk, 2)
				end
			end
		end
	end
end

function WorldView:knockModel(m: Model, velocity: Vector3, spin: number)
	m.Parent = self.debris
	local parts = partsOf(m)
	local main = parts[1]
	if not main then return end
	for _, p in ipairs(parts) do
		if p.Size.Magnitude > main.Size.Magnitude then main = p end
	end
	for _, p in ipairs(parts) do
		if p ~= main then
			p.Anchored = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = main
			w.Part1 = p
			w.Parent = p
		end
	end
	fling(main, velocity, spin)
	fadeAndClear(m, 3)
end

--==============================================================
-- bounce targets (v3): a model standing side-on across the lane, scaled so its top is the landing
-- height, with a ring painted over that top: dim until the tyre is coming down over it, then lit
--==============================================================
local RING_IDLE = Color3.fromRGB(255, 214, 90)
local RING_HOT = Color3.fromRGB(120, 255, 140)

function WorldView:makeTarget(parent: Instance, t)
	local tpl = Models.get(t.path)
	local m: Model
	if tpl then
		m = Models.copy(tpl)
		for _, p in ipairs(partsOf(m)) do
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = true
		end
		m:PivotTo(CFrame.new())
		local _, size = m:GetBoundingBox()
		-- long side along the road, so the camera sees it side-on and the landing length reads
		if size.Z > size.X * 1.05 then
			m:PivotTo(CFrame.Angles(0, math.pi / 2, 0))
			_, size = m:GetBoundingBox()
		end
		local s = t.h / math.max(size.Y, 0.1)
		m:ScaleTo(m:GetScale() * s)
		local box = m:GetBoundingBox()
		local ground = (self:roadY(t.x))
		local _, sz = m:GetBoundingBox()
		m:PivotTo(CFrame.new(t.x - box.Position.X, ground - (box.Position.Y - sz.Y / 2) - 0.2, t.z - box.Position.Z) * m:GetPivot())
		-- pivot on its foot, so the squash on a hit sits it down into the road
		local foot = CFrame.new(t.x, ground - 0.2, t.z) * (m:GetPivot() - m:GetPivot().Position)
		if m.PrimaryPart then
			m.PrimaryPart.PivotOffset = m.PrimaryPart.CFrame:ToObjectSpace(foot)
		else
			m.WorldPivot = foot
		end
	else
		m = Instance.new("Model")
		m.Name = t.kind
		local body = newPart(m, "Body", Vector3.new(t.len, t.h, 14), CFrame.new(t.x, t.y + t.h / 2, t.z), Color3.fromRGB(203, 168, 84), Enum.Material.Grass)
		body.CastShadow = true
		m.PrimaryPart = body
	end
	m.Name = "Target_" .. t.kind
	m.Parent = parent
	-- the ring over the top: where you want to come down
	local top = (self:roadY(t.x)) + t.h
	local ring = newPart(parent, "TargetRing", Vector3.new(0.3, t.len + 6, t.len + 6), CFrame.new(t.x, top + 0.6, t.z) * CFrame.Angles(0, 0, math.rad(90)), RING_IDLE, Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.72
	ring.CastShadow = false
	local hole = newPart(parent, "TargetRingCore", Vector3.new(0.34, t.len + 1, t.len + 1), CFrame.new(t.x, top + 0.62, t.z) * CFrame.Angles(0, 0, math.rad(90)), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	hole.Shape = Enum.PartType.Cylinder
	hole.Transparency = 0.86
	hole.CastShadow = false
	return { model = m, ring = ring, hole = hole, data = t, top = top, scale = m:GetScale(), pivot = m:GetPivot(), hot = 0 }
end

-- 0..1: how lit the ring is (the tyre coming down over it)
function WorldView:targetHeat(key: string, k: number)
	local n = self.targetNodes[key]
	if not n or math.abs(k - n.hot) < 0.03 then return end
	n.hot = k
	n.ring.Color = RING_IDLE:Lerp(RING_HOT, k)
	n.ring.Transparency = 0.72 - 0.5 * k
end

-- a bounce off it: it squashes and springs back, the ring flashes, a puff of its own dust
function WorldView:targetHit(key: string, perfect: boolean)
	local n = self.targetNodes[key]
	if not n then return end
	local m, base, pivot = n.model, n.scale, n.pivot
	n.ring.Color = perfect and Color3.fromRGB(255, 236, 120) or RING_HOT
	n.ring.Transparency = 0.1
	TweenService:Create(n.ring, TweenInfo.new(0.5), { Transparency = 1 }):Play()
	TweenService:Create(n.hole, TweenInfo.new(0.5), { Transparency = 1 }):Play()
	PackFX.burst("dustPuff", CFrame.new(n.data.x, n.top, n.data.z), perfect and 16 or 9,
		(perfect and Color3.fromRGB(255, 226, 120) or Color3.fromRGB(230, 220, 200)), perfect and 1.8 or 1.2)
	task.spawn(function()
		local t0 = os.clock()
		while m.Parent do
			local t = os.clock() - t0
			if t > 0.45 then break end
			-- down to 70% and back with a wobble (the Blender pivot is on the ground, so it squashes
			-- into the road rather than shrinking in mid-air)
			local k = 1 - 0.3 * math.exp(-t * 9) * math.cos(t * 26)
			pcall(function() m:ScaleTo(base * math.max(0.6, k)) end)
			task.wait()
		end
		if m.Parent then pcall(function() m:ScaleTo(base); m:PivotTo(pivot) end) end
	end)
end

--==============================================================
-- hazards
--==============================================================
function WorldView:makeHazard(parent: Instance, h)
	local anchor = newPart(parent, "DustDevil", Vector3.one, CFrame.new(h.x, h.y + 4, h.z), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	anchor.Transparency = 1
	local fx = VFX.attach("DustDevil", anchor, CFrame.new(), h.radius / 8)
	if fx then fx.set(true) end
	return { anchor = anchor, fx = fx, data = h, z = h.z }
end

function WorldView:gateFX(position: Vector3)
	VFX.emit("CheckpointShock", CFrame.new(position), { scale = 1.4 })
end

--==============================================================
-- scenery
--==============================================================
local PROP_SPECS = {
	haybales  = { size = Vector3.new(9, 9, 13), color = Color3.fromRGB(203, 168, 84), mat = Enum.Material.Grass },
	posts     = { size = Vector3.new(2, 20, 2), color = Color3.fromRGB(120, 96, 66), mat = Enum.Material.Wood },
	cones     = { size = Vector3.new(4, 7, 4), color = Color3.fromRGB(240, 110, 40), mat = Enum.Material.Plastic },
	barriers  = { size = Vector3.new(6, 9, 26), color = Color3.fromRGB(206, 206, 200), mat = Enum.Material.Concrete },
	boulders  = { size = Vector3.new(16, 14, 16), color = Color3.fromRGB(112, 108, 102), mat = Enum.Material.Rock },
	bones     = { size = Vector3.new(3, 12, 3), color = Color3.fromRGB(224, 216, 196), mat = Enum.Material.Sand },
	spires    = { size = Vector3.new(12, 44, 12), color = Color3.fromRGB(166, 126, 82), mat = Enum.Material.Sandstone },
	wreck     = { size = Vector3.new(22, 10, 12), color = Color3.fromRGB(96, 62, 48), mat = Enum.Material.CorrodedMetal },
	pylons    = { size = Vector3.new(5, 60, 5), color = Color3.fromRGB(140, 144, 150), mat = Enum.Material.Metal },
	rubble    = { size = Vector3.new(11, 5, 11), color = Color3.fromRGB(96, 92, 86), mat = Enum.Material.Slate },
	ruins     = { size = Vector3.new(8, 34, 22), color = Color3.fromRGB(86, 82, 76), mat = Enum.Material.Concrete },
}

-- where the kit has a real model for a band's roadside clutter, use it
local PROP_MODELS = {
	cones = { folder = "Props", names = { "Cone_Big", "Cone_Striped", "Cone_Small" }, height = { 6, 8 } },
	posts = { folder = "Props", names = { "Cone_Post" }, height = { 9, 12 } },
	wreck = { folder = "Props", names = { "OilDrum_1", "OilDrum_2", "OilDrum_3", "Tyres_Scatter_01a", "Tyres_Scatter_01b", "Tyres_Stacked_01", "Tyres_Stacked_02" }, height = { 7, 12 } },
	pylons = { folder = "Props", names = { "StreetLamp" }, height = { 44, 56 } },
	boulders = { folder = "Obstacles", names = { "Rock_1", "Rock_2", "Rock_3" }, height = { 12, 22 } },
	rubble = { folder = "Obstacles", names = { "Rock_1", "Rock_2", "Rock_3" }, height = { 4, 8 } },
	spires = { folder = "Obstacles", names = { "Rock_2", "Rock_3" }, height = { 40, 64 } },
	ruins = { folder = "Props", names = { "ShippingContainer" }, height = { 16, 20 } },
}

function WorldView:buildBandProps(f: Instance, ci: number, band, r: Random)
	local spec = PROP_SPECS[band.prop]
	local modelSpec = PROP_MODELS[band.prop]
	if not spec and not modelSpec then return end
	local half = Config.Physics.CorridorHalfWidth
	for _ = 1, 1 + math.floor(band.propDensity * 3) do
		local x = ci * CHUNK + r:NextNumber(10, CHUNK - 10)
		local side = (r:NextNumber() < 0.5) and -1 or 1
		-- just off the road, so nothing at the side reads as something to dodge
		local z = side * r:NextNumber(half * 1.08, half * 1.6)
		local y = self:groundAt(x, z)
		local yaw = r:NextNumber(0, 6.28)
		local placed = false
		if modelSpec then
			local src = Assets.World:FindFirstChild(modelSpec.folder)
			local tpl = src and src:FindFirstChild(modelSpec.names[r:NextInteger(1, #modelSpec.names)])
			if tpl then
				local m = asModel(tpl:Clone())
				local _, size = m:GetBoundingBox()
				scaleModel(m, r:NextNumber(modelSpec.height[1], modelSpec.height[2]) / math.max(size.Y, 0.1))
				plant(m, x, y, z, yaw, 0.3)
				settle(m, true)
				m.Parent = f
				placed = true
			end
		end
		if not placed and spec then
			local s = spec.size * r:NextNumber(0.8, 1.3)
			local p = newPart(f, "Band_" .. band.prop, s, CFrame.new(x, y + s.Y / 2, z) * CFrame.Angles(0, yaw, 0), spec.color, spec.mat)
			p.CastShadow = true
		end
	end
end

function WorldView:buildDecor(f: Instance, ci: number)
	for _, d in ipairs(self.track:decorForChunk(ci)) do
		local tpl: Instance? = nil
		if d.scenery and d.pick then
			-- a named piece: from this zone's folder, or "zone/Name" from another's
			local path = if string.find(d.pick, "/") then "Scenery/" .. d.pick else "Scenery/" .. d.scenery .. "/" .. d.pick
			tpl = Models.get(path)
		elseif d.scenery then
			local kit = Models.list("Scenery/" .. d.scenery)
			if #kit > 0 then
				tpl = kit[1 + math.floor(hash01(d.x, d.z) * #kit) % #kit]
			end
		elseif d.model then
			local folder = Assets.World:FindFirstChild(d.folder or "Decor")
			tpl = folder and folder:FindFirstChild(d.model)
		end
		if tpl then
			local m = d.scenery and Models.copy(tpl) or asModel(tpl:Clone())
			scaleModel(m, d.scale)
			local _, size = m:GetBoundingBox()
			plant(m, d.x, self:groundAt(d.x, d.z), d.z, d.yaw, 0.4)
			local tall = size.Y > 20
			settle(m, tall)
			if d.tint and math.abs(d.tint - 1) > 0.01 then
				for _, p in ipairs(partsOf(m)) do
					p.Color = d.tint < 1 and p.Color:Lerp(Color3.new(0, 0, 0), 1 - d.tint) or p.Color:Lerp(Color3.new(1, 1, 1), d.tint - 1)
				end
			end
			m.Parent = f
		end
	end
end

-- The Backroad's countryside (art/blender/punjab.py): poplars standing in rows along the field
-- edges with gaps where a row was never finished, mustard and straw stacks and the odd goat or
-- buffalo on the verges, tube-wells and houses out in the fields, and every so often a brick
-- kiln's chimney on the skyline, smoking. All seeded by the chunk, so a run sees the same land.
local KILN_EVERY = 5		-- chunks between kilns
local PYLON_EVERY = 2		-- chunks between pylons on the Highway's power line
local PYLON_Z = 760
function WorldView:buildCountryside(f: Instance, ci: number, land)
	local kind = land.countryside
	local key = ({ backroad = "backroad/Poplar", highway = "highway/GoodsTruck", dunes = "dunes/Khejri" })[kind]
	if not (key and Models.get("Scenery/" .. key)) then return end
	local r = Random.new(self.track.runSeed * 7349 + ci * 2246822519 + 3)
	local x0 = ci * CHUNK
	local half = Config.Physics.CorridorHalfWidth
	-- name is "Piece" from this zone's own folder, or "zone/Piece" from another's
	local function put(name: string, x: number, z: number, scale: number, yaw: number?, sink: number?): Model?
		local path = if string.find(name, "/") then "Scenery/" .. name else "Scenery/" .. kind .. "/" .. name
		local tpl = Models.get(path)
		if not tpl then return nil end
		local m = Models.copy(tpl)
		scaleModel(m, scale)
		plant(m, x, self:groundAt(x, z), z, yaw or r:NextNumber(0, math.pi * 2), sink or 0.3)
		local _, size = m:GetBoundingBox()
		settle(m, size.Y > 12)
		m.Parent = f
		return m
	end
	-- a line of a long piece (a fence, a guardrail) end to end along the road, with gaps
	local function row(name: string, z: number, gapChance: number, scale: number)
		local path = if string.find(name, "/") then "Scenery/" .. name else "Scenery/" .. kind .. "/" .. name
		local tpl = Models.get(path)
		if not tpl then return end
		local probe = Models.copy(tpl)
		local _, size = probe:GetBoundingBox()
		probe:Destroy()
		local long = math.max(size.X, size.Z) * scale
		local yaw = if size.X >= size.Z then 0 else math.pi / 2
		local x = x0 + long / 2
		while x < x0 + CHUNK do
			if r:NextNumber() > gapChance then put(name, x, z, scale, yaw + (r:NextNumber() < 0.5 and 0 or math.pi), 0.2) end
			x += long + 0.2
		end
	end
	self:dressZone(kind, put, row, r, x0, half)
	-- (2026-10-24, the owner: fill the run's background "like the desert terrain" in the lobby) the belt
	-- between the fields and the far hills, 500 to 1,800 out, was bare: now each zone's own big shapes
	-- stand in it, no shadows (they're far): the Thar's dune ridges, the Backroad's poplar lines along
	-- the field edges and its villages, the Grand Trunk's eucalyptus stands
	local function far(name: string, x: number, z: number, scale: number, yaw: number?)
		local m = put(name, x, z, scale, yaw, 0.6)
		if m then settle(m, false) end
		return m
	end
	for _, side in ipairs({ -1, 1 }) do
		if kind == "dunes" then
			for k = 1, 2 do
				local z = side * r:NextNumber(560 + (k - 1) * 520, 1000 + (k - 1) * 700)
				local m = far("DuneRidge", x0 + r:NextNumber(0, CHUNK), z, r:NextNumber(5, 9) + (k - 1) * 4, 0)
				if m then
					-- its length along the road, its slip face to it
					local _, size = m:GetBoundingBox()
					local yaw = (if size.X >= size.Z then 0 else math.pi / 2) + (if side > 0 then math.pi else 0) + r:NextNumber(-0.2, 0.2)
					m:PivotTo(CFrame.new(m:GetPivot().Position) * CFrame.Angles(0, yaw, 0))
				end
			end
		elseif kind == "backroad" then
			-- a poplar line along a field edge (one side a chunk, in turn), and now and then a village
			if (ci + (if side > 0 then 1 else 0)) % 2 == 0 then
				local z = side * r:NextNumber(520, 1500)
				local x = x0 + r:NextNumber(0, 20)
				while x < x0 + CHUNK do
					if r:NextNumber() > 0.2 then far("Poplar", x, z + r:NextNumber(-4, 4), r:NextNumber(1.1, 1.5)) end
					x += r:NextNumber(20, 28)
				end
			end
			if r:NextNumber() < 0.3 then
				local x, z = x0 + r:NextNumber(40, CHUNK - 40), side * r:NextNumber(600, 1300)
				for k = 1, r:NextInteger(2, 4) do
					far("VillageHouse", x + r:NextNumber(-40, 40), z + side * r:NextNumber(-30, 30), r:NextNumber(1.1, 1.4))
				end
				for k = 1, 3 do far("Safeda", x + r:NextNumber(-60, 60), z + side * r:NextNumber(20, 60), r:NextNumber(1.0, 1.3)) end
			end
		elseif kind == "highway" then
			-- a stand of eucalyptus out in the plain, a neem or two
			local cx, cz = x0 + r:NextNumber(30, CHUNK - 30), side * r:NextNumber(480, 1400)
			for k = 1, r:NextInteger(4, 7) do
				far("backroad/Safeda", cx + r:NextNumber(-50, 50), cz + side * r:NextNumber(-30, 30), r:NextNumber(1.0, 1.35))
			end
			if r:NextNumber() < 0.5 then far("dunes/Khejri", x0 + r:NextNumber(0, CHUNK), side * r:NextNumber(450, 1200), r:NextNumber(1.1, 1.5)) end
		end
	end
	if kind == "highway" then
		-- the Grand Trunk is lined with eucalyptus both sides, close in, with gaps
		for _, side in ipairs({ -1, 1 }) do
			local x = x0 + r:NextNumber(0, 8)
			while x < x0 + CHUNK do
				if hash01(side * 7 + 3, math.floor(x / 380)) > 0.22 then
					put("backroad/Safeda", x, side * (half + 26 + r:NextNumber(-2, 2)), r:NextNumber(0.9, 1.15))
				end
				x += r:NextNumber(22, 28)
			end
			-- a truck pulled over on the verge, and now and then a dhaba with trucks outside
			if r:NextNumber() < 0.22 then
				put("GoodsTruck", x0 + r:NextNumber(20, CHUNK - 20), side * (half + 12), 1.0, (r:NextNumber() < 0.5) and 0 or math.pi, 0.2)
			end
			if r:NextNumber() < 0.12 then
				local x = x0 + r:NextNumber(40, CHUNK - 40)
				put("Dhaba", x, side * (half + 58), 1.15, side > 0 and math.pi or 0, 0.2)
				put("GoodsTruck", x + r:NextNumber(18, 26), side * (half + 46), 1.0, math.pi / 2 + r:NextNumber(-0.3, 0.3), 0.2)
			end
		end
		-- the power line marching across the plain
		if ci % PYLON_EVERY == 0 then
			put("Pylon", x0 + 40, PYLON_Z, 1.0, 0, 0.5)
		end
		return
	elseif kind == "dunes" then
		for _, side in ipairs({ -1, 1 }) do
			-- khejri trees, scattered and alone
			for _ = 1, r:NextInteger(0, 2) do
				put("Khejri", x0 + r:NextNumber(0, CHUNK), side * r:NextNumber(half + 30, 900), r:NextNumber(0.85, 1.25))
			end
			-- a camel caravan plodding along a crest
			if r:NextNumber() < 0.12 then
				local x = x0 + r:NextNumber(30, CHUNK - 60)
				local z = side * r:NextNumber(half + 50, 420)
				for k = 0, r:NextInteger(1, 3) do
					put("Camel", x + k * 13, z + r:NextNumber(-2, 2), r:NextNumber(1.0, 1.15), math.pi + r:NextNumber(-0.15, 0.15), 0.2)
				end
			end
		end
		-- a sandstone chhatri out on the skyline
		if ci % 4 == 1 then
			local side = (math.floor(ci / 4) % 2 == 0) and -1 or 1
			put("Chhatri", x0 + r:NextNumber(40, CHUNK - 40), side * r:NextNumber(500, 900), r:NextNumber(1.3, 1.7), r:NextNumber(0, math.pi * 2), 0.6)
		end
		return
	end
	-- the rows: along the first two field edges each side, a tree every 26-32 studs
	for _, side in ipairs({ -1, 1 }) do
		local strips = self:landStrips(side, land)
		for b = 1, math.min(2, #strips) do
			local z = side * strips[b].z0
			local x = x0 + r:NextNumber(0, 10)
			while x < x0 + CHUNK do
				-- some stretches of a row were never planted; the rest is mostly poplar, with eucalyptus
				-- and the odd oak mixed in, all sizes, so it never reads as one tree stamped out
				if hash01(b * 31 + side, math.floor(x / 520)) > 0.34 then
					local pick = r:NextNumber()
					local name = pick < 0.62 and "Poplar" or (pick < 0.88 and "Safeda" or "Oak")
					put(name, x, z + r:NextNumber(-4, 4), r:NextNumber(0.72, 1.3))
				end
				x += r:NextNumber(24, 46)
			end
		end
	end
	-- the verges, between the road and the fields
	for _, side in ipairs({ -1, 1 }) do
		for _ = 1, r:NextInteger(2, 4) do
			put("MustardPatch", x0 + r:NextNumber(0, CHUNK), side * r:NextNumber(half + 12, LAND_NEAR - 8), r:NextNumber(0.9, 1.4))
		end
		if r:NextNumber() < 0.45 then
			local x = x0 + r:NextNumber(20, CHUNK - 20)
			local z = side * r:NextNumber(half + 30, LAND_NEAR - 14)
			put("Kup", x, z, r:NextNumber(0.9, 1.2))
			if r:NextNumber() < 0.5 then put("Kup", x + r:NextNumber(-16, 16), z + side * r:NextNumber(10, 16), r:NextNumber(0.75, 1.0)) end
		end
		if r:NextNumber() < 0.16 then
			local name = "Goat" -- (2026-10-23, the owner: no cows; goats only on the verges)
			local x = x0 + r:NextNumber(0, CHUNK)
			put(name, x, side * r:NextNumber(half + 18, LAND_NEAR - 10), name == "Goat" and 1.3 or 1.15, side > 0 and math.pi or 0)
			if name == "Goat" and r:NextNumber() < 0.6 then
				put("Goat", x + r:NextNumber(-10, 10), side * r:NextNumber(half + 18, LAND_NEAR - 10), 1.15)
			end
		end
		if r:NextNumber() < 0.22 then
			local x = x0 + r:NextNumber(30, CHUNK - 30)
			put("Safeda", x, side * r:NextNumber(half + 40, LAND_NEAR - 10), r:NextNumber(0.9, 1.15))
			put("Safeda", x + r:NextNumber(14, 24), side * r:NextNumber(half + 40, LAND_NEAR - 10), r:NextNumber(0.85, 1.1))
		end
	end
	-- out in the fields: a tube-well, now and then a house facing the road
	for _, side in ipairs({ -1, 1 }) do
		if r:NextNumber() < 0.14 then
			put("TubeWell", x0 + r:NextNumber(20, CHUNK - 20), side * r:NextNumber(LAND_NEAR + 8, LAND_NEAR + 60), 1.25, r:NextNumber(0, math.pi * 2), 0.4)
		end
		if r:NextNumber() < 0.1 then
			local z = side * r:NextNumber(LAND_NEAR + 80, LAND_NEAR + 260)
			put("VillageHouse", x0 + r:NextNumber(20, CHUNK - 20), z, r:NextNumber(1.1, 1.3), side > 0 and math.pi or 0, 0.6)
		end
	end
	-- a brick kiln on the skyline, smoke lazing off its stack
	if ci % KILN_EVERY == 2 then
		local side = (math.floor(ci / KILN_EVERY) % 2 == 0) and 1 or -1
		local kiln = put("KilnChimney", x0 + r:NextNumber(40, CHUNK - 40), side * r:NextNumber(900, 1300), r:NextNumber(1.1, 1.4), nil, 0.8)
		if kiln then
			local cf, size = kiln:GetBoundingBox()
			local att = Instance.new("Attachment")
			att.WorldPosition = cf.Position + Vector3.new(0, size.Y / 2 + 1, 0)
			att.Parent = kiln.PrimaryPart or kiln:FindFirstChildWhichIsA("BasePart", true)
			local e = Instance.new("ParticleEmitter")
			e.Texture = PackFX.Sheet.plume
			e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
			e.FlipbookMode = Enum.ParticleFlipbookMode.Loop
			e.Rate = 2.5
			e.Lifetime = NumberRange.new(9, 13)
			e.Speed = NumberRange.new(5, 8)
			e.SpreadAngle = Vector2.new(8, 8)
			e.Acceleration = Vector3.new(2.5, 0.6, 1.2)
			e.Drag = 0.25
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 36) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
			e.Color = ColorSequence.new(Color3.fromRGB(86, 82, 80), Color3.fromRGB(176, 170, 164))
			e.RotSpeed = NumberRange.new(-8, 8)
			e.LightInfluence = 1
			e.LightEmission = 0
			e.Parent = att
		end
	end
end

-- The zone's own kit, spread thicker so no stretch of road looks empty: every piece each zone was
-- given is used somewhere, near the road (where the eye is at speed) and out in the land. Anything
-- solid stands past 215 studs from the centre line (the furthest the tyre can go), so it never
-- rolls through a lamp or a rail.
function WorldView:dressZone(kind: string, put: any, row: any, r: Random, x0: number, half: number)
	local function anyOf(list: { string }): string
		return list[r:NextInteger(1, #list)]
	end
	if kind == "backroad" then
		for _, side in ipairs({ -1, 1 }) do
			-- a field fence runs along the verge, broken in places
			if hash01(side * 13 + 5, math.floor(x0 / 900)) > 0.4 then
				row("Fence", side * (half + 92), 0.18, r:NextNumber(0.95, 1.1))
			end
			-- bushes and a birch or two on the verge
			for _ = 1, r:NextInteger(3, 5) do
				put("Bush", x0 + r:NextNumber(0, CHUNK), side * r:NextNumber(half + 50, LAND_NEAR + 30), r:NextNumber(0.8, 1.4))
			end
			if r:NextNumber() < 0.5 then
				put("Birch", x0 + r:NextNumber(0, CHUNK), side * r:NextNumber(half + 100, LAND_NEAR + 60), r:NextNumber(0.85, 1.2))
			end
			-- a mailbox at a farm gate
			if r:NextNumber() < 0.3 then
				put("Mailbox", x0 + r:NextNumber(20, CHUNK - 20), side * (half + 88), 1.2, side > 0 and math.pi or 0, 0.1)
			end
			-- out in the fields: a tractor at work, now and then a farmstead (barn and silo)
			if r:NextNumber() < 0.28 then
				put("Tractor", x0 + r:NextNumber(20, CHUNK - 20), side * r:NextNumber(LAND_NEAR + 20, LAND_NEAR + 200), r:NextNumber(1.0, 1.2))
			end
			if r:NextNumber() < 0.14 then
				local x = x0 + r:NextNumber(40, CHUNK - 40)
				local z = side * r:NextNumber(LAND_NEAR + 120, LAND_NEAR + 420)
				put("Barn", x, z, r:NextNumber(1.0, 1.2), side > 0 and math.pi or 0, 0.5)
				put("Silo", x + r:NextNumber(18, 26), z + side * r:NextNumber(4, 12), r:NextNumber(1.0, 1.15), nil, 0.5)
			end
		end
	elseif kind == "highway" then
		for _, side in ipairs({ -1, 1 }) do
			-- a guardrail along the hard shoulder, and street lamps over it
			row("Guardrail", side * (half + 90), 0.08, 1.0)
			local x = x0 + 30 + (side > 0 and 0 or 45)
			while x < x0 + CHUNK do
				put("StreetLamp", x, side * (half + 95), 1.15, side > 0 and 0 or math.pi, 0.2)
				x += 90
			end
			-- jersey barriers stacked at a works spot, now and then
			if r:NextNumber() < 0.18 then
				local bx = x0 + r:NextNumber(30, CHUNK - 30)
				for k = 0, r:NextInteger(1, 3) do
					put("JerseyBarrier", bx + k * 17, side * (half + 105), 1.0, 0, 0.1)
				end
			end
		end
		-- a billboard out in the scrub every other chunk, a gantry sign now and then
		if math.floor(x0 / CHUNK) % 2 == 0 then
			local side = (math.floor(x0 / CHUNK / 2) % 2 == 0) and -1 or 1
			put("Billboard", x0 + r:NextNumber(40, CHUNK - 40), side * r:NextNumber(half + 130, half + 220), r:NextNumber(1.2, 1.5), side > 0 and math.pi or 0, 0.3)
		end
		if math.floor(x0 / CHUNK) % 3 == 1 then
			local side = (r:NextNumber() < 0.5) and -1 or 1
			put("HighwaySign", x0 + r:NextNumber(40, CHUNK - 40), side * (half + 100), 1.3, side > 0 and math.pi or 0, 0.2)
		end
		-- the power line on the far side too
		if math.floor(x0 / CHUNK) % 2 == 1 then put("Pylon", x0 + 40, -760, 1.0, 0, 0.5) end
	elseif kind == "dunes" then
		for _, side in ipairs({ -1, 1 }) do
			-- scrub on the verge: prickly pear, tumbleweed, the odd skull
			for _ = 1, r:NextInteger(3, 5) do
				put(anyOf({ "PricklyPear", "PricklyPear", "Tumbleweed" }), x0 + r:NextNumber(0, CHUNK), side * r:NextNumber(half + 70, LAND_NEAR + 60), r:NextNumber(0.9, 1.5))
			end
			if r:NextNumber() < 0.3 then
				put("CowSkull", x0 + r:NextNumber(0, CHUNK), side * r:NextNumber(half + 60, half + 110), r:NextNumber(1.0, 1.4), nil, 0.2)
			end
			-- khejri closer in than the lone ones out on the sand
			for _ = 1, r:NextInteger(1, 2) do
				put("Khejri", x0 + r:NextNumber(0, CHUNK), side * r:NextNumber(half + 100, half + 220), r:NextNumber(0.85, 1.2))
			end
			-- a wreck half sunk by the road
			if r:NextNumber() < 0.12 then
				put("Wreck", x0 + r:NextNumber(20, CHUNK - 20), side * r:NextNumber(half + 100, half + 180), r:NextNumber(1.0, 1.2), nil, 0.6)
			end
			-- a cactus or two (the odd saguaro among them)
			if r:NextNumber() < 0.35 then
				put(anyOf({ "Saguaro", "PricklyPear" }), x0 + r:NextNumber(0, CHUNK), side * r:NextNumber(half + 100, LAND_NEAR + 160), r:NextNumber(1.0, 1.4))
			end
		end
		-- an oasis: a cluster of palms round a hollow, every few chunks
		if math.floor(x0 / CHUNK) % 5 == 3 then
			local side = (math.floor(x0 / CHUNK / 5) % 2 == 0) and 1 or -1
			local cx = x0 + r:NextNumber(60, CHUNK - 60)
			local cz = side * r:NextNumber(half + 120, half + 320)
			for _ = 1, r:NextInteger(4, 7) do
				put("Palm", cx + r:NextNumber(-30, 30), cz + r:NextNumber(-24, 24), r:NextNumber(0.9, 1.3))
			end
		end
	end
end

--==============================================================
-- chunk build / teardown
--==============================================================
function WorldView:buildChunk(ci: number, withDecor: boolean)
	-- (2026-10-18) a chunk built out past the decor range gets its decor once it comes into range; it
	-- used to return here, so every chunk after the first few had bare verges for the whole run
	self.decorDone = self.decorDone or {}
	local existing = self.chunks[ci]
	if existing then
		if withDecor and not self.decorDone[ci] then
			self.decorDone[ci] = true
			local land = self:landAt(ci * CHUNK + CHUNK / 2)
			self:buildDecor(existing, ci)
			if land.countryside then self:buildCountryside(existing, ci, land) end
		end
		return
	end
	if withDecor then self.decorDone[ci] = true end
	local track = self.track
	local cfg = self:cfgAt(ci * CHUNK + CHUNK / 2)
	local land = self:landAt(ci * CHUNK + CHUNK / 2)
	local half = Config.Physics.CorridorHalfWidth
	local band = self:bandFor(ci)

	local f = Instance.new("Folder")
	f.Name = "C" .. ci
	f.Parent = self.root
	self.chunks[ci] = f

	local roadW = half * 2
	local shoulderW = roadW + 190
	local shoulderColor = band.ground:Lerp(Color3.fromRGB(90, 110, 60), 0.32)
	for s = 0, SEGS_PER_CHUNK - 1 do
		local x0 = ci * CHUNK + s * SEG
		local x1 = x0 + SEG
		local y0, y1 = track:heightAt(x0), track:heightAt(x1)
		local dy = y1 - y0
		local len = math.sqrt(SEG * SEG + dy * dy)
		local theta = math.atan2(dy, SEG)
		local top = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0) * CFrame.Angles(0, 0, theta)
		local sh = newPart(f, "Shoulder", Vector3.new(len + 0.4, GROUND_THICK, shoulderW), top * CFrame.new(0, -GROUND_THICK / 2 - 1.2, 0), shoulderColor, cfg.groundMaterial, true)
		textured(sh, land.vergeVariant, Color3.new(1, 1, 1):Lerp(shoulderColor, band.tier / 7))
		local rd = newPart(f, "Road", Vector3.new(len + 0.4, GROUND_THICK, roadW), top * CFrame.new(0, -GROUND_THICK / 2, 0), band.ground, cfg.groundMaterial, true)
		if land.lane then
			-- a farm track: the corridor is grass and the dirt lane runs down its middle
			textured(rd, land.vergeVariant, Color3.new(1, 1, 1))
			local lane = newPart(f, "Lane", Vector3.new(len + 0.4, 0.4, land.lane), top * CFrame.new(0, -0.18, 0), band.ground, cfg.groundMaterial, true)
			textured(lane, land.roadVariant, Color3.new(1, 1, 1):Lerp(band.ground, band.tier / 7))
		else
			textured(rd, land.roadVariant, Color3.new(1, 1, 1):Lerp(band.ground, band.tier / 7))
		end
		self:markRoad(f, s, top, len, band, shoulderColor, land)
		-- where a ramp lifts the road, its sides slope down into the fields instead of standing
		-- as flat walls
		local b0, b1 = track:baseHeight(x0), track:baseHeight(x1)
		if math.max(y0 - b0, y1 - b1) > 0.6 then
			self:rampSides(f, x0, x1, y0, y1, b0, b1, theta, shoulderColor, land)
		end
	end
	self:buildLand(f, ci, band, land)

	-- kickers get a painted lip so they read as built ramps
	for _, r in ipairs(track:rampsForChunk(ci)) do
		if r.kicker then self:rampLip(f, r.x + r.len - 2) end
	end

	-- white milestones with yellow caps every 100 m, like the ones on Indian roads
	local first = math.ceil(ci * CHUNK / MILESTONE)
	local last = math.floor(((ci + 1) * CHUNK - 0.01) / MILESTONE)
	for k = math.max(1, first), last do
		self:milestone(f, k * MILESTONE, k * 100)
	end

	local objs = track:objectsForChunk(ci)
	for _, o in ipairs(objs.obstacles) do
		if not self.collected[o.key] then
			self.obstacleNodes[o.key] = self:makeObstacle(f, o)
		end
	end
	for _, t in ipairs(if self.backdrop then {} else track:targetsForChunk(ci)) do
		local node = self:makeTarget(f, t)
		if node then self.targetNodes[t.key] = node end
	end
	if self.sceneryOnly then
		self:buildBandProps(f, ci, band, Random.new(track.runSeed * 5779 + ci * 2654435761))
		if withDecor then self:buildDecor(f, ci) end
		if withDecor and land.countryside then self:buildCountryside(f, ci, land) end
		return
	end
	for _, d in ipairs(objs.pads) do
		self.padNodes[d.key] = self:makePad(f, d)
	end
	for _, q in ipairs(objs.perks) do
		if not self.collected[q.key] then
			local node = self:makePerkIcon(f, q)
			if node then self.perkNodes[q.key] = node end
		end
	end
	for _, tb in ipairs(track:toolboxesForChunk(ci)) do
		if not self.collected[tb.key] then
			local node = self:makeToolbox(f, tb)
			if node then self.toolNodes[tb.key] = node end
		end
	end
	for _, mt in ipairs(track:metalsForChunk(ci)) do
		if not self.collected[mt.key] then
			local node = self:makeMetal(f, mt)
			if node then self.metalNodes[mt.key] = node end
		end
	end
	for _, h in ipairs(track:hazardsForChunk(ci)) do
		self.hazardNodes[h.key] = self:makeHazard(f, h)
	end
	for _, k in ipairs(track:keysForChunk(ci)) do
		if not self.collected[k.key] then
			self.keyNodes[k.key] = self:makeKey(f, k)
		end
	end

	self:buildBandProps(f, ci, band, Random.new(track.runSeed * 5779 + ci * 2654435761))

	for n, dist in ipairs(Config.Difficulty.Checkpoints) do
		if dist >= ci * CHUNK and dist < (ci + 1) * CHUNK then
			self:makeGate(f, n, dist, band)
		end
	end

	if withDecor then self:buildDecor(f, ci) end
	if withDecor and land.countryside then self:buildCountryside(f, ci, land) end
end

function WorldView:dropChunk(ci: number)
	local f = self.chunks[ci]
	if not f then return end
	local objs = self.track:objectsForChunk(ci)
	for _, q in ipairs(objs.perks) do self.perkNodes[q.key] = nil end
	for _, d in ipairs(objs.pads) do self.padNodes[d.key] = nil end
	for _, o in ipairs(objs.obstacles) do self.obstacleNodes[o.key] = nil end
	for _, tb in ipairs(self.track:toolboxesForChunk(ci)) do self.toolNodes[tb.key] = nil end
	for _, mt in ipairs(self.track:metalsForChunk(ci)) do self.metalNodes[mt.key] = nil end
	for _, h in ipairs(self.track:hazardsForChunk(ci)) do self.hazardNodes[h.key] = nil end
	for _, k in ipairs(self.track:keysForChunk(ci)) do self.keyNodes[k.key] = nil end
	for _, t in ipairs(self.track:targetsForChunk(ci)) do self.targetNodes[t.key] = nil end
	f:Destroy()
	self.chunks[ci] = nil
	if self.decorDone then self.decorDone[ci] = nil end
end

-- (2026-10-24) budget: how many chunks (or a chunk's decor) may be built this call past the one the
-- tyre is on and the next. Per-frame callers pass 1, so a fast tyre no longer builds a run of whole
-- chunks in one frame (a hitch); without it everything in range is built (the first frame).
function WorldView:ensure(x: number, budget: number?)
	local ci = math.max(0, math.floor(x / CHUNK))
	local left = budget or math.huge
	self.decorDone = self.decorDone or {}
	for c = math.max(0, ci - BEHIND), ci + AHEAD_GROUND do
		local decor = c <= ci + AHEAD_DECOR
		local needed = not self.chunks[c] or (decor and not self.decorDone[c])
		if needed then
			if c <= ci + 1 then
				self:buildChunk(c, decor)
			elseif left > 0 then
				left -= 1
				self:buildChunk(c, decor)
			end
		end
	end
	for c in pairs(self.chunks) do
		if c < ci - BEHIND or c > ci + AHEAD_GROUND then self:dropChunk(c) end
	end
end

--==============================================================
-- per frame
--==============================================================
function WorldView:update(dt: number, tyreX: number)
	self.t += dt
	local tier = Config.TierAt(math.max(0, tyreX))
	if self.track.isRoad then
		-- a new zone: its sky, light and haze roll in, the far hills take its colours
		local zi = self.track:zoneIndex(math.max(0, tyreX))
		if zi ~= self.lightZone then
			local first = self.lightZone == nil
			self.lightZone = zi
			local cfg = self:cfgAt(math.max(0, tyreX))
			if self.look and ZoneLook.Looks[cfg.id] then
				self.look:enter(cfg.id, first)
			else
				local band = Config.BandFor(cfg, 0)
				local Lighting = game:GetService("Lighting")
				local ti = TweenInfo.new(first and 0 or 2.2, Enum.EasingStyle.Sine)
				TweenService:Create(Lighting, ti, {
					ClockTime = cfg.clockTime, Ambient = cfg.ambient, OutdoorAmbient = cfg.ambient,
					FogColor = band.fog, FogEnd = band.fogEnd, FogStart = band.fogEnd * 0.3,
				}):Play()
				local atm = Lighting:FindFirstChildOfClass("Atmosphere")
				if atm then
					local space = cfg.id == "moon"
					TweenService:Create(atm, ti, {
						Color = band.fog, Decay = band.fog:Lerp(Color3.fromRGB(96, 112, 138), 0.35),
						Density = space and 0.05 or 0.22, Haze = space and 0 or 0.5,
					}):Play()
				end
			end
			self:recolourHills(self:landAt(math.max(0, tyreX)))
		end
	elseif tier ~= self.fogTier then
		self.fogTier = tier
		local band = Config.BandFor(self.cfg, tier)
		local Lighting = game:GetService("Lighting")
		TweenService:Create(Lighting, TweenInfo.new(1.6), {
			FogColor = band.fog, FogEnd = band.fogEnd, FogStart = band.fogEnd * 0.3,
		}):Play()
		-- the haze thickens and takes the band's colour the deeper you get
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm then
			TweenService:Create(atm, TweenInfo.new(1.6), {
				Color = band.fog, Decay = band.fog:Lerp(Color3.fromRGB(96, 112, 138), 0.35),
				Density = 0.2 + math.clamp(tier, 0, 7) / 7 * 0.1,
			}):Play()
		end
	end
	if self.look then self.look:frame(dt, self.track:heightAt(math.max(0, tyreX))) end
	if self.skirt then self:placeSkirt(tyreX) end
	if self.hills then
		for _, hill in ipairs(self.hills) do
			if hill.x < tyreX - 2600 then
				hill.x += HORIZON_LOOP
				self:placeHill(hill)
			end
		end
	end
	local t = self.t
	for _, n in pairs(self.perkNodes) do
		local d = n.data
		if math.abs(d.x - tyreX) < 1400 then
			local y = n.baseY + math.sin(t * 1.7 + d.phase) * d.bob
			-- turns about upright, lingering a moment face-on to the road coming in
			local a = t * d.spinSpeed * 1.1 + d.phase
			local spin = a - math.sin(a * 2) * 0.35
			local cf = CFrame.new(d.x, y, d.z) * CFrame.Angles(0, spin, 0)
			n.core.CFrame = cf
			n.ring.CFrame = cf
		end
	end
	for _, n in pairs(self.toolNodes) do
		local d = n.data
		if math.abs(d.x - tyreX) < 1400 then
			n.model:PivotTo(CFrame.new(d.x, n.baseY + math.sin(t * 1.4 + d.phase) * 1.6, d.z) * CFrame.Angles(0, t * 0.9 + d.phase, 0))
		end
	end
	for _, n in pairs(self.metalNodes) do
		local d = n.data
		if math.abs(d.x - tyreX) < 1400 and n.model.Parent then
			n.model.CFrame = CFrame.new(d.x, d.y + math.sin(t * 2.2 + d.phase) * 1.4, d.z) * CFrame.Angles(0, t * 2 + d.phase, 0) * n.upright
		end
	end
	for _, n in pairs(self.hazardNodes) do
		local d = n.data
		n.z = d.z + math.sin(t * d.sway) * d.radius * 0.8
		n.anchor.CFrame = CFrame.new(d.x, d.y + 4, n.z)
	end
	for _, n in pairs(self.keyNodes) do
		local d = n.data
		if math.abs(d.x - tyreX) < 1400 and n.model.Parent then
			n.model:PivotTo(CFrame.new(d.x, d.y + math.sin(t * 1.8 + d.phase) * 1.5, d.z) * CFrame.Angles(0, t * 1.6 + d.phase, 0) * n.offset)
			-- the pennant flaps
			if n.flag then
				local rest = n.flagRest :: CFrame
				local hinge = rest * CFrame.new(4.5, 0, 0)
				n.flag.CFrame = hinge * CFrame.Angles(0, math.sin(t * 5.2 + d.phase) * 0.22, 0) * CFrame.new(-4.5, 0, 0)
			end
		end
	end
end

--==============================================================
-- collection
--==============================================================
function WorldView:markCollected(key: string)
	self.collected[key] = true
	local n = self.perkNodes[key]
	if not n then return end
	self.perkNodes[key] = nil
	local core, ring = n.core, n.ring
	for _, d in ipairs(core:GetChildren()) do
		if d:IsA("SurfaceGui") or d:IsA("BillboardGui") then d.Enabled = false end
	end
	task.spawn(function()
		local ti = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		pcall(function()
			TweenService:Create(core, ti, { Size = Vector3.new(0.4, 30, 30), Transparency = 1 }):Play()
			TweenService:Create(ring, ti, { Size = Vector3.new(0.3, 36, 36), Transparency = 1 }):Play()
		end)
		task.wait(0.35)
		if n.model and n.model.Parent then n.model:Destroy() end
	end)
end

function WorldView:markToolCollected(key: string)
	self.collected[key] = true
	local n = self.toolNodes[key]
	if not n then return end
	self.toolNodes[key] = nil
	PackFX.burst("dustPuff", CFrame.new(n.body.Position), 10, n.rarity.color:Lerp(Color3.new(1, 1, 1), 0.5), 1.4)
	task.spawn(function()
		local ti = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		pcall(function()
			for _, p in ipairs(n.model:GetDescendants()) do
				if p:IsA("BasePart") then TweenService:Create(p, ti, { Transparency = 1, Size = p.Size * 0.2 }):Play() end
			end
		end)
		task.wait(0.36)
		if n.model and n.model.Parent then n.model:Destroy() end
	end)
end

function WorldView:destroy()
	if self.look then self.look:destroy() end
	self.look = nil
	if self.root then self.root:Destroy() end
	self.root = nil
	self.chunks = {}
	self.perkNodes = {}
	self.padNodes = {}
	self.toolNodes = {}
	self.metalNodes = {}
	self.obstacleNodes = {}
	self.hazardNodes = {}
	self.keyNodes = {}
	self.targetNodes = {}
end

return WorldView
