--!strict
-- TYRE CANNON :: Server / Loop
-- The revamped loop, decided on the server: starting a run, paying it out, buying machine
-- levels, overhauling, opening crates with keys, equipping and forging tyres, playtime gifts and
-- offline earnings. The run itself is simulated on the client; every number that comes back is
-- checked against what this player's plot can actually reach and how long the run took.
-- Remotes live in Remotes.V2 and are created here if they don't exist yet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Game = require(Modules.Game)
local Config = require(Modules.Config)
local Goals = require(Modules.Goals)
local DataStoreService = game:GetService("DataStoreService")
local LoopData = require(script.Parent.LoopData)
-- every cash and key in and out is logged for the dashboard (Analytics.luau)
local Analytics = require(script.Parent.Analytics)

local Loop = {}

local function remote(folder: Instance, class: string, name: string): any
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = folder
	end
	return r
end

function Loop.init(S)
	local root = ReplicatedStorage:WaitForChild("TyreCannon")
	local remotes = root:WaitForChild("Remotes")
	local folder = remotes:FindFirstChild("V2")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "V2"
		folder.Parent = remotes
	end
	local R = {
		Begin = remote(folder, "RemoteFunction", "Begin"),
		Finish = remote(folder, "RemoteFunction", "Finish"),
		Buy = remote(folder, "RemoteFunction", "Buy"),
		Overhaul = remote(folder, "RemoteFunction", "Overhaul"),
		OpenCrate = remote(folder, "RemoteFunction", "OpenCrate"),
		Equip = remote(folder, "RemoteFunction", "Equip"),
		Forge = remote(folder, "RemoteFunction", "Forge"),
		Design = remote(folder, "RemoteFunction", "Design"),
		Fav = remote(folder, "RemoteFunction", "Fav"),
		Layout = remote(folder, "RemoteFunction", "Layout"),
		Announce = remote(folder, "RemoteEvent", "Announce"),
		Offline = remote(folder, "RemoteEvent", "Offline"),
		-- v3
		TestDrive = remote(folder, "RemoteFunction", "TestDrive"),
		Daily = remote(folder, "RemoteFunction", "Daily"),
		Prestige = remote(folder, "RemoteFunction", "Prestige"),
		Launched = remote(folder, "RemoteEvent", "Launched"),      -- (userId, plotIndex, grade): everyone sees the shot
		Reward = remote(folder, "RemoteEvent", "Reward"),          -- a reward worth a banner: { text, keys, bonus }
		AutoFire = remote(folder, "RemoteEvent", "AutoFire"),      -- (plotIndex, cash for the owner or nil)
		Look = remote(folder, "RemoteFunction", "Look"),          -- (lookId, way): the yard's look (Game.YardLooks)
		AfkReport = remote(folder, "RemoteEvent", "AfkReport"),   -- back from AFK: { seconds, shots, cash, balance }
		-- v4
		PickPerk = remote(folder, "RemoteFunction", "PickPerk"),   -- (perk id): keep one of the prestige's three
		Like = remote(folder, "RemoteFunction", "Like"),           -- (owner userId): like a yard, once a day each
		Feedback = remote(folder, "RemoteFunction", "Feedback"),   -- (kind, text, rating): the playtest's notes
		Quest = remote(folder, "RemoteEvent", "Quest"),            -- a quest or trial done: { kind = "quest"|"trial"|"theme", text, keys, cash }
		Track = remote(folder, "RemoteEvent", "Track"),            -- (name): a screen opened or a tip seen, for the playtest log
		BenchPose = remote(folder, "RemoteEvent", "BenchPose"),    -- (0..3): sat on a bench in pose k (BenchPose.luau), 0 stood up
	}
	S.V2 = R

	-- the playtest log's session rows (Analytics): where each player had got to
	Analytics.describe = function(player: Player)
		local p = S.profiles[player.UserId]
		local v = p and p.v2
		if not v then return {} end
		return {
			runs = v.runs, best = math.floor(v.bestEver or 0), stage = v.tier, pres = p.prestige or 0,
			lvl = v.career and v.career.level or 1, tut = p.tutStep or 0, tutDone = p.tutorial == true,
			style = v.style or 0,
		}
	end
	-- what the client reports: screens opened, tips seen, buttons pressed (names only, a few a second)
	local trackAt: { [number]: number } = {}
	-- a bench pose shows for everyone as the character's BenchPose attribute (with the tyre's looks, for
	-- the pose where you talk to it)
	local poseAt: { [number]: number } = {}
	R.BenchPose.OnServerEvent:Connect(function(player: Player, k: any)
		if type(k) ~= "number" or k ~= k // 1 or k < 0 or k > 3 then return end
		local now = os.clock()
		if (poseAt[player.UserId] or 0) > now then return end
		poseAt[player.UserId] = now + 0.2
		local char = player.Character
		if not char then return end
		local p = S.profiles[player.UserId]
		char:SetAttribute("BenchSkin", p and p.skin or "stock")
		char:SetAttribute("BenchRim", p and p.rim or "steel")
		char:SetAttribute("BenchPose", if k > 0 then k else nil)
	end)
	Players.PlayerRemoving:Connect(function(player: Player) poseAt[player.UserId] = nil end)

	R.Track.OnServerEvent:Connect(function(player: Player, name: any)
		if type(name) ~= "string" or #name > 40 or not string.match(name, "^[%a]+:[%w_]+$") then return end
		local kind = string.match(name, "^(%a+):")
		if kind ~= "open" and kind ~= "tip" and kind ~= "click" and kind ~= "skip" then return end
		local now = os.clock()
		if (trackAt[player.UserId] or 0) > now then return end
		trackAt[player.UserId] = now + 0.3
		Analytics.count(name)
	end)
	Players.PlayerRemoving:Connect(function(pl) trackAt[pl.UserId] = nil end)

	local active: { [number]: any } = {}

	--==============================================================
	-- v4: the trial, the quests and the yard's style kept current on the save
	--==============================================================
	local function syncV4(player: Player, p, v)
		v.pres = p.prestige or 0
		-- the stage's trial: a fresh one whenever the prestige or the stage changes
		local key = v.pres .. ":" .. v.tier
		if not v.trial or v.trial.key ~= key then
			local g = Goals.trial(v.pres, v.tier, 0, Game.perkLv(v, "trials"))
			v.trial = { key = key, k = g.k, t = g.t, tries = 0, best = 0, done = false }
		end
		-- a new day's three quests, a new week's one
		local day = Game.utcDay()
		if v.quests.day ~= day then
			v.quests.day = day
			-- (2026-10-24) this climb's furthest, not the all-time best: after a prestige the "best" daily
			-- asked for the old top stage's distance from the Dirt Lot
			v.quests.list = Goals.dailies(player.UserId, day, v.tier, math.min(v.bestEver, v.reached or v.bestEver))
			v.quests.bonus = false
		end
		local week = Goals.utcWeek()
		if v.quests.week ~= week or not v.quests.wk then
			v.quests.week = week
			v.quests.wk = Goals.weekly(player.UserId, week, v.tier)
		end
		if v.likes.week ~= week then v.likes = { week = week, n = 0 } end
		if v.liked.day ~= day then v.liked = { day = day, to = {} } end
		if v.likeKeys.day ~= day then v.likeKeys = { day = day, n = 0 } end
	end

	local function data(player: Player)
		local p = S.profiles[player.UserId]
		if not p then return nil, nil end
		p.v2 = p.v2 or LoopData.default()
		syncV4(player, p, p.v2)
		return p, p.v2
	end

	-- quests: `amount` more of `kind` (or, for a one-run kind, this run's value); a finished quest
	-- pays at once and says so, and all three dailies pay a bonus
	local function questAdd(player: Player, v, kind: string, amount: number)
		if amount <= 0 then return end
		local p = S.profiles[player.UserId]
		local function pay(g, reward, label: string)
			-- (2026-10-18: v.rate is run cash, which already carries the prestige multiplier; it was applied twice)
			local cash = math.floor((v.rate or 0) * (reward.minutes or 0))
			v.keys = math.min(1e6, v.keys + (reward.keys or 0))
			if p and cash > 0 then p.credits = math.min(1e15, p.credits + cash) end
			Analytics.earn(player, "Keys", reward.keys or 0, v.keys, "Gameplay", "Quest")
			Analytics.count("ev:QuestDone")
			R.Quest:FireClient(player, { kind = "quest", text = label .. ": " .. Goals.text(g), keys = if (reward.keys or 0) > 0 then reward.keys else nil, cash = cash })
		end
		local function bump(g, reward, label: string)
			if not g or g.done or g.k ~= kind then return end
			local def = Goals.CountKinds[g.k]
			if def and def.run then g.h = math.max(g.h or 0, amount) else g.h = (g.h or 0) + amount end
			if g.h >= g.t then
				g.done = true
				pay(g, reward, label)
			end
		end
		for _, g in ipairs(v.quests.list) do bump(g, Goals.DailyReward, "Daily done") end
		bump(v.quests.wk, Goals.WeeklyReward, "Weekly done")
		if not v.quests.bonus and #v.quests.list > 0 then
			local all = true
			for _, g in ipairs(v.quests.list) do
				if not g.done then all = false end
			end
			if all then
				v.quests.bonus = true
				v.keys = math.min(1e6, v.keys + Goals.DailyBonus.keys)
				R.Quest:FireClient(player, { kind = "quest", text = "All three dailies done", keys = Goals.DailyBonus.keys })
			end
		end
	end
	S.questAdd = questAdd

	-- the yard's style (Game.yardStyle) worked out again; finishing the week's theme set pays once
	local function restyle(player: Player, v)
		local week = Goals.utcWeek()
		local st = Game.yardStyle(v.layout or Game.yardLayout(nil), v.look and v.look.id or "stage", Game.perkLv(v, "showman"), week)
		v.style = st.score
		if st.theme and table.find(st.whole, st.theme) and v.themeWeek ~= week then
			v.themeWeek = week
			v.keys = math.min(1e6, v.keys + Game.Style.ThemeKeys)
			local set = Game.DecorSetsById[st.theme]
			R.Quest:FireClient(player, { kind = "theme", text = "Theme set done: " .. (set and set.name or st.theme), keys = Game.Style.ThemeKeys })
		end
		return st
	end

	-- every yard shows its owner's machines to everyone: the levels ride on the plot as attributes
	-- (V2_<machine>, V2_Tier), set on every push and cleared when the owner leaves
	local published: { [number]: Instance } = {}
	local function plotModel(userId: number): Instance?
		local i = S.plotOf(userId)
		local lobby = workspace:FindFirstChild("Lobby")
		local plots = lobby and lobby:FindFirstChild("Plots")
		return i and plots and plots:FindFirstChild("Plot" .. i) or nil
	end
	local function clearYard(plot: Instance)
		for _, m in ipairs(Game.Machines) do plot:SetAttribute("V2_" .. m.id, nil) end
		plot:SetAttribute("V2_Tier", nil)
		plot:SetAttribute("V2_Layout", nil)
		plot:SetAttribute("V2_Owner", nil)
		plot:SetAttribute("V2_Prestige", nil)
		plot:SetAttribute("V2_Look", nil)
		plot:SetAttribute("V2_Midnight", nil)
		plot:SetAttribute("V2_Style", nil)
		plot:SetAttribute("V2_Likes", nil)
		plot:SetAttribute("V2_Showcase", nil)
		plot:SetAttribute("V2_OwnerId", nil)
	end
	local function publish(player: Player)
		local p = S.profiles[player.UserId]
		local plot = plotModel(player.UserId)
		local before = published[player.UserId]
		if before and before ~= plot then clearYard(before) end
		published[player.UserId] = plot
		if not (p and p.v2 and plot) then return end
		for _, m in ipairs(Game.Machines) do plot:SetAttribute("V2_" .. m.id, p.v2.mach[m.id] or 0) end
		plot:SetAttribute("V2_Tier", p.v2.tier or 1)
		plot:SetAttribute("V2_Layout", Game.yardEncode(p.v2.layout or Game.yardLayout(nil)))
		-- the name over the garage door
		plot:SetAttribute("V2_Owner", player.DisplayName)
		-- the prestige looks (tyre, cannon trim, yard) and the yard's look, "id:way"; a look the owner
		-- can't use (a pass they no longer own) shows as the stage's
		plot:SetAttribute("V2_Prestige", p.prestige or 0)
		player:SetAttribute("Prestige", p.prestige or 0)
		local look = p.v2.look or { id = "stage", way = "Midnight" }
		local id = if Game.lookOpen(Game.YardLooksById[look.id], p.prestige, p.v2.passes) then look.id else "stage"
		plot:SetAttribute("V2_Look", id .. ":" .. Game.yardWay(look.way).id)
		plot:SetAttribute("V2_Midnight", p.v2.passes.midnight == true)
		-- v4: the yard's style and likes for its sign, the owner (for Like and Visit), and the three best
		-- tyres for the Tyre Showcase ("id:mut:stars,...")
		plot:SetAttribute("V2_Style", p.v2.style or 0)
		plot:SetAttribute("V2_Likes", p.v2.likes and p.v2.likes.n or 0)
		plot:SetAttribute("V2_OwnerId", player.UserId)
		local best = table.clone(p.v2.inv)
		table.sort(best, function(a, b) return Game.tyrePoints(a.id, a.forge, a.mut) > Game.tyrePoints(b.id, b.forge, b.mut) end)
		local show = {}
		for i = 1, math.min(3, #best) do
			local t = best[i]
			table.insert(show, ("%s:%s:%d"):format(t.id, t.mut or "", t.forge or 0))
		end
		plot:SetAttribute("V2_Showcase", table.concat(show, ","))
	end
	local push = S.push
	S.push = function(player: Player)
		push(player)
		publish(player)
	end
	Players.PlayerRemoving:Connect(function(pl)
		local plot = published[pl.UserId]
		if plot then clearYard(plot) end
		published[pl.UserId] = nil
	end)

	-- friendships asked once per pair per server: IsFriendsWith yields on a web call
	local friendCache: { [string]: boolean } = {}
	local function isFriend(a: Player, b: Player): boolean
		local key = math.min(a.UserId, b.UserId) .. ":" .. math.max(a.UserId, b.UserId)
		local known = friendCache[key]
		if known == nil then
			local ok, yes = pcall(function() return a:IsFriendsWith(b.UserId) end)
			known = ok and yes == true
			if ok then friendCache[key] = known end
		end
		return known
	end

	local function boostOn(v, id: string): boolean
		return (v.boosts[id] or 0) > os.time()
	end

	-- every multiplier on cash, in its bucket
	local function cashMult(player: Player, v): (number, { [string]: number })
		local tyres = Game.tyreBucket(v.inv, v.launch, v.spares)
		local over = Game.stageCash(v.overhauls)
		local bought = 1
		if v.passes.cash2 then bought *= 2 end
		if boostOn(v, "cash2") then bought *= 2 end
		bought = math.min(bought, Game.Buy.Cap)
		local friends = 0
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and isFriend(player, other) then friends += Game.Friends.PerFriend end
		end
		friends = math.min(friends, Game.Friends.Max)
		local index = 1 + Game.IndexBonus * (v.indexPaid or 0)
		if v.passes.vip then index *= 1.1 end
		local owner = S.profiles[player.UserId]
		local prestige = Game.prestigeMult(owner and owner.prestige or 0)
		local premium = if player.MembershipType == Enum.MembershipType.Premium then Game.Premium.Cash else 1
		return tyres * over * bought * (1 + friends) * index * prestige * premium,
			{ tyres = tyres, overhaul = over, bought = bought, friends = 1 + friends, index = index, prestige = prestige, premium = premium }
	end

	local function launchTyre(v)
		for _, t in ipairs(v.inv) do
			if t.uid == v.launch then return t end
		end
		return v.inv[1]
	end

	local function equipped(v)
		local launch, spares = Game.equipped(v.inv, v.launch, v.spares)
		return launch or v.inv[1], spares
	end

	local function grantKeys(v, n: number)
		v.keys = math.min(1e6, v.keys + n)
	end

	--==============================================================
	-- the Index paying out: every Game.IndexEvery tyres found, a key and a cash bonus for good
	--==============================================================
	local function checkIndex(player: Player, v)
		local found = 0
		for _ in pairs(v.index) do found += 1 end
		while found >= (v.indexPaid + 1) * Game.IndexEvery do
			v.indexPaid += 1
			v.keys = math.min(1e6, v.keys + 1)
			Analytics.earn(player, "Keys", 1, v.keys, "Gameplay", "Index")
			R.Reward:FireClient(player, { kind = "index", name = ("%d tyres found"):format(v.indexPaid * Game.IndexEvery), text = ("Index: %d tyres found"):format(v.indexPaid * Game.IndexEvery), keys = 1,
				bonus = ("+%d%% cash for good"):format(math.floor(Game.IndexBonus * 100 * v.indexPaid + 0.5)) })
		end
	end

	--==============================================================
	-- the run
	--==============================================================
	-- zoneId: start the run at the start of a zone you've already reached (the zone map's Start Here)
	R.Begin.OnServerInvoke = function(player: Player, zoneId: any)
		-- (2026-10-24) one launch every 3 s at most: a script used to call Begin and Finish twice a second
		if S.throttled(player, 3, "v2begin") then return { ok = false, err = "One at a time." } end
		local p, v = data(player)
		if not p then return { ok = false, err = "Still loading your save." } end
		local reach = Game.reachMetres(v.mach, v.tier)
		-- a heat racer runs the heat's road; everyone else a fresh one
		local seed = (S.heatSeedFor and S.heatSeedFor[player.UserId]) or math.random(1, 2147483646)
		local from = type(zoneId) == "string" and Game.ZonesById[zoneId]
		local startM = (from and v.zones[from.id]) and from.start or 0
		local keyZones = Game.runKeys(seed, v.runs)
		active[player.UserId] = { seed = seed, reach = reach, started = os.clock(), startM = startM, keyZones = keyZones }
		local t = launchTyre(v)
		-- Studio only: try any tyre on the next run (player attribute DebugTyre = tyre id)
		local dbg = game:GetService("RunService"):IsStudio() and player:GetAttribute("DebugTyre")
		if type(dbg) == "string" and Game.TyresById[dbg] then t = { uid = -1, id = dbg, forge = 0 } end
		-- a Test Drive: the featured Legendary for this one run
		local testDrive = false
		if v.testArmed then
			v.testArmed = false
			t = { uid = -2, id = (v.testTyre and Game.TyresById[v.testTyre] and v.testTyre) or Game.banner().legendary, forge = 0 }
			testDrive = true
		end
		local mult = cashMult(player, v)
		local stats = Game.runStats(v.mach, v.tier, t, select(2, equipped(v)))
		-- v4 perks
		stats.launchSpeed *= 1 + 0.05 * Game.perkLv(v, "barrel")
		stats.nitroMax *= 1 + 0.1 * Game.perkLv(v, "tank")
		stats.nitroRegen *= 1 + 0.1 * Game.perkLv(v, "tank")
		stats.magnetRadius *= 1 + 0.15 * Game.perkLv(v, "magnet")
		local ev = Game.eventAt().on
		if ev and ev.id == "tailwind" then stats.launchSpeed *= 1.4 end
		-- everyone in the server sees the shot go up from this yard
		R.Launched:FireAllClients(player.UserId, S.plotOf(player.UserId))
		return {
			ok = true,
			testDrive = testDrive,
			event = ev and ev.id or nil,
			seed = seed,
			reach = reach,
			startMetres = startM,
			stats = stats,
			tier = v.tier,
			mach = table.clone(v.mach),
			mult = mult,
			tyre = { id = t.id, forge = t.forge, uid = t.uid, design = v.designs[tostring(t.uid)] },
			best = v.bestEver,
			ghost = p.ghosts and p.ghosts.road or nil,
			rivals = (function()
				-- everyone else here with a best run: their ghost, their name, their launch tyre
				local list = {}
				for _, other in ipairs(Players:GetPlayers()) do
					local op = other ~= player and S.profiles[other.UserId] or nil
					if op and op.ghosts and op.ghosts.road and #list < 6 then
						local tid = nil
						local ov = op.v2
						if ov then
							for _, it in ipairs(ov.inv) do
								if it.uid == ov.launch then tid = it.id end
							end
						end
						table.insert(list, { name = other.DisplayName, ghost = op.ghosts.road, tyre = tid })
					end
				end
				return list
			end)(),
			-- the keys out on the road this run (indices into Game.keySpots)
			keyZones = keyZones,
			trial = v.trial,
			cool = v.mach.cooling,
			fuel = v.mach.fuel,
		}
	end

	R.Finish.OnServerInvoke = function(player: Player, payload: any)
		local p, v = data(player)
		local run = active[player.UserId]
		if not p or not run or type(payload) ~= "table" then return { ok = false } end
		active[player.UserId] = nil
		local function n(x: any, lo: number, hi: number): number
			local y = tonumber(x) or 0
			if y ~= y then return lo end
			return math.clamp(y, lo, math.max(lo, hi))
		end
		local elapsed = os.clock() - run.started
		-- a steered run can beat the plot's average reach a long way with skill, pads and quirks,
		-- but not past what the tyre could physically cover in the time
		-- a run started further down the road is paid for the road it covered, at those zones' rates
		local startM = run.startM or 0
		-- (2026-10-24) no free head start: the old "+ 120" paid 330 m for a half-second "run"
		local metres = n(payload.metres, startM, startM + math.min(run.reach * 8 + 500, math.max(0, elapsed - 0.5) * 420 + 20))
		local covered = metres - startM
		-- (2026-10-24) a bail off the barrel (or a scripted Begin/Finish) isn't a run: it's paid for its
		-- road, but doesn't count toward runs, streak keys, the run-rate or the runs quest
		local short = elapsed < 5 or covered < 100
		-- Cash keeps the generous cap above, so skilled runs are never short-changed. What other
		-- players compare against (boards, weekly, heats, records, titles) only believes up to
		-- 3x the plot's reach; past 4x the run is logged as suspicious.
		-- (2026-10-18: only the road this run covered. A Start Here run used to count from 0, so starting
		-- at the Dunes won every heat, passed distance trials at once and posted 12 km boards for a 50 m roll.
		-- Cash still pays for the road at its zones' rates, above.)
		local ranked = math.min(covered, run.reach * 3 + 300)
		if covered > run.reach * 4 + 300 then
			warn(("[TyreCannon] outlier run: %s (%d) claimed %dm, reach %dm, %.1fs"):format(
				player.Name, player.UserId, math.floor(covered), math.floor(run.reach), elapsed))
		end
		local zone = Game.zoneAt(metres)
		local keySpots = Game.keySpots()
		local keysPossible = 0
		for _, i in ipairs(run.keyZones or {}) do
			local k = keySpots[i]
			if k and k > startM and k <= metres then keysPossible += 1 end
		end
		local keys = math.floor(n(payload.keys, 0, keysPossible))
		local ev = Game.eventAt().on
		local evId = ev and ev.id or nil
		local smashes = math.floor(n(payload.smashes, 0, covered / 20 + 3))
		-- the bounce run: a bounce needs about 10 m of road at the least, a PERFECT is a bounce
		local bounces = math.floor(n(payload.bounces, 0, covered / 10 + 3))
		-- (2026-10-18: these were capped at `bounces`, which only bounce targets count, and targets are
		-- off: every PERFECT and the whole chain were thrown away, so a PERFECTs stage trial could never be
		-- passed. A PERFECT needs about 10 m of road too; a chain link is a PERFECT, a smash or a landing.)
		local perfects = math.floor(n(payload.perfects, 0, covered / 10 + 3))
		local peakChain = math.floor(n(payload.peakChain, 0, perfects + smashes + covered / 40 + 3))
		local blowout = payload.blowout == true

		local mult, parts = cashMult(player, v)
		local rate = Game.Zones[zone].rate
		-- every metre paid at the chain multiplier it was covered with: the average can't beat what
		-- the bounces claimed could make it
		local comboCap = math.min(Config.Run.ComboMax, 1 + Config.Run.ComboStep * peakChain)
		local comboAvg = covered > 1 and n((tonumber(payload.comboMetres) or covered) / covered, 1, comboCap) or 1
		local base = (Game.runCash(metres) - Game.runCash(startM)) * comboAvg
		local smashCash = smashes * 12 * rate * (1 + 0.5 * Game.perkLv(v, "wreck"))
		-- coins picked up on the road (arcs of them now), and PERFECTs
		local metals = type(payload.metals) == "table" and payload.metals or {}
		local coinCap = covered / 6 + 8
		local coins = n(metals.bronze, 0, coinCap) * 3 + n(metals.silver, 0, coinCap) * 8 + n(metals.gold, 0, coinCap) * 25
		local coinCash = coins * rate * (evId == "monsoon" and 2 or 1) * (1 + 0.15 * Game.perkLv(v, "magnet"))
		local tricks = perfects * 8 + math.floor(n(payload.airTime, 0, elapsed))
		local trickCash = tricks * rate
		-- (2026-10-24) the skill zones: "SMASH THROUGH · DOUBLE PAY" (a smash there pays again) and the
		-- zone's own bonus were shown on the road and never paid. A zone is a few hundred metres of road.
		local zoneSmashes = math.floor(n(payload.zoneSmashes, 0, smashes))
		local zoneBonus = math.floor(n(payload.zoneBonus, 0, covered / 500 + 1))
		local zoneCash = (zoneSmashes * 12 * (1 + 0.5 * Game.perkLv(v, "wreck")) + zoneBonus * 48) * rate
		local cash = math.floor((base + smashCash + coinCash + trickCash + zoneCash) * mult)

		p.credits = math.min(1e15, p.credits + cash)
		local streakKey = 0
		if not short then
			v.runs += 1
			streakKey = (v.runs % Game.Keys.PerRunStreak == 0) and 1 or 0
			-- the Key Finder perk: keys every 5 runs
			if v.runs % 5 == 0 then streakKey += Game.perkLv(v, "finder") end
		end
		local roadKeys = keys * (evId == "golden" and 2 or 1)
		grantKeys(v, roadKeys + streakKey)
		Analytics.earn(player, "Cash", cash, p.credits, "Gameplay", "Run")
		Analytics.earn(player, "Keys", roadKeys + streakKey, v.keys, "Gameplay", "Run")
		Analytics.custom(player, "RunMetres", math.floor(metres), {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = Game.Zones[zone] and Game.Zones[zone].name or "?",
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = Game.Tiers[v.tier] and Game.Tiers[v.tier].name or "?",
		})
		local wasBest = ranked > v.bestEver
		v.bestEver = math.max(v.bestEver, ranked)
		v.reached = math.max(v.reached, metres)
		local newZones = {}
		for i = 1, zone do
			local id = Game.Zones[i].id
			if not v.zones[id] then
				v.zones[id] = true
				table.insert(newZones, id)
			end
		end
		-- the compressor pays a share of how fast you earn when you're playing
		local perMin = cash / math.max(elapsed + 8, 15) * 60
		if not short then v.rate = v.rate <= 0 and perMin or (v.rate * 0.8 + perMin * 0.2) end
		v.started = true

		-- what the old run kept, kept again: the ghost of a new best, the photo, quirks seen, the
		-- lifetime stats titles read, the record for the road
		local distance = ranked / Game.StudsToMetres
		local airTime = n(payload.airTime, 0, elapsed + 2)
		local longestAir = n(payload.longestAir, 0, airTime)
		local hits = math.floor(n(payload.hits, 0, metres / 10 + 10))
		local redline = n(payload.redlineSeconds, 0, elapsed + 2)
		local drafts = math.floor(n(payload.drafts, 0, #Config.Difficulty.Checkpoints))
		local perksN = math.floor(n(payload.perks, 0, metres / 15 + 20))
		local tierReached = Config.TierAt(distance)
		local rec = p.records.road or { dist = 0, credits = 0, runs = 0 }
		rec.runs += 1
		rec.dist = math.max(rec.dist, distance)
		rec.credits = math.max(rec.credits, cash)
		p.records.road = rec
		local fromStart = (tonumber(payload.startX) or 0) <= 0
		if wasBest and fromStart and type(payload.ghost) == "string" and #payload.ghost <= 12000 and payload.ghost:match("^[%d%-,;]*$") then
			local splits = {}
			if type(payload.splits) == "table" then
				for i = 1, #Config.Difficulty.Checkpoints do
					local sv = tonumber(payload.splits[i])
					if not sv then break end
					splits[i] = math.floor(n(sv, 0, elapsed) * 10 + 0.5) / 10
				end
			end
			p.ghosts = p.ghosts or {}
			p.ghosts.road = { d = payload.ghost, s = splits }
		end
		local ph = payload.photo
		if type(ph) == "table" and metres >= 40 then
			table.insert(p.photos, 1, {
				track = "road", metres = math.floor(metres), air = n(ph.air, 0, airTime),
				speed = math.floor(n(ph.speed, 0, 3000)),
				x = n(ph.x, 0, distance + 100), y = n(ph.y, -50000, 50000), z = n(ph.z, -5000, 5000),
				vx = n(ph.vx, -5000, 5000), vy = n(ph.vy, -5000, 5000), roll = n(ph.roll, -1e9, 1e9),
				seed = run.seed, skin = p.skin, rim = p.rim, caption = "", best = wasBest, at = os.time(),
			})
			while #p.photos > 6 do table.remove(p.photos) end
		end
		if type(payload.seen) == "table" then
			local k = 0
			for _, id in ipairs(payload.seen) do
				k += 1
				if k > 40 then break end
				if type(id) == "string" and Config.PerksById[id] then p.codex[id] = true end
			end
		end
		local st = p.stats
		st.runs += 1
		st.redlineSeconds += redline
		if payload.flawless == true then st.flawless += 1 end
		if blowout then st.overheats += 1 end
		st.hits += hits
		if tierReached >= 3 and not blowout and hits == 0 then st.cleanRuns += 1 end
		st.smashes += smashes
		st.maxTier = math.max(st.maxTier, tierReached)
		st.longestAir = math.max(st.longestAir, longestAir)
		st.drafts += drafts
		st.trackBest.road = math.max(st.trackBest.road or 0, distance)
		local codexCount = 0
		for _ in pairs(p.codex) do codexCount += 1 end
		st.codexMax = math.max(st.codexMax, codexCount)
		p.totals.perks += perksN
		p.totals.airtime += airTime

		p.totals.runs += 1
		p.totals.distance += metres / Game.StudsToMetres
		p.totals.credits += cash
		p.lifetime.bestDistance = math.max(p.lifetime.bestDistance, ranked / Game.StudsToMetres)
		p.lifetime.credits += cash
		S.postBoard("distance", player.UserId, p.lifetime.bestDistance)
		S.postBoard("credits", player.UserId, p.lifetime.credits)
		if S.postWeekly then S.postWeekly(player.UserId, ranked) end
		if S.heatFinish then S.heatFinish(player, ranked, cash) end
		if S.growth then S.growth(player, "run", { zone = zone, metres = metres, best = wasBest, perfects = perfects }) end
		-- v4: the stage's trial and the quests, from the checked numbers
		local coinCount = math.floor(n(metals.bronze, 0, coinCap) + n(metals.silver, 0, coinCap) + n(metals.gold, 0, coinCap))
		local runVals = { metres = ranked, perfects = perfects, smashes = smashes, longestAir = longestAir, coins = coinCount, hits = hits }
		local trial = v.trial
		local trialJust = false
		if trial and not trial.done then
			local val = Goals.runValue(trial.k, runVals)
			trial.best = math.max(trial.best or 0, val)
			if val >= trial.t then
				trial.done = true
				trialJust = true
				Analytics.custom(player, "TrialDone", v.tier)
			else
				-- a run that falls short makes the next try a little easier
				trial.tries = (trial.tries or 0) + 1
				-- (never above what it was: a trial saved before the targets went up keeps its old target)
				trial.t = math.min(trial.t or math.huge, Goals.trial(v.pres, v.tier, trial.tries, Game.perkLv(v, "trials")).t)
			end
		end
		if not short then questAdd(player, v, "runs", 1) end
		questAdd(player, v, "km", covered / 1000)
		questAdd(player, v, "perfects", perfects)
		questAdd(player, v, "smashes", smashes)
		questAdd(player, v, "coinsTotal", coinCount)
		questAdd(player, v, "best", ranked)
		S.push(player)
		return {
			trial = v.trial,
			trialJust = trialJust,
			ok = true,
			cash = cash,
			event = evId,
			metres = metres,
			best = wasBest,
			keys = roadKeys,
			streakKey = streakKey,
			zone = zone,
			newZones = newZones,
			breakdown = { base = math.floor(base), smash = math.floor(smashCash), coins = math.floor(coinCash), tricks = math.floor(trickCash), zone = math.floor(zoneCash),
				mult = mult, parts = parts, combo = comboAvg },
			bounces = bounces,
			peakChain = peakChain,
			perfects = perfects,
			smashes = smashes,
			blowout = blowout,
			canOverhaul = Game.canUpgradePlot(v, p.credits),
		}
	end

	--==============================================================
	-- the plot
	--==============================================================
	R.Buy.OnServerInvoke = function(player: Player, id: any)
		if S.throttled(player, 0.08, "v2buy") then return { ok = false, err = "Easy." } end
		local p, v = data(player)
		if not p or type(id) ~= "string" or not Game.MachinesById[id] then return { ok = false, err = "Nothing to buy." } end
		local level = v.mach[id] or 0
		if level >= Game.maxLevel(id) then
			return { ok = false, err = (id == "compressor" or id == "rack") and "Maxed out." or "Maxed for this plot. Overhaul to go further." }
		end
		local price = Game.machinePrice(id, level, v.tier, v)
		if p.credits < price then return { ok = false, err = "Not enough cash.", short = price - p.credits } end
		p.credits -= price
		v.mach[id] = level + 1
		questAdd(player, v, "upgrades", 1)
		Analytics.spend(player, "Cash", price, p.credits, "Shop", ("Machine:%s:%d"):format(id, level + 1))
		if S.growth then S.growth(player, "upgrade", id) end
		S.push(player)
		return { ok = true, id = id, level = level + 1, price = price, cash = p.credits }
	end

	R.Overhaul.OnServerInvoke = function(player: Player)
		local p, v = data(player)
		if not p then return { ok = false } end
		if v.tier >= #Game.Tiers then return { ok = false, err = "Your yard is the top stage." } end
		if not Game.machinesMaxed(v) then return { ok = false, err = "Max every machine first." } end
		if not Game.trialDone(v) then return { ok = false, err = "Finish the stage trial first." } end
		local cost = Game.plotUpgradeCost(v.tier, v)
		if p.credits < cost then
			return { ok = false, err = ("Need $%s more."):format(Game.short(cost - p.credits)), short = cost - p.credits }
		end
		p.credits -= cost
		v.overhauls += 1
		v.tier = math.min(v.tier + 1, #Game.Tiers)
		Analytics.spend(player, "Cash", cost, p.credits, "Shop", "StageUp:" .. Game.Tiers[v.tier].name)
		Analytics.custom(player, "StageUp", v.tier)
		-- (the Head Start perk: every stage starts with the machines a few levels up)
		local head = math.min(Game.perkLv(v, "headstart"), Game.LevelsPerTier - 1)
		for _, id in ipairs({ "cannon", "fuel", "cooling" }) do v.mach[id] = head end
		v.reached = 0
		syncV4(player, p, v)
		if S.growth then S.growth(player, "stage", v.tier) end
		S.push(player)
		return { ok = true, overhauls = v.overhauls, tier = v.tier }
	end

	-- prestige (Game.Prestige): the top stage with its machines maxed, and one more stage's price
	R.Prestige.OnServerInvoke = function(player: Player)
		if S.throttled(player, 1, "v2prestige") then return { ok = false, err = "Easy." } end
		local p, v = data(player)
		if not p then return { ok = false } end
		if v.tier < #Game.Tiers then return { ok = false, err = "Reach the top yard stage first." } end
		if (p.prestige or 0) >= Game.Prestige.Max then return { ok = false, err = "That's the top prestige." } end
		if not Game.machinesMaxed(v) then return { ok = false, err = "Max every machine first." } end
		if not Game.trialDone(v) then return { ok = false, err = "Finish the stage trial first." } end
		local cost = Game.prestigeCost(v)
		if p.credits < cost then
			return { ok = false, err = ("Need $%s more."):format(Game.short(cost - p.credits)), short = cost - p.credits }
		end
		p.credits -= cost
		p.prestige = (p.prestige or 0) + 1
		local keys = Game.Prestige.Keys + Game.Prestige.KeysPer * p.prestige
		grantKeys(v, keys)
		-- v4: a prestige is a rebirth: the climb starts from nothing (cash included), and a perk is offered
		local spent = p.credits
		p.credits = 0
		v.tier = 1
		v.overhauls = 0
		local head = math.min(Game.perkLv(v, "headstart"), Game.LevelsPerTier - 1)
		for _, id in ipairs(Game.Overhaul.Machines) do v.mach[id] = head end
		v.reached = 0
		-- (2026-10-24) the auto-cannon, offline pay, quests and daily cash all pay from the run rate; the
		-- top stage's rate made the restart no climb at all. The next run sets it afresh.
		v.rate = 0
		v.perkOffer = Game.perkOffer(player.UserId, p.prestige, v.perks)
		syncV4(player, p, v)
		Analytics.spend(player, "Cash", spent, 0, "Shop", "PrestigeReset")
		Analytics.spend(player, "Cash", cost, p.credits, "Shop", "Prestige:" .. p.prestige)
		Analytics.earn(player, "Keys", keys, v.keys, "Gameplay", "Prestige")
		Analytics.custom(player, "Prestige", p.prestige)
		R.Announce:FireAllClients({ kind = "prestige", name = player.DisplayName, userId = player.UserId, level = p.prestige })
		if S.growth then S.growth(player, "prestige", p.prestige) end
		S.push(player)
		return { ok = true, level = p.prestige, mult = Game.prestigeMult(p.prestige), keys = keys, offer = v.perkOffer }
	end

	--==============================================================
	-- tyres
	--==============================================================
	local function roll(v, zoneId: string, withKeys: boolean?, minOrder: number?)
		local ev = Game.eventAt().on
		local list = Game.crateOdds(zoneId, nil, ev and ev.id == "rush" and 5 or nil)
		-- the pity: enough crates (keys and cash count apart) without a Legendary and this one is the
		-- banner's
		if withKeys and v.pity + 1 >= Game.Crate.Pity then return Game.banner(nil, zoneId).legendary end
		if not withKeys and (v.cashPity or 0) + 1 >= Game.Crate.CashPity then return Game.banner(nil, zoneId).legendary end
		-- the big open's floor: only what's at least this rare
		if minOrder then
			local kept = {}
			for _, e in ipairs(list) do
				if Game.RaritiesById[Game.TyresById[e.id].rarity].order >= minOrder then table.insert(kept, e) end
			end
			if #kept > 0 then list = kept end
		end
		local luck = 1
		if v.passes.lucky then luck *= 1.5 end
		if boostOn(v, "luck2") then luck *= 2 end
		luck *= 1 + 0.15 * Game.perkLv(v, "luck")
		if S.serverLuckUntil and S.serverLuckUntil > os.time() then luck *= 2 end
		-- luck lifts the odds of everything above Common
		-- (2026-10-24) by what it says: the chance of a Rare, and of an Epic or better, is multiplied by
		-- the luck (key crates: Epic and up by KeyLuck as well), and Common gives up the difference. Scaling
		-- the weights and renormalising delivered about half: "double luck" was +35%, "15% more" +7%.
		local epic = Game.RaritiesById.Epic.order
		local share = { c = 0, r = 0, e = 0 }
		local function group(e): string
			local r = Game.TyresById[e.id].rarity
			if r == "Common" then return "c" end
			return if Game.RaritiesById[r].order >= epic then "e" else "r"
		end
		local sum = 0
		for _, e in ipairs(list) do
			share[group(e)] += e.odds
			sum += e.odds
		end
		local want = { e = 0, r = 0 }
		if sum > 0 then
			local pe, pr = share.e / sum, share.r / sum
			want.e = math.min(0.9, pe * luck * (if withKeys then Game.Crate.KeyLuck else 1))
			want.r = math.min(0.95 - want.e, pr * luck)
			want.c = 1 - want.e - want.r
		end
		local total = 0
		for _, e in ipairs(list) do
			local g = group(e)
			local base = share[g] / math.max(sum, 1e-9)
			e.w = if base > 0 and want[g] then e.odds * want[g] / base else e.odds
			total += e.w
		end
		local x = math.random() * total
		for _, e in ipairs(list) do
			x -= e.w
			if x <= 0 then return e.id end
		end
		return list[1].id
	end

	-- pay = "cash" (the zone's cash price at your stage) or "keys" (premium luck, counts to the pity)
	R.OpenCrate.OnServerInvoke = function(player: Player, zoneId: any, count: any, pay: any)
		if S.throttled(player, 0.25, "v2crate") then return { ok = false, err = "Easy." } end
		local p, v = data(player)
		if not p or type(zoneId) ~= "string" or not Game.ZonesById[zoneId] then return { ok = false, err = "No such crate." } end
		if not v.zones[zoneId] then return { ok = false, err = "Reach " .. Game.ZonesById[zoneId].name .. " to unlock this crate." } end
		-- one, or the big open (Game.Crate.Multi): nothing in between
		local times = if (tonumber(count) or 1) >= Game.Crate.Multi then Game.Crate.Multi else 1
		local withKeys = pay == "keys"
		if #v.inv + times > LoopData.MAX_TYRES then return { ok = false, err = "Your tyre rack is full. Forge some." } end
		if withKeys then
			local price = Game.cratePrice(zoneId)
			if v.keys < price * times then return { ok = false, err = "Not enough keys.", short = price * times - v.keys } end
			v.keys -= price * times
			Analytics.spend(player, "Keys", price * times, v.keys, "Shop", "Crate:" .. zoneId)
		else
			local price = Game.crateCash(zoneId, v.tier, v)
			if p.credits < price * times then return { ok = false, err = "Not enough cash.", short = price * times - p.credits } end
			p.credits -= price * times
			Analytics.spend(player, "Cash", price * times, p.credits, "Shop", "Crate:" .. zoneId)
		end
		Analytics.count("ev:CratesOpened", times)
		local got = {}
		local legendary = Game.RaritiesById.Legendary.order
		local floorOrder = Game.RaritiesById[Game.Crate.MultiFloor].order
		local rolled = {}
		local hitFloor = false
		for i = 1, times do
			-- the big open's last crate is at least Rare if none of the others were
			local id = roll(v, zoneId, withKeys, if times >= Game.Crate.Multi and i == times and not hitFloor then floorOrder else nil)
			local order = Game.RaritiesById[Game.TyresById[id].rarity].order
			if order >= floorOrder then hitFloor = true end
			if withKeys then
				if order >= legendary then v.pity = 0 else v.pity += 1 end
			else
				if order >= legendary then v.cashPity = 0 else v.cashPity = (v.cashPity or 0) + 1 end
			end
			table.insert(rolled, id)
		end
		for _, id in ipairs(rolled) do
			local ev = Game.eventAt().on
			local mutLuck = (v.passes.lucky and 1.5 or 1) * (withKeys and 1.5 or 1)
			local entry = { uid = v.nextUid, id = id, forge = 0, mut = Game.rollMutation(math.random(), mutLuck, ev and ev.id or nil) }
			v.nextUid += 1
			table.insert(v.inv, entry)
			local fresh = not v.index[id]
			v.index[id] = true
			table.insert(got, { uid = entry.uid, id = id, new = fresh, mut = entry.mut })
			local r = Game.RaritiesById[Game.TyresById[id].rarity]
			if r.order >= Game.RaritiesById.Legendary.order then
				R.Announce:FireAllClients({ kind = "pull", name = player.DisplayName, userId = player.UserId, tyre = id, rarity = r.id })
			end
		end
		checkIndex(player, v)
		questAdd(player, v, "crates", times)
		if S.growth then S.growth(player, "tyres", got) end
		S.push(player)
		return { ok = true, got = got, keys = v.keys, credits = p.credits, pity = v.pity, cashPity = v.cashPity }
	end

	R.Equip.OnServerInvoke = function(player: Player, uid: any, slot: any)
		local p, v = data(player)
		uid = tonumber(uid)
		-- "best" is the one call that names no tyre: it picks them all
		if not p or (not uid and slot ~= "best") then return { ok = false } end
		local owned = slot == "best"
		for _, t in ipairs(v.inv) do
			if t.uid == uid then owned = true end
		end
		if not owned then return { ok = false, err = "You don't own that tyre." } end
		local slots = 1 + (v.mach.rack or 0) + (v.passes.spares2 and 2 or 0)
		if slot == "launch" then
			local old = v.launch
			local at = table.find(v.spares, uid)
			if at then v.spares[at] = old end
			v.launch = uid
		elseif slot == "spare" then
			if uid == v.launch then return { ok = false, err = "That's your launch tyre." } end
			if table.find(v.spares, uid) then
				table.remove(v.spares, table.find(v.spares, uid))
			elseif #v.spares >= math.min(slots, LoopData.MAX_SPARES) then
				return { ok = false, err = "Spare rack is full. Upgrade the Spare Rack." }
			else
				table.insert(v.spares, uid)
			end
		elseif slot == "best" then
			-- fill the launch slot and the spares with the strongest tyres owned
			local sorted = table.clone(v.inv)
			table.sort(sorted, function(a, b)
				local pa, pb = Game.tyrePoints(a.id, a.forge, a.mut), Game.tyrePoints(b.id, b.forge, b.mut)
				if pa ~= pb then return pa > pb end
				return a.uid < b.uid
			end)
			v.launch = sorted[1].uid
			v.spares = {}
			for i = 2, math.min(#sorted, slots + 1) do table.insert(v.spares, sorted[i].uid) end
		end
		S.push(player)
		return { ok = true, launch = v.launch, spares = v.spares }
	end

	R.Forge.OnServerInvoke = function(player: Player, id: any, forge: any)
		local p, v = data(player)
		forge = math.floor(tonumber(forge) or 0)
		if not p or type(id) ~= "string" or not Game.TyresById[id] or forge < 0 or forge > 2 then return { ok = false } end
		local need = Game.fuseNeed(id)
		local pick = {}
		for _, t in ipairs(v.inv) do
			if t.id == id and t.forge == forge and t.uid ~= v.launch and not table.find(v.spares, t.uid) and not t.fav then
				table.insert(pick, t.uid)
			end
		end
		-- the equipped ones count too if there aren't enough spare copies (a favourite never does)
		if #pick < need then
			for _, t in ipairs(v.inv) do
				if t.id == id and t.forge == forge and not table.find(pick, t.uid) and not t.fav then table.insert(pick, t.uid) end
			end
		end
		if #pick < need then return { ok = false, err = ("You need %d of these (favourites are kept)."):format(need) } end
		local gone = {}
		for i = 1, need do gone[pick[i]] = true end
		local keep = {}
		for _, t in ipairs(v.inv) do
			if not gone[t.uid] then table.insert(keep, t) end
		end
		local bestMut, bestMult = nil, 1
		for _, t in ipairs(v.inv) do
			if gone[t.uid] and t.mut and Game.MutationsById[t.mut] and Game.MutationsById[t.mut].mult > bestMult then
				bestMut, bestMult = t.mut, Game.MutationsById[t.mut].mult
			end
		end
		local made = { uid = v.nextUid, id = id, forge = forge + 1, mut = bestMut }
		v.nextUid += 1
		table.insert(keep, made)
		v.inv = keep
		if gone[v.launch] then v.launch = made.uid end
		local spares = {}
		for _, u in ipairs(v.spares) do
			if not gone[u] then table.insert(spares, u) end
		end
		v.spares = spares
		S.push(player)
		return { ok = true, made = made }
	end

	-- the yard's layout: snapped to the grid, kept on the floor and clear, then shown to everyone
	R.Layout.OnServerInvoke = function(player: Player, raw: any)
		local p, v = data(player)
		if not p or type(raw) ~= "table" then return { ok = false } end
		local layout = Game.yardLayout(raw, v and v.tier or 1, { prestige = p.prestige, passes = v.passes })
		local ok, bad = Game.yardCheck(layout, v and v.tier or 1)
		if not ok then
			local ids = {}
			for id in pairs(bad) do table.insert(ids, id) end
			return { ok = false, bad = ids }
		end
		local before = v.layout and v.layout.decor and #v.layout.decor or 0
		v.layout = layout
		questAdd(player, v, "decor", #(layout.decor or {}) - before)
		local st = restyle(player, v)
		S.push(player)
		return { ok = true, layout = Game.yardEncode(layout), style = st }
	end

	-- the yard's look: the stage's, the Hall of Prestige (P1+) or the Midnight Garage (its pass)
	R.Look.OnServerInvoke = function(player: Player, id: any, way: any)
		if S.throttled(player, 0.5, "v2look") then return { ok = false } end
		local p, v = data(player)
		local look = Game.YardLooksById[tostring(id)]
		if not (p and look) then return { ok = false } end
		if not Game.lookOpen(look, p.prestige, v.passes) then
			return { ok = false, err = if look.pass then "locked_pass" else "locked_prestige" }
		end
		v.look = { id = look.id, way = Game.yardWay(tostring(way)).id }
		restyle(player, v)
		S.push(player)
		return { ok = true }
	end

	--==============================================================
	-- v4: perks, likes, feedback
	--==============================================================
	-- keep one of the three perks the last prestige offered
	R.PickPerk.OnServerInvoke = function(player: Player, id: any)
		if S.throttled(player, 0.5, "v2perk") then return { ok = false } end
		local p, v = data(player)
		if not p or not v.perkOffer or type(id) ~= "string" or not table.find(v.perkOffer, id) then return { ok = false } end
		local pk = Game.PerksById[id]
		v.perks[id] = math.min(pk.max, (v.perks[id] or 0) + 1)
		v.perkOffer = nil
		-- (what a perk changes about the climb in progress, it changes now)
		if id == "headstart" then
			local head = math.min(Game.perkLv(v, "headstart"), Game.LevelsPerTier - 1)
			for _, mid in ipairs(Game.Overhaul.Machines) do v.mach[mid] = math.max(v.mach[mid] or 0, head) end
		elseif id == "trials" and v.trial and not v.trial.done then
			v.trial.t = math.min(v.trial.t or math.huge, Goals.trial(v.pres, v.tier, v.trial.tries or 0, Game.perkLv(v, "trials")).t)
		end
		restyle(player, v)
		Analytics.custom(player, "PerkPicked", v.perks[id], { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = id })
		S.push(player)
		return { ok = true, perks = v.perks }
	end

	-- like another player's yard: once a day per yard; the owner gets a key for each (up to 5 a day)
	-- and the like counts toward their week
	R.Like.OnServerInvoke = function(player: Player, ownerId: any)
		if S.throttled(player, 0.5, "v2like") then return { ok = false } end
		local p, v = data(player)
		local uid = tonumber(ownerId)
		if not p or not uid then return { ok = false } end
		if uid == player.UserId then return { ok = false, err = "That's your own yard." } end
		local owner = Players:GetPlayerByUserId(uid)
		local op, ov = nil, nil
		if owner then op, ov = data(owner) end
		if not (op and ov) then return { ok = false, err = "They've left the server." } end
		local key = tostring(uid)
		if v.liked.to[key] then return { ok = false, err = "You've liked this yard today." } end
		v.liked.to[key] = true
		ov.likes.n += 1
		local keyed = ov.likeKeys.n < 5
		if keyed then
			ov.likeKeys.n += 1
			ov.keys = math.min(1e6, ov.keys + 1)
		end
		R.Quest:FireClient(owner :: Player, { kind = "like", text = player.DisplayName .. " liked your yard", keys = if keyed then 1 else nil })
		questAdd(player, v, "likes", 1)
		Analytics.custom(player, "YardLike", 1)
		S.push(owner :: Player)
		S.push(player)
		return { ok = true, likes = ov.likes.n }
	end

	-- the playtest's notes: kept in a DataStore for reading later (never shown to other players)
	local fbStore: DataStore? = nil
	pcall(function() fbStore = DataStoreService:GetDataStore("TC_Feedback_v1") end)
	local fbCount: { [number]: number } = {}
	R.Feedback.OnServerInvoke = function(player: Player, kind: any, text: any, rating: any)
		if S.throttled(player, 10, "v2feedback") then return { ok = false, err = "Thanks! Give it a moment before sending more." } end
		fbCount[player.UserId] = (fbCount[player.UserId] or 0) + 1
		if fbCount[player.UserId] > 12 then return { ok = false, err = "That's plenty for one session. Thank you!" } end
		local p, v = data(player)
		local entry = {
			u = player.UserId, name = player.Name, t = os.time(),
			kind = string.sub(tostring(kind or "note"), 1, 16),
			text = if type(text) == "string" then string.sub(text, 1, 600) else "",
			rating = math.clamp(math.floor(tonumber(rating) or 0), 0, 5),
			tier = v and v.tier or 0, pres = p and p.prestige or 0, runs = v and v.runs or 0,
			ver = Config.VersionLabel,
		}
		Analytics.custom(player, "Feedback", entry.rating, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = entry.kind })
		Analytics.note(entry)
		if fbStore then
			task.spawn(function()
				pcall(function() (fbStore :: DataStore):SetAsync(("%d_%d"):format(player.UserId, entry.t), entry) end)
			end)
		end
		return { ok = true }
	end

	-- a favourite: starred at the Workbench, kept out of every fuse
	R.Fav.OnServerInvoke = function(player: Player, uid: any, on: any)
		local p, v = data(player)
		uid = tonumber(uid)
		if not p or not uid then return { ok = false } end
		for _, t in ipairs(v.inv) do
			if t.uid == uid then
				t.fav = on == true or nil
				S.push(player)
				return { ok = true, fav = t.fav == true }
			end
		end
		return { ok = false }
	end

	R.Design.OnServerInvoke = function(player: Player, uid: any, design: any)
		local p, v = data(player)
		uid = tonumber(uid)
		if not p or not uid or type(design) ~= "table" then return { ok = false } end
		local owned = false
		for _, t in ipairs(v.inv) do
			if t.uid == uid then owned = true end
		end
		if not owned then return { ok = false } end
		-- only the fields the Tyre Studio uses, clamped; sidewall text is filtered for everyone else
		-- (2026-10-24: paint's RimPrimary is the tyre's tint in the Customization tab; smoke is the
		-- colour of its dust and tread smoke in a run; a sticker can carry a tint, col)
		-- (a number, never NaN, which would poison the save)
		local function num(x: any, default: number): number
			local n = tonumber(x)
			if n == nil or n ~= n then return default end
			return n
		end
		local function rgb(c: any): { number }?
			if type(c) ~= "table" or #c ~= 3 then return nil end
			return { math.clamp(num(c[1], 0), 0, 1), math.clamp(num(c[2], 0), 0, 1), math.clamp(num(c[3], 0), 0, 1) }
		end
		local clean = { paint = {}, finish = {}, stickers = {}, text = "", smoke = rgb(design.smoke) }
		if type(design.paint) == "table" then
			for _, zone in ipairs({ "Rubber", "RimPrimary", "RimSecondary", "Accent" }) do
				local c = design.paint[zone]
				if type(c) == "table" and #c == 3 then
					clean.paint[zone] = { math.clamp(tonumber(c[1]) or 0, 0, 1), math.clamp(tonumber(c[2]) or 0, 0, 1), math.clamp(tonumber(c[3]) or 0, 0, 1) }
				end
				local f = type(design.finish) == "table" and design.finish[zone]
				if f == "matte" or f == "gloss" or f == "metal" or f == "chrome" then clean.finish[zone] = f end
			end
		end
		if type(design.text) == "string" then
			local ok, filtered = pcall(function()
				local TextService = game:GetService("TextService")
				local res = TextService:FilterStringAsync(design.text:sub(1, 24), player.UserId)
				return res:GetNonChatStringForBroadcastAsync()
			end)
			clean.text = ok and filtered or ""
		end
		if type(design.stickers) == "table" then
			for _, s in ipairs(design.stickers) do
				if #clean.stickers >= (Config.Stickers and Config.Stickers.MaxPerTyre or 8) then break end
				if type(s) == "table" and type(s.id) == "string" then
					table.insert(clean.stickers, {
						id = s.id:sub(1, 40),
						a = math.clamp(num(s.a, 0), -360, 360),
						r = math.clamp(num(s.r, 0.85), 0.6, 1.0),
						rot = math.clamp(num(s.rot, 0), -360, 360),
						size = math.clamp(num(s.size, 1), 0.3, 2.5),
						repeatN = math.clamp(math.floor(num(s.repeatN, 1)), 1, 6),
						mirror = s.mirror == true,
						col = rgb(s.col),
					})
				end
			end
		end
		v.designs[tostring(uid)] = clean
		S.push(player)
		return { ok = true, design = clean }
	end

	--==============================================================
	-- v3: the Test Drive, the login calendar
	--==============================================================
	-- (zoneId: the crate it was asked from; it drives that crate's featured Legendary)
	R.TestDrive.OnServerInvoke = function(player: Player, zoneId: any)
		local p, v = data(player)
		if not p then return { ok = false } end
		local span = Game.Crate.BannerHours * 3600
		local now = os.time()
		if now - v.testDrive < span and math.floor(v.testDrive / span) == math.floor(now / span) then
			return { ok = false, err = "One Test Drive a banner. The next banner brings another." }
		end
		v.testDrive = now
		v.testArmed = true
		local zid = if type(zoneId) == "string" and Game.ZonesById[zoneId] then zoneId else nil
		v.testTyre = Game.banner(nil, zid).legendary
		S.push(player)
		return { ok = true, tyre = v.testTyre }
	end

	R.Daily.OnServerInvoke = function(player: Player)
		local p, v = data(player)
		if not p then return { ok = false } end
		local today = Game.utcDay()
		if v.daily.last == today then return { ok = false, err = "Come back tomorrow." } end
		local streak = (v.daily.last == today - 1) and (v.daily.streak + 1) or 1
		local day = ((streak - 1) % #Game.Daily) + 1
		local gift = Game.Daily[day]
		local reward = { day = day, streak = streak }
		if gift.keys then
			grantKeys(v, gift.keys)
			reward.keys = gift.keys
			Analytics.earn(player, "Keys", gift.keys, v.keys, "TimedReward", "Daily")
		end
		if gift.cashRuns then
			local cash = math.floor(math.max(80, v.rate / 60 * 30) * gift.cashRuns)
			p.credits += cash
			reward.cash = cash
			Analytics.earn(player, "Cash", cash, p.credits, "TimedReward", "Daily")
		end
		v.daily = { last = today, streak = streak }
		if S.growth then S.growth(player, "daily") end
		S.push(player)
		return { ok = true, reward = reward }
	end

	--==============================================================
	-- v3: the auto-cannon. While you're in the server and not out on a run, your yard's cannon fires
	-- on its own: a share of your recent rate, shown to everyone as a shot leaving your yard.
	--==============================================================
	-- the AFK report: every auto-cannon shot is remembered for a while, so when someone goes AFK
	-- (TyreCannonServer marks it after AFK_AFTER seconds without moving) their report starts from
	-- when they stopped moving; when they're back it's sent to them (Hub2:afkReport)
	local AFK_AFTER = 600	-- (TyreCannonServer's AFK_SECONDS)
	local recent: { [number]: { { number } } } = {}	-- userId -> { { time, cash } } of the last AFK_AFTER seconds
	local afkLog: { [number]: { since: number, shots: number, cash: number } } = {}
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for _, pl in ipairs(Players:GetPlayers()) do
				local uid = pl.UserId
				local status = S.statusOf[uid] or "base"
				local a = afkLog[uid]
				if status == "afk" and not a then
					a = { since = now - AFK_AFTER, shots = 0, cash = 0 }
					for _, s in ipairs(recent[uid] or {}) do
						if s[1] >= a.since then a.shots += 1; a.cash += s[2] end
					end
					afkLog[uid] = a
				elseif status ~= "afk" and a then
					afkLog[uid] = nil
					local p = S.profiles[uid]
					if a.shots > 0 and p then
						R.AfkReport:FireClient(pl, { seconds = now - a.since, shots = a.shots, cash = a.cash, balance = p.credits })
					end
				end
			end
		end
	end)

	task.spawn(function()
		local A = Game.AutoCannon
		while true do
			-- (when the next shot goes, for the hub's countdown)
			workspace:SetAttribute("AutoCannonAt", workspace:GetServerTimeNow() + A.Every)
			task.wait(A.Every)
			for _, pl in ipairs(Players:GetPlayers()) do
				local p = S.profiles[pl.UserId]
				local v = p and p.v2
				local status = S.statusOf[pl.UserId] or "base"
				local plot = S.plotOf(pl.UserId)
				if v and plot and v.runs > 0 and v.rate > 0 and (status == "base" or status == "afk") then
					local share = (v.passes.autolaunch and A.PassShare or A.Share)
					share = math.min(A.MaxShare, share * Game.styleBonus(v.style) * (1 + 0.2 * Game.perkLv(v, "idle")))
					local cash = math.floor(v.rate / 60 * A.Every * share)
					if cash > 0 then
						p.credits = math.min(1e15, p.credits + cash)
						Analytics.earn(pl, "Cash", cash, p.credits, "Gameplay", "AutoCannon")
						-- (for the AFK report)
						local now = os.time()
						local list = recent[pl.UserId] or {}
						recent[pl.UserId] = list
						table.insert(list, { now, cash })
						while list[1] and list[1][1] < now - AFK_AFTER do table.remove(list, 1) end
						local a = afkLog[pl.UserId]
						if a then
							a.shots += 1
							a.cash += cash
						end
						for _, other in ipairs(Players:GetPlayers()) do
							R.AutoFire:FireClient(other, plot, other == pl and cash or nil)
						end
						S.push(pl)
					end
				end
			end
		end
	end)

	-- Roblox Premium: a key a day (paid on join, or the moment they become a member)
	local function premiumDaily(player: Player)
		local p, v = data(player)
		if not p or player.MembershipType ~= Enum.MembershipType.Premium then return end
		local today = Game.utcDay()
		if v.premDay == today then return end
		v.premDay = today
		v.keys = math.min(1e6, v.keys + Game.Premium.DailyKeys)
		Analytics.earn(player, "Keys", Game.Premium.DailyKeys, v.keys, "Gameplay", "Premium")
		task.delay(10, function()
			if player.Parent then R.Quest:FireClient(player, { kind = "premium", text = "Premium bonus: your daily key", keys = Game.Premium.DailyKeys }) end
		end)
		S.push(player)
	end
	Players.PlayerMembershipChanged:Connect(premiumDaily)

	local function onJoin(player: Player)
		task.spawn(function()
			local t0 = os.clock()
			while not S.profiles[player.UserId] and os.clock() - t0 < 20 and player.Parent do task.wait(0.2) end
			local p, v = data(player)
			if not p then return end
			restyle(player, v)
			if v.runs == 0 then Analytics.count("newPlayers") end
			local now = os.time()
			-- v4: the yard earns while you're away: a share of your recent rate for up to
			-- Game.Offline.CapHours, raised by the yard's style and the Idle Hands perk
			local away = math.clamp(now - (v.lastSeen or now), 0, Game.Offline.CapHours * 3600)
			if away >= 300 and v.lastSeen > 0 and (v.rate or 0) > 0 and v.runs > 0 then
				restyle(player, v)
				local cash = math.floor(v.rate / 60 * away * Game.Offline.Share * Game.styleBonus(v.style) * (1 + 0.2 * Game.perkLv(v, "idle")))
				if cash > 0 then
					p.credits = math.min(1e15, p.credits + cash)
					Analytics.earn(player, "Cash", cash, p.credits, "Gameplay", "Offline")
					task.delay(8, function()
						if player.Parent then R.Offline:FireClient(player, { seconds = away, cash = cash, style = v.style }) end
					end)
				end
			end
			v.lastSeen = now
			S.push(player)
			premiumDaily(player)
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, pl in ipairs(Players:GetPlayers()) do onJoin(pl) end
	Players.PlayerRemoving:Connect(function(pl)
		local p = S.profiles[pl.UserId]
		if p and p.v2 then p.v2.lastSeen = os.time() end
		active[pl.UserId] = nil
		recent[pl.UserId] = nil
		afkLog[pl.UserId] = nil
	end)
	-- lastSeen ticks while they play, so a crash still counts the time correctly
	task.spawn(function()
		while true do
			task.wait(60)
			for _, pl in ipairs(Players:GetPlayers()) do
				local p = S.profiles[pl.UserId]
				if p and p.v2 then p.v2.lastSeen = os.time() end
			end
		end
	end)
end

return Loop
