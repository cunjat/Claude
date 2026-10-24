--!strict
-- TYRE CANNON :: Main
-- Client state machine: yard -> launch -> run -> payout -> yard.
-- The run starts from the lever on your own yard. Prompts go through
-- ProximityPromptService so late-replicating plots can't miss a binding.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Remotes = Root:WaitForChild("Remotes")

local Config = require(Modules.Config)
local TrackGen = require(Modules.TrackGen)
local UI = require(script.Parent.UI)
local VFX = require(script.Parent.VFX)
local RunSim = require(script.Parent.RunSim)
local HubUI = require(script.Parent.HubUI)
local HudUI = require(script.Parent.HudUI)
local LaunchShow = require(script.Parent.LaunchShow)
local LaunchShow2 = require(script.Parent.LaunchShow2)
local YardEdit = require(script.Parent.YardEdit)
local YardLife = require(script.Parent.YardLife)
local PlotSigns = require(script.Parent.PlotSigns)
local Movement = require(script.Parent.Movement)
local AnimController = require(script.Parent.AnimController)
local PlotWheels = require(script.Parent.PlotWheels)
local Spectator = require(script.Parent.Spectator)
local TouchControls = require(script.Parent.TouchControls)
local TitleTags = require(script.Parent.TitleTags)
local DebugMenu = require(script.Parent.DebugMenu)
local ShiftLock = require(script.Parent.ShiftLock)
local Prefs = require(script.Parent.Prefs)
local PerfOverlay = require(script.Parent.PerfOverlay)
local DayNight = require(script.Parent.DayNight)
-- the revamped loop
local Game = require(Modules.Game)
local LaunchTap = require(script.Parent.LaunchTap)
local Receipt2 = require(script.Parent.Receipt2)
local Plot2 = require(script.Parent.Plot2)
local Physical = require(script.Parent.Physical)
local Settings2 = require(script.Parent.Settings2)
local Kit = require(script.Parent.Kit)
local StageUp = require(script.Parent.StageUp)
local Workbench = require(script.Parent.Workbench)
local Crates2 = require(script.Parent.Crates2)
local Tyres2 = require(script.Parent.Tyres2)
local Hub2 = require(script.Parent.Hub2)
local ZoneMap = require(script.Parent.ZoneMap)
local PlotStage = require(script.Parent.PlotStage)
local HubExtras = require(script.Parent.HubExtras)
local LaunchArcs = require(script.Parent.LaunchArcs)
local Rivals = require(script.Parent.Rivals)
local WheelView = require(script.Parent.WheelView)
local CannonWorker = require(script.Parent.CannonWorker)
local Tutorial = require(script.Parent.Tutorial)
local LobbyVista = require(script.Parent.LobbyVista)
local PerkPick = require(script.Parent.PerkPick)
local QuestCard = require(script.Parent.QuestCard)
local Tips = require(script.Parent.Tips)
local Sound = require(script.Parent.Sound)
local Goals = require(Modules.Goals)
local T = UI.Theme

--==============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "TyreCannonUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- our own pointer, in steel and red
UI.startCursor(gui)

local hub = HubUI.new(gui)
local hud = HudUI.new(gui)
local movement = Movement.new(gui)
local anims = AnimController.new(player, movement)
local spectator = Spectator.new(gui)
local touch = TouchControls.new(gui)
local shiftLock = ShiftLock.new(gui, function() return hub:isOpen() end)
hub.anims = anims
PerfOverlay.start(gui)
local dayNight = DayNight.new()
pcall(function() require(script.Parent.BenchPose).init() end)
Prefs.onError = function(msg) hub:toast(msg, T.bad) end

