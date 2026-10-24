--!strict
-- TYRE CANNON :: Sound
-- The run's sounds by name, in one place. Every id is licensed audio from the Creator Store
-- (APM Music and Pro Sound Effects), so it plays in any experience. Change an id here and
-- it changes everywhere.
--   Sound.play(name, opts)      one-shot (opts: volume, pitch, length to fade out after)
--   Sound.bed(name)             start a looping music bed that stings duck under
--   Sound.duck(seconds)         pull the bed down while something important plays

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local Sound = {}

Sound.Bank = {
	-- Pro Sound Effects
	gateWhoosh = { id = "rbxassetid://9114346802", volume = 0.6, group = "Effects" },	-- enhanced vehicle pass by, fast whoosh
	land = { id = "rbxassetid://9114036511", volume = 0.5, group = "Effects" },			-- deep impacts, low end
	cheer = { id = "rbxassetid://9120973900", volume = 0.4, group = "Effects" },			-- crowd, short punchy cheers
	medal = { id = "rbxassetid://9113849492", volume = 0.6, group = "Effects" },			-- coins or keys jingle, metallic clinks
	-- (2026-10-23) the cannon going off: a short deep punch with a long booming tail under it
	launchPunch = { id = "rbxassetid://9114036511", volume = 0.85, group = "Effects" },	-- deep impacts 7
	launchBoom = { id = "rbxassetid://9125402735", volume = 0.5, group = "Effects" },	-- boom impact, deep distant, long resonant decay
	-- APM Music
	lobby = { id = "rbxassetid://1837050956", volume = 0.2, group = "Music", looped = true },	-- "Bouncing", 2:33
}

local bed: Sound? = nil
local bedVolume = 1
local duckUntil = 0
local duckLevel = 1
local bedSpeed = 1

local function make(def, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = def.id
	s.Volume = volume
	s.Looped = def.looped == true
	s.SoundGroup = SoundService:FindFirstChild(def.group) :: SoundGroup?
	s.Parent = SoundService
	return s
end

function Sound.play(name: string, opts: { [string]: any }?): Sound?
	local def = Sound.Bank[name]
	if not def then return nil end
	local o = opts or {}
	local s = make(def, def.volume * (o.volume or 1))
	s.PlaybackSpeed = o.pitch or 1
	s:Play()
	local length = o.length
	if length then
		task.delay(length, function()
			if s.Parent then TweenService:Create(s, TweenInfo.new(0.6), { Volume = 0 }):Play() end
		end)
		Debris:AddItem(s, length + 0.7)
	else
		Debris:AddItem(s, 30)
	end
	return s
end

-- a looping bed that fades in; stop it with Sound.stopBed
function Sound.bed(name: string)
	Sound.stopBed(0.2)
	local def = Sound.Bank[name]
	if not def then return end
	local s = make(def, 0)
	s:Play()
	bed = s
	bedVolume = 0
	TweenService:Create(s, TweenInfo.new(1.4), { Volume = def.volume }):Play()
	task.delay(1.45, function()
		if bed == s then bedVolume = def.volume end
	end)
end

function Sound.stopBed(fade: number?)
	local s = bed
	bed = nil
	if not s then return end
	local t = TweenService:Create(s, TweenInfo.new(fade or 0.8), { Volume = 0 })
	t:Play()
	t.Completed:Once(function() s:Destroy() end)
end

-- (2026-10-23) the hub's music: "Bouncing" while you're in the yard, paused (not restarted) during a run,
-- so coming back picks up where it left off; it waits for the loading intro to finish
local hubSong: Sound? = nil
local hubOn = false
function Sound.hubMusic(on: boolean)
	hubOn = on
	task.spawn(function()
		local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		while pg and pg:GetAttribute("IntroPlaying") do task.wait(0.25) end
		if hubOn ~= on then return end
		local def = Sound.Bank.lobby
		if not hubSong then
			hubSong = make(def, 0)
		end
		local s = hubSong :: Sound
		if on then
			if not s.IsPlaying then if s.TimePosition > 0 then s:Resume() else s:Play() end end
			TweenService:Create(s, TweenInfo.new(2.5), { Volume = def.volume }):Play()
		else
			local t = TweenService:Create(s, TweenInfo.new(0.8), { Volume = 0 })
			t:Play()
			t.Completed:Once(function() if not hubOn then s:Pause() end end)
		end
	end)
end

-- how fast the bed plays: slow motion drags the music down with it
function Sound.setBedSpeed(speed: number)
	bedSpeed = speed
end

function Sound.duck(seconds: number)
	duckUntil = math.max(duckUntil, os.clock() + seconds)
end

RunService.Heartbeat:Connect(function(dt)
	local s = bed
	if not s or bedVolume <= 0 then return end
	local goal = os.clock() < duckUntil and 0.35 or 1
	duckLevel += (goal - duckLevel) * (1 - math.exp(-dt * 6))
	s.Volume = bedVolume * duckLevel
	s.PlaybackSpeed += (bedSpeed - s.PlaybackSpeed) * (1 - math.exp(-dt * 5))
end)

-- every sound fetched ahead of its first play, but only once you're in: behind the loading screen
-- the menus and your yard go first (Preload queues these too, after the road)
task.spawn(function()
	local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local t0 = os.clock()
	while not pg:GetAttribute("TyreReady") and os.clock() - t0 < 60 do task.wait(0.5) end
	local list = {}
	for _, def in pairs(Sound.Bank) do
		local s = Instance.new("Sound")
		s.SoundId = def.id
		table.insert(list, s)
	end
	pcall(function() ContentProvider:PreloadAsync(list) end)
end)

return Sound
