--!strict
-- TYRE CANNON :: Spectator
-- Watching someone else's attempt. The runner streams a pose and a seed; the
-- road is rebuilt locally from that seed, so a whole run costs a few numbers
-- a second.

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
local UI = require(script.Parent.UI)
local T = UI.Theme

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

	for _, y in ipairs({ 0, 1 }) do
		UI.mk("Frame", {
			AnchorPoint = Vector2.new(0, y), Position = UDim2.fromScale(0, y), Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = T.void, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 30, Parent = root,
		})
	end

	local card = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(400, 108),
		BackgroundTransparency = 0.06, ZIndex = 31, Parent = root,
	})
	UI.autoScale(card)

	local tag = UI.text("WATCHING", 11, "monoBold", T.good)
	tag.Position = UDim2.fromOffset(18, 10)
	tag.Size = UDim2.fromOffset(200, 14)
	tag.ZIndex = 32
	tag.Parent = card

	self.nameLabel = UI.text("", 28, "display", T.text)
	self.nameLabel.Position = UDim2.fromOffset(18, 22)
	self.nameLabel.Size = UDim2.fromOffset(364, 32)
	self.nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	self.nameLabel.ZIndex = 32
	self.nameLabel.Parent = card

	self.title = UI.titleLabel(nil, 16)
	self.title.Position = UDim2.fromOffset(18, 54)
	self.title.Size = UDim2.fromOffset(364, 20)
	self.title.ZIndex = 32
	self.title.Parent = card

	self.statLabel = UI.text("connecting...", 13, "monoBold", T.dim)
	self.statLabel.Position = UDim2.fromOffset(18, 80)
	self.statLabel.Size = UDim2.fromOffset(364, 18)
	self.statLabel.ZIndex = 32
	self.statLabel.Parent = card

	local leave = UI.button("LEAVE", "bad", 180, 44)
	leave.AnchorPoint = Vector2.new(0.5, 1)
	leave.Position = UDim2.new(0.5, 0, 1, -72)
	leave.ZIndex = 32
	leave.Parent = root
	leave.Activated:Connect(function() self:stop() end)

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

function Spectator:buildWorld(trackId: string, seed: number)
	if self.world then self.world:destroy(); self.world = nil end
	if self.folder then self.folder:Destroy(); self.folder = nil end

	local track = TrackGen.get(trackId)
	track:setRun(seed, 0, 0)
	self.trackId = trackId
	self.seed = seed
	self.track = track
	self.world = WorldView.new(trackId)
	self.world:ensure(0)

	local cfg = track.cfg
	Lighting.ClockTime = cfg.clockTime
	Lighting.Ambient = cfg.ambient
	Lighting.OutdoorAmbient = cfg.ambient

	local folder = Instance.new("Folder")
	folder.Name = "TyreCannonSpectate"
	folder.Parent = workspace
	self.folder = folder

	local m = WheelAssembly.build(folder, { diameter = P.TyreRadius * 2, skin = self.skinId or "stock", rim = self.rimId or "steel", detail = "low" })
	m.Name = "WatchedTyre"
	self.model = m
end

function Spectator:onState(fromUserId: number, payload: any)
	if not self.active or fromUserId ~= self.target or type(payload) ~= "table" then return end
	if payload.done then
		self.statLabel.Text = "run's over"
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
		self.skinId = payload.sk
		self.rimId = payload.rm
		self:buildWorld(trackId, seed)
	end

	self.pose = {
		x = tonumber(payload.x) or 0,
		y = tonumber(payload.y) or 0,
		z = tonumber(payload.z) or 0,
		roll = tonumber(payload.roll) or 0,
	}
	self.dist = tonumber(payload.d) or 0
	self.spd = tonumber(payload.sp) or 0
	self.tier = tonumber(payload.tr) or 0
	self.smooth = self.smooth or table.clone(self.pose)
end

function Spectator:frame(dt: number)
	if not self.active then return end
	if os.clock() - self.lastPacket > STALE then
		self:stop()
		return
	end
	if not (self.pose and self.smooth and self.world and self.model) then return end

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

	self.statLabel.Text = ("%s m   %s STUDS/S   CHECKPOINT %d"):format(
		UI.comma(self.dist * P.StudsToMetres), UI.comma(self.spd), self.tier)
end

function Spectator:stop()
	if not self.active then return end
	self.active = false
	pcall(function() Remotes.Spectate:InvokeServer(nil) end)

	if self.conn then self.conn:Disconnect(); self.conn = nil end
	if self.world then self.world:destroy(); self.world = nil end
	if self.folder then self.folder:Destroy(); self.folder = nil end
	self.model = nil
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
