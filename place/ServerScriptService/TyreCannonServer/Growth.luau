--!strict
-- TYRE CANNON :: Server / Growth
-- What brings players in and keeps them coming back. Each piece stays off until the owner fills its id in
-- Config.Growth (badges, the group and the notification strings are made on the Creator Dashboard), so
-- nothing here errors or prompts before then:
--   badges         S.growth(player, event, data) is called where the moments happen (Loop: a run, crates,
--                  a stage-up; Heats: a win; Economy: the tutorial) and awards the matching badge
--   invites        a friend who joins from your invite (launch data { ref = userId }) gets keys at once;
--                  you get yours when they finish their first run, so alts that never play pay nothing.
--                  If you're not in their server it waits in a DataStore until you next join
--   group reward   keys, once, for being in the group: checked on join and when the client asks after
--                  Roblox's join-group prompt (V2.GroupCheck)
--   notifications  one reminder queued when a player leaves (a MemoryStore sorted map, so any live
--                  server sends it when it's due) through Roblox's Open Cloud package, once the owner has
--                  put it in ServerScriptService (OpenCloud) and made the message strings
--   Growth.init(S)   (after Loop: it uses S.V2)

local Players = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)
local Game = require(Modules.Game)
local Analytics = require(script.Parent.Analytics)

local Growth = {}
local G = Config.Growth

-- an Async method, or the older name of it if this server doesn't have the Async one yet
local function call(obj: any, async: string, old: string, ...): (boolean, any)
	local args = table.pack(...)
	local ok, res = pcall(function() return obj[async](obj, table.unpack(args, 1, args.n)) end)
	if not ok and tostring(res):find("not a valid member") then
		ok, res = pcall(function() return obj[old](obj, table.unpack(args, 1, args.n)) end)
	end
	return ok, res
end

