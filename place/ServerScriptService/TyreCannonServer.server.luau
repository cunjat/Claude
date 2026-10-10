--!strict
-- TYRE CANNON :: Server
-- Boots the server: profiles and saving, plots, spectating, leaderboards and
-- Robux receipts. The shop and progression (Economy), launches and payouts
-- (Runs) and the test console (Debug) live in the child modules.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Remotes = Root:WaitForChild("Remotes")

local Config = require(Modules.Config)
local Profile = require(script.Profile)

local STORE_KEY = "TyreCannon_profiles_v1"
local AUTOSAVE_SECONDS = 120
local PLOT_COUNT = 8
local AFK_SECONDS = 600

local store: DataStore? = nil
do
	local ok, res = pcall(function() return DataStoreService:GetDataStore(STORE_KEY) end)
	if ok then store = res end
end

local S: { [string]: any } = {
	Remotes = Remotes,
	profiles = {},
	loadFailed = {},
	statusOf = {},
	peakWatchers = {},
	fakeWatchers = {},
	liveOverride = {},
	boardCache = {},
}

--==============================================================
-- helpers
--==============================================================
local lastCall: { [number]: { [string]: number } } = {}

-- rate limit per action, so two quick shop clicks never cancel each other
function S.throttled(player: Player, gap: number, key: string?): boolean
	local now = os.clock()
	local bucket = lastCall[player.UserId]
	if not bucket then
		bucket = {}
		lastCall[player.UserId] = bucket
	end
	local k = key or "default"
	if now - (bucket[k] or 0) < gap then return true end
	bucket[k] = now
	return false
end

function S.save(userId: number, release: boolean?): boolean
	if S.loadFailed[userId] then return false end
	return Profile.save(store, userId, S.profiles[userId], release)
end

--==============================================================
-- plots
--==============================================================
local plotOwner: { [number]: number? } = {}
local ownerPlot: { [number]: number? } = {}
local lastMove: { [number]: number } = {}
local lastPos: { [number]: Vector3 } = {}

local function plotSnapshot()
	local out = {}
	for i = 1, PLOT_COUNT do
		local uid = plotOwner[i]
		if uid then
			local pl = Players:GetPlayerByUserId(uid)
			local pr = S.profiles[uid]
			out[i] = {
				userId = uid,
				name = pl and pl.DisplayName or "?",
				user = pl and pl.Name or "?",
				status = S.statusOf[uid] or "base",
				skin = pr and pr.skin or "stock",
				rim = pr and pr.rim or "steel",
				rigSkin = pr and pr.rigSkin or "works",
				generator = pr and pr.generator or "field",
				prestige = pr and pr.prestige or 0,
				title = pr and pr.title or "",
				stickers = pr and pr.stickers or {},
				rigName = pr and pr.prefs and pr.prefs.rigName or "",
				doorPaint = pr and pr.prefs and pr.prefs.doorPaint or "steel",
				doorStencil = pr and pr.prefs and pr.prefs.doorStencil or "none",
				honks = pr and pr.honks or 0,
				trail = pr and pr.trail or "none",
				pressure = pr and pr.pressure or 50,
				best = pr and math.floor(pr.lifetime.bestDistance * Config.Physics.StudsToMetres) or 0,
				-- the launch tyre, for VIEW WHEEL on the yard's sign
				wheel = (function()
					local v = pr and pr.v2
					if not v then return nil end
					for _, t in ipairs(v.inv) do
						if t.uid == v.launch then
							return { id = t.id, forge = t.forge or 0, mut = t.mut, design = v.designs and v.designs[tostring(t.uid)] or nil }
						end
					end
					return nil
				end)(),
			}
		else
			out[i] = false
		end
	end
	return out
end

function S.broadcastPlots()
	Remotes.PlotsUpdated:FireAllClients(plotSnapshot())
end

local plotsDirty = false
local function queuePlotBroadcast()
	if plotsDirty then return end
	plotsDirty = true
	task.delay(0.35, function()
		plotsDirty = false
		S.broadcastPlots()
	end)
end

local function releasePlot(userId: number)
	local i = ownerPlot[userId]
	if i then
		plotOwner[i] = nil
		ownerPlot[userId] = nil
	end
end

