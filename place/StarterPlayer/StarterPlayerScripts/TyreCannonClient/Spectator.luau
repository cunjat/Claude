--!strict
-- TYRE CANNON :: Spectator (v2, 2026-10-21: rebuilt on the bounce run)
-- Watching someone else's run the way they see it. While anyone's watching, the runner streams ten
-- frames a second (RunSim:stream): where the tyre is and how it's riding, what their HUD shows, the
-- stamps since the last frame, and what it takes to build the same road. Here the road is rebuilt
-- from that (seed, hills, skill zones, the run's keys and targets) under the run's own light, haze
-- and weather; their tyre rides it, played a beat behind and eased between frames; and the run's own
-- camera (RunCamera) chases it. On screen: the run's own HUD (HudUI: distance and the zone rail, the
-- zone, the chain, speed, nitro, their moves lighting up, the same stamps), and in the kit4 look a
-- WATCHING card top right (their face, name and title), LEAVE bottom left, and PREV / NEXT beside it
-- when more than one player is out on the road.
-- Backspace / B leave; Q / E (LB / RB) hop between runners; a run that goes quiet for five seconds
-- ends the watch; when the run ends, the next one out on the road is picked up (or you're home).
--   Spectator.new(gui) · :start(userId, name) -> ok · :stop() · .onStop · .lastError · .active

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Remotes = Root:WaitForChild("Remotes")
local Config = require(Modules.Config)
local Game = require(Modules:WaitForChild("Game"))
local TrackGen = require(Modules.TrackGen)
local RunCamera = require(Modules.RunCamera)
local WheelAssembly = require(Modules:WaitForChild("WheelAssembly"))
local WorldView = require(script.Parent.WorldView)
local TyreLook = require(script.Parent.TyreLook)
local PrestigeLook = require(script.Parent.PrestigeLook)
local Weather = require(script.Parent.Weather)
local VFX = require(script.Parent.VFX)
local HudUI = require(script.Parent.HudUI)
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local C = Kit.C

local P = Config.Physics
local M = P.StudsToMetres
local R = P.TyreRadius
local STALE = 5          -- seconds without a frame and the watch is over
local DELAY = 0.2        -- play a beat behind the newest frame, so there's always one to ease toward
local AHEAD = 0.25       -- past the newest frame, carry on along the heading for at most this long
local ITALIC = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local GOLD = Color3.fromRGB(255, 214, 72)
-- the road's reactions the runner streams (RunSim's STREAM_WORLD), replayed on our road
local WORLD_OPS = {
	targetHit = true, shatter = true, knock = true, padFX = true, markMetalCollected = true, markKeyCollected = true,
	markCollected = true, markToolCollected = true, gateFX = true,
}

local Spectator = {}
Spectator.__index = Spectator

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function num(v: any, default: number): number
	return if type(v) == "number" and v == v then v else default
end

-- a streamed { x, y, z } back into a Vector3 (anything else as it came)
local function vec(v: any): any
	if type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number" then
		return Vector3.new(v[1], v[2], v[3])
	end
	return v
end