-- the revamped loop's screens
local V2 = Remotes:WaitForChild("V2", 30)
local plot2 = Plot2.new(gui, V2)
-- every yard's worker: out of the garage to fire its cannon
local cannonWorker = CannonWorker.new(plot2)
local yardLife = YardLife.new(plot2)
-- every yard dressed for its owner's tier
local plotStage = PlotStage.new()
-- the paths joining every yard to the plaza, and each yard's path to its cannon
local plotPaths = require(script.Parent.PlotPaths).new()
-- the land round the plaza (Launch Valley): built behind the loading screen, hidden for runs
local lobbyVista = LobbyVista.new()
local crates2 = Crates2.new(gui, V2)
local tyres2 = Tyres2.new(gui, V2)
local settings2 = Settings2.new(gui, function() anims:victory() end)
local bench = Workbench.new(gui, V2)
-- VIEW WHEEL on a yard's sign
local wheelView = WheelView.new(gui)
local hub2
-- the zone the next run starts in (picked on the zone map; the server checks you've reached it)
local zonePick = "backroad"
local zoneMap = ZoneMap.new(gui, function(id: string)
	zonePick = id
	if hub2 then hub2:setZone(id) end
end)
local hubX
-- the Shop lives in HubExtras; this lets it close and open like the other panels
local shopPanel = {
	isOpen = function() return hubX ~= nil and hubX:isShopOpen() end,
	close = function() if hubX then hubX:openShop(false) end end,
	open = function() if hubX then hubX:openShop(true) end end,
}
local eventsPanel = {
	isOpen = function() return hubX ~= nil and hubX:isEventsOpen() end,
	close = function() if hubX then hubX:openEvents(false) end end,
	open = function() if hubX then hubX:openEvents(true) end end,
}
-- your level, prestige and titles (opened from the level badge)
local profilePanel = require(script.Parent.ProfilePanel).new(gui, V2)
-- v4: the playtest's notes, from Settings; a quick rating after the 3rd and 10th run
local feedback = require(script.Parent.Feedback).new(gui, V2)
settings2.onFeedback = function() feedback:open() end
local help = require(script.Parent.Help).new(gui)
settings2.onHelp = function() help:open() end
local sessionRuns = 0
-- every panel the hub steps aside for
local PANELS = { plot2, crates2, tyres2, zoneMap, shopPanel, eventsPanel, settings2, bench, wheelView, profilePanel, feedback, help }
local function closePanels(except: any?)
	for _, panel in ipairs(PANELS) do
		if panel ~= except and panel:isOpen() then panel:close() end
	end
end
-- the playtest log: which screens get opened (Analytics on the server counts them)
local PANEL_NAMES = {
	[plot2] = "plot", [crates2] = "crates", [tyres2] = "tyres", [zoneMap] = "zones", [shopPanel] = "shop", [eventsPanel] = "events",
	[settings2] = "settings", [bench] = "workbench", [wheelView] = "wheel", [profilePanel] = "profile", [feedback] = "feedback",
}
local function track(name: string)
	local r = V2 and V2:FindFirstChild("Track")
	if r then pcall(function() (r :: RemoteEvent):FireServer(name) end) end
end
local function togglePanel(panel)
	-- the login calendar is up: nothing opens over it until it's claimed (a hotkey could)
	if not panel:isOpen() and hubX and hubX:isDailyOpen() then return end
	if not panel:isOpen() then track("open:" .. (PANEL_NAMES[panel] or "panel")) end
	if panel:isOpen() then
		panel:close()
	elseif Receipt2.active then
		-- one menu at a time: the receipt fades right out before the panel comes in
		Receipt2.active(function()
			closePanels(panel)
			panel:open()
		end)
	else
		closePanels(panel)
		panel:open()
	end
end

-- two volume knobs for everything that makes a sound
do
	local SoundService = game:GetService("SoundService")
	local function group(name: string, key: string)
		local g = SoundService:FindFirstChild(name) :: SoundGroup?
		if not g then
			g = Instance.new("SoundGroup")
			g.Name = name
			g.Parent = SoundService
		end
		Prefs.watch(key, function(v) (g :: SoundGroup).Volume = tonumber(v) or 1 end)
	end
	group("Music", "music")
	group("Effects", "sfx")
end
TitleTags.start(playerGui)

local state = "hub"
local profile = nil
local sim = nil
local show = nil
local myPlot: Instance? = nil
local signs = nil
local wheels = nil

-- older prompt actions still map onto the new menu
local PANEL_FOR = {
	Career = "Career", Codex = "Career", Prestige = "Career", Boards = "Career",
}

local function setStatus(s: string)
	Remotes.SetStatus:FireServer(s)
end

local function rootPart(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

--==============================================================
-- profile
--==============================================================
local lastPrestige = nil
-- the first session's tutorial (made once the hub exists, further down)
local tutorial = nil
-- v4: today's jobs on the right of the yard, and the perk picker after a prestige
local questCard = nil
local perkPick = nil
local function applyProfile(p)
	if not p then return end
	if lastPrestige and (p.prestige or 0) > lastPrestige then
		local r = rootPart()
		if r then
			VFX.emit("Lightning", r.CFrame, { scale = 3 })
			task.delay(0.25, function() VFX.emit("Lightning", r.CFrame * CFrame.new(0, 4, 0), { scale = 4 }) end)
		end
	end
	lastPrestige = p.prestige or 0
	profile = p
	Prefs.load(p)
	hub:setProfile(p)
	plot2:setProfile(p)
	crates2:setProfile(p)
	tyres2:setProfile(p)
	bench:setProfile(p)
	zoneMap:setProfile(p)
	if hub2 then hub2:setProfile(p) end
	if hubX then hubX:setProfile(p) end
	profilePanel:setProfile(p)
	if tutorial then tutorial:setProfile(p) end
	if questCard then questCard:setProfile(p) end
end

task.spawn(function()
	local ok, res = pcall(function() return Remotes.RequestProfile:InvokeServer() end)
	if ok then applyProfile(res) end
end)
Remotes.ProfileUpdated.OnClientEvent:Connect(applyProfile)

-- the character's animations (small). (Every asset used to be queued here as well, a second full
-- preload on top of Preload's that doubled the download queue behind the loading screen; Preload
-- does that now, the menus and your yard first and the rest once you're in.)
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local list = {}
	for _, id in pairs(Config.Animations or {}) do
		if type(id) == "string" and id ~= "" then
			local a = Instance.new("Animation")
			a.AnimationId = id
			table.insert(list, a)
		end
	end
	pcall(function() ContentProvider:PreloadAsync(list) end)
end)

--==============================================================
-- character, prompts, camera
--==============================================================
local function setCharacterActive(active: boolean)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.AutoRotate = active end
	movement:setEnabled(active)
	anims:setEnabled(active)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = active and 0 or 1
		end
	end
end

-- the last plot snapshot from the server (who owns which yard)
local lastSnapshot = nil
local function setPromptsEnabled(on: boolean)
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then return end
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			-- (2026-10-23, the owner: "there is STILL a lingering claim plot there even though your plot is
			-- auto claimed") yards are given out on joining, so a claim prompt never comes back; it used to
			-- return on every free yard each time the hub came back
			local pad = d.Parent
			if pad and pad.Name == "ClaimPad" then
				d.Enabled = false
			else
				d.Enabled = on
			end
		end
	end
end

-- the walking camera starts well back and a little above: the yards are full of big machines, and
-- Roblox's default 12 studs puts the whole screen inside one. Pinning both zoom limits for a moment
-- sets the distance; then the player can zoom as they like.
local HUB_ZOOM, ZOOM_MIN, ZOOM_MAX = 26, 10, 60
local function setHubZoom()
	player.CameraMinZoomDistance = HUB_ZOOM
	player.CameraMaxZoomDistance = HUB_ZOOM
	task.delay(0.2, function()
		player.CameraMinZoomDistance = ZOOM_MIN
		player.CameraMaxZoomDistance = ZOOM_MAX
	end)
end

local function restoreCamera()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
	-- the follow camera keeps whatever offset it's handed: after the launch shot that's inside the
	-- cannon, so start it from a plain spot behind the character
	local hrp = rootPart()
	if hrp then
		local back = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
		back = back.Magnitude > 0.01 and back.Unit or Vector3.new(0, 0, -1)
		-- (2026-10-16) behind the character, unless something's in the way (the cannon, after a run:
		-- the camera ended up with the screen full of it): then the first clear side, turning round
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Instance }
		local eye = hrp.Position + Vector3.new(0, 2, 0)
		local pick = nil
		for k = 0, 7 do
			local a = (if k % 2 == 0 then 1 else -1) * math.ceil(k / 2) * math.rad(45)
			local dir = CFrame.Angles(0, a, 0):VectorToWorldSpace(back)
			local at = hrp.Position - dir * HUB_ZOOM * 0.92 + Vector3.new(0, HUB_ZOOM * 0.42, 0)
			if not workspace:Raycast(eye, at - eye, params) then
				pick = at
				break
			end
		end
		pick = pick or (hrp.Position - back * HUB_ZOOM * 0.92 + Vector3.new(0, HUB_ZOOM * 0.42, 0))
		cam.CFrame = CFrame.lookAt(pick, hrp.Position + Vector3.new(0, 1.5, 0))
	end
	setHubZoom()
end

