--!strict
-- TYRE CANNON :: Server / Profile
-- Profile shape, cleaning and persistence. A profile that failed to load is
-- flagged by the caller and never saved, so a DataStore outage can't wipe
-- anyone's progress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Config"))

local LoopData = require(script.Parent.LoopData)

local Profile = {}

Profile.MAX_LOADOUT = 2
Profile.MAX_GIFTS = 20
Profile.MAX_PHOTOS = 6
Profile.STAT_KEYS = {
	"runs", "perfectPumps", "upgrades", "bronze", "silver", "gold", "flawless",
	"flowMaxed", "smashes", "contracts", "maxTier", "longestAir", "codexMax",
	"forged", "forgedLegendary", "drafts", "redlineSeconds", "cleanRuns", "overheats", "hits",
}

function Profile.default()
	local stats: { [string]: any } = { trackBest = {} }
	for _, k in ipairs(Profile.STAT_KEYS) do stats[k] = 0 end
	return {
		v = 2,
		credits = Config.Economy.StartingCredits,
		metals = { bronze = 0, silver = 0, gold = 0 },
		upgrades = {},
		tracks = { backroad = true },
		records = {},
		codex = {},
		totals = { runs = 0, distance = 0, credits = 0, perks = 0, airtime = 0 },
		selected = "backroad",
		charms = {},
		loadout = {},
		boosters = {},
		pressure = Config.Pressure.Default,
		skins = { stock = true }, skin = "stock",
		trails = { none = true }, trail = "none",
		rims = { steel = true }, rim = "steel",
		rigs = { works = true }, rigSkin = "works",
		generators = { field = true }, generator = "field",
		prestige = 0,
		tokens = 0,
		tokenUpgrades = {},
		permanent = { skins = {}, trails = {}, rims = {}, rigs = {}, generators = {} },
		toolboxes = {},
		equipped = {},
		nextToolUid = 1,
		titles = {},
		title = "",
		stickers = {},				-- { id, side, u, v, rot, scale }
		stats = stats,
		contracts = { day = 0, list = {} },
		daily = { day = 0, streak = 0 },
		lifetime = { bestDistance = 0, credits = 0, robux = 0, bestSpectators = 0 },
		tutorial = false,
		tutStep = 0,
		prefs = table.clone(Config.PrefDefaults),
		gifts = {},					-- { uid, kind, id, from, fromId, at } waiting on the bench
		nextGiftUid = 1,
		honks = 0,					-- honks other players gave your yard
		photos = {},				-- end-of-run photos, newest first
		tyreLog = {},				-- [skin id] = { runs, dist, best } for every tyre you've run on
		ghosts = {},				-- [track id] = { d = recorded best run, s = gate split times }
		guestbook = {},				-- { name, fromId, stamp, at } left by visitors, newest first
		bay = { unlocked = false, skin = "stock", rim = "steel", trail = "none", stickers = {} },
		receipts = {},				-- PurchaseIds of the last 50 Robux products granted, newest first
		growth = { referredBy = 0, refPaid = false, group = false },	-- Server/Growth: who invited you, paid them, group reward
		v2 = LoopData.default(),	-- the revamped loop (machines, keys, tyres)
	}
end

-- A setting as it may be saved: returns ok and the clean value.
function Profile.cleanPref(key: string, v: any): (boolean, any)
	local def = (Config.PrefDefaults :: any)[key]
	if def == nil then return false, nil end
	if key == "dance" then
		return type(v) == "string" and Config.VictoryDancesById[v] ~= nil, v
	elseif key == "doorPaint" then
		return type(v) == "string" and Config.DoorPaintsById[v] ~= nil, v
	elseif key == "doorStencil" then
		return type(v) == "string" and Config.DoorStencilsById[v] ~= nil, v
	elseif key == "camera" then
		return v == "chase" or v == "first", v
	elseif key == "rigName" then
		if type(v) ~= "string" then return false, nil end
		return true, v:sub(1, Config.RigName.MaxLength)
	elseif key == "tips" then
		if type(v) ~= "string" then return false, nil end
		return true, (string.gsub(v, "[^%w_,]", "")):sub(1, 300)
	elseif key == "uiScale" then
		local x = tonumber(v)
		if x == nil or x ~= x then return false, nil end
		return true, math.clamp(x, 0.85, 1.15)
	elseif type(def) == "boolean" then
		return type(v) == "boolean", v
	elseif type(def) == "number" then
		local x = tonumber(v)
		if x == nil or x ~= x then return false, nil end
		return true, math.clamp(x, 0, 1)
	end
	return false, nil