local function assignPlot(userId: number, wanted: number?): number?
	if wanted and (wanted < 1 or wanted > PLOT_COUNT) then return nil end
	if wanted and plotOwner[wanted] and plotOwner[wanted] ~= userId then return nil end
	local target = wanted
	if not target then
		for i = 1, PLOT_COUNT do
			if not plotOwner[i] then target = i break end
		end
	end
	if not target then return nil end
	releasePlot(userId)
	plotOwner[target] = userId
	ownerPlot[userId] = target
	return target
end

--==============================================================
-- live ranks (for Mythic titles)
--==============================================================
function S.refreshLive(skipUserId: number?)
	local rich = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local p = S.profiles[pl.UserId]
		if p then table.insert(rich, { uid = pl.UserId, v = p.credits }) end
	end
	table.sort(rich, function(a, b) return a.v > b.v end)
	local richRank = {}
	for i, r in ipairs(rich) do richRank[r.uid] = i end

	for _, pl in ipairs(Players:GetPlayers()) do
		local p = S.profiles[pl.UserId]
		if p then
			local live = { richest = richRank[pl.UserId] }
			for _, key in ipairs({ "distance", "robux" }) do
				for i, row in ipairs(S.boardCache[key] or {}) do
					if row.userId == pl.UserId then live[key] = i break end
				end
			end
			for k, v in pairs(S.liveOverride[pl.UserId] or {}) do live[k] = v end
			local before = p.live
			p.live = live
			local changed = not before or before.richest ~= live.richest
				or before.distance ~= live.distance or before.robux ~= live.robux
			if changed then
				if S.applyTitle then S.applyTitle(pl) end
				if pl.UserId ~= skipUserId then Remotes.ProfileUpdated:FireClient(pl, p) end
			end
		end
	end
end

function S.push(player: Player)
	local p = S.profiles[player.UserId]
	if not p then return end
	S.ensureContracts(p, player.UserId)
	S.refreshLive(player.UserId)
	Remotes.ProfileUpdated:FireClient(player, p)
	queuePlotBroadcast()

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local c = ls:FindFirstChild("Credits")
		if c then (c :: IntValue).Value = math.floor(math.min(p.credits, 2 ^ 31 - 1)) end
		local b = ls:FindFirstChild("Best")
		local best = 0
		for _, r in pairs(p.records) do best = math.max(best, r.dist) end
		if b then (b :: IntValue).Value = math.floor(best * Config.Physics.StudsToMetres) end
	end
end

--==============================================================
-- modules
--==============================================================
function S.plotOf(userId: number): number?
	return ownerPlot[userId]
end

require(script.Economy).init(S)
require(script.Debug).init(S)
require(script.Loop).init(S)
require(script.Heats).init(S)
require(script.Store).init(S)

--==============================================================
-- spectating
--==============================================================
local watchers: { [number]: { [number]: boolean } } = {}
local watchingWho: { [number]: number? } = {}

local function watcherCount(runnerId: number): number
	local n = S.fakeWatchers[runnerId] or 0
	for _ in pairs(watchers[runnerId] or {}) do n += 1 end
	return n
end

local function pushWatcherCount(runnerId: number)
	local n = watcherCount(runnerId)
	S.peakWatchers[runnerId] = math.max(S.peakWatchers[runnerId] or 0, n)
	local pl = Players:GetPlayerByUserId(runnerId)
	if pl then Remotes.SpectatorCount:FireClient(pl, n) end
end

local function stopWatching(viewerId: number)
	local target = watchingWho[viewerId]
	if not target then return end
	watchingWho[viewerId] = nil
	if watchers[target] then
		watchers[target][viewerId] = nil
		pushWatcherCount(target)
	end
end

Remotes.Spectate.OnServerInvoke = function(player: Player, targetUserId: any)
	if S.throttled(player, 0.3, "spectate") then return { ok = false, err = "One at a time." } end
	stopWatching(player.UserId)
	if targetUserId == nil then return { ok = true, stopped = true } end
	if type(targetUserId) ~= "number" then return { ok = false, err = "Bad request." } end
	if targetUserId == player.UserId then return { ok = false, err = "You can't watch yourself." } end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then return { ok = false, err = "They've left." } end
	if (S.statusOf[targetUserId] or "base") ~= "attempt" then
		return { ok = false, err = "They're not out on the road." }
	end
	watchers[targetUserId] = watchers[targetUserId] or {}
	watchers[targetUserId][player.UserId] = true
	watchingWho[player.UserId] = targetUserId
	pushWatcherCount(targetUserId)
	return { ok = true, target = targetUserId, name = target.DisplayName }