local function anchorPart(parent: Instance, name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.one
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

function Spectator.new(gui: ScreenGui)
	local self = setmetatable({}, Spectator)
	self.gui = gui
	self.active = false
	self.onStop = nil
	self.runners = {} :: { { userId: number, name: string } }
	self.myId = Players.LocalPlayer.UserId
	self.session = 0 -- bumped by every stop: an answer from the server for an older session is undone

	-- the run's HUD, fed from the stream (its controls hint and key caps are the runner's, so hidden)
	local hud = HudUI.new(gui)
	self.hud = hud
	-- (a watcher can't press anything: no key caps on the move tiles, their names centred instead)
	for _, t in pairs(hud.moveTiles) do
		t.cap.Text = ""
		t.name.AnchorPoint = Vector2.new(0.5, 0.5)
		t.name.Position = UDim2.fromScale(0.5, 0.5)
	end

	local root = UI.mk("Frame", {
		Name = "Spectate", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui,
	})
	self.root = root

	-- tuning in: a dark sheet until the first frame lands
	local veil = UI.mk("Frame", {
		Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.night, BackgroundTransparency = 0.15, ZIndex = 30, Parent = root,
	})
	self.veil = veil
	self.veilText = Kit.text("TUNING IN...", 30, C.white, 2.5, ITALIC)
	self.veilText.AnchorPoint = Vector2.new(0.5, 0.5)
	self.veilText.Position = UDim2.fromScale(0.5, 0.5)
	self.veilText.Size = UDim2.fromOffset(700, 40)
	self.veilText.ZIndex = 31
	self.veilText.Parent = veil
	UI.autoScale(self.veilText)

	-- top right: WATCHING, their face, name and title, on a panel ringed green
	local tr = UI.mk("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -28, 0, 70), Size = UDim2.fromOffset(330, 96),
		BackgroundTransparency = 1, ZIndex = 32, Parent = root,
	})
	UI.autoScale(tr)
	self.cardHolder = tr
	local card = UI.mk("Frame", { Size = UDim2.fromOffset(330, 96), BackgroundTransparency = 1, ZIndex = 32, Parent = tr })
	Kit.slice("panel_body", nil, card, 32, 0.4)
	Kit.slice("panel_ring", C.green, card, 33, 0.4)
	self.card = card
	local face = UI.mk("ImageLabel", {
		Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(68, 68), BackgroundColor3 = C.well, Image = "",
		ZIndex = 34, Parent = card,
	}, { UI.corner(34) })
	UI.stroke(C.green, 2.5, 0).Parent = face
	self.face = face
	self.initial = Kit.text("", 34, C.white, 2.5, ITALIC)
	self.initial.Size = UDim2.fromScale(1, 1)
	self.initial.ZIndex = 35
	self.initial.Parent = face
	local live = Kit.text("WATCHING", 13, C.green, 1.5, Kit.Body)
	live.TextXAlignment = Enum.TextXAlignment.Left
	live.Position = UDim2.fromOffset(96, 12)
	live.Size = UDim2.fromOffset(220, 16)
	live.ZIndex = 35
	live.Parent = card
	-- the red dot: it breathes while frames are coming in
	local dot = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(176, 20), Size = UDim2.fromOffset(9, 9),
		BackgroundColor3 = C.red, BorderSizePixel = 0, ZIndex = 35, Parent = card,
	}, { UI.corner(5) })
	self.dot = dot
	self.nameLabel = Kit.text("", 26, C.white, 2.5, ITALIC)
	self.nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	self.nameLabel.Position = UDim2.fromOffset(96, 30)
	self.nameLabel.Size = UDim2.fromOffset(222, 32)
	Kit.fit(self.nameLabel, 26, 14)
	self.nameLabel.ZIndex = 35
	self.nameLabel.Parent = card
	self.title = UI.titleLabel(nil, 14)
	self.title.Position = UDim2.fromOffset(96, 64)
	self.title.Size = UDim2.fromOffset(222, 18)
	self.title.TextXAlignment = Enum.TextXAlignment.Left
	self.title.ZIndex = 35
	self.title.Parent = card

	-- beside LEAVE: hop to the others out on the road (the chain panel owns the right edge, so
	-- they live down here, bottom left, where the runner's controls hint would be)
	local nav = UI.mk("Frame", { Position = UDim2.fromOffset(196, 6), Size = UDim2.fromOffset(216, 72), BackgroundTransparency = 1, ZIndex = 32 })
	self.nav = nav
	local prev = Kit.button("Q  Prev", C.grey, UDim2.fromOffset(104, 40), 16)
	prev.root.Position = UDim2.fromOffset(0, 0)
	prev.root.ZIndex = 33
	prev.root.Parent = nav
	;(prev :: any).setDark(true)
	prev.onClick = function() self:hop(-1) end
	local nxt = Kit.button("Next  E", C.grey, UDim2.fromOffset(104, 40), 16)
	nxt.root.Position = UDim2.fromOffset(112, 0)
	nxt.root.ZIndex = 33
	nxt.root.Parent = nav
	;(nxt :: any).setDark(true)
	nxt.onClick = function() self:hop(1) end
	self.navCount = Kit.text("", 13, C.muted, 1.5, Kit.Body)
	self.navCount.Position = UDim2.fromOffset(0, 52)
	self.navCount.Size = UDim2.fromOffset(216, 16)
	self.navCount.ZIndex = 33
	self.navCount.Parent = nav

	-- bottom left: LEAVE, and its key
	local bl = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -24), Size = UDim2.fromOffset(420, 78),
		BackgroundTransparency = 1, ZIndex = 32, Parent = root,
	})
	UI.autoScale(bl)
	self.leaveHolder = bl
	nav.Parent = bl
	local leave = Kit.button("Leave", C.red, UDim2.fromOffset(180, 52), 24)
	leave.root.ZIndex = 33
	leave.root.Parent = bl
	leave.onClick = function() self:stop() end
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local key = Kit.text(if touchOnly then "" else "BACKSPACE", 12, C.muted, 1.5, Kit.Body)
	key.Position = UDim2.fromOffset(0, 58)
	key.Size = UDim2.fromOffset(180, 16)
	key.ZIndex = 33
	key.Parent = bl

	self.inputConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if not self.active or gpe then return end
		local k = input.KeyCode
		if k == Enum.KeyCode.Backspace or k == Enum.KeyCode.ButtonB then
			self:stop()
		elseif k == Enum.KeyCode.Q or k == Enum.KeyCode.ButtonL1 then
			self:hop(-1)
		elseif k == Enum.KeyCode.E or k == Enum.KeyCode.ButtonR1 then
			self:hop(1)
		end
	end)

	Remotes.RunState.OnClientEvent:Connect(function(fromUserId, payload)
		self:onState(fromUserId, payload)
	end)
	-- who's out on the road, from the yards' broadcast (for PREV / NEXT and picking up the next run)
	Remotes.PlotsUpdated.OnClientEvent:Connect(function(plots)
		self:onPlots(plots)
	end)

	return self