end

local function num(v: any, lo: number, hi: number, default: number): number
	local x = tonumber(v)
	if x == nil or x ~= x then return default end
	return math.clamp(x, lo, hi)
end

local function loadSet(src: any, dst: { [string]: boolean }, lookup: { [string]: any })
	if type(src) ~= "table" then return end
	for id, v in pairs(src) do
		if type(id) == "string" and lookup[id] and v then dst[id] = true end
	end
end

function Profile.sanitize(raw: any)
	local d = Profile.default()
	if type(raw) ~= "table" then return d end
	local p = raw

	-- (2026-10-24) the same cap as in a session (Loop: 1e15); 1e12 here cut a rich save to $1T on rejoin
	d.credits = num(p.credits, 0, 1e15, d.credits)
	if type(p.metals) == "table" then
		for k in pairs(d.metals) do d.metals[k] = math.floor(num(p.metals[k], 0, 1e7, 0)) end
	end
	if type(p.upgrades) == "table" then
		for id, lvl in pairs(p.upgrades) do
			local u = Config.UpgradesById[id]
			if u then d.upgrades[id] = math.floor(num(lvl, 0, u.maxLevel, 0)) end
		end
	end
	loadSet(p.tracks, d.tracks, Config.TracksById)
	if type(p.records) == "table" then
		for id, r in pairs(p.records) do
			if Config.TracksById[id] and type(r) == "table" then
				d.records[id] = { dist = num(r.dist, 0, 1e7, 0), credits = num(r.credits, 0, 1e9, 0), runs = num(r.runs, 0, 1e7, 0) }
			end
		end
	end
	loadSet(p.codex, d.codex, Config.PerksById)
	if type(p.totals) == "table" then
		for k in pairs(d.totals) do d.totals[k] = num(p.totals[k], 0, 1e13, 0) end
	end
	if type(p.selected) == "string" and d.tracks[p.selected] then d.selected = p.selected end

	if type(p.charms) == "table" then
		for id, c in pairs(p.charms) do
			if Config.CharmsById[id] then
				local v = math.floor(num(c, 0, 999, 0))
				if v > 0 then d.charms[id] = v end
			end
		end
	end
	if type(p.loadout) == "table" then
		for _, id in ipairs(p.loadout) do
			if Config.CharmsById[id] and #d.loadout < Profile.MAX_LOADOUT then table.insert(d.loadout, id) end
		end
	end
	if type(p.boosters) == "table" then
		for id, v in pairs(p.boosters) do
			if Config.BoostersById[id] then
				local x = math.floor(num(v, 0, 1e6, 0))
				if x > 0 then d.boosters[id] = x end
			end
		end
	end
	d.pressure = math.floor(num(p.pressure, 0, 100, d.pressure))

	loadSet(p.skins, d.skins, Config.SkinsById)
	loadSet(p.trails, d.trails, Config.TrailsById)
	loadSet(p.rims, d.rims, Config.RimsById)
	loadSet(p.rigs, d.rigs, Config.RigSkinsById)
	loadSet(p.generators, d.generators, Config.GeneratorsById)
	if type(p.permanent) == "table" then
		loadSet(p.permanent.skins, d.permanent.skins, Config.SkinsById)
		loadSet(p.permanent.trails, d.permanent.trails, Config.TrailsById)
		loadSet(p.permanent.rims, d.permanent.rims, Config.RimsById)
		loadSet(p.permanent.rigs, d.permanent.rigs, Config.RigSkinsById)
		loadSet(p.permanent.generators, d.permanent.generators, Config.GeneratorsById)
	end
	-- equipped items are checked only after BOTH owned sets are loaded
	local function equip(field: string, cat: string)
		local v = p[field]
		if type(v) == "string" and ((d :: any)[cat][v] or (d.permanent :: any)[cat][v]) then (d :: any)[field] = v end
	end
	equip("skin", "skins")
	equip("trail", "trails")
	equip("rim", "rims")
	equip("rigSkin", "rigs")
	equip("generator", "generators")

	d.prestige = math.floor(num(p.prestige, 0, Config.Prestige.MaxLevel, 0))
	d.tokens = math.floor(num(p.tokens, 0, 9999, 0))
	if type(p.tokenUpgrades) == "table" then
		for id, c in pairs(p.tokenUpgrades) do
			local t = Config.TokenShopById[id]
			if t then d.tokenUpgrades[id] = math.floor(num(c, 0, t.max, 0)) end
		end
	end

	local maxUid = 0
	if type(p.toolboxes) == "table" then
		for _, tb in ipairs(p.toolboxes) do
			if type(tb) == "table" and Config.ToolboxKindsById[tb.kind] and Config.ToolboxRaritiesById[tb.rarity] and #d.toolboxes < 60 then
				local uid = math.floor(num(tb.uid, 0, 1e9, 0))
				maxUid = math.max(maxUid, uid)
				table.insert(d.toolboxes, {
					uid = uid, kind = tb.kind, rarity = tb.rarity,
					q = num(tb.q, Config.Forge.QualityMin, Config.Forge.QualityMax, 1),
				})
			end
		end
	end
	d.nextToolUid = math.max(maxUid + 1, math.floor(num(p.nextToolUid, 1, 1e9, 1)))
	if type(p.equipped) == "table" then
		for slot, uid in pairs(p.equipped) do
			local s = math.floor(tonumber(slot) or 0)
			if s >= 1 and s <= Config.Toolbox.Slots then
				for _, tb in ipairs(d.toolboxes) do
					if tb.uid == uid then d.equipped[s] = uid break end
				end
			end
		end
	end

	loadSet(p.titles, d.titles, Config.TitlesById)
	if type(p.title) == "string" and Config.TitlesById[p.title] then d.title = p.title end

	if type(p.stats) == "table" then
		for _, k in ipairs(Profile.STAT_KEYS) do d.stats[k] = num(p.stats[k], 0, 1e12, 0) end
		if type(p.stats.trackBest) == "table" then
			for id, v in pairs(p.stats.trackBest) do
				if Config.TracksById[id] then d.stats.trackBest[id] = num(v, 0, 1e7, 0) end
			end
		end
	end
	local codexCount = 0
	for _ in pairs(d.codex) do codexCount += 1 end
	d.stats.codexMax = math.max(d.stats.codexMax, codexCount)

	if type(p.contracts) == "table" and type(p.contracts.list) == "table" then
		d.contracts.day = math.floor(num(p.contracts.day, 0, 1e9, 0))
		for _, c in ipairs(p.contracts.list) do
			if type(c) == "table" and type(c.tpl) == "string" and type(c.reward) == "table" then
				local reward = {}
				for cur, v in pairs(c.reward) do
					if type(cur) == "string" then reward[cur] = math.floor(num(v, 0, 1e6, 0)) end
				end
				table.insert(d.contracts.list, {
					tpl = c.tpl, n = tonumber(c.n) or 0,
					track = type(c.track) == "string" and c.track or nil,
					reward = reward, done = c.done == true,
				})
			end
		end
	end
	if type(p.daily) == "table" then
		d.daily.day = math.floor(num(p.daily.day, 0, 1e9, 0))
		d.daily.streak = math.floor(num(p.daily.streak, 0, 1e6, 0))
	end
	if type(p.lifetime) == "table" then
		for k in pairs(d.lifetime) do d.lifetime[k] = num(p.lifetime[k], 0, 1e13, 0) end
	end
	if type(p.stickers) == "table" then
		for _, s in ipairs(p.stickers) do
			if type(s) == "table" and type(s.id) == "string" and #d.stickers < Config.Stickers.MaxPerTyre then
				table.insert(d.stickers, {
					id = s.id,
					side = (s.side == -1) and -1 or 1,
					u = num(s.u, -1, 1, 0),
					v = num(s.v, -1, 1, 0),
					rot = num(s.rot, -360, 360, 0),
					scale = num(s.scale, Config.Stickers.MinScale, Config.Stickers.MaxScale, 1),
				})
			end
		end
	end
	d.tutorial = p.tutorial == true
	d.tutStep = math.clamp(math.floor(tonumber(p.tutStep) or 0), 0, 99)

	if type(p.prefs) == "table" then
		for k in pairs(Config.PrefDefaults) do
			local ok, v = Profile.cleanPref(k, p.prefs[k])
			if ok then d.prefs[k] = v end
		end
	end
	local maxGift = 0
	if type(p.gifts) == "table" then
		local lookup = { skin = Config.SkinsById, rim = Config.RimsById, trail = Config.TrailsById, rig = Config.RigSkinsById }
		for _, g in ipairs(p.gifts) do
			if type(g) == "table" and type(g.kind) == "string" and lookup[g.kind] and type(g.id) == "string"
				and lookup[g.kind][g.id] and #d.gifts < Profile.MAX_GIFTS then
				local uid = math.floor(num(g.uid, 0, 1e9, 0))
				maxGift = math.max(maxGift, uid)
				table.insert(d.gifts, {
					uid = uid, kind = g.kind, id = g.id,
					from = type(g.from) == "string" and g.from:sub(1, 40) or "Someone",
					fromId = math.floor(num(g.fromId, -1e12, 1e12, 0)),
					at = math.floor(num(g.at, 0, 1e12, 0)),
				})
			end
		end
	end
	d.nextGiftUid = math.max(maxGift + 1, math.floor(num(p.nextGiftUid, 1, 1e9, 1)))
	d.honks = math.floor(num(p.honks, 0, 1e9, 0))
	if type(p.photos) == "table" then
		for _, ph in ipairs(p.photos) do
			if type(ph) == "table" and type(ph.track) == "string" and Config.TracksById[ph.track] and #d.photos < Profile.MAX_PHOTOS then
				table.insert(d.photos, {
					track = ph.track,
					metres = math.floor(num(ph.metres, 0, 1e7, 0)),
					air = num(ph.air, 0, 999, 0),
					speed = math.floor(num(ph.speed, 0, 1e5, 0)),
					x = num(ph.x, -1e7, 1e7, 0), y = num(ph.y, -1e6, 1e6, 0), z = num(ph.z, -1e5, 1e5, 0),
					vx = num(ph.vx, -1e5, 1e5, 0), vy = num(ph.vy, -1e5, 1e5, 0),
					roll = num(ph.roll, -1e9, 1e9, 0),
					seed = math.floor(num(ph.seed, 0, 2 ^ 31, 0)),
					skin = type(ph.skin) == "string" and ph.skin or "stock",
					rim = type(ph.rim) == "string" and ph.rim or "steel",
					caption = type(ph.caption) == "string" and ph.caption:sub(1, 60) or "",
					best = ph.best == true,
					at = math.floor(num(ph.at, 0, 1e12, 0)),
				})
			end
		end
	end
	if type(p.ghosts) == "table" then
		for id, g in pairs(p.ghosts) do
			if Config.TracksById[id] and type(g) == "table" and type(g.d) == "string" and #g.d <= 12000 and g.d:match("^[%d%-,;]*$") then
				local splits = {}
				if type(g.s) == "table" then
					for i = 1, 7 do
						local v = tonumber(g.s[i])
						if not v then break end
						splits[i] = num(v, 0, 1e5, 0)
					end
				end
				d.ghosts[id] = { d = g.d, s = splits }
			end
		end
	end
	if type(p.tyreLog) == "table" then
		for id, t in pairs(p.tyreLog) do
			if type(id) == "string" and Config.SkinsById[id] and type(t) == "table" then
				d.tyreLog[id] = { runs = math.floor(num(t.runs, 0, 1e7, 0)), dist = num(t.dist, 0, 1e13, 0), best = num(t.best, 0, 1e7, 0) }
			end
		end
	end
	if type(p.guestbook) == "table" then
		for _, g in ipairs(p.guestbook) do
			if type(g) == "table" and type(g.stamp) == "string" and Config.Garage.StampsById[g.stamp] and #d.guestbook < Config.Garage.GuestbookSize then
				table.insert(d.guestbook, {
					name = type(g.name) == "string" and g.name:sub(1, 40) or "Someone",
					fromId = math.floor(num(g.fromId, -1e12, 1e12, 0)),
					stamp = g.stamp,
					at = math.floor(num(g.at, 0, 1e12, 0)),
				})
			end
		end
	end
	if type(p.bay) == "table" then
		local b = p.bay
		d.bay.unlocked = b.unlocked == true
		if type(b.skin) == "string" and Config.SkinsById[b.skin] then d.bay.skin = b.skin end
		if type(b.rim) == "string" and Config.RimsById[b.rim] then d.bay.rim = b.rim end
		if type(b.trail) == "string" and Config.TrailsById[b.trail] then d.bay.trail = b.trail end
		if type(b.stickers) == "table" then
			for _, s in ipairs(b.stickers) do
				if type(s) == "table" and type(s.id) == "string" and #d.bay.stickers < Config.Stickers.MaxPerTyre then
					table.insert(d.bay.stickers, {
						id = s.id, side = (s.side == -1) and -1 or 1,
						u = num(s.u, -1, 1, 0), v = num(s.v, -1, 1, 0), rot = num(s.rot, -360, 360, 0),
						scale = num(s.scale, Config.Stickers.MinScale, Config.Stickers.MaxScale, 1),
					})
				end
			end
		end
	end
	if type(p.receipts) == "table" then
		for _, id in ipairs(p.receipts) do
			if type(id) == "string" and #d.receipts < 50 then table.insert(d.receipts, id) end
		end
	end
	if type(p.growth) == "table" then
		d.growth.referredBy = math.floor(tonumber(p.growth.referredBy) or 0)
		d.growth.refPaid = p.growth.refPaid == true
		d.growth.group = p.growth.group == true
	end
	d.v2 = LoopData.sanitize(p.v2)
	return d
