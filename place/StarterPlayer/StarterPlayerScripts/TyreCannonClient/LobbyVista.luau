--!strict
-- TYRE CANNON :: LobbyVista
-- "Launch Valley" (lobby-concepts-2026-10-11, concept 1): the land round the plaza, in rings that
-- run outward in the order the road does, so the first thing you see from your yard is where
-- you're about to fly:
--   the canal      a ring of water with poplars along both banks: the edge of the lawn (and a soft
--                  wall you can't walk past, so nothing beyond looks walkable and isn't)
--   Punjab         mustard, wheat, fodder and ploughed strips stepping gently up in terraces, with
--                  villages (houses, tube wells, haystacks, buffalo) and kiln chimneys trailing smoke
--   Grand Trunk    a ring road on its embankment: eucalyptus both sides, pylons, dhabas with smoke and
--                  trucks parked out front, and a convoy of painted goods trucks driving round
--   scrub          dry ground climbing toward the desert, khejri trees
--   Thar           ridges of dunes closing the horizon all the way round (so the bottom of the sky
--                  never shows), chhatris on the crests, a camel caravan walking the ridge
--   milestones     white stones with yellow caps out along every yard's line of fire: HIGHWAY 4 KM
--                  at the road (2026-10-23: milestone-sized; the THAR stone and the pylons are gone)
--   roundabout     (LobbyTraffic, 2026-10-15) a ring road past the poplars, roads out along each line of
--                  fire to the Grand Trunk, and traffic on them
--   detail         (LobbyDetail, 2026-10-17) the lawn as a park (LobbyPark: ponds, playground, fountain,
--                  strollers, spectators filming the launches) with grass, flowers and reeds round it;
--                  earth bunds, trees and haystacks out in the fields
-- Everything is built on the client (like the run's WorldView), so streaming never drops it, from
-- the game's own scenery models and MaterialVariants, scaled up the further out they stand (a big,
-- simple backdrop reads at distance; Knowledge/patterns/lobby-aesthetics). No lights, no glows:
-- smoke is grey particles. Nothing in the plaza or the yards is touched.
--   LobbyVista.new() -> vista ; vista:build() (yields; call behind the loading screen)
--   vista:setVisible(on)   off for the run, on in the yard ; vista:destroy()

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialService = game:GetService("MaterialService")

local LobbyVista = {}
LobbyVista.__index = LobbyVista

local CENTRE = Vector3.new(-6000, 0, 6000)
-- (2026-10-18, the owner: the inner lobby ~40% smaller, too much dead space. Every ring past the
-- yards (which reach 280 studs out) is drawn in by S; widths, heights and models keep their size.)
-- (2026-10-21, the owner: a stage-5 yard ran over the park's footpath. Yards reach 316 studs out at stage 5
-- (Game.YardGrowth: x1 104, z 60, the fence and palisade past that), so every ring is pushed out to clear it.)
local S = 0.66
local CANAL_R = 640 * S
LobbyVista.S = S
LobbyVista.CANAL_R = CANAL_R
local FIELDS = { 680 * S, 1900 * S }
local FIELD_RISE = 0.05 / S        -- the terraces climb this much a stud, so they fill the view
local ROAD_R = 2050 * S
local SCRUB = { 2160 * S, 3300 * S }
local SCRUB_RISE = 60
-- (2026-10-23, the owner: the ground was "super glitchy and overlappy": stepped terrace boxes with walls
-- between them, straight strips laid round a circle (overlapping at their inner edges, gaps at their
-- outer), and a 30-stud wall up to the road. Now one continuous surface: the fields slope gently,
-- a grassy bank climbs to the road, and every piece is short and tilted to lie on it)
local EMBANKMENT = 14              -- the road stands this much above the top of the fields, up a bank
local BANK_END = ROAD_R - 40        -- where the bank meets the road's level
local CARAVAN_R = 3150 * S
-- the zones' real distances, painted on the stones
-- (2026-10-23, the owner: "weird looking distance things". Scaled with distance the stones stood 50 and
-- 120 studs tall, giant tombstones on the skyline; now only the HIGHWAY stone, at a milestone's size
-- beside the road: a few studs on screen, a detail you find rather than a billboard)
local STONES = { { r = 1860 * S, text = "HIGHWAY", km = "4 KM", scale = 6 } }

local function scenery(): Instance?
	local root = ReplicatedStorage:FindFirstChild("TyreCannon")
	local assets = root and root:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Scenery")