local function setHubMode(on: boolean)
	-- the old credits plate and menu bar stay hidden; the revamp's dock replaces them
	hub:setHubVisible(false)
	if hub2 then hub2:setVisible(on) end
	if hubX then hubX:setVisible(on) end
	if not on then closePanels() end
	setPromptsEnabled(on)
	setCharacterActive(on)
	shiftLock:setAllowed(on)
	dayNight:setActive(on)
	yardLife:setPaused(not on)
	Sound.hubMusic(on)
end

--==============================================================
-- spectating
--==============================================================
local function startSpectating(userId: number, name: string?)
	if state ~= "hub" then
		hub:toast("Finish what you're doing first.", T.bad)
		return
	end
	hub:closeAll()
	setHubMode(false)
	if signs then signs:setVisible(false) end
	state = "spectate"
	lobbyVista:setVisible(false)
	if not spectator:start(userId, name) then
		lobbyVista:setVisible(true)
		state = "hub"
		setHubMode(true)
		if signs then signs:setVisible(true) end
		hub:toast(spectator.lastError or "Couldn't watch that run.", T.bad)
	end
end

spectator.onStop = function()
	if state ~= "spectate" then return end
	lobbyVista:setVisible(true)
	state = "hub"
	restoreCamera()
	setHubMode(true)
	if signs then signs:setVisible(true) end
end

--==============================================================
-- after a run: a personal best earns the victory, a blowout or a hit earns the chair
--==============================================================
local function reactToRun(summary, payout)
	local r = rootPart()
	if r then VFX.emit("PortalEnter", r.CFrame * CFrame.new(0, -2.8, 0), { scale = 2 }) end
	if payout and payout.best then
		task.delay(0.4, function() anims:victory() end)
	elseif summary.reason == "overheat" or (summary.hits or 0) > 0 then
		local base = myPlot and myPlot:GetAttribute("BaseCFrame")
		local chair = ReplicatedStorage.TyreCannon.Assets.Props:FindFirstChild("Chair")
		if base and chair then
			local upright = chair:GetAttribute("Upright") or CFrame.new()
			local chairCF = base * CFrame.new(-2, 2 + 1.35, 6) * CFrame.Angles(0, math.pi / 2, 0) * upright
			task.delay(0.3, function() anims:sadSit(chairCF) end)
		end
	end
end

--==============================================================
-- the run
--==============================================================
local startRun
local launchesThisSession = 0
local heatRun = false
local rivals = nil

