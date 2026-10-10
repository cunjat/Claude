--!strict
-- TYRE CANNON :: Server / LoopData
-- The revamped loop's save data, kept under profile.v2 so the old profile cleaner leaves it
-- alone. Cash itself stays in profile.credits. Everything here is cleaned on load.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))

local LoopData = {}

LoopData.MAX_TYRES = 400
LoopData.MAX_SPARES = 4

function LoopData.default()
	return {
		keys = Game.Keys.StartWith,
		pity = 0,             -- key crates since the last Legendary or better (Game.Crate.Pity)
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
	d.testDrive = math.floor(num(raw.testDrive, 0, 1e12, 0))
	d.testArmed = raw.testArmed == true
	if type(raw.daily) == "table" then
		d.daily = { last = math.floor(num(raw.daily.last, 0, 1e7, 0)), streak = math.floor(num(raw.daily.streak, 0, 1e5, 0)) }
	end
	d.indexPaid = math.floor(num(raw.indexPaid, 0, 1e4, 0))
	return d
end

return LoopData
