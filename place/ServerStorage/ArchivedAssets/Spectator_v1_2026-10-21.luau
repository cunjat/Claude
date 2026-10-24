--!strict
-- TYRE CANNON :: Spectator
-- Watching someone else's attempt. While anyone's watching, the runner streams its pose ten times a
-- second with what it takes to build the same road (RunSim:stream): the seed, the hill scale its
-- stage gives the road, its skill zones' kind, and its tyre, skin and rim. The road is rebuilt here
-- from those, the runner's own tyre rides it, and the camera chases it. In the kit's look: a card
-- at the top (WATCHING, their name and title, how far and how fast), LEAVE at the bottom.
-- Backspace / Esc / B leave too; a run that goes quiet for five seconds ends the watch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Remotes = Root:WaitForChild("Remotes")
local Config = require(Modules.Config)
local TrackGen = require(Modules.TrackGen)
local WheelAssembly = require(Modules:WaitForChild("WheelAssembly"))
local WorldView = require(script.Parent.WorldView)
local TyreLook = require(script.Parent.TyreLook)
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local C = Kit.C

local P = Config.Physics
local STALE = 5

local Spectator = {}
Spectator.__index = Spectator

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Spectator.new(gui: ScreenGui)
	local self = setmetatable({}, Spectator)
	self.gui = gui
	self.active = false
	self.onStop = nil

	local root = UI.mk("Frame", {
		Name = "Spectate", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui,
	})
	self.root = root

	-- the card at the top: WATCHING on a plate, their name big, their title, how far and how fast
	local top = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(440, 118), BackgroundTransparency = 1, ZIndex = 31, Parent = root })
	UI.autoScale(top, 1280, 760)
	local card = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 31, Parent = top })
	Kit.panel(card, C.green, 31)
	self.card = card
	Kit.plate(card, "Watching", C.green, UDim2.new(0.5, -60, 0, -13), UDim2.fromOffset(120, 26), 34)
	self.nameLabel = Kit.text("", 30, C.white, 2.5)
	self.nameLabel.Position = UDim2.fromOffset(16, 18)
	self.nameLabel.Size = UDim2.new(1, -32, 0, 34)
	Kit.fit(self.nameLabel, 30, 14)
	self.nameLabel.ZIndex = 34
	self.nameLabel.Parent = card
	self.title = UI.titleLabel(nil, 16)
	self.title.Position = UDim2.fromOffset(16, 52)
	self.title.Size = UDim2.new(1, -32, 0, 20)
	self.title.TextXAlignment = Enum.TextXAlignment.Center
	self.title.ZIndex = 34
	self.title.Parent = card
	self.statLabel = Kit.text("connecting...", 16, C.gold, 2)
	self.statLabel.Position = UDim2.fromOffset(16, 78)
	self.statLabel.Size = UDim2.new(1, -32, 0, 22)
	Kit.fit(self.statLabel, 16, 10)
	self.statLabel.ZIndex = 34
	self.statLabel.Parent = card

	local bottom = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(200, 56), BackgroundTransparency = 1, ZIndex = 31, Parent = root })
	UI.autoScale(bottom, 1280, 760)
	local leave = Kit.button("Leave", C.red, UDim2.fromOffset(200, 56), 24)
	leave.root.ZIndex = 32
	leave.root.Parent = bottom
	leave.onClick = function() self:stop() end

	self.escConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if not self.active then return end
		local k = input.KeyCode
		if k == Enum.KeyCode.Backspace or k == Enum.KeyCode.ButtonB or (not gpe and k == Enum.KeyCode.Escape) then
			self:stop()
		end
	end)

	Remotes.RunState.OnClientEvent:Connect(function(fromUserId, payload)
		self:onState(fromUserId, payload)
	end)

	return self
end

function Spectator:start(userId: number, name: string?): boolean
	if self.active then self:stop() end
	local ok, res = pcall(function() return Remotes.Spectate:InvokeServer(userId) end)
	if not ok or type(res) ~= "table" or not res.ok then
		self.lastError = (type(res) == "table" and res.err) or "Couldn't watch that run."
		return false
	end

	self.active = true
	self.target = userId
	self.lastPacket = os.clock()
	self.pose = nil
	self.smooth = nil
	self.root.Visible = true
	Kit.appear(self.card, 0, 20)
	self.nameLabel.Text = string.upper(res.name or name or "?")
	local pl = Players:GetPlayerByUserId(userId)
	local titleId = pl and pl:GetAttribute("Title")
	UI.applyTitle(self.title, (type(titleId) == "string" and titleId ~= "") and titleId or nil)
	self.statLabel.Text = "waiting for their next frame..."

	self.camera = workspace.CurrentCamera
	self.savedCamType = self.camera.CameraType
	self.savedFov = self.camera.FieldOfView
	self.camera.CameraType = Enum.CameraType.Scriptable
	self.savedLighting = {
		FogColor = Lighting.FogColor, FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
		ClockTime = Lighting.ClockTime, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
	}

	self.conn = RunService.RenderStepped:Connect(function(dt) self:frame(dt) end)
	return true
end