startRun = function(_trackId: string?, auto: boolean?, _startX: number?)
	if state ~= "hub" then return end
	if hubX and hubX:isDailyOpen() then
		hub:toast("Claim your daily reward first.", T.bad)
		return
	end
	if tutorial and tutorial:isChoosing() then return end
	-- whatever path started this run, the last receipt goes first
	if Receipt2.active then Receipt2.active(function() end) end
	if not profile then
		hub:toast("Still loading your save.", T.bad)
		return
	end
	if not myPlot then
		hub:toast(if game:GetService("UserInputService").KeyboardEnabled then "No yard yet. Walk up to a free plot and press E." else "No yard yet. Walk up to a free plot and tap Claim.", T.bad)
		return
	end
	anims:standUp(true)
	state = "launch"
	local ok, begin = pcall(function() return V2.Begin:InvokeServer(zonePick) end)
	if not ok or type(begin) ~= "table" or not begin.ok then
		state = "hub"
		hub:toast((type(begin) == "table" and begin.err) or "Couldn't start the run.", T.bad)
		return
	end
	hub:closeAll()
	setHubMode(false)
	setStatus("launching")
	if tutorial then tutorial:launching() end

	-- you go home for the launch, so the run hands you back in your own yard beside what you buy next
	local home = myPlot:FindFirstChild("OwnerSpawn") :: BasePart?
	local char = player.Character
	if home and char and char.PrimaryPart then
		char:PivotTo(home.CFrame * CFrame.new(0, 3.2, 0))
	end

	-- your yard's worker walks out to the cannon for the launch
	pcall(function() cannonWorker:attend(myPlot :: Instance) end)
	-- at the cannon: the camera comes round, the tyre goes in, the dial decides the shot
	local cannon = plot2:cannonOf(myPlot)
	local launchId = nil
	local launchDesign = nil   -- (its paint and stickers ride into the cannon with it)
	local v2 = profile.v2
	if v2 then
		for _, t in ipairs(v2.inv) do
			if t.uid == v2.launch then
				launchId = t.id
				launchDesign = v2.designs and v2.designs[tostring(t.uid)] or nil
			end
		end
	end
	show = (cannon and LaunchShow2.new(profile.skin, myPlot, cannon, Plot2.ModelScale.cannon, launchId, launchDesign)) or LaunchShow.new(profile.skin, myPlot)
	-- quick fire: after the first launch of a session the load-in plays fast; a Good or Weak shot
	-- plays fast too, while a Great or Perfect keeps its full build-up (the tell is the point)
	launchesThisSession += 1
	local repeatLaunch = launchesThisSession > 1
	if show and repeatLaunch then (show :: any).quick = 1.7 end
	if show then
		show:takeCamera()
		show:pullLever()
		-- the dial comes up once the tyre is in
		if show.waitReady then show:waitReady() end
	end
	local autoLaunch = auto or (profile.v2 and profile.v2.passes and profile.v2.passes.autolaunch) or false
	-- Rev & Shift: three shifts grade the launch, and each one lands on the cannon as it happens
	local grade = LaunchTap.run(gui, autoLaunch, function(gear, rating)
		if show and show.shift then show:shift(gear, rating) end
	end, tutorial and tutorial:launchSlow() or 1)
	local G = LaunchTap.Grades[grade] or LaunchTap.Grades.good
	if show then
		local quick = repeatLaunch and (grade == "good" or grade == "weak")
		;(show :: any).quick = if quick then 2.4 elseif repeatLaunch then 1.15 else 1
		show:release(400 + G.show * 600, G.show, grade)
		show:destroy()
		show = nil
	end
	-- the shot's away: the worker goes back in
	if myPlot then pcall(function() cannonWorker:dismiss(myPlot :: Instance) end) end

	state = "run"
	setStatus("attempt")
	lobbyVista:setVisible(false)
	-- the run: steer, boost, ride the road through every zone it reaches
	local road = TrackGen.get("road")
	road:setRun(begin.seed or os.time(), 0, 0)
	road.keyAllow = if type(begin.keyZones) == "table" then begin.keyZones else {}
	-- Stampede (a server event) fills the road with more targets
	road.targetRate = (begin.stats and begin.stats.targetRate) or 1
	local stats = begin.stats or Game.runStats(begin.mach or {}, begin.tier or 1, begin.tyre)
	local startMetres = tonumber(begin.startMetres) or 0
	local zone1 = Game.Zones[Game.zoneAt(startMetres)]
	hud:setTrack({ name = zone1.name, creditMult = zone1.rate }, (begin.best or 0) / Game.StudsToMetres)
	hud:show()
	local push = G.push
	if game:GetService("RunService"):IsStudio() and player:GetAttribute("DebugStartX") then
		-- Studio zone check: a late-game tyre so the stretch can be ridden
		stats = table.clone(stats)
		stats.launchSpeed = math.max(stats.launchSpeed, 520)
		stats.boostAccel = math.max(stats.boostAccel, 240)
		stats.boostFuel = math.max(stats.boostFuel, 300)
		stats.frictionScale, stats.dragScale = 0.55, 0.5
	end
	local thisIsHeat = heatRun
	sim = RunSim.start({
		trackId = "road",
		stats = stats,
		tyreId = begin.tyre and begin.tyre.id,
		design = begin.tyre and begin.tyre.design,
		skin = profile.skin,
		launchSpeed = stats.launchSpeed * push,
		launchAngleDeg = stats.launchAngle or 26,
		flawless = grade == "perfect",
		nitroStart = G.nitro,
		-- Studio only: start further down the road to look at a zone (set the attribute on the player)
		startX = (startMetres > 0 and startMetres / Game.StudsToMetres)
			or (game:GetService("RunService"):IsStudio() and player:GetAttribute("DebugStartX")) or nil,
		best = (begin.best or 0) / Game.StudsToMetres,
		bestName = player.DisplayName,
		ghost = begin.ghost,
		rivals = begin.rivals,
		hudGui = gui,
		onTick = function(s)
			hud:update(s)
			if tutorial then tutorial:runTick(s) end
		end,
		onEvent = function(e)
			hud:event(e)
			if tutorial then tutorial:runEvent(e) end
			if e.kind == "ghostpass" then
				hud:stamp("PASSED YOUR BEST!", Color3.fromRGB(255, 200, 70), 46, -3, "every metre from here is a new record")
				Sound.play("medal", { volume = 0.8, pitch = 1.15, length = 1.2 })
			end
		end,
		onEnd = function(summary)
			touch:unbind()
			sim = nil
			if rivals then
				rivals:stop()
				rivals = nil
			end
			hud:hide()
			lobbyVista:setVisible(true)
			state = "payout"
			local okF, payout = pcall(function()
				return V2.Finish:InvokeServer({
					metres = summary.metres, keys = summary.keys, smashes = summary.smashes, perks = summary.perks,
					spins = summary.spins, pads = summary.pads, metals = summary.metals, airTime = summary.airTime,
					runTime = summary.runTime, blowout = summary.blowout, zone = summary.zone,
					ghost = summary.ghost, splits = summary.splits, photo = summary.photo, seen = summary.seen,
					hits = summary.hits, redlineSeconds = summary.redlineSeconds, longestAir = summary.longestAir,
					drafts = summary.drafts, flawless = summary.flawless, startX = summary.startX,
					bounces = summary.bounces, perfects = summary.perfects, peakChain = summary.peakChain,
					comboMetres = summary.comboMetres, zoneSmashes = summary.zoneSmashes, zoneBonus = summary.zoneBonus,
				})
			end)
			if not okF or type(payout) ~= "table" then payout = { cash = 0, metres = summary.metres } end
			restoreCamera()
			setHubMode(true)
			state = "hub"
			setStatus("base")
			reactToRun({ reason = summary.reason, hits = summary.hits or 0 }, { best = payout.best })
			if tutorial then tutorial:runEnd(summary, payout) end
			-- a Heat has its own result (the placings, from the server): no Run Complete over it
			if thisIsHeat then
				if (payout.cash or 0) > 0 then hub:toast(("Heat run paid $%s"):format(Game.short(payout.cash)), T.good or T.accent) end
			else
				sessionRuns += 1
				if sessionRuns == 3 or sessionRuns == 10 then
					-- (2026-10-24) only at home: a Launch Again inside 4 s used to put the card over the launch
					local asked = sessionRuns
					task.delay(4, function()
						local waited = 0
						while state ~= "hub" and waited < 600 do waited += task.wait(0.5) end
						if state == "hub" then feedback:askRating(("run %d, stage %d"):format(asked, profile and profile.v2 and profile.v2.tier or 0)) end
					end)
				end
				if payout.trialJust then
					task.delay(1.2, function()
						Kit.callout(gui, "STAGE TRIAL COMPLETE", Color3.fromRGB(255, 196, 64), UDim2.fromScale(0.5, 0.16), 40)
						Sound.play("medal", { volume = 0.8, pitch = 1.1 })
					end)
				end
				Receipt2.show(gui, summary, payout, function()
					task.delay(0.15, function() startRun() end)
				end, function()
					closePanels(plot2)
					plot2:open()
				end)
			end
		end,
	})
	touch:bind(sim)
	if tutorial then tutorial:runStart(sim, tonumber(begin.best) or 0) end
	-- a Heat: the other racers ride alongside
	if heatRun and sim then rivals = Rivals.start(sim, V2) end
	heatRun = false
	if begin.testDrive then hud:stamp("TEST DRIVE", Color3.fromRGB(255, 196, 64), 44, -3, string.upper(begin.tyre and Game.TyresById[begin.tyre.id] and Game.TyresById[begin.tyre.id].name or ""))
	elseif type(begin.trial) == "table" and not begin.trial.done and begin.trial.k then
		-- the stage's trial, said at the start of every run until it's done
		hud:stamp("STAGE TRIAL", Color3.fromRGB(255, 196, 64), 34, -2, string.upper(Goals.text({ k = begin.trial.k, t = begin.trial.t })))
	end
end

hud.onDraftPick = function(i: number)
	if sim and sim.pickDraft then sim:pickDraft(i) end
end