end

-- the ground's height at a distance from the plaza: the lawn, then terraces climbing gently out to
-- the road's embankment, then the scrub rising toward the dunes
local function heightAt(r: number): number
	if r < FIELDS[1] then return 0 end
	local top = 0.4 + (FIELDS[2] - FIELDS[1]) * FIELD_RISE
	if r < FIELDS[2] then return 0.4 + (r - FIELDS[1]) * FIELD_RISE end
	if r < BANK_END then return top + (r - FIELDS[2]) / (BANK_END - FIELDS[2]) * EMBANKMENT end
	if r < SCRUB[1] then return top + EMBANKMENT end
	return top + EMBANKMENT + math.min(1, (r - SCRUB[1]) / (SCRUB[2] - SCRUB[1])) * SCRUB_RISE
end
-- the radii where the ground's slope changes (a sloped piece never straddles one)
local KINKS = { FIELDS[1], FIELDS[2], BANK_END, SCRUB[1], SCRUB[2] }

local function at(r: number, a: number, y: number?): Vector3
	return CENTRE + Vector3.new(math.cos(a) * r, y or heightAt(r), math.sin(a) * r)
end

-- a frame at r, a on the ground: -Z faces the plaza, X runs round the ring
local function ringFrame(r: number, a: number, y: number): CFrame
	local p = at(r, a, y)
	return CFrame.lookAt(p, Vector3.new(CENTRE.X, p.Y, CENTRE.Z))
end

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
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

-- the run's MaterialVariants (WorldView does the same: the colour eases toward white so the
-- texture's own colours show)
local function textured(p: BasePart, variant: string?, tint: Color3?)
	if not variant then return end
	local v = MaterialService:FindFirstChild(variant)
	if not (v and v:IsA("MaterialVariant")) then return end
	p.Material = v.BaseMaterial
	p.MaterialVariant = variant
	p.Color = Color3.new(1, 1, 1):Lerp(tint or p.Color, 0.35)
end

-- (2026-10-23) ground over the ring between radii r0..r1 and angles a0..a1, lying on heightAt's surface:
-- short pieces tilted to its slope (split where the slope changes), each a little wider than its
-- arc at the outer edge so no gap opens between neighbours, alternate ones a hair higher so the
-- overlaps never flicker
function LobbyVista:ground(f: Instance, name: string, r0: number, r1: number, a0: number, a1: number, seg: number, paint: (Part) -> (), parity: number)
	local cuts = { r0 }
	for _, k in ipairs(KINKS) do
		if k > r0 + 0.5 and k < r1 - 0.5 then table.insert(cuts, k) end
	end
	table.insert(cuts, r1)
	local T = 8
	for ci = 1, #cuts - 1 do
		local ra, rb = cuts[ci], cuts[ci + 1]
		local h0, h1 = heightAt(ra + 0.01), heightAt(rb - 0.01)
		local rm, depth = (ra + rb) / 2, rb - ra
		local tilt = math.atan2(h1 - h0, depth)
		local L = math.sqrt(depth * depth + (h1 - h0) ^ 2) + 1.2
		local n = math.max(1, math.ceil((a1 - a0) * rm / seg))
		local da = (a1 - a0) / n
		for i = 0, n - 1 do
			local ac = a0 + (i + 0.5) * da
			local lift = ((i + parity + ci) % 2) * 0.12
			local cf = ringFrame(rm, ac, (h0 + h1) / 2 + lift) * CFrame.Angles(-tilt, 0, 0) * CFrame.new(0, -T / 2, 0)
			paint(newPart(f, name, Vector3.new(da * rb + 1.2, T, L), cf, Color3.new(1, 1, 1), Enum.Material.Grass))
			self.groundMade = (self.groundMade or 0) + 1
			if self.groundMade % 80 == 0 then task.wait() end
		end
	end
end

function LobbyVista.new()
	local self = setmetatable({}, LobbyVista)
	self.root = Instance.new("Folder")
	self.root.Name = "LobbyVista"
	self.movers = {} :: { any }
	self.visible = true
	self.built = false
	self.rng = Random.new(20261011)
	return self
end

