--!strict
-- TYRE CANNON :: Server / LoopData
-- The revamped loop's save data, kept under profile.v2 so the old profile cleaner leaves it
-- alone. Cash itself stays in profile.credits. Everything here is cleaned on load.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))

local LoopData = {}

LoopData.MAX_TYRES = 400
-- (2026-10-18: the most spare slots there are: 1 + a maxed rack's 4 + the pass's 2. It was 4, so a
-- load cut a bigger rack back and the +2 pass stopped paying after one rejoin)
LoopData.MAX_SPARES = 7

function LoopData.default()
	return {
		keys = Game.Keys.StartWith,
		pity = 0,             -- key crates since the last Legendary or better (Game.Crate.Pity)
		cashPity = 0,         -- cash crates since the last Legendary or better (Game.Crate.CashPity)
		mach = { cannon = 0, fuel = 0, cooling = 0, compressor = 0, rack = 0 },
		tier = 1,
		overhauls = 0,
		reached = 0,          -- furthest metres on this plot tier (overhauls need it)
		bestEver = 0,
		zones = { backroad = true },
		inv = { { uid = 1, id = Game.StarterTyre, forge = 0 } },
		nextUid = 2,
		launch = 1,
		spares = {},
		index = { [Game.StarterTyre] = true },
		runs = 0,
		lastSeen = 0,
		rate = 0,             -- recent cash per minute while playing, for the compressor
		passes = {},
		boosts = {},          -- [id] = os.time() it runs out
		designs = {},         -- [tostring(uid)] = Tyre Studio design
		layout = nil,         -- where the yard's machines stand (Game.Yard); nil = the default
		started = false,      -- has had the scripted first run
		-- v3
		testDrive = 0,        -- os.time() of the last Test Drive of the featured Legendary
		testArmed = false,    -- the next run is a Test Drive
		daily = { last = 0, streak = 0 },   -- the login calendar: the UTC day last claimed, the run of days
		indexPaid = 0,        -- Index milestones paid out (one every Game.IndexEvery tyres found)
		-- Server/Career: level, XP, the counters titles read, the titles you own
		career = { xp = 0, level = 1, upgrades = 0, crates = 0, perfects = 0, heatWins = 0, maxStage = 1, titles = {} },
		look = { id = "stage", way = "Midnight" },   -- the yard's look (Game.YardLooks) and the Midnight Garage colourway
		-- v4 (2026-10-16)
		pres = 0,             -- profile.prestige mirrored here, so prices read it from the save (Game.priceScale)
		perks = {},           -- [perk id] = level (Game.Perks)
		perkOffer = nil,      -- the perks offered at the last prestige, until one's picked
		trial = nil,          -- this stage's trial (Goals.trial): { key, k, t, tries, best, done }
		quests = { day = 0, list = {}, bonus = false, week = 0, wk = nil },
		likes = { week = 0, n = 0 },          -- likes this yard got this week
		liked = { day = 0, to = {} },         -- yards this player liked today (owner userId -> true)
		likeKeys = { day = 0, n = 0 },        -- keys from likes today (capped)
		style = 0,            -- the yard's style score (Game.yardStyle), kept for the sign and the boards
		themeWeek = 0,        -- the week whose theme set last paid out
		premDay = 0,          -- the UTC day a Premium member's daily key was last paid
	}
end

local function num(v: any, lo: number, hi: number, default: number): number
	local x = tonumber(v)
	if not x or x ~= x then return default end
	return math.clamp(x, lo, hi)
end