hub2 = Hub2.new(gui, V2, {
	launch = function()
		closePanels()
		if Receipt2.active then
			Receipt2.active(function() startRun() end)
		else
			startRun()
		end
	end,
	plot = function() togglePanel(plot2) end,
	profile = function() togglePanel(profilePanel) end,
	tyres = function() togglePanel(tyres2) end,
	crates = function() togglePanel(crates2) end,
	zones = function() togglePanel(zoneMap) end,
	zone = function() return zonePick end,
	shop = function() togglePanel(shopPanel) end,
	events = function() togglePanel(eventsPanel) end,
	bench = function() togglePanel(bench) end,
	settings = function() togglePanel(settings2) end,
	daily = function()
		if hubX and profile and profile.v2 and not hubX:isDailyOpen() then
			closePanels()
			hubX:showDaily(profile.v2)
		end
	end,
})
if profile then hub2:setProfile(profile) end
tutorial = Tutorial.new(gui, {
	remotes = Remotes,
	hud = hud,
	touch = touch,
	hub2 = function() return hub2 end,
	plot2 = plot2,
	crates2 = crates2,
	receipt = Receipt2,
	state = function() return state end,
	hubX = function() return hubX end,
	showDaily = function()
		if hubX and profile and profile.v2 and not hubX:isDailyOpen() then hubX:showDaily(profile.v2) end
	end,
	-- the yard with nothing open over it
	idle = function()
		if state ~= "hub" or Receipt2.active or crates2.stage.Visible then return false end
		if hubX and hubX:isDailyOpen() then return false end
		if playerGui:GetAttribute("IntroPlaying") then return false end
		for _, panel in ipairs(PANELS) do
			if panel:isOpen() then return false end
		end
		return true
	end,
})
if profile then tutorial:setProfile(profile) end
-- Roblox's invite, notification and group prompts, at quiet moments after the tutorial (GrowthClient)
require(script.Parent.GrowthClient).start({
	profile = function() return profile end,
	idle = function() return tutorial ~= nil and tutorial.ctx.idle() and not tutorial:isChoosing() end,
	v2 = V2,
})
-- shift lock lets go of the mouse while any menu or card is up, so its buttons can be clicked
shiftLock.blocked = function()
	if hub:isOpen() or (hubX and hubX:isDailyOpen()) then return true end
	for _, p in ipairs(PANELS) do
		if p and p.isOpen and p:isOpen() then return true end
	end
	return false
end
hubX = HubExtras.new(gui, V2, {
	-- a newcomer's tutorial-or-skip comes before the daily reward
	holdDaily = function() return tutorial ~= nil and tutorial:holdDaily() end,
	-- no Heat notice over the tutorial's choice, the daily reward, or a newcomer's first launch
	quiet = function()
		if hubX and hubX:isDailyOpen() then return true end
		if not tutorial then return false end
		return tutorial:isChoosing() or (tutorial.active and not tutorial:is("First run"))
	end,
	idle = function()
		if state ~= "hub" or Receipt2.active then return false end
		for _, panel in ipairs(PANELS) do
			if panel:isOpen() then return false end
		end
		return true
	end,
	eventLive = function(on: boolean) if hub2 then hub2:setEventLive(on) end end,
	-- the heat's started: everyone who joined launches now (if they're still in the hub)
	heatStart = function(_d)
		if state ~= "hub" then return end
		closePanels()
		heatRun = true
		if Receipt2.active then
			Receipt2.active(function() startRun() end)
		else
			task.spawn(startRun)
		end
	end,
})
if profile then hubX:setProfile(profile) end
-- rewards (titles, levels, jobs...) wait for the yard: not over a run, the payout or a crate opening
hubX.rewardGate = function()
	return state == "hub" and not Receipt2.active and not (crates2.stage and crates2.stage.Visible)
end

