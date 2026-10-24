--!strict
-- TYRE CANNON :: TrackGen
-- Deterministic, infinite track generation. The same seed always produces the
-- same world, so physics and visuals never disagree and no world data has to
-- be replicated. Ground height is a function of X only, which keeps the tyre
-- simulation exact; lateral interest comes from obstacles, pads and quirks.
-- TrackGen.get("road") is the one road through every zone (Game.Zones): its terrain, ramps,
-- obstacles, scenery and hazards come from the zone under each stretch (Config.ZoneWorlds), the
-- terrain blended across each zone line so the ground never steps, and a key waits in every zone.

local Config = require(script.Parent.Config)
local Game = require(script.Parent.Game)

local CHUNK = 300
local RAMP_REACH = 2		-- chunks either side that can influence heightAt
local ZONE_BLEND = 360		-- studs over which one zone's terrain turns into the next's

-- where each zone starts, in studs along the road
local ZONE_STARTS = {}
local ZONE_CFGS = {}
for i, z in ipairs(Game.Zones) do
	ZONE_STARTS[i] = z.start / Game.StudsToMetres
	ZONE_CFGS[i] = Config.ZoneWorlds[z.id]
end

local TrackGen = {}
TrackGen.ChunkSize = CHUNK

local Track = {}
Track.__index = Track

local cache: { [string]: any } = {}

-- w = across the road, h = height, d = along the road. Kinds with a model use
-- Assets.World.Obstacles; dimensions are matched to each model's proportions
-- so the collision box and the art agree. "breaks" picks how it comes apart.
local OBSTACLE_SETS = {
	fields = {
		{ kind = "haybale", runModel = "HayBale", w = 11, h = 11, d = 16, loss = 0.16, color = Color3.fromRGB(203, 168, 84), mat = Enum.Material.Grass, breaks = "chunks" },
		{ kind = "rock",    model = "Rock_3", w = 15, h = 13, d = 16, loss = 0.24, color = Color3.fromRGB(120, 116, 108), mat = Enum.Material.Slate, breaks = "rocks" },
		{ kind = "log",     model = "Log", w = 23, h = 5.6, d = 6.3, loss = 0.18, color = Color3.fromRGB(120, 84, 52), mat = Enum.Material.Wood, breaks = "log" },
	},
	highway = {
		{ kind = "barrier", runModel = "RoadBarrier", w = 26, h = 10, d = 7, loss = 0.26, color = Color3.fromRGB(206, 206, 200), mat = Enum.Material.Concrete, breaks = "chunks" },
		{ kind = "trash",   model = "Trash", w = 9.1, h = 7.8, d = 11.7, loss = 0.15, color = Color3.fromRGB(70, 90, 70), mat = Enum.Material.Plastic, breaks = "trash" },
		{ kind = "vending", model = "Vending", w = 9, h = 15.7, d = 7.6, loss = 0.28, color = Color3.fromRGB(200, 40, 40), mat = Enum.Material.Metal, breaks = "vending" },
	},
	desert = {
		{ kind = "boulder", runModel = "DesertRocks", model = "Rock_2", w = 14, h = 17, d = 21, loss = 0.28, color = Color3.fromRGB(160, 126, 86), mat = Enum.Material.Sandstone, breaks = "rocks" },
		{ kind = "cactus",  w = 8, h = 22, d = 8, loss = 0.12, color = Color3.fromRGB(86, 130, 74), mat = Enum.Material.Grass, breaks = "chunks" },
		{ kind = "log",     model = "Log", w = 23, h = 5.6, d = 6.3, loss = 0.18, color = Color3.fromRGB(150, 116, 80), mat = Enum.Material.Wood, breaks = "log" },
	},
	quarry = {
		{ kind = "keg",     runModel = "PowderKeg", model = "OilDrum_1", folder = "Props", w = 8, h = 11, d = 8, loss = 0.2, color = Color3.fromRGB(176, 52, 40), mat = Enum.Material.Wood, breaks = "chunks" },
		{ kind = "boulder", model = "Rock_1", w = 15, h = 13, d = 16, loss = 0.26, color = Color3.fromRGB(130, 120, 110), mat = Enum.Material.Slate, breaks = "rocks" },
		{ kind = "tyres",   model = "Tyres_Stacked_01", folder = "Props", w = 10, h = 9, d = 10, loss = 0.14, color = Color3.fromRGB(30, 30, 32), mat = Enum.Material.Rubber, breaks = "chunks" },
	},
	docks = {
		{ kind = "crate",   runModel = "CargoCrate", w = 10, h = 10, d = 10, loss = 0.2, color = Color3.fromRGB(176, 128, 74), mat = Enum.Material.WoodPlanks, breaks = "chunks" },
		{ kind = "drum",    model = "OilDrum_2", folder = "Props", w = 7, h = 10, d = 7, loss = 0.15, color = Color3.fromRGB(40, 90, 170), mat = Enum.Material.Metal, breaks = "chunks" },
		{ kind = "barrier", model = "Barrier", folder = "Props", w = 22, h = 8, d = 6, loss = 0.24, color = Color3.fromRGB(206, 206, 200), mat = Enum.Material.Concrete, breaks = "chunks" },
	},
	salt = {
		{ kind = "marker",  runModel = "SaltMarker", model = "Cone_Post", folder = "Props", w = 7, h = 16, d = 7, loss = 0.12, color = Color3.fromRGB(220, 60, 50), mat = Enum.Material.Plastic, breaks = "chunks" },
		{ kind = "cones",   model = "Cone_Big", folder = "Props", w = 7, h = 9, d = 7, loss = 0.08, color = Color3.fromRGB(240, 110, 40), mat = Enum.Material.Plastic, breaks = "chunks" },
		{ kind = "barrier", model = "Barrier", folder = "Props", w = 22, h = 8, d = 6, loss = 0.24, color = Color3.fromRGB(206, 206, 200), mat = Enum.Material.Concrete, breaks = "chunks" },
	},
	mountain = {
		{ kind = "snowman", runModel = "Snowman", w = 9, h = 14, d = 9, loss = 0.14, color = Color3.fromRGB(244, 246, 250), mat = Enum.Material.Snow, breaks = "chunks" },
		{ kind = "log",     model = "Log", w = 23, h = 5.6, d = 6.3, loss = 0.18, color = Color3.fromRGB(110, 80, 56), mat = Enum.Material.Wood, breaks = "log" },
		{ kind = "rock",    model = "Rock_3", w = 15, h = 13, d = 16, loss = 0.24, color = Color3.fromRGB(150, 156, 166), mat = Enum.Material.Slate, breaks = "rocks" },
	},
	moon = {
		{ kind = "moonrock", runModel = "MoonRock", model = "Rock_2", w = 16, h = 12, d = 18, loss = 0.22, color = Color3.fromRGB(150, 150, 158), mat = Enum.Material.Basalt, breaks = "rocks" },
		{ kind = "rock",     model = "Rock_3", w = 12, h = 10, d = 13, loss = 0.18, color = Color3.fromRGB(128, 128, 136), mat = Enum.Material.Basalt, breaks = "rocks" },
	},
}

