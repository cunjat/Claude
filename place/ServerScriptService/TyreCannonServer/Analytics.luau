--!strict
-- TYRE CANNON :: Server / Analytics
-- What the Creator Dashboard's Analytics shows. AnalyticsService only logs from the server, so
-- every event goes through here:
--   funnel   the tutorial's steps (Game.TutorialSteps), in order, once a player
--            (Dashboard > Analytics > Funnels > Onboarding)
--   economy  cash and keys in and out, and what for (Dashboard > Analytics > Economy)
--   custom   a run: how far, and which zone it ended in (Dashboard > Analytics > Custom)
-- Every call is wrapped: analytics never breaks the game.
--   Analytics.funnel(player, step)                     step = index into Game.TutorialSteps
--   Analytics.earn(player, currency, amount, balance, kind, sku)    a source (Enum.AnalyticsEconomyTransactionType)
--   Analytics.spend(player, currency, amount, balance, kind, sku)   a sink
--   Analytics.custom(player, name, value, fields?)
--
-- The playtest log (2026-10-16): the Dashboard can't be read from inside the game, so the same
-- events are also counted here and kept in our own DataStore (TC_Playtest_v1), for the Debug
-- menu's Playtest tab, which any dev can open:
--   per UTC day ("d<day>")  counters: joins, new players, minutes played, runs and metres, each
--                           tutorial step reached, each custom event, cash and keys in and out,
--                           screens opened (from the client, Track), tips seen
--   "sessions"              the last 80 sessions: who, how long, runs, best, stage, tutorial step, level
--   "notes"                 the last 60 feedback notes and ratings
-- Counts gather in memory and are written once a minute (and on shutdown). In Studio the store
-- can't be reached, so the tab shows this server's own counts.
--   Analytics.count(name, n?) ; Analytics.note(entry) ; Analytics.describe = fn(player) -> session row
--   Analytics.read() -> { today, days, sessions, notes, live, day }