-- v4: today's jobs, the perk picker, and the banners for quests, trials, themes and likes
questCard = QuestCard.new(gui)
perkPick = PerkPick.new(gui, V2)
if profile then questCard:setProfile(profile) end
V2:WaitForChild("Quest").OnClientEvent:Connect(function(d)
	if type(d) ~= "table" then return end
	hubX:reward({ text = d.text, keys = d.keys, bonus = if (d.cash or 0) > 0 then "+$" .. Game.short(d.cash) else nil })
	Sound.play("medal", { volume = 0.6, pitch = if d.kind == "like" then 1.3 else 1.0 })
end)
task.spawn(function()
	local perkLater = 0
	while true do
		task.wait(0.25)
		local idle = tutorial ~= nil and tutorial.ctx.idle() and state == "hub"
		local inTutorial = tutorial ~= nil and (tutorial.active or tutorial.list ~= nil)
		-- (2026-10-16: the jobs live in the Profile's Jobs tab now; the card on the yard was clutter)
		questCard:show(false)
		local _ = inTutorial
		-- a prestige's perks wait on the table until one's picked (closing it brings it back later)
		local v = profile and profile.v2
		if v and v.perkOffer and #v.perkOffer > 0 and idle and not perkPick:isOpen() and os.clock() > perkLater then
			perkLater = os.clock() + 90
			perkPick:show(v.perkOffer, v.perks, profile.prestige or 0)
		end
	end
end)
LaunchArcs.workers = cannonWorker
LaunchArcs.start(V2, plot2, hub)
LaunchArcs.onAutoPaid = function(cash: number) if hub2 then hub2:autoFired(cash) end end
Receipt2.onShown = function(_on: boolean) end
-- the hub steps aside for whatever's on top: while a panel, the crate opening or the receipt is up,
-- only your cash and keys stay; the dock, the corner buttons, the Heat notice and Launch all go (and
-- the screen darkens behind the panel, Kit.dim), so a screen never fights the one under it
task.spawn(function()
	while true do
		task.wait(0.1)
		local busy = Receipt2.active ~= nil or crates2.stage.Visible or (hubX ~= nil and hubX:isResultOpen())
		for _, panel in ipairs(PANELS) do
			if panel:isOpen() then busy = true end
		end
		if hub2.side then hub2.side.Visible = not busy end
		if hub2.corner then hub2.corner.Visible = not busy end
		if hub2.launchDock then hub2.launchDock.Visible = not busy end
		if hubX and hubX.root then hubX.root.Visible = not busy and state == "hub" end
	end
end)

-- open a menu without clicking (workspace DebugPanel = "plot" | "tyres" | "crates" | "zones" | "yard",
-- or "run" / "runauto" to launch): Studio
-- testing and the debug menu's OPEN buttons
do
	workspace:GetAttributeChangedSignal("DebugPanel"):Connect(function()
		local v = workspace:GetAttribute("DebugPanel")
		local ok, err = pcall(function()
			if v == "plot" then togglePanel(plot2)
			elseif v == "tyres" then togglePanel(tyres2)
			elseif v == "crates" then togglePanel(crates2)
			elseif v == "bench" then togglePanel(bench)
			elseif v == "events" then togglePanel(eventsPanel)
			elseif v == "settings" then togglePanel(settings2)
			elseif v == "zones" then togglePanel(zoneMap)
			elseif v == "shop" then togglePanel(shopPanel)
			elseif v == "yard" and plot2.onEditYard then plot2.onEditYard()
			elseif v == "run" then task.spawn(startRun)
			elseif v == "runauto" then task.spawn(startRun, nil, true)
			elseif v == "tutorial" and tutorial then tutorial:restart()
			elseif v == "scene:exit" and _G.TC_Scene then
				-- (Studio: play the loading scene's exit)
				task.spawn(function() _G.TC_Scene:exit() end)
			elseif type(v) == "string" and string.sub(v, 1, 6) == "scene:" then
				-- (Studio: the loading scene somewhere along the road, UI hidden, for shooting the zone
				-- pictures; "scene:<zone id>" a little way into that zone, "scene:off" to end it)
				if _G.TC_Scene then pcall(function() _G.TC_Scene:destroy() end) _G.TC_Scene = nil end
				local zid = string.sub(v, 7)
				local z = Game.ZonesById[zid]
				gui.Enabled = z == nil
				if z then
					local LoadScene = require(script.Parent.LoadScene)
					local s = LoadScene.new(playerGui, (z.start + 350) / Game.StudsToMetres)
					if s.gui then s.gui.Enabled = false end
					s:start()
					_G.TC_Scene = s
				else
					setHubZoom()
				end
			elseif v == "tour" and tutorial then
				-- (the yard tour from the start: the pref cleared, the editor opened)
				require(script.Parent.Prefs).set("yardTour", false, true)
				tutorial.tour = nil
				if plot2.onEditYard then plot2.onEditYard() end
			elseif v == nil or v == "" then closePanels() end
		end)
		print("[DebugPanel]", v, ok, err)
	end)
end

-- the plot upgrade is a scene: the camera swings in, the old stage drops away and the new one is
-- built up out of the ground (StageUp / PlotStage)
local stageUp = StageUp.new(gui, plotStage, {
	hideHub = function()
		state = "stageup"
		setHubMode(false)
	end,
	showHub = function()
		state = "hub"
		setHubMode(true)
	end,
	restoreCamera = restoreCamera,
})
plot2.upgradeScene = function(startServer)
	if state ~= "hub" or not myPlot then return end
	task.spawn(function()
		local ok, res = stageUp:play(myPlot, startServer)
		if not ok and type(res) == "table" and res.err then
			Kit.callout(gui, string.upper(res.err), T.bad or Color3.fromRGB(214, 52, 48), UDim2.fromScale(0.5, 0.2), 32)
		end
	end)
end

-- moving the machines round your yard: the hub steps aside while you do
local yardEdit = YardEdit.new(gui, V2, plot2)
-- (the tutorial's yard tour points at the editor's buttons)
if tutorial then tutorial.yardEdit = yardEdit end
-- Settings > Help > Replay Tutorial: from the first launch
help.onReplay = function()
	if tutorial then tutorial:replay() end
end

-- the newer systems explained the first time each comes up (Tips), once the tutorial's behind you
local tips = Tips.new(gui, track)
task.spawn(function()
	while true do
		task.wait(0.5)
		local p = profile
		local v = p and p.v2
		local inTutorial = tutorial ~= nil and (tutorial.active or tutorial.list ~= nil)
		if v and p.tutorial and not inTutorial and not tips:busy() then
			local idle = tutorial ~= nil and tutorial.ctx.idle() and state == "hub"
			if perkPick:isOpen() then
				tips:want("perks")
			elseif yardEdit:isOpen() and Prefs.get("yardTour") == true then
				tips:want("style")
			elseif plot2:isOpen() and v.trial and not v.trial.done then
				tips:want("trial")
			elseif idle and v.quests and v.quests.list and #v.quests.list > 0 and (v.runs or 0) >= 3 then
				tips:want("jobs")
			elseif idle and #Players:GetPlayers() > 1 and (v.runs or 0) >= 5 then
				tips:want("likes")
			end
		end
	end
end)
plot2.onEditYard = function()
	if state ~= "hub" or not myPlot then return end
	plot2:close()
	state = "yard"
	setHubMode(false)
	task.delay(0.2, function()
		if not myPlot then
			state = "hub"
			setHubMode(true)
			return
		end
		yardEdit:open(myPlot, function()
			state = "hub"
			setHubMode(true)
		end)
	end)
end

--==============================================================
-- every entry point funnels through here
--==============================================================
local function handleAction(action: string, plotIndex: number?)
	if state ~= "hub" then return end
	if action == "Claim" then
		if not plotIndex then return end
		local res = Remotes.ClaimPlot:InvokeServer(plotIndex)
		if res and res.ok then
			hub:toast(("YARD %d IS YOURS"):format(res.plot), T.good)
		else
			hub:toast((res and res.err) or "Couldn't claim that yard.", T.bad)
		end
		return
	end
	if action == "Launch" then
		startRun(profile and profile.selected or "backroad")
	elseif action == "Workbench" then
		togglePanel(bench)
	elseif action == "Settings" then
		togglePanel(settings2)
	elseif action == "Shop" then
		togglePanel(shopPanel)
	else
		local panel = PANEL_FOR[action]
		if panel then
			if hub:isOpen(panel) then hub:closeAll() else hub:open(panel) end
		end
	end
end

hub.onAction = handleAction
hub.onLaunch = nil

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	local action = prompt:GetAttribute("TCAction")
	if type(action) ~= "string" then return end
	local idx = prompt:GetAttribute("PlotIndex")
	-- everything on a yard is its owner's
	if idx and action ~= "Claim" then
		if not myPlot or myPlot:GetAttribute("Index") ~= idx then
			hub:toast("That's someone else's yard.", T.bad)
			return
		end
	end
	handleAction(action, idx)
end)

--==============================================================
-- notifications
--==============================================================
Remotes.Notify.OnClientEvent:Connect(function(d)
	if type(d) == "table" and d.kind == "toast" then
		hub:toast(d.text or "", d.bad and T.bad or T.good)
	elseif type(d) == "table" and d.kind == "gift" then
		hub:toast(("%s SENT YOU %s. IT'S ON YOUR WORKBENCH."):format(string.upper(tostring(d.from)), string.upper(tostring(d.item))), T.gold)
	end
end)
Remotes.SpectatorCount.OnClientEvent:Connect(function(n)
	if type(n) == "number" then
		hud:setWatchers(n)
		-- the run streams itself only while someone's watching
		RunSim.watchers = n
	end
end)

--==============================================================
-- plots
--==============================================================
local plotsReady = false

local function onPlots(snapshot)
	if snapshot then lastSnapshot = snapshot end
	snapshot = lastSnapshot
	if not (snapshot and plotsReady) then return end
	if signs then signs:apply(snapshot) end
	if wheels then wheels:apply(snapshot) end
	local lobby = workspace:FindFirstChild("Lobby")
	local plots = lobby and lobby:FindFirstChild("Plots")
	if not plots then return end
	local before = myPlot
	myPlot = nil
	for i, info in pairs(snapshot) do
		if type(info) == "table" and info.userId == player.UserId then
			myPlot = plots:FindFirstChild("Plot" .. i)
		end
	end
	if myPlot ~= before then plot2:attach(myPlot) end
	for _, plot in ipairs(plots:GetChildren()) do
		local pad = plot:FindFirstChild("ClaimPad") :: BasePart?
		if pad then
			-- (plots are claimed on joining: the old claim pad never shows)
			pad.Transparency = 1
			pad.CanCollide = false
			for _, d in ipairs(pad:GetDescendants()) do
				if d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Light") then
					(d :: any).Enabled = false
				elseif d:IsA("BasePart") or d:IsA("Decal") then
					(d :: any).Transparency = 1
				end
			end
			local pr = pad:FindFirstChildWhichIsA("ProximityPrompt", true)
			if pr then pr.Enabled = false end
		end
	end
end
Remotes.PlotsUpdated.OnClientEvent:Connect(onPlots)

task.spawn(function()
	local plots = PlotSigns.waitForPlots(8, 30)
	-- (2026-10-23) the claim pads go the moment the yards are there, not on the first plot update
	if plots then
		for _, plot in ipairs(plots:GetChildren()) do
			local pad = plot:FindFirstChild("ClaimPad") :: BasePart?
			if pad then
				pad.Transparency = 1
				pad.CanCollide = false
				for _, d in ipairs(pad:GetDescendants()) do
					if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Light") then
						(d :: any).Enabled = false
					elseif d:IsA("BasePart") or d:IsA("Decal") then
						(d :: any).Transparency = 1
					end
				end
			end
		end
	end
	signs = PlotSigns.new(function(userId, name) startSpectating(userId, name) end)
	signs.onView = function(_index: number, info)
		if state ~= "hub" then return end
		closePanels(wheelView)
		wheelView:open(info)
	end
	-- v4: VISIT walks you to the yard's gate (its street side, facing in); LIKE likes it
	signs.onVisit = function(plot: Instance)
		if state ~= "hub" or not plot then return end
		local base = plot:GetAttribute("BaseCFrame") :: CFrame?
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (base and hrp) then return end
		closePanels()
		local gate = base * CFrame.new(Game.Yard.Floor.x0 + 6, 5, 0) * CFrame.Angles(0, -math.pi / 2, 0)
		hrp.CFrame = gate
		hrp.AssemblyLinearVelocity = Vector3.zero
		Kit.callout(gui, ("%s'S YARD"):format(string.upper(tostring(plot:GetAttribute("V2_Owner") or "THEIR"))), Color3.fromRGB(48, 178, 184), UDim2.fromScale(0.5, 0.2), 34)
	end
	signs.onLike = function(userId: number): boolean
		local ok, res = pcall(function() return V2.Like:InvokeServer(userId) end)
		if ok and type(res) == "table" and res.ok then
			Kit.callout(gui, "YARD LIKED", Color3.fromRGB(255, 70, 110), UDim2.fromScale(0.5, 0.2), 34)
			Sound.play("medal", { volume = 0.5, pitch = 1.4 })
			return true
		end
		local err = ok and type(res) == "table" and res.err or "Couldn't like that yard"
		Kit.callout(gui, string.upper(err), Color3.fromRGB(214, 52, 48), UDim2.fromScale(0.5, 0.2), 28)
		return false
	end
	if plots then
		-- no launch lever: the run starts from the hub
		for _, plot in ipairs(plots:GetChildren()) do
			for _, d in ipairs(plot:GetDescendants()) do
				if d.Name == "Lever" and (d:IsA("Model") or d:IsA("BasePart")) then d:Destroy() end
			end
		end
		wheels = PlotWheels.new(plots)
		for _, plot in ipairs(plots:GetChildren()) do
			local op = plot:FindFirstChild("Operator")
			if op then AnimController.idleNPC(op) end
		end
	end
	local statue = workspace:FindFirstChild("Lobby") and workspace.Lobby.Plaza:FindFirstChild("Statue")
	if statue then AnimController.idleNPC(statue) end
	plotsReady = true
	onPlots(nil)
end)

--==============================================================
-- the lobby is walked, so what's built in it is solid (trees by their trunk, foliage stays soft)
--==============================================================
task.spawn(function()
	local lobby = workspace:WaitForChild("Lobby", 30)
	if not lobby then return end
	for _, name in ipairs({ "Dressing", "District" }) do
		local folder = lobby:WaitForChild(name, 20)
		if folder then Physical.watch(folder, { RingRoad = true }) end
	end
end)

--==============================================================
-- every rig idles over, spinning on its own axle
--==============================================================
task.spawn(function()
	local lobby = workspace:WaitForChild("Lobby", 30)
	local plots = lobby and lobby:WaitForChild("Plots", 20)
	if not plots then return end
	task.wait(2)
	local rigs = {}
	for _, plot in ipairs(plots:GetChildren()) do
		local rig = plot:FindFirstChild("LauncherRig")
		local fly = rig and rig:FindFirstChild("Flywheel") :: BasePart?
		if fly then
			local spokes = rig:FindFirstChild("Spokes")
			local sb = {}
			if spokes then
				for _, s in ipairs(spokes:GetChildren()) do
					if s:IsA("BasePart") then sb[s] = fly.CFrame:ToObjectSpace(s.CFrame) end
				end
			end
			table.insert(rigs, { fly = fly, base = fly.CFrame, spokes = sb, plot = plot })
		end
	end
	local a = 0
	RunService.RenderStepped:Connect(function(dt)
		if state ~= "hub" then return end
		a += dt * 1.4
		for _, r in ipairs(rigs) do
			if not (show and r.plot == myPlot) then
				-- idling: the flywheel turns with a little shudder in it
				local shudder = math.noise(a * 3.1, r.plot:GetAttribute("Index") or 0) * 0.035
				local spun = r.base * CFrame.new(0, shudder, 0) * CFrame.Angles(a + math.sin(a * 11) * 0.02, 0, 0)
				r.fly.CFrame = spun
				for s, rel in pairs(r.spokes) do s.CFrame = spun * rel end
			end
		end
	end)
end)

player.CharacterAdded:Connect(function()
	task.wait(0.4)
	if state == "hub" then
		setCharacterActive(true)
		if not playerGui:GetAttribute("IntroPlaying") then restoreCamera() end
	else
		setCharacterActive(false)
	end
end)

--==============================================================
-- build tag and debug console
--==============================================================
local debugMenu = DebugMenu.new(gui, {
	hub = hub,
	touch = touch,
	getSim = function() return sim end,
	getState = function() return state end,
	startRun = function(x: number, auto: boolean)
		startRun(profile and profile.selected or "backroad", auto, x)
	end,
	playTutorial = function() if tutorial then tutorial:restart() end end,
	setHubMode = setHubMode,
	showDaily = function() if hubX and profile and profile.v2 then hubX:showDaily(profile.v2) end end,
	reactToRun = reactToRun,
})
UI.buildTag(gui, function() debugMenu:toggle() end)

setHubMode(true)
setHubZoom()

-- the loading sweep flies over the yard: no menus or floating labels in the shot
task.spawn(function()
	if not playerGui:GetAttribute("IntroPlaying") then return end
	local hidden = {}
	local function hide(d: Instance)
		if d:IsA("BillboardGui") and d.Enabled and hidden[d] == nil then
			hidden[d] = true
			d.Enabled = false
		end
	end
	hub:setHubVisible(false)
	if hub2 then hub2:setVisible(false) end
	shiftLock:setAllowed(false)
	for _, d in ipairs(playerGui:GetDescendants()) do hide(d) end
	for _, d in ipairs(workspace:GetDescendants()) do hide(d) end
	local adds = {
		playerGui.DescendantAdded:Connect(hide),
		workspace.DescendantAdded:Connect(hide),
	}
	while playerGui:GetAttribute("IntroPlaying") do task.wait(0.1) end
	for _, c in ipairs(adds) do c:Disconnect() end
	for d in pairs(hidden) do
		if d.Parent then d.Enabled = true end
	end
	if state == "hub" then
		if hub2 then hub2:enter() end
		shiftLock:setAllowed(true)
	elseif signs then
		signs:setVisible(false)
	end
end)

-- the loading door in ReplicatedFirst lifts once this is set
task.spawn(function()
	local t0 = os.clock()
	while not profile and os.clock() - t0 < 20 do task.wait(0.1) end
	-- the menus and your yard load now, behind the loading screen, which shows how far along it is;
	-- the road, the tyres, the sounds and the rest of the hub follow once you're in
	pcall(function() lobbyVista:build() end)
	local t2 = os.clock()
	while not myPlot and os.clock() - t2 < 5 do task.wait(0.1) end
	local Preload: any = nil
	pcall(function()
		Preload = require(script.Parent:WaitForChild("Preload")) :: any
		playerGui:SetAttribute("LoadStages", #Preload.Stages)
		Preload.run(gui, function(index: number, name: string, k: number, n: number?, of: number?)
			playerGui:SetAttribute("LoadStage", index)
			playerGui:SetAttribute("LoadStageName", name)
			playerGui:SetAttribute("LoadStageK", k)
			playerGui:SetAttribute("LoadStageCount", if n and of and of > 0 then ("%d / %d"):format(n, of) else "")
		end, { plot = function() return myPlot end })
	end)
	-- and the interface itself: every image in every screen has actually arrived (the last stage
	-- holds at the end of the bar until they have, up to a limit)
	-- (only what's on screen: an image in a hidden menu loads when the menu opens, and Preload has
	-- already fetched those)
	local function shown(g: Instance): boolean
		-- (a card parked off the screen until it slides in, like the Heat notice, isn't drawn either)
		local screen = gui.AbsoluteSize
		local pos, size = (g :: any).AbsolutePosition, (g :: any).AbsoluteSize
		if pos.X + size.X <= 0 or pos.Y + size.Y <= 0 or pos.X >= screen.X or pos.Y >= screen.Y then return false end
		local o: Instance? = g
		while o and o ~= playerGui do
			if o:IsA("GuiObject") and not o.Visible then return false end
			if o:IsA("LayerCollector") and not o.Enabled then return false end
			-- (a sign over a yard is a billboard: it only counts as loaded once it's on camera, which it
			-- never is behind the loading screen; its images were fetched by id in Preload already)
			if o:IsA("LayerCollector") and not o:IsA("ScreenGui") then return false end
			o = o.Parent
		end
		return true
	end
	-- the hub is hidden for the intro and the Heat notice waits off the screen, and an image that
	-- isn't drawn never reports IsLoaded, so their art is fetched here by instance instead: it's all
	-- there the moment they come in
	do
		local hubArt = {}
		for _, d in ipairs(gui:GetDescendants()) do
			if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and (d :: any).Image ~= "" and (d:FindFirstAncestor("Hub2") or d:FindFirstAncestor("HubExtras")) then
				table.insert(hubArt, d)
			end
		end
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(hubArt) end)
	end
	local t1 = os.clock()
	-- (and gives up waiting once the count has stood still for three seconds: an image that never
	-- reports in would otherwise hold every join for the full limit)
	local lastCount, lastMove = math.huge, os.clock()
	playerGui:SetAttribute("LoadStageK", 0.95)    -- (the bar holds just short of the end meanwhile)
	while os.clock() - t1 < 15 and os.clock() - lastMove < 3 do
		local waiting = 0
		for _, d in ipairs(playerGui:GetDescendants()) do
			if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and (d :: any).Image ~= "" and not (d :: any).IsLoaded
				and d:FindFirstAncestor("TyreLoading") == nil and shown(d) then
				waiting += 1
			end
		end
		if waiting == 0 then break end
		if waiting < lastCount then lastCount, lastMove = waiting, os.clock() end
		playerGui:SetAttribute("LoadStageName", ("THE INTERFACE  ·  %d TO GO"):format(waiting))
		task.wait(0.2)
	end
	playerGui:SetAttribute("LoadStageK", 1)
	playerGui:SetAttribute("TyreReady", true)
	-- the rest loads now, road first, while you're already in
	if Preload then task.delay(1, function() pcall(Preload.background) end) end
	-- (no title: the loading plate drives its tyre off and the game is there)
end)
print("[TyreCannon] client ready · " .. Config.VersionLabel)
