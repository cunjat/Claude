--!strict
-- TYRE CANNON :: Progress
-- Pure rules shared by server and client: title unlocks, contracts and the
-- daily streak. The server decides; the client uses the same functions to
-- draw progress bars without asking.

local Config = require(script.Parent.Config)

local Progress = {}

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function trackName(id: string?): string
	local t = id and Config.TracksById[id]
	return t and t.name or "any track"
end

function Progress.today(): number
	return math.floor(os.time() / 86400)
end

--==============================================================
-- costs
--==============================================================
local CURRENCIES = { "credits", "bronze", "silver", "gold" }
Progress.Currencies = CURRENCIES

function Progress.balance(p, currency: string): number
	if currency == "credits" then return p.credits or 0 end
	return (p.metals and p.metals[currency]) or 0
end

function Progress.canAfford(p, cost): boolean
	for _, c in ipairs(CURRENCIES) do
		if (cost[c] or 0) > Progress.balance(p, c) then return false end
	end
	return true
end

--==============================================================
-- titles
--==============================================================
function Progress.statValue(p, cond): number
	local s = p.stats or {}
	if cond.stat == "trackBest" then
		return (s.trackBest and s.trackBest[cond.track]) or 0
	elseif cond.stat == "prestige" then
		return p.prestige or 0
	elseif cond.stat == "bestSpectators" then
		return (p.lifetime and p.lifetime.bestSpectators) or 0
	end
	return s[cond.stat] or 0
end

local STAT_TEXT = {
	runs = "Finish %s runs",
	redlineSeconds = "Spend %s seconds in the redline",
	upgrades = "Buy %s garage upgrades",
	bronze = "Pick up %s bronze",
	gold = "Pick up %s gold",
	flawless = "Pull off %s flawless launches",
	cleanRuns = "Reach checkpoint 3 without overheating or hitting anything, %s times",
	smashes = "Smash through %s obstacles",
	contracts = "Finish %s contracts",
	maxTier = "Reach checkpoint %s",
	longestAir = "Stay airborne %ss in one jump",
	bestSpectators = "Have %s people watch one run",
	codexMax = "Find all %s quirks",
	prestige = "Reach prestige %s",
	forgedLegendary = "Forge a legendary toolbox",
}
local LIVE_TEXT = {
	distance = "Hold a top %d spot on Longest Attempt",
	robux = "Hold a top %d spot on Robux Spent",
	richest = "Be the richest player in the server",
}

function Progress.titleHow(t): string
	if t.live then
		return (LIVE_TEXT[t.live.board] or "Hold rank %d"):format(t.live.rank)
	end
	local c = t.cond
	if c.stat == "trackBest" then
		return ("Roll %s m in one run on %s"):format(comma(c.goal * Config.Physics.StudsToMetres + 0.5), trackName(c.track))
	end
	return (STAT_TEXT[c.stat] or "%s"):format(comma(c.goal))
end

-- { unlocked, owned, equipped, current, goal, cost }
function Progress.titleState(p, t)
	local tier = Config.TitleTiers[t.tier]
	local st = {
		owned = (p.titles and p.titles[t.id]) == true,
		equipped = p.title == t.id,
		cost = tier and tier.cost or 1,
		current = 0,
		goal = 1,
	}
	if t.live then
		local rank = p.live and p.live[t.live.board]
		st.unlocked = type(rank) == "number" and rank >= 1 and rank <= t.live.rank
		st.current = st.unlocked and 1 or 0
		st.owned = st.unlocked
	else
		st.current = Progress.statValue(p, t.cond)
		st.goal = t.cond.goal
		st.unlocked = st.current >= st.goal
	end
	return st
end

--==============================================================
-- contracts
--==============================================================
local TRACKS = {}
for _, t in ipairs(Config.Tracks) do table.insert(TRACKS, t.id) end