-- roadside scenery from Assets.World.Decor. far = sits well off the road
local DECOR_SETS = {
	-- the Backroad's trees, stacks, animals and buildings come from WorldView's countryside
	fields = {
		{ model = "Grass_2", scale = { 2.5, 4 }, weight = 4 },
		{ model = "Grass_3", scale = { 2.5, 4 }, weight = 4 },
		{ model = "Flower1", scale = { 4, 6 }, weight = 2 },
		{ model = "Flower_2", scale = { 4, 6 }, weight = 2 },
		{ model = "Rock_1", scale = { 1.5, 3 }, weight = 2 },
	},
	-- the Grand Trunk: eucalyptus, roadside furniture, a dhaba or a parked truck now and then
	-- (no cypresses, palms or pines: they were a free pack's, not this road's)
	highway = {
		{ model = "Grass_2", scale = { 2.5, 4 }, weight = 3 },
		{ model = "Rock_1", scale = { 1.5, 3 }, weight = 1 },
		{ scenery = true, pick = { "backroad/Safeda" }, scale = { 0.9, 1.15 }, far = true, weight = 4 },
		{ scenery = true, pick = { "StreetLamp", "HighwaySign", "JerseyBarrier" }, scale = { 1, 1 }, weight = 2 },
		{ scenery = true, pick = { "Dhaba", "GoodsTruck" }, scale = { 1, 1 }, far = true, weight = 1 },
	},
	-- the Thar: khejri, camels, a chhatri on a rise, a wreck, rocks and dry grass (no palms,
	-- beanstalk or American cacti)
	desert = {
		{ model = "Rock_1", scale = { 2, 4 }, weight = 3 },
		{ model = "Grass_3", scale = { 2, 3 }, weight = 2 },
		{ scenery = true, pick = { "Khejri" }, scale = { 0.85, 1.25 }, far = true, weight = 4 },
		{ scenery = true, pick = { "Camel", "Chhatri", "Wreck", "CowSkull" }, scale = { 1, 1 }, far = true, weight = 2 },
	},
	quarry = {
		{ model = "Rock_1", folder = "Obstacles", scale = { 2.5, 5 }, far = true, weight = 4 },
		{ model = "Rock_3", folder = "Obstacles", scale = { 1.5, 3 }, weight = 3 },
		{ model = "OilDrum_3", folder = "Props", scale = { 1, 1.3 }, weight = 2 },
		{ model = "Tyres_Scatter_01a", folder = "Props", scale = { 1, 1.4 }, weight = 2 },
		{ model = "CarEngine", folder = "Props", scale = { 1, 1.3 }, weight = 1 },
		{ model = "Pine_2", scale = { 0.7, 1.0 }, far = true, weight = 1 },
		{ scenery = true, scale = { 1, 1 }, far = true, weight = 4 },
	},
	docks = {
		{ model = "ShippingContainer", folder = "Props", scale = { 1, 1.2 }, far = true, weight = 4 },
		{ model = "OilDrum_1", folder = "Props", scale = { 1, 1.3 }, weight = 2 },
		{ model = "OilDrum_4", folder = "Props", scale = { 1, 1.3 }, weight = 2 },
		{ model = "StreetLamp", folder = "Props", scale = { 1, 1.1 }, weight = 2 },
		{ model = "Tyres_Stacked_02", folder = "Props", scale = { 1, 1.3 }, weight = 1 },
		{ scenery = true, scale = { 1, 1 }, far = true, weight = 5 },
	},
	salt = {
		{ model = "Cone_Striped", folder = "Props", scale = { 1, 1.2 }, weight = 2 },
		{ model = "Cone_Post", folder = "Props", scale = { 1, 1.2 }, weight = 2 },
		{ model = "Rock_1", folder = "Obstacles", scale = { 0.6, 1.2 }, weight = 1 },
		{ scenery = true, scale = { 1, 1 }, far = true, weight = 3 },
	},
	mountain = {
		{ model = "Pine_1", scale = { 0.9, 1.4 }, far = true, weight = 4 },
		{ model = "Pine_2", scale = { 0.9, 1.4 }, far = true, weight = 4 },
		{ model = "Pine_3", scale = { 0.9, 1.4 }, far = true, weight = 3 },
		{ model = "Sequoia_1", scale = { 0.7, 1.0 }, far = true, weight = 1 },
		{ model = "Rock_1", folder = "Obstacles", scale = { 1.5, 3.5 }, weight = 3 },
		{ scenery = true, scale = { 1, 1 }, far = true, weight = 3 },
	},
	moon = {
		{ model = "Rock_1", folder = "Obstacles", scale = { 2, 6 }, far = true, weight = 4 },
		{ model = "Rock_2", folder = "Obstacles", scale = { 1, 2.5 }, weight = 3 },
		{ model = "Rock_3", folder = "Obstacles", scale = { 1, 2 }, weight = 3 },
		{ scenery = true, scale = { 1, 1 }, far = true, weight = 4 },
	},
}

