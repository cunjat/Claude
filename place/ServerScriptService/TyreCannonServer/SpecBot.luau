--!strict
-- TYRE CANNON :: SpecBot (Studio only: TyreCannonServer requires it only in Studio)
-- A stand-in runner, to try spectating with one player. It takes a free yard, says it's out on a
-- run, and sends a recorded run's stream frames to whoever watches it, the way a real runner's
-- frames are relayed, so the yard's SPECTATE tab, the server's hand-off and the Spectator all run
-- as they do live.
--   workspace attribute SpecBotRecord = true   your next run streams as if watched, and is recorded
--                                              (kept in ServerStorage.DevTools.SpecBotRecording, so
--                                              copy it into the place to keep it between sessions)
--   workspace attribute SpecBot = true         the bot takes a yard and replays the recording on a
--                                              loop: the run, its end, a few seconds in base, again
--   workspace attribute SpecBotCount = n       n stand-ins instead of one (Spec Bot 1, 2, ...), each a
--                                              few seconds behind the last (for PREV / NEXT)
--   workspace attribute SpecBot = false        it leaves its yard

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local BOT_ID = -4242
local BOT_NAME = "Spec Bot"
local REST = 4 -- seconds in base between replays

local SpecBot = {}

-- the recording lives here for the session, and in ServerStorage.DevTools.SpecBotRecording as
-- StringValues of at most CHUNK characters each (a StringValue holds under 200,000), in order
local CHUNK = 190000
local kept: { any }? = nil

local function save(frames)
	kept = frames
	local tools = ServerStorage:FindFirstChild("DevTools") or Instance.new("Folder")
	tools.Name = "DevTools"
	tools.Parent = ServerStorage
	local old = tools:FindFirstChild("SpecBotRecording")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "SpecBotRecording"
	local json = HttpService:JSONEncode(frames)
	for i = 1, math.ceil(#json / CHUNK) do
		local v = Instance.new("StringValue")
		v.Name = string.format("%03d", i)
		v.Value = string.sub(json, (i - 1) * CHUNK + 1, i * CHUNK)
		v.Parent = folder
	end
	folder.Parent = tools
end

local function load(): { any }?
	if kept then return kept end
	local tools = ServerStorage:FindFirstChild("DevTools")
	local folder = tools and tools:FindFirstChild("SpecBotRecording")
	if not folder then return nil end
	local parts = folder:GetChildren()
	table.sort(parts, function(a, b) return a.Name < b.Name end)
	local buf = {}
	for _, v in ipairs(parts) do
		if v:IsA("StringValue") then table.insert(buf, v.Value) end
	end
	local ok, frames = pcall(function() return HttpService:JSONDecode(table.concat(buf)) end)
	if ok and type(frames) == "table" and #frames > 0 then
		kept = frames
		return frames
	end
	return nil
end

function SpecBot.init(S)
	local R = S.Remotes

	-- recording: everyone's runs stream (they're told one person's watching) and the next whole run
	-- of anyone's is kept
	local recording = nil
	local function arm()
		for _, pl in ipairs(Players:GetPlayers()) do
			S.fakeWatchers[pl.UserId] = math.max(S.fakeWatchers[pl.UserId] or 0, 1)
			R.SpectatorCount:FireClient(pl, S.fakeWatchers[pl.UserId])
		end
	end
	workspace:GetAttributeChangedSignal("SpecBotRecord"):Connect(function()
		if workspace:GetAttribute("SpecBotRecord") then arm() end
	end)
	-- (and again every few seconds while it's on: a client still loading misses the first word)
	task.spawn(function()
		while true do
			if workspace:GetAttribute("SpecBotRecord") then arm() end
			task.wait(3)
		end
	end)
	R.RunState.OnServerEvent:Connect(function(player: Player, payload: any)
		if not workspace:GetAttribute("SpecBotRecord") or type(payload) ~= "table" then return end
		if payload.done then
			if recording and #recording.frames > 20 then
				table.insert(recording.frames, { t = os.clock() - recording.t0, p = payload })
				local ok, err = pcall(save, recording.frames)
				if not ok then warn("[SpecBot] couldn't keep the recording:", err) end
				workspace:SetAttribute("SpecBotRecord", false)
				workspace:SetAttribute("SpecBotFrames", #recording.frames)
				S.fakeWatchers[player.UserId] = nil
				R.SpectatorCount:FireClient(player, 0)
			end
			recording = nil
			return
		end
		-- (a new seed is a new run: if the last one's end never came, start over rather than glue two)
		if recording and recording.sd ~= payload.sd then recording = nil end
		recording = recording or { t0 = os.clock(), frames = {}, sd = payload.sd }
		table.insert(recording.frames, { t = os.clock() - recording.t0, p = payload })
	end)

	-- the replay
	local running = false
	local function bot(id: number, frames: { any }, delay: number)
		local function setStatus(st: string?)
			S.statusOf[id] = st
			S.broadcastPlots()
		end
		local function send(payload: any)
			for viewerId in pairs(S.spectate.watchers[id] or {}) do
				local v = Players:GetPlayerByUserId(viewerId)
				if v then R.RunState:FireClient(v, id, payload) end
			end
		end
		task.wait(delay)
		while workspace:GetAttribute("SpecBot") do
			setStatus("attempt")
			local t0 = os.clock()
			for _, f in ipairs(frames) do
				if not workspace:GetAttribute("SpecBot") then break end
				local wait = (tonumber(f.t) or 0) - (os.clock() - t0)
				if wait > 0 then task.wait(wait) end
				send(f.p)
			end
			setStatus("base")
			task.wait(REST)
		end
		S.spectate.releasePlot(id)
		S.statusOf[id] = nil
		S.botNames[id] = nil
		S.broadcastPlots()
	end
	local function run()
		if running then return end
		local frames = load()
		if not frames then
			warn("[SpecBot] no recording yet: set workspace.SpecBotRecord = true and do a run")
			workspace:SetAttribute("SpecBot", false)
			return
		end
		local n = math.clamp(tonumber(workspace:GetAttribute("SpecBotCount")) or 1, 1, 4)
		running = true
		local live = 0
		for i = 1, n do
			local id = BOT_ID - (i - 1)
			S.botNames[id] = if n == 1 then BOT_NAME else ("%s %d"):format(BOT_NAME, i)
			if S.spectate.assignPlot(id, nil) then
				live += 1
				task.spawn(function()
					bot(id, frames, (i - 1) * 6)
					live -= 1
					if live <= 0 then running = false end
				end)
			else
				warn("[SpecBot] no free yard for", S.botNames[id])
				S.botNames[id] = nil
			end
		end
		if live == 0 then
			running = false
			workspace:SetAttribute("SpecBot", false)
		end
	end
	workspace:GetAttributeChangedSignal("SpecBot"):Connect(function()
		if workspace:GetAttribute("SpecBot") then run() end
	end)
	if workspace:GetAttribute("SpecBot") then task.defer(run) end
end

return SpecBot
