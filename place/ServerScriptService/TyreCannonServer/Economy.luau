--!strict
-- TYRE CANNON :: Server / Economy
-- Everything bought, equipped, claimed or forged.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)
local Progress = require(Modules.Progress)
local Profile = require(script.Parent.Profile)

local Economy = {}

local CAT = { skin = "skins", trail = "trails", rim = "rims", rig = "rigs", generator = "generators" }
local LOOKUP = {
	skin = Config.SkinsById, trail = Config.TrailsById, rim = Config.RimsById,
	rig = Config.RigSkinsById, generator = Config.GeneratorsById,
}
local FIELD = { skin = "skin", trail = "trail", rim = "rim", rig = "rigSkin", generator = "generator" }
local DEFAULT = { skin = "stock", trail = "none", rim = "steel", rig = "works", generator = "field" }

function Economy.init(S)
	local R = S.Remotes
	local comma = Progress.comma

	local function fail(msg: string) return { ok = false, err = msg } end
	local function done(player: Player, extra: { [string]: any }?)
		S.push(player)
		local out = extra or {}
		out.ok = true
		out.profile = S.profiles[player.UserId]
		return out
	end
	local function guard(player: Player, gap: number, key: string)
		if S.throttled(player, gap, key) then return nil, fail("One at a time.") end
		local p = S.profiles[player.UserId]
		if not p then return nil, fail("Still loading your save.") end
		return p, nil
	end

	--==========================================================
	-- shared helpers
	--==========================================================
	function S.owns(p, kind: string, id: string): boolean
		local cat = CAT[kind]
		if not cat then return false end
		return (p[cat] and p[cat][id] == true) or (p.permanent[cat] and p.permanent[cat][id] == true)
	end

	function S.grantPermanent(p, kind: string, id: string): boolean
		local cat = CAT[kind]
		if not cat or not LOOKUP[kind][id] then return false end
		p.permanent[cat][id] = true
		return true
	end

	function S.tokenEffects(p)
		local e = { creditMult = 0, launchMult = 0, perkSlots = 0, freeCharm = 0, toolboxRate = 0, keepTracks = 0 }
		for id, n in pairs(p.tokenUpgrades or {}) do
			local t = Config.TokenShopById[id]
			if t and t.effect then
				for k, v in pairs(t.effect) do e[k] = (e[k] or 0) + v * n end
			end
		end
		return e
	end

	function S.toolboxEffects(p)
		local e = { boostMult = 0, creditMult = 0, distanceMult = 0 }
		for slot = 1, Config.Toolbox.Slots do
			local uid = p.equipped[slot]
			if uid then
				for _, tb in ipairs(p.toolboxes) do
					if tb.uid == uid then
						local kind = Config.ToolboxKindsById[tb.kind]
						local rar = Config.ToolboxRaritiesById[tb.rarity]
						if kind and rar then e[kind.stat] += rar.bonus * (tb.q or 1) end
						break
					end
				end
			end
		end
		return e
	end

	function S.boosterActive(p, id: string): boolean
		return (p.boosters[id] or 0) > 0
	end

	function S.grant(p, reward)
		if reward.credits then p.credits += reward.credits end
		for _, m in ipairs(Config.Metals) do
			if reward[m.id] then p.metals[m.id] += reward[m.id] end
		end
		if reward.tokens then p.tokens += reward.tokens end
	end

	local function spend(p, cost)
		if cost.credits then p.credits -= cost.credits end
		for _, m in ipairs(Config.Metals) do
			if cost[m.id] then p.metals[m.id] -= cost[m.id] end
		end
	end

	function S.ensureContracts(p, seedUserId: number)
		local today = Progress.today()
		if p.contracts.day ~= today or #p.contracts.list == 0 then
			p.contracts = { day = today, list = Progress.generateContracts(seedUserId, today) }
		end
	end

	function S.applyTitle(player: Player)
		local p = S.profiles[player.UserId]
		local id = p and p.title or ""
		if p and id ~= "" then
			local t = Config.TitlesById[id]
			local st = t and Progress.titleState(p, t)
			if not (st and st.owned) then
				p.title = ""
				id = ""
			end
		end
		player:SetAttribute("Title", id)
	end

	--==========================================================
	-- garage and tracks
	--==========================================================
	R.BuyUpgrade.OnServerInvoke = function(player: Player, upgradeId: any)
		local p, e = guard(player, 0.1, "buyUpgrade")
		if not p then return e end
		local u = type(upgradeId) == "string" and Config.UpgradesById[upgradeId]
		if not u then return fail("That upgrade doesn't exist.") end
		local level = p.upgrades[upgradeId] or 0
		if level >= u.maxLevel then return fail("Already maxed.") end
		local cost = Config.UpgradeCost(upgradeId, level)
		if p.credits < cost then return fail(("Need %s more credits."):format(comma(cost - p.credits))) end
		p.credits -= cost
		p.upgrades[upgradeId] = level + 1
		p.stats.upgrades += 1
		return done(player, { level = level + 1, spent = cost })
	end

	R.SelectTrack.OnServerInvoke = function(player: Player, trackId: any)
		local p, e = guard(player, 0.1, "selectTrack")
		if not p then return e end
		local t = type(trackId) == "string" and Config.TracksById[trackId]
		if not t then return fail("That road doesn't exist.") end
		if not p.tracks[trackId] then
			if p.credits < t.cost then return fail(("Locked. %s credits to open it."):format(comma(t.cost))) end
			p.credits -= t.cost
			p.tracks[trackId] = true
		end
		p.selected = trackId
		return done(player, { unlocked = true })
	end

	R.SetPressure.OnServerInvoke = function(player: Player, value: any)
		local p, e = guard(player, 0.05, "pressure")
		if not p then return e end
		if type(value) ~= "number" or value ~= value then return fail("Bad value.") end
		p.pressure = math.clamp(math.floor(value + 0.5), 0, 100)
		return done(player)
	end

	--==========================================================
	-- shop
	--==========================================================
	R.BuyItem.OnServerInvoke = function(player: Player, kind: any, id: any)
		local p, e = guard(player, 0.08, "buyItem")
		if not p then return e end
		if type(kind) ~= "string" or type(id) ~= "string" then return fail("Bad request.") end

		if kind == "charm" then
			local c = Config.CharmsById[id]
			if not c then return fail("That charm doesn't exist.") end
			if p.credits < c.cost then return fail(("Need %s more credits."):format(comma(c.cost - p.credits))) end
			if (p.charms[id] or 0) >= 99 then return fail("You're carrying 99 already.") end
			p.credits -= c.cost
			p.charms[id] = (p.charms[id] or 0) + 1
			return done(player, { bought = c.name })
		end

		local lookup = LOOKUP[kind]
		local def = lookup and lookup[id]
		if not def then return fail("That isn't for sale.") end
		if S.owns(p, kind, id) then return fail("Already yours.") end
		if def.robux then return fail("That one is Robux only.") end
		if def.locked then return fail("Earned, not bought.") end
		if p.credits < def.cost then return fail(("Need %s more credits."):format(comma(def.cost - p.credits))) end
		p.credits -= def.cost
		p[CAT[kind]][id] = true
		p[FIELD[kind]] = id
		return done(player, { bought = def.name })
	end

	local function equip(player: Player, kind: any, id: any)
		local p, e = guard(player, 0.05, "equip")
		if not p then return e end
		if type(kind) ~= "string" or not FIELD[kind] then return fail("Bad request.") end
		if id == nil or id == "" then id = DEFAULT[kind] end
		if type(id) ~= "string" then return fail("Bad request.") end
		if id ~= DEFAULT[kind] and not S.owns(p, kind, id) then return fail("You don't own that.") end
		p[FIELD[kind]] = id
		return done(player)
	end
	R.EquipCosmetic.OnServerInvoke = equip
	R.EquipSkin.OnServerInvoke = function(player, id) return equip(player, "skin", id) end
	R.EquipTrail.OnServerInvoke = function(player, id) return equip(player, "trail", id) end

	R.SetLoadout.OnServerInvoke = function(player: Player, ids: any)
		local p, e = guard(player, 0.05, "loadout")
		if not p then return e end
		if type(ids) ~= "table" then return fail("Bad request.") end
		local out, seen = {}, {}
		for _, id in ipairs(ids) do
			if type(id) == "string" and Config.CharmsById[id] and not seen[id]
				and (p.charms[id] or 0) > 0 and #out < Profile.MAX_LOADOUT then
				seen[id] = true
				table.insert(out, id)
			end
		end
		p.loadout = out
		return done(player)
	end

	R.BuyBooster.OnServerInvoke = function(player: Player, id: any)
		local p, e = guard(player, 0.12, "booster")
		if not p then return e end
		local b = type(id) == "string" and Config.BoostersById[id]
		if not b then return fail("That booster doesn't exist.") end
		if not Progress.canAfford(p, b.cost) then return fail("Not enough metal.") end
		if b.kind == "timed" then
			if (p.boosters[id] or 0) + b.seconds > 4 * 3600 then return fail("Four hours stacked is the limit.") end
			spend(p, b.cost)
			p.boosters[id] = (p.boosters[id] or 0) + b.seconds
		else
			if (p.boosters[id] or 0) + b.charges > 50 then return fail("Fifty charges is the limit.") end
			spend(p, b.cost)
			p.boosters[id] = (p.boosters[id] or 0) + b.charges
		end
		return done(player, { bought = b.name })
	end

	--==========================================================
	-- toolboxes and the retread forge
	--==========================================================
	R.EquipToolbox.OnServerInvoke = function(player: Player, slot: any, uid: any)
		local p, e = guard(player, 0.05, "equipTool")
		if not p then return e end
		if type(slot) ~= "number" then return fail("Bad request.") end
		slot = math.floor(slot)
		if slot < 1 or slot > Config.Toolbox.Slots then return fail("No such slot.") end
		if uid == nil then
			p.equipped[slot] = nil
			return done(player)
		end
		if type(uid) ~= "number" then return fail("Bad request.") end
		local found = false
		for _, tb in ipairs(p.toolboxes) do if tb.uid == uid then found = true break end end
		if not found then return fail("You don't have that toolbox.") end
		for s, u in pairs(p.equipped) do
			if u == uid and s ~= slot then p.equipped[s] = nil end
		end
		p.equipped[slot] = uid
		return done(player)
	end

	local RARITY_INDEX = {}
	for i, r in ipairs(Config.ToolboxRarities) do RARITY_INDEX[r.id] = i end

	R.Forge.OnServerInvoke = function(player: Player, uids: any, strikes: any)
		local p, e = guard(player, 0.8, "forge")
		if not p then return e end
		if type(uids) ~= "table" or #uids ~= Config.Forge.Inputs then return fail("Put three toolboxes on the bench.") end
		local picked, seen = {}, {}
		for _, uid in ipairs(uids) do
			if type(uid) ~= "number" or seen[uid] then return fail("Bad request.") end
			seen[uid] = true
			for i, tb in ipairs(p.toolboxes) do
				if tb.uid == uid then table.insert(picked, { index = i, tb = tb }) break end
			end
		end
		if #picked ~= Config.Forge.Inputs then return fail("One of those isn't yours any more.") end
		local rarity = picked[1].tb.rarity
		for _, it in ipairs(picked) do
			if it.tb.rarity ~= rarity then return fail("All three need the same rarity.") end
		end
		local ri = RARITY_INDEX[rarity]
		if not ri or ri >= #Config.ToolboxRarities then return fail("Legendary is the highest rarity, so it can't be forged.") end

		local acc = 0
		for i = 1, Config.Forge.Strikes do
			local s = type(strikes) == "table" and tonumber(strikes[i]) or 0
			if s ~= s then s = 0 end
			acc += math.clamp(s or 0, 0, 1)
		end
		acc /= Config.Forge.Strikes

		local counts, kind = {}, picked[1].tb.kind
		for _, it in ipairs(picked) do counts[it.tb.kind] = (counts[it.tb.kind] or 0) + 1 end
		for k, c in pairs(counts) do if c > (counts[kind] or 0) then kind = k end end

		table.sort(picked, function(x, y) return x.index > y.index end)
		for _, it in ipairs(picked) do
			for s, u in pairs(p.equipped) do if u == it.tb.uid then p.equipped[s] = nil end end
			table.remove(p.toolboxes, it.index)
		end

		local F = Config.Forge
		local q = math.floor((F.QualityMin + (F.QualityMax - F.QualityMin) * acc) * 100 + 0.5) / 100
		local out = { uid = p.nextToolUid, kind = kind, rarity = Config.ToolboxRarities[ri + 1].id, q = q }
		p.nextToolUid += 1
		table.insert(p.toolboxes, out)
		p.stats.forged += 1
		if out.rarity == "legendary" then p.stats.forgedLegendary += 1 end
		return done(player, { result = out, accuracy = acc })
	end

	--==========================================================
	-- prestige, tokens, titles
	--==========================================================
	R.Prestige.OnServerInvoke = function(player: Player)
		local p, e = guard(player, 1, "prestige")
		if not p then return e end
		if p.prestige >= Config.Prestige.MaxLevel then return fail("That's the top. Nowhere left to go.") end
		local cost = Config.PrestigeCost(p.prestige)
		if p.credits < cost then return fail(("Need %s more credits."):format(comma(cost - p.credits))) end

		local newLevel = p.prestige + 1
		local reward = Config.PrestigeReward(newLevel)
		local keepTracks = S.tokenEffects(p).keepTracks >= 1
		local tokens = Config.Prestige.TokensFor(newLevel)

		p.prestige = newLevel
		p.tokens += tokens
		if reward then S.grantPermanent(p, reward.kind, reward.id) end

		p.credits = Config.Economy.StartingCredits
		p.upgrades = {}
		p.charms = {}
		p.loadout = {}
		p.skins = { stock = true }
		p.trails = { none = true }
		p.rims = { steel = true }
		p.rigs = { works = true }
		p.generators = { field = true }
		p.toolboxes = {}
		p.equipped = {}
		p.records = {}
		if not keepTracks then
			p.tracks = { backroad = true }
			p.selected = "backroad"
		end
		if not Config.Prestige.KeepsCodex then p.codex = {} end
		for kind, field in pairs(FIELD) do
			if not S.owns(p, kind, p[field]) then p[field] = DEFAULT[kind] end
		end

		S.save(player.UserId)
		return done(player, { level = newLevel, spent = cost, tokens = tokens, reward = reward and reward.note or nil })
	end

	R.BuyToken.OnServerInvoke = function(player: Player, id: any)
		local p, e = guard(player, 0.15, "buyToken")
		if not p then return e end
		local t = type(id) == "string" and Config.TokenShopById[id]
		if not t then return fail("That isn't in the token shop.") end
		local have = p.tokenUpgrades[id] or 0
		if have >= t.max then return fail("Already maxed.") end
		if p.tokens < t.cost then return fail("Not enough tokens.") end
		p.tokens -= t.cost
		p.tokenUpgrades[id] = have + 1
		if t.grant then S.grantPermanent(p, t.grant.kind, t.grant.id) end
		S.save(player.UserId)
		return done(player, { bought = t.name })
	end

	R.BuyTitle.OnServerInvoke = function(player: Player, id: any)
		local p, e = guard(player, 0.2, "buyTitle")
		if not p then return e end
		local t = type(id) == "string" and Config.TitlesById[id]
		if not t then return fail("That title doesn't exist.") end
		if t.live then return fail("Live titles can't be bought. Hold the rank.") end
		local st = Progress.titleState(p, t)
		if st.owned then return fail("Already yours.") end
		if not st.unlocked then return fail(Progress.titleHow(t) .. " first.") end
		if p.tokens < st.cost then return fail(("Costs %d token%s."):format(st.cost, st.cost == 1 and "" or "s")) end
		p.tokens -= st.cost
		p.titles[t.id] = true
		p.title = t.id
		S.applyTitle(player)
		S.save(player.UserId)
		return done(player, { bought = t.name })
	end

	R.EquipTitle.OnServerInvoke = function(player: Player, id: any)
		local p, e = guard(player, 0.1, "equipTitle")
		if not p then return e end
		if id == nil or id == "" then
			p.title = ""
		else
			local t = type(id) == "string" and Config.TitlesById[id]
			if not t then return fail("That title doesn't exist.") end
			if not Progress.titleState(p, t).owned then return fail("You haven't earned that one.") end
			p.title = t.id
		end
		S.applyTitle(player)
		return done(player)
	end

	--==========================================================
	-- stickers on the tyre
	--==========================================================
	local stickerIds: { [string]: boolean } = {}
	local function scanStickers()
		stickerIds = {}
		local pack = ReplicatedStorage.TyreCannon.Assets.Props:FindFirstChild("StickerPack")
		if not pack then return end
		for _, d in ipairs(pack:GetDescendants()) do
			if d:IsA("BasePart") and d:FindFirstChildOfClass("Decal") then stickerIds[d.Name] = true end
		end
	end
	scanStickers()

	R.SetStickers.OnServerInvoke = function(player: Player, list: any)
		local p, e = guard(player, 0.15, "stickers")
		if not p then return e end
		if type(list) ~= "table" then return fail("Bad request.") end
		local S = Config.Stickers
		local out = {}
		for _, s in ipairs(list) do
			if #out >= S.MaxPerTyre then break end
			if type(s) == "table" and type(s.id) == "string" and stickerIds[s.id] then
				local function n(v, lo, hi, d)
					local x = tonumber(v)
					if x == nil or x ~= x then return d end
					return math.clamp(x, lo, hi)
				end
				table.insert(out, {
					id = s.id,
					side = (s.side == -1) and -1 or 1,
					u = n(s.u, -1, 1, 0),
					v = n(s.v, -1, 1, 0),
					rot = n(s.rot, -360, 360, 0),
					scale = n(s.scale, S.MinScale, S.MaxScale, 1),
				})
			end
		end
		p.stickers = out
		return done(player)
	end

	--==========================================================
	-- daily streak, tutorial
	--==========================================================
	R.ClaimDaily.OnServerInvoke = function(player: Player)
		local p, e = guard(player, 0.5, "daily")
		if not p then return e end
		local claimable, index, streak = Progress.dailyState(p)
		if not claimable then return fail("Already claimed today. Back tomorrow.") end
		local reward = Config.Daily[index]
		S.grant(p, reward)
		p.daily = { day = Progress.today(), streak = streak }
		return done(player, { reward = reward, day = index, streak = streak })
	end

	R.TutorialDone.OnServerEvent:Connect(function(player: Player)
		local p = S.profiles[player.UserId]
		if not p or p.tutorial then return end
		p.tutorial = true
		S.save(player.UserId)
		S.push(player)
	end)

	--==========================================================
	-- settings
	--==========================================================
	local TextService = game:GetService("TextService")
	local SHOWN_ON_PLOT = { rigName = true, doorPaint = true, doorStencil = true }

	R.SetPref.OnServerInvoke = function(player: Player, key: any, value: any)
		if type(key) ~= "string" then return fail("Bad request.") end
		local p, e = guard(player, key == "rigName" and 1 or 0.05, "pref_" .. key)
		if not p then return e end
		local ok, clean = Profile.cleanPref(key, value)
		if not ok then return fail("That setting can't take that value.") end
		if key == "rigName" then
			local text = (clean :: string):gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
			if text ~= "" then
				local okF, res = pcall(function()
					return TextService:FilterStringAsync(text, player.UserId):GetNonChatStringForBroadcastAsync()
				end)
				if not okF then return fail("Couldn't check that name. Try again in a moment.") end
				if res ~= text then return fail("That name didn't get past the filter. Try another.") end
			end
			clean = text
		end
		p.prefs[key] = clean
		if SHOWN_ON_PLOT[key] then
			S.push(player)
			return { ok = true, value = clean, profile = p }
		end
		-- sliders fire often, so these save quietly without a full profile push
		return { ok = true, value = clean }
	end

	--==========================================================
	-- gifts: bought here, wrapped on the friend's bench, opened in their workbench
	--==========================================================
	local GIFTABLE = { skin = Config.SkinsById, rim = Config.RimsById, trail = Config.TrailsById, rig = Config.RigSkinsById }

	R.SendGift.OnServerInvoke = function(player: Player, targetId: any, kind: any, id: any)
		local p, e = guard(player, 0.5, "gift")
		if not p then return e end
		if type(targetId) ~= "number" or type(kind) ~= "string" or type(id) ~= "string" then return fail("Bad request.") end
		if targetId == player.UserId then return fail("That's you. Buy it from the rack instead.") end
		local target = Players:GetPlayerByUserId(targetId)
		local tp = target and S.profiles[targetId]
		if not (target and tp) then return fail("They're not in this server any more.") end
		local lookup = GIFTABLE[kind]
		local def = lookup and lookup[id]
		if not def then return fail("That can't be gifted.") end
		if def.robux then return fail("Robux parts can't be gifted.") end
		if def.locked then return fail("Earned, not bought, so it can't be gifted.") end
		if id == DEFAULT[kind] then return fail("Everyone has that one.") end
		if S.owns(tp, kind, id) then return fail(target.DisplayName .. " already has that.") end
		for _, g in ipairs(tp.gifts) do
			if g.kind == kind and g.id == id then return fail("There's already one wrapped for them.") end
		end
		if #tp.gifts >= Profile.MAX_GIFTS then return fail("Their bench is full of gifts.") end
		if p.credits < def.cost then return fail(("Need %s more credits."):format(comma(def.cost - p.credits))) end
		p.credits -= def.cost
		table.insert(tp.gifts, {
			uid = tp.nextGiftUid, kind = kind, id = id,
			from = player.DisplayName, fromId = player.UserId, at = os.time(),
		})
		tp.nextGiftUid += 1
		task.spawn(S.save, targetId)
		task.spawn(S.save, player.UserId)
		S.push(target)
		R.Notify:FireClient(target, { kind = "gift", from = player.DisplayName, item = def.name })
		return done(player, { sent = def.name, to = target.DisplayName })
	end

	R.OpenGift.OnServerInvoke = function(player: Player, uid: any)
		local p, e = guard(player, 0.3, "openGift")
		if not p then return e end
		if type(uid) ~= "number" then return fail("Bad request.") end
		for i, g in ipairs(p.gifts) do
			if g.uid == uid then
				table.remove(p.gifts, i)
				local set = p[CAT[g.kind]]
				if not S.owns(p, g.kind, g.id) then set[g.id] = true end
				task.spawn(S.save, player.UserId)
				return done(player, { gift = g })
			end
		end
		return fail("That one's already open.")
	end

	-- timed boosters only burn while you're in the game
	task.spawn(function()
		while true do
			task.wait(10)
			for _, pl in ipairs(Players:GetPlayers()) do
				local p = S.profiles[pl.UserId]
				if p then
					for _, b in ipairs(Config.Boosters) do
						if b.kind == "timed" and (p.boosters[b.id] or 0) > 0 then
							p.boosters[b.id] = math.max(0, p.boosters[b.id] - 10)
							if p.boosters[b.id] == 0 then p.boosters[b.id] = nil end
						end
					end
				end
			end
		end
	end)
end

return Economy