-- a scenery model, scaled, standing on the ground at r, a (turned by yaw, or to face the plaza)
function LobbyVista:place(folder: Instance, path: string, r: number, a: number, scale: number, yaw: number?, y: number?): Model?
	local src = scenery()
	local zone, name = path:match("^(%w+)/(%w+)$")
	local proto = src and zone and src:FindFirstChild(zone) and (src :: any)[zone]:FindFirstChild(name)
	if not (proto and proto:IsA("Model")) then return nil end
	local m = proto:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("LuaSourceContainer") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	pcall(function() m:ScaleTo(scale) end)
	local ground = y or heightAt(r)
	local face = ringFrame(r, a, ground)
	m:PivotTo(face * CFrame.Angles(0, yaw or 0, 0))
	local cf, size = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + Vector3.new(0, ground - (cf.Position.Y - size.Y / 2), 0))
	m.Parent = folder
	return m
end

-- grey smoke rising from a point (particles only: no light, no glow)
local function smoke(where: BasePart, size: number)
	local att = Instance.new("Attachment")
	att.Parent = where
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(196, 192, 186), Color3.fromRGB(230, 228, 224))
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, size * 2.4) })
	e.Lifetime = NumberRange.new(7, 11)
	e.Rate = 1.6
	e.Speed = NumberRange.new(size * 0.35, size * 0.55)
	e.SpreadAngle = Vector2.new(8, 8)
	e.Acceleration = Vector3.new(4, 0.6, 2)
	e.RotSpeed = NumberRange.new(-12, 12)
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = att
end