local AnalyticsService = game:GetService("AnalyticsService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))

local Analytics = {}

local function try(f: () -> ())
	local ok, err = pcall(f)
	if not ok then warn("[TyreCannon] analytics:", err) end
end

--==============================================================
-- the playtest log
--==============================================================
local store: DataStore? = nil
pcall(function() store = DataStoreService:GetDataStore("TC_Playtest_v1") end)
local MAX_SESSIONS, MAX_NOTES = 80, 60

local pending: { [string]: number } = {}       -- not yet written
local live: { [string]: number } = {}          -- everything this server has counted today
local pendingSessions, pendingNotes = {}, {}
local localSessions, localNotes = {}, {}       -- this server's own, newest first
local liveDay = Game.utcDay()
local joined: { [number]: number } = {}

-- a session row for a player who's leaving (Loop fills this in: runs, best, stage, level...)
Analytics.describe = nil :: ((Player) -> { [string]: any })?

function Analytics.count(name: string, n: number?)
	local d = Game.utcDay()
	if d ~= liveDay then
		liveDay = d
		live = {}
	end
	local k = n or 1
	pending[name] = (pending[name] or 0) + k
	live[name] = (live[name] or 0) + k
end

local function pushFront(list, row, cap)
	table.insert(list, 1, row)
	while #list > cap do table.remove(list) end
end

-- a feedback note or rating
function Analytics.note(entry: { [string]: any })
	pushFront(localNotes, entry, MAX_NOTES)
	table.insert(pendingNotes, entry)
end

local function flush()
	local day = liveDay
	local counts = pending
	pending = {}
	local sessions, notes = pendingSessions, pendingNotes
	pendingSessions, pendingNotes = {}, {}
	if not store then return end
	local s = store :: DataStore
	if next(counts) then
		local ok = pcall(function()
			s:UpdateAsync("d" .. day, function(old)
				local t = type(old) == "table" and old or {}
				for k, v in pairs(counts) do t[k] = (tonumber(t[k]) or 0) + v end
				return t
			end)
		end)
		-- (not written: they wait for the next go)
		if not ok then for k, v in pairs(counts) do pending[k] = (pending[k] or 0) + v end end
	end
	local function append(key: string, rows, cap: number)
		if #rows == 0 then return end
		pcall(function()
			s:UpdateAsync(key, function(old)
				local t = type(old) == "table" and old or {}
				for _, r in ipairs(rows) do pushFront(t, r, cap) end
				return t
			end)
		end)
	end
	append("sessions", sessions, MAX_SESSIONS)
	append("notes", notes, MAX_NOTES)
end

task.spawn(function()
	while true do
		task.wait(60)
		pcall(flush)
	end
end)
game:BindToClose(function() pcall(flush) end)

local function sessionEnd(player: Player)
	local t0 = joined[player.UserId]
	joined[player.UserId] = nil
	if not t0 then return end
	local minutes = (os.time() - t0) / 60
	Analytics.count("minutes", math.floor(minutes * 10 + 0.5) / 10)
	Analytics.count("sessions")
	local row: { [string]: any } = { n = player.Name, u = player.UserId, t = t0, m = math.floor(minutes * 10 + 0.5) / 10 }
	if Analytics.describe then
		local ok, extra = pcall(Analytics.describe :: any, player)
		if ok and type(extra) == "table" then
			for k, v in pairs(extra) do row[k] = v end
		end
	end
	pushFront(localSessions, row, MAX_SESSIONS)
	table.insert(pendingSessions, row)
end

Players.PlayerAdded:Connect(function(player)
	joined[player.UserId] = os.time()
	Analytics.count("joins")
end)
for _, pl in ipairs(Players:GetPlayers()) do
	joined[pl.UserId] = joined[pl.UserId] or os.time()
end
Players.PlayerRemoving:Connect(sessionEnd)
game:BindToClose(function()
	for _, pl in ipairs(Players:GetPlayers()) do sessionEnd(pl) end
	pcall(flush)
end)

-- everything the Playtest tab shows: today and the six days before (saved, or this server's own
-- when the store can't be read), the recent sessions and notes, and who's on now
function Analytics.read()
	pcall(flush)
	local day = Game.utcDay()
	local days = {}
	local sessions, notes = localSessions, localNotes
	local fromStore = false
	if store then
		local s = store :: DataStore
		for i = 0, 6 do
			local ok, t = pcall(function() return s:GetAsync("d" .. (day - i)) end)
			if ok then fromStore = true end
			table.insert(days, { day = day - i, c = if ok and type(t) == "table" then t else {} })
		end
		local ok1, ss = pcall(function() return s:GetAsync("sessions") end)
		if ok1 and type(ss) == "table" then sessions = ss end
		local ok2, nn = pcall(function() return s:GetAsync("notes") end)
		if ok2 and type(nn) == "table" then notes = nn end
	end
	if not fromStore then
		days = { { day = day, c = table.clone(live) } }
	end
	local now = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local row: { [string]: any } = { n = pl.Name, m = math.floor((os.time() - (joined[pl.UserId] or os.time())) / 6) / 10 }
		if Analytics.describe then
			local ok, extra = pcall(Analytics.describe :: any, pl)
			if ok and type(extra) == "table" then
				for k, v in pairs(extra) do row[k] = v end
			end
		end
		table.insert(now, row)
	end
	return { day = day, days = days, sessions = sessions, notes = notes, now = now, saved = fromStore, steps = Game.TutorialSteps }
end

--==============================================================
-- the Dashboard
--==============================================================
function Analytics.funnel(player: Player, step: number)
	local name = Game.TutorialSteps[step]
	if not name then return end
	Analytics.count("tut:" .. name)
	try(function() AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name) end)
end

-- kind: an Enum.AnalyticsEconomyTransactionType name ("Gameplay", "Shop", "IAP", "Onboarding", ...)
local function economy(player: Player, flow: Enum.AnalyticsEconomyFlowType, currency: string, amount: number, balance: number, kind: string, sku: string?)
	if amount <= 0 then return end
	Analytics.count((if flow == Enum.AnalyticsEconomyFlowType.Source then "in:" else "out:") .. currency, math.floor(amount + 0.5))
	try(function()
		AnalyticsService:LogEconomyEvent(player, flow, currency, math.floor(amount + 0.5), math.floor(balance + 0.5),
			(Enum.AnalyticsEconomyTransactionType :: any)[kind].Name, sku)
	end)
end

function Analytics.earn(player: Player, currency: string, amount: number, balance: number, kind: string, sku: string?)
	economy(player, Enum.AnalyticsEconomyFlowType.Source, currency, amount, balance, kind, sku)
end

function Analytics.spend(player: Player, currency: string, amount: number, balance: number, kind: string, sku: string?)
	economy(player, Enum.AnalyticsEconomyFlowType.Sink, currency, amount, balance, kind, sku)
end

function Analytics.custom(player: Player, name: string, value: number?, fields: { [string]: string }?)
	Analytics.count("ev:" .. name)
	if name == "RunMetres" and value then Analytics.count("metres", value) end
	if name == "Feedback" and value and value > 0 then
		Analytics.count("stars", value)
		Analytics.count("rated")
	end
	try(function()
		if fields then
			AnalyticsService:LogCustomEvent(player, name, value or 1, fields)
		else
			AnalyticsService:LogCustomEvent(player, name, value or 1)
		end
	end)
end

return Analytics
