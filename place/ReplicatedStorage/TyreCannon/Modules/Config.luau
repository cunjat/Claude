--!strict
-- TYRE CANNON :: Config
-- Single source of truth for physics tuning, perks, upgrades, tracks and economy.

local Config = {}

Config.Version = "0.1.0"
Config.GameName = "TYRE CANNON"

--==============================================================
-- PHYSICS
--==============================================================
Config.Physics = {
	CorridorHalfWidth = 130,
	TyreRadius = 6,
	MaxSpeed = 1400,			-- terminal velocity; keeps late-game runs finite
	StudsToMetres = 0.28,
}

--==============================================================
-- DIFFICULTY
-- Terrain is reseeded every attempt and ramps up across seven checkpoints.
-- Tier 0 is deliberately gentle: you should always be able to build speed.
-- Only by checkpoint 7 is the ground genuinely fighting you.
--==============================================================
Config.Difficulty = {
	-- studs: where each zone of the road begins (Game.Zones starts / 0.28), so every gate is a zone line
	Checkpoints = { 2857, 7143, 13571, 22143, 32857, 46429, 64286 },
	Curve = 0.85,				-- <1 front-loads the ramp-up slightly

	-- how the three terrain octaves scale from tier 0 (d=0) to tier 7 (d=1)
	HillAmp     = { 0.50, 1.30 },	-- long rolling hills: the momentum you ride
	HillFreq    = { 0.65, 1.20 },
	MidAmp      = { 0.35, 1.40 },	-- medium undulation
	RoughAmp    = { 0.15, 1.50 },	-- fine chop: this is what murders momentum

	ObstacleRate = { 0.25, 1.75 },	-- multiplier on obstacles per chunk
	RampRate     = { 1.25, 0.85 },	-- more kickers early to help you get going
	PerkSpacing  = { 1.15, 0.80 },	-- quirks thin early, a touch denser deep in
	PadRate      = { 1.20, 0.90 },
}

function Config.TierAt(x: number): number
	local t = 0
	for i, d in ipairs(Config.Difficulty.Checkpoints) do
		if x >= d then t = i end
	end
	return t
end