-- the runner's road, built the way theirs is: their seed, their stage's hills, their skill zones
function Spectator:buildWorld(payload: any)
	if self.world then self.world:destroy(); self.world = nil end
	if self.folder then self.folder:Destroy(); self.folder = nil end

	local trackId, seed = payload.t, tonumber(payload.sd) :: number
	local track = TrackGen.get(trackId)
	track:setRun(seed, 0, 0)
	track.hillScale = tonumber(payload.hs) or track.hillScale
	pcall(function() track:setSkillKind(if type(payload.kk) == "string" then payload.kk else nil) end)
	self.trackId = trackId
	self.seed = seed
	self.track = track
	self.world = WorldView.new(trackId)
	self.world:ensure(tonumber(payload.x) or 0)

	local cfg = track.cfg
	if cfg.clockTime then Lighting.ClockTime = cfg.clockTime end
	if cfg.ambient then
		Lighting.Ambient = cfg.ambient
		Lighting.OutdoorAmbient = cfg.ambient
	end

	local folder = Instance.new("Folder")
	folder.Name = "TyreCannonSpectate"
	folder.Parent = workspace
	self.folder = folder

	-- their own tyre (its model), or the stock wheel in their skin and rim
	local tyreId = if type(payload.ty) == "string" then payload.ty else nil
	local m: Model
	if tyreId and TyreLook.has(tyreId) then
		m = TyreLook.model(tyreId, P.TyreRadius * 2, "WatchedTyre")
		m.Parent = folder
	else
		m = WheelAssembly.build(folder, { diameter = P.TyreRadius * 2, skin = payload.sk or "stock", rim = payload.rm or "steel", detail = "low" })
	end
	m.Name = "WatchedTyre"
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	self.model = m
end

function Spectator:onState(fromUserId: number, payload: any)
	if not self.active or fromUserId ~= self.target or type(payload) ~= "table" then return end
	if payload.done then
		self.statLabel.Text = "RUN'S OVER"
		task.delay(2.2, function()
			if self.active then self:stop() end
		end)
		return
	end

	local trackId = payload.t
	local seed = tonumber(payload.sd)
	if type(trackId) ~= "string" or not Config.TracksById[trackId] or not seed then return end

	self.lastPacket = os.clock()
	if self.trackId ~= trackId or self.seed ~= seed then
		self:buildWorld(payload)
	end

	self.pose = {
		x = tonumber(payload.x) or 0,
		y = tonumber(payload.y) or 0,
		z = tonumber(payload.z) or 0,
		roll = tonumber(payload.roll) or 0,
	}
	self.dist = tonumber(payload.d) or 0
	self.spd = tonumber(payload.sp) or 0
	self.zoneI = tonumber(payload.tr) or 1
	self.smooth = self.smooth or table.clone(self.pose)
end

function Spectator:frame(dt: number)
	if not self.active then return end
	if os.clock() - self.lastPacket > STALE then
		self:stop()
		return
	end
	if not (self.pose and self.smooth and self.world and self.model) then return end

	-- the packets come ten a second: ease toward the newest
	local a = math.min(1, dt * 12)
	local s, p = self.smooth, self.pose
	s.x = lerp(s.x, p.x, a)
	s.y = lerp(s.y, p.y, a)
	s.z = lerp(s.z, p.z, a)
	s.roll = lerp(s.roll, p.roll, math.min(1, dt * 8))

	self.world:ensure(s.x)
	self.world:update(dt, s.x)
	self.model:PivotTo(CFrame.new(s.x, s.y, s.z) * CFrame.Angles(0, 0, -s.roll))

	local speedT = math.clamp(self.spd / 950, 0, 1.4)
	local desired = CFrame.lookAt(
		Vector3.new(s.x - (54 + speedT * 44), s.y + (28 + speedT * 15), s.z * 0.5 + 34),
		Vector3.new(s.x + 58 + speedT * 90, s.y + 2, s.z * 0.85))
	self.camCF = self.camCF and self.camCF:Lerp(desired, math.min(1, dt * 9)) or desired
	self.camera.CFrame = self.camCF
	self.camera.FieldOfView = 68 + speedT * 26

	local zone = self.track and self.track.isRoad and self.track:cfgAt(math.max(0, s.x))
	self.statLabel.Text = ("%s M   ·   %s STUDS/S%s"):format(
		UI.comma(math.floor(self.dist * P.StudsToMetres)), UI.comma(math.floor(self.spd)),
		if zone and zone.name then "   ·   " .. string.upper(zone.name) else "")
end

function Spectator:stop()
	if not self.active then return end
	self.active = false
	pcall(function() Remotes.Spectate:InvokeServer(nil) end)

	if self.conn then self.conn:Disconnect(); self.conn = nil end
	if self.world then self.world:destroy(); self.world = nil end
	if self.folder then self.folder:Destroy(); self.folder = nil end
	-- (the road object is shared: the next run of our own sets its own seed, hills and zones)
	if self.track then pcall(function() self.track:setSkillKind(nil) end) end
	self.model = nil
	self.track = nil
	self.trackId = nil
	self.seed = nil
	self.pose = nil
	self.smooth = nil
	self.camCF = nil
	self.root.Visible = false

	if self.camera then
		self.camera.CameraType = self.savedCamType or Enum.CameraType.Custom
		self.camera.FieldOfView = self.savedFov or 70
	end
	for k, v in pairs(self.savedLighting or {}) do
		(Lighting :: any)[k] = v
	end
	if self.onStop then task.spawn(self.onStop) end
end

return Spectator
