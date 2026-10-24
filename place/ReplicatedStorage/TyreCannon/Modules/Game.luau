--!strict
-- TYRE CANNON :: Game
-- The revamped loop's rules in one place, shared by server and client:
--   launch -> fly -> cash out -> upgrade -> launch again
-- Two loops that can't feed each other (see tools/econ_sim.py, which tuned these numbers):
--   cash -> machines -> reach -> more cash      (how far you CAN get comes from plot tier + machines)
--   keys -> crates   -> tyres -> faster cash    (keys only come from playing)
-- Multipliers stack in buckets: tyres add up, overhauls add up, bought multipliers multiply (capped).

local Game = {}

--==============================================================
-- units and the run
--==============================================================
Game.StudsToMetres = 0.28
Game.TyreRadius = 6
Game.Run = {
	TargetSeconds = 26,      -- an average run lasts about this long at every stage of the game
	BaseMetres = 1000,       -- a fresh plot's typical rolling run (headless: none 360, a hand on it 1,000, a good one 1,700)
	Skill = 1.12,            -- what perfect launches and landings add on average
	PerfectLaunch = 1.25,    -- launch power on a PERFECT tap
	GoodLaunch = 1.0,
	MissLaunch = 0.82,
	LandingLoss = 0.14,      -- speed lost on a normal landing
	PerfectLandingBoost = 0.05,
	HopSpeed = 90,           -- studs/s up when you hop
	SuperHopSpeed = 170,     -- off a kicker lip
	Gravity = 210,
	BoostAccel = 0.55,       -- fraction of launch speed added per second of boost
	HeatRate = 0.42,         -- heat per second of boost (1 = blowout)
	CoolRate = 0.22,
	Redline = 0.72,          -- past this, boost pushes twice as hard
	SmashSpeed = 0.55,       -- fraction of launch speed needed to smash instead of bump
	BumpLoss = 0.22,
	MinSpeed = 18,
	StopGrace = 1.2,
}

--==============================================================
-- zones: one road, three stretches for Alpha 0.2 (Quarry, Docks, Salt Flats, Mountain Pass and the
-- Moon come back in later patches; their worlds stay in Config.ZoneWorlds). Past the Dunes line the
-- road stays Dunes. Each metre pays its zone's rate.
--==============================================================
Game.Zones = {
	{ id = "backroad", name = "Backroad", start = 0, rate = 0.45, keys = 1,
		road = Color3.fromRGB(150, 116, 78), verge = Color3.fromRGB(104, 158, 74), ground = Enum.Material.Grass,
		sky = { clock = 10.5, haze = 1.4, fog = Color3.fromRGB(196, 214, 230) } },
	{ id = "highway", name = "Highway", start = 4000, rate = 0.72, keys = 2,
		road = Color3.fromRGB(58, 60, 66), verge = Color3.fromRGB(120, 150, 80), ground = Enum.Material.Grass,
		sky = { clock = 13.0, haze = 1.2, fog = Color3.fromRGB(206, 220, 236) } },
	{ id = "dunes", name = "Dunes", start = 12000, rate = 1.1, keys = 2,
		road = Color3.fromRGB(226, 186, 120), verge = Color3.fromRGB(236, 200, 136), ground = Enum.Material.Sand,
		sky = { clock = 15.6, haze = 2.0, fog = Color3.fromRGB(240, 212, 170) } },
}
Game.ZonesById = {}
for i, z in ipairs(Game.Zones) do
	(z :: any).index = i
	Game.ZonesById[z.id] = z
end

function Game.zoneAt(metres: number): number
	local idx = 1
	for i, z in ipairs(Game.Zones) do
		if metres >= z.start then idx = i end
	end
	return idx
end

-- cash for a run of `metres`: every metre pays the rate of the zone it's in
function Game.runCash(metres: number): number
	local total = 0
	for i, z in ipairs(Game.Zones) do
		local nextStart = Game.Zones[i + 1] and Game.Zones[i + 1].start or math.huge
		if metres > z.start then
			total += (math.min(metres, nextStart) - z.start) * z.rate
		end
	end
	return total
end

--==============================================================
-- the plot: machines and tiers
--==============================================================
-- six chunky levels a machine a tier (each one a visible step), not twenty small ones; prices from
-- tools/econ_sim.py: first buy after about three runs, a buy every minute or so after, about
-- 0.5 h, 1 h, 1.7 h, 2.7 h and 3.8 h in each tier
Game.LevelsPerTier = 6
Game.PriceGrowth = 1.45
Game.Tiers = {
	{ name = "Dirt Lot", reach = 1.0, price = 2.9 },
	{ name = "Scrapyard", reach = 2.05, price = 23.6 },
	{ name = "Workshop Yard", reach = 4.4, price = 251.3 },
	{ name = "Depot", reach = 9.0, price = 1386.3 },
	{ name = "Launch Complex", reach = 18.0, price = 6365.4 },
}
-- v3.1, the flight run: every machine changes something you feel on the very next launch. `gain` is
-- what a level adds to the reach estimate (the server's sanity cap and the Plot's "your reach").
-- (The launch ramp is gone: the cannon fires straight out of its own barrel.)
Game.Machines = {
	{ id = "cannon", name = "Cannon", what = "Launch speed", gain = 0.16, cost = 120 },
	{ id = "fuel", name = "Fuel Tank", what = "Nitro tank", gain = 0.10, cost = 200 },
	{ id = "cooling", name = "Cooling Tower", what = "Nitro recharge", gain = 0.09, cost = 240 },
	{ id = "compressor", name = "Compressor", what = "Glide", gain = 0.07, cost = 300, maxLevel = 10 },
	{ id = "rack", name = "Spare Rack", what = "Spare tyre slots", gain = 0, cost = 1500, maxLevel = 4 },
}
Game.MachinesById = {}
for _, m in ipairs(Game.Machines) do Game.MachinesById[m.id] = m end