end

--==============================================================
-- who's out on the road
--==============================================================
function Spectator:onPlots(plots: any)
	if type(plots) ~= "table" then return end
	local list = {}
	for i = 1, #plots do
		local info = plots[i]
		if type(info) == "table" and info.status == "attempt" and type(info.userId) == "number" and info.userId ~= self.myId then
			table.insert(list, { userId = info.userId, name = tostring(info.name or "?") })
		end
	end
	self.runners = list
	self:paintNav()
end

function Spectator:paintNav()
	local n = #self.runners
	local here = 0
	for i, r in ipairs(self.runners) do
		if r.userId == self.target then here = i end
	end
	local others = n - (if here > 0 then 1 else 0)
	self.nav.Visible = others > 0
	self.navCount.Text = if here > 0 then ("%d OF %d ON THE ROAD"):format(here, n) else ("%d ON THE ROAD"):format(n)
end

-- the next (dir 1) or previous (-1) runner after the one you're watching
function Spectator:pick(dir: number): { userId: number, name: string }?
	local n = #self.runners
	if n == 0 then return nil end
	local here = 0
	for i, r in ipairs(self.runners) do
		if r.userId == self.target then here = i end
	end
	for step = 1, n do
		local i = ((here - 1 + dir * step) % n) + 1
		local r = self.runners[i]
		if r and r.userId ~= self.target then return r end
	end
	return nil
end

function Spectator:hop(dir: number)
	if not self.active or self.hopping then return end
	if os.clock() - (self.hopAt or 0) < 0.35 then return end
	local r = self:pick(dir)
	if not r then return end
	self.hopping = true
	self.hopAt = os.clock()
	local ok = self:watch(r.userId, r.name)
	self.hopping = false
	if not ok and self.lastError and self.active then self:flashNav(self.lastError) end
end