-- Smooth 0..1 used for terrain, so amplitude never jumps at a checkpoint.
function Config.DifficultyAt(x: number): number
	local cps = Config.Difficulty.Checkpoints
	local last = cps[#cps]
	return math.clamp(x / last, 0, 1) ^ Config.Difficulty.Curve
end

function Config.DiffLerp(pair, d: number): number
	return pair[1] + (pair[2] - pair[1]) * d
end

--==============================================================
-- RARITY
--==============================================================
Config.Rarity = {
	Common    = { order = 1, weight = 100, color = Color3.fromRGB(226, 232, 240), glow = 1.0, name = "Common" },
	Uncommon  = { order = 2, weight = 58,  color = Color3.fromRGB(74, 222, 128),  glow = 1.4, name = "Uncommon" },
	Rare      = { order = 3, weight = 26,  color = Color3.fromRGB(96, 165, 250),  glow = 1.9, name = "Rare" },
	Epic      = { order = 4, weight = 9,   color = Color3.fromRGB(192, 132, 252), glow = 2.5, name = "Epic" },
	Legendary = { order = 5, weight = 2.5, color = Color3.fromRGB(251, 191, 36),  glow = 3.4, name = "Legendary" },
}

--==============================================================
-- PERKS / QUIRKS
-- mods    : continuous modifiers applied while the perk is active
-- instant : one-shot impulse applied the moment it is collected
--==============================================================
Config.Perks = {
	--------------------------- COMMON ---------------------------
	{ id = "nitro_roll", name = "Nitro Roll", rarity = "Common", icon = "rbxassetid://6031075931",
	  desc = "A steady shove forward for 7 seconds.",
	  duration = 7, mods = { thrust = 16 }, instant = { up = 63, fwd = 25 } },

	{ id = "feather_weight", name = "Feather Weight", rarity = "Common", icon = "rbxassetid://6034509993",
	  desc = "Gravity drops 28%. You hang in the air far longer.",
	  duration = 6, mods = { gravityMult = 0.72 }, instant = { up = 85 } },

	{ id = "slick_tread", name = "Slick Tread", rarity = "Common", icon = "rbxassetid://6034684949",
	  desc = "Rolling friction cut by more than half.",
	  duration = 8, mods = { frictionMult = 0.45 }, instant = { up = 56, fwd = 20 } },

	{ id = "air_kick", name = "Air Kick", rarity = "Common", icon = "rbxassetid://6035047377",
	  desc = "Instant punch of loft and forward drive.",
	  duration = 0, mods = {}, instant = { up = 132, fwd = 40 } },

	{ id = "credit_chip", name = "Credit Chip", rarity = "Common", icon = "rbxassetid://6034754445",
	  desc = "Loose change. 40 credits, banked instantly.",
	  duration = 0, mods = {}, instant = { up = 56, credits = 40 } },

	{ id = "second_wind", name = "Second Wind", rarity = "Common", icon = "rbxassetid://6031225817",
	  desc = "Tops up 35 units of boost fuel.",
	  duration = 0, mods = {}, instant = { up = 63, boost = 35 } },

	{ id = "fuel_tap", name = "Fuel Tap", rarity = "Common", icon = "rbxassetid://6034287618",
	  desc = "Boost burns no fuel at all for 6 seconds.",
	  duration = 6, mods = { boostFree = true }, instant = { up = 56, boost = 20 } },

	-------------------------- UNCOMMON --------------------------
	{ id = "steel_belt", name = "Steel Belt", rarity = "Uncommon", icon = "rbxassetid://6034509996",
	  desc = "Every bounce comes back 35% harder.",
	  duration = 9, mods = { bounceMult = 1.35 }, instant = { up = 70 } },

	{ id = "magnet_coil", name = "Magnet Coil", rarity = "Uncommon", icon = "rbxassetid://6031090990",
	  desc = "Triples pickup reach. Quirks come to you.",
	  duration = 10, mods = { magnetMult = 3.0 }, instant = { up = 63 } },

	{ id = "bounce_master", name = "Bounce Master", rarity = "Uncommon", icon = "rbxassetid://6034684950",
	  desc = "Huge restitution and a touch less gravity.",
	  duration = 7, mods = { bounceMult = 1.60, gravityMult = 0.90 }, instant = { up = 77 } },

	{ id = "tailwind", name = "Tailwind", rarity = "Uncommon", icon = "rbxassetid://6034684942",
	  desc = "Air drag slashed to 45%. Glide forever.",
	  duration = 9, mods = { dragMult = 0.45 }, instant = { up = 63, fwd = 35 } },

	{ id = "spin_cycle", name = "Spin Cycle", rarity = "Uncommon", icon = "rbxassetid://6035067836",
	  desc = "Earn 35% more credits for 12 seconds.",
	  duration = 12, mods = { creditMult = 1.35 }, instant = { up = 63 } },

	{ id = "momentum_bank", name = "Momentum Bank", rarity = "Uncommon", icon = "rbxassetid://6031280882",
	  desc = "Cashes out into raw forward speed.",
	  duration = 0, mods = {}, instant = { up = 77, fwd = 90 } },

	{ id = "grip_wax", name = "Grip Wax", rarity = "Uncommon", icon = "rbxassetid://6035145364",
	  desc = "Steering authority more than doubled.",
	  duration = 10, mods = { controlMult = 2.2 }, instant = { up = 63 } },

	---------------------------- RARE ----------------------------
	{ id = "ghost_tyre", name = "Ghost Tyre", rarity = "Rare", icon = "rbxassetid://6034925618",
	  desc = "Phase clean through every obstacle for 8 seconds.",
	  duration = 8, mods = { phase = true, thrust = 9 }, instant = { up = 85 } },

	{ id = "rocket_retread", name = "Rocket Retread", rarity = "Rare", icon = "rbxassetid://6031229347",
	  desc = "Strapped-on thrust. 140 studs/s of shove.",
	  duration = 6, mods = { thrust = 42 }, instant = { up = 98, fwd = 60 } },

	{ id = "double_credits", name = "Double Credits", rarity = "Rare", icon = "rbxassetid://6034754447",
	  desc = "Everything you earn counts twice for 10 seconds.",
	  duration = 10, mods = { creditMult = 2.0 }, instant = { up = 77 } },

	{ id = "skyhook", name = "Skyhook", rarity = "Rare", icon = "rbxassetid://6034287617",
	  desc = "Yanks you skyward, then lets you float down.",
	  duration = 4, mods = { gravityMult = 0.80 }, instant = { up = 290 } },

	{ id = "shockwave", name = "Shockwave", rarity = "Rare", icon = "rbxassetid://6035047384",
	  desc = "Blast forward and shrug off anything in the way.",
	  duration = 3, mods = { phase = true }, instant = { up = 85, fwd = 130 } },

	---------------------------- EPIC ----------------------------
	{ id = "overdrive", name = "Overdrive", rarity = "Epic", icon = "rbxassetid://6031075939",
	  desc = "Thrust, low drag and low friction, all at once.",
	  duration = 9, mods = { thrust = 36, dragMult = 0.50, frictionMult = 0.50 }, instant = { up = 118, fwd = 70 } },

	{ id = "perpetual_motion", name = "Perpetual Motion", rarity = "Epic", icon = "rbxassetid://6034925616",
	  desc = "Friction and drag all but vanish for 12 seconds.",
	  duration = 12, mods = { frictionMult = 0.15, dragMult = 0.25 }, instant = { up = 98 } },

	{ id = "golden_rim", name = "Golden Rim", rarity = "Epic", icon = "rbxassetid://6034754443",
	  desc = "2.5x credits and double magnet reach.",
	  duration = 12, mods = { creditMult = 2.5, magnetMult = 2.0 }, instant = { up = 90 } },

	-------------------------- LEGENDARY -------------------------
	{ id = "cannonball", name = "Cannonball", rarity = "Legendary", icon = "rbxassetid://6031280884",
	  desc = "You stop being a tyre and become ordnance.",
	  duration = 6, mods = { thrust = 28, phase = true }, instant = { up = 168, fwd = 300 } },

	{ id = "big_bang", name = "Big Bang", rarity = "Legendary", icon = "rbxassetid://6035047391",
	  desc = "Launched into the stratosphere on half gravity.",
	  duration = 8, mods = { gravityMult = 0.55 }, instant = { up = 440, fwd = 180 } },
}

Config.PerksById = {}
for _, p in ipairs(Config.Perks) do
	Config.PerksById[p.id] = p
end

--==============================================================
-- UPGRADES
-- Two trees: "Rig" (the launcher) and "Tyre" (you).
-- cost(level) = floor(baseCost * growth ^ level)
--==============================================================
Config.Upgrades = {
	---- RIG -------------------------------------------------------
	{ id = "engine", tree = "Rig", name = "Engine Displacement", order = 1,
	  desc = "Bigger single-cylinder diesel. Raises the base speed the flywheel can impart.",
	  maxLevel = 12, baseCost = 190, growth = 1.52,
	  stat = "launchSpeed", base = 210, perLevel = 20, unit = " studs/s" },

	{ id = "flywheel", tree = "Rig", name = "Flywheel Mass", order = 2,
	  desc = "Heavier wheel stores more energy, lifting the ceiling on a perfect charge.",
	  maxLevel = 12, baseCost = 240, growth = 1.55,
	  stat = "chargeCeiling", base = 1.00, perLevel = 0.028, unit = "x", percent = true },

	{ id = "belt", tree = "Rig", name = "Belt Grip", order = 3,
	  desc = "Less slip on the pulley. Widens the perfect-release window on the charge gauge.",
	  maxLevel = 10, baseCost = 210, growth = 1.50,
	  stat = "perfectWindow", base = 0.055, perLevel = 0.0060, unit = "", percent = true },

	{ id = "ramp", tree = "Rig", name = "Ramp Kicker", order = 4,
	  desc = "Rebuild the lip of the ramp steeper. More of your launch speed becomes altitude.",
	  maxLevel = 10, baseCost = 260, growth = 1.53,
	  stat = "launchLoft", base = 0.30, perLevel = 0.013, unit = "", percent = true },

	{ id = "injector", tree = "Rig", name = "Fuel Injector", order = 5,
	  desc = "Fills a larger boost tank before every launch.",
	  maxLevel = 12, baseCost = 200, growth = 1.51,
	  stat = "boostFuel", base = 100, perLevel = 11, unit = " fuel" },

	---- TYRE ------------------------------------------------------
	{ id = "tread", tree = "Tyre", name = "Tread Compound", order = 1,
	  desc = "Harder compound keeps momentum alive while you are rolling on the deck.",
	  maxLevel = 12, baseCost = 220, growth = 1.54,
	  stat = "frictionScale", base = 1.00, perLevel = -0.042, unit = "", percent = true, lowerBetter = true },

	{ id = "sidewall", tree = "Tyre", name = "Sidewall Stiffness", order = 2,
	  desc = "Stiffer walls fire you back off the ground instead of soaking the hit.",
	  maxLevel = 12, baseCost = 250, growth = 1.55,
	  stat = "restitution", base = 0.42, perLevel = 0.014, unit = "", percent = true },

	{ id = "aero", tree = "Tyre", name = "Aero Shell", order = 3,
	  desc = "Faired sidewalls cut the air. Long flights stay fast.",
	  maxLevel = 12, baseCost = 280, growth = 1.56,
	  stat = "dragScale", base = 1.00, perLevel = -0.045, unit = "", percent = true, lowerBetter = true },

	{ id = "control", tree = "Tyre", name = "Air Control", order = 4,
	  desc = "Gyro stabiliser. Steer harder on the ground and much harder in the air.",
	  maxLevel = 12, baseCost = 230, growth = 1.52,
	  stat = "controlScale", base = 1.00, perLevel = 0.080, unit = "", percent = true },

	{ id = "tank", tree = "Tyre", name = "Boost Tank", order = 5,
	  desc = "Higher-pressure nitrous. Boost pushes harder every second you hold it.",
	  maxLevel = 12, baseCost = 270, growth = 1.55,
	  stat = "boostAccel", base = 55, perLevel = 7, unit = " studs/s²" },

	{ id = "magnet", tree = "Tyre", name = "Magnet Rim", order = 6,
	  desc = "Charged rim drags nearby quirk icons into your path.",
	  maxLevel = 12, baseCost = 240, growth = 1.53,
	  stat = "magnetRadius", base = 20, perLevel = 4.0, unit = " studs" },

	{ id = "slots", tree = "Tyre", name = "Quirk Slots", order = 7,
	  desc = "How many quirks can burn at the same time. The build-defining upgrade.",
	  maxLevel = 3, baseCost = 3200, growth = 3.10,
	  stat = "perkSlots", base = 3, perLevel = 1, unit = " slots" },

	{ id = "durability", tree = "Tyre", name = "Casing Durability", order = 8,
	  desc = "Reinforced casing. Obstacles rob far less of your speed.",
	  maxLevel = 10, baseCost = 300, growth = 1.57,
	  stat = "impactScale", base = 1.00, perLevel = -0.060, unit = "", percent = true, lowerBetter = true },
}

Config.UpgradesById = {}
for _, u in ipairs(Config.Upgrades) do
	Config.UpgradesById[u.id] = u
end

function Config.UpgradeCost(id: string, level: number): number
	local u = Config.UpgradesById[id]
	if not u then return math.huge end
	if level >= u.maxLevel then return math.huge end
	return math.floor(u.baseCost * (u.growth ^ level))
end

function Config.StatAt(id: string, level: number): number
	local u = Config.UpgradesById[id]
	if not u then return 0 end
	return u.base + u.perLevel * math.clamp(level, 0, u.maxLevel)
end

-- Resolve a full stat block from a table of { upgradeId = level }
function Config.ComputeStats(levels: { [string]: number })
	levels = levels or {}
	local s = {}
	for _, u in ipairs(Config.Upgrades) do
		s[u.stat] = Config.StatAt(u.id, levels[u.id] or 0)
	end
	s.perkSlots = math.floor(s.perkSlots + 0.001)
	return s
end

--==============================================================
-- TRACKS
--==============================================================
Config.Tracks = {
	{
		id = "backroad", name = "Punjab Backroad", order = 1, available = true,
		deepGround = Color3.fromRGB(96, 74, 48), deepAccent = Color3.fromRGB(210, 120, 50),
		deepFog = Color3.fromRGB(150, 128, 96),
		bandProps = { "none", "haybales", "posts", "wreck", "boulders", "pylons", "rubble", "ruins" },
		subtitle = "Where the trend was born. Packed dirt, mustard fields, a very patient goat.",
		cost = 0, creditMult = 1.00, seed = 1337,
		ground = Color3.fromRGB(150, 118, 78), groundMaterial = Enum.Material.Ground,
		accent = Color3.fromRGB(120, 160, 70), fog = Color3.fromRGB(214, 205, 170), fogEnd = 2200,
		clockTime = 10.2, ambient = Color3.fromRGB(120, 115, 100),
		hillAmp = 30, hillFreq = 0.0011, roughAmp = 3.5, roughFreq = 0.008,
		rampEvery = 460, obstacleEvery = 430, perkEvery = 415, padEvery = 760,
		gravityMult = 1.00, dragMult = 1.00,
		scenery = "fields",
	},
	{
		id = "highway", name = "Grand Trunk Highway", order = 2, available = true,
		deepGround = Color3.fromRGB(38, 38, 44), deepAccent = Color3.fromRGB(255, 90, 40),
		deepFog = Color3.fromRGB(96, 100, 110),
		bandProps = { "none", "cones", "posts", "barriers", "wreck", "pylons", "rubble", "ruins" },
		subtitle = "Six lanes of hot asphalt and concrete barriers that do not move for anyone.",
		cost = 4000, creditMult = 1.25, seed = 90210,
		ground = Color3.fromRGB(72, 74, 80), groundMaterial = Enum.Material.Asphalt,
		accent = Color3.fromRGB(240, 200, 60), fog = Color3.fromRGB(190, 196, 205), fogEnd = 2600,
		clockTime = 12, ambient = Color3.fromRGB(130, 132, 138),
		hillAmp = 22, hillFreq = 0.0009, roughAmp = 1.5, roughFreq = 0.010,
		rampEvery = 420, obstacleEvery = 360, perkEvery = 390, padEvery = 680,
		gravityMult = 1.00, dragMult = 0.94,
		scenery = "highway",
	},
	{
		id = "dunes", name = "Thar Dunes", order = 3, available = true,
		deepGround = Color3.fromRGB(168, 110, 58), deepAccent = Color3.fromRGB(255, 150, 60),
		deepFog = Color3.fromRGB(206, 152, 96),
		bandProps = { "none", "posts", "boulders", "bones", "wreck", "spires", "rubble", "ruins" },
		subtitle = "Enormous rolling sand. Every crest is a ramp if you are brave enough.",
		cost = 15000, creditMult = 1.60, seed = 4242,
		ground = Color3.fromRGB(214, 176, 112), groundMaterial = Enum.Material.Sand,
		accent = Color3.fromRGB(233, 205, 150), fog = Color3.fromRGB(233, 214, 176), fogEnd = 1700,
		clockTime = 15.6, ambient = Color3.fromRGB(150, 130, 100),
		hillAmp = 52, hillFreq = 0.0013, roughAmp = 5, roughFreq = 0.007,
		rampEvery = 520, obstacleEvery = 520, perkEvery = 375, padEvery = 720,
		gravityMult = 0.95, dragMult = 1.06,
		scenery = "desert",
	},
}

Config.TracksById = {}
for _, t in ipairs(Config.Tracks) do
	Config.TracksById[t.id] = t
end

--==============================================================
-- THE ROAD: one road through eight zones (Game.Zones), each with its own ground, light,
-- terrain, obstacles and scenery. TrackGen.get("road") reads the zone under any x; the first three
-- are the original tracks' worlds. Kept out of Config.Tracks so track lists stay as they were.
--==============================================================
Config.ZoneWorlds = {
	backroad = Config.TracksById.backroad,
	highway = Config.TracksById.highway,
	dunes = Config.TracksById.dunes,
	quarry = {
		id = "quarry", name = "Quarry", seed = 5150,
		ground = Color3.fromRGB(132, 122, 110), groundMaterial = Enum.Material.Slate,
		deepGround = Color3.fromRGB(104, 94, 86), accent = Color3.fromRGB(214, 150, 64), deepAccent = Color3.fromRGB(240, 120, 40),
		fog = Color3.fromRGB(204, 196, 184), deepFog = Color3.fromRGB(170, 160, 148), fogEnd = 2100,
		clockTime = 9.0, ambient = Color3.fromRGB(124, 118, 110),
		hillAmp = 40, hillFreq = 0.0012, roughAmp = 4.5, roughFreq = 0.009,
		rampEvery = 440, obstacleEvery = 420, perkEvery = 400, padEvery = 700,
		gravityMult = 1.00, dragMult = 1.00, creditMult = 1, scenery = "quarry",
		bandProps = { "none", "boulders", "rubble", "posts", "wreck", "rubble", "boulders", "ruins" },
	},
	docks = {
		id = "docks", name = "Docks", seed = 7007,
		ground = Color3.fromRGB(112, 114, 120), groundMaterial = Enum.Material.Concrete,
		deepGround = Color3.fromRGB(90, 92, 100), accent = Color3.fromRGB(244, 196, 56), deepAccent = Color3.fromRGB(250, 160, 40),
		fog = Color3.fromRGB(242, 200, 164), deepFog = Color3.fromRGB(214, 160, 130), fogEnd = 2400,
		clockTime = 16.6, ambient = Color3.fromRGB(160, 140, 128),
		hillAmp = 18, hillFreq = 0.0008, roughAmp = 1.2, roughFreq = 0.010,
		rampEvery = 400, obstacleEvery = 380, perkEvery = 390, padEvery = 640,
		gravityMult = 1.00, dragMult = 0.96, creditMult = 1, scenery = "docks",
		bandProps = { "none", "posts", "barriers", "cones", "wreck", "pylons", "barriers", "rubble" },
	},
	saltflats = {
		id = "saltflats", name = "Salt Flats", seed = 9001,
		ground = Color3.fromRGB(236, 234, 226), groundMaterial = Enum.Material.Salt,
		deepGround = Color3.fromRGB(226, 222, 212), accent = Color3.fromRGB(80, 132, 220), deepAccent = Color3.fromRGB(60, 110, 210),
		fog = Color3.fromRGB(226, 236, 248), deepFog = Color3.fromRGB(206, 222, 242), fogEnd = 3400,
		clockTime = 12.0, ambient = Color3.fromRGB(176, 180, 190),
		hillAmp = 8, hillFreq = 0.0006, roughAmp = 0.6, roughFreq = 0.010,
		rampEvery = 520, obstacleEvery = 560, perkEvery = 380, padEvery = 600,
		gravityMult = 1.00, dragMult = 0.90, creditMult = 1, scenery = "salt",
		bandProps = { "none", "posts", "cones", "posts", "pylons", "cones", "posts", "pylons" },
	},
	mountain = {
		id = "mountain", name = "Mountain Pass", seed = 3141,
		ground = Color3.fromRGB(236, 242, 248), groundMaterial = Enum.Material.Snow,
		deepGround = Color3.fromRGB(214, 224, 236), accent = Color3.fromRGB(62, 104, 74), deepAccent = Color3.fromRGB(44, 84, 60),
		fog = Color3.fromRGB(214, 226, 240), deepFog = Color3.fromRGB(186, 202, 224), fogEnd = 1900,
		clockTime = 8.0, ambient = Color3.fromRGB(150, 162, 178),
		hillAmp = 60, hillFreq = 0.0012, roughAmp = 4.0, roughFreq = 0.008,
		rampEvery = 380, obstacleEvery = 420, perkEvery = 380, padEvery = 700,
		gravityMult = 1.00, dragMult = 1.04, creditMult = 1, scenery = "mountain",
		bandProps = { "none", "boulders", "posts", "boulders", "spires", "rubble", "spires", "ruins" },
	},
	moon = {
		id = "moon", name = "The Moon", seed = 1969,
		ground = Color3.fromRGB(150, 150, 156), groundMaterial = Enum.Material.Basalt,
		deepGround = Color3.fromRGB(116, 116, 124), accent = Color3.fromRGB(96, 96, 108), deepAccent = Color3.fromRGB(80, 80, 92),
		fog = Color3.fromRGB(18, 18, 28), deepFog = Color3.fromRGB(10, 10, 18), fogEnd = 4200,
		clockTime = 0.0, ambient = Color3.fromRGB(206, 206, 216),
		hillAmp = 34, hillFreq = 0.0010, roughAmp = 3.0, roughFreq = 0.008,
		rampEvery = 420, obstacleEvery = 460, perkEvery = 360, padEvery = 620,
		gravityMult = 0.40, dragMult = 0.70, creditMult = 1, scenery = "moon",
		bandProps = { "none", "boulders", "spires", "boulders", "spires", "rubble", "boulders", "spires" },
	},
}
-- lookups by id ("road") still find something sensible, without listing it as a track
Config.TracksById.road = Config.ZoneWorlds.backroad

-- Each checkpoint repaints the world a step further toward the track's "deep"
-- palette and adds a new prop type, so you can see the difficulty on the ground
-- rather than only reading it off the HUD.
function Config.BandFor(track, tier: number)
	local t = math.clamp(tier, 0, 7) / 7
	return {
		tier = tier,
		ground = track.ground:Lerp(track.deepGround or track.ground, t * 0.85),
		accent = track.accent:Lerp(track.deepAccent or track.accent, t * 0.9),
		fog = track.fog:Lerp(track.deepFog or track.fog, t * 0.8),
		fogEnd = track.fogEnd * (1 - t * 0.42),
		prop = (track.bandProps and track.bandProps[math.clamp(tier, 0, 7) + 1]) or "none",
		propDensity = t,
	}
end

--==============================================================
-- ECONOMY
--==============================================================
Config.Economy = {
	ComboStep = 0.10,			-- multiplier gained per chained pickup
	ComboMax = 3.00,
	ComboWindow = 6.0,			-- seconds to keep a chain alive
	StartingCredits = 0,
	-- server-side sanity limits
	MaxRunSeconds = 320,
}

--==============================================================
-- SHOP :: CHARMS
-- Consumables burned on the next launch. They change the launch itself,
-- so each one also drives its own effect on the rig during the spin-up.
--==============================================================
Config.Charms = {
	{ id = "grease", name = "Grease Pack", cost = 250,
	  desc = "Slicker bearings. +6% launch speed.",
	  fx = Color3.fromRGB(120, 220, 130), effect = { launchMult = 1.06 } },

	{ id = "fulltank", name = "Full Tank", cost = 400,
	  desc = "Start the run with half again as much boost fuel.",
	  fx = Color3.fromRGB(230, 230, 240), effect = { fuelMult = 1.5 } },

	{ id = "bearings", name = "Ceramic Bearings", cost = 600,
	  desc = "Both timing windows are 50% wider this run.",
	  fx = Color3.fromRGB(110, 190, 255), effect = { windowMult = 1.5 } },

	{ id = "shoulder", name = "Iron Shoulder", cost = 750,
	  desc = "The operator puts his back into it. +18% push-off power.",
	  fx = Color3.fromRGB(255, 150, 60), effect = { pushMult = 1.18 } },

	{ id = "nitrous", name = "Nitrous Primer", cost = 900,
	  desc = "Charged straight into the cylinder. +15% launch speed.",
	  fx = Color3.fromRGB(90, 220, 255), effect = { launchMult = 1.15 } },

	{ id = "lucky", name = "Lucky Charm", cost = 1400,
	  desc = "Rare quirks show up far more often for the whole run.",
	  fx = Color3.fromRGB(255, 205, 70), effect = { rarityBias = 0.65 } },
}
Config.CharmsById = {}
for _, c in ipairs(Config.Charms) do Config.CharmsById[c.id] = c end

--==============================================================
-- SHOP :: SKINS (permanent)
--==============================================================
Config.Skins = {
	{ id = "stock", name = "Stock Rubber", cost = 0, default = true,
	  tyre = Color3.fromRGB(26, 26, 28), rim = Color3.fromRGB(196, 200, 206),
	  material = Enum.Material.Pebble, glow = Color3.fromRGB(255, 190, 90) },

	{ id = "sand", name = "Desert Sand", cost = 1200,
	  tyre = Color3.fromRGB(180, 150, 104), rim = Color3.fromRGB(120, 104, 80),
	  material = Enum.Material.Sand, glow = Color3.fromRGB(255, 214, 140) },

	{ id = "whitewall", name = "Whitewall", cost = 2500,
	  tyre = Color3.fromRGB(232, 230, 224), rim = Color3.fromRGB(60, 60, 66),
	  material = Enum.Material.SmoothPlastic, glow = Color3.fromRGB(255, 255, 255) },

	{ id = "chrome", name = "Chrome Rim", cost = 6000,
	  tyre = Color3.fromRGB(18, 18, 20), rim = Color3.fromRGB(240, 244, 250),
	  material = Enum.Material.Metal, glow = Color3.fromRGB(200, 230, 255), reflect = 0.35 },

	{ id = "molten", name = "Molten", cost = 18000,
	  tyre = Color3.fromRGB(70, 22, 12), rim = Color3.fromRGB(255, 120, 40),
	  material = Enum.Material.Neon, glow = Color3.fromRGB(255, 110, 40) },

	{ id = "void", name = "Void", cost = 60000,
	  tyre = Color3.fromRGB(24, 16, 44), rim = Color3.fromRGB(170, 110, 255),
	  material = Enum.Material.Neon, glow = Color3.fromRGB(170, 110, 255) },

	-- Robux-only. Set devProductId from the Creator Dashboard to switch them on.
	{ id = "goldleaf", name = "Gold Leaf", cost = 0, robux = 149, devProductId = 0,
	  tyre = Color3.fromRGB(60, 48, 18), rim = Color3.fromRGB(255, 208, 80),
	  material = Enum.Material.Metal, glow = Color3.fromRGB(255, 200, 90), reflect = 0.45 },

	{ id = "circuit", name = "Circuit Board", cost = 0, robux = 199, devProductId = 0,
	  tyre = Color3.fromRGB(18, 58, 44), rim = Color3.fromRGB(120, 255, 190),
	  material = Enum.Material.Neon, glow = Color3.fromRGB(120, 255, 190) },

	{ id = "magma", name = "Magma Core", cost = 0, robux = 249, devProductId = 0,
	  tyre = Color3.fromRGB(30, 12, 8), rim = Color3.fromRGB(255, 90, 30),
	  material = Enum.Material.Neon, glow = Color3.fromRGB(255, 70, 20) },

	{ id = "glacier", name = "Glacier", cost = 0, robux = 299, devProductId = 0,
	  tyre = Color3.fromRGB(180, 226, 244), rim = Color3.fromRGB(240, 252, 255),
	  material = Enum.Material.Glass, glow = Color3.fromRGB(190, 235, 255), reflect = 0.3 },
}
Config.SkinsById = {}
for _, s in ipairs(Config.Skins) do Config.SkinsById[s.id] = s end

--==============================================================
-- SHOP :: AIRTIME TRAILS
-- Off by default. These only fire while the tyre is off the ground, so the
-- trail is a readout of how much air you are actually getting.
-- The first one is priced at roughly three early runs.
--==============================================================
Config.Trails = {
	{ id = "none", name = "No Trail", cost = 0, default = true,
	  desc = "Nothing behind you but dust." },

	{ id = "dust", name = "Dust Devil", cost = 2000,
	  desc = "A dry plume that hangs in the air behind a long jump.",
	  a = Color3.fromRGB(224, 200, 152), b = Color3.fromRGB(150, 122, 80),
	  width = 5, life = 0.55, glow = 0 },

	{ id = "ember", name = "Ember", cost = 4500,
	  desc = "Sparks off the tread, like the rubber is about to give.",
	  a = Color3.fromRGB(255, 174, 60), b = Color3.fromRGB(200, 40, 20),
	  width = 4.5, life = 0.7, glow = 0.6, sparks = true },

	{ id = "ion", name = "Ion Wake", cost = 9000,
	  desc = "A clean blue ribbon that reads your exact arc.",
	  a = Color3.fromRGB(140, 226, 255), b = Color3.fromRGB(40, 90, 220),
	  width = 5.5, life = 0.9, glow = 0.7 },

	{ id = "aurora", name = "Aurora", cost = 20000,
	  desc = "Shifting green and violet. Best seen from a very long way up.",
	  a = Color3.fromRGB(120, 255, 190), b = Color3.fromRGB(150, 90, 255),
	  width = 7, life = 1.15, glow = 0.8 },

	{ id = "prism", name = "Prism", cost = 45000,
	  desc = "Splits into a full spectrum the longer you stay airborne.",
	  a = Color3.fromRGB(255, 120, 200), b = Color3.fromRGB(120, 220, 255),
	  width = 8, life = 1.3, glow = 0.85, rainbow = true, sparks = true },

	{ id = "comet", name = "Comet", cost = 0, robux = 179, devProductId = 0,
	  desc = "A hard white core with a burning tail.",
	  a = Color3.fromRGB(255, 255, 255), b = Color3.fromRGB(255, 160, 40),
	  width = 8.5, life = 1.4, glow = 0.9, sparks = true },
}
Config.TrailsById = {}
for _, t in ipairs(Config.Trails) do Config.TrailsById[t.id] = t end

--==============================================================
-- SHOP :: CREDIT PACKS (Robux)
-- devProductId 0 means "not set up yet". Create the developer products in
-- the Creator Dashboard and paste their ids here; the shop wires itself up.
--==============================================================
Config.CreditPacks = {
	{ id = "pack_small",  name = "Handful",   credits = 1000,   robux = 25,  devProductId = 0 },
	{ id = "pack_med",    name = "Toolbox",   credits = 6000,   robux = 99,  devProductId = 0, tag = "POPULAR" },
	{ id = "pack_large",  name = "Crate",     credits = 30000,  robux = 399, devProductId = 0 },
	{ id = "pack_huge",   name = "Truckload", credits = 120000, robux = 999, devProductId = 0, tag = "BEST VALUE" },
}
Config.PacksByProductId = {}
for _, p in ipairs(Config.CreditPacks) do
	if p.devProductId ~= 0 then Config.PacksByProductId[p.devProductId] = p end
end

--==============================================================
-- RIMS
-- Split out of the tyre so the wheel reads as two parts, the way a real one
-- does. Rims are their own cosmetic slot.
--==============================================================
Config.Rims = {
	{ id = "steel", name = "Steel Stock", cost = 0, default = true,
	  face = Color3.fromRGB(176, 180, 188), barrel = Color3.fromRGB(120, 124, 130),
	  spokes = 6, style = "solid", desc = "What it came with." },

	{ id = "fivespoke", name = "Five Spoke", cost = 1800,
	  face = Color3.fromRGB(206, 210, 218), barrel = Color3.fromRGB(140, 144, 150),
	  spokes = 5, style = "spoke", desc = "Clean cast alloy. Light and honest." },

	{ id = "deepdish", name = "Deep Dish", cost = 4200,
	  face = Color3.fromRGB(58, 60, 66), barrel = Color3.fromRGB(196, 160, 62),
	  spokes = 8, style = "dish", desc = "Gold barrel, black face. Loud on purpose." },

	{ id = "mesh", name = "Mesh", cost = 9500,
	  face = Color3.fromRGB(150, 154, 162), barrel = Color3.fromRGB(96, 100, 108),
	  spokes = 10, style = "mesh", desc = "Ten thin spokes. Looks fast standing still." },

	{ id = "chrome", name = "Polished Chrome", cost = 26000,
	  face = Color3.fromRGB(242, 246, 252), barrel = Color3.fromRGB(220, 226, 234),
	  spokes = 6, style = "spoke", reflect = 0.5, desc = "Mirror finish. Shows every bit of dust." },

	-- prestige and token rewards, never buyable with credits
	{ id = "neonblue", name = "Neon Halo", cost = 0, locked = true,
	  face = Color3.fromRGB(30, 36, 52), barrel = Color3.fromRGB(70, 190, 255),
	  spokes = 6, style = "spoke", glow = Color3.fromRGB(70, 190, 255), neon = true,
	  desc = "Blue neon burning around the lip. Prestige 1." },

	{ id = "moltengold", name = "Molten Gold", cost = 0, locked = true,
	  face = Color3.fromRGB(70, 44, 10), barrel = Color3.fromRGB(255, 190, 60),
	  spokes = 5, style = "dish", glow = Color3.fromRGB(255, 170, 40), neon = true,
	  desc = "Poured, not cast. Prestige 5." },

	{ id = "voidchrome", name = "Void Chrome", cost = 0, locked = true,
	  face = Color3.fromRGB(22, 16, 38), barrel = Color3.fromRGB(180, 120, 255),
	  spokes = 10, style = "mesh", glow = Color3.fromRGB(170, 110, 255), neon = true,
	  desc = "Prestige 8." },

	{ id = "tokenchrome", name = "Token Alloy", cost = 0, locked = true,
	  face = Color3.fromRGB(240, 214, 130), barrel = Color3.fromRGB(150, 118, 40),
	  spokes = 8, style = "dish", reflect = 0.4,
	  desc = "Only ever bought with prestige tokens." },
}
Config.RimsById = {}
for _, r in ipairs(Config.Rims) do Config.RimsById[r.id] = r end

--==============================================================
-- GENERATORS
-- A real upgrade path, not just a repaint. Each tier changes the launch
-- numbers and the silhouette of the machine on your plot.
--==============================================================
Config.Generators = {
	{ id = "field", name = "Field Diesel", cost = 0, default = true, tier = 1,
	  desc = "The single-cylinder workhorse everybody starts on.",
	  body = Color3.fromRGB(24, 122, 92), trim = Color3.fromRGB(206, 176, 62),
	  flywheel = Color3.fromRGB(28, 28, 30),
	  effect = { launchMult = 1.00, windowMult = 1.00, ceilingAdd = 0.00, fuelAdd = 0 } },

	{ id = "twin", name = "Twin Cylinder", cost = 25000, tier = 2,
	  desc = "Two pots instead of one. Smoother wind-up, wider release window.",
	  body = Color3.fromRGB(30, 96, 140), trim = Color3.fromRGB(216, 196, 96),
	  flywheel = Color3.fromRGB(34, 34, 38),
	  effect = { launchMult = 1.08, windowMult = 1.20, ceilingAdd = 0.02, fuelAdd = 10 } },

	{ id = "turbo", name = "Turbo Diesel", cost = 120000, tier = 3,
	  desc = "Forced induction. It hurts to stand next to.",
	  body = Color3.fromRGB(150, 60, 34), trim = Color3.fromRGB(240, 160, 60),
	  flywheel = Color3.fromRGB(44, 40, 38),
	  effect = { launchMult = 1.18, windowMult = 1.30, ceilingAdd = 0.05, fuelAdd = 25 } },

	{ id = "genset", name = "Industrial Genset", cost = 500000, tier = 4,
	  desc = "Skid-mounted plant. Somebody clearly stole this.",
	  body = Color3.fromRGB(78, 82, 92), trim = Color3.fromRGB(120, 200, 255),
	  flywheel = Color3.fromRGB(58, 62, 70),
	  effect = { launchMult = 1.30, windowMult = 1.42, ceilingAdd = 0.09, fuelAdd = 45 } },

	{ id = "fusion", name = "Fusion Coil", cost = 2500000, tier = 5,
	  desc = "Not a diesel at all any more. Nobody asks questions.",
	  body = Color3.fromRGB(36, 44, 72), trim = Color3.fromRGB(140, 240, 255),
	  flywheel = Color3.fromRGB(90, 200, 255), neon = true,
	  effect = { launchMult = 1.45, windowMult = 1.55, ceilingAdd = 0.14, fuelAdd = 70 } },
}
Config.GeneratorsById = {}
for _, g in ipairs(Config.Generators) do Config.GeneratorsById[g.id] = g end

--==============================================================
-- RIG FINISHES (pure cosmetic paint over whatever generator you own)
--==============================================================
Config.RigSkins = {
	{ id = "works", name = "Works Paint", cost = 0, default = true, tintStrength = 0,
	  desc = "Factory colours." },
	{ id = "hazard", name = "Hazard Orange", cost = 3500, tint = Color3.fromRGB(240, 140, 40), tintStrength = 0.75,
	  desc = "High-vis. Nobody is going to trip over this." },
	{ id = "arctic", name = "Arctic White", cost = 8000, tint = Color3.fromRGB(236, 240, 244), tintStrength = 0.8,
	  desc = "Spotless, briefly." },
	{ id = "steelfin", name = "Brushed Steel", cost = 0, locked = true, tint = Color3.fromRGB(186, 192, 200), tintStrength = 0.85,
	  metal = true, desc = "Prestige 2." },
	{ id = "carbon", name = "Carbon", cost = 0, locked = true, tint = Color3.fromRGB(40, 42, 48), tintStrength = 0.9,
	  desc = "Prestige 6." },
	{ id = "royal", name = "Prestige Royal", cost = 0, locked = true, tint = Color3.fromRGB(96, 60, 180), tintStrength = 0.85,
	  glow = true, desc = "Prestige 10." },
}
Config.RigSkinsById = {}
for _, r in ipairs(Config.RigSkins) do Config.RigSkinsById[r.id] = r end

--==============================================================
-- TOOLBOXES
-- Found out on the road, not bought. Three shapes, five rarities, and the
-- good ones only turn up deep into a run.
--==============================================================
Config.ToolboxKinds = {
	{ id = "drum",   name = "Fuel Drum",    stat = "boostMult",    label = "boost power" },
	{ id = "trophy", name = "Trophy Case",  stat = "creditMult",   label = "credits earned" },
	{ id = "stake",  name = "Survey Stake", stat = "distanceMult", label = "distance scored" },
}
Config.ToolboxKindsById = {}
for _, k in ipairs(Config.ToolboxKinds) do Config.ToolboxKindsById[k.id] = k end

-- minTier is the checkpoint you must have crossed for one to appear at all;
-- weight is how likely it is once you are deep enough.
Config.ToolboxRarities = {
	{ id = "common",    name = "Common",    minTier = 0, weight = 100, bonus = 0.04,
	  color = Color3.fromRGB(206, 210, 218), glow = 0 },
	{ id = "uncommon",  name = "Uncommon",  minTier = 1, weight = 46,  bonus = 0.09,
	  color = Color3.fromRGB(96, 216, 128),  glow = 0.4 },
	{ id = "rare",      name = "Rare",      minTier = 3, weight = 18,  bonus = 0.17,
	  color = Color3.fromRGB(86, 168, 255),  glow = 0.7 },
	{ id = "epic",      name = "Epic",      minTier = 5, weight = 6,   bonus = 0.30,
	  color = Color3.fromRGB(186, 120, 255), glow = 1 },
	{ id = "legendary", name = "Legendary", minTier = 6, weight = 1.2, bonus = 0.55,
	  color = Color3.fromRGB(255, 190, 60),  glow = 1 },
}
Config.ToolboxRaritiesById = {}
for _, r in ipairs(Config.ToolboxRarities) do Config.ToolboxRaritiesById[r.id] = r end

Config.Toolbox = {
	SpawnEvery = math.huge,		-- off: v2 has no toolboxes (was 5200 studs between candidate spawns)
	Slots = 3,					-- plinths on your plot
	LegendaryTier6Scale = 0.18,	-- legendary is throttled at 6 and opens up at 7
}

--==============================================================
-- PRESTIGE
--==============================================================
Config.Prestige = {
	BaseCost = 750000,
	Growth = 1.55,				-- cost(n) = BaseCost * Growth^n
	MaxLevel = 25,
	KeepsCodex = false,			-- flip to true if wiping the quirk log feels harsh

	-- one item per prestige. Anything granted here is permanent for good.
	Rewards = {
		{ kind = "rim",   id = "neonblue",   note = "Neon Halo rims" },
		{ kind = "rig",   id = "steelfin",   note = "Brushed Steel rig" },
		{ kind = "trail", id = "aurora",     note = "Aurora trail" },
		{ kind = "skin",  id = "void",       note = "Void tyre" },
		{ kind = "rim",   id = "moltengold", note = "Molten Gold rims" },
		{ kind = "rig",   id = "carbon",     note = "Carbon rig" },
		{ kind = "skin",  id = "molten",     note = "Molten tyre" },
		{ kind = "rim",   id = "voidchrome", note = "Void Chrome rims" },
		{ kind = "trail", id = "prism",      note = "Prism trail" },
		{ kind = "rig",   id = "royal",      note = "Prestige Royal rig" },
	},
}

function Config.PrestigeCost(level: number): number
	return math.floor(Config.Prestige.BaseCost * (Config.Prestige.Growth ^ math.max(0, level)))
end

function Config.PrestigeReward(level: number)
	local r = Config.Prestige.Rewards
	if #r == 0 then return nil end
	return r[((level - 1) % #r) + 1]
end

--==============================================================
-- PRESTIGE TOKEN SHOP
-- Tokens are the only way to buy any of this, and none of it is ever lost.
--==============================================================
Config.TokenShop = {
	{ id = "tk_credits", name = "Ledger Training", cost = 1, max = 5,
	  desc = "+6% credits from every run, permanently. Stacks five times.",
	  effect = { creditMult = 0.06 } },

	{ id = "tk_launch", name = "Machinist's Eye", cost = 1, max = 5,
	  desc = "+5% launch speed, permanently. Stacks five times.",
	  effect = { launchMult = 0.05 } },

	{ id = "tk_slot", name = "Wider Loom", cost = 2, max = 2,
	  desc = "One more quirk slot on every run. Survives prestige.",
	  effect = { perkSlots = 1 } },

	{ id = "tk_charm", name = "Lucky Pocket", cost = 2, max = 1,
	  desc = "Start every run with a free random common charm armed.",
	  effect = { freeCharm = 1 } },

	{ id = "tk_toolbox", name = "Scrap Sense", cost = 2, max = 3,
	  desc = "Toolboxes turn up 25% more often out on the road.",
	  effect = { toolboxRate = 0.25 } },

	{ id = "tk_track", name = "Standing Permit", cost = 3, max = 1,
	  desc = "Keep every track you have unlocked when you prestige.",
	  effect = { keepTracks = 1 } },

	{ id = "tk_rim", name = "Token Alloy Rims", cost = 2, max = 1,
	  desc = "An alloy you cannot get any other way.",
	  grant = { kind = "rim", id = "tokenchrome" } },
}
Config.TokenShopById = {}
for _, t in ipairs(Config.TokenShop) do Config.TokenShopById[t.id] = t end

--==============================================================
-- SPECTATORS
--==============================================================
Config.Spectator = {
	PerViewer = 0.07,			-- +7% credits per person watching
	MaxBonus = 0.50,			-- capped so a full server is not a jackpot
	Range = 3200,				-- how far a nameplate stays clickable
}

-- Every Robux purchase in the game, keyed by developer product id, so one
-- ProcessReceipt handler covers credit packs, skins and trails alike.
Config.ProductsById = {}
for _, p in ipairs(Config.CreditPacks) do
	if p.devProductId ~= 0 then
		Config.ProductsById[p.devProductId] = { kind = "pack", id = p.id, credits = p.credits, name = p.name }
	end
end
for _, s in ipairs(Config.Skins) do
	if (s.devProductId or 0) ~= 0 then
		Config.ProductsById[s.devProductId] = { kind = "skin", id = s.id, name = s.name }
	end
end
for _, t in ipairs(Config.Trails) do
	if (t.devProductId or 0) ~= 0 then
		Config.ProductsById[t.devProductId] = { kind = "trail", id = t.id, name = t.name }
	end
end

--==============================================================
-- BUILD
--==============================================================
Config.VersionLabel = "ALPHA 0.2"

-- the TYRE logo (transparent PNG, 729 x 396)
Config.Brand = {
	Logo = "rbxassetid://77980337593031",
	LogoAspect = 729 / 396,
	-- resampled copies for smaller spots: never show an image above its own pixel size
	Logo360 = "rbxassetid://70863711421275",
	Logo200 = "rbxassetid://122557972179647",
}

--==============================================================
-- TYRE PRESSURE
-- Set on the workbench and applied to every launch.
-- 0 = soft: grips and steers, soaks up bounces. 100 = hard: flies, drifts.
--==============================================================
Config.Pressure = {
	Default = 50,
	Bounce = { 0.84, 1.20 },
	Grip   = { 1.28, 0.80 },
	Roll   = { 1.12, 0.88 },
}

function Config.PressureMods(p: number?)
	local t = math.clamp((tonumber(p) or Config.Pressure.Default) / 100, 0, 1)
	local P = Config.Pressure
	return {
		bounce = P.Bounce[1] + (P.Bounce[2] - P.Bounce[1]) * t,
		grip = P.Grip[1] + (P.Grip[2] - P.Grip[1]) * t,
		roll = P.Roll[1] + (P.Roll[2] - P.Roll[1]) * t,
	}
end

--==============================================================
-- REDLINE HEAT
-- Boost heats the casing. Past the redline boost shoves harder, but let the
-- gauge hit the top and the tyre blows out and the run is over.
--==============================================================
Config.Heat = {
	Max = 100,
	Blowout = 100,
}

--==============================================================
-- THE ROLLING RUN (RunPhysics, RunSim)
-- You launch out of the cannon, land and roll. On the ground gravity along the slope is the engine:
-- down a hill it pulls you harder than the same hill holds you back going up, so a road of hills
-- carries you on and how well you take them is how far you go. Crests throw you into the air; in
-- the air it's an arc you can flare or dive. Nitro (a tank) adds thrust. tools/run_test.py flies
-- this against the real terrain with three kinds of driver, so change numbers there first.
--==============================================================
-- the run's camera (RunCamera): tools/camera_test.py flies it against real runs
Config.Camera = {
	SpeedRef = 700,           -- the speed that counts as "full speed" for the speed terms
	Dist0 = 40,               -- studs behind the tyre at rest...
	DistSpeed = 22,           -- ...plus this at full speed...
	DistAlt = 0.34,           -- ...plus this per stud of height above the road...
	DistAltMax = 110,         -- ...up to this...
	DistAir = 6,              -- ...and a little more while airborne
	DistStiff = 22,           -- the distance spring
	DistDamp = 7.5,
	Height0 = 8,              -- camera height over the tyre, and
	HeightPer = 0.2,          -- more per stud of distance
	Side = 11,                -- the camera sits this far to the right of the tyre's line, looking down it: an angled view
	Clear = 5,                -- the sight line to the tyre clears every crest by this
	LosIgnore = 10,           -- road this close behind the tyre never counts as in the way
	RiseMax = 90,             -- the camera never needs to climb more than this over the tyre
	Floor = 3,                -- never nearer the road under the camera than this
	EyeUp = 16,               -- how fast the camera rises over a crest...
	EyeDown = 3.2,            -- ...and how slowly it settles back
	EyeSlack = 6,
	YawFollow = 7,            -- turning with the tyre, on the ground...
	YawFollowAir = 3.5,       -- ...and in the air
	PitchShare = 0.55,
	PitchFollow = 4,
	Look0 = 44,               -- looks this far ahead along the heading
	LookSpeed = 80,           -- more at speed
	LookRoad = 0.65,          -- how much of what it looks at is the road ahead (not the tyre's own height)
	LookRoadAir = 0.3,
	LookPath = 0.5,
	LookLift = 0.02,
	LookFollow = 5,
	Fov0 = 66,
	FovSpeed = 18,
	FovAlt = 0.05,
	FovAltMax = 14,
	FovBoost = 7,
	FovMax = 98,
	FovFollow = 6,
	FirstFov = 14,
	Roll = 0.55,
	RollFollow = 6,
}

-- the rolling hills the road is built from (TrackGen:rollerHeight)
Config.Roller = {
	Start = 120,              -- studs: flat before this
	Amp0 = 34,                -- hill height at the start...
	AmpGrow = 0.0045,         -- ...growing by this per stud...
	AmpMax = 95,              -- ...up to this
	Wave1 = 560,              -- the long wave, studs crest to crest
	Wave2 = 330,              -- the short one that rides on it
	Second = 0.3,             -- how much of it
	Swell = 800,              -- how fast the big hills grow and shrink
}

Config.Run = {
	SmashKeep = 0.96,         -- forward speed kept rolling through a smashable
	TurnCost = 0.15,          -- share of speed lost per radian of turning: weaving costs energy
	FatigueStart = 55,        -- seconds into a run after which the air gets thicker...
	FatigueRate = 0.035,      -- ...by this share of the drag more every second (no run is endless)
	Drag0 = 0.05,             -- air drag: decel = s * (Drag0 + s * Drag1)
	Drag1 = 1 / 9500,
	TuckDrag = 0.5,           -- drag while tucked (S / Shift / the TUCK button)
	TuckTurn = 0.55,          -- turning while tucked
	TurnRate = 1.7,           -- rad/s of yaw at full input, at low speed
	TurnFall = 650,           -- the speed at which turning is cut by a third
	YawLimit = math.rad(70),  -- either side of straight down the road
	NitroThrust = 200,        -- studs/s^2 while held, at full power
	NitroDrain = 30,          -- units a second
	NitroStart = 0.6,         -- the tank you launch with, as a share
	KickFade = 420,           -- a pad's kick fades to a fifth of itself by the time you're this fast (no runaway)
	TargetKick = 110,         -- off a target's top, down to a glance
	SkimHeight = 18,          -- close to the ground for a skim
	SkimSpeed = 180,          -- ... at least this fast
	SkimEvery = 0.6,          -- seconds of skimming per tick
	SkimNitro = 6,
	Gravity = 118,            -- studs/s^2, in the air
	HillDown = 1.5,           -- on the ground, how much of gravity pulls you down a slope...
	HillUp = 0.4,             -- ...and how much of it holds you back up one: the gap is what the hills give
	TakeoffMin = 55,          -- slower than this the tyre hugs the ground over a crest
	SoftImpact = 105,         -- landing speed into the slope under this: it just rolls on
	HardImpact = 230,         -- over this: it kicks back up and the chain breaks
	BraceSoft = 2.2,          -- tucked as it touches down (braced): this many times the impact still rolls on...
	BraceHard = 1.8,          -- ...and this many times before it kicks back up
	BraceCue = 0.55,          -- seconds before touchdown the HUD says TUCK to land
	SmoothHang = 0.8,         -- a landing after this long in the air that comes down soft is a link
	LandNitro = 8,
	AirTurn = 0.45,           -- steering in the air, against the ground
	FlareLift = 0.42,         -- nose up in the air: this much less gravity...
	FlareDrag = 0.7,          -- ...for this much more drag
	DiveGrav = 0.55,          -- nose down: this much more gravity
	TuckRoll = 0.55,          -- tucked on the ground: this much of the rolling friction
	TuckWindow = 1.6,         -- a tuck works this many seconds, then the legs cramp...
	TuckCool = 0.8,           -- ...and it's dead this long
	TuckEarly = 0.2,          -- letting go early only costs this
	TuckBuffer = 0.2,         -- a press this long before the tuck is ready again still counts
	PerfectLook = 65,         -- a PERFECT tuck: pressed as the road drops away within this many studs...
	PerfectTime = 0.9,        -- ...or this many seconds at your speed, whichever is further...
	PerfectFlat = -0.04,      -- ...(flat or rising where you are: a slope above this)...
	PerfectDrop = -0.14,      -- ...and falling steeper than this ahead
	PerfectGrace = 0.18,      -- the chance stays open this long after the drop is passed
	PerfectKick = 34,         -- studs/s it adds (times the stage), fed in over PerfectKickTime
	PerfectKickTime = 0.4,
	GroundFriction0 = 3,      -- rolling: decel = Friction0 + s * Friction1
	GroundFriction1 = 0.04,
	Targets = false,          -- the old bounce targets (a ring painted on a bale): off for now
	HardKeep = 0.55,          -- speed kept on the hardest landing
	MinSpeed = 28,            -- rolling slower than this the run ends
	StopGrace = 0.8,
	ChainDecay = 4.6,         -- seconds with nothing before the chain drops
	ComboStep = 0.15,         -- cash multiplier per link
	ComboMax = 8,
	MouseSens = 0.0032,       -- radians per pixel
	KeyRate = 1.5,            -- rad/s of aim on the keys
	CorridorSoft = 175,       -- studs from the centreline the wind starts pushing you back
}

--==============================================================
-- THE STORE (v3): gamepasses and developer products. Make each on the Creator Dashboard, then
-- paste its id here: an id of 0 shows the item greyed out as "soon" and never opens a prompt.
--==============================================================
Config.Store = {
	Passes = {
		{ id = "cash2", name = "2x Cash", text = "Every run, crate and auto-cannon shot pays double", passId = 0, robux = 199, icon = "cash" },
		{ id = "autolaunch", name = "Auto Launch", text = "Launch hands-free: every shift taken for you", passId = 0, robux = 249, icon = "cannon" },
		{ id = "spares2", name = "+2 Spare Slots", text = "Two more tyres multiply your cash", passId = 0, robux = 149, icon = "rack" },
		{ id = "lucky", name = "Lucky Crates", text = "Rarer tyres and mutations, every crate", passId = 0, robux = 299, icon = "crates" },
		{ id = "vip", name = "VIP", text = "+10% cash, a gold name tag and a VIP chat tag", passId = 0, robux = 399, icon = "crest" },
	},
	Products = {
		{ id = "keys5", name = "5 Keys", keys = 5, productId = 0, robux = 49, icon = "key" },
		{ id = "keys15", name = "15 Keys", keys = 15, productId = 0, robux = 129, icon = "key" },
		{ id = "keys40", name = "40 Keys", keys = 40, productId = 0, robux = 299, icon = "key" },
		{ id = "serverluck", name = "Server Luck", text = "30 minutes of double luck for everyone in the server", minutes = 30, productId = 0, robux = 99, icon = "crates" },
	},
}
Config.StorePassesById, Config.StoreProductsById, Config.StoreByProductId, Config.StoreByPassId = {}, {}, {}, {}
for _, p in ipairs(Config.Store.Passes) do
	Config.StorePassesById[p.id] = p
	if p.passId ~= 0 then Config.StoreByPassId[p.passId] = p end
end
for _, p in ipairs(Config.Store.Products) do
	Config.StoreProductsById[p.id] = p
	if p.productId ~= 0 then Config.StoreByProductId[p.productId] = p end
end

Config.Physics.SmashSpeed = 900
Config.Economy.CreditsPerSmash = 15

-- speed thresholds for the wind effect (studs/s)
Config.Wind = { Tiers = { 300, 600, 900, 1200 } }

--==============================================================
-- CHECKPOINT DRAFT
--==============================================================
Config.Draft = { Choices = 3, Seconds = 6, SlowMo = 0.06, DepthBoost = 1.6 }

--==============================================================
-- METALS: found on the road, deeper = rarer
--==============================================================
Config.Metals = {
	{ id = "bronze", name = "Bronze", fromTier = 1, chance = 0.45, amount = 2, color = Color3.fromRGB(205, 128, 70) },
	{ id = "silver", name = "Silver", fromTier = 3, chance = 0.24, amount = 1, color = Color3.fromRGB(196, 206, 218) },
	{ id = "gold",   name = "Gold",   fromTier = 6, chance = 0.20, amount = 1, color = Color3.fromRGB(246, 196, 64) },
}
Config.MetalsById = {}
for _, m in ipairs(Config.Metals) do Config.MetalsById[m.id] = m end

--==============================================================
-- BOOSTERS: bought with metals
--==============================================================
Config.Boosters = {
	{ id = "chai", name = "Masala Chai", kind = "timed", seconds = 600, cost = { bronze = 30 },
	  desc = "+25% credits for 10 minutes of play.", effect = { creditMult = 1.25 },
	  color = Color3.fromRGB(214, 150, 84) },
	{ id = "grease", name = "Grease Gun", kind = "charges", charges = 5, cost = { bronze = 20, silver = 2 },
	  desc = "Both launch windows 25% wider for 5 launches.", effect = { windowMult = 1.25 },
	  color = Color3.fromRGB(120, 220, 130) },
	{ id = "octane", name = "Octane Additive", kind = "charges", charges = 5, cost = { silver = 10 },
	  desc = "+10% launch speed for 5 launches.", effect = { launchMult = 1.10 },
	  color = Color3.fromRGB(96, 200, 255) },
	{ id = "nimbu", name = "Nimbu-Mirchi", kind = "timed", seconds = 900, cost = { gold = 4 },
	  desc = "Lemon and chillies on the bumper. Rare quirks turn up far more for 15 minutes.",
	  effect = { rarityBias = 0.5 }, color = Color3.fromRGB(236, 220, 70) },
}
Config.BoostersById = {}
for _, b in ipairs(Config.Boosters) do Config.BoostersById[b.id] = b end

--==============================================================
-- DAILY STREAK (7-day cycle)
--==============================================================
Config.Daily = {
	{ credits = 300, bronze = 10 },
	{ bronze = 25 },
	{ silver = 4 },
	{ credits = 1500, bronze = 15 },
	{ silver = 8 },
	{ gold = 2 },
	{ credits = 4000, silver = 6, gold = 4 },
}

Config.Contracts = { PerDay = 3 }

--==============================================================
-- COSMETIC RARITY, by price band for now
--==============================================================
Config.CosmeticBands = {
	{ max = 999, tier = "Common" },
	{ max = 4999, tier = "Uncommon" },
	{ max = 14999, tier = "Rare" },
	{ max = 49999, tier = "Epic" },
	{ max = math.huge, tier = "Legendary" },
}
Config.PremiumColor = Color3.fromRGB(255, 96, 176)

function Config.CosmeticTier(item): string
	if not item then return "Common" end
	if item.robux then return "Premium" end
	if item.locked then return "Legendary" end
	local cost = item.cost or 0
	for _, b in ipairs(Config.CosmeticBands) do
		if cost <= b.max then return b.tier end
	end
	return "Legendary"
end

function Config.TierColor(tier: string): Color3
	if tier == "Premium" then return Config.PremiumColor end
	local r = Config.Rarity[tier]
	return r and r.color or Color3.new(1, 1, 1)
end

--==============================================================
-- STICKERS
-- The catalogue is whatever sits in Assets.Props.StickerPack. Each sticker
-- is saved as where it sits on the tyre, not a world position.
--==============================================================
Config.Stickers = {
	MaxPerTyre = 8,
	Grid = 16,			-- samples per side when wrapping a sticker onto the tyre
	Lift = 0.006,		-- how far it floats off the surface
	MinScale = 0.4,
	MaxScale = 2.2,
}

--==============================================================
-- RETREAD: three toolboxes of one rarity forged into the next
--==============================================================
Config.Forge = {
	Inputs = 3,
	Strikes = 3,
	QualityMin = 0.85,
	QualityMax = 1.25,
	SweepSeconds = 0.9,
	SweetWidth = 0.10,
}

--==============================================================
-- TITLES
-- Doing things unlocks the right to buy a title; prestige tokens buy it.
-- Mythic titles are live: hold the rank or lose the title.
--==============================================================
Config.TitleTiers = {
	Common    = { order = 1, cost = 1, style = "solid",    colors = { Color3.fromRGB(226, 232, 240) } },
	Uncommon  = { order = 2, cost = 1, style = "solid",    colors = { Color3.fromRGB(92, 224, 138) }, stroke = true },
	Rare      = { order = 3, cost = 2, style = "gradient", colors = { Color3.fromRGB(96, 165, 250), Color3.fromRGB(165, 243, 252) } },
	Epic      = { order = 4, cost = 3, style = "flow",     colors = { Color3.fromRGB(192, 132, 252), Color3.fromRGB(240, 171, 252), Color3.fromRGB(129, 140, 248) } },
	Legendary = { order = 5, cost = 4, style = "cycle",    colors = { Color3.fromRGB(255, 95, 109), Color3.fromRGB(251, 191, 36), Color3.fromRGB(74, 222, 128), Color3.fromRGB(96, 165, 250), Color3.fromRGB(192, 132, 252) } },
	Mythic    = { order = 6, cost = 0, style = "shine",    colors = { Color3.fromRGB(251, 191, 36), Color3.fromRGB(255, 244, 199), Color3.fromRGB(183, 121, 31) } },
}
Config.TitleTierOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

local M = 1 / Config.Physics.StudsToMetres
Config.Titles = {
	{ id = "regular",    name = "Backroad Regular", tier = "Common",    cond = { stat = "runs", goal = 25 } },
	{ id = "hothands",   name = "Hot Hands",        tier = "Common",    cond = { stat = "redlineSeconds", goal = 120 } },
	{ id = "grease",     name = "Grease Monkey",    tier = "Common",    cond = { stat = "upgrades", goal = 20 } },
	{ id = "goat",       name = "Goat Whisperer",   tier = "Uncommon",  cond = { stat = "trackBest", track = "backroad", goal = math.ceil(5000 * M) } },
	{ id = "lane",       name = "Lane Splitter",    tier = "Uncommon",  cond = { stat = "trackBest", track = "highway", goal = math.ceil(5000 * M) } },
	{ id = "dunerat",    name = "Dune Rat",         tier = "Uncommon",  cond = { stat = "trackBest", track = "dunes", goal = math.ceil(5000 * M) } },
	{ id = "scrap",      name = "Scrap Collector",  tier = "Uncommon",  cond = { stat = "bronze", goal = 500 } },
	{ id = "flawless",   name = "Flawless",         tier = "Rare",      cond = { stat = "flawless", goal = 10 } },
	{ id = "coolhead",   name = "Cool Head",        tier = "Rare",      cond = { stat = "cleanRuns", goal = 10 } },
	{ id = "wrecking",   name = "Wrecking Ball",    tier = "Rare",      cond = { stat = "smashes", goal = 100 } },
	{ id = "contractor", name = "Contractor",       tier = "Rare",      cond = { stat = "contracts", goal = 25 } },
	{ id = "deepend",    name = "The Deep End",     tier = "Epic",      cond = { stat = "maxTier", goal = 7 } },
	{ id = "hangtime",   name = "Hang Time",        tier = "Epic",      cond = { stat = "longestAir", goal = 12 } },
	{ id = "crowd",      name = "Crowd Pleaser",    tier = "Epic",      cond = { stat = "bestSpectators", goal = 5 } },
	{ id = "goldrush",   name = "Gold Rush",        tier = "Epic",      cond = { stat = "gold", goal = 100 } },
	{ id = "codex",      name = "Codex Complete",   tier = "Legendary", cond = { stat = "codexMax", goal = #Config.Perks } },
	{ id = "ironcasing", name = "Iron Casing",      tier = "Legendary", cond = { stat = "prestige", goal = 5 } },
	{ id = "retreader",  name = "Master Retreader", tier = "Legendary", cond = { stat = "forgedLegendary", goal = 1 } },
	{ id = "record",     name = "Longest on Record", tier = "Mythic",   live = { board = "distance", rank = 3 } },
	{ id = "spender",    name = "Big Spender",      tier = "Mythic",    live = { board = "robux", rank = 3 } },
	{ id = "richest",    name = "Richest Here",     tier = "Mythic",    live = { board = "richest", rank = 1 } },
}
Config.TitlesById = {}
for _, t in ipairs(Config.Titles) do Config.TitlesById[t.id] = t end

Config.Prestige.TokensFor = function(newLevel: number): number
	return 2 + math.floor(newLevel / 5)
end

-- Character animations. Paste an uploaded animation id ("rbxassetid://123")
-- into any slot and it replaces the default the next time a character spawns.
-- Uploads must belong to whoever owns the game (you or the group), and match
-- the avatar rig type (the current sprint is R6).
Config.Animations = {
	idle = "rbxassetid://110618648268733",
	idle2 = "rbxassetid://79213512467320",		-- checks his watch
	walk = "rbxassetid://77529904423883",		-- authored brisk
	run = "rbxassetid://84956216951852",
	jump = "rbxassetid://80770955787499",		-- the crouch and lift-off
	jumpFall = "rbxassetid://116637025732047",	-- coming down after a jump
	fall = "rbxassetid://137963496054996",		-- dropping without having jumped
	land = "rbxassetid://135499897151310",
	victory = "rbxassetid://133750952067894",
	sadSit = "rbxassetid://79286409560704",
	sprint = "rbxassetid://84956216951852",
}

-- Asset layout (ReplicatedStorage.TyreCannon.Assets):
--   Wheel/Tyre, Wheel/Spoke           the carcass and hub pieces
--   Characters/Operator, Props/Pole    the man with the pole
--   Props/Lever, Chair, SonicPad, Coin, StickerPack
--   Workshop/Bench, Anvil, Hammer
--   World/Decor, World/Obstacles
--   VFX/<name>                         picked effects, cloned where needed


--==============================================================
-- workbench
--==============================================================
Config.Workshop = {
	-- rbxassetid of a front-on roller-door image. Empty uses the drawn slats.
	DoorImage = "rbxassetid://105446864116440",
	-- how many of the player's stickers get slapped on the door
	DoorStickers = 7,
}

--==============================================================
-- player settings: saved on the profile, changed in the Settings panel
--==============================================================
-- The dance your character does after a personal best. Torture Dance is yours;
-- the rest are Roblox's own R6 emotes, so they load in any game.
Config.VictoryDances = {
	{ id = "torture", name = "Torture Dance", anim = "rbxassetid://133750952067894" },
	{ id = "cheer",   name = "Cheer",         anim = "rbxassetid://129423030", loops = 3 },
	{ id = "shuffle", name = "Shuffle",       anim = "rbxassetid://182435998", seconds = 4 },
	{ id = "groove",  name = "Groove",        anim = "rbxassetid://182491037", seconds = 4 },
	{ id = "bounce",  name = "Bounce",        anim = "rbxassetid://182491065", seconds = 4 },
}
Config.VictoryDancesById = {}
for _, d in ipairs(Config.VictoryDances) do Config.VictoryDancesById[d.id] = d end

-- your garage door: paint washes over the steel, a stencil goes on top, stickers over that
Config.DoorPaints = {
	{ id = "steel",   name = "Bare Steel",     tint = Color3.fromRGB(255, 255, 255) },
	{ id = "red",     name = "Racing Red",     tint = Color3.fromRGB(222, 58, 52) },
	{ id = "green",   name = "Workshop Green", tint = Color3.fromRGB(92, 146, 100) },
	{ id = "blue",    name = "Garage Blue",    tint = Color3.fromRGB(84, 122, 190) },
	{ id = "mustard", name = "Mustard",        tint = Color3.fromRGB(226, 178, 64) },
	{ id = "black",   name = "Soot Black",     tint = Color3.fromRGB(72, 72, 78) },
}
Config.DoorPaintsById = {}
for _, d in ipairs(Config.DoorPaints) do Config.DoorPaintsById[d.id] = d end
Config.DoorStencils = {
	{ id = "none",   name = "No Stencil" },
	{ id = "number", name = "Yard Number" },
	{ id = "name",   name = "Rig Name" },
	{ id = "stripe", name = "Racing Stripe" },
	{ id = "hazard", name = "Hazard Band" },
}
Config.DoorStencilsById = {}
for _, d in ipairs(Config.DoorStencils) do Config.DoorStencilsById[d.id] = d end

Config.RigName = { MaxLength = 18 }

Config.PrefDefaults = {
	dance = "torture",
	shake = 1,			-- camera shake, 0..1
	particles = 1,		-- 0.35 low, 0.65 medium, 1 high
	uiScale = 1,		-- 0.85..1.15
	perf = false,		-- frame time and memory readout
	music = 0.6,
	sfx = 0.8,
	camera = "chase",	-- the run: "chase" or "first"
	sens = 0.5,		-- steering sensitivity on the mouse, 0..1
	invertpitch = false,
	doorPaint = "steel",
	doorStencil = "none",
	rigName = "",
}

--==============================================================
-- sticker sheets, one tab each on the sticker station. Stickers not listed land on
-- the last sheet, so new ones always show up somewhere.
--==============================================================
Config.StickerSheets = {
	{ id = "jdm", name = "JDM", ids = { "P1_02", "P1_08", "P1_13", "P1_16", "P2_04", "P2_21", "P1_06" } },
	{ id = "anime", name = "Anime", ids = {
		"P1_01", "P1_05", "P1_09", "P1_10", "P1_12", "P1_14", "P1_15", "P1_18", "P1_19", "P1_20", "P2_01",
		"P2_02", "P2_03", "P2_06", "P2_08", "P2_09", "P2_12", "P2_14", "P2_15", "P2_16", "P2_19",
	} },
	{ id = "critters", name = "Critters", ids = { "P1_03", "P1_07", "P1_17", "P2_07", "P2_10", "P2_11", "P2_17", "P2_18", "P2_20" } },
	{ id = "memes", name = "Memes", ids = { "P1_04", "P1_11", "P2_05", "P2_13" } },
}

-- stickers that shimmer as the wheel turns
Config.FoilStickers = { P1_02 = true, P1_13 = true, P1_16 = true, P2_18 = true, P2_21 = true }

--==============================================================
-- GARAGE
-- The walk-in garage behind every yard's door. Nothing in it is bought: it fills up with
-- what happened on your runs. Anyone can walk in and look round.
--==============================================================
Config.Garage = {
	-- the second bay stores a whole build (tyre, rim, trail and stickers) you can swap in
	BayCost = 25000,
	-- stamps a visitor can leave in your guestbook
	Stamps = {
		{ id = "respect", text = "RESPECT", color = Color3.fromRGB(196, 44, 38) },
		{ id = "clean", text = "CLEAN BUILD", color = Color3.fromRGB(40, 104, 196) },
		{ id = "sendit", text = "SEND IT", color = Color3.fromRGB(222, 116, 24) },
		{ id = "legend", text = "LEGEND", color = Color3.fromRGB(176, 136, 30) },
		{ id = "honk", text = "HONK HONK", color = Color3.fromRGB(36, 140, 76) },
		{ id = "wall", text = "NICE WALL", color = Color3.fromRGB(118, 60, 168) },
	},
	StampCooldown = 600,
	GuestbookSize = 24,
	-- shelf trophies: the highest step reached shows, in bronze, silver, gold, then platinum
	Trophies = {
		{ id = "distance", name = "ROAD COVERED", steps = { 1, 10, 50, 250 }, unit = "KM" },
		{ id = "runs", name = "LAUNCHES", steps = { 10, 100, 500, 2000 }, unit = "" },
		{ id = "best", name = "LONGEST RUN", steps = { 750, 1750, 3350, 8800 }, unit = "M" },
		{ id = "forged", name = "BOXES FORGED", steps = { 1, 10, 50, 200 }, unit = "" },
		{ id = "flawless", name = "PERFECT LAUNCHES", steps = { 5, 25, 100, 500 }, unit = "" },
		{ id = "contracts", name = "CONTRACTS DONE", steps = { 5, 25, 100, 400 }, unit = "" },
	},
	TrophyTiers = {
		{ name = "BRONZE", color = Color3.fromRGB(176, 108, 58) },
		{ name = "SILVER", color = Color3.fromRGB(190, 196, 204) },
		{ name = "GOLD", color = Color3.fromRGB(238, 186, 56) },
		{ name = "PLATINUM", color = Color3.fromRGB(176, 222, 232) },
	},
}
Config.Garage.StampsById = {}
for _, s in ipairs(Config.Garage.Stamps) do Config.Garage.StampsById[s.id] = s end

return Config