end

--==============================================================
-- session locking
-- A save is an envelope { v = 2, data = profile, lock = { j = JobId, t = os.time() } }. Loading
-- takes the lock; saving only writes while this server still holds it, and refreshes it; leaving
-- releases it. A server that joins while another still holds a fresh lock waits for it to let go
-- (the old server saves on leave), so a quick server hop can never load a stale save and then
-- overwrite the newer one. A lock nobody has refreshed for LOCK_STALE seconds belonged to a server
-- that died, and is taken over. Saves from before the envelope (a bare profile) load as they are.
--==============================================================
local LOCK_STALE = 330   -- autosave refreshes the lock every 120 s
local LOCK_WAITS = 8     -- tries, 3 s apart, before taking a fresh lock anyway

local function unwrap(old: any): (any, any)
	if type(old) == "table" and old.v == 2 and old.data ~= nil then return old.data, old.lock end
	return old, nil
end

-- returns profile, loadedOk
function Profile.load(store: DataStore?, userId: number)
	if not store then return Profile.default(), true end
	local job = game.JobId
	for attempt = 1, LOCK_WAITS + 3 do
		local held, raw = false, nil
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(tostring(userId), function(old)
				local data, lock = unwrap(old)
				local now = os.time()
				if lock and lock.j ~= job and now - (tonumber(lock.t) or 0) < LOCK_STALE and attempt <= LOCK_WAITS then
					held = true
					return nil
				end
				raw = data
				return { v = 2, data = data, lock = { j = job, t = now } }
			end)
		end)
		if ok and not held then return Profile.sanitize(raw), true end
		-- Studio with API access off: that's permanent, so don't sit through the retries
		-- (the pcall's message is "403: Cannot write to DataStore from studio if API access is not enabled.")
		if not ok and (tostring(err):find("API access is not enabled", 1, true) or tostring(err):find("StudioAccessToApisNotAllowed", 1, true)) then
			return Profile.default(), false
		end
		task.wait(held and 3 or attempt)
	end
	return Profile.default(), false
end

-- release = true lets go of the lock (the player is leaving); false means another server holds the
-- session now (or the store failed), and nothing was written
function Profile.save(store: DataStore?, userId: number, p: any, release: boolean?): boolean
	if not store or not p then return false end
	local data = table.clone(p)
	data.live = nil
	local job = game.JobId
	for attempt = 1, 3 do
		local lost = false
		local ok = pcall(function()
			(store :: DataStore):UpdateAsync(tostring(userId), function(old)
				local _, lock = unwrap(old)
				if lock and lock.j ~= job then
					lost = true
					return nil
				end
				return { v = 2, data = data, lock = (not release) and { j = job, t = os.time() } or nil }
			end)
		end)
		if lost then
			warn("[TyreCannon] save skipped for", userId, "- another server holds the session")
			return false
		end
		if ok then return true end
		task.wait(attempt)
	end
	return false
end

return Profile
