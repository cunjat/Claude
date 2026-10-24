--!strict
-- TYRE CANNON :: Goals
-- The challenges the game sets, shared by server and client so both read the same targets:
--   Stage Trials  a stage-up (and a prestige) needs one challenge done on a run, on top of the
--                 cash: land PERFECTs, stay in the air, smash things, grab coins, run clean, go far.
--                 Which one comes up is fixed for each (prestige, stage), so every climb asks for
--                 something different; a run that falls short makes the next try a little easier
--                 (4% a try, never past 75% of the first target), so a trial is hard but never a wall.
--                 (2026-10-24, the owner: "make the challenges harder to rank up": higher targets
--                 at every stage, a steeper climb with each prestige, much less given back for misses)
--   Quests        three a day and one a week, rolled per player per day / week from the same kinds
--                 plus things done around the yard (open crates, buy levels, like yards, decorate).
--                 Each pays keys and a few minutes of your earnings; all three dailies, a bonus.
-- A run's numbers come from the server's own checked values (Loop's Finish), never the client's.
--   Goals.trial(pres, tier, tries, easier) -> goal ; Goals.dailies(uid, day, tier, best) -> { goal }
--   Goals.weekly(uid, week, tier) -> goal ; Goals.runValue(kind, run) ; Goals.text(goal) -> string

local Goals = {}

export type Goal = { k: string, t: number, h: number?, done: boolean? }

local function metres(m: number): string
	if m >= 10000 then return ("%.1f KM"):format(m / 1000) end
	local whole = tostring(math.floor(m + 0.5))
	return whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") .. " M"
end

-- what a run counts toward, in one run (the run's best is what counts)
Goals.RunKinds = {
	dist = { text = "Reach %s in one run", unit = "m", base = 2600, grow = 1.42, round = 100 },
	perfect = { text = "Land %d PERFECTs in one run", base = 4, step = 1.5, round = 1 },
	smash = { text = "Smash %d things in one run", base = 6, step = 3, round = 1 },
	air = { text = "Stay in the air %.1f s in one jump", unit = "s", base = 3, step = 0.6, round = 0.1 },
	coins = { text = "Grab %d coins in one run", base = 90, step = 35, round = 5 },
	clean = { text = "Reach %s without hitting anything", unit = "m", base = 1600, grow = 1.42, round = 100 },
}
Goals.TrialOrder = { "perfect", "dist", "air", "smash", "coins", "clean" }

-- what adds up over many runs and around the yard
Goals.CountKinds = {
	runs = { text = "Play %d runs" },
	km = { text = "Drive %d km in total", unit = "km" },
	perfects = { text = "Land %d PERFECTs" },
	smashes = { text = "Smash %d things" },
	coinsTotal = { text = "Grab %d coins" },
	crates = { text = "Open %d crates" },
	upgrades = { text = "Buy %d machine levels" },
	likes = { text = "Like %d other yards" },
	decor = { text = "Place %d new decor pieces" },
	best = { text = "Reach %s in one run", unit = "m", run = true },
}

local function roundTo(x: number, step: number): number
	return math.max(step, math.floor(x / step + 0.5) * step)
end

-- a run kind's target at a stage (1..5) and prestige
local function runTarget(kind: string, tier: number, pres: number): number
	local d = Goals.RunKinds[kind]
	local t = math.clamp(tier, 1, 5)
	local v
	if d.grow then
		v = d.base * d.grow ^ (t - 1)
	else
		v = d.base + (d.step or 0) * (t - 1)
	end
	v *= 1 + 0.08 * math.min(pres, 25)
	return roundTo(v, d.round or 1)
end

-- the trial for moving up from `tier` (tier 5: the trial before a prestige). `tries` runs have
-- fallen short (each takes 4% off, down to 75%); `easier` is the Trial Runner perk's levels.
function Goals.trial(pres: number, tier: number, tries: number?, easier: number?): Goal
	local n = #Goals.TrialOrder
	-- the same order every climb, shifted by the prestige, so no two climbs ask the same things
	local kind = Goals.TrialOrder[((tier - 1) + pres * 2) % n + 1]
	local base = runTarget(kind, tier, pres)
	local k = math.max(0.75, 1 - 0.04 * (tries or 0)) * (1 - 0.1 * (easier or 0))
	local d = Goals.RunKinds[kind]
	return { k = kind, t = roundTo(base * k, d.round or 1) }
end

-- the run's value for a run kind (run = the server's checked numbers)
function Goals.runValue(kind: string, run: { [string]: number }): number
	if kind == "dist" then return run.metres or 0 end
	if kind == "perfect" then return run.perfects or 0 end
	if kind == "smash" then return run.smashes or 0 end
	if kind == "air" then return run.longestAir or 0 end
	if kind == "coins" then return run.coins or 0 end
	if kind == "clean" then return if (run.hits or 0) == 0 then (run.metres or 0) else 0 end
	if kind == "best" then return run.metres or 0 end
	return 0
end

-- three dailies (different kinds), rolled from the player and the UTC day
local DAILY_POOL = {
	{ k = "runs", t = 8 }, { k = "km", t = 12 }, { k = "perfects", t = 12 }, { k = "smashes", t = 15 },
	{ k = "coinsTotal", t = 300 }, { k = "crates", t = 3 }, { k = "upgrades", t = 6 },
	{ k = "decor", t = 2 }, { k = "best", t = 0 },
}
local WEEKLY_POOL = {
	{ k = "runs", t = 60 }, { k = "km", t = 90 }, { k = "perfects", t = 80 }, { k = "crates", t = 20 },
	{ k = "likes", t = 10 }, { k = "upgrades", t = 40 },
}

function Goals.dailies(uid: number, day: number, tier: number, best: number): { Goal }
	local r = Random.new((uid % 1000003) * 31 + day * 7919)
	local pool = table.clone(DAILY_POOL)
	local out = {}
	while #out < 3 and #pool > 0 do
		local q = table.remove(pool, r:NextInteger(1, #pool))
		local t = q.t
		if q.k == "km" then t = q.t + 4 * (tier - 1) end
		if q.k == "best" then t = roundTo(math.max(1500, best * 0.85), 100) end
		table.insert(out, { k = q.k, t = t, h = 0, done = false })
	end
	return out
end

function Goals.weekly(uid: number, week: number, tier: number): Goal
	local r = Random.new((uid % 1000003) * 17 + week * 104729)
	local q = WEEKLY_POOL[r:NextInteger(1, #WEEKLY_POOL)]
	local t = q.t
	if q.k == "km" then t = q.t + 20 * (tier - 1) end
	return { k = q.k, t = t, h = 0, done = false }
end

-- the goal in words
function Goals.text(g: Goal): string
	local d = Goals.RunKinds[g.k] or Goals.CountKinds[g.k]
	if not d then return g.k end
	if d.unit == "m" then return d.text:format(metres(g.t)) end
	if d.unit == "s" then return d.text:format(g.t) end
	return d.text:format(g.t)
end

-- "1,240 / 2,000 M", "2 / 4"
function Goals.progressText(g: Goal, have: number?): string
	local h = have or g.h or 0
	local d = Goals.RunKinds[g.k] or Goals.CountKinds[g.k]
	if d and d.unit == "m" then return ("%s / %s"):format((metres(math.min(h, g.t)):gsub(" M$", "")), metres(g.t)) end
	if d and d.unit == "s" then return ("%.1f / %.1f s"):format(math.min(h, g.t), g.t) end
	return ("%d / %d"):format(math.floor(math.min(h, g.t)), g.t)
end

-- the UTC week (Monday 00:00), for the weekly quest and the yard theme
function Goals.utcWeek(now: number?): number
	return math.floor(((now or os.time()) / 86400 + 3) / 7)
end

-- quest rewards: keys, and minutes of the player's recent earnings
-- (2026-10-16: keys are rare) a daily pays mostly cash; the set of three and the weekly pay keys
Goals.DailyReward = { keys = 0, minutes = 5 }
Goals.DailyBonus = { keys = 2 }
Goals.WeeklyReward = { keys = 5, minutes = 20 }

return Goals