local function pickTrack(rng: Random): string
	return TRACKS[rng:NextInteger(1, #TRACKS)]
end

local TEMPLATES = {
	{ id = "cp",
	  gen = function(rng) local n = rng:NextInteger(2, 5)
		return { n = n, track = pickTrack(rng), reward = { bronze = 10 + n * 6, silver = n >= 4 and 2 or 0 } } end,
	  text = function(c) return ("Reach checkpoint %d on %s"):format(c.n, trackName(c.track)) end,
	  check = function(c, s) return s.trackId == c.track and (s.tier or 0) >= c.n end },

	{ id = "noboost",
	  gen = function(rng) local n = rng:NextInteger(1, 3)
		return { n = n, reward = { bronze = 16 + n * 8, silver = n } } end,
	  text = function(c) return ("Reach checkpoint %d without touching boost"):format(c.n) end,
	  check = function(c, s) return (s.tier or 0) >= c.n and not s.boosted end },

	{ id = "air",
	  gen = function(rng) local n = rng:NextInteger(4, 9)
		return { n = n, reward = { bronze = 8 + n * 3, silver = n >= 7 and 2 or 1 } } end,
	  text = function(c) return ("Stay in the air for %d seconds in one jump"):format(c.n) end,
	  check = function(c, s) return (s.longestAir or 0) >= c.n end },

	{ id = "cool",
	  gen = function(rng) local n = rng:NextInteger(2, 5)
		return { n = n, reward = { bronze = 10 + n * 6, silver = n >= 4 and 2 or 1 } } end,
	  text = function(c) return ("Reach checkpoint %d without overheating"):format(c.n) end,
	  check = function(c, s) return (s.tier or 0) >= c.n and not s.overheated end },

	{ id = "redline",
	  gen = function(rng) local n = rng:NextInteger(3, 8) * 5
		return { n = n, reward = { bronze = 8 + n, silver = n >= 30 and 2 or 0 } } end,
	  text = function(c) return ("Spend %d seconds in the redline in one run"):format(c.n) end,
	  check = function(c, s) return (s.redlineSeconds or 0) >= c.n end },

	{ id = "quirks",
	  gen = function(rng) local n = rng:NextInteger(4, 10) * 2
		return { n = n, reward = { bronze = 10 + n } } end,
	  text = function(c) return ("Grab %d quirks in one run"):format(c.n) end,
	  check = function(c, s) return (s.perks or 0) >= c.n end },

	{ id = "smash",
	  gen = function(rng) local n = rng:NextInteger(2, 6)
		return { n = n, reward = { bronze = 12 + n * 4, silver = math.floor(n / 2) } } end,
	  text = function(c) return ("Smash through %d obstacles in one run"):format(c.n) end,
	  check = function(c, s) return (s.smashes or 0) >= c.n end },

	{ id = "metres",
	  gen = function(rng) local list = { 1500, 2500, 4000, 6000 }
		local i = rng:NextInteger(1, #list)
		return { n = list[i], track = pickTrack(rng), reward = { bronze = 8 + i * 8, silver = i >= 3 and i or 0, gold = i == 4 and 1 or 0 } } end,
	  text = function(c) return ("Roll %s m on %s"):format(comma(c.n), trackName(c.track)) end,
	  check = function(c, s) return s.trackId == c.track and (s.distance or 0) * Config.Physics.StudsToMetres >= c.n end },
}
local TEMPLATES_BY_ID = {}
for _, t in ipairs(TEMPLATES) do TEMPLATES_BY_ID[t.id] = t end

function Progress.generateContracts(userId: number, day: number)
	local rng = Random.new((userId % 1000003) * 31 + day * 7919 + 17)
	local pool = table.clone(TEMPLATES)
	local list = {}
	for _ = 1, math.min(Config.Contracts.PerDay, #pool) do
		local tpl = table.remove(pool, rng:NextInteger(1, #pool))
		local c = tpl.gen(rng)
		c.tpl = tpl.id
		c.done = false
		for k, v in pairs(c.reward) do if v <= 0 then c.reward[k] = nil end end
		table.insert(list, c)
	end
	return list
end

function Progress.contractText(c): string
	local tpl = TEMPLATES_BY_ID[c.tpl]
	return tpl and tpl.text(c) or "?"
end

function Progress.contractMet(c, summary): boolean
	local tpl = TEMPLATES_BY_ID[c.tpl]
	return tpl ~= nil and tpl.check(c, summary) == true
end

function Progress.rewardText(reward): string
	local bits = {}
	for _, cur in ipairs(CURRENCIES) do
		local v = reward[cur]
		if v and v > 0 then
			table.insert(bits, ("%s %s"):format(comma(v), cur == "credits" and "cr" or cur))
		end
	end
	return table.concat(bits, "  ·  ")
end

--==============================================================
-- daily streak
--==============================================================
-- returns claimable, dayIndex (1..7) that would be paid next
function Progress.dailyState(p)
	local today = Progress.today()
	local d = p.daily or { day = 0, streak = 0 }
	if d.day == today then
		return false, ((d.streak - 1) % #Config.Daily) + 1
	end
	local streak = (d.day == today - 1) and (d.streak + 1) or 1
	return true, ((streak - 1) % #Config.Daily) + 1, streak
end

Progress.comma = comma
return Progress
