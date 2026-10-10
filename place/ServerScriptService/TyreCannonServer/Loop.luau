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
local LoopData = require(script.Parent.LoopData)

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
		Launched = remote(folder, "RemoteEvent", "Launched"),      -- (userId, plotIndex, grade): everyone sees the shot
		Reward = remote(folder, "RemoteEvent", "Reward"),          -- a reward worth a banner: { text, keys, bonus }
		AutoFire = remote(folder, "RemoteEvent", "AutoFire"),      -- (plotIndex, cash for the owner or nil)
	}
	S.V2 = R

	local active: { [number]: any } = {}

	local function data(player: Player)
		local p = S.profiles[player.UserId]
		if not p then return nil, nil end
		p.v2 = p.v2 or LoopData.default()
		return p, p.v2
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
		return tyres * over * bought * (1 + friends) * index, { tyres = tyres, overhaul = over, bought = bought, friends = 1 + friends, index = index }
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
			R.Reward:FireClient(player, { text = ("Index: %d tyres found"):format(v.indexPaid * Game.IndexEvery), keys = 1,
				bonus = ("+%d%% cash for good"):format(math.floor(Game.IndexBonus * 100 * v.indexPaid + 0.5)) })
		end
	end

	--==============================================================
	-- the run
	--==============================================================
	-- zoneId: start the run at the start of a zone you've already reached (the zone map's Start Here)
	R.Begin.OnServerInvoke = function(player: Player, zoneId: any)
		if S.throttled(player, 0.5, "v2begin") then return { ok = false, err = "One at a time." } end
		local p, v = data(player)
		if not p then return { ok = false, err = "Still loading your save." } end
		local reach = Game.reachMetres(v.mach, v.tier)
		-- a heat racer runs the heat's road; everyone else a fresh one
		local seed = (S.heatSeedFor and S.heatSeedFor[player.UserId]) or math.random(1, 2147483646)
		local from = type(zoneId) == "string" and Game.ZonesById[zoneId]
		local startM = (from and v.zones[from.id]) and from.start or 0
		active[player.UserId] = { seed = seed, reach = reach, started = os.clock(), startM = startM }
		local t = launchTyre(v)
		-- Studio only: try any tyre on the next run (player attribute DebugTyre = tyre id)
		local dbg = game:GetService("RunService"):IsStudio() and player:GetAttribute("DebugTyre")
		if type(dbg) == "string" and Game.TyresById[dbg] then t = { uid = -1, id = dbg, forge = 0 } end
		-- a Test Drive: the featured Legendary for this one run
		local testDrive = false
		if v.testArmed then
			v.testArmed = false
			t = { uid = -2, id = Game.banner().legendary, forge = 0 }
			testDrive = true
		end
		local mult = cashMult(player, v)
		local stats = Game.runStats(v.mach, v.tier, t, select(2, equipped(v)))
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
			keySpots = Game.keySpots(),
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
		local metres = n(payload.metres, startM, startM + math.min(run.reach * 8 + 500, elapsed * 420 + 120))
		local covered = metres - startM
		local zone = Game.zoneAt(metres)
		local keySpots = Game.keySpots()
		local keysPossible = 0
		for _, k in ipairs(keySpots) do
			if k > startM and k <= metres then keysPossible += 1 end
		end
		local keys = math.floor(n(payload.keys, 0, keysPossible))
		local ev = Game.eventAt().on
		local evId = ev and ev.id or nil
		local smashes = math.floor(n(payload.smashes, 0, covered / 20 + 3))
		-- the bounce run: a bounce needs about 10 m of road at the least, a PERFECT is a bounce
		local bounces = math.floor(n(payload.bounces, 0, covered / 10 + 3))
		local perfects = math.floor(n(payload.perfects, 0, bounces))
		local peakChain = math.floor(n(payload.peakChain, 0, bounces))
		local blowout = payload.blowout == true

		local mult, parts = cashMult(player, v)
		local rate = Game.Zones[zone].rate
		-- every metre paid at the chain multiplier it was covered with: the average can't beat what
		-- the bounces claimed could make it
		local comboCap = math.min(Config.Run.ComboMax, 1 + Config.Run.ComboStep * peakChain)
		local comboAvg = covered > 1 and n((tonumber(payload.comboMetres) or covered) / covered, 1, comboCap) or 1
		local base = (Game.runCash(metres) - Game.runCash(startM)) * comboAvg
		local smashCash = smashes * 12 * rate
		-- coins picked up on the road (arcs of them now), and PERFECTs
		local metals = type(payload.metals) == "table" and payload.metals or {}
		local coinCap = covered / 6 + 8
		local coins = n(metals.bronze, 0, coinCap) * 3 + n(metals.silver, 0, coinCap) * 8 + n(metals.gold, 0, coinCap) * 25
		local coinCash = coins * rate * (evId == "monsoon" and 2 or 1)
		local tricks = perfects * 8 + math.floor(n(payload.airTime, 0, elapsed))
		local trickCash = tricks * rate
		local cash = math.floor((base + smashCash + coinCash + trickCash) * mult)

		p.credits = math.min(1e15, p.credits + cash)
		v.runs += 1
		local streakKey = (v.runs % Game.Keys.PerRunStreak == 0) and 1 or 0
		local roadKeys = keys * (evId == "golden" and 2 or 1)
		grantKeys(v, roadKeys + streakKey)
		local wasBest = metres > v.bestEver
		v.bestEver = math.max(v.bestEver, metres)
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
		v.rate = v.rate <= 0 and perMin or (v.rate * 0.8 + perMin * 0.2)
		v.started = true

		-- what the old run kept, kept again: the ghost of a new best, the photo, quirks seen, the
		-- lifetime stats titles read, the record for the road
		local distance = metres / Game.StudsToMetres
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
		p.lifetime.bestDistance = math.max(p.lifetime.bestDistance, metres / Game.StudsToMetres)
		p.lifetime.credits += cash
		S.postBoard("distance", player.UserId, p.lifetime.bestDistance)
		S.postBoard("credits", player.UserId, p.lifetime.credits)
		if S.postWeekly then S.postWeekly(player.UserId, metres) end
		if S.heatFinish then S.heatFinish(player, metres, cash) end
		S.push(player)
		return {
			ok = true,
			cash = cash,
			event = evId,
			metres = metres,
			best = wasBest,
			keys = roadKeys,
			streakKey = streakKey,
			zone = zone,
			newZones = newZones,
			breakdown = { base = math.floor(base), smash = math.floor(smashCash), coins = math.floor(coinCash), tricks = math.floor(trickCash),
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
		local price = Game.machinePrice(id, level, v.tier)
		if p.credits < price then return { ok = false, err = "Not enough cash.", short = price - p.credits } end
		p.credits -= price
		v.mach[id] = level + 1
		S.push(player)
		return { ok = true, id = id, level = level + 1, price = price, cash = p.credits }
	end

	R.Overhaul.OnServerInvoke = function(player: Player)
		local p, v = data(player)
		if not p then return { ok = false } end
		if v.tier >= #Game.Tiers then return { ok = false, err = "Your yard is the top stage." } end
		if not Game.machinesMaxed(v) then return { ok = false, err = "Max every machine first." } end
		local cost = Game.plotUpgradeCost(v.tier)
		if p.credits < cost then
			return { ok = false, err = ("Need $%s more."):format(Game.short(cost - p.credits)), short = cost - p.credits }
		end
		p.credits -= cost
		v.overhauls += 1
		v.tier = math.min(v.tier + 1, #Game.Tiers)
		for _, id in ipairs({ "cannon", "fuel", "cooling" }) do v.mach[id] = 0 end
		v.reached = 0
		S.push(player)
		return { ok = true, overhauls = v.overhauls, tier = v.tier }
	end

	--==============================================================
	-- tyres
	--==============================================================
	local function roll(v, zoneId: string, withKeys: boolean?)
		local ev = Game.eventAt().on
		local list = Game.crateOdds(zoneId, nil, ev and ev.id == "rush" and 5 or nil)
		-- the pity: enough key crates without a Legendary and this one is the banner's
		if withKeys and v.pity + 1 >= Game.Crate.Pity then return Game.banner().legendary end
		local luck = 1
		if v.passes.lucky then luck *= 1.5 end
		if boostOn(v, "luck2") then luck *= 2 end
		if S.serverLuckUntil and S.serverLuckUntil > os.time() then luck *= 2 end
		-- luck lifts the odds of everything above Common, then the list is renormalised
		local total = 0
		local epic = Game.RaritiesById.Epic.order
		for _, e in ipairs(list) do
			local r = Game.TyresById[e.id].rarity
			e.w = e.odds * (r == "Common" and 1 or luck)
			if withKeys and Game.RaritiesById[r].order >= epic then e.w *= Game.Crate.KeyLuck end
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
		local times = math.clamp(math.floor(tonumber(count) or 1), 1, Game.Crate.MaxOpen)
		local withKeys = pay == "keys"
		if #v.inv + times > LoopData.MAX_TYRES then return { ok = false, err = "Your tyre rack is full. Forge some." } end
		if withKeys then
			local price = Game.cratePrice(zoneId)
			if v.keys < price * times then return { ok = false, err = "Not enough keys.", short = price * times - v.keys } end
			v.keys -= price * times
		else
			local price = Game.crateCash(zoneId, v.tier)
			if p.credits < price * times then return { ok = false, err = "Not enough cash.", short = price * times - p.credits } end
			p.credits -= price * times
		end
		local got = {}
		local legendary = Game.RaritiesById.Legendary.order
		for _ = 1, times do
			local id = roll(v, zoneId, withKeys)
			if withKeys then
				if Game.RaritiesById[Game.TyresById[id].rarity].order >= legendary then v.pity = 0 else v.pity += 1 end
			end
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
		S.push(player)
		return { ok = true, got = got, keys = v.keys, credits = p.credits, pity = v.pity }
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
			elseif #v.spares >= math.min(slots, LoopData.MAX_SPARES + 2) then
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
		local pick = {}
		for _, t in ipairs(v.inv) do
			if t.id == id and t.forge == forge and t.uid ~= v.launch and not table.find(v.spares, t.uid) and not t.fav then
				table.insert(pick, t.uid)
			end
		end
		-- the equipped ones count too if there aren't enough spare copies (a favourite never does)
		if #pick < Game.Forge.Need then
			for _, t in ipairs(v.inv) do
				if t.id == id and t.forge == forge and not table.find(pick, t.uid) and not t.fav then table.insert(pick, t.uid) end
			end
		end
		if #pick < Game.Forge.Need then return { ok = false, err = ("You need %d of these (favourites are kept)."):format(Game.Forge.Need) } end
		local gone = {}
		for i = 1, Game.Forge.Need do gone[pick[i]] = true end
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
		local layout = Game.yardLayout(raw, v and v.tier or 1)
		local ok, bad = Game.yardCheck(layout)
		if not ok then
			local ids = {}
			for id in pairs(bad) do table.insert(ids, id) end
			return { ok = false, bad = ids }
		end
		v.layout = layout
		S.push(player)
		return { ok = true, layout = Game.yardEncode(layout) }
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
		local clean = { paint = {}, finish = {}, stickers = {}, text = "", smoke = nil }
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
				if #clean.stickers >= 16 then break end
				if type(s) == "table" and type(s.id) == "string" then
					table.insert(clean.stickers, {
						id = s.id:sub(1, 40),
						a = math.clamp(tonumber(s.a) or 0, -360, 360),
						r = math.clamp(tonumber(s.r) or 0.85, 0.6, 1.0),
						rot = math.clamp(tonumber(s.rot) or 0, -360, 360),
						size = math.clamp(tonumber(s.size) or 1, 0.3, 2.5),
						repeatN = math.clamp(math.floor(tonumber(s.repeatN) or 1), 1, 6),
						mirror = s.mirror == true,
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
	R.TestDrive.OnServerInvoke = function(player: Player)
		local p, v = data(player)
		if not p then return { ok = false } end
		local span = Game.Crate.BannerHours * 3600
		local now = os.time()
		if now - v.testDrive < span and math.floor(v.testDrive / span) == math.floor(now / span) then
			return { ok = false, err = "One Test Drive a banner. The next banner brings another." }
		end
		v.testDrive = now
		v.testArmed = true
		S.push(player)
		return { ok = true, tyre = Game.banner().legendary }
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
		end
		if gift.cashRuns then
			local cash = math.floor(math.max(80, v.rate / 60 * 30) * gift.cashRuns)
			p.credits += cash
			reward.cash = cash
		end
		v.daily = { last = today, streak = streak }
		S.push(player)
		return { ok = true, reward = reward }
	end

	--==============================================================
	-- v3: the auto-cannon. While you're in the server and not out on a run, your yard's cannon fires
	-- on its own: a share of your recent rate, shown to everyone as a shot leaving your yard.
	--==============================================================
	task.spawn(function()
		local A = Game.AutoCannon
		while true do
			task.wait(A.Every)
			for _, pl in ipairs(Players:GetPlayers()) do
				local p = S.profiles[pl.UserId]
				local v = p and p.v2
				local status = S.statusOf[pl.UserId] or "base"
				local plot = S.plotOf(pl.UserId)
				if v and plot and v.runs > 0 and v.rate > 0 and (status == "base" or status == "afk") then
					local share = (v.passes.autolaunch and A.PassShare or A.Share)
					local cash = math.floor(v.rate / 60 * A.Every * share)
					if cash > 0 then
						p.credits = math.min(1e15, p.credits + cash)
						for _, other in ipairs(Players:GetPlayers()) do
							R.AutoFire:FireClient(other, plot, other == pl and cash or nil)
						end
						S.push(pl)
					end
				end
			end
		end
	end)

	local function onJoin(player: Player)
		task.spawn(function()
			local t0 = os.clock()
			while not S.profiles[player.UserId] and os.clock() - t0 < 20 and player.Parent do task.wait(0.2) end
			local p, v = data(player)
			if not p then return end
			local now = os.time()
			-- v3: no offline cash (the Compressor is tyre pressure now); the yard's auto-cannon pays
			-- while you're in the server instead
			local _ = now
			v.lastSeen = now
			S.push(player)
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, pl in ipairs(Players:GetPlayers()) do onJoin(pl) end
	Players.PlayerRemoving:Connect(function(pl)
		local p = S.profiles[pl.UserId]
		if p and p.v2 then p.v2.lastSeen = os.time() end
		active[pl.UserId] = nil
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
