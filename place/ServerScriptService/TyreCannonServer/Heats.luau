--!strict
-- TYRE CANNON :: Server / Heats
-- A race the whole server can join, on its own clock (Game.Heats). Every Every seconds a join
-- window opens for Join seconds; everyone who joined fires together on one seeded road, sees the
-- others as rival tyres (positions relayed four times a second), and is placed by distance:
-- 1st, 2nd and 3rd get a share of their run's cash again and a key. Everyone in the server hears
-- who won. The state rides on workspace attributes so every client can draw the countdown:
--   HeatPhase "idle" | "join" | "race"   HeatAt (os.time the phase ends)   HeatCount (joined)
-- Remotes (Remotes.V2): HeatJoin (fn), HeatStart (ev, to the joined: seed), HeatPos (unreliable,
-- client -> server metres, alt), HeatRivals (unreliable, server -> joined: { [userId] = {m, a} }),
-- HeatResult (ev, to all: the placings).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))

local Heats = {}

local function remote(folder: Instance, class: string, name: string): any
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = folder
	end
	return r
end

function Heats.init(S)
	local H = Game.Heats
	local folder = S.Remotes:WaitForChild("V2")
	local R = {
		Join = remote(folder, "RemoteFunction", "HeatJoin"),
		Start = remote(folder, "RemoteEvent", "HeatStart"),
		Pos = remote(folder, "UnreliableRemoteEvent", "HeatPos"),
		Rivals = remote(folder, "UnreliableRemoteEvent", "HeatRivals"),
		Result = remote(folder, "RemoteEvent", "HeatResult"),
	}
	-- in Studio a heat runs with one player, so it can be tried alone
	local minPlayers = RunService:IsStudio() and 1 or H.MinPlayers

	local phase = "idle"
	local joined: { [number]: boolean } = {}
	local racers: { [number]: { name: string, m: number, a: number, done: boolean, metres: number, cash: number } } = {}
	local seed = 0
	S.heatSeedFor = {} :: { [number]: number }

	local function setPhase(ph: string, endsAt: number)
		phase = ph
		workspace:SetAttribute("HeatPhase", ph)
		workspace:SetAttribute("HeatAt", endsAt)
		local n = 0
		for _ in pairs(joined) do n += 1 end
		workspace:SetAttribute("HeatCount", n)
	end

	R.Join.OnServerInvoke = function(player: Player)
		if phase ~= "join" then return { ok = false, err = "No heat open right now." } end
		local status = S.statusOf[player.UserId] or "base"
		if status ~= "base" and status ~= "afk" then return { ok = false, err = "Finish your run first." } end
		if not S.plotOf(player.UserId) then return { ok = false, err = "Claim a yard first." } end
		joined[player.UserId] = not joined[player.UserId] or nil
		local n = 0
		for _ in pairs(joined) do n += 1 end
		workspace:SetAttribute("HeatCount", n)
		return { ok = true, joined = joined[player.UserId] == true, count = n }
	end

	R.Pos.OnServerEvent:Connect(function(player: Player, m: any, a: any)
		local r = racers[player.UserId]
		if not r or r.done then return end
		local mm, aa = tonumber(m), tonumber(a)
		if mm and aa and mm == mm and aa == aa then
			r.live = true
			r.m = math.clamp(mm, 0, 1e6)
			r.a = math.clamp(aa, -50, 5000)
		end
	end)

	-- Loop's Finish calls this for every finished run; a racer's counts for the heat
	S.heatFinish = function(player: Player, metres: number, cash: number)
		local r = racers[player.UserId]
		if not r or r.done then return end
		r.done = true
		r.metres = metres
		r.cash = cash
	end

	local function settle()
		local list = {}
		for uid, r in pairs(racers) do
			if r.done then table.insert(list, { uid = uid, r = r }) end
		end
		table.sort(list, function(a, b) return a.r.metres > b.r.metres end)
		local placings = {}
		for i, e in ipairs(list) do
			local pl = Players:GetPlayerByUserId(e.uid)
			local p = S.profiles[e.uid]
			local bonus, keys = 0, 0
			if pl and p and p.v2 and i <= #H.Pay then
				bonus = math.floor(e.r.cash * H.Pay[i])
				keys = H.TopKeys
				p.credits += bonus
				p.v2.keys = math.min(1e6, p.v2.keys + keys)
				S.push(pl)
			end
			table.insert(placings, { userId = e.uid, name = e.r.name, metres = math.floor(e.r.metres), place = i, bonus = bonus, keys = keys })
		end
		if #placings > 0 then R.Result:FireAllClients(placings) end
		racers = {}
		S.heatSeedFor = {}
	end

	-- the clock: idle until the next slot, a join window, the race (until everyone's in or 90 s)
	task.spawn(function()
		while true do
			local now = os.time()
			local slot = math.floor(now / H.Every)
			local openAt = slot * H.Every
			local joinEnds = openAt + H.Join
			if now >= joinEnds then
				setPhase("idle", (slot + 1) * H.Every)
				task.wait(math.max(0.5, (slot + 1) * H.Every - now))
				continue
			end
			joined = {}
			setPhase("join", joinEnds)
			while os.time() < joinEnds do task.wait(0.25) end
			local n = 0
			for uid in pairs(joined) do
				if Players:GetPlayerByUserId(uid) then n += 1 else joined[uid] = nil end
			end
			if n < minPlayers then
				joined = {}
				continue
			end
			seed = math.random(1, 2147483646)
			racers = {}
			for uid in pairs(joined) do
				local pl = Players:GetPlayerByUserId(uid)
				if pl then
					racers[uid] = { name = pl.DisplayName, m = 0, a = 0, done = false, metres = 0, cash = 0 }
					S.heatSeedFor[uid] = seed
					R.Start:FireClient(pl, { seed = seed, count = n })
				end
			end
			joined = {}
			local raceEnds = os.time() + 90
			setPhase("race", raceEnds)
			while os.time() < raceEnds do
				task.wait(0.25)
				local snap = {}
				local allDone = true
				for uid, r in pairs(racers) do
					snap[tostring(uid)] = { r.m, r.a, r.name }
					if not r.done then allDone = false end
					if not Players:GetPlayerByUserId(uid) then racers[uid] = nil end
				end
				-- only to racers whose run is up (they report their own position once it is)
				for uid, r in pairs(racers) do
					local pl = Players:GetPlayerByUserId(uid)
					if pl and (r :: any).live and not r.done then R.Rivals:FireClient(pl, snap) end
				end
				if allDone then break end
			end
			settle()
		end
	end)
end

return Heats