function Growth.init(S)
	local folder = S.V2.Daily.Parent
	local groupCheck = folder:FindFirstChild("GroupCheck") or Instance.new("RemoteFunction")
	groupCheck.Name = "GroupCheck"
	groupCheck.Parent = folder

	local function data(player: Player)
		local p = S.profiles[player.UserId]
		return p, p and p.v2
	end

	local function giveKeys(player: Player, n: number, text: string, sku: string)
		local p, v = data(player)
		if not p or not v or n <= 0 then return end
		v.keys = math.min(1e6, v.keys + n)
		Analytics.earn(player, "Keys", n, v.keys, "Gameplay", sku)
		S.push(player)
		pcall(function() S.V2.Reward:FireClient(player, { text = text, keys = n }) end)
	end

	--==========================================================
	-- badges
	--==========================================================
	local awarded: { [number]: { [string]: boolean } } = {}
	local function badge(player: Player, key: string)
		local id = G.Badges[key]
		if type(id) ~= "number" or id == 0 then return end
		local mine = awarded[player.UserId]
		if not mine then
			mine = {}
			awarded[player.UserId] = mine
		end
		if mine[key] then return end
		mine[key] = true
		task.spawn(function()
			local okHas, has = call(BadgeService, "UserHasBadgeAsync", "UserHasBadge", player.UserId, id)
			if okHas and has then return end
			local ok, err = call(BadgeService, "AwardBadgeAsync", "AwardBadge", player.UserId, id)
			if not ok then
				warn("[TyreCannon] badge", key, "not awarded:", err)
				mine[key] = nil
			end
		end)
	end
	S.badge = badge

	--==========================================================
	-- invites: the friend's keys on joining, yours on their first run
	--==========================================================
	local refStore: DataStore? = nil
	pcall(function() refStore = DataStoreService:GetDataStore("tc_referrals_v1") end)

	local function payInviter(inviterId: number)
		local inviter = Players:GetPlayerByUserId(inviterId)
		if inviter and S.profiles[inviterId] then
			giveKeys(inviter, G.Invite.InviterKeys, "A friend you invited finished their first run!", "Referral")
			badge(inviter, "invited")
			return
		end
		-- not here: it waits for their next join
		if refStore then
			pcall(function()
				(refStore :: DataStore):UpdateAsync(tostring(inviterId), function(old)
					local n = (type(old) == "table" and tonumber(old.n)) or 0
					return { n = math.min(G.Invite.MaxWaiting, n + 1) }
				end)
			end)
		end
	end

	local function claimWaiting(player: Player)
		if not refStore then return end
		local got = 0
		pcall(function()
			(refStore :: DataStore):UpdateAsync(tostring(player.UserId), function(old)
				got = (type(old) == "table" and tonumber(old.n)) or 0
				if got <= 0 then return nil end
				return { n = 0 }
			end)
		end)
		if got > 0 then
			giveKeys(player, got * G.Invite.InviterKeys, ("%d friend%s you invited played!"):format(got, got == 1 and "" or "s"), "Referral")
			badge(player, "invited")
		end
	end

	--==========================================================
	-- the group
	--==========================================================
	local function checkGroup(player: Player)
		local p = data(player)
		if not p or G.GroupId == 0 or p.growth.group then return end
		local ok, inGroup = call(player, "IsInGroupAsync", "IsInGroup", G.GroupId)
		if ok and inGroup then
			p.growth.group = true
			giveKeys(player, G.GroupKeys, "Thanks for joining the group!", "Group")
		end
	end
	groupCheck.OnServerInvoke = function(player: Player)
		if S.throttled(player, 2, "groupCheck") then return { ok = false } end
		checkGroup(player)
		local p = data(player)
		return { ok = true, rewarded = p ~= nil and p.growth.group == true }
	end

	--==========================================================
	-- the moments (called from Loop, Heats and Economy)
	--==========================================================
	S.growth = function(player: Player, event: string, d: any)
		local p, v = data(player)
		if not p or not v then return end
		if event == "run" then
			badge(player, "firstLaunch")
			local zone = tonumber(d and d.zone) or 1
			if zone >= 2 then badge(player, "highway") end
			if zone >= 3 then badge(player, "dunes") end
			local g = p.growth
			if g.referredBy ~= 0 and not g.refPaid then
				g.refPaid = true
				task.spawn(payInviter, g.referredBy)
			end
		elseif event == "tyres" and type(d) == "table" then
			for _, e in ipairs(d) do
				local t = Game.TyresById[e.id]
				if t then
					if t.rarity == "Legendary" then badge(player, "legendary")
					elseif t.rarity == "Mythic" then badge(player, "mythic")
					elseif t.rarity == "Secret" then badge(player, "secret") end
				end
			end
		elseif event == "stage" then
			badge(player, "stageUp")
			if (tonumber(d) or 0) >= #Game.Tiers then badge(player, "topStage") end
		elseif event == "prestige" then
			badge(player, "prestige")
		elseif event == "heat" then
			if d and tonumber(d.place) == 1 then badge(player, "heatWin") end
		elseif event == "tutorial" then
			badge(player, "tutorial")
		end
	end

	--==========================================================
	-- notifications: one reminder queued on leaving, sent by whichever server sees it due
	--==========================================================
	local queue: MemoryStoreSortedMap? = nil
	pcall(function() queue = MemoryStoreService:GetSortedMap("tc_notify_v1") end)
	local OC: any = nil
	local pkg = ServerScriptService:FindFirstChild("OpenCloud")
	if pkg then
		pcall(function() OC = require((pkg :: any).V2.UserNotification) end)
	end
	local notifyOn = queue ~= nil and OC ~= nil and (G.Notify.DailyMessageId ~= "" or G.Notify.StashMessageId ~= "")

	local function cancelNotify(uid: number)
		if not queue then return end
		pcall(function() (queue :: MemoryStoreSortedMap):RemoveAsync(tostring(uid)) end)
	end

	local function send(uid: number, entry: any)
		local msg = if entry.kind == "daily" then G.Notify.DailyMessageId else G.Notify.StashMessageId
		if msg == "" then return end
		local payload: any = {
			messageId = msg,
			type = "MOMENT",
			joinExperience = { launchData = HttpService:JSONEncode({ n = entry.kind }) },
			analyticsData = { category = entry.kind },
		}
		if entry.day then payload.parameters = { day = { stringValue = tostring(entry.day) } } end
		local ok, res = pcall(function() return OC.createUserNotification(uid, { payload = payload }) end)
		if not ok or type(res) ~= "table" or res.statusCode ~= 200 then
			warn("[TyreCannon] notification not sent:", ok and res and res.statusCode, ok and res and res.error and res.error.message or res)
		end
	end

	if notifyOn then
		Players.PlayerRemoving:Connect(function(player: Player)
			local p, v = data(player)
			if not p or not v or not v.started then return end
			local now = os.time()
			local today = Game.utcDay(now)
			local entry, due = nil, 0
			-- they claimed today: tomorrow's is ready at the next UTC midnight, and the streak breaks at
			-- the one after, so the reminder lands in between
			if G.Notify.DailyMessageId ~= "" and v.daily and v.daily.last == today then
				local nextDay = (today + 1) * 86400
				due = math.max(nextDay + 2 * 3600, now + 8 * 3600)
				if due < nextDay + 22 * 3600 then
					entry = { kind = "daily", day = ((v.daily.streak or 0) % #Game.Daily) + 1 }
				end
			end
			if not entry and G.Notify.StashMessageId ~= "" then
				entry = { kind = "stash" }
				due = now + math.floor(Game.Offline.CapHours * 3600)
			end
			if entry then
				pcall(function() (queue :: MemoryStoreSortedMap):SetAsync(tostring(player.UserId), entry, 48 * 3600, due) end)
			end
		end)

		task.spawn(function()
			while true do
				task.wait(60 + math.random() * 30)
				local okR, items = pcall(function()
					return (queue :: MemoryStoreSortedMap):GetRangeAsync(Enum.SortDirection.Ascending, 20, nil, { sortKey = os.time() })
				end)
				if okR and type(items) == "table" then
					for _, it in ipairs(items) do
						-- claim it first, so only one server sends it
						local mine = false
						pcall(function()
							(queue :: MemoryStoreSortedMap):UpdateAsync(it.key, function(old, sortKey)
								mine = false
								if type(old) ~= "table" or old.claim then return nil end
								old.claim = game.JobId
								mine = true
								return old, sortKey
							end, 600)
						end)
						if mine then
							send(tonumber(it.key) :: number, it.value)
							pcall(function() (queue :: MemoryStoreSortedMap):RemoveAsync(it.key) end)
						end
					end
				end
			end
		end)
	end

	--==========================================================
	-- joining
	--==========================================================
	local function onJoin(player: Player)
		local t0 = os.clock()
		while not S.profiles[player.UserId] and player.Parent and os.clock() - t0 < 30 do task.wait(0.25) end
		local p, v = data(player)
		if not p or not v then return end
		badge(player, "welcome")
		cancelNotify(player.UserId)
		claimWaiting(player)
		checkGroup(player)
		-- from a friend's invite? (launch data can take a few seconds to arrive)
		for _ = 1, 10 do
			if not player.Parent then return end
			local ok, jd = pcall(function() return player:GetJoinData() end)
			local raw = ok and type(jd) == "table" and jd.LaunchData
			if type(raw) == "string" and raw ~= "" then
				local okj, t = pcall(function() return HttpService:JSONDecode(raw) end)
				local ref = okj and type(t) == "table" and tonumber(t.ref)
				if ref and ref ~= player.UserId and p.growth.referredBy == 0 and v.runs == 0 then
					p.growth.referredBy = ref
					giveKeys(player, G.Invite.FriendKeys, "A friend invited you! Have some keys.", "Referral")
				end
				return
			end
			task.wait(1)
		end
	end
	Players.PlayerAdded:Connect(function(pl) task.spawn(onJoin, pl) end)
	for _, pl in ipairs(Players:GetPlayers()) do task.spawn(onJoin, pl) end
	Players.PlayerRemoving:Connect(function(pl) awarded[pl.UserId] = nil end)
end

return Growth