function LoopData.sanitize(raw: any)
	local d = LoopData.default()
	if type(raw) ~= "table" then return d end
	d.keys = math.floor(num(raw.keys, 0, 1e6, d.keys))
	d.pity = math.floor(num(raw.pity, 0, 1e4, 0))
	d.cashPity = math.floor(num(raw.cashPity, 0, 1e5, 0))
	if type(raw.mach) == "table" then
		for id in pairs(d.mach) do
			d.mach[id] = math.floor(num(raw.mach[id], 0, Game.maxLevel(id), 0))
		end
	end
	d.tier = math.floor(num(raw.tier, 1, #Game.Tiers, 1))
	d.overhauls = math.floor(num(raw.overhauls, 0, 1e4, 0))
	d.reached = num(raw.reached, 0, 1e7, 0)
	d.bestEver = num(raw.bestEver, 0, 1e7, 0)
	if type(raw.zones) == "table" then
		for id, v in pairs(raw.zones) do
			if v == true and Game.ZonesById[id] then d.zones[id] = true end
		end
	end
	if type(raw.inv) == "table" then
		d.inv = {}
		local seen = {}
		for _, t in ipairs(raw.inv) do
			if #d.inv >= LoopData.MAX_TYRES then break end
			if type(t) == "table" and type(t.id) == "string" and Game.TyresById[t.id] then
				local uid = math.floor(num(t.uid, 1, 1e9, 0))
				if uid > 0 and not seen[uid] then
					seen[uid] = true
					local mut = (type(t.mut) == "string" and Game.MutationsById[t.mut]) and t.mut or nil
					table.insert(d.inv, { uid = uid, id = t.id, forge = math.floor(num(t.forge, 0, 3, 0)), mut = mut, fav = t.fav == true or nil })
				end
			end
		end
		if #d.inv == 0 then d.inv = { { uid = 1, id = Game.StarterTyre, forge = 0 } } end
	end
	local maxUid = 0
	local owned = {}
	for _, t in ipairs(d.inv) do
		maxUid = math.max(maxUid, t.uid)
		owned[t.uid] = true
	end
	d.nextUid = math.max(math.floor(num(raw.nextUid, 1, 1e9, 1)), maxUid + 1)
	d.launch = owned[tonumber(raw.launch) or -1] and math.floor(raw.launch) or d.inv[1].uid
	d.spares = {}
	if type(raw.spares) == "table" then
		for _, uid in ipairs(raw.spares) do
			local u = tonumber(uid)
			if u and owned[u] and u ~= d.launch and #d.spares < LoopData.MAX_SPARES and not table.find(d.spares, u) then
				table.insert(d.spares, u)
			end
		end
	end
	if type(raw.index) == "table" then
		for id, v in pairs(raw.index) do
			if v == true and Game.TyresById[id] then d.index[id] = true end
		end
	end
	d.runs = math.floor(num(raw.runs, 0, 1e9, 0))
	d.lastSeen = math.floor(num(raw.lastSeen, 0, 1e12, 0))
	d.rate = num(raw.rate, 0, 1e15, 0)
	if type(raw.passes) == "table" then
		for id, v in pairs(raw.passes) do
			if type(id) == "string" and v == true then d.passes[id] = true end
		end
	end
	if type(raw.boosts) == "table" then
		for id, v in pairs(raw.boosts) do
			if type(id) == "string" then d.boosts[id] = math.floor(num(v, 0, 1e12, 0)) end
		end
	end
	if type(raw.designs) == "table" then
		for uid, des in pairs(raw.designs) do
			if owned[tonumber(uid) or -1] and type(des) == "table" then d.designs[tostring(uid)] = des end
		end
	end
	if type(raw.layout) == "table" then
		local layout = Game.yardLayout(raw.layout)
		if Game.yardCheck(layout) then d.layout = layout end
	end
	d.started = raw.started == true
	if type(raw.look) == "table" then
		local id = tostring(raw.look.id)
		d.look.id = Game.YardLooksById[id] and id or "stage"
		d.look.way = Game.yardWay(tostring(raw.look.way)).id
	end
	d.testDrive = math.floor(num(raw.testDrive, 0, 1e12, 0))
	d.testArmed = raw.testArmed == true
	d.testTyre = if type(raw.testTyre) == "string" and #raw.testTyre <= 32 then raw.testTyre else nil
	if type(raw.daily) == "table" then
		d.daily = { last = math.floor(num(raw.daily.last, 0, 1e7, 0)), streak = math.floor(num(raw.daily.streak, 0, 1e5, 0)) }
	end
	d.indexPaid = math.floor(num(raw.indexPaid, 0, 1e4, 0))
	-- v4
	d.pres = math.floor(num(raw.pres, 0, Game.Prestige.Max, 0))
	if type(raw.perks) == "table" then
		for id, lv in pairs(raw.perks) do
			local pk = Game.PerksById[id]
			if pk then d.perks[id] = math.floor(num(lv, 0, pk.max, 0)) end
		end
	end
	if type(raw.perkOffer) == "table" then
		local offer = {}
		for _, id in ipairs(raw.perkOffer) do
			if type(id) == "string" and Game.PerksById[id] and #offer < Game.Prestige.Choices then table.insert(offer, id) end
		end
		d.perkOffer = if #offer > 0 then offer else nil
	end
	if type(raw.trial) == "table" and type(raw.trial.k) == "string" then
		local t = raw.trial
		d.trial = {
			key = tostring(t.key or ""), k = t.k, t = num(t.t, 0, 1e7, 0), tries = math.floor(num(t.tries, 0, 1e4, 0)),
			best = num(t.best, 0, 1e7, 0), done = t.done == true,
		}
	end
	if type(raw.quests) == "table" then
		local q = raw.quests
		local function goal(g: any)
			if type(g) ~= "table" or type(g.k) ~= "string" then return nil end
			return { k = g.k, t = num(g.t, 0, 1e9, 1), h = num(g.h, 0, 1e9, 0), done = g.done == true }
		end
		d.quests.day = math.floor(num(q.day, 0, 1e7, 0))
		d.quests.week = math.floor(num(q.week, 0, 1e6, 0))
		d.quests.bonus = q.bonus == true
		if type(q.list) == "table" then
			for _, g in ipairs(q.list) do
				local gg = goal(g)
				if gg and #d.quests.list < 3 then table.insert(d.quests.list, gg) end
			end
		end
		d.quests.wk = goal(q.wk)
	end
	if type(raw.likes) == "table" then
		d.likes = { week = math.floor(num(raw.likes.week, 0, 1e6, 0)), n = math.floor(num(raw.likes.n, 0, 1e7, 0)) }
	end
	if type(raw.liked) == "table" then
		d.liked.day = math.floor(num(raw.liked.day, 0, 1e7, 0))
		if type(raw.liked.to) == "table" then
			local n = 0
			for uid, on in pairs(raw.liked.to) do
				n += 1
				if n > 200 then break end
				if on == true then d.liked.to[tostring(uid)] = true end
			end
		end
	end
	if type(raw.likeKeys) == "table" then
		d.likeKeys = { day = math.floor(num(raw.likeKeys.day, 0, 1e7, 0)), n = math.floor(num(raw.likeKeys.n, 0, 100, 0)) }
	end
	d.premDay = math.floor(num(raw.premDay, 0, 1e7, 0))
	d.style = math.floor(num(raw.style, 0, 1e6, 0))
	d.themeWeek = math.floor(num(raw.themeWeek, 0, 1e6, 0))
	if type(raw.career) == "table" then
		local c = raw.career
		local cr = d.career
		cr.level = math.floor(num(c.level, 1, Game.Levels.Max, 1))
		cr.xp = math.floor(num(c.xp, 0, 1e9, 0))
		for _, k in ipairs({ "upgrades", "crates", "perfects", "heatWins" }) do
			cr[k] = math.floor(num(c[k], 0, 1e9, 0))
		end
		cr.maxStage = math.floor(num(c.maxStage, 1, #Game.Tiers, 1))
		if type(c.titles) == "table" then
			local n = 0
			for id, on in pairs(c.titles) do
				if on == true and type(id) == "string" and #id <= 32 then
					n += 1
					if n > 100 then break end
					cr.titles[id] = true
				end
			end
		end
	end
	-- (2026-10-22) the lost lug nuts found today (HubHunt): the day and a bit per spot
	if type(raw.hunt) == "table" then
		d.hunt = { day = math.floor(num(raw.hunt.day, 0, 1e7, 0)), mask = math.floor(num(raw.hunt.mask, 0, 63, 0)) }
	end
	return d
end

return LoopData