--==============================================================
-- the rings
--==============================================================
function LobbyVista:canal()
	local f = Instance.new("Folder")
	f.Name = "Canal"
	f.Parent = self.root
	local n = 96
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local w = 2 * math.pi * CANAL_R / n + 2
		-- the water and its two banks
		newPart(f, "Water", Vector3.new(w, 2, 26), ringFrame(CANAL_R, a, -0.6), Color3.fromRGB(86, 140, 150), Enum.Material.SmoothPlastic)
		for _, side in ipairs({ -1, 1 }) do
			local bank = newPart(f, "Bank", Vector3.new(w, 1.2, 6), ringFrame(CANAL_R + side * 16, a, 0.2), Color3.fromRGB(150, 128, 96), Enum.Material.Ground)
			textured(bank, "TC_Dirt", bank.Color)
		end
		-- the wall you can't walk past: the canal is the edge of the lawn (on its inner bank)
		local wall = newPart(f, "Edge", Vector3.new(w, 90, 4), ringFrame(CANAL_R - 18, a, 45), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		wall.Transparency = 1
		wall.CanCollide = true
	end
	-- poplars along both banks, a windbreak
	local poplars = Instance.new("Folder")
	poplars.Name = "Poplars"
	poplars.Parent = f
	-- (2026-10-18 visual review: an even double row read as a wall, so some trees are missing, the
	-- spacing wanders and the heights spread wider. Its own Random, so the fields after keep their layout.)
	local count = 110
	local wild = Random.new(20261018)
	for i = 0, count - 1 do
		local a = (i + self.rng:NextNumber(-0.2, 0.2)) / count * math.pi * 2
		for _, side in ipairs({ -1, 1 }) do
			local scale, yaw = self.rng:NextNumber(1.6, 2.1), self.rng:NextNumber(0, math.pi * 2)
			if wild:NextNumber() > 0.18 then
				local da = wild:NextNumber(-0.35, 0.35) / count * math.pi * 2
				self:place(poplars, "backroad/Poplar", CANAL_R + side * 26 + wild:NextNumber(-4, 4), a + da + side * 0.004, scale * wild:NextNumber(0.8, 1.15), yaw, 0)
			end
		end
		if i % 30 == 0 then task.wait() end
	end
end

function LobbyVista:fields()
	local f = Instance.new("Folder")
	f.Name = "Punjab"
	f.Parent = self.root
	local palette = { { "TC_Mustard", 4 }, { "TC_Wheat", 3 }, { "TC_Fodder", 3 }, { "TC_Soil", 2 } }
	local total = 0
	for _, e in ipairs(palette) do total += e[2] end
	local function pick(): string
		local x = self.rng:NextNumber(0, total)
		for _, e in ipairs(palette) do
			x -= e[2]
			if x <= 0 then return e[1] end
		end
		return palette[1][1]
	end
	-- strips in rings, each running round the ring, on the gently rising ground (the last ring runs
	-- right up to the bank)
	local r = FIELDS[1]
	local strip = 0
	while r < FIELDS[2] - 1 do
		local depth = self.rng:NextNumber(110, 170) * S
		if r + depth + 110 * S > FIELDS[2] then depth = FIELDS[2] - r end
		local mid = r + depth / 2
		local a = self.rng:NextNumber(0, 0.2)
		local stop = a + math.pi * 2
		while a < stop - 1e-3 do
			local len = self.rng:NextNumber(260, 560) * S
			local da = math.min(len / mid, stop - a)
			local variant = pick()
			strip += 1
			self:ground(f, "Field", r, r + depth, a, a + da, 40, function(p) textured(p, variant, Color3.new(1, 1, 1)) end, strip)
			a += da
		end
		r += depth
	end
	-- the grassy bank up to the road, and the verge it runs along
	self:ground(f, "Embankment", FIELDS[2], SCRUB[1], 0, math.pi * 2, 50, function(p)
		p.Color = Color3.fromRGB(150, 160, 100)
		textured(p, "TC_Verge", p.Color)
	end, 0)
	-- villages and kilns out in the fields
	local life = Instance.new("Folder")
	life.Name = "Villages"
	life.Parent = f
	for v = 0, 9 do
		local a = (v + self.rng:NextNumber(-0.3, 0.3)) / 10 * math.pi * 2
		local rr = self.rng:NextNumber(950, 1750) * S
		local s = 2.4
		self:place(life, "backroad/VillageHouse", rr, a, s, self.rng:NextNumber(-0.4, 0.4))
		self:place(life, "backroad/VillageHouse", rr + 40, a + 0.02, s, self.rng:NextNumber(-0.4, 0.4))
		self:place(life, "backroad/TubeWell", rr - 30, a - 0.025, s)
		self:place(life, "backroad/Kup", rr + 10, a - 0.04, s)
		-- (2026-10-23, the owner: no cow model in the map)
		if v % 2 == 0 then self:place(life, "backroad/Tractor", rr + 90, a - 0.01, s, self.rng:NextNumber(0, math.pi * 2)) end
		task.wait()
	end
	for k = 0, 4 do
		local a = (k + 0.5) / 5 * math.pi * 2 + 0.3
		local kiln = self:place(life, "backroad/KilnChimney", self.rng:NextNumber(1200, 1800) * S, a, 3)
		if kiln then
			local top = nil :: BasePart?
			for _, d in ipairs(kiln:GetDescendants()) do
				if d:IsA("BasePart") and (not top or d.Position.Y > (top :: BasePart).Position.Y) then top = d end
			end
			if top then smoke(top, 22) end
		end
	end
end

function LobbyVista:road()
	local f = Instance.new("Folder")
	f.Name = "GrandTrunk"
	f.Parent = self.root
	local top = heightAt(ROAD_R)
	local n = 120
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local w = 2 * math.pi * ROAD_R / n + 3
		local asphalt = newPart(f, "Road", Vector3.new(w, 4, 72), ringFrame(ROAD_R, a, top - 1.6), Color3.fromRGB(70, 72, 78), Enum.Material.Asphalt)
		textured(asphalt, "TC_Asphalt", asphalt.Color)
		for _, side in ipairs({ -1, 1 }) do
			newPart(f, "Edge", Vector3.new(w, 0.3, 2), ringFrame(ROAD_R + side * 31, a, top + 0.5), Color3.fromRGB(232, 232, 224), Enum.Material.SmoothPlastic)
			newPart(f, "Shoulder", Vector3.new(w, 60, 30), ringFrame(ROAD_R + side * 50, a, top - 30.4), Color3.fromRGB(150, 136, 104), Enum.Material.Ground)
		end
		if i % 2 == 0 then
			newPart(f, "Centre", Vector3.new(w * 0.55, 0.3, 1.4), ringFrame(ROAD_R, a, top + 0.5), Color3.fromRGB(240, 196, 40), Enum.Material.SmoothPlastic)
		end
		if i % 30 == 0 then task.wait() end
	end
	-- eucalyptus both sides, pylons marching round outside
	local trees = Instance.new("Folder")
	trees.Name = "Roadside"
	trees.Parent = f
	-- (2026-10-23: the even double row of same-size eucalyptus read as a fence of lollipops on the
	-- skyline; now they come in stands with gaps between, of mixed heights. Their own Random, so the
	-- rest of the layout keeps its draw.)
	local stand = Random.new(20261023)
	for i = 0, 89 do
		local a = (i + self.rng:NextNumber(-0.3, 0.3)) / 90 * math.pi * 2
		local thick = math.noise(i * 0.37, 4.2) -- -0.5..0.5: runs of trees, then open stretches
		for _, side in ipairs({ -1, 1 }) do
			if self.rng:NextNumber() < 0.8 and stand:NextNumber() < 0.55 + thick * 1.2 then
				self:place(trees, "backroad/Safeda", ROAD_R + side * stand:NextNumber(66, if side < 0 then 100 else 150), a + stand:NextNumber(-0.012, 0.012), stand:NextNumber(1.7, 3.3), self.rng:NextNumber(0, math.pi * 2), top)
			end
		end
		if i % 15 == 0 then task.wait() end
	end
	-- (2026-10-23: no pylons. Eighteen bare lattice towers with no wires between them were the spikes
	-- poking over the poplars on every side of the hub)
	-- dhabas with trucks pulled in out front and their chimneys smoking
	for d = 0, 3 do
		local a = d / 4 * math.pi * 2 + 0.35
		local dh = self:place(trees, "highway/Dhaba", ROAD_R + 75, a, 3, math.pi, top)
		if dh then
			local cf, size = dh:GetBoundingBox()
			local anchor = newPart(trees, "SmokeFrom", Vector3.new(1, 1, 1), CFrame.new(cf.Position + Vector3.new(0, size.Y / 2, 0)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
			anchor.Transparency = 1
			smoke(anchor, 14)
		end
		self:place(trees, "highway/GoodsTruck", ROAD_R + 44, a + 0.022, 2.6, math.pi / 2 + 0.15, top)
		self:place(trees, "highway/GoodsTruck", ROAD_R + 44, a - 0.024, 2.6, math.pi / 2 - 0.1, top)
	end
	-- the convoy: painted goods trucks driving round, in the outer lane
	for c = 0, 4 do
		local truck = self:place(f, "highway/GoodsTruck", ROAD_R + 14, 0, 2.6, 0, top)
		if truck then
			table.insert(self.movers, { model = truck, r = ROAD_R + 14, y = top, a0 = c * 0.11 + (c >= 3 and 2.6 or 0), speed = 55, kind = "truck" })
		end
	end
end

function LobbyVista:desert()
	local f = Instance.new("Folder")
	f.Name = "Thar"
	f.Parent = self.root
	-- the scrub climbing toward the dunes
	local r = SCRUB[1]
	local strip = 0
	while r < SCRUB[2] + 300 * S do
		local depth = self.rng:NextNumber(160, 240) * S
		local mid = r + depth / 2
		local a = self.rng:NextNumber(0, 0.2)
		local stop = a + math.pi * 2
		while a < stop - 1e-3 do
			local len = self.rng:NextNumber(500, 900) * S
			local da = math.min(len / mid, stop - a)
			local variant = if mid > 3100 * S then "TC_Dune" elseif self.rng:NextNumber() < 0.5 then "TC_Scrub" else "TC_Gravel"
			strip += 1
			self:ground(f, "Scrub", r, r + depth, a, a + da, 90, function(p)
				p.Material = Enum.Material.Sand
				textured(p, variant, Color3.fromRGB(240, 226, 200))
			end, strip)
			a += da
		end
		r += depth
	end
	-- (2026-10-23: khejri in loose groves of one to four, of mixed sizes, scattered in depth; one tree
	-- every ten degrees at one size read as a row of lollipops along the skyline)
	local grove = Random.new(20261023)
	for g = 0, 15 do
		local a = (g + grove:NextNumber(-0.45, 0.45)) / 16 * math.pi * 2
		local r0 = grove:NextNumber(2280, 3080) * S
		for _ = 1, grove:NextInteger(1, 4) do
			local rr = r0 + grove:NextNumber(-60, 60) * S
			self:place(f, "dunes/Khejri", rr, a + grove:NextNumber(-40, 40) / rr, grove:NextNumber(2.2, 4.2), grove:NextNumber(0, math.pi * 2))
		end
	end
	task.wait()
	-- the dunes: long lying cylinders sunk so only their crowns show, in staggered rows that close
	-- the horizon all the way round
	-- rows of half-buried spheres of different sizes: a rolling skyline, every row a little
	-- higher and paler than the one in front { radius, diameter range, crown range }
	local rows = {
		{ 3500 * S, { 900, 1400 }, { 210, 330 } },
		{ 4200 * S, { 1200, 1800 }, { 300, 440 } },
		{ 5100 * S, { 1500, 2040 }, { 400, 560 } },
		{ 6200 * S, { 1800, 2040 }, { 500, 700 } },
	}
	local crests = {}
	-- (2026-10-23) with the Blender dune (hubkit.dune, Scenery/dunes/DuneRidge) imported, the rows are long
	-- ridges with a wandering crest and a steep slip face toward the plaza; until then, the spheres
	local src = scenery()
	local ridge = src and src:FindFirstChild("dunes") and (src :: any).dunes:FindFirstChild("DuneRidge")
	if ridge then
		local RH, RL = 17, 60       -- the model's own height and length
		for ri, row in ipairs(rows) do
			local rr = row[1]
			local a = self.rng:NextNumber(0, 0.3)
			local stop = a + math.pi * 2
			while a < stop do
				local rj = rr + self.rng:NextNumber(-150, 150) * S
				local base = heightAt(rj) - 2
				local crown = self.rng:NextNumber(row[3][1], row[3][2])
				local scale = math.clamp((crown - base) / RH, 3, 33)
				local m = self:place(f, "dunes/DuneRidge", rj, a, scale, self.rng:NextNumber(-0.25, 0.25), base)
				if m then
					-- nearer rows warmer, farther ones paler into the haze
					local tint = Color3.fromRGB(255, 236, 214):Lerp(Color3.fromRGB(236, 226, 220), (ri - 1) / 3)
					for _, d in ipairs(m:GetDescendants()) do
						if d:IsA("SurfaceAppearance") then d.Color = tint end
					end
					-- (the crest at the middle of its length stands about two thirds of its peak, a little toward the plaza)
					if ri == 1 then table.insert(crests, { r = rj - 1.1 * scale, a = a, y = base + RH * scale * 0.68, model = m }) end
				end
				a += RL * scale * 0.55 / rr
			end
			task.wait()
		end
	end
	for ri, row in ipairs(if ridge then {} else rows) do
		local rr = row[1]
		local a = self.rng:NextNumber(0, 0.3)
		local stop = a + math.pi * 2
		while a < stop do
			local d = self.rng:NextNumber(row[2][1], row[2][2])
			local crown = self.rng:NextNumber(row[3][1], row[3][2])
			local rj = rr + self.rng:NextNumber(-150, 150) * S
			local sand = Color3.fromRGB(218, 176, 112):Lerp(Color3.fromRGB(198, 152, 98), self.rng:NextNumber()):Lerp(Color3.fromRGB(226, 204, 170), (ri - 1) * 0.12)
			local p = newPart(f, "Dune", Vector3.new(d, d, d), ringFrame(rj, a, crown - d / 2), sand, Enum.Material.Sand)
			p.Shape = Enum.PartType.Ball
			textured(p, "TC_Dune", p.Color)
			if ri == 1 then table.insert(crests, { r = rj, a = a, y = crown }) end
			-- overlap enough that no gap ever opens on the skyline
			a += d * 0.42 / rr
		end
		task.wait()
	end
	-- the sand under everything past the dunes, so a high camera never finds the edge of the world
	for ring = 0, 4 do
		local rr = (7400 + ring * 1900) * S
		local n = math.ceil(2 * math.pi * rr / 1900)
		for i = 0, n - 1 do
			newPart(f, "Skirt", Vector3.new(2048, 20, 2000), ringFrame(rr, i / n * math.pi * 2, 260), Color3.fromRGB(206, 164, 104), Enum.Material.Sand)
		end
	end
	-- chhatris standing alone on the nearest crests
	-- (2026-10-23, the owner: the chhatri wasn't placed right) each stands on its ridge's real highest
	-- point, found by probing the dune's surface from above, and sinks a little into the sand
	-- (2026-10-24, the owner: "fix the chhatris in the background") they still floated: a dune ridge is one
	-- mesh scaled up to 33x, and its collision (what any probe hits) rides ~50 studs over the crest you
	-- see. So each chhatri now stands out on the open sand just in front of the first row of dunes, on
	-- the ground itself, a size down: a lone cenotaph at the desert's edge, framed by the dunes behind.
	local sandParts = {}
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "DuneRidge" and not (d.Parent and d.Parent.Name == "DuneRidge") and d.Name ~= "Scrub" then
			table.insert(sandParts, d)
		end
	end
	local home = f.Parent
	f.Parent = workspace
	for _, d in ipairs(sandParts) do d:SetAttribute("TC_Q", d.CanQuery) d.CanQuery = true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = sandParts
	for k = 1, 4 do
		local c = crests[math.clamp(math.floor(k / 4 * #crests), 1, #crests)]
		local a = if c then c.a else k * math.pi / 2
		local r = rows[1][1] - 300 * S
		local o = CENTRE + Vector3.new(math.cos(a) * r, 900, math.sin(a) * r)
		local hit = workspace:Raycast(o, Vector3.new(0, -1800, 0), params)
		local y = if hit then hit.Position.Y else heightAt(r)
		self:place(f, "dunes/Chhatri", r, a, 5, self.rng:NextNumber(0, math.pi * 2), y - 1.5)
	end
	for _, d in ipairs(sandParts) do d.CanQuery = d:GetAttribute("TC_Q") == true d:SetAttribute("TC_Q", nil) end
	f.Parent = home
	for k = 1, if false then 4 else 0 do
		local c = crests[math.clamp(math.floor(k / 4 * #crests), 1, #crests)]
		if c and c.model then
			local ridge = c.model :: Model
			-- (the lobby's built off-screen: the ridge goes into the world just while it's probed)
			local home = ridge.Parent
			ridge.Parent = workspace
			local parts = {}
			for _, d in ipairs(ridge:GetDescendants()) do
				if d:IsA("BasePart") then d.CanQuery = true table.insert(parts, d) end
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = parts
			local box, size = ridge:GetBoundingBox()
			local best: Vector3? = nil
			for i = -6, 6 do
				for j = -3, 3 do
					local o = (box * CFrame.new(i / 6 * size.X * 0.45, 0, j / 3 * size.Z * 0.4)).Position + Vector3.new(0, size.Y + 50, 0)
					local hit = workspace:Raycast(o, Vector3.new(0, -size.Y - 120, 0), params)
					if hit and (not best or hit.Position.Y > (best :: Vector3).Y) then best = hit.Position end
				end
			end
			for _, p in ipairs(parts) do p.CanQuery = false end
			ridge.Parent = home
			if best then
				local spot = best :: Vector3
				local d = Vector3.new(spot.X - CENTRE.X, 0, spot.Z - CENTRE.Z)
				-- (2026-10-24, the owner: "fix the chhatris in the background": they floated over the sand. The probe
				-- hit the ridge's rough collision hull; the template now has a precise one, and the chhatri is a
				-- size down so it stands on the crest rather than looming over it)
				self:place(f, "dunes/Chhatri", d.Magnitude, math.atan2(d.Z, d.X), 5, self.rng:NextNumber(0, math.pi * 2), spot.Y - 3)
			end
		elseif c then
			self:place(f, "dunes/Chhatri", c.r, c.a, 7, self.rng:NextNumber(0, math.pi * 2), c.y - 6)
		end
	end
	-- the camel caravan, walking the edge of the desert
	for i = 0, 5 do
		local camel = self:place(f, "dunes/Camel", CARAVAN_R, 0, 4.2, 0)
		if camel then
			-- (a camel's length and a stride apart: they were nose inside tail)
			table.insert(self.movers, { model = camel, r = CARAVAN_R, y = heightAt(CARAVAN_R), a0 = 1.2 - i * 0.02, speed = 7, kind = "camel", phase = i * 0.7 })
		end
	end
end

-- a milestone stone on every yard's line of fire, painted with the zone it marks
function LobbyVista:milestones()
	local f = Instance.new("Folder")
	f.Name = "Milestones"
	f.Parent = self.root
	local font = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		for _, s in ipairs(STONES) do
			local g = heightAt(s.r)
			local scale = s.scale
			-- (the HIGHWAY stone stands beside the road on the line of fire, not in the middle of it)
			local face = ringFrame(s.r, a + (if s.r < 2000 * S then 64 / s.r else 0), g)
			newPart(f, "Base", Vector3.new(3.6, 0.5, 2.4) * scale, face * CFrame.new(0, 0.25 * scale, 0), Color3.fromRGB(150, 146, 138), Enum.Material.Concrete)
			local stone = newPart(f, "Stone", Vector3.new(3, 4.2, 1.8) * scale, face * CFrame.new(0, 2.1 * scale, 0), Color3.fromRGB(236, 234, 226), Enum.Material.SmoothPlastic)
			-- (a hair shallower than the stone: its lower half hides inside, and the faces never fight)
			local cap = newPart(f, "Cap", Vector3.new(1.74, 3, 3) * scale, face * CFrame.new(0, 4.2 * scale, 0) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(242, 190, 40), Enum.Material.SmoothPlastic)
			cap.Shape = Enum.PartType.Cylinder
			-- the face toward the plaza (-Z): the zone, then the distance
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Front
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 4
			sg.LightInfluence = 0.7
			sg.Parent = stone
			for i, line in ipairs({ s.text, s.km }) do
				local l = Instance.new("TextLabel")
				l.BackgroundTransparency = 1
				l.Position = UDim2.fromScale(0.06, if i == 1 then 0.2 else 0.5)
				l.Size = UDim2.fromScale(0.88, if i == 1 then 0.26 else 0.3)
				l.FontFace = font
				l.TextScaled = true
				l.TextColor3 = if i == 1 then Color3.fromRGB(40, 40, 44) else Color3.fromRGB(200, 40, 34)
				l.Text = line
				l.Parent = sg
			end
		end
	end
end

-- the roundabout and its traffic (LobbyTraffic): built into the vista, so it hides with it
function LobbyVista:traffic()
	if workspace:GetAttribute("LobbyTraffic") == false then return end
	local mod = script.Parent:FindFirstChild("LobbyTraffic")
	if not mod then return end
	self.roundabout = (require(mod) :: any).new(self.root, heightAt)
end

-- the land's small detail: grass, flowers, groves, reeds, field bunds (LobbyDetail; after the traffic,
-- which moves the villages off the roads)
function LobbyVista:detail()
	local mod = script.Parent:FindFirstChild("LobbyDetail")
	if mod then self.park = (require(mod) :: any).build(self.root, heightAt) end
end

-- the plaza round the Trophy Pillar: rangoli, planters, benches, bunting, a chai corner (PlazaLife)
function LobbyVista:plaza()
	local mod = script.Parent:FindFirstChild("PlazaLife")
	if mod then (require(mod) :: any).build(self.root) end
end

--==============================================================
function LobbyVista:build()
	if self.built then return end
	self.built = true
	local steps = { self.canal, self.fields, self.road, self.desert, self.milestones, self.traffic, self.detail, self.plaza }
	for _, step in ipairs(steps) do
		local ok, err = pcall(step, self)
		if not ok then warn("[TyreCannon] LobbyVista:", err) end
		task.wait()
	end
	self.root.Parent = workspace
	-- the convoy and the caravan move; nothing else does
	self.conn = RunService.Heartbeat:Connect(function() self:step() end)
end

function LobbyVista:step()
	if not self.visible then return end
	local t = workspace:GetServerTimeNow()
	if self.roundabout then self.roundabout:step(t) end
	if self.park then self.park:step(t) end
	for _, mv in ipairs(self.movers) do
		local a = mv.a0 + t * mv.speed / mv.r
		local bob = if mv.kind == "camel" then math.abs(math.sin(t * 1.6 + (mv.phase or 0))) * 1.6 else 0
		local p = at(mv.r, a, mv.y + bob)
		-- facing along the ring (anticlockwise)
		local ahead = at(mv.r, a + 0.01, mv.y + bob)
		local cf = CFrame.lookAt(p, ahead)
		local lift = mv.lift
		if not lift then
			local box, size = mv.model:GetBoundingBox()
			lift = mv.model:GetPivot().Position.Y - (box.Position.Y - size.Y / 2)
			mv.lift = lift
		end
		-- (Camel is long in X with its front at -X, so a quarter that way; the GoodsTruck's front is +X:
		-- 2026-10-23, the owner saw the convoy driving backwards)
		local q = if mv.kind == "truck" then math.pi / 2 else -math.pi / 2
		mv.model:PivotTo(cf * CFrame.Angles(0, q, 0) + Vector3.new(0, lift, 0))
	end
end

function LobbyVista:setVisible(on: boolean)
	if self.visible == on then return end
	self.visible = on
	if self.built then self.root.Parent = if on then workspace else nil end
end

function LobbyVista:destroy()
	if self.conn then self.conn:Disconnect() end
	if self.roundabout then self.roundabout:destroy() end
	if self.park then self.park:destroy() end
	self.root:Destroy()
end

return LobbyVista