end

Remotes.RunState.OnServerEvent:Connect(function(player: Player, payload: any)
	if type(payload) ~= "table" then return end
	local set = watchers[player.UserId]
	if not set then return end
	for viewerId in pairs(set) do
		local v = Players:GetPlayerByUserId(viewerId)
		if v then Remotes.RunState:FireClient(v, player.UserId, payload) end
	end
end)

--==============================================================
-- lifecycle
--==============================================================
-- Everyone plays on the R6 body in StarterPlayer.StarterCharacter, because the character
-- animations are R6. Each spawn dresses it in the player's own avatar.
local avatarOf: { [number]: HumanoidDescription } = {}

local function dress(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then return end
	local desc = avatarOf[player.UserId]
	if not desc then
		local ok, res = pcall(function() return Players:GetHumanoidDescriptionFromUserId(math.max(1, player.UserId)) end)
		if not ok then return end
		desc = res
		avatarOf[player.UserId] = res
	end
	if char.Parent and hum.Parent then
		pcall(function() (hum :: Humanoid):ApplyDescription((desc :: HumanoidDescription):Clone()) end)
	end
end

local function onJoin(player: Player)
	player.CharacterAdded:Connect(function(char) dress(player, char) end)
	if player.Character then task.spawn(dress, player, player.Character) end

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local credits = Instance.new("IntValue")
	credits.Name = "Credits"
	credits.Parent = ls
	local best = Instance.new("IntValue")
	best.Name = "Best"
	best.Parent = ls
	ls.Parent = player

	S.statusOf[player.UserId] = "base"
	lastMove[player.UserId] = os.clock()

	local p, ok = Profile.load(store, player.UserId)
	if not player.Parent then
		-- they left while it loaded: hand the session lock straight back
		if ok then Profile.save(store, player.UserId, p, true) end
		return
	end
	S.profiles[player.UserId] = p
	if not ok then
		S.loadFailed[player.UserId] = true
		if RunService:IsStudio() then
			print("[TyreCannon] Studio: no DataStore access, playing on a fresh unsaved profile")
		else
			warn("[TyreCannon] profile failed to load for", player.UserId, "- this session will not save")
			Remotes.Notify:FireClient(player, { kind = "toast", bad = true,
				text = "Your save didn't load. Nothing this session will be kept. Rejoin to try again." })
		end
	end

	assignPlot(player.UserId, nil)
	S.applyTitle(player)
	S.push(player)
	S.broadcastPlots()
end

local function onLeave(player: Player)
	local uid = player.UserId
	S.save(uid, true)
	S.profiles[uid] = nil
	S.loadFailed[uid] = nil
	lastCall[uid] = nil
	releasePlot(uid)
	stopWatching(uid)
	for viewerId in pairs(watchers[uid] or {}) do watchingWho[viewerId] = nil end
	watchers[uid] = nil
	S.peakWatchers[uid] = nil
	S.fakeWatchers[uid] = nil
	S.liveOverride[uid] = nil
	S.statusOf[uid] = nil
	lastMove[uid] = nil
	lastPos[uid] = nil
	avatarOf[uid] = nil
	S.broadcastPlots()
	S.refreshLive()
end

Players.PlayerAdded:Connect(onJoin)
Players.PlayerRemoving:Connect(onLeave)
for _, pl in ipairs(Players:GetPlayers()) do task.spawn(onJoin, pl) end

game:BindToClose(function()
	local pending = 0
	for _, pl in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			S.save(pl.UserId, true)
			pending -= 1
		end)
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < 25 do task.wait(0.1) end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, pl in ipairs(Players:GetPlayers()) do task.spawn(S.save, pl.UserId) end
	end
end)

Remotes.RequestProfile.OnServerInvoke = function(player: Player)
	local t0 = os.clock()
	while not S.profiles[player.UserId] and os.clock() - t0 < 15 and player.Parent do task.wait(0.1) end
	task.defer(S.broadcastPlots)
	return S.profiles[player.UserId]
end

