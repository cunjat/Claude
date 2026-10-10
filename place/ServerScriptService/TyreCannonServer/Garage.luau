--!strict
-- TYRE CANNON :: Server / Garage
-- The walk-in garage behind every yard's door. The client builds the room; the server
-- hands anyone the owner's side of it (their build, their tyres, their records, photos and
-- guestbook), takes guestbook stamps from visitors, and runs the second bay: unlocking it,
-- and swapping the build stored there with the one on the rig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)

local Garage = {}

local function owns(p, cat: string, id: string, default: string): boolean
	if id == default then return true end
	return (p[cat] and p[cat][id] == true) or (p.permanent and p.permanent[cat] and p.permanent[cat][id] == true) or false
end

-- everything a visitor sees in someone's garage, and nothing else
local function view(S, userId: number)
	local p = S.profiles[userId]
	if not p then return nil end
	local pl = Players:GetPlayerByUserId(userId)
	local skins = {}
	for id in pairs(p.skins) do skins[id] = true end
	for id in pairs(p.permanent.skins) do skins[id] = true end
	local st = p.stats
	return {
		userId = userId,
		name = pl and pl.DisplayName or "?",
		plot = S.plotOf(userId),
		rigName = p.prefs and p.prefs.rigName or "",
		skin = p.skin, rim = p.rim, trail = p.trail, stickers = p.stickers, pressure = p.pressure,
		rigSkin = p.rigSkin, generator = p.generator, prestige = p.prestige, title = p.title,
		skins = skins,
		tyreLog = p.tyreLog,
		records = p.records,
		totals = p.totals,
		metals = p.metals,
		stats = {
			runs = st.runs, forged = st.forged, forgedLegendary = st.forgedLegendary, flawless = st.flawless,
			contracts = st.contracts, maxTier = st.maxTier, smashes = st.smashes, longestAir = st.longestAir,
			bronze = st.bronze, silver = st.silver, gold = st.gold,
		},
		bestDistance = p.lifetime.bestDistance,
		photos = p.photos,
		honks = p.honks,
		guestbook = p.guestbook,
		bay = p.bay,
	}
end

function Garage.init(S)
	local R = S.Remotes
	local stampedAt: { [string]: number } = {}

	R.GetGarage.OnServerInvoke = function(player: Player, userId: any)
		if S.throttled(player, 0.3, "garage") then return { ok = false, err = "One at a time." } end
		if type(userId) ~= "number" then userId = player.UserId end
		local v = view(S, math.floor(userId))
		if not v then return { ok = false, err = "They've left." } end
		return { ok = true, garage = v }
	end

	R.StampGuestbook.OnServerInvoke = function(player: Player, ownerId: any, stampId: any)
		if S.throttled(player, 1, "stamp") then return { ok = false, err = "One at a time." } end
		if type(ownerId) ~= "number" or type(stampId) ~= "string" then return { ok = false, err = "Bad request." } end
		ownerId = math.floor(ownerId)
		if ownerId == player.UserId then return { ok = false, err = "You can't stamp your own guestbook." } end
		if not Config.Garage.StampsById[stampId] then return { ok = false, err = "Bad request." } end
		local op = S.profiles[ownerId]
		local owner = Players:GetPlayerByUserId(ownerId)
		if not (op and owner) then return { ok = false, err = "They've left." } end
		local key = player.UserId .. ":" .. ownerId
		local now = os.clock()
		if stampedAt[key] and now - stampedAt[key] < Config.Garage.StampCooldown then
			return { ok = false, err = "You've already stamped this guestbook. Come back later." }
		end
		stampedAt[key] = now
		table.insert(op.guestbook, 1, { name = player.DisplayName, fromId = player.UserId, stamp = stampId, at = os.time() })
		while #op.guestbook > Config.Garage.GuestbookSize do table.remove(op.guestbook) end
		R.Notify:FireClient(owner, { kind = "toast", text = ("%s STAMPED YOUR GUESTBOOK: %s"):format(
			string.upper(player.DisplayName), Config.Garage.StampsById[stampId].text) })
		S.push(owner)
		return { ok = true, guestbook = op.guestbook }
	end

	R.UnlockBay.OnServerInvoke = function(player: Player)
		if S.throttled(player, 0.6, "bay") then return { ok = false, err = "One at a time." } end
		local p = S.profiles[player.UserId]
		if not p then return { ok = false, err = "Still loading your save." } end
		if p.bay.unlocked then return { ok = false, err = "Bay 2 is already open." } end
		local cost = Config.Garage.BayCost
		if p.credits < cost then
			return { ok = false, err = ("Bay 2 costs %d credits."):format(cost) }
		end
		p.credits -= cost
		p.bay = { unlocked = true, skin = "stock", rim = "steel", trail = "none", stickers = {} }
		S.push(player)
		return { ok = true, profile = p }
	end

	R.SwapBay.OnServerInvoke = function(player: Player)
		if S.throttled(player, 0.8, "bay") then return { ok = false, err = "One at a time." } end
		local p = S.profiles[player.UserId]
		if not p then return { ok = false, err = "Still loading your save." } end
		if not p.bay.unlocked then return { ok = false, err = "Bay 2 is locked." } end
		local b = p.bay
		local stored = {
			skin = owns(p, "skins", b.skin, "stock") and b.skin or "stock",
			rim = owns(p, "rims", b.rim, "steel") and b.rim or "steel",
			trail = owns(p, "trails", b.trail, "none") and b.trail or "none",
			stickers = b.stickers or {},
		}
		p.bay = { unlocked = true, skin = p.skin, rim = p.rim, trail = p.trail, stickers = p.stickers }
		p.skin, p.rim, p.trail, p.stickers = stored.skin, stored.rim, stored.trail, stored.stickers
		S.push(player)
		return { ok = true, profile = p }
	end
end

return Garage
