--!strict
-- TYRE CANNON :: Server / Debug
-- Password-gated test commands. The password lives on the server only, so
-- it never ships to a client. Unlocked players also get every server error
-- and warning mirrored into their debug log.

local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)
local Profile = require(script.Parent.Profile)
local Analytics = require(script.Parent.Analytics)

local PASSWORD = "dbug"
-- the Roblox user ids let into the Debug menu (and its Playtest tab) without the password
local DEVS: { [number]: boolean } = {
	[3402448415] = true,   -- cjtrxn
}

local Debug = {}

function Debug.init(S)
	local R = S.Remotes
	local authed: { [number]: boolean } = {}
	S.debugAuthed = authed

	local function all(lookup)
		local set = {}
		for id in pairs(lookup) do set[id] = true end
		return set
	end

	local COMMANDS = {}

	COMMANDS.give = function(player, p, currency, amount)
		amount = math.floor(tonumber(amount) or 0)
		if currency == "credits" then p.credits = math.max(0, p.credits + amount)
		elseif currency == "tokens" then p.tokens = math.max(0, p.tokens + amount)
		elseif p.metals[currency] ~= nil then p.metals[currency] = math.max(0, p.metals[currency] + amount)
		else return "unknown currency " .. tostring(currency) end
		return ("+%d %s"):format(amount, currency)
	end

	COMMANDS.maxUpgrades = function(_, p)
		for _, u in ipairs(Config.Upgrades) do p.upgrades[u.id] = u.maxLevel end
		return "all upgrades maxed"
	end

	COMMANDS.resetUpgrades = function(_, p)
		p.upgrades = {}
		return "upgrades reset"
	end

	COMMANDS.unlockAll = function(_, p)
		p.tracks = all(Config.TracksById)
		p.skins = all(Config.SkinsById)
		p.trails = all(Config.TrailsById)
		p.rims = all(Config.RimsById)
		p.rigs = all(Config.RigSkinsById)
		p.generators = all(Config.GeneratorsById)
		for _, c in ipairs(Config.Charms) do p.charms[c.id] = 20 end
		return "every track, cosmetic, generator and 20 of each charm"
	end

	COMMANDS.titlesReady = function(_, p)
		for _, t in ipairs(Config.Titles) do
			local c = t.cond
			if c then
				if c.stat == "trackBest" then p.stats.trackBest[c.track] = math.max(p.stats.trackBest[c.track] or 0, c.goal)
				elseif c.stat == "prestige" then p.prestige = math.max(p.prestige, c.goal)
				elseif c.stat == "bestSpectators" then p.lifetime.bestSpectators = math.max(p.lifetime.bestSpectators, c.goal)
				else p.stats[c.stat] = math.max(p.stats[c.stat] or 0, c.goal) end
			end
		end
		p.tokens += 60
		return "every title unlocked, +60 tokens"
	end

	COMMANDS.live = function(player, _, board, rank)
		S.liveOverride[player.UserId] = S.liveOverride[player.UserId] or {}
		S.liveOverride[player.UserId][tostring(board)] = tonumber(rank)
		S.refreshLive()
		return ("pretending rank %s on %s"):format(tostring(rank), tostring(board))
	end

	COMMANDS.boosters = function(_, p)
		for _, b in ipairs(Config.Boosters) do
			p.boosters[b.id] = (b.kind == "timed") and b.seconds or b.charges
		end
		return "one of every booster"
	end

	COMMANDS.toolbox = function(_, p, kind, rarity)
		if not Config.ToolboxKindsById[kind] or not Config.ToolboxRaritiesById[rarity] then return "bad kind/rarity" end
		local uid = p.nextToolUid
		p.nextToolUid += 1
		table.insert(p.toolboxes, { uid = uid, kind = kind, rarity = rarity, q = 1 })
		return ("added %s %s toolbox"):format(rarity, kind)
	end

	COMMANDS.prestigeReady = function(_, p)
		p.credits = math.max(p.credits, Config.PrestigeCost(p.prestige))
		return "credits set to prestige cost"
	end

	COMMANDS.resetDaily = function(_, p)
		p.daily = { day = 0, streak = 0 }
		return "daily streak reset"
	end

	COMMANDS.yesterday = function(_, p)
		p.daily.day = math.max(0, p.daily.day - 1)
		return "daily moved back a day"
	end

	COMMANDS.rerollContracts = function(player, p)
		p.contracts = { day = 0, list = {} }
		S.ensureContracts(p, player.UserId + math.random(1, 99999))
		return "contracts rerolled"
	end

	COMMANDS.watchers = function(player, _, n)
		n = math.max(0, math.floor(tonumber(n) or 0))
		S.fakeWatchers[player.UserId] = n
		S.peakWatchers[player.UserId] = math.max(S.peakWatchers[player.UserId] or 0, n)
		R.SpectatorCount:FireClient(player, n)
		return ("%d fake watchers"):format(n)
	end

	COMMANDS.tutorial = function(_, p)
		p.tutorial = false
		p.tutStep = 0
		return "tutorial will play again on rejoin"
	end

	COMMANDS.resetProfile = function(player)
		local fresh = Profile.default()
		fresh.tutorial = true
		S.profiles[player.UserId] = fresh
		S.ensureContracts(fresh, player.UserId)
		return "profile wiped (not saved in Studio)"
	end

	COMMANDS.save = function(player)
		return S.save(player.UserId) and "saved" or "save failed or disabled"
	end

	-- (a no-op: answers ok only to someone let in, so the client knows to open unlocked)
	COMMANDS.whoami = function()
		return "dev"
	end

	COMMANDS.profile = function(_, p)
		return p
	end

	-- a wrapped part from a pretend friend, to test opening gifts alone
	COMMANDS.gift = function(_, p, kind, id)
		local lookup = ({ skin = Config.SkinsById, rim = Config.RimsById, trail = Config.TrailsById })[kind or "rim"]
		local def = lookup and lookup[id or "fivespoke"]
		if not def then return "bad kind/id" end
		table.insert(p.gifts, { uid = p.nextGiftUid, kind = kind or "rim", id = def.id, from = "Test Friend", fromId = 1, at = os.time() })
		p.nextGiftUid += 1
		return "gift wrapped: " .. def.name
	end

	-- a lived-in career for looking round the garage: tyres, records, trophies, photos, stamps
	COMMANDS.garageDemo = function(_, p)
		local Config = require(game:GetService("ReplicatedStorage").TyreCannon.Modules.Config)
		local TrackGen = require(game:GetService("ReplicatedStorage").TyreCannon.Modules.TrackGen)
		local M = 1 / Config.Physics.StudsToMetres
		for i, s in ipairs(Config.Skins) do
			if i <= 7 then
				p.skins[s.id] = true
				p.tyreLog[s.id] = { runs = 3 + i * 11, dist = (4200 + i * 2600) * M * (3 + i), best = (900 + i * 380) * M }
			end
		end
		p.totals.distance = 186400 * M
		p.totals.runs = 612
		p.stats.runs = 612
		p.stats.forged = 23
		p.stats.forgedLegendary = 1
		p.stats.flawless = 41
		p.stats.contracts = 18
		p.stats.maxTier = 4
		p.metals = { bronze = 312, silver = 47, gold = 9 }
		p.lifetime.bestDistance = 3620 * M
		p.honks = 37
		for i, t in ipairs(Config.Tracks) do
			p.tracks[t.id] = true
			p.records[t.id] = { dist = (3620 - i * 700) * M, credits = 5000, runs = 40 * i }
		end
		p.photos = {}
		for i = 1, 6 do
			local track = Config.Tracks[((i - 1) % #Config.Tracks) + 1]
			local x = (1200 + i * 1500)
			local seed = 1000 + i * 77
			local tg = TrackGen.get(track.id)
			local old = tg.runSeed
			tg:setRun(seed)
			local ground = tg:heightAt(x)
			if old then tg:setRun(old) end
			table.insert(p.photos, {
				track = track.id, metres = math.floor(x / M), air = 1.2 + i * 0.4, speed = 300 + i * 40,
				x = x, y = ground + 20 + i * 12, z = 0, vx = 420, vy = 60, roll = i * 2.1, seed = seed,
				skin = Config.Skins[(i % 5) + 1].id, rim = "steel", caption = "", best = i == 4, at = os.time(),
			})
		end
		p.guestbook = {}
		local names = { "Lemmy", "TyreGuy99", "Honker", "Asha", "BigWheel", "Mo" }
		for i, s in ipairs(Config.Garage.Stamps) do
			table.insert(p.guestbook, { name = names[i], fromId = i, stamp = s.id, at = os.time() - i * 600 })
		end
		return "garage filled"
	end

	-- honks on your own yard, to test the sign's counter
	COMMANDS.honks = function(_, p, n)
		p.honks += math.floor(tonumber(n) or 1)
		return "honks now " .. p.honks
	end

	--==============================================================
	-- the loop (profile.v2): cash, keys, stages, machines, zones, tyres
	--==============================================================
	local Game = require(Modules.Game)
	local LoopData = require(script.Parent.LoopData)
	local function v2(p) p.v2 = p.v2 or LoopData.default() return p.v2 end

	COMMANDS.keys = function(_, p, n)
		local v = v2(p)
		v.keys = math.max(0, v.keys + math.floor(tonumber(n) or 0))
		return "keys now " .. v.keys
	end

	COMMANDS.setTier = function(_, p, tier)
		local v = v2(p)
		v.tier = math.clamp(math.floor(tonumber(tier) or 1), 1, #Game.Tiers)
		-- levels above the new stage's cap come down to it
		for id, lv in pairs(v.mach) do v.mach[id] = math.min(lv, Game.maxLevel(id)) end
		return ("stage %d: %s"):format(v.tier, Game.Tiers[v.tier].name)
	end

	COMMANDS.machine = function(_, p, id, delta)
		local v = v2(p)
		if not Game.MachinesById[id] then return "unknown machine " .. tostring(id) end
		v.mach[id] = math.clamp((v.mach[id] or 0) + math.floor(tonumber(delta) or 1), 0, Game.maxLevel(id))
		return ("%s level %d / %d"):format(id, v.mach[id], Game.maxLevel(id))
	end

	COMMANDS.maxMachines = function(_, p)
		local v = v2(p)
		for _, m in ipairs(Game.Machines) do v.mach[m.id] = Game.maxLevel(m.id) end
		return "every machine maxed for this stage"
	end

	COMMANDS.resetMachines = function(_, p)
		local v = v2(p)
		for _, m in ipairs(Game.Machines) do v.mach[m.id] = 0 end
		return "machines back to 0"
	end

	COMMANDS.overhaulReady = function(_, p)
		local v = v2(p)
		p.credits = math.max(p.credits, Game.plotUpgradeCost(v.tier))
		return "plot upgrade affordable"
	end

	COMMANDS.allZones = function(_, p)
		local v = v2(p)
		for _, z in ipairs(Game.Zones) do v.zones[z.id] = true end
		return "every zone open"
	end

	COMMANDS.allTyres = function(_, p)
		local v = v2(p)
		for _, t in ipairs(Game.Tyres) do
			if t.zone ~= "retired" and #v.inv < LoopData.MAX_TYRES then
				table.insert(v.inv, { uid = v.nextUid, id = t.id, forge = 0 })
				v.nextUid += 1
				v.index[t.id] = true
			end
		end
		return "one of every tyre"
	end

	COMMANDS.tyreOf = function(_, p, rarity)
		local v = v2(p)
		local pool = {}
		for _, t in ipairs(Game.Tyres) do
			if t.zone ~= "retired" and t.rarity == rarity then table.insert(pool, t) end
		end
		if #pool == 0 then return "no tyres of rarity " .. tostring(rarity) end
		local t = pool[math.random(1, #pool)]
		table.insert(v.inv, { uid = v.nextUid, id = t.id, forge = 0 })
		v.nextUid += 1
		v.index[t.id] = true
		return "got " .. t.name
	end

	-- the yard's looks (Game.YardLooks): the neon stage's pass on or off, a look straight on (its pass
	-- or prestige given if it needs one), the prestige level
	COMMANDS.midnightPass = function(_, p)
		local v = v2(p)
		v.passes.midnight = (not v.passes.midnight) or nil
		if not v.passes.midnight and v.look and v.look.id == "midnight" then v.look = { id = "stage", way = v.look.way } end
		return "neon stage pass " .. (v.passes.midnight and "on" or "off")
	end

	COMMANDS.setLook = function(_, p, id, way)
		local v = v2(p)
		local look = Game.YardLooksById[tostring(id)]
		if not look then return "unknown look " .. tostring(id) end
		if look.pass then v.passes[look.pass] = true end
		if look.prestige and (p.prestige or 0) < look.prestige then p.prestige = look.prestige end
		v.look = { id = look.id, way = Game.yardWay(tostring(way)).id }
		return "look: " .. look.name .. (if look.ways then " (" .. v.look.way .. ")" else "")
	end

	COMMANDS.prestige = function(_, p, n)
		p.prestige = math.clamp((p.prestige or 0) + math.floor(tonumber(n) or 1), 0, Game.Prestige.Max)
		return "prestige " .. p.prestige
	end

	COMMANDS.wipeLoop = function(_, p)
		p.v2 = LoopData.default()
		p.credits = 0
		return "loop progress wiped (stage 1, nothing bought)"
	end

	-- the playtest log (Analytics): every counter, session and note, for the Playtest tab
	COMMANDS.playtest = function()
		return Analytics.read()
	end

	R.Debug.OnServerInvoke = function(player: Player, cmd: any, a: any, b: any)
		-- (devs listed in DEVS are let in without the password)
		if DEVS[player.UserId] or game:GetService("RunService"):IsStudio() then authed[player.UserId] = true end
		if cmd == "auth" then
			if S.throttled(player, 1, "debugAuth") then return { ok = false, err = "Wait a second." } end
			if a == PASSWORD then
				authed[player.UserId] = true
				return { ok = true, msg = "unlocked" }
			end
			return { ok = false, err = "Wrong password." }
		end
		if not authed[player.UserId] then return { ok = false, err = "Locked." } end
		local p = S.profiles[player.UserId]
		local fn = type(cmd) == "string" and COMMANDS[cmd]
		if not fn then return { ok = false, err = "Unknown command." } end
		if not p and cmd ~= "resetProfile" then return { ok = false, err = "No profile loaded." } end
		local ok, res = pcall(fn, player, p, a, b)
		if not ok then return { ok = false, err = tostring(res) } end
		if cmd ~= "profile" and cmd ~= "playtest" and cmd ~= "whoami" then S.push(player) end
		return { ok = true, msg = res, profile = S.profiles[player.UserId] }
	end

	Players.PlayerRemoving:Connect(function(pl)
		authed[pl.UserId] = nil
	end)

	LogService.MessageOut:Connect(function(message, messageType)
		if messageType ~= Enum.MessageType.MessageError and messageType ~= Enum.MessageType.MessageWarning then return end
		for uid in pairs(authed) do
			local pl = Players:GetPlayerByUserId(uid)
			if pl then R.DebugLog:FireClient(pl, "server", message, messageType.Name) end
		end
	end)
end

return Debug