--==============================================================
-- plot remotes and status
--==============================================================
Remotes.ClaimPlot.OnServerInvoke = function(player: Player, index: any)
	if S.throttled(player, 0.4, "claim") then return { ok = false, err = "One at a time." } end
	if type(index) ~= "number" then return { ok = false, err = "Bad request." } end
	index = math.floor(index)
	if plotOwner[index] == player.UserId then return { ok = false, err = "This yard's already yours." } end
	if plotOwner[index] then return { ok = false, err = "Someone's already set up here." } end
	local got = assignPlot(player.UserId, index)
	if not got then return { ok = false, err = "Couldn't claim that yard." } end
	S.broadcastPlots()
	-- a push publishes this player's machine levels onto the yard they just took
	S.push(player)
	return { ok = true, plot = got }
end

Remotes.SetStatus.OnServerEvent:Connect(function(player: Player, status: any)
	if status ~= "base" and status ~= "launching" and status ~= "attempt" then return end
	if S.statusOf[player.UserId] == status then return end
	S.statusOf[player.UserId] = status
	lastMove[player.UserId] = os.clock()
	S.broadcastPlots()
end)

-- AFK comes from real movement, not a client claim
task.spawn(function()
	while true do
		task.wait(5)
		local changed = false
		for _, pl in ipairs(Players:GetPlayers()) do
			local uid = pl.UserId
			local char = pl.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local prev = lastPos[uid]
				if not prev or (hrp.Position - prev).Magnitude > 3 then
					lastPos[uid] = hrp.Position
					lastMove[uid] = os.clock()
				end
			end
			local idle = os.clock() - (lastMove[uid] or os.clock())
			local cur = S.statusOf[uid] or "base"
			if cur ~= "launching" and cur ~= "attempt" then
				local want = (idle >= AFK_SECONDS) and "afk" or "base"
				if cur ~= want then
					S.statusOf[uid] = want
					changed = true
				end
			end
		end
		if changed then S.broadcastPlots() end
	end
end)

--==============================================================
-- leaderboards
--==============================================================
local BOARDS = {
	{ key = "robux",      store = "tc_lb_robux_v1",    title = "ROBUX SPENT" },
	{ key = "distance",   store = "tc_lb_distance_v1", title = "LONGEST ATTEMPT" },
	{ key = "credits",    store = "tc_lb_credits_v1",  title = "CREDITS EARNED" },
	{ key = "spectators", store = "tc_lb_specs_v1",    title = "MOST WATCHED RUN" },
}
local SHOWN = {
	{ key = "robux", title = "ROBUX SPENT" },
	{ key = "distance", title = "LONGEST ATTEMPT" },
	{ key = "richest", title = "RICHEST HERE" },
	{ key = "spectators", title = "MOST WATCHED" },
}
-- this week's best distances (a fresh store every UTC week, Monday to Monday)
local WEEK = math.floor((os.time() + 3 * 86400) / (7 * 86400))
table.insert(BOARDS, { key = "week", store = "tc_lb_week_v3_" .. WEEK, title = "THIS WEEK" })
local boardStore: { [string]: OrderedDataStore? } = {}
for _, b in ipairs(BOARDS) do
	local ok, s = pcall(function() return DataStoreService:GetOrderedDataStore(b.store) end)
	if ok then boardStore[b.key] = s end
end
local nameCache: { [number]: string } = {}

local function refreshBoards()
	for _, b in ipairs(BOARDS) do
		local rows = {}
		local os_ = boardStore[b.key]
		if os_ then
			local ok, pages = pcall(function() return (os_ :: OrderedDataStore):GetSortedAsync(false, 15) end)
			if ok and pages then
				local ok2, page = pcall(function() return pages:GetCurrentPage() end)
				if ok2 and page then
					for _, entry in ipairs(page) do
						local uid = tonumber(entry.key)
						if uid then
							local nm = nameCache[uid]
							if not nm then
								local okn, res = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
								nm = okn and res or ("User " .. uid)
								nameCache[uid] = nm
							end
							table.insert(rows, { name = nm, value = entry.value, userId = uid })
						end
					end
				end
			end
		end
		if #rows == 0 then
			for _, pl in ipairs(Players:GetPlayers()) do
				local p = S.profiles[pl.UserId]
				if p then
					local v = (b.key == "week" and math.floor((p.v2 and p.v2.bestEver or 0)))
						or (b.key == "robux" and p.lifetime.robux)
						or (b.key == "distance" and math.floor(p.lifetime.bestDistance))
						or (b.key == "credits" and math.floor(p.lifetime.credits))
						or math.floor(p.lifetime.bestSpectators)
					if v and v > 0 then table.insert(rows, { name = pl.DisplayName, value = v, userId = pl.UserId }) end
				end
			end
			table.sort(rows, function(x, y) return x.value > y.value end)
		end
		S.boardCache[b.key] = rows
	end
	S.refreshLive()