-- the flight's tuning the machines feed (RunSim reads the rest from Config.Run)
Game.V3 = {
	LaunchBase = 255,        -- studs/s out of a level-0 cannon on a dirt lot
	CannonPer = 0.09,        -- launch speed per cannon level
	NitroBase = 100,         -- the tank, in units; a ring gives about a fifth of it
	NitroPer = 0.18,         -- tank size per fuel level
	RegenBase = 2.2,         -- units a second, always
	RegenPer = 0.22,         -- per cooling level
	GlidePer = 0.045,        -- less sink, wider glide per compressor level
	StageSpeed = { 1.0, 1.1, 1.2, 1.3, 1.4 },  -- each yard stage scales the whole run (gently: cash is the stage's reward)
	-- what a machine level is worth at each stage: a level at a later stage adds more (Cannon +9% a
	-- level on a dirt lot, +20% on a launch complex), so every stage's upgrades are felt
	StageUpgrade = { 1.0, 1.3, 1.6, 1.9, 2.2 },
}

-- the per-level multiplier for machines at a yard stage
function Game.upgradeMul(tier: number?): number
	local u = Game.V3.StageUpgrade
	return u[math.clamp(math.floor(tier or 1), 1, #u)]
end

-- what a machine does at a level, in words people read ("Launch speed +27%", "Nitro tank 154");
-- `tier` is the yard's stage (a level is worth more at a later stage)
function Game.machineEffect(id: string, level: number, tier: number?): string
	local V = Game.V3
	local u = Game.upgradeMul(tier)
	if id == "cannon" then return ("Launch speed +%d%%"):format(math.floor(V.CannonPer * u * level * 100 + 0.5)) end
	if id == "fuel" then return ("Nitro tank %d"):format(math.floor(V.NitroBase * (1 + V.NitroPer * u * level) + 0.5)) end
	if id == "cooling" then return ("Nitro recharge %.1f/s"):format(V.RegenBase * (1 + V.RegenPer * u * level)) end
	if id == "compressor" then return ("Glide +%d%%"):format(math.floor(V.GlidePer * level * 100 + 0.5)) end
	if id == "rack" then return ("%d spare tyre slot%s"):format(1 + level, level == 0 and "" or "s") end
	return ""
end

-- what the next level adds, short, for the goal card and the Plot rows
function Game.machineNext(id: string, _level: number, tier: number?): string
	local V = Game.V3
	local u = Game.upgradeMul(tier)
	if id == "cannon" then return ("+%d%% launch speed"):format(math.floor(V.CannonPer * u * 100 + 0.5)) end
	if id == "fuel" then return ("+%d nitro"):format(math.floor(V.NitroBase * V.NitroPer * u + 0.5)) end
	if id == "cooling" then return ("+%.1f nitro/s"):format(V.RegenBase * V.RegenPer * u) end
	if id == "compressor" then return ("+%.1f%% glide"):format(V.GlidePer * 100) end
	if id == "rack" then return "+1 spare tyre slot" end
	return ""
end

Game.CannonBuilds = { "Junk Pipe", "Steel Mortar", "Air Cannon", "Howitzer", "Mag Rail" }

function Game.maxLevel(id: string): number
	local m = Game.MachinesById[id]
	return m and m.maxLevel or Game.LevelsPerTier
end

-- `v` (the save, optional) brings the prestige and the perks into the price (Game.priceScale)
function Game.machinePrice(id: string, level: number, tier: number, v: any?): number
	local m = Game.MachinesById[id]
	if not m then return math.huge end
	local t = Game.Tiers[math.clamp(tier, 1, #Game.Tiers)]
	if m.maxLevel then
		-- utility machines: priced off the tier too, but on their own short ladder
		return math.floor(m.cost * 3.2 ^ level * t.price * Game.priceScale(v))
	end
	return math.floor(m.cost * Game.PriceGrowth ^ level * t.price * Game.priceScale(v))
end

-- the metres a plot can reach on an average run (before skill and luck)
function Game.reachMetres(levels: { [string]: number }, tier: number): number
	local d = Game.Run.BaseMetres * Game.Tiers[math.clamp(tier, 1, #Game.Tiers)].reach
	local u = Game.upgradeMul(tier)
	for _, m in ipairs(Game.Machines) do
		-- (the compressor's glide doesn't scale with the stage)
		local k = if m.id == "compressor" then 1 else u
		if m.gain > 0 then d *= 1 + m.gain * k * (levels[m.id] or 0) end
	end
	return d
end

-- which cannon build stands on the plot for a cannon level (one new build every 4 levels)
-- the cannon's build is the yard's tier: Junk Pipe on a dirt lot .. Mag Rail on a launch complex
function Game.cannonBuild(tier: number): number
	return math.clamp(tier, 1, #Game.CannonBuilds)
end

--==============================================================
-- the plot upgrade (stage up): it costs cash, and it's a real purchase
-- The yard moves up a stage (Dirt Lot .. Launch Complex): a new cannon build, a faster stage, every
-- cash source +100% for good. The machines start again at level 0 in the new stage (their prices
-- are higher there); your tyres and your cash (less the price) stay. It costs this many times what
-- it takes to max the stage's three run machines, so it comes when you've nearly finished the stage.
--==============================================================
-- the first-session tutorial's steps (Tutorial.luau shows them, Analytics logs them as the onboarding
-- funnel). The order is the funnel: a step only counts once the one before it has.
Game.TutorialSteps = {
	"Joined", "Launch", "Shift", "Nitro", "Tuck", "Land", "First run", "Spend it",
	"Cannon bought", "Crate", "Second run", "Float", "Dive", "Daily", "Done",
}

Game.Overhaul = {
	Mult = 3.0,         -- each plot stage multiplies all cash by this (x3, x9, x27, x81)
	CostMult = 2.0,
	Machines = { "cannon", "fuel", "cooling" },
}

-- what moving up from `tier` costs
function Game.plotUpgradeCost(tier: number, v: any?): number
	local total = 0
	for _, id in ipairs(Game.Overhaul.Machines) do
		for lvl = 0, Game.maxLevel(id) - 1 do total += Game.machinePrice(id, lvl, tier, v) end
	end
	return math.floor(total * Game.Overhaul.CostMult * (1 - 0.1 * Game.perkLv(v, "scrap")))
end

-- the stage's cash multiplier (after `overhauls` upgrades)
function Game.stageCash(overhauls: number): number
	return Game.Overhaul.Mult ^ math.max(0, overhauls)
end

-- every machine that resets with the stage at its top level
function Game.machinesMaxed(v): boolean
	for _, id in ipairs(Game.Overhaul.Machines) do
		if (v.mach[id] or 0) < Game.maxLevel(id) then return false end
	end
	return true
end

-- the stage's trial (Goals) is done: a save from before trials has none, and counts as done
function Game.trialDone(v): boolean
	return v.trial == nil or v.trial.done == true
end

function Game.canUpgradePlot(v, credits: number): boolean
	return v.tier < #Game.Tiers and Game.machinesMaxed(v) and Game.trialDone(v) and credits >= Game.plotUpgradeCost(v.tier, v)
end

--==============================================================
-- prestige (Loop's Prestige, 2026-10-12): past the top stage the yard starts again from the Dirt Lot.
-- Each prestige is all cash +50% for good, on top of everything else; the stage multiplier goes back to
-- x1 and is earned again stage by stage. It pays keys, puts P1, P2... on your yard sign and keeps
-- everything you collected: tyres, keys, cosmetics, the compressor and the spare rack. (The v1 prestige
-- wiped your cosmetics and paid tokens for a shop that's gone.) p.prestige, capped at 25 by Profile.
--==============================================================
Game.Prestige = {
	CashPer = 0.5,      -- all cash +50% per prestige
	Keys = 14,          -- keys for prestiging...
	KeysPer = 1,        -- ...plus this many per level reached (P1 15, P2 16, ...: keys are rare now)
	Max = 25,           -- (Config.Prestige.MaxLevel, the cap Profile.sanitize keeps)
	-- v4 (2026-10-16): a prestige spends all your cash (the climb starts from nothing, as a rebirth
	-- should), and every price grows with prestige as its cash bonus to this power, so a climb never
	-- collapses into a minute: each one is about as long as the last, a little shorter for the bonus
	PriceExp = 0.8,
	Choices = 3,        -- perks offered at each prestige (pick one)
}

-- v4: the save's prestige (mirrored into profile.v2 as `pres`) and a perk's level
function Game.presOf(v: any?): number
	return (v and v.pres) or 0
end

function Game.perkLv(v: any?, id: string): number
	local p = v and v.perks
	return (p and p[id]) or 0
end

-- every price scales with the prestige (Game.Prestige.PriceExp) and the Bargain Bin perk
function Game.priceScale(v: any?): number
	return Game.prestigeMult(Game.presOf(v)) ^ Game.Prestige.PriceExp * (1 - 0.08 * Game.perkLv(v, "bargain"))
end

--==============================================================
-- prestige perks (v4): each prestige offers three, you keep one for good. They stack up into a build
-- of your own, so every climb plays a little differently: cheaper machines and a sprint through the
-- early stages, or a stronger cannon, or keys and luck, or a yard that earns while you're away.
--==============================================================
Game.Perks = {
	{ id = "bargain", name = "Bargain Bin", text = "Machines cost %d%% less", per = 8, max = 4, icon = "cannon" },
	{ id = "scrap", name = "Scrap Dealer", text = "Stage-ups cost %d%% less", per = 10, max = 3, icon = "plot" },
	{ id = "barrel", name = "Hot Barrel", text = "Launch speed +%d%%", per = 5, max = 4, icon = "cannon" },
	{ id = "tank", name = "Deep Tank", text = "Nitro tank +%d%% and recharge", per = 10, max = 4, icon = "fuel" },
	{ id = "headstart", name = "Head Start", text = "Every stage starts with machines at level %d", per = 1, max = 3, icon = "plot" },
	{ id = "finder", name = "Key Finder", text = "+%d key every 5 runs", per = 1, max = 3, icon = "key" },
	{ id = "luck", name = "Lucky Spin", text = "Epic and rarer %d%% more likely in crates", per = 15, max = 3, icon = "crate" },
	{ id = "idle", name = "Idle Hands", text = "Auto-cannon and offline pay +%d%%", per = 20, max = 4, icon = "cannon" },
	{ id = "wreck", name = "Wrecking Ball", text = "Smashing pays +%d%%", per = 50, max = 3, icon = "tyre" },
	{ id = "magnet", name = "Coin Magnet", text = "Coins pay +%d%% and pull from further", per = 15, max = 3, icon = "cash" },
	{ id = "showman", name = "Showman", text = "Yard style +%d%%", per = 10, max = 3, icon = "plot" },
	{ id = "trials", name = "Trial Runner", text = "Stage trials %d%% easier", per = 10, max = 3, icon = "medal" },
}
Game.PerksById = {}
for _, pk in ipairs(Game.Perks) do Game.PerksById[pk.id] = pk end

-- what a perk does at a level, in words
function Game.perkText(id: string, level: number): string
	local pk = Game.PerksById[id]
	if not pk then return "" end
	return pk.text:format(pk.per * math.max(1, level))
end

-- the three on offer at a prestige: perks not yet at their top, rolled from the player and the level
function Game.perkOffer(uid: number, pres: number, perks: { [string]: number }?): { string }
	local pool = {}
	for _, pk in ipairs(Game.Perks) do
		if ((perks and perks[pk.id]) or 0) < pk.max then table.insert(pool, pk.id) end
	end
	local r = Random.new((uid % 1000003) * 53 + pres * 7)
	local out = {}
	while #out < Game.Prestige.Choices and #pool > 0 do
		table.insert(out, table.remove(pool, r:NextInteger(1, #pool)))
	end
	return out
end

function Game.prestigeMult(level: number?): number
	return 1 + Game.Prestige.CashPer * math.max(0, level or 0)
end

-- what a prestige costs: the price of one more stage past the top
function Game.prestigeCost(v: any?): number
	return Game.plotUpgradeCost(#Game.Tiers, v)
end

function Game.canPrestige(v, credits: number, level: number?): boolean
	return v.tier >= #Game.Tiers and Game.machinesMaxed(v) and Game.trialDone(v) and credits >= Game.prestigeCost(v) and (level or 0) < Game.Prestige.Max
end

-- prestige looks (2026-10-12, the Prestige & Neon design canvas): each milestone has one colour that
-- shows on your tyre (a neon lip, PrestigeLook.dressTyre), your cannon (a trim: muzzle ring, barrel
-- tube, collars, a P badge) and the Hall of Prestige yard (YardLook). Levels between milestones keep
-- the last milestone's look plus a gold pip a level. `collar` nil keeps the cannon's own collars.
local function rgb(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end
Game.PrestigeLooks = {
	{ n = 1, name = "Neon Halo", color = rgb(63, 184, 255) },
	{ n = 2, name = "Mint Line", color = rgb(67, 230, 160) },
	{ n = 3, name = "Ember Tread", color = rgb(255, 122, 46), strap = rgb(255, 122, 46) },
	{ n = 5, name = "Molten Gold", color = rgb(255, 194, 58), collar = rgb(255, 194, 58), strap = rgb(255, 194, 58) },
	{ n = 8, name = "Void Chrome", color = rgb(166, 107, 255), collar = rgb(42, 30, 70), strap = rgb(201, 168, 255) },
	{ n = 10, name = "Checker Crown", color = rgb(255, 79, 163), collar = rgb(244, 241, 232) },
	{ n = 15, name = "Circuit", color = rgb(184, 240, 58), collar = rgb(22, 48, 31), strap = rgb(184, 240, 58) },
	{ n = 20, name = "Inferno", color = rgb(255, 59, 48), collar = rgb(122, 22, 16), strap = rgb(255, 122, 46) },
	{ n = 25, name = "Prism Apex", color = rgb(255, 79, 163), collar = rgb(230, 235, 242), strap = rgb(244, 241, 232),
		prism = { rgb(63, 184, 255), rgb(255, 194, 58), rgb(255, 79, 163) } },
}
Game.PrestigePip = rgb(255, 194, 58)
-- the tubes on prestige looks, the yard looks and the neon decor: off, they're bright flat paint; on,
-- they're Neon material, which blooms under the game's Bloom. On since 2026-10-17: the owner lifted the
-- no-glow rule so the neon pack really glows (NeonDecor and YardLook add the lights)
Game.NeonTubes = true

-- the look for a prestige level (nil below P1) and how many pips past its milestone
function Game.prestigeLook(level: number?): (any?, number)
	local lv = math.floor(level or 0)
	local best = nil
	for _, l in ipairs(Game.PrestigeLooks) do
		if lv >= l.n then best = l end
	end
	return best, best and (lv - best.n) or 0
end

-- the colours a look paints with, in order (one, or the three of the prism)
function Game.lookColors(look: any?): { Color3 }
	if not look then return {} end
	return look.prism or { look.color }
end

-- yard looks: what the yard's floor and edges are dressed as (YardLook). The stage's own look is
-- free; the Hall of Prestige comes with your first prestige; the Midnight Garage is a gamepass
-- (Config.Store.Passes "midnight", 699 R$) and comes in three colourways.
Game.YardLooks = {
	{ id = "stage", name = "Stage Look", text = "The yard as its stage builds it." },
	{ id = "prestige", name = "Hall of Prestige", text = "Your milestone colour round the edge, down the lane and under the cannon.", prestige = 1 },
	{ id = "midnight", name = "Midnight Garage", text = "Night floor, a double neon edge, a bump lane and tyre towers.", pass = "midnight",
		ways = {
			{ id = "Midnight", a = rgb(224, 64, 251), b = rgb(46, 230, 242), floor = rgb(29, 22, 56), grid = rgb(52, 42, 96) },
			{ id = "Sunset", a = rgb(255, 122, 46), b = rgb(255, 79, 163), floor = rgb(40, 22, 44), grid = rgb(76, 40, 72) },
			{ id = "Toxic", a = rgb(184, 240, 58), b = rgb(46, 230, 242), floor = rgb(18, 28, 40), grid = rgb(34, 58, 70) },
		} },
}
Game.YardLooksById = {}
for _, l in ipairs(Game.YardLooks) do Game.YardLooksById[l.id] = l end

-- the Midnight Garage's colourway by name (the first when unknown)
function Game.yardWay(name: string?): any
	local ways = Game.YardLooksById.midnight.ways
	for _, w in ipairs(ways) do
		if w.id == name then return w end
	end
	return ways[1]
end

-- can someone with this prestige and these passes use the look (or the decor kind)?
function Game.lookOpen(item: any, prestige: number?, passes: { [string]: any }?): boolean
	if not item then return false end
	if item.prestige and (prestige or 0) < item.prestige then return false end
	if item.pass and not (passes and passes[item.pass]) then return false end
	return true
end

--==============================================================
-- levels (Server/Career): XP from playing, a level badge whose colour moves up through the bands, keys
-- on every level (5 every 5th, 10 every 10th)
--==============================================================
Game.Levels = {
	Base = 100, Step = 40,      -- XP from level L to L+1: Base + Step * (L - 1)  (L10 ~40 runs, L50 ~10 h)
	XP = {
		run = 20, zone = 10,    -- a finished run, +10 for each zone past the first it reached
		best = 25,              -- a new best
		upgrade = 5,            -- a machine level
		crate = 8,              -- each tyre out of a crate
		stage = 150,            -- a yard stage-up
		prestige = 500,
		heat = 20, heatWin = 60,   -- finishing a Heat, winning one
		daily = 40,             -- the daily reward
	},
	Bands = {   -- the badge's colour and rank from this level up
		{ from = 1,   name = "Rookie", color = Color3.fromRGB(205, 140, 80) },
		{ from = 10,  name = "Driver", color = Color3.fromRGB(192, 198, 210) },
		{ from = 25,  name = "Pro",    color = Color3.fromRGB(236, 196, 120) },
		{ from = 50,  name = "Ace",    color = Color3.fromRGB(48, 178, 184) },
		{ from = 75,  name = "Legend", color = Color3.fromRGB(152, 98, 236) },
		{ from = 100, name = "Master", color = Color3.fromRGB(214, 52, 48) },
	},
	Max = 999,
}

function Game.xpToNext(level: number): number
	return Game.Levels.Base + Game.Levels.Step * (math.max(1, level) - 1)
end

function Game.levelBand(level: number)
	local band = Game.Levels.Bands[1]
	for _, b in ipairs(Game.Levels.Bands) do
		if level >= b.from then band = b end
	end
	return band
end

-- keys for reaching `level`
-- (2026-10-16: keys are rare) every 5th level a key or two, every 10th a handful
function Game.levelKeys(level: number): number
	if level % 10 == 0 then return 5 end
	if level % 5 == 0 then return 2 end
	return 0
end

--==============================================================
-- titles (Config.Titles): how far a save is toward one, as (have, goal). Shared, so the Profile panel
-- shows the same numbers the server unlocks on
--==============================================================
function Game.titleProgress(p, t): (number, number)
	if t.live then
		local rank = p.live and tonumber(p.live[t.live.board])
		return if rank and rank <= t.live.rank then 1 else 0, 1
	end
	local c = t.cond or {}
	local goal = c.goal or 1
	local v = p.v2 or {}
	local cr = v.career or {}
	local st = p.stats or {}
	local s = c.stat
	local have = 0
	if s == "runs" then
		have = v.runs or 0
	elseif s == "upgrades" or s == "perfects" or s == "crates" or s == "heatWins" then
		have = cr[s] or 0
	elseif s == "best" then
		have = math.floor(v.bestEver or 0)
	elseif s == "zone" then
		have = if v.zones and v.zones[c.zone] then 1 else 0
	elseif s == "flawless" or s == "cleanRuns" or s == "smashes" or s == "longestAir" then
		have = st[s] or 0
	elseif s == "index" then
		for _ in pairs(v.index or {}) do have += 1 end
	elseif s == "stage" then
		have = math.max(v.tier or 1, cr.maxStage or 1, if (p.prestige or 0) > 0 then #Game.Tiers else 0)
	elseif s == "bestSpectators" then
		have = p.lifetime and p.lifetime.bestSpectators or 0
	elseif s == "prestige" then
		have = p.prestige or 0
	elseif s == "level" then
		have = cr.level or 1
	elseif s == "rarity" then
		for id in pairs(v.index or {}) do
			local tt = Game.TyresById[id]
			if tt and tt.rarity == c.rarity then
				have = 1
				break
			end
		end
	end
	return math.min(have, goal), goal
end

--==============================================================
-- tyres
--==============================================================
Game.Rarities = {
	{ id = "Common", odds = 0.52, mult = 1.2, color = Color3.fromRGB(176, 182, 190) },
	{ id = "Uncommon", odds = 0.30, mult = 1.5, color = Color3.fromRGB(98, 214, 120) },
	{ id = "Rare", odds = 0.13, mult = 2, color = Color3.fromRGB(80, 160, 255) },
	{ id = "Epic", odds = 0.045, mult = 3, color = Color3.fromRGB(190, 110, 255) },
	{ id = "Legendary", odds = 0.0045, mult = 6, color = Color3.fromRGB(255, 190, 60) },
	{ id = "Mythic", odds = 0.0005, mult = 12, color = Color3.fromRGB(255, 70, 90) },
	{ id = "Secret", odds = 0.0001, mult = 30, color = Color3.fromRGB(240, 240, 236) },
}
Game.RaritiesById = {}
for i, r in ipairs(Game.Rarities) do
	(r :: any).order = i
	Game.RaritiesById[r.id] = r
end
-- fusing copies of the same tyre makes the next star: each star adds half the rarity's multiplier
-- again. How many copies a fuse takes goes down as the tyre gets rarer (Game.fuseNeed).
Game.Forge = { Need = 5, Names = { "", "Gold", "Chrome", "Obsidian" }, StarShare = 0.5,
	NeedBy = { Common = 6, Uncommon = 6, Rare = 5, Epic = 5, Legendary = 4, Mythic = 3, Secret = 2 } }

-- how many of a tyre one fuse takes
function Game.fuseNeed(id: string): number
	local t = Game.TyresById and Game.TyresById[id]
	return (t and Game.Forge.NeedBy[t.rarity]) or Game.Forge.Need
end

--==============================================================
-- v3: a tyre is a cash multiplier (like a pet in a simulator). Its rarity sets it, stars add to
-- it, and a mutation rolled on the crate multiplies it. Every equipped tyre counts in full; the
-- launch tyre also brings its special and its skill.
--==============================================================
-- every tyre has two stats from this pool. A tyre's points are its rarity's place (Common 1 ..
-- Secret 7) plus its stars; `per` is what one point does (the launch tyre in full, spares at half).
-- Rarity also sets the cash multiplier (Game.tyreMult); these are what changes how it FLIES.
Game.Stats = {
	{ id = "launch", name = "Launch", text = "launch speed", per = 0.06 },
	{ id = "boost", name = "Boost", text = "nitro power", per = 0.05 },
	{ id = "fuel", name = "Tank", text = "nitro tank", per = 0.05 },
	{ id = "cooling", name = "Recharge", text = "nitro recharge", per = 0.09 },
	{ id = "grip", name = "Grip", text = "turning", per = 0.07 },
	{ id = "air", name = "Glide", text = "glide", per = 0.05 },
	{ id = "magnet", name = "Magnet", text = "ring and coin reach", per = 0.10 },
	{ id = "tough", name = "Tough", text = "speed kept in hits", per = 0.06 },
	{ id = "cash", name = "Cash", text = "extra cash", per = 0.03 },
}
Game.StatsById = {}
for _, st in ipairs(Game.Stats) do Game.StatsById[st.id] = st end
Game.SparesShare = 0.5

Game.Mutations = {
	{ id = "gold", name = "Gold", mult = 2, odds = 0.08, color = Color3.fromRGB(255, 196, 60) },
	{ id = "chrome", name = "Chrome", mult = 3, odds = 0.02, color = Color3.fromRGB(200, 226, 255) },
	{ id = "rainbow", name = "Rainbow", mult = 5, odds = 0.004, color = Color3.fromRGB(255, 120, 220) },
	-- only drops while the Monsoon event is on
	{ id = "monsoon", name = "Monsoon", mult = 2.5, odds = 0, event = "monsoon", color = Color3.fromRGB(90, 200, 255) },
}
Game.MutationsById = {}
for _, m in ipairs(Game.Mutations) do Game.MutationsById[m.id] = m end

-- roll a mutation for a fresh tyre (nil = none); `event` is the server event that's on, if any
function Game.rollMutation(r: number, luck: number?, event: string?): string?
	local k = luck or 1
	-- (2026-10-18) the event's slice comes first and the usual ones after it: they used to share the
	-- same low numbers, so during the Monsoon no Chrome or Rainbow could ever drop
	local acc = 0
	for _, m in ipairs(Game.Mutations) do
		if m.event and m.event == event then
			if r < 0.12 then return m.id end
			acc = 0.12
		end
	end
	for i = #Game.Mutations, 1, -1 do
		local m = Game.Mutations[i]
		if not m.event then
			acc += m.odds * k
			if r < acc then return m.id end
		end
	end
	return nil
end

-- a tyre from a dearer crate is worth more at every rarity: a Highway tyre x2 a Backroad one, a
-- Dunes tyre x4 (so a Dunes Common beats a Backroad Epic), and a few more stat points. Mythics and
-- Secrets (any crate) count as the top zone.
-- (v4: x1.6 and x2.4, down from x2 and x4: one lucky Dunes crate no longer outruns the whole yard)
Game.ZonePower = {
	backroad = { mult = 1, pts = 0 },
	highway = { mult = 1.6, pts = 1.5 },
	dunes = { mult = 2.4, pts = 3 },
	mythic = { mult = 2.4, pts = 3 },
	secret = { mult = 2.4, pts = 3 },
	retired = { mult = 1, pts = 0 },
}
function Game.zonePower(id: string): { mult: number, pts: number }
	local t = Game.TyresById[id]
	return (t and Game.ZonePower[t.zone]) or Game.ZonePower.backroad
end

function Game.tyreMult(id: string, forge: number?, mut: string?): number
	local t = Game.TyresById[id]
	if not t then return 1 end
	local base = Game.RaritiesById[t.rarity].mult * Game.zonePower(id).mult
	local m = base * (1 + Game.Forge.StarShare * (forge or 0))
	local mu = mut and Game.MutationsById[mut]
	if mu then m *= mu.mult end
	return m
end

-- a tyre's points for the stats: its rarity's place plus its stars, plus its crate's zone bonus
function Game.statPoints(id: string, forge: number?): number
	local t = Game.TyresById[id]
	if not t then return 0 end
	return Game.RaritiesById[t.rarity].order + (forge or 0) + Game.zonePower(id).pts
end

-- for the screens that sort by strength: the cash multiplier first, the stat points to break ties
function Game.tyrePoints(id: string, forge: number?, mut: string?): number
	return Game.tyreMult(id, forge, mut) + Game.statPoints(id, forge) * 0.001
end

-- what each stat adds, from the launch tyre and the spares: { launch = 0.07, grip = 0.12, ... }
function Game.tyreEffects(launch: { id: string, forge: number? }?, spares: { { id: string, forge: number? } }?)
	local e = {}
	for _, st in ipairs(Game.Stats) do e[st.id] = 0 end
	local function add(t, share: number)
		local def = t and Game.TyresById[t.id]
		if not def then return end
		local pts = Game.statPoints(t.id, t.forge) * share
		for _, sid in ipairs(def.stats) do
			e[sid] += pts * Game.StatsById[sid].per
		end
	end
	add(launch, 1)
	for _, sp in ipairs(spares or {}) do add(sp, Game.SparesShare) end
	return e
end

-- "x1.2 CASH", then its special and skill if it has them
function Game.tyreLines(id: string, forge: number?, mut: string?): { string }
	local def = Game.TyresById[id]
	local out = {}
	if not def then return out end
	table.insert(out, ("x%s CASH"):format(Game.multText(Game.tyreMult(id, forge, mut))))
	local pts = Game.statPoints(id, forge)
	for _, sid in ipairs(def.stats) do
		local st = Game.StatsById[sid]
		table.insert(out, ("+%d%% %s"):format(math.floor(pts * st.per * 100 + 0.5), string.upper(st.text)))
	end
	if def.special and Game.Specials[def.special] then table.insert(out, string.upper(Game.Specials[def.special].name)) end
	if def.skill and Game.Skills[def.skill] then table.insert(out, "SKILL: " .. string.upper(Game.Skills[def.skill].name)) end
	return out
end

-- what a tyre's special and skill do, for the screens that explain them
function Game.tyreAbilities(id: string): { { kind: string, name: string, text: string, key: string?, cooldown: number? } }
	local def = Game.TyresById[id]
	local out = {}
	if not def then return out end
	local sp = def.special and Game.Specials[def.special]
	if sp then table.insert(out, { kind = "Special", name = sp.name, text = sp.text }) end
	local sk = def.skill and Game.Skills[def.skill]
	if sk then table.insert(out, { kind = "Skill", name = sk.name, text = sk.text, key = sk.key, cooldown = sk.cooldown }) end
	return out
end

function Game.multText(m: number): string
	if m >= 100 then return tostring(math.floor(m + 0.5)) end
	if m >= 10 then return (("%.1f"):format(m):gsub("%.0$", "")) end
	return (("%.2f"):format(m):gsub("0$", ""):gsub("%.0$", ""))
end

-- Epic and up: a handling special, built into how the run plays and shown with its own effects
Game.Specials = {
	timber = { name = "Timber", text = "Smashes anything wooden at any speed, in a burst of chips" },
	jet = { name = "Jet", text = "Boost fires a long jet flame and pushes 15% harder" },
	bore = { name = "Bore", text = "Grinds through rock at any speed, throwing sparks" },
	monster = { name = "Monster Bounce", text = "Lands heavy and bounces high, slamming dust" },
	chrome = { name = "Chrome", text = "Throws sparks off the road at speed" },
	sandtrail = { name = "Golden Sand", text = "Leaves a trail of golden sand" },
	steady = { name = "Steady", text = "Stays level in the air; landings are kinder" },
	floaty = { name = "Floaty", text = "Falls a little slower, trailing stardust" },
	kart = { name = "Kart Tuned", text = "Sharper steering and a little spark when you turn" },
	blocky = { name = "Blocky", text = "Rolls in bumpy hops, edge to edge" },
	glazed = { name = "Glazed", text = "Slippery: slides through turns, drips glaze" },
}
-- Legendary and up: an active skill on one key (E / the skill button), on a cooldown
Game.Skills = {
	groundpound = { name = "Meteor", key = "E", cooldown = 12, text = "Dive-bomb: slam down for a shockwave that smashes what's near and throws you back up" },
	spindash = { name = "Drill Dash", key = "E", cooldown = 11, text = "A burst of speed in a spinning ball: nothing on the road can stop you" },
	wings = { name = "Scarab Wings", key = "E", cooldown = 14, text = "Golden wings: four seconds of true glide, no sink and no stall" },
	sandevistan = { name = "Sandevistan", key = "E", cooldown = 16, text = "The world slows to a crawl while you don't, leaving afterimages: every ring is easy to line up" },
	zerog = { name = "Zero-G", key = "E", cooldown = 13, text = "Three seconds of low gravity in a ring of stardust" },
	-- (2026-10-24) a 5 s cooldown and charged on the ground only: it was free speed with no limit
	miniturbo = { name = "Mini-Turbo", key = "E", cooldown = 5, text = "On the ground, hold to charge sparks blue, orange, purple; let go to shoot off" },
	mine = { name = "Mine", key = "E", cooldown = 10, text = "The next few things you hit break into blocks and drop coins" },
	inhale = { name = "Inhale", key = "E", cooldown = 12, text = "Swallow everything ahead, then float puffed up" },
}

-- num, id, name, zone, rarity, { stat, stat }, special, skill  (zone "mythic" and "secret" drop from any crate;
-- "retired" ones aren't in a crate this patch but still work for anyone who has them)
local T = {
	{ 1, "wheelbarrow", "Wheelbarrow Wheel", "backroad", "Common", { "grip", "magnet" } },
	{ 2, "baldspare", "Bald Spare", "backroad", "Common", { "launch", "cash" } },
	{ 3, "steelie", "Steelie", "backroad", "Uncommon", { "tough", "fuel" } },
	{ 4, "tractorlug", "Tractor Lug", "backroad", "Rare", { "grip", "tough" } },
	{ 5, "cartwheel", "Wooden Cartwheel", "backroad", "Epic", { "tough", "cash" }, "timber" },
	{ 6, "monster", "Monster", "backroad", "Legendary", { "launch", "tough" }, "monster", "groundpound" },
	{ 7, "hubcap", "Hubcap Sedan", "highway", "Common", { "fuel", "cash" } },
	{ 8, "whitewall", "Whitewall", "highway", "Common", { "boost", "magnet" } },
	{ 9, "slick", "Racing Slick", "highway", "Uncommon", { "boost", "launch" } },
	{ 10, "splitfive", "Split Five", "highway", "Rare", { "boost", "cooling" } },
	{ 11, "turbofan", "Turbofan", "highway", "Epic", { "boost", "fuel" }, "jet" },
	{ 12, "spinner", "Chrome Spinner", "highway", "Legendary", { "launch", "magnet" }, "chrome", "spindash" },
	{ 13, "balloon", "Sand Balloon", "dunes", "Common", { "air", "grip" } },
	{ 14, "beadlock", "Beadlock", "dunes", "Common", { "tough", "cooling" } },
	{ 15, "paddle", "Paddle", "dunes", "Uncommon", { "grip", "fuel" } },
	{ 16, "dumper", "Dumper", "dunes", "Rare", { "tough", "cash" } },
	{ 17, "drill", "Drill Tread", "dunes", "Epic", { "tough", "boost" }, "bore" },
	{ 18, "scarab", "Scarab", "dunes", "Legendary", { "air", "cooling" }, "sandtrail", "wings" },
	{ 19, "gyro", "Gyro", "mythic", "Mythic", { "grip", "air" }, "steady", "sandevistan" },
	{ 20, "orbital", "Orbital", "mythic", "Mythic", { "air", "launch" }, "floaty", "zerog" },
	{ 21, "original", "The Original", "secret", "Secret", { "launch", "boost" }, "kart", "miniturbo" },
	{ 22, "square", "Square Wheel", "secret", "Secret", { "tough", "cash" }, "blocky", "mine" },
	{ 23, "donut", "Glazed Donut", "secret", "Secret", { "magnet", "cash" }, "glazed", "inhale" },
	-- retired for Alpha 0.2 (their zones are parked)
	{ 24, "stone", "Stone Wheel", "retired", "Uncommon", { "tough", "launch" } },
	{ 25, "chained", "Chained", "retired", "Rare", { "grip", "tough" } },
	{ 26, "track", "Track Wheel", "retired", "Epic", { "tough", "grip" } },
	{ 27, "fender", "Fender", "retired", "Common", { "tough", "cooling" } },
	{ 28, "forklift", "Forklift Solid", "retired", "Uncommon", { "tough", "fuel" } },
	{ 29, "lifering", "Life Ring", "retired", "Rare", { "air", "magnet" } },
	{ 30, "helm", "Ship's Helm", "retired", "Epic", { "grip", "magnet" } },
	{ 31, "propeller", "Propeller", "retired", "Legendary", { "air", "boost" } },
	{ 32, "aerodisc", "Aero Disc", "retired", "Common", { "launch", "fuel" } },
	{ 33, "skinny", "Skinny Racer", "retired", "Uncommon", { "launch", "boost" } },
	{ 34, "streamliner", "Streamliner", "retired", "Rare", { "boost", "fuel" } },
	{ 35, "record", "Record Breaker", "retired", "Legendary", { "launch", "boost" } },
	{ 36, "studded", "Studded Ice", "retired", "Common", { "grip", "cooling" } },
	{ 37, "winter", "Siped Winter", "retired", "Uncommon", { "grip", "fuel" } },
	{ 38, "rally", "Rally Gravel", "retired", "Rare", { "grip", "launch" } },
	{ 39, "honeycomb", "Honeycomb", "retired", "Epic", { "cooling", "tough" } },
	{ 40, "moonrock", "Moon Rock", "retired", "Common", { "air", "tough" } },
	{ 41, "meshrover", "Mesh Rover", "retired", "Uncommon", { "air", "grip" } },
	{ 42, "roversix", "Rover Six", "retired", "Rare", { "air", "cooling" } },
	{ 43, "dish", "Dish", "retired", "Epic", { "magnet", "air" } },
}
Game.Tyres = {}
Game.TyresById = {}
Game.TyresByZone = {}
Game.TyreCount = 0      -- the tyres in this patch (what the index counts)
for _, row in ipairs(T) do
	local t = { num = row[1], id = row[2], name = row[3], zone = row[4], rarity = row[5], stats = row[6], special = row[7], skill = row[8] }
	table.insert(Game.Tyres, t)
	Game.TyresById[t.id] = t
	Game.TyresByZone[t.zone] = Game.TyresByZone[t.zone] or {}
	table.insert(Game.TyresByZone[t.zone], t)
	if t.zone ~= "retired" then Game.TyreCount += 1 end
end
Game.StarterTyre = "baldspare"

--==============================================================
-- the run: what the plot does to the tyre (RunSim, Config.Run)
-- The yard stage scales the whole run; the cannon sets the launch speed, the ramp the angle, the
-- fuel tank the boost charges, the cooling tower the PERFECT window, the compressor the bounce.
-- Tyres don't change the physics (they multiply cash); the launch tyre's special and skill do.
--==============================================================
function Game.runStats(levels: { [string]: number }, tier: number, launch: { id: string, forge: number? }?, spares: { any }?)
	local V = Game.V3
	local cannon, fuel, cooling, comp = levels.cannon or 0, levels.fuel or 0, levels.cooling or 0, levels.compressor or 0
	local k = V.StageSpeed[math.clamp(tier, 1, #V.StageSpeed)]
	local u = Game.upgradeMul(tier)
	local e = Game.tyreEffects(launch, spares)
	local def = launch and Game.TyresById[launch.id]
	local st = {
		stage = k,
		launchSpeed = V.LaunchBase * k * (1 + V.CannonPer * u * cannon) * (1 + e.launch),
		launchAngle = 20,
		nitroMax = V.NitroBase * (1 + V.NitroPer * u * fuel) * (1 + e.fuel),
		nitroRegen = V.RegenBase * (1 + V.RegenPer * u * cooling) * (1 + e.cooling),
		nitroPower = 1 + e.boost,
		glide = (1 + V.GlidePer * comp) * (1 + e.air),
		turn = 1 + e.grip,
		reach = 1 + e.magnet,
		keep = 1 + e.tough,
		-- later stages fly on further: everything bleeds less speed
		dragScale = 1 / (1 + 0.12 * (k - 1)),
		frictionScale = 1 / (1 + 0.10 * (k - 1)),
		restitution = 0.32,
		magnetRadius = 24 * (1 + e.magnet),
		gravityScale = 1.0,
		airGravityScale = 1.0,
		maxSpeedScale = 1.0,
		perkSlots = 3,
		tyreId = launch and launch.id or nil,
		special = def and def.special or nil,
		skill = def and def.skill or nil,
	}
	-- specials that change the numbers (the rest are handled, with their effects, in the run)
	if st.special == "jet" then st.nitroPower *= 1.25
	elseif st.special == "monster" then st.restitution = 0.5
	elseif st.special == "floaty" then st.glide *= 1.25
	elseif st.special == "kart" then st.turn *= 1.3
	elseif st.special == "glazed" then st.frictionScale *= 0.7
	elseif st.special == "steady" then st.glide *= 1.12
	end
	return st
end

--==============================================================
-- crates and keys
--==============================================================
Game.Keys = {
	PerRunStreak = 25,   -- a free key every this many runs (2026-10-16: was 10)
	StartWith = 1,
	OpeningRuns = 5,     -- (v4) the key over the buffalo only shows on a newcomer's first runs
	-- (2026-10-16) keys are the rare currency: a zone's key is out on the road on only some runs
	-- (the server rolls which, Game.runKeys), so seeing one is worth the detour
	ZoneChance = 0.2,
}

-- Roblox Premium (2026-10-16): members earn a little more cash and get a key every day they play
Game.Premium = { Cash = 1.1, DailyKeys = 1 }

-- which of Game.keySpots() are out on the road this run (indices): the opening one for newcomers,
-- each zone's by chance, rolled from the run's seed so server and client agree
function Game.runKeys(seed: number, runs: number): { number }
	local r = Random.new((seed % 2147483646) + 7717)
	local out = {}
	for i = 1, #Game.keySpots() do
		local roll = r:NextNumber()
		if i == 1 then
			if runs < Game.Keys.OpeningRuns then table.insert(out, i) end
		elseif roll < Game.Keys.ZoneChance then
			table.insert(out, i)
		end
	end
	return out
end

-- where the keys sit on the road: one over the buffalo in the opening stretch, then one in every
-- zone, 40% of the way through it
Game.OpeningKey = 200
function Game.keySpots(): { number }
	local spots = { Game.OpeningKey }
	for i, z in ipairs(Game.Zones) do
		local nextStart = Game.Zones[i + 1] and Game.Zones[i + 1].start or (z.start + 1000)
		table.insert(spots, z.start + (nextStart - z.start) * 0.4)
	end
	return spots
end

-- the zones whose crates a player can open: any zone they've reached
function Game.cratePrice(zoneId: string): number
	local z = Game.ZonesById[zoneId]
	return z and z.keys or math.huge
end
-- Crates open two ways: with cash (the everyday way, priced by zone and yard stage) or with keys
-- (premium: Epic and up twice as likely, and every key crate counts toward the pity, a guaranteed
-- featured Legendary). Up to Game.Crate.MaxOpen at once.
Game.Crate = {
	MaxOpen = 10,
	Multi = 10,           -- the big open: this many at once, and one of them always Rare or better
	MultiFloor = "Rare",
	CashPity = 120,       -- cash crates without a Legendary or better, then the featured Legendary
	Cash = { backroad = 600, highway = 2000, dunes = 6000 },
	KeyLuck = 2,          -- key crates: Epic and up this much more likely
	Pity = 25,            -- key crates without a Legendary or better, then the featured Legendary
	BannerHours = 4,
	FeaturedMult = 3,     -- the banner's Legendary: this many times its odds, in every crate
	MythicMult = 2,       -- the banner's Mythic
}

-- what a zone's crate costs in cash at a yard stage (it grows with the stage, like the machines)
function Game.crateCash(zoneId: string, tier: number, v: any?): number
	local base = Game.Crate.Cash[zoneId] or 1000
	local t1 = Game.Tiers[1].price
	local tt = (Game.Tiers[math.clamp(tier, 1, #Game.Tiers)] or Game.Tiers[1]).price
	local raw = base * tt / t1 * Game.prestigeMult(Game.presOf(v)) ^ Game.Prestige.PriceExp
	local mag = 10 ^ math.max(0, math.floor(math.log10(raw)) - 1)
	return math.floor(raw / mag + 0.5) * mag
end

-- the banner: a featured Legendary and a featured Mythic, changing every BannerHours on a clock
-- every server shares (UTC): its index, the two tyre ids, the next Legendary, when it ends (os.time)
local LEGENDS, MYTHS = {}, {}
-- (2026-10-16) each crate features its own zone's Legendary (zoneId given); without a zone, the
-- old rotation through every Legendary. The Mythic rotates the same either way.
function Game.banner(now: number?, zoneId: string?)
	if #LEGENDS == 0 then
		for _, t in ipairs(Game.Tyres) do
			if t.zone ~= "retired" and t.rarity == "Legendary" then table.insert(LEGENDS, t.id) end
			if t.zone ~= "retired" and t.rarity == "Mythic" then table.insert(MYTHS, t.id) end
		end
	end
	local span = Game.Crate.BannerHours * 3600
	local idx = math.floor((now or os.time()) / span)
	local own = {}
	for _, t in ipairs(zoneId and Game.TyresByZone[zoneId] or {}) do
		if t.rarity == "Legendary" then table.insert(own, t.id) end
	end
	return {
		index = idx,
		legendary = if #own > 0 then own[idx % #own + 1] else LEGENDS[idx % #LEGENDS + 1],
		mythic = MYTHS[idx % math.max(1, #MYTHS) + 1],
		nextLegendary = LEGENDS[(idx + 1) % #LEGENDS + 1],
		ends = (idx + 1) * span,
	}
end

-- a zone's crate holds its six tyres; the mythics and secrets can drop from any crate; the banner's
-- Legendary drops from every crate at FeaturedMult its odds, its Mythic at MythicMult
function Game.crateOdds(zoneId: string, now: number?, featuredMult: number?): { { id: string, odds: number, featured: boolean? } }
	local b = Game.banner(now, zoneId)
	local list = {}
	local total = 0
	for _, t in ipairs(Game.TyresByZone[zoneId] or {}) do
		if t.id ~= b.legendary then
			local o = Game.RaritiesById[t.rarity].odds
			table.insert(list, { id = t.id, odds = o })
			total += o
		end
	end
	do
		local o = Game.RaritiesById.Legendary.odds * (featuredMult or Game.Crate.FeaturedMult)
		table.insert(list, { id = b.legendary, odds = o, featured = true })
		total += o
	end
	for _, t in ipairs(Game.TyresByZone.mythic or {}) do
		local o = Game.RaritiesById.Mythic.odds / #Game.TyresByZone.mythic * (t.id == b.mythic and Game.Crate.MythicMult or 1)
		table.insert(list, { id = t.id, odds = o, featured = t.id == b.mythic })
		total += o
	end
	for _, t in ipairs(Game.TyresByZone.secret) do
		local o = Game.RaritiesById.Secret.odds / #Game.TyresByZone.secret
		table.insert(list, { id = t.id, odds = o })
		total += o
	end
	for _, e in ipairs(list) do e.odds /= total end
	return list
end

--==============================================================
-- multipliers
--==============================================================
Game.Buy = { Cap = 4 }   -- bought multipliers never stack past this
Game.Friends = { PerFriend = 0.10, Max = 0.30 }

-- the launch tyre and the spares as entries ({ id, forge }), from a save's inventory
function Game.equipped(owned: { [number]: any }, launchUid: number?, spareUids: { number })
	local byUid = {}
	for _, t in pairs(owned) do byUid[t.uid] = t end
	local spares = {}
	for _, uid in ipairs(spareUids) do
		if byUid[uid] then table.insert(spares, byUid[uid]) end
	end
	return launchUid and byUid[launchUid] or nil, spares
end

-- the tyre bucket: 1 plus what every equipped tyre's multiplier adds over 1 (v4: the launch tyre
-- in full, each spare at Game.SpareCash of it, so a rack of luck can't skip the yard)
Game.SpareCash = 0.4
function Game.tyreBucket(owned: { [number]: any }, launchUid: number?, spareUids: { number }): number
	local launch, spares = Game.equipped(owned, launchUid, spareUids)
	local total = 1
	if launch then total += Game.tyreMult(launch.id, launch.forge, launch.mut) - 1 end
	for _, t in ipairs(spares) do total += (Game.tyreMult(t.id, t.forge, t.mut) - 1) * Game.SpareCash end
	return total
end

-- the login calendar: day 1..7 then round again (a missed UTC day starts it over)
Game.Daily = {
	{ cashRuns = 3 }, { keys = 1 }, { cashRuns = 5 }, { keys = 2 }, { cashRuns = 8 }, { keys = 3 }, { keys = 5, big = true },
}
function Game.utcDay(now: number?): number
	return math.floor((now or os.time()) / 86400)
end

-- the Index pays: every this many different tyres found, a key and +5% cash for good
Game.IndexEvery = 5
Game.IndexBonus = 0.05

-- the yard's auto-cannon: while you're in the server and not on a run, it fires on its own
-- (the Auto Launch pass makes it fire harder: PassShare)
-- (2026-10-24) MaxShare: with the pass, a style bonus and the idle perk the share reached 173% of the
-- run rate, so standing still paid better than playing; everything together stops at 75%
-- (PassShare 0.56: the pass says "60% more" than 0.35; 0.6 was 71%)
Game.AutoCannon = { Every = 30, Share = 0.35, PassShare = 0.56, MaxShare = 0.75 }

-- server events: one every Every seconds (on a clock every server shares), lasting Length
Game.Events = {
	Every = 25 * 60, Length = 5 * 60,
	List = {
		{ id = "tailwind", name = "Tailwind", text = "Launches fly 40% further", color = Color3.fromRGB(120, 210, 255) },
		{ id = "monsoon", name = "Monsoon", text = "Double coins, and Monsoon tyres drop", color = Color3.fromRGB(90, 160, 255) },
		{ id = "golden", name = "Golden Hour", text = "Every key on the road is worth 2", color = Color3.fromRGB(255, 206, 80) },
		{ id = "rush", name = "Legendary Rush", text = "The featured Legendary at x5", color = Color3.fromRGB(255, 120, 200) },
	},
}
Game.EventsById = {}
for _, e in ipairs(Game.Events.List) do Game.EventsById[e.id] = e end

-- the event on at a moment (or nil), the one coming next, and when it starts/ends (os.time)
function Game.eventAt(now: number?)
	local t = now or os.time()
	local E = Game.Events
	local idx = math.floor(t / E.Every)
	local start = idx * E.Every
	local pick = E.List[(idx * 7 + 3) % #E.List + 1]
	local nextPick = E.List[((idx + 1) * 7 + 3) % #E.List + 1]
	local on = t - start < E.Length
	return {
		on = on and pick or nil,
		ends = start + E.Length,
		nextEvent = nextPick,
		nextAt = start + E.Every,
		starts = start,
	}
end

-- heats: a race the whole server can join, on its own clock
Game.Heats = { Every = 150, Join = 30, Pay = { 1.0, 0.5, 0.25 }, TopKeys = 1, MinPlayers = 2 }

--==============================================================
-- time-based rewards
--==============================================================
-- (v4) while you're away the yard earns a share of your recent rate, for up to CapHours, raised by its
-- style (Game.styleBonus) and the Idle Hands perk
Game.Offline = { Share = 0.10, CapHours = 4 }

--==============================================================
-- numbers people read
--==============================================================
local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi" }
function Game.short(n: number): string
	n = math.floor(n + 0.5)
	if math.abs(n) < 1000 then return tostring(n) end
	local i = 1
	local v = n
	while math.abs(v) >= 1000 and i < #SUFFIX do
		v /= 1000
		i += 1
	end
	local s = math.abs(v) >= 100 and ("%d"):format(math.floor(v)) or (math.abs(v) >= 10 and ("%.1f"):format(v) or ("%.2f"):format(v))
	-- trailing zeros only come off a decimal ("1.50" -> "1.5", "2.00" -> "2"): a whole number keeps
	-- them (it used to strip them too, so 200M showed as "2M" and 120K as "12K")
	if s:find(".", 1, true) then
		s = (s:gsub("0+$", ""))
		s = (s:gsub("%.$", ""))
	end
	return s .. SUFFIX[i]
end

function Game.metres(m: number): string
	if m >= 10000 then return ("%.1f KM"):format(m / 1000) end
	local whole = tostring(math.floor(m + 0.5))
	-- thousands separators: 2000 -> "2,000"
	local spaced = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return spaced .. " M"
end

--==============================================================
-- the yard layout: what you can move, where it starts, the room it takes
--==============================================================
-- Plot space (the plot's BaseCFrame): +X runs out down the launch lane, the floor's top is at y 2.
-- A unit stands at (x, z) turned r quarter-turns; its footprint is one or more boxes round that
-- point ({x0, z0, x1, z1} at r = 0). Every box stays on the floor, clear of the stations that
-- don't move, and Gap studs clear of every other unit. Client (YardEdit) and server (Loop) both
-- check with Game.yardCheck.
Game.Yard = {
	Grid = 2,
	Gap = 2,
	Floor = { x0 = -33, z0 = -38, x1 = 73, z1 = 38 },
	Units = {
		-- the cannon and its ramp move as one: the shot has to go out over the ramp
		{ id = "launcher", name = "Launcher", machines = { { id = "cannon", x = 0 } },
			x = -8, z = 0, r = 0, boxes = { { -21, -11.5, 24, 11.5 } } },
		{ id = "fuel", name = "Fuel Tank", machines = { { id = "fuel", x = 0 } }, x = 30, z = 26, r = 2, boxes = { { -7.5, -7, 7.5, 7 } } },
		{ id = "cooling", name = "Cooling Tower", machines = { { id = "cooling", x = 0 } }, x = 52, z = 26, r = 2, boxes = { { -9, -8.5, 9, 8.5 } } },
		{ id = "compressor", name = "Compressor", machines = { { id = "compressor", x = 0 } }, x = 30, z = -26, r = 0, boxes = { { -10, -7, 10, 7 } } },
		{ id = "rack", name = "Spare Rack", machines = { { id = "rack", x = 0 } }, x = 54, z = -26, r = 0, boxes = { { -11.5, -5, 11.5, 5 } } },
	},
	-- what stays put: the workbench, the garage door, where you spawn home
	Fixed = {
		{ -0.5, -34.5, 8.5, -21.5 },
		{ -26, -37, -18, -29 },
		{ -18, 12, -14, 16 },
	},
}
-- the yard grows with its stage: wider each side and longer down the lane (the street edge, x0,
-- stays where it is). Stage 1 is the floor above; the plots have room round them for stage 5.
Game.YardGrowth = {
	{ z = 38, x1 = 73 }, { z = 44, x1 = 80 }, { z = 50, x1 = 88 }, { z = 55, x1 = 96 }, { z = 60, x1 = 104 },
}
-- the floor a yard at `tier` has (nil: the biggest, for reading anyone's layout)
function Game.yardFloor(tier: number?): { x0: number, z0: number, x1: number, z1: number }
	local g = Game.YardGrowth[math.clamp(math.floor(tier or #Game.YardGrowth), 1, #Game.YardGrowth)]
	return { x0 = Game.Yard.Floor.x0, z0 = -g.z, x1 = g.x1, z1 = g.z }
end

Game.YardUnits = {}
Game.YardUnitOf = {}	-- machine id -> its unit
for _, u in ipairs(Game.Yard.Units) do
	Game.YardUnits[u.id] = u
	for _, m in ipairs(u.machines) do Game.YardUnitOf[m.id] = u end
end

-- Decor: things you set round your yard to make it yours. Each kind is one of the game's own models
-- (path under Assets), the stage it unlocks at, and its footprint (half sizes, measured from the
-- model). How many you can set grows with the stage. Decor stays on the floor, clear of the machines
-- and the fixed stations, and clear of other decor.
Game.YardDecor = {
	{ id = "tyrestack", name = "Tyre Stack", path = "Lobby/TyreStack", tier = 1, hx = 2.4, hz = 2.4 },
	{ id = "oildrum", name = "Oil Drum", path = "Lobby/OilDrum", tier = 1, hx = 1.6, hz = 1.6 },
	{ id = "jack", name = "Trolley Jack", path = "Lobby/TrolleyJack", tier = 1, hx = 3.1, hz = 0.9 },
	{ id = "haybale", name = "Hay Bale", path = "Run/HayBale", tier = 1, hx = 3.7, hz = 3.4 },
	{ id = "mustard", name = "Mustard Patch", path = "Scenery/backroad/MustardPatch", tier = 1, hx = 3.7, hz = 4.0 },
	{ id = "fence", name = "Field Fence", path = "Scenery/backroad/Fence", tier = 1, hx = 8.7, hz = 1.1 },
	{ id = "tumbleweed", name = "Tumbleweed", path = "Scenery/dunes/Tumbleweed", tier = 1, hx = 1.9, hz = 1.9 },
	{ id = "mailbox", name = "Mailbox", path = "Scenery/backroad/Mailbox", tier = 1, hx = 1.8, hz = 1.1 },
	{ id = "tyrerack", name = "Tyre Rack", path = "Lobby/TyreRack", tier = 2, hx = 5.3, hz = 1.8 },
	{ id = "barrier", name = "Road Barrier", path = "Run/RoadBarrier", tier = 2, hx = 9.9, hz = 3.1 },
	{ id = "jersey", name = "Jersey Barrier", path = "Scenery/highway/JerseyBarrier", tier = 2, hx = 8.3, hz = 1.4 },
	{ id = "haystack", name = "Haystack", path = "Scenery/backroad/Kup", tier = 2, hx = 5.7, hz = 5.7 },
	{ id = "sodium", name = "Sodium Lamp", path = "Lobby/SodiumLamp", tier = 3, hx = 3.7, hz = 1.3 },
	{ id = "guardrail", name = "Guardrail", path = "Scenery/highway/Guardrail", tier = 3, hx = 8.1, hz = 1.0 },
	{ id = "streetlamp", name = "Street Lamp", path = "Scenery/highway/StreetLamp", tier = 3, hx = 4.3, hz = 1.4 },
	{ id = "roadsign", name = "Highway Sign", path = "Scenery/highway/HighwaySign", tier = 3, hx = 8.6, hz = 1.7 },
	{ id = "gantry", name = "Gantry Hoist", path = "Lobby/GantryHoist", tier = 4, hx = 7.9, hz = 3.6 },
	{ id = "poplar", name = "Poplar", path = "Scenery/backroad/Poplar", tier = 4, hx = 3.4, hz = 3.2 },
	{ id = "khejri", name = "Khejri Tree", path = "Scenery/dunes/Khejri", tier = 4, hx = 7.8, hz = 8.7 },
	{ id = "billboard", name = "Billboard", path = "Scenery/highway/Billboard", tier = 5, hx = 11.1, hz = 2.4 },
	{ id = "chhatri", name = "Chhatri", path = "Scenery/dunes/Chhatri", tier = 5, hx = 7.1, hz = 7.1 },
	-- the neon decor pack (2026-10-12): built in code (NeonDecor.luau). `prestige` pieces come with that
	-- prestige level, `pass` pieces with the Midnight Garage pass, the rest with their stage.
	{ id = "laurel", name = "Laurel Ring", build = true, tier = 1, prestige = 1, hx = 5.6, hz = 5.6 },
	{ id = "pillar", name = "Milestone Pillar", build = true, tier = 1, prestige = 2, hx = 1.6, hz = 1.6 },
	{ id = "podium", name = "Winner's Podium", build = true, tier = 1, prestige = 3, hx = 4.8, hz = 1.8 },
	{ id = "goldtyre", name = "Gold Tyre Statue", build = true, tier = 1, prestige = 5, hx = 2.6, hz = 1.6 },
	{ id = "crownarch", name = "Crown Arch", build = true, tier = 1, prestige = 10, hx = 5.6, hz = 1.0 },
	{ id = "prismbanner", name = "Prism Banner", build = true, tier = 1, prestige = 25, hx = 2.4, hz = 0.8 },
	{ id = "neonsign", name = "Neon Tyre Sign", build = true, tier = 1, pass = "midnight", hx = 3.4, hz = 0.9 },
	{ id = "neonarrow", name = "Neon Arrow", build = true, tier = 1, pass = "midnight", hx = 4.0, hz = 0.9 },
	{ id = "neonbump", name = "Neon Speed Bump", build = true, tier = 1, pass = "midnight", hx = 5.4, hz = 1.8 },
	{ id = "neonstack", name = "Neon Tyre Stack", build = true, tier = 1, pass = "midnight", hx = 2.4, hz = 2.4 },
	{ id = "neoncones", name = "Neon Cones", build = true, tier = 1, pass = "midnight", hx = 3.6, hz = 1.2 },
	{ id = "neonbarrier", name = "Neon Barrier", build = true, tier = 1, pass = "midnight", hx = 5.4, hz = 0.9 },
	{ id = "neonlamp", name = "Neon Lamp Post", build = true, tier = 1, pass = "midnight", hx = 2.8, hz = 0.9 },
	{ id = "checkerflag", name = "Checker Flag", build = true, tier = 1, pass = "midnight", hx = 2.6, hz = 0.8 },
	{ id = "neondrum", name = "Neon Oil Drum", build = true, tier = 2, hx = 1.6, hz = 1.6 },
	{ id = "litpallets", name = "Lit Pallet Stack", build = true, tier = 3, hx = 3.4, hz = 2.4 },
	{ id = "gaugesign", name = "Gauge Sign", build = true, tier = 4, hx = 2.6, hz = 0.8 },
	{ id = "bollards", name = "Neon Bollards", build = true, tier = 5, hx = 2.8, hz = 0.9 },
	-- the workshop set (2026-10-15): the game's own garage, yard and roadside models
	{ id = "toolbox", name = "Red Toolbox", path = "Workshop/ToolboxRed", tier = 1, hx = 1.6, hz = 0.9 },
	{ id = "toolboxblue", name = "Blue Toolbox", path = "Workshop/ToolboxBlue", tier = 1, hx = 1.6, hz = 0.9 },
	{ id = "tyrepile", name = "Tyre Pile", path = "World/Props/Tyres_Stacked_01", tier = 1, hx = 1.8, hz = 1.7 },
	{ id = "loosetyres", name = "Loose Tyres", path = "World/Props/Tyres_Scatter_01a", tier = 1, hx = 2.9, hz = 1.8 },
	{ id = "cone", name = "Traffic Cone", path = "World/Props/Cone_Striped", tier = 1, hx = 0.9, hz = 0.9 },
	{ id = "rustydrum", name = "Rusty Drum", path = "World/Props/OilDrum_2", tier = 1, hx = 1.3, hz = 1.3 },
	{ id = "anvil", name = "Anvil", path = "Workshop/Anvil", tier = 1, hx = 2.2, hz = 1.2 },
	{ id = "bucket", name = "Quench Bucket", path = "Workshop/QuenchBucket", tier = 1, hx = 1.9, hz = 1.9 },
	{ id = "boombox", name = "Boombox", path = "Workshop/Boombox", tier = 1, hx = 1.6, hz = 0.5 },
	{ id = "chair", name = "Camp Chair", path = "Props/Chair", tier = 1, hx = 1.5, hz = 2.3 },
	{ id = "workbench", name = "Workbench", path = "Workshop/Bench", tier = 2, hx = 1.9, hz = 6.1 },
	{ id = "wheelstand", name = "Wheel Stand", path = "Workshop/WheelStand", tier = 2, hx = 1.8, hz = 3.7 },
	{ id = "shelves", name = "Parts Shelves", path = "Workshop/Shelves", tier = 2, hx = 4.5, hz = 2.0 },
	{ id = "airpump", name = "Air Pump", path = "Lobby/AirPoint", tier = 2, hx = 1.3, hz = 1.3 },
	{ id = "tyrebundle", name = "Tyre Bundle", path = "World/Props/Tyres_Stacked_03", tier = 2, hx = 2.5, hz = 2.4 },
	{ id = "tarp", name = "Covered Project", path = "Garage/TarpCover", tier = 2, hx = 2.7, hz = 2.7 },
	{ id = "vending", name = "Vending Machine", path = "World/Obstacles/Vending", tier = 2, hx = 1.5, hz = 1.7 },
	{ id = "engine", name = "Car Engine", path = "World/Props/CarEngine", tier = 3, hx = 3.5, hz = 3.6 },
	{ id = "furnace", name = "Furnace", path = "Workshop/Furnace", tier = 3, hx = 2.4, hz = 2.3 },
	{ id = "waterpump", name = "Water Pump", path = "Scenery/backroad/TubeWell", tier = 3, hx = 3.8, hz = 2.6 },
	{ id = "wreck", name = "Car Wreck", path = "Scenery/dunes/Wreck", tier = 3, hx = 7.8, hz = 4.2 },
	{ id = "container", name = "Shipping Container", path = "World/Props/ShippingContainer", tier = 4, hx = 9.9, hz = 3.7 },
	{ id = "tractor", name = "Tractor", path = "Scenery/backroad/Tractor", tier = 4, hx = 6.6, hz = 5.1 },
	{ id = "floodmast", name = "Floodlight Mast", path = "Stages/FloodLight", tier = 5, hx = 3.7, hz = 2.0 },
	{ id = "truck", name = "Goods Truck", path = "Scenery/highway/GoodsTruck", tier = 5, hx = 10.5, hz = 3.3 },
	-- the Roadside Decor Pack (2026-10-15): built in code (RoadDecor.luau), from the Decor Pack 2 design canvas
	{ id = "planter", name = "Tyre Planter", build = true, tier = 1, hx = 2.5, hz = 2.5 },
	{ id = "milestone", name = "Milestone", build = true, tier = 1, hx = 1.6, hz = 0.9 },
	{ id = "charpai", name = "Charpai", build = true, tier = 1, hx = 3.9, hz = 1.9 },
	{ id = "matka", name = "Matka Stand", build = true, tier = 1, hx = 3.5, hz = 1.2 },
	{ id = "chaicart", name = "Chai Cart", build = true, tier = 2, hx = 4.5, hz = 2.0 },
	{ id = "tyreswing", name = "Tyre Swing", build = true, tier = 2, hx = 4.1, hz = 1.9 },
	{ id = "tyrepyramid", name = "Tyre Pyramid", build = true, tier = 2, hx = 4.7, hz = 0.8 },
	{ id = "toran", name = "Marigold Toran", build = true, tier = 2, hx = 5.7, hz = 0.7 },
	{ id = "scooter", name = "Old Scooter", build = true, tier = 3, hx = 3.2, hz = 1.2 },
	{ id = "toolwall", name = "Tool Wall", build = true, tier = 3, hx = 4.3, hz = 0.6 },
	{ id = "fuelpump", name = "Vintage Fuel Pump", build = true, tier = 4, hx = 2.2, hz = 1.3 },
	{ id = "hornok", name = "Honk Please", build = true, tier = 5, hx = 5.9, hz = 0.6 },
	-- the showroom (v4): your three best tyres on stands, for anyone walking past (NeonDecor builds it
	-- from the plot's V2_Showcase)
	{ id = "showcase", name = "Tyre Showcase", build = true, tier = 1, hx = 4.6, hz = 1.8 },
}
Game.YardDecorById = {}
for _, d in ipairs(Game.YardDecor) do Game.YardDecorById[d.id] = d end

-- the editor's drawer tabs: every decor kind sits in one (neon, prestige and pass pieces are "special")
Game.DecorCats = {
	{ id = "tools", name = "Tools" }, { id = "stock", name = "Stock" }, { id = "road", name = "Roadside" },
	{ id = "nature", name = "Nature" }, { id = "big", name = "Big" }, { id = "special", name = "Special" },
}
local DECOR_CAT = {
	jack = "tools", gantry = "tools", toolbox = "tools", toolboxblue = "tools", anvil = "tools", bucket = "tools", boombox = "tools",
	chair = "tools", workbench = "tools", wheelstand = "tools", shelves = "tools", airpump = "tools", furnace = "tools", waterpump = "tools",
	tyrestack = "stock", oildrum = "stock", tyrerack = "stock", tyrepile = "stock", loosetyres = "stock", rustydrum = "stock",
	tyrebundle = "stock", tarp = "stock", vending = "stock", engine = "stock",
	fence = "road", mailbox = "road", barrier = "road", jersey = "road", sodium = "road", guardrail = "road", streetlamp = "road",
	roadsign = "road", cone = "road", billboard = "road", floodmast = "road",
	haybale = "nature", mustard = "nature", tumbleweed = "nature", haystack = "nature", poplar = "nature", khejri = "nature", chhatri = "nature",
	wreck = "big", container = "big", tractor = "big", truck = "big",
	planter = "nature", tyreswing = "nature", toran = "nature", milestone = "road", fuelpump = "road", hornok = "road",
	charpai = "tools", toolwall = "tools", matka = "stock", chaicart = "stock", tyrepyramid = "stock", scooter = "big",
	showcase = "special",
}
for _, d in ipairs(Game.YardDecor) do
	(d :: any).cat = DECOR_CAT[d.id] or (if d.build then "special" else "stock")
end

--==============================================================
-- yard style (v4): why a yard is worth dressing. Every piece has style points (more for the later
-- stages, the prestige pieces and the pass); a second copy of the same piece counts half, a third a
-- quarter, so variety beats spam. Pieces that belong together are sets: all of a set in the yard is
-- a big bonus, and each week one set is the theme (its pieces count double, and finishing it pays
-- keys once that week). Floors, fences and looks add their own. The score is the yard's Style: it
-- shows on the plot's sign, it ranks the yards, and it raises what the auto-cannon and offline time
-- pay (Game.styleBonus), so a well-dressed yard earns while you're away.
--==============================================================
Game.DecorSets = {
	{ id = "dhaba", name = "Dhaba Stop", pieces = { "charpai", "chaicart", "matka", "toran", "planter" } },
	{ id = "workshop", name = "Workshop", pieces = { "toolbox", "anvil", "workbench", "toolwall", "shelves" } },
	{ id = "tyreshop", name = "Tyre Shop", pieces = { "tyrestack", "tyrepile", "tyrerack", "tyrepyramid", "wheelstand" } },
	{ id = "farm", name = "Farmyard", pieces = { "haybale", "haystack", "mustard", "poplar", "tractor" } },
	{ id = "highway", name = "Highway Crew", pieces = { "cone", "jersey", "barrier", "guardrail", "roadsign" } },
	{ id = "garage", name = "Back Garage", pieces = { "rustydrum", "oildrum", "engine", "tarp", "jack" } },
	{ id = "thar", name = "Thar Desert", pieces = { "tumbleweed", "khejri", "chhatri", "wreck" } },
	{ id = "truckstop", name = "Truck Stop", pieces = { "fuelpump", "vending", "hornok", "truck", "sodium" } },
	{ id = "hall", name = "Hall of Fame", pieces = { "laurel", "pillar", "podium", "goldtyre" } },
	{ id = "midnight", name = "Midnight Garage", pieces = { "neonsign", "neonarrow", "neonstack", "neoncones", "checkerflag" } },
}
Game.DecorSetsById = {}
Game.DecorSetOf = {}   -- decor id -> its set
for _, st in ipairs(Game.DecorSets) do
	Game.DecorSetsById[st.id] = st
	for _, k in ipairs(st.pieces) do Game.DecorSetOf[k] = st end
end
Game.Style = {
	SetBonus = 40,          -- a whole set in the yard
	ThemeKeys = 5,          -- finishing the week's theme set, once a week
	PerPointBonus = 0.001,  -- each style point: +0.1% auto-cannon and offline pay...
	MaxBonus = 0.6,         -- ...up to +60%
	LevelEvery = 50,        -- a style level every 50 points
}

-- a piece's style points
function Game.decorStyle(kind: any): number
	if not kind then return 0 end
	if kind.id == "showcase" then return 15 end
	if kind.prestige then return 20 end
	if kind.pass then return 12 end
	return 4 + 3 * (kind.tier or 1)
end

-- the set the week is themed on (the same for everyone, by UTC week; the pass and prestige sets
-- sit out, so the theme is something anyone can build)
function Game.styleTheme(week: number)
	local open = {}
	for _, st in ipairs(Game.DecorSets) do
		if st.id ~= "hall" and st.id ~= "midnight" then table.insert(open, st) end
	end
	return open[week % #open + 1]
end

-- a yard's style: the score, the sets it has whole, and how far into each set it is
-- (layout: Game.YardLayout; look: the look id; showman: the perk's level; week: Goals.utcWeek())
function Game.yardStyle(layout: any, look: string?, showman: number?, week: number?)
	local theme = Game.styleTheme(week or 0)
	local counts = {}
	local score = 0
	for _, d in ipairs((layout and layout.decor) or {}) do
		local kind = Game.YardDecorById[d.k]
		if kind then
			counts[d.k] = (counts[d.k] or 0) + 1
			local pts = Game.decorStyle(kind) * 0.5 ^ (counts[d.k] - 1)
			if theme and Game.DecorSetOf[d.k] == theme then pts *= 2 end
			score += pts
		end
	end
	local distinct = 0
	for _ in pairs(counts) do distinct += 1 end
	score += distinct * 2
	local sets = {}
	local whole = {}
	for _, st in ipairs(Game.DecorSets) do
		local have = 0
		for _, k in ipairs(st.pieces) do
			if counts[k] then have += 1 end
		end
		sets[st.id] = have
		if have >= #st.pieces then
			table.insert(whole, st.id)
			score += Game.Style.SetBonus * (if theme and st.id == theme.id then 1.5 else 1)
		end
	end
	local floor = layout and Game.YardFloorsById[layout.floor or "stage"]
	if floor and floor.id ~= "stage" then score += 6 * floor.tier end
	local fence = layout and Game.YardFencesById[layout.fence or "stage"]
	if fence and fence.id ~= "stage" and fence.id ~= "none" then score += 5 * fence.tier end
	if look == "midnight" then score += 35 elseif look == "prestige" then score += 25 end
	score *= 1 + 0.1 * (showman or 0)
	return { score = math.floor(score + 0.5), sets = sets, whole = whole, theme = theme and theme.id or nil }
end

function Game.styleLevel(score: number): number
	return math.floor((score or 0) / Game.Style.LevelEvery)
end

-- what a yard's style adds to its auto-cannon and offline pay (x1 .. x1.6)
function Game.styleBonus(score: number): number
	return 1 + math.min(Game.Style.MaxBonus, (score or 0) * Game.Style.PerPointBonus)
end

-- the yard's ground and fence (2026-10-15): "stage" follows the stage (PlotStage's own choice);
-- the rest unlock with the stage, like decor. Materials are Roblox's own; fences are the game's models.
Game.YardFloors = {
	{ id = "stage", name = "Stage Ground", tier = 1 },
	{ id = "dirt", name = "Dirt", tier = 1, mat = "Ground", variant = "TC_Dirt", color = Color3.fromRGB(255, 255, 255) },
	{ id = "grass", name = "Grass", tier = 1, mat = "Grass", color = Color3.fromRGB(106, 140, 66) },
	{ id = "sand", name = "Sand", tier = 1, mat = "Sand", color = Color3.fromRGB(214, 190, 140) },
	{ id = "gravel", name = "Gravel", tier = 2, mat = "Ground", variant = "TC_Gravel", color = Color3.fromRGB(255, 255, 255) },
	{ id = "planks", name = "Wood Planks", tier = 2, mat = "WoodPlanks", color = Color3.fromRGB(150, 112, 74) },
	{ id = "asphalt", name = "Asphalt", tier = 2, mat = "Asphalt", color = Color3.fromRGB(62, 62, 66) },
	{ id = "concrete", name = "Concrete", tier = 3, mat = "Concrete", color = Color3.fromRGB(176, 172, 164) },
	{ id = "brick", name = "Brick", tier = 3, mat = "Brick", color = Color3.fromRGB(150, 78, 58) },
	{ id = "cobble", name = "Cobblestone", tier = 3, mat = "Cobblestone", color = Color3.fromRGB(140, 136, 128) },
	{ id = "plate", name = "Diamond Plate", tier = 4, mat = "DiamondPlate", color = Color3.fromRGB(150, 154, 160) },
	{ id = "slate", name = "Slate", tier = 4, mat = "Slate", color = Color3.fromRGB(92, 96, 104) },
	{ id = "pavement", name = "Pavement", tier = 5, mat = "Pavement", color = Color3.fromRGB(196, 190, 178) },
}
Game.YardFences = {
	{ id = "stage", name = "Stage Fence", tier = 1 },
	{ id = "none", name = "No Fence", tier = 1 },
	{ id = "scrap", name = "Scrap Sheets", tier = 1, path = "Stages/ScrapFence" },
	{ id = "field", name = "Field Fence", tier = 1, path = "Scenery/backroad/Fence" },
	{ id = "chain", name = "Chain-link", tier = 2, path = "Lobby/ChainFence" },
	{ id = "guardrail", name = "Guardrail", tier = 2, path = "Scenery/highway/Guardrail" },
	{ id = "jersey", name = "Jersey Barriers", tier = 3, path = "Scenery/highway/JerseyBarrier" },
	{ id = "palisade", name = "Palisade", tier = 4, path = "Stages/PalisadeFence" },
}
Game.YardFloorsById, Game.YardFencesById = {}, {}
for _, f in ipairs(Game.YardFloors) do Game.YardFloorsById[f.id] = f end
for _, f in ipairs(Game.YardFences) do Game.YardFencesById[f.id] = f end

-- how many decor pieces a yard at `tier` can hold (a bigger yard holds more: 14, 20, 26, 32, 38)
function Game.yardDecorMax(tier: number?): number
	return 8 + 6 * math.clamp(math.floor(tier or 1), 1, 5)
end

export type YardSpot = { x: number, z: number, r: number }
-- decor turns in 15 degree steps: `a` is its angle in steps (0-23); `r` is the quarter turn under it
-- (kept for anything that still reads quarters, and for layouts saved before angles)
export type DecorSpot = { k: string, x: number, z: number, r: number, a: number? }
export type YardLayout = { [string]: any }

-- a unit's footprint boxes in plot space, standing at (x, z) turned r quarter-turns
function Game.yardBoxes(unitId: string, x: number, z: number, r: number): { { number } }
	local u = Game.YardUnits[unitId]
	local out = {}
	if not u then return out end
	local a = (r % 4) * math.pi / 2
	local c, s = math.cos(a), math.sin(a)
	for _, b in ipairs(u.boxes) do
		local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
		for _, p in ipairs({ { b[1], b[2] }, { b[3], b[2] }, { b[1], b[4] }, { b[3], b[4] } }) do
			-- the same turn as CFrame.Angles(0, a, 0)
			local px = p[1] * c + p[2] * s
			local pz = -p[1] * s + p[2] * c
			x0, z0, x1, z1 = math.min(x0, px), math.min(z0, pz), math.max(x1, px), math.max(z1, pz)
		end
		table.insert(out, { x + x0, z + z0, x + x1, z + z1 })
	end
	return out
end

-- a decor piece's angle in 15 degree steps (0-23)
function Game.decorAngle(d: DecorSpot): number
	if type(d.a) == "number" then return math.floor(d.a) % 24 end
	return (math.floor(d.r or 0) % 4) * 6
end

-- a decor piece's footprint box in plot space: the box round its footprint at its angle (at a
-- quarter turn it's the footprint itself)
function Game.decorBox(d: DecorSpot): { number }
	local k = Game.YardDecorById[d.k]
	local hx, hz = (k and k.hx or 1), (k and k.hz or 1)
	local th = math.rad(Game.decorAngle(d) * 15)
	local c, s = math.abs(math.cos(th)), math.abs(math.sin(th))
	if c < 1e-6 then c = 0 end
	if s < 1e-6 then s = 0 end
	local bx, bz = hx * c + hz * s, hx * s + hz * c
	return { d.x - bx, d.z - bz, d.x + bx, d.z + bz }
end

-- every unit's spot, taken from `raw` where it's a sensible number and the default otherwise; decor
-- is kept where it's a known kind, unlocked at `tier` (when given), up to the stage's allowance;
-- `access` ({ prestige, passes }) also drops decor its owner can't use (prestige and pass pieces)
function Game.yardLayout(raw: any, tier: number?, access: { prestige: number?, passes: { [string]: any }? }?): YardLayout
	local out = {}
	local Y = Game.Yard
	local F = Game.yardFloor(tier)
	for _, u in ipairs(Y.Units) do
		local e = type(raw) == "table" and raw[u.id] or nil
		local x, z, r = u.x, u.z, u.r
		if type(e) == "table" then
			local ex, ez, er = tonumber(e.x), tonumber(e.z), tonumber(e.r)
			if ex and ez and er and ex == ex and ez == ez then
				x = math.clamp(math.floor(ex / Y.Grid + 0.5) * Y.Grid, F.x0, F.x1)
				z = math.clamp(math.floor(ez / Y.Grid + 0.5) * Y.Grid, F.z0, F.z1)
				r = math.floor(er) % 4
			end
		end
		out[u.id] = { x = x, z = z, r = r }
	end
	local decor = {}
	local rd = type(raw) == "table" and raw.decor or nil
	if type(rd) == "table" then
		local max = Game.yardDecorMax(tier or 5)
		for _, e in ipairs(rd) do
			if #decor >= max then break end
			local kind = type(e) == "table" and Game.YardDecorById[tostring(e.k)] or nil
			local ex, ez, er = type(e) == "table" and tonumber(e.x), type(e) == "table" and tonumber(e.z), type(e) == "table" and tonumber(e.r)
			local ea = type(e) == "table" and tonumber(e.a) or nil
			if kind and ex and ez and er and ex == ex and ez == ez and (tier == nil or kind.tier <= tier)
				and (access == nil or Game.lookOpen(kind, access.prestige, access.passes)) then
				local a = if ea and ea == ea then math.floor(ea) % 24 else (math.floor(er) % 4) * 6
				table.insert(decor, {
					k = kind.id,
					x = math.clamp(math.floor(ex / Y.Grid + 0.5) * Y.Grid, F.x0, F.x1),
					z = math.clamp(math.floor(ez / Y.Grid + 0.5) * Y.Grid, F.z0, F.z1),
					r = a // 6,
					a = a,
				})
			end
		end
	end
	out.decor = decor
	local rf = type(raw) == "table" and Game.YardFloorsById[tostring(raw.floor)] or nil
	local rn = type(raw) == "table" and Game.YardFencesById[tostring(raw.fence)] or nil
	out.floor = if rf and (tier == nil or rf.tier <= tier) then rf.id else "stage"
	out.fence = if rn and (tier == nil or rn.tier <= tier) then rn.id else "stage"
	return out
end

local function overlap(a: { number }, b: { number }, gap: number): boolean
	return a[1] < b[3] + gap and b[1] < a[3] + gap and a[2] < b[4] + gap and b[2] < a[4] + gap
end

-- is the layout allowed on a yard at `tier` (nil: the biggest floor)? returns ok and the set of
-- units that are in the wrong place
function Game.yardCheck(layout: YardLayout, tier: number?): (boolean, { [string]: boolean })
	local Y = Game.Yard
	local F = Game.yardFloor(tier)
	local bad = {}
	local boxes = {}
	for _, u in ipairs(Y.Units) do
		local s = layout[u.id]
		boxes[u.id] = s and Game.yardBoxes(u.id, s.x, s.z, s.r) or {}
		for _, b in ipairs(boxes[u.id]) do
			if b[1] < F.x0 or b[3] > F.x1 or b[2] < F.z0 or b[4] > F.z1 then bad[u.id] = true end
			for _, f in ipairs(Y.Fixed) do
				if overlap(b, f, 0) then bad[u.id] = true end
			end
		end
	end
	for i, u in ipairs(Y.Units) do
		for j = i + 1, #Y.Units do
			local w = Y.Units[j]
			for _, a in ipairs(boxes[u.id]) do
				for _, b in ipairs(boxes[w.id]) do
					if overlap(a, b, Y.Gap) then
						bad[u.id] = true
						bad[w.id] = true
					end
				end
			end
		end
	end
	-- decor: on the floor, off the stations, a stud clear of the machines, not on other decor
	local decor = layout.decor or {}
	local dboxes = {}
	for i, d in ipairs(decor) do
		local b = Game.decorBox(d)
		dboxes[i] = b
		local id = "d" .. i
		if b[1] < F.x0 or b[3] > F.x1 or b[2] < F.z0 or b[4] > F.z1 then bad[id] = true end
		for _, f in ipairs(Y.Fixed) do
			if overlap(b, f, 0) then bad[id] = true end
		end
		for _, u in ipairs(Y.Units) do
			for _, ub in ipairs(boxes[u.id]) do
				-- (both of them: a machine carried onto decor is as wrong as decor put on a machine)
				if overlap(b, ub, 1) then
					bad[id] = true
					bad[u.id] = true
				end
			end
		end
		for j = 1, i - 1 do
			if overlap(b, dboxes[j], 0) then
				bad[id] = true
				bad["d" .. j] = true
			end
		end
	end
	return next(bad) == nil, bad
end

-- a layout made to fit a yard at `tier` (after a prestige the yard is stage 1 again): the stage's
-- rules applied, then any machine still in the wrong place back on its own spot and any decor still
-- in the wrong place taken off, until it passes (in the end: every machine home, no decor)
function Game.yardFit(raw: any, tier: number?, access: { prestige: number?, passes: { [string]: any }? }?): YardLayout
	local layout = Game.yardLayout(raw, tier, access)
	for _ = 1, 4 do
		local ok, bad = Game.yardCheck(layout, tier)
		if ok then return layout end
		for _, u in ipairs(Game.Yard.Units) do
			if bad[u.id] then layout[u.id] = { x = u.x, z = u.z, r = u.r } end
		end
		local keep = {}
		for i, d in ipairs(layout.decor or {}) do
			if not bad["d" .. i] then table.insert(keep, d) end
		end
		layout.decor = keep
	end
	if Game.yardCheck(layout, tier) then return layout end
	local home = Game.yardLayout(nil, tier, access)
	home.floor, home.fence = layout.floor, layout.fence
	return home
end

-- where a machine stands in plot space under a layout
function Game.yardSpot(layout: YardLayout, machineId: string): CFrame
	local u = Game.YardUnitOf[machineId]
	if not u then return CFrame.new() end
	local s = layout[u.id] or { x = u.x, z = u.z, r = u.r }
	local off = 0
	for _, m in ipairs(u.machines) do
		if m.id == machineId then off = m.x end
	end
	return CFrame.new(s.x, 2, s.z) * CFrame.Angles(0, (s.r % 4) * math.pi / 2, 0) * CFrame.new(off, 0, 0)
end

-- a layout as a short string for a plot attribute ("launcher:-8,0,0;fuel:30,26,2;..."), and back
function Game.yardEncode(layout: YardLayout): string
	local parts = {}
	for _, u in ipairs(Game.Yard.Units) do
		local s = layout[u.id]
		if s then table.insert(parts, ("%s:%d,%d,%d"):format(u.id, s.x, s.z, s.r)) end
	end
	local ds = {}
	for _, d in ipairs(layout.decor or {}) do table.insert(ds, ("%s,%d,%d,%d,%d"):format(d.k, d.x, d.z, d.r, Game.decorAngle(d))) end
	if #ds > 0 then table.insert(parts, "decor=" .. table.concat(ds, "|")) end
	if (layout.floor and layout.floor ~= "stage") or (layout.fence and layout.fence ~= "stage") then
		table.insert(parts, ("skin=%s,%s"):format(layout.floor or "stage", layout.fence or "stage"))
	end
	return table.concat(parts, ";")
end

function Game.yardDecode(str: string?): YardLayout
	local raw = {}
	for id, x, z, r in string.gmatch(str or "", "(%w+):(%-?[%d%.]+),(%-?[%d%.]+),(%d+)") do
		raw[id] = { x = tonumber(x), z = tonumber(z), r = tonumber(r) }
	end
	local d = string.match(str or "", "decor=([^;]*)")
	if d then
		raw.decor = {}
		-- (an angle after the quarter turn, when it was saved with one)
		for k, x, z, r, a in string.gmatch(d, "(%w+),(%-?[%d%.]+),(%-?[%d%.]+),(%d+),?(%d*)") do
			table.insert(raw.decor, { k = k, x = tonumber(x), z = tonumber(z), r = tonumber(r), a = tonumber(a) })
		end
	end
	raw.floor, raw.fence = string.match(str or "", "skin=(%w+),(%w+)")
	return Game.yardLayout(raw)
end

return Game