--==============================================================
-- bounce targets (v3): things on the line that throw the tyre back up. h = height of the top the
-- tyre lands on, len = the landing length along the road (from the model's own proportions),
-- bounce = how hard it throws you. path is the model under Assets; WorldView scales it to h.
--==============================================================
local TARGETS = {
	hay = { path = "Run/HayBale", h = 13, len = 13, bounce = 1.0, sound = "thud" },
	kup = { path = "Scenery/backroad/Kup", h = 17, len = 18, bounce = 1.2, sound = "thud" },
	tractor = { path = "Scenery/backroad/Tractor", h = 14, len = 19, bounce = 1.5, sound = "metal" },
	buffalo = { path = "Scenery/backroad/Buffalo", h = 12, len = 21, bounce = 1.9, sound = "moo" },
	truck = { path = "Scenery/highway/GoodsTruck", h = 16, len = 40, bounce = 2.3, sound = "metal" },
	dhaba = { path = "Scenery/highway/Dhaba", h = 14, len = 32, bounce = 1.4, sound = "thud" },
	container = { path = "World/Props/ShippingContainer", h = 14, len = 38, bounce = 1.2, sound = "metal" },
	camel = { path = "Scenery/dunes/Camel", h = 15, len = 15, bounce = 1.9, sound = "moo" },
	wreck = { path = "Scenery/dunes/Wreck", h = 9, len = 27, bounce = 1.3, sound = "metal" },
	tumbleweed = { path = "Scenery/dunes/Tumbleweed", h = 9, len = 10, bounce = 0.8, sound = "thud" },
}
TrackGen.Targets = TARGETS
local TARGET_SETS = {
	fields = { { "hay", 5 }, { "kup", 3 }, { "tractor", 2 }, { "buffalo", 1 } },
	highway = { { "hay", 2 }, { "dhaba", 2 }, { "container", 2 }, { "truck", 1.2 } },
	desert = { { "hay", 2 }, { "wreck", 2 }, { "tumbleweed", 2 }, { "camel", 1.3 } },
}
-- the opening stretch, the same every run (metres): it teaches the run in its first 300 m
local OPENING = {
	targets = { { 40, "hay" }, { 110, "tractor" }, { 200, "buffalo" }, { 250, "kup" }, { 300, "hay" } },
	smash = { 150, 154 },
	pad = 85,
	coins = { 52, 96 },
}
local OPENING_END = 330 / Game.StudsToMetres

local function pickFrom(set, rng: Random): string
	local total = 0
	for _, e in ipairs(set) do total += e[2] end
	local r = rng:NextNumber() * total
	for _, e in ipairs(set) do
		r -= e[2]
		if r <= 0 then return e[1] end
	end
	return set[#set][1]
end

--==============================================================
-- construction
--==============================================================
function TrackGen.get(trackId: string)
	if cache[trackId] then return cache[trackId] end
	local isRoad = trackId == "road"
	local cfg = isRoad and ZONE_CFGS[1] or Config.TracksById[trackId]
	assert(cfg, "unknown track " .. tostring(trackId))

	local self = setmetatable({}, Track)
	self.id = trackId
	self.isRoad = isRoad
	self.cfg = cfg
	self.seed = cfg.seed
	self.runSeed = cfg.seed
	self.o1 = (cfg.seed % 977) * 0.37
	self.o2 = (cfg.seed % 613) * 0.71 + 41.3
	self.o3 = (cfg.seed % 431) * 1.13 + 88.9
	self._ramps = {}
	self._objects = {}
	self._decor = {}
	self._tools = {}
	self._metals = {}
	self._hazards = {}
	self._keys = {}
	self._targets = {}
	self.toolboxRate = 0
	self.obstacleSet = OBSTACLE_SETS[cfg.scenery] or OBSTACLE_SETS.fields
	cache[trackId] = self
	return self
end

--==============================================================
-- zones (the road only; a single track is one zone)
--==============================================================
function Track:zoneIndex(x: number): number
	if not self.isRoad then return 1 end
	local idx = 1
	for i, s in ipairs(ZONE_STARTS) do
		if x >= s then idx = i end
	end
	return idx
end

function Track:cfgAt(x: number)
	if not self.isRoad then return self.cfg end
	return ZONE_CFGS[self:zoneIndex(x)]
end

-- how far through its zone x is, 0 at the zone line to 1 at the next
function Track:zoneFrac(x: number): number
	if not self.isRoad then return math.clamp(x / (Config.Difficulty.Checkpoints[#Config.Difficulty.Checkpoints]), 0, 1) end
	local i = self:zoneIndex(x)
	local s0 = ZONE_STARTS[i]
	local s1 = ZONE_STARTS[i + 1] or (s0 + 25000)
	return math.clamp((x - s0) / (s1 - s0), 0, 1)
end

function Track:zoneStart(i: number): number
	return ZONE_STARTS[i] or 0
end

local function noise(x: number, o: number): number
	return math.noise(x, o, 0) * 2
end

--==============================================================
-- ramps (pure: never calls heightAt, so heightAt can call this)
--==============================================================
function Track:rampsForChunk(ci: number)
	local cached = self._ramps[ci]
	if cached then return cached end

	local cfg = self:cfgAt(ci * CHUNK + CHUNK / 2)
	local rng = Random.new(self.runSeed * 7919 + ci * 104729 + 11)
	local list = {}

	-- the first 900 studs are a clean approach so the launch always reads well
	local d = Config.DifficultyAt(ci * CHUNK)
	local expected = CHUNK / cfg.rampEvery * Config.DiffLerp(Config.Difficulty.RampRate, d)
	local count = math.floor(expected)
	if rng:NextNumber() < (expected % 1) then count += 1 end
	if ci < 3 then count = math.min(count, 1) end
	if ci < 1 then count = 0 end

	for i = 1, count do
		local x = ci * CHUNK + rng:NextNumber(30, CHUNK - 30)
		-- a ramp is a gentle kicker a rolling tyre can climb (the old wall-steep ones stopped it dead)
		local len = rng:NextNumber(110, 200)
		local hgt = rng:NextNumber(9, 26) * (cfg.scenery == "mountain" and 1.35 or 1)
		table.insert(list, {
			x = x, len = len, h = hgt,
			kicker = rng:NextNumber() < 0.62,	-- true = abrupt lip, false = smooth crest
			width = rng:NextNumber(70, 190),
			z = rng:NextNumber(-40, 40),
		})
	end

	self._ramps[ci] = list
	return list
end

--==============================================================
-- ground height
--==============================================================
-- Three octaves, each scaled by how far into the run you are.
-- The fine "rough" octave is the one that used to make hills feel like walls:
-- amplitude times frequency is what sets slope, and a small fast wave has a
-- brutal gradient. It now starts at 15% and only reaches full at checkpoint 7.
-- The rollers: the hills the run is about. A tyre gains more speed running down a roller than
-- it gives back climbing the next (Config.Run.HillDown / HillUp), so a course of them carries
-- you on, and how well you take them (tuck downhill, nitro up, leave a crest, land on the far
-- slope) is how far you go. Two waves of different length so no two hills repeat, growing with
-- distance; the first crest sits where the cannon's shot comes down, so you land running.
function Track:rollerHeight(x: number): number
	local R = Config.Roller
	if x < R.Start then return 0 end
	-- a faster tyre needs bigger hills to feel them: the world grows with the stage (hillScale is
	-- the stage's speed squared, set per run), heights and lengths together so the slopes stay alike
	local hs = self.hillScale or 1
	local u = (x - R.Start) / hs
	local amp = math.clamp(R.Amp0 + u * R.AmpGrow, R.Amp0, R.AmpMax) * hs
	local a = 0.5 - 0.5 * math.cos(2 * math.pi * u / R.Wave1)
	local b = 0.5 - 0.5 * math.cos(2 * math.pi * u / R.Wave2 + self.o3)
	local swell = 0.78 + 0.22 * math.sin(u / R.Swell + self.o2)
	return amp * (a * swell + R.Second * b)
end

function Track:baseHeight(x: number): number
	local h
	if self.isRoad then
		local i = self:zoneIndex(x)
		h = self:octaves(ZONE_CFGS[i], x)
		local into = x - ZONE_STARTS[i]
		if i > 1 and into < ZONE_BLEND then
			local t = into / ZONE_BLEND
			t = t * t * (3 - 2 * t)
			h = self:octaves(ZONE_CFGS[i - 1], x) * (1 - t) + h * t
		end
	else
		h = self:octaves(self.cfg, x)
	end
	-- flatten the landing apron so the launch always reads cleanly
	if x < 420 then
		local t = math.clamp(x / 420, 0, 1)
		h *= t * t
	end
	if self.isRoad then h += self:rollerHeight(x) end
	return h
end

function Track:octaves(cfg, x: number): number
	local D = Config.Difficulty
	local d = Config.DifficultyAt(x)

	local a1 = cfg.hillAmp * Config.DiffLerp(D.HillAmp, d)
	local f1 = cfg.hillFreq * Config.DiffLerp(D.HillFreq, d)
	local a2 = cfg.hillAmp * 0.30 * Config.DiffLerp(D.MidAmp, d)
	local f2 = cfg.hillFreq * 3.1
	local a3 = cfg.roughAmp * Config.DiffLerp(D.RoughAmp, d)
	local f3 = cfg.roughFreq * 0.55

	return a1 * noise(x * f1, self.o1)
		+ a2 * noise(x * f2, self.o2)
		+ a3 * noise(x * f3, self.o3)
end

function Track:rampHeight(x: number): number
	local add = 0
	local ci = math.floor(x / CHUNK)
	for c = ci - RAMP_REACH, ci + RAMP_REACH do
		if c >= 0 then
			for _, r in ipairs(self:rampsForChunk(c)) do
				local d = x - r.x
				if d >= 0 and d <= r.len then
					local t = d / r.len
					add += r.h * (t ^ 1.55)
				elseif not r.kicker and d > r.len and d <= r.len * 1.9 then
					local t = (d - r.len) / (r.len * 0.9)
					add += r.h * (1 - t) ^ 1.4
				end
			end
		end
	end
	return add
end

function Track:heightAt(x: number): number
	if x < 0 then return 0 end
	return self:baseHeight(x) + self:rampHeight(x)
end

-- Forward slope, used for launch-off-crest behaviour and visuals.
function Track:slopeAt(x: number): number
	local d = 4
	return (self:heightAt(x + d) - self:heightAt(x - d)) / (2 * d)
end

--==============================================================
-- rarity roll
--==============================================================
local PERKS_BY_RARITY: { [string]: { any } } = {}
for _, p in ipairs(Config.Perks) do
	PERKS_BY_RARITY[p.rarity] = PERKS_BY_RARITY[p.rarity] or {}
	table.insert(PERKS_BY_RARITY[p.rarity], p)
end

local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

function Track:rollPerk(rng: Random, x: number)
	-- deeper into the run, and on later tracks, the good stuff gets likelier
	local depth = math.clamp(x / 45000, 0, 1.6)
	local trackBias = (self.isRoad and (self:zoneIndex(x) - 1) * 0.12 or (self.cfg.creditMult - 1) * 0.5) + (self.luck or 0)
	local total = 0
	local weights = {}
	for i, r in ipairs(RARITY_ORDER) do
		local info = Config.Rarity[r]
		local w = info.weight
		if i >= 3 then
			w *= (1 + depth * (i - 1) * 0.8 + trackBias * (i - 1) * 0.5)
		elseif i == 1 then
			w *= math.max(0.35, 1 - depth * 0.35)
		end
		weights[i] = w
		total += w
	end

	local pick = rng:NextNumber() * total
	local chosen = "Common"
	for i, r in ipairs(RARITY_ORDER) do
		pick -= weights[i]
		if pick <= 0 then chosen = r break end
	end

	local pool = PERKS_BY_RARITY[chosen]
	return pool[rng:NextInteger(1, #pool)]
end

--==============================================================
-- objects: quirk icons, obstacles, boost pads
--==============================================================
function Track:objectsForChunk(ci: number)
	local cached = self._objects[ci]
	if cached then return cached end

	local cfg = self:cfgAt(ci * CHUNK + CHUNK / 2)
	local obstacleSet = OBSTACLE_SETS[cfg.scenery] or self.obstacleSet
	local half = Config.Physics.CorridorHalfWidth
	local rng = Random.new(self.runSeed * 6151 + ci * 39916801 + 3)
	local out = { perks = {}, obstacles = {}, pads = {} }

	-- the road (v3): one lane. Smashables and pads sit on it between the target slots; no quirk icons
	if self.isRoad then
		local M = Game.StudsToMetres
		local function smash(key: string, x: number, zAt: number?)
			-- never a hay bale: that's a bounce target on the road, and the two must never look alike
			local def = obstacleSet[rng:NextInteger(1, #obstacleSet)]
			for _ = 1, 4 do
				if def.kind ~= "haybale" then break end
				def = obstacleSet[rng:NextInteger(1, #obstacleSet)]
			end
			if def.kind == "haybale" then def = OBSTACLE_SETS.fields[2] end
			local scale = rng:NextNumber(0.8, 1.05)
			table.insert(out.obstacles, {
				key = key, x = x, z = zAt or rng:NextNumber(-3, 3), y = self:heightAt(x),
				kind = def.kind, w = def.w * scale, h = def.h * scale, d = def.d * scale,
				loss = def.loss, color = def.color, mat = def.mat,
				model = def.model, folder = def.folder, runModel = def.runModel, breaks = def.breaks, scale = scale,
				yaw = rng:NextNumber(-0.3, 0.3),
			})
		end
		local function pad(key: string, x: number)
			table.insert(out.pads, {
				key = key, x = x, z = 0, y = self:heightAt(x), w = 34,
				power = 115 * rng:NextNumber(0.9, 1.3), lift = rng:NextNumber(60, 95), yaw = 0,
			})
		end
		local x0, x1 = ci * CHUNK, (ci + 1) * CHUNK
		for i, m in ipairs(OPENING.smash) do
			local x = m / M
			if x >= x0 and x < x1 then smash(ci .. ":os" .. i, x) end
		end
		if OPENING.pad / M >= x0 and OPENING.pad / M < x1 then pad(ci .. ":op", OPENING.pad / M) end
		if x1 > OPENING_END then
			-- sporadic, not a beat: a slow "busy-ness" along the road leaves some stretches bare and
			-- clusters others, and each piece lands anywhere along the chunk and across the lane
			local busy = math.clamp((math.noise(ci * 0.29, (self.runSeed % 977) * 0.013, 0.5) + 0.5), 0, 1)
			local n = 0
			if rng:NextNumber() < 0.15 + busy * 0.6 then
				n = 1
				if rng:NextNumber() < busy * 0.55 then n += 1 end
				if rng:NextNumber() < busy * 0.25 then n += 1 end
			end
			local cx = x0 + rng:NextNumber(30, CHUNK - 30)
			local cz = rng:NextNumber(-half * 0.45, half * 0.45)
			for k = 1, n do
				-- a cluster sits round one spot; a lone one anywhere
				local x = if n > 1 then cx + rng:NextNumber(-34, 34) else x0 + rng:NextNumber(15, CHUNK - 15)
				local z = if n > 1 then cz + rng:NextNumber(-18, 18) else rng:NextNumber(-half * 0.55, half * 0.55)
				if x > OPENING_END and x > x0 and x < x1 then smash(ci .. ":o" .. k, x, z) end
			end
			if rng:NextNumber() < 0.2 then
				local x = x0 + rng:NextNumber(20, CHUNK - 20)
				if x > OPENING_END then pad(ci .. ":d1", x) end
			end
		end
		-- the skill zones' furniture (their own generator, so the rest of the road is the same with or
		-- without them)
		for _, zone in ipairs(self:skillZones(x0, x1)) do
			local zr = Random.new((self.runSeed % 65536) * 104729 + zone.i * 7177 + 5)
			if zone.kind == "smash" then
				for k = 1, 9 do
					local x = zone.x0 + 36 + (k - 1) * 42 + zr:NextNumber(-8, 8)
					local z = zr:NextNumber(-half * 0.5, half * 0.5)
					if x >= x0 and x < x1 then smash(ci .. ":z" .. zone.i .. ":" .. k, x, z) end
				end
			elseif zone.kind == "speed" then
				for k = 1, 3 do
					local x = zone.x0 + 70 + (k - 1) * 140
					if x >= x0 and x < x1 then pad(ci .. ":zp" .. zone.i .. ":" .. k, x) end
				end
			end
		end
		self._objects[ci] = out
		return out
	end

	local d = Config.DifficultyAt(ci * CHUNK)
	local D = Config.Difficulty
	local function countFor(every: number, minChunk: number, rate: number?): number
		if ci < minChunk then return 0 end
		local e = CHUNK / every * (rate or 1)
		local n = math.floor(e)
		if rng:NextNumber() < (e % 1) then n += 1 end
		return n
	end

	-- QUIRK ICONS -------------------------------------------------
	local perkCount = countFor(cfg.perkEvery * Config.DiffLerp(D.PerkSpacing, d), 1)
	for i = 1, perkCount do
		local x = ci * CHUNK + rng:NextNumber(20, CHUNK - 20)
		-- kept nearer the racing line so a quirk is always a reachable choice,
		-- not a coin flip on where it happened to spawn
		local z = rng:NextNumber(-half * 0.62, half * 0.62)
		local ground = self:heightAt(x)
		local perk = self:rollPerk(rng, x)
		local tier = Config.Rarity[perk.rarity].order
		-- rarer icons float higher, so they cost you a real commitment to reach
		-- wider spread in height as well as across the road, so no two stretches
		-- present the same shape twice
		local lift = 14 + tier * 14 + rng:NextNumber(0, 44)
		table.insert(out.perks, {
			key = ci .. ":p" .. i,
			x = x, z = z, y = ground + lift,
			perkId = perk.id,
			rarity = perk.rarity,
			spinSpeed = 1.1 + tier * 0.28,
			bob = 2.5 + tier * 0.8,
			phase = rng:NextNumber(0, 6.28),
		})
	end

	-- clustered bonus ring: three icons in an arc, worth diving for
	if ci >= 2 and rng:NextNumber() < 0.14 then
		local cx = ci * CHUNK + rng:NextNumber(40, CHUNK - 40)
		local cz = rng:NextNumber(-half * 0.6, half * 0.6)
		local ground = self:heightAt(cx)
		local baseLift = 34 + rng:NextNumber(0, 40)
		for k = -1, 1 do
			local perk = self:rollPerk(rng, cx)
			local tier = Config.Rarity[perk.rarity].order
			table.insert(out.perks, {
				key = ci .. ":c" .. (k + 2),
				x = cx + k * 26, z = cz + k * 14, y = ground + baseLift + math.abs(k) * 10,
				perkId = perk.id, rarity = perk.rarity,
				spinSpeed = 1.4 + tier * 0.3, bob = 3.0, phase = rng:NextNumber(0, 6.28),
				cluster = true,
			})
		end
	end

	-- OBSTACLES ---------------------------------------------------
	local obsCount = countFor(cfg.obstacleEvery, 3, Config.DiffLerp(D.ObstacleRate, d))
	for i = 1, obsCount do
		local x = ci * CHUNK + rng:NextNumber(20, CHUNK - 20)
		local z = rng:NextNumber(-half * 0.9, half * 0.9)
		local def = obstacleSet[rng:NextInteger(1, #obstacleSet)]
		local scale = rng:NextNumber(0.85, 1.3)
		table.insert(out.obstacles, {
			key = ci .. ":o" .. i,
			x = x, z = z, y = self:heightAt(x),
			kind = def.kind,
			w = def.w * scale, h = def.h * scale, d = def.d * scale,
			loss = def.loss, color = def.color, mat = def.mat,
			model = def.model, folder = def.folder, runModel = def.runModel, breaks = def.breaks, scale = scale,
			yaw = rng:NextNumber(-0.4, 0.4),
		})
	end

	-- BOOST PADS --------------------------------------------------
	local padCount = countFor(cfg.padEvery, 2, Config.DiffLerp(D.PadRate, d))
	for i = 1, padCount do
		local x = ci * CHUNK + rng:NextNumber(30, CHUNK - 30)
		local z = rng:NextNumber(-half * 0.7, half * 0.7)
		table.insert(out.pads, {
			key = ci .. ":d" .. i,
			x = x, z = z, y = self:heightAt(x),
			w = rng:NextNumber(28, 36),
			power = 125 * rng:NextNumber(0.8, 1.45),
			lift = rng:NextNumber(35, 85),
			yaw = rng:NextNumber(-0.25, 0.25),
		})
	end

	self._objects[ci] = out
	return out
end

--==============================================================
-- toolboxes
-- Not bought, not guaranteed: found lying on the road, roughly one every
-- SpawnEvery studs, and the good ones only exist deep into a run because a
-- rarity is filtered out entirely until you have crossed its checkpoint.
--==============================================================
function Track:rollToolboxRarity(rng: Random, tier: number)
	local pool, total = {}, 0
	for _, r in ipairs(Config.ToolboxRarities) do
		if tier >= r.minTier then
			local w = r.weight
			-- legendary exists at checkpoint 6 but is throttled hard; it only
			-- comes into its own at 7
			if r.id == "legendary" and tier < 7 then
				w *= Config.Toolbox.LegendaryTier6Scale
			end
			-- and the further you are past a rarity's gate, the likelier it gets
			w *= 1 + math.min(2, (tier - r.minTier)) * 0.22
			table.insert(pool, { r = r, w = w })
			total += w
		end
	end
	if total <= 0 then return Config.ToolboxRarities[1] end
	local pick = rng:NextNumber() * total
	for _, e in ipairs(pool) do
		pick -= e.w
		if pick <= 0 then return e.r end
	end
	return pool[#pool].r
end

function Track:toolboxesForChunk(ci: number)
	local cached = self._tools[ci]
	if cached then return cached end

	local list = {}
	-- nothing in the opening stretch: the first thing you should be reading is
	-- the launch, not a pickup; and none on the road, which has keys instead
	if ci >= 4 and not self.isRoad then
		-- Two things to get right at once. The seed has to stay inside 2^53 or
		-- Random.new silently clamps it to zero and every chunk draws the same
		-- number; and consecutive chunk seeds have to be far apart or their first
		-- draw comes out correlated. Fold the run seed down, then step by a large
		-- odd stride per chunk.
		local rng = Random.new((self.runSeed % 65536) * 40503 + ci * 2654435761 + 19)
		rng:NextNumber()
		local chance = (CHUNK / Config.Toolbox.SpawnEvery) * (1 + (self.toolboxRate or 0))
		if rng:NextNumber() < chance then
			local x = ci * CHUNK + rng:NextNumber(30, CHUNK - 30)
			local half = Config.Physics.CorridorHalfWidth
			local tier = Config.TierAt(x)
			local rar = self:rollToolboxRarity(rng, tier)
			local kind = Config.ToolboxKinds[rng:NextInteger(1, #Config.ToolboxKinds)]
			table.insert(list, {
				key = ci .. ":t1",
				x = x,
				z = rng:NextNumber(-half * 0.55, half * 0.55),
				y = self:heightAt(x) + 9,
				kind = kind.id,
				rarity = rar.id,
				tier = tier,
				phase = rng:NextNumber(0, 6.28),
			})
		end
	end

	self._tools[ci] = list
	return list
end

--==============================================================
-- roadside scenery (visual only): clusters of models off both edges
--==============================================================
function Track:decorForChunk(ci: number)
	local cached = self._decor[ci]
	if cached then return cached end

	local half = Config.Physics.CorridorHalfWidth
	local rng = Random.new(self.runSeed * 3571 + ci * 15485863 + 7)
	local zcfg = self:cfgAt(ci * CHUNK + CHUNK / 2)
	local set = DECOR_SETS[zcfg.scenery] or DECOR_SETS.fields
	local total = 0
	for _, d in ipairs(set) do total += d.weight end
	local function pickDef()
		local r = rng:NextNumber() * total
		for _, d in ipairs(set) do
			r -= d.weight
			if r <= 0 then return d end
		end
		return set[#set]
	end

	local list = {}
	-- (2026-10-16) how busy this stretch is: a slow seeded wave along the road, so there are quiet
	-- open runs and busier patches, never the same four clumps a chunk everywhere
	local s = (self.runSeed % 9973) * 0.137
	local x0 = ci * CHUNK
	local wave = 0.5 + 0.32 * math.sin(x0 / 2300 + s) + 0.18 * math.sin(x0 / 830 + s * 2.3)
	local clusters = 2 + math.floor(math.clamp(wave, 0, 1) * 7 + rng:NextNumber())
	for c = 1, clusters do
		local cx = ci * CHUNK + rng:NextNumber(0, CHUNK)
		local side = (c % 2 == 0) and 1 or -1
		local def = pickDef()
		local count = def.far and rng:NextInteger(1, 2) or rng:NextInteger(3, 6)
		local cz = side * (def.far and rng:NextNumber(half * 1.35, half * 1.9) or rng:NextNumber(half * 1.04, half * 1.3))
		for k = 1, count do
			local x = cx + rng:NextNumber(-18, 18)
			local z = cz + rng:NextNumber(-10, 10)
			if def.far then z = cz + side * rng:NextNumber(0, 30) end
			table.insert(list, {
				key = ci .. ":s" .. c .. "_" .. k,
				model = def.model, folder = def.folder, scenery = def.scenery and zcfg.id or nil,
				pick = def.pick and def.pick[rng:NextInteger(1, #def.pick)] or nil,
				x = x, y = self:heightAt(x), z = z,
				yaw = rng:NextNumber(0, math.pi * 2),
				scale = rng:NextNumber(def.scale[1], def.scale[2]),
				tint = rng:NextNumber(0.85, 1.08),
			})
			if not def.far and rng:NextNumber() < 0.35 then def = pickDef() end
		end
	end

	-- a landmark now and then: a little place built on purpose beside the road (a village on the
	-- Backroad, a truck stop on the Highway, a camel camp in the Thar), spaced 1.1-1.6 km apart by
	-- the seed, each piece placed by hand-ish rules (round the middle, facing the road, nudged)
	self:landmarksInto(list, ci, zcfg, half)
	self._decor[ci] = list
	return list
end

local LANDMARKS = {
	backroad = {
		{ "VillageHouse", 0, 0, 0.0 }, { "VillageHouse", -26, 10, 0.35 }, { "Kup", 22, -6, 0 }, { "Kup", 30, 8, 0 },
		{ "TubeWell", -10, -18, 0.2 }, { "Buffalo", 8, -22, 1.2 }, { "Goat", 14, -26, 2.1 }, { "Goat", 18, -20, 0.6 },
		{ "Tractor", -36, -10, 1.1 }, { "Bush", -18, 26, 0 }, { "Bush", 34, 24, 0 }, { "MustardPatch", 0, 36, 0 }, { "MustardPatch", 14, 40, 0 },
		{ "Fence", -8, -30, 0 }, { "Fence", 9, -31, 0.05 }, { "Mailbox", -2, -34, 0 },
	},
	highway = {
		{ "Dhaba", 0, 0, 0 }, { "GoodsTruck", -30, -8, 0.25 }, { "GoodsTruck", 30, -4, -0.15 }, { "StreetLamp", -12, -22, 0 },
		{ "StreetLamp", 14, -22, 0 }, { "Billboard", 0, 30, 0 }, { "JerseyBarrier", -18, -30, 0 }, { "JerseyBarrier", 0, -32, 0.04 },
		{ "JerseyBarrier", 18, -30, -0.03 }, { "HighwaySign", 44, -26, 0 },
	},
	dunes = {
		{ "Chhatri", 0, 18, 0 }, { "Camel", -14, -8, 1.3 }, { "Camel", -4, -14, 1.5 }, { "Camel", 8, -10, 1.2 },
		{ "Khejri", 26, 6, 0 }, { "Khejri", -30, 14, 0 }, { "Wreck", 34, -16, 0.6 }, { "CowSkull", 12, -24, 0 },
		{ "Tumbleweed", -22, -22, 0 }, { "PricklyPear", 20, 22, 0 },
	},
}

function Track:landmarksInto(list, ci: number, zcfg, half: number)
	if not self.isRoad then return end
	local pieces = LANDMARKS[zcfg.id]
	if not pieces then return end
	-- the landmarks' places along the road: every 1100-1600 m from the run's seed
	local stM = Game.StudsToMetres
	local x0, x1 = ci * CHUNK, (ci + 1) * CHUNK
	local r = Random.new(self.runSeed * 811 + 17)
	local m = r:NextNumber(500, 900)
	local k = 0
	while m / stM < x1 and k < 200 do
		local x = m / stM
		k += 1
		if x >= x0 then
			local lr = Random.new(self.runSeed * 6007 + k * 977)
			local side = if lr:NextNumber() < 0.5 then -1 else 1
			-- (far enough out that the pieces nearest the road stay off the steering corridor)
			local z0 = side * (half + 40 + lr:NextNumber(0, half * 0.25))
			local turn = lr:NextNumber(-0.3, 0.3)
			for i, p in ipairs(pieces) do
				-- (laid out facing the road: +z away from it; turned a touch as a whole, each piece nudged)
				local dx, dz = p[2] + lr:NextNumber(-2.5, 2.5), (p[3] + lr:NextNumber(-2.5, 2.5)) * side
				local cx = x + dx * math.cos(turn) - dz * math.sin(turn)
				local cz = z0 + dx * math.sin(turn) + dz * math.cos(turn)
				table.insert(list, {
					key = ci .. ":lm" .. k .. "_" .. i, scenery = zcfg.id, pick = p[1],
					x = cx, y = self:heightAt(cx), z = cz,
					yaw = (if side > 0 then math.pi else 0) + p[4] + turn + lr:NextNumber(-0.12, 0.12),
					scale = lr:NextNumber(0.92, 1.08), tint = lr:NextNumber(0.92, 1.05),
				})
			end
		end
		m += r:NextNumber(1100, 1600)
	end
end

--==============================================================
-- hazards: dust devils on the dunes. Ride into one and it throws you up.
--==============================================================
function Track:hazardsForChunk(ci: number)
	local cached = self._hazards[ci]
	if cached then return cached end
	local list = {}
	if self:cfgAt(ci * CHUNK + CHUNK / 2).scenery == "desert" and ci >= 6 then
		local rng = Random.new((self.runSeed % 65536) * 91433 + ci * 1597334677 + 41)
		rng:NextNumber()
		if rng:NextNumber() < 0.16 then
			local x = ci * CHUNK + rng:NextNumber(40, CHUNK - 40)
			local half = Config.Physics.CorridorHalfWidth
			table.insert(list, {
				key = ci .. ":h1",
				kind = "dustdevil",
				x = x,
				z = self.isRoad and 0 or rng:NextNumber(-half * 0.6, half * 0.6),
				y = self:heightAt(x),
				radius = rng:NextNumber(16, 26),
				lift = rng:NextNumber(220, 320),
				sway = rng:NextNumber(0.4, 0.9),
			})
		end
	end
	self._hazards[ci] = list
	return list
end

--==============================================================
-- metals: bronze from checkpoint 1, silver from 3, gold from 6
--==============================================================
function Track:metalsForChunk(ci: number)
	local cached = self._metals[ci]
	if cached then return cached end
	local list = {}
	if self.isRoad then
		-- coin arcs over the lane: the line a good bounce takes. Bronze, silver deeper in, a gold
		-- coin at the top of an arc now and then
		local M = Game.StudsToMetres
		local rng = Random.new((self.runSeed % 65536) * 52711 + ci * 2246822519 + 29)
		rng:NextNumber()
		local function arc(key: string, xa: number, xb: number, rise: number)
			local n = 6
			local zi = self:zoneIndex((xa + xb) / 2)
			for k = 0, n - 1 do
				local t = k / (n - 1)
				local x = xa + (xb - xa) * t
				local top = k == math.floor(n / 2)
				local kind = (top and rng:NextNumber() < 0.25) and "gold" or (zi >= 2 and rng:NextNumber() < 0.4 and "silver" or "bronze")
				local def = Config.MetalsById[kind]
				table.insert(list, {
					key = key .. "_" .. k, kind = kind, amount = def and def.amount or 1,
					x = x, z = 0, y = self:heightAt(x) + 16 + rise * math.sin(math.pi * t), phase = k * 0.6,
				})
			end
		end
		local oa, ob = OPENING.coins[1] / M, OPENING.coins[2] / M
		if oa >= ci * CHUNK and oa < (ci + 1) * CHUNK then arc("oc", oa, ob, 30) end
		if (ci + 1) * CHUNK > OPENING_END and rng:NextNumber() < 0.75 then
			local xa = ci * CHUNK + rng:NextNumber(60, 140)
			if xa > OPENING_END then arc(ci .. ":c", xa, xa + rng:NextNumber(90, 150), rng:NextNumber(22, 60)) end
		end
		self._metals[ci] = list
		return list
	end
	if ci >= 2 then
		local rng = Random.new((self.runSeed % 65536) * 52711 + ci * 2246822519 + 29)
		rng:NextNumber()
		local half = Config.Physics.CorridorHalfWidth
		for i, m in ipairs(Config.Metals) do
			local roll = rng:NextNumber()
			local x = ci * CHUNK + rng:NextNumber(25, CHUNK - 25)
			local z = rng:NextNumber(-half * 0.7, half * 0.7)
			local phase = rng:NextNumber(0, 6.28)
			if Config.TierAt(x) >= m.fromTier and roll < m.chance then
				table.insert(list, {
					key = ci .. ":m" .. i, kind = m.id, amount = m.amount,
					x = x, z = z, y = self:heightAt(x) + 7, phase = phase,
				})
			end
		end
	end
	self._metals[ci] = list
	return list
end

--==============================================================
-- checkpoint draft: three distinct quirks, rolled as if deeper than you are
--==============================================================
function Track:draftCards(tier: number)
	local rng = Random.new((self.runSeed % 65536) * 7717 + tier * 104723 + 5)
	local cps = Config.Difficulty.Checkpoints
	local depthX = (cps[tier] or 0) * Config.Draft.DepthBoost
	local out, seen = {}, {}
	local guard = 0
	while #out < Config.Draft.Choices and guard < 60 do
		guard += 1
		local perk = self:rollPerk(rng, depthX)
		if not seen[perk.id] then
			seen[perk.id] = true
			table.insert(out, perk)
		end
	end
	return out
end

--==============================================================
-- keys (the road): one in every zone, 40% of the way through it, somewhere across the road so
-- you have to steer for it
--==============================================================
function Track:keysForChunk(ci: number)
	local cached = self._keys[ci]
	if cached then return cached end
	local list = {}
	if self.isRoad then
		local half = Config.Physics.CorridorHalfWidth
		for i, m in ipairs(Game.keySpots()) do
			local x = m / Game.StudsToMetres
			-- (keyAllow: the run's keys from the server's Begin; nil shows them all, as the load scene does)
			local allowed = self.keyAllow == nil or table.find(self.keyAllow, i) ~= nil
			if allowed and x >= ci * CHUNK and x < (ci + 1) * CHUNK then
				local rng = Random.new((self.runSeed % 65536) * 31337 + i * 2654435761 + 23)
				rng:NextNumber()
				local _ = half
				-- on the route, a little to one side of the ring line: a key is a detour worth taking
				local rz, rup = self:routeAt(x)
				table.insert(list, {
					key = "key" .. i, zone = i,
					x = x, z = math.clamp(rz + (i == 1 and 0 or rng:NextNumber(-40, 40)), -150, 150),
					y = self:heightAt(x) + (i == 1 and 14 or rng:NextNumber(10, 34)) + 0 * rup, phase = rng:NextNumber(0, 6.28),
				})
			end
		end
	end
	self._keys[ci] = list
	return list
end

function Track:chunkIndex(x: number): number
	return math.floor(x / CHUNK)
end

-- Every attempt gets its own terrain. The noise offsets and all the object
-- RNG hang off runSeed, so a new seed means a genuinely different run, and
-- the same seed reproduces it exactly (which is what spectating will need).
function Track:setRun(runSeed: number, luck: number?, toolboxRate: number?)
	self.runSeed = math.max(1, math.floor(runSeed or self.cfg.seed))
	self.luck = luck or 0
	self.toolboxRate = toolboxRate or 0
	local r = Random.new(self.runSeed)
	self.o1 = r:NextNumber(0, 600)
	self.o2 = r:NextNumber(0, 600)
	self.o3 = r:NextNumber(0, 600)
	self._ramps = {}
	self._objects = {}
	self._decor = {}
	self._tools = {}
	self._metals = {}
	self._hazards = {}
	self._keys = {}
	self._targets = {}
	self._zones = nil
	self.skillKind = nil
end

--==============================================================
-- skill zones: stretches of road set out for the launch tyre's skill (RunSim sets the kind each run;
-- "air", "smash" or "speed"). They start well into the run and come every couple of thousand studs.
-- A smash zone carries a scatter of extra smashables, a speed zone a line of pads; an air zone is an
-- updraft and needs nothing on the road.
--==============================================================
local ZONE_LEN = 420
function Track:setSkillKind(kind: string?)
	if self.skillKind == kind then return end
	self.skillKind = kind
	self._objects = {}
	self._zones = nil
end

-- the zones whose stretch overlaps [x0, x1)
function Track:skillZones(x0: number, x1: number)
	if not self.skillKind or not self.isRoad then return {} end
	local z = self._zones
	if not z then
		z = { list = {}, rng = Random.new((self.runSeed % 65536) * 7919 + 41), nextX = 2600 }
		z.nextX += z.rng:NextNumber(0, 700)
		self._zones = z
	end
	while z.nextX < x1 + ZONE_LEN do
		local a = z.nextX
		table.insert(z.list, { i = #z.list + 1, x0 = a, x1 = a + ZONE_LEN, kind = self.skillKind })
		z.nextX = a + ZONE_LEN + z.rng:NextNumber(1900, 3200)
	end
	local out = {}
	for _, zone in ipairs(z.list) do
		if zone.x1 > x0 and zone.x0 < x1 then table.insert(out, zone) end
	end
	return out
end

--==============================================================
-- bounce targets for a chunk: the opening stretch's fixed ones, then two slots a chunk that may
-- each hold one, picked from the zone's set (Stampede, a server event, fills more of them)
--==============================================================
function Track:targetsForChunk(ci: number)
	-- (the bounce targets are off for now: the road is hills and the things you smash)
	if not Config.Run.Targets then return {} end
	local cached = self._targets[ci]
	if cached then return cached end
	local list = {}
	local M = Game.StudsToMetres
	local function add(key: string, kind: string, x: number)
		local def = TARGETS[kind]
		table.insert(list, {
			key = key, kind = kind, path = def.path, x = x, z = 0, y = self:heightAt(x),
			h = def.h, len = def.len, bounce = def.bounce, sound = def.sound,
		})
	end
	local x0, x1 = ci * CHUNK, (ci + 1) * CHUNK
	if self.isRoad then
		for i, t in ipairs(OPENING.targets) do
			local x = t[1] / M
			if x >= x0 and x < x1 then add("o" .. i, t[2], x) end
		end
		if x1 > OPENING_END then
			local rng = Random.new((self.runSeed % 65536) * 48611 + ci * 2246822519 + 61)
			rng:NextNumber()
			local cfg = self:cfgAt(x0 + CHUNK / 2)
			local set = TARGET_SETS[cfg.scenery] or TARGET_SETS.fields
			local chance = 0.62 * (self.targetRate or 1)
			for slot, range in ipairs({ { 20, 120 }, { 180, 280 } }) do
				local x = x0 + rng:NextNumber(range[1], range[2])
				local roll = rng:NextNumber()
				local kind = pickFrom(set, rng)
				if x > OPENING_END and roll < chance then add(ci .. ":b" .. slot, kind, x) end
			end
		end
	end
	self._targets[ci] = list
	return list
end

--==============================================================
-- the route: a gentle line that wanders across the road. Keys sit on it, a little off to one side,
-- so taking one is a detour worth the trouble.
--==============================================================
-- where the route is at x: z across the road, and its clearance above the ground
function Track:routeAt(x: number): (number, number)
	if x < OPENING_END then
		return 22 * math.sin(x / 330), 46 + 8 * math.sin(x / 250)
	end
	local amp = math.clamp((x - OPENING_END) / 600, 0, 1)
	amp = amp * amp * (3 - 2 * amp)
	local s = self.runSeed % 9973
	local z = amp * (80 * math.sin(x / 1180 + s * 0.31) + 36 * math.sin(x / 470 + s * 0.77))
	local up = 52 + 34 * math.sin(x / 760 + s * 0.53) + 14 * math.sin(x / 290 + s)
	return z, up
end

-- the opening stretch's smash line, pad and coin arc (metres), for objectsForChunk/metalsForChunk
TrackGen.Opening = OPENING
TrackGen.OpeningEnd = OPENING_END

function Track:reset(luck: number?)
	self:setRun(self.runSeed, luck)
end

return TrackGen