end

function S.postBoard(key: string, userId: number, value: number)
	local os_ = boardStore[key]
	if not os_ or value <= 0 then return end
	task.spawn(function()
		pcall(function()
			(os_ :: OrderedDataStore):UpdateAsync(tostring(userId), function(old)
				return math.max(old or 0, math.floor(value))
			end)
		end)
	end)
end

function S.postWeekly(userId: number, metres: number)
	S.postBoard("week", userId, metres)
end

Remotes.Leaderboards.OnServerInvoke = function(_player: Player)
	local richest = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local p = S.profiles[pl.UserId]
		if p then table.insert(richest, { name = pl.DisplayName, value = math.floor(p.credits), userId = pl.UserId }) end
	end
	table.sort(richest, function(a, b) return a.value > b.value end)
	local out = {}
	for _, b in ipairs(SHOWN) do
		local rows = b.key == "richest" and richest or (S.boardCache[b.key] or {})
		table.insert(out, { key = b.key, title = b.title, rows = rows })
	end
	return out
end

-- the lobby's boards: two signs on the service hall's front (it faces the spawn), longest run of
-- all time and this week's, top ten each, in the kit's colours
local function lobbyBoards()
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then return nil end
	local old = lobby:FindFirstChild("RunBoards")
	if old then return old end
	local m = Instance.new("Model")
	m.Name = "RunBoards"
	local function board(name: string, x: number, title: string, accent: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.Size = Vector3.new(19, 13, 0.6)
		p.CFrame = CFrame.new(x, 15.5, 6006.4)
		p.Color = Color3.fromRGB(22, 22, 26)
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = m
		local edge = Instance.new("Part")
		edge.Name = name .. "Frame"
		edge.Anchored = true
		edge.CanCollide = false
		edge.Size = Vector3.new(20, 14, 0.4)
		edge.CFrame = CFrame.new(x, 15.5, 6006.1)
		edge.Color = accent
		edge.Material = Enum.Material.Metal
		edge.Parent = m
		local sg = Instance.new("SurfaceGui")
		sg.Name = "Board"
		sg.Face = Enum.NormalId.Back
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		sg.Brightness = 1.2
		sg.Parent = p
		local head = Instance.new("TextLabel")
		head.Name = "Title"
		head.BackgroundColor3 = accent
		head.BorderSizePixel = 0
		head.Size = UDim2.new(1, 0, 0, 80)
		head.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
		head.TextColor3 = Color3.new(1, 1, 1)
		head.TextSize = 56
		head.Text = title
		head.Parent = sg
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(14, 13, 12)
		stroke.Parent = head
		for i = 1, 10 do
			local row = Instance.new("TextLabel")
			row.Name = "Row" .. i
			row.BackgroundTransparency = i % 2 == 0 and 0.9 or 1
			row.BackgroundColor3 = Color3.new(1, 1, 1)
			row.BorderSizePixel = 0
			row.Position = UDim2.new(0, 20, 0, 88 + (i - 1) * 42)
			row.Size = UDim2.new(1, -40, 0, 40)
			row.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
			row.TextColor3 = i == 1 and Color3.fromRGB(255, 214, 92) or Color3.fromRGB(240, 236, 228)
			row.TextSize = 30
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.RichText = true
			row.Text = ""
			row.Parent = sg
		end
	end
	board("AllTime", -6022, "LONGEST RUN", Color3.fromRGB(246, 156, 38))
	board("Week", -5978, "THIS WEEK", Color3.fromRGB(152, 98, 236))
	m.Parent = lobby
	return m
end

local function paintBoards()
	local m = lobbyBoards()
	if not m then return end
	local function fill(partName: string, rows: { any }, toMetres: number)
		local p = m:FindFirstChild(partName)
		local sg = p and p:FindFirstChild("Board")
		if not sg then return end
		for i = 1, 10 do
			local r = rows[i]
			local label = sg:FindFirstChild("Row" .. i) :: TextLabel?
			if label then
				label.Text = r and ('%d.  %s  <font color="#ECC478">%s</font>'):format(i, r.name, Config.Physics and
					(math.floor(r.value * toMetres + 0.5) >= 10000 and ("%.1f KM"):format(r.value * toMetres / 1000) or (math.floor(r.value * toMetres + 0.5) .. " M")) or "") or ""
			end
		end
	end
	fill("AllTime", S.boardCache.distance or {}, Config.Physics.StudsToMetres)
	fill("Week", S.boardCache.week or {}, 1)
end

task.spawn(function()
	while true do
		pcall(refreshBoards)
		pcall(paintBoards)
		task.wait(90)
	end
end)

--==============================================================
-- Robux
--==============================================================
local function promptProduct(player: Player, productId: number)
	if productId == 0 then
		Remotes.Notify:FireClient(player, { kind = "toast", bad = true, text = "Not on sale yet." })
		return
	end
	local ok, err = pcall(function() MarketplaceService:PromptProductPurchase(player, productId) end)
	if not ok then
		warn("[TyreCannon] product prompt failed:", err)
		Remotes.Notify:FireClient(player, { kind = "toast", bad = true, text = "The purchase window didn't open. Try again." })
	end
end

Remotes.BuyRobux.OnServerEvent:Connect(function(player: Player, kind: any, id: any)
	if type(kind) ~= "string" or type(id) ~= "string" then return end
	local item
	if kind == "pack" then
		for _, c in ipairs(Config.CreditPacks) do if c.id == id then item = c break end end
	elseif kind == "skin" then item = Config.SkinsById[id]
	elseif kind == "trail" then item = Config.TrailsById[id]
	end
	if item then promptProduct(player, item.devProductId or 0) end
end)

Remotes.BuyCreditPack.OnServerEvent:Connect(function(player: Player, packId: any)
	if type(packId) ~= "string" then return end
	for _, c in ipairs(Config.CreditPacks) do
		if c.id == packId then promptProduct(player, c.devProductId or 0) return end
	end
end)

local receiptStore
pcall(function() receiptStore = DataStoreService:GetDataStore("TyreCannon_receipts_v1") end)

MarketplaceService.ProcessReceipt = function(info)
	local product = Config.ProductsById[info.ProductId]
	local storeItem = Config.StoreByProductId[info.ProductId]
	if not product and not storeItem then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local p = S.profiles[info.PlayerId]
	if not player or not p then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local key = "r_" .. info.PurchaseId
	if receiptStore then
		local ok, seen = pcall(function() return receiptStore:GetAsync(key) end)
		if not ok then return Enum.ProductPurchaseDecision.NotProcessedYet end
		if seen == true then return Enum.ProductPurchaseDecision.PurchaseGranted end
	end

	local message
	if storeItem then
		message = S.storeGrant and S.storeGrant(player, p, info.ProductId)
		if not message then return Enum.ProductPurchaseDecision.NotProcessedYet end
	elseif product.kind == "pack" then
		p.credits += product.credits
		message = ("+%d credits"):format(product.credits)
	elseif product.kind == "skin" then
		p.permanent.skins[product.id] = true
		p.skin = product.id
		message = product.name .. " is yours. For good."
	elseif product.kind == "trail" then
		p.permanent.trails[product.id] = true
		p.trail = product.id
		message = product.name .. " is yours. For good."
	else
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local spent = 0
	pcall(function()
		spent = MarketplaceService:GetProductInfo(info.ProductId, Enum.InfoType.Product).PriceInRobux or 0
	end)
	p.lifetime.robux += spent
	S.postBoard("robux", info.PlayerId, p.lifetime.robux)

	if not S.save(info.PlayerId) and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if receiptStore then pcall(function() receiptStore:SetAsync(key, true) end) end
	S.push(player)
	Remotes.Notify:FireClient(player, { kind = "toast", text = message })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

print(("[TyreCannon] server ready · %s · %d quirks · %d tracks · %d titles"):format(
	Config.VersionLabel, #Config.Perks, #Config.Tracks, #Config.Titles))