-- a short red word where the count sits (why a hop didn't happen)
function Spectator:flashNav(text: string)
	self.navCount.Text = string.upper(text)
	self.navCount.TextColor3 = C.red
	local at = os.clock()
	self.navFlash = at
	task.delay(2, function()
		if self.navFlash ~= at then return end
		self.navCount.TextColor3 = C.muted
		self:paintNav()
	end)
end

--==============================================================
-- start, hop, stop
--==============================================================
-- ask the server to watch someone; on yes, everything about the last one is dropped and the card
-- turns to the new one (the camera and the screen stay up)
function Spectator:watch(userId: number, name: string?): boolean
	local session = self.session
	local ok, res = pcall(function() return Remotes.Spectate:InvokeServer(userId) end)
	if self.session ~= session then
		-- left while the server was answering: undo what it just did
		-- (only if that watch is still the one the server holds: a newer one must survive this)
		if ok and type(res) == "table" and res.ok then
			task.spawn(function() pcall(function() Remotes.Spectate:InvokeServer(nil, userId) end) end)
		end
		return false
	end
	if not ok or type(res) ~= "table" or not res.ok then
		self.lastError = (type(res) == "table" and res.err) or "Couldn't watch that run."
		return false
	end
	self:clearRun()
	self.target = userId
	self.lastPacket = os.clock()
	local shown = string.upper(res.name or name or "?")
	self.nameLabel.Text = shown
	local pl = Players:GetPlayerByUserId(userId)
	local titleId = pl and pl:GetAttribute("Title")
	UI.applyTitle(self.title, (type(titleId) == "string" and titleId ~= "") and titleId or nil)
	self.face.Image = ""
	self.initial.Text = string.sub(shown, 1, 1)
	self.initial.Visible = true
	if userId > 0 then
		task.spawn(function()
			local okT, img = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if okT and self.target == userId then
				self.face.Image = img
				self.initial.Visible = false
			end
		end)
	end
	self.veil.Visible = true
	self.veil.BackgroundTransparency = 0.15
	self.veilText.TextTransparency = 0
	local st = self.veilText:FindFirstChildOfClass("UIStroke")
	if st then st.Transparency = 0.05 end
	self.veilText.Text = ("TUNING IN TO %s..."):format(shown)
	self.hud:hide()
	Kit.pop(self.card, 0.85, 0.2)
	self:paintNav()
	return true
end

function Spectator:start(userId: number, name: string?): boolean
	if self.active then self:stop() end
	self.camera = workspace.CurrentCamera
	if not self:watch(userId, name) then return false end

	self.active = true
	self.root.Visible = true
	self.savedCamType = self.camera.CameraType
	self.savedFov = self.camera.FieldOfView
	self.camera.CameraType = Enum.CameraType.Scriptable
	-- (just after the default camera, so the camera and its Focus are ours each frame)
	RunService:BindToRenderStep("TCSpectate", Enum.RenderPriority.Camera.Value + 1, function(dt) self:frame(dt) end)
	self.bound = true
	return true
end

-- the run's light and haze, as RunSim sets them at its start (and back again)
function Spectator:light(cfg: any, startX: number)
	if not self.savedLighting then
		self.savedLighting = {
			ClockTime = Lighting.ClockTime, FogColor = Lighting.FogColor, FogEnd = Lighting.FogEnd,
			FogStart = Lighting.FogStart, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
		}
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm then
			self.savedAtmosphere = { inst = atm, Density = atm.Density, Offset = atm.Offset, Color = atm.Color, Decay = atm.Decay, Glare = atm.Glare, Haze = atm.Haze }
		end
	end
	if cfg.clockTime then Lighting.ClockTime = cfg.clockTime end
	if cfg.fog then Lighting.FogColor = cfg.fog end
	if cfg.fogEnd then
		Lighting.FogEnd = cfg.fogEnd
		Lighting.FogStart = cfg.fogEnd * 0.35
	end
	if cfg.ambient then
		Lighting.Ambient = cfg.ambient
		Lighting.OutdoorAmbient = cfg.ambient
	end
	local a = self.savedAtmosphere
	if a and a.inst.Parent then
		local okB, band = pcall(function() return Config.BandFor(cfg, Config.TierAt(startX)) end)
		if okB and band and band.fog then
			a.inst.Density = 0.2
			a.inst.Offset = 0
			a.inst.Color = band.fog
			a.inst.Decay = band.fog:Lerp(Color3.fromRGB(96, 112, 138), 0.35)
			a.inst.Glare = 0.15
			a.inst.Haze = 0.5
		end
	end
end

function Spectator:unlight()
	for k, v in pairs(self.savedLighting or {}) do
		(Lighting :: any)[k] = v
	end
	local a = self.savedAtmosphere
	if a and a.inst.Parent then
		for k, v in pairs(a) do
			if k ~= "inst" then (a.inst :: any)[k] = v end
		end
	end
	self.savedLighting = nil
	self.savedAtmosphere = nil
end

-- everything belonging to the run being watched (not the screen)
function Spectator:clearRun()
	if self.weather then pcall(function() self.weather:stop() end); self.weather = nil end
	if self.world then self.world:destroy(); self.world = nil end
	if self.folder then self.folder:Destroy(); self.folder = nil end
	-- (the road object is shared: the next run of our own sets its own seed, hills, keys and zones)
	if self.track then
		pcall(function() self.track:setSkillKind(nil) end)
		self.track.keyAllow = nil
		self.track.targetRate = 1
	end
	self.glow = nil
	self.model = nil
	self.track = nil
	self.trackId = nil
	self.seed = nil
	self.frames = {}
	self.offset = nil
	self.latest = nil
	self.cam = nil
	self.design = nil
	self.dressed = nil
	self.over = false
	self.hud:hide()
end

function Spectator:stop()
	if not self.active then return end
	self.active = false
	self.session += 1
	if self.bound then
		RunService:UnbindFromRenderStep("TCSpectate")
		self.bound = false
	end
	self:clearRun()
	self:unlight()
	self.target = nil
	self.root.Visible = false
	if self.camera then
		self.camera.CameraType = self.savedCamType or Enum.CameraType.Custom
		self.camera.FieldOfView = self.savedFov or 70
	end
	-- the server last: it's a round trip, and nothing on screen should wait for it
	task.spawn(function() pcall(function() Remotes.Spectate:InvokeServer(nil) end) end)
	if self.onStop then task.spawn(self.onStop) end
end

--==============================================================
-- the road and the tyre
--==============================================================
function Spectator:buildWorld(p: any)
	self:clearRun()
	local trackId, seed = p.t, tonumber(p.sd) :: number
	local track = TrackGen.get(trackId)
	track:setRun(seed, 0, 0)
	track.hillScale = num(p.hs, track.hillScale or 1)
	track.keyAllow = if type(p.ka) == "table" then p.ka else nil
	track.targetRate = num(p.tg, 1)
	pcall(function() track:setSkillKind(if type(p.kk) == "string" then p.kk else nil) end)
	self.track = track
	self.trackId = trackId
	self.seed = seed
	self.terrain = {
		heightAt = function(x: number) return track:heightAt(x) end,
		slopeAt = function(x: number) return track:slopeAt(x) end,
	}
	local startX = math.max(0, num(p.sx, 0))
	self.world = WorldView.new(trackId)
	local best = num(p.bx, 0)
	if best > 0 then pcall(function() self.world:markBest(best, self.nameLabel.Text) end) end
	self.world:ensure(num(p.x, startX))
	self:light(track:cfgAt(0), startX)

	local folder = Instance.new("Folder")
	folder.Name = "TyreCannonSpectate"
	folder.Parent = workspace
	self.folder = folder
	pcall(function() self.weather = Weather.start(trackId, folder) end)

	-- the boost flame rides an unrotated anchor behind the hub, as the runner's does
	self.fxAnchor = anchorPart(folder, "FXAnchor")
	self.flame = VFX.attach("BoostFlame", self.fxAnchor, CFrame.new(-R * 0.9, -R * 0.35, 0) * CFrame.Angles(0, 0, math.rad(90)), 0.3)
	-- the landing disc under the tyre while it's in the air
	local shadow = anchorPart(folder, "AirShadow")
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Size = Vector3.new(0.12, R * 2, R * 2)
	self.airShadow = shadow

	-- the HUD: the zone they started in and their best, the runner's own hints and keys hidden
	local zone1 = Game.Zones[Game.zoneAt(startX * M)] or Game.Zones[1]
	self.hud:setTrack({ name = zone1.name, creditMult = zone1.rate }, best)
	self.hud.hint.Visible = false
	self.hud.nitroKey.Text = ""
	for _, t in pairs(self.hud.moveTiles) do t.cap.Text = "" end
	self.hud:show()
	-- the veil lifts
	local veil = self.veil
	Kit.tween(veil, 0.35, { BackgroundTransparency = 1 })
	Kit.tween(self.veilText, 0.25, { TextTransparency = 1 })
	local st = self.veilText:FindFirstChildOfClass("UIStroke")
	if st then Kit.tween(st, 0.25, { Transparency = 1 }) end
	task.delay(0.36, function()
		if veil.BackgroundTransparency > 0.99 then veil.Visible = false end
	end)
	-- the tyre last: a design that won't build mustn't leave the watcher behind the veil
	local okT, err = pcall(function() self:dressTyre(p) end)
	if not okT then warn("[Spectator] tyre:", err) end
end

-- their tyre: its model in its design (the design comes every 20th frame), or the stock wheel in
-- their skin and rim; rebuilt once if the design turns up after the first frame
function Spectator:dressTyre(p: any)
	if type(p.ds) == "table" then self.design = p.ds end
	local want = if self.design then "design" else "plain"
	if self.dressed == want or not self.folder then return end
	local tyreId = if type(p.ty) == "string" then p.ty else nil
	-- (their tyre in its design if it builds; the stock wheel in their skin and rim if not; the old
	-- model goes only once the new one exists)
	local okM, built = pcall(function()
		if tyreId and TyreLook.has(tyreId) then return TyreLook.model(tyreId, R * 2, "WatchedTyre", self.design) end
		return nil
	end)
	local m: Model = if okM and built then built
		else WheelAssembly.build(self.folder, { diameter = R * 2, skin = p.sk or "stock", rim = p.rm or "steel", name = "WatchedTyre" })
	if self.model then self.model:Destroy() end
	pcall(function() PrestigeLook.dressTyre(m, tonumber(p.pr) or 0) end)
	m.Name = "WatchedTyre"
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	m.Parent = self.folder
	self.model = m
	self.dressed = want
	-- the tuck cue shows on the tyre as on theirs: gold when a tuck now pays, teal while tucked
	if self.glow then self.glow:Destroy() end
	local glow = Instance.new("Highlight")
	glow.Name = "TuckGlow"
	glow.Adornee = m
	glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	glow.FillTransparency = 1
	glow.OutlineTransparency = 1
	glow.Enabled = false
	glow.Parent = self.folder
	self.glow = glow
end

--==============================================================
-- the stream
--==============================================================
function Spectator:onState(fromUserId: number, p: any)
	if not self.active or fromUserId ~= self.target or type(p) ~= "table" then return end
	self.lastPacket = os.clock()
	if p.done then
		local last = self.frames[#self.frames]
		self:runOver(num(p.d, if last then last.x else 0))
		return
	end
	local trackId = p.t
	local seed = tonumber(p.sd)
	if type(trackId) ~= "string" or not Config.TracksById[trackId] and trackId ~= "road" or not seed then return end
	if self.trackId ~= trackId or self.seed ~= seed then
		self:buildWorld(p)
	elseif p.ds ~= nil and not self.design then
		self:dressTyre(p)
	end
	self.over = false

	-- each frame is placed on our clock by when it was sent (the runner's clock plus the smallest
	-- delay seen, which creeps up slowly if the clocks drift), not when it arrived: frames arrive in
	-- clumps, and spacing them by arrival made the tyre surge and stall
	local now = os.clock()
	local sent = num(p.ck, now)
	local lag = now - sent
	if not self.offset or lag < self.offset then
		self.offset = lag
	else
		self.offset += (lag - self.offset) * 0.01
	end
	local prev = self.frames[#self.frames]
	local at = sent + self.offset
	if prev then at = math.max(at, prev.at + 0.01) end
	local f = {
		at = at,
		x = num(p.x, 0), y = num(p.y, 0), z = num(p.z, 0), roll = num(p.roll, 0),
		yaw = num(p.yw, 0), pitch = num(p.pt, 0), bank = num(p.bk, 0), speed = num(p.sp, 0),
	}
	table.insert(self.frames, f)
	while #self.frames > 24 do table.remove(self.frames, 1) end
	self.latest = p

	-- the stamps since the last frame, on our HUD as on theirs, a beat later (with the tyre); the
	-- runner's coaching ("tuck to brace") left off, a watcher can't act on it
	local world = self.world
	if type(p.ev) == "table" then
		for _, e in ipairs(p.ev) do
			if type(e) == "table" and type(e.kind) == "string" and (e.kind ~= "skill" or type(e.name) == "string") then
				e.chain = num(e.chain, 0)
				e.combo = num(e.combo, 1)
				task.delay(DELAY, function()
					if self.world ~= world or not world then return end
					if e.kind == "rough" then
						self.hud:toast("ROUGH LANDING", C.muted, 22)
					elseif e.kind == "bump" then
						if not e.tucked then self.hud:toast("SPEED BUMP", C.muted, 22) end
					else
						pcall(function() self.hud:event(e) end)
					end
				end)
			end
		end
	end
	-- and the road reacting: coins and keys taken, targets hit, things smashed, pads, gates
	if type(p.wo) == "table" then
		for _, w in ipairs(p.wo) do
			if type(w) == "table" and WORLD_OPS[w.op] then
				local a, b = vec(w.a), vec(w.b)
				task.delay(DELAY, function()
					if self.world ~= world or not world then return end
					pcall(function() (world :: any)[w.op](world, a, b) end)
				end)
			end
		end
	end
end

function Spectator:runOver(x: number)
	if self.over then return end
	self.over = true
	local metres = UI.comma(math.floor(x * M))
	if self.world then
		self.hud:stamp("RUN OVER", C.accent, 46, -3, ("%s M"):format(metres))
	else
		-- (it ended while we were still tuning in)
		self.veilText.Text = ("RUN OVER  ·  %s M"):format(metres)
	end
	local was = self.target
	task.delay(2.6, function()
		if not self.active or self.target ~= was or not self.over or self.hopping then return end
		-- the next one out on the road, or home
		local r = self:pick(1)
		if r then
			self.hopping = true
			local ok = self:watch(r.userId, r.name)
			self.hopping = false
			if ok then return end
		end
		if self.active and self.target == was then self:stop() end
	end)
end

-- where the tyre is now: a beat behind the newest frame, eased between the two either side
function Spectator:sample(): any?
	local fr = self.frames
	local n = #fr
	if n == 0 then return nil end
	local t = os.clock() - DELAY
	if t <= fr[1].at then return fr[1] end
	for i = n - 1, 1, -1 do
		local a, b = fr[i], fr[i + 1]
		if t >= a.at then
			if t > b.at then break end
			local k = (t - a.at) / math.max(1e-3, b.at - a.at)
			return {
				x = lerp(a.x, b.x, k), y = lerp(a.y, b.y, k), z = lerp(a.z, b.z, k), roll = lerp(a.roll, b.roll, k),
				yaw = lerp(a.yaw, b.yaw, k), pitch = lerp(a.pitch, b.pitch, k), bank = lerp(a.bank, b.bank, k),
				speed = lerp(a.speed, b.speed, k),
			}
		end
	end
	-- past the newest: carry on along its heading for a moment, then hold
	local last = fr[n]
	local ahead = math.clamp(t - last.at, 0, AHEAD)
	local h = last.speed * ahead
	return {
		x = last.x + math.cos(last.pitch) * math.cos(last.yaw) * h,
		y = last.y + math.sin(last.pitch) * h,
		z = last.z + math.cos(last.pitch) * math.sin(last.yaw) * h,
		roll = last.roll + h / R, yaw = last.yaw, pitch = last.pitch, bank = last.bank, speed = last.speed,
	}
end

function Spectator:frame(dt: number)
	if not self.active then return end
	if os.clock() - (self.lastPacket or 0) > STALE then
		self:stop()
		return
	end
	-- the live dot breathes while frames come in, and dims when they stop
	local fresh = os.clock() - (self.lastPacket or 0) < 0.5
	self.dot.BackgroundTransparency = if fresh then 0.15 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 5)) else 0.75
	local s = self:sample()
	local p = self.latest
	if not (s and p and self.world and self.model and self.track) then return end

	local pos = Vector3.new(s.x, s.y, s.z)
	local ground = self.track:heightAt(s.x)
	local alt = math.max(0, s.y - ground - R)
	local grounded = p.g == true
	self.world:ensure(s.x, 1)
	self.world:update(dt, s.x)
	self.model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, -s.yaw, 0) * CFrame.Angles(s.bank * 0.4, 0, 0) * CFrame.Angles(0, 0, -s.roll))
	self.fxAnchor.CFrame = CFrame.new(pos) * CFrame.Angles(0, -s.yaw, 0) * CFrame.Angles(0, 0, s.pitch)
	if self.flame then self.flame.set(p.nb == true, 1.0) end
	local glow = self.glow
	if glow then
		local cue = p.cu
		local col, fill, line = GOLD, 1, 1
		if cue == "perfect" or cue == "land" then
			col, fill, line = GOLD, 0.45 + 0.25 * (0.5 + 0.5 * math.sin(os.clock() * 13)), 0
		elseif cue == "soon" then
			col, fill, line = GOLD, 0.92, 0.5
		elseif p.tk == true or cue == "tucked" or cue == "braced" then
			col, fill, line = C.teal, 0.7, 0.15
		end
		local on = fill < 0.98 or line < 0.98
		glow.Enabled = on
		if on then
			glow.FillColor, glow.OutlineColor = col, col
			glow.FillTransparency, glow.OutlineTransparency = fill, line
		end
	end
	if not grounded and alt > 3 then
		local k = math.clamp(alt / 320, 0, 1)
		local d = R * 2 * (1 - k * 0.35)
		self.airShadow.Size = Vector3.new(0.12, d, d)
		self.airShadow.Transparency = 0.45 + k * 0.3
		self.airShadow.CFrame = CFrame.new(s.x, ground + 0.2, s.z) * CFrame.Angles(0, 0, math.atan(self.track:slopeAt(s.x))) * CFrame.Angles(0, 0, math.rad(90))
	else
		self.airShadow.Transparency = 1
	end

	-- the run's own camera, from the same numbers the runner's is
	local cs = self.cam
	if not cs then
		cs = RunCamera.new()
		self.cam = cs
	end
	local co = RunCamera.step(cs, {
		x = s.x, y = s.y, z = s.z, yaw = s.yaw, pitch = s.pitch, speed = s.speed,
		grounded = grounded, alt = alt, bank = s.bank, boosting = p.nb == true, first = false, radius = R,
	}, self.terrain, Config.Camera, dt)
	local camCF = CFrame.lookAt(Vector3.new(co.ex, co.ey, co.ez), Vector3.new(co.lx, co.ly, co.lz)) * CFrame.Angles(0, 0, co.roll)
	self.camera.CFrame = camCF
	-- (the engine draws detail round Camera.Focus: far down the road it must sit on the tyre, or the
	-- world stops drawing there)
	self.camera.Focus = CFrame.new(pos)
	self.camera.FieldOfView += (co.fov - self.camera.FieldOfView) * math.min(1, dt * 6)
	if self.weather then pcall(function() self.weather:update(pos, camCF.Position) end) end

	-- their HUD, from the newest frame (the distance and speed from the eased pose)
	self.hud:update({
		metres = math.floor(s.x * M), distance = s.x, zone = self.track:zoneIndex(math.max(0, s.x)),
		chain = num(p.ch, 0), combo = num(p.cm, 1), speed = s.speed,
		tucking = p.tk == true, tuckCool = false, floating = p.fl == true, diving = p.dv == true,
		nitroFrac = num(p.nf, 0), nitroDry = p.nd == true, nitroOn = p.nb == true,
		altitude = alt, metals = if type(p.mt) == "table" then p.mt else {}, stopping = false, runTime = num(p.rt, 0),
	})
end

return Spectator
