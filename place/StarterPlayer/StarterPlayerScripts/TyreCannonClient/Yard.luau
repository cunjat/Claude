--!strict
-- TYRE CANNON :: Yard
-- What every plot shows off, driven by the plots snapshot:
--   garage doors   the owner's paint, stencil and stickers on their roller door. If the
--                  garage model has a part called Door it's used; otherwise a door panel
--                  goes in front of the Doorway placeholder
--   name plates    a brass plate on the rig with the rig's name stamped in it
--   honks          walk up to someone else's lever and press H: out comes the vuvuzela,
--                  and their sign counts it
--   ticking over   rigs puff exhaust from any SmokePoint attachment on their engine model

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Remotes = Root:WaitForChild("Remotes")
local Config = require(Modules.Config)
local WheelAssembly = require(Modules.WheelAssembly)
local DoorArt = require(Modules:WaitForChild("DoorArt"))
local UI = require(script.Parent.UI)
local Prefs = require(script.Parent.Prefs)
local T = UI.Theme

local Yard = {}
Yard.__index = Yard

local BRASS = Color3.fromRGB(184, 144, 74)
local ENGRAVE = Color3.fromRGB(62, 42, 20)

local function anchored(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

function Yard.new(plots: Instance, hooks)
	local self = setmetatable({}, Yard)
	self.plots = plots
	self.hooks = hooks or {}
	self.byIndex = {}
	self.snapshot = {}
	self.keys = {}
	for _, plot in ipairs(plots:GetChildren()) do
		local i = plot:GetAttribute("Index")
		if i then
			self.byIndex[i] = { plot = plot }
			self:buildPlot(i)
		end
	end
	Remotes:WaitForChild("Honked").OnClientEvent:Connect(function(index, userId, count)
		self:onHonked(index, userId, count)
	end)
	self:startPuffs()
	return self
end

--==============================================================
-- per-plot pieces
--==============================================================
function Yard:buildPlot(i: number)
	local node = self.byIndex[i]
	local plot = node.plot
	local base = plot:GetAttribute("BaseCFrame") :: CFrame?

	-- the door
	local garage = plot:FindFirstChild("Garage")
	local door = garage and garage:FindFirstChild("Door") :: BasePart?
	local face = Enum.NormalId.Front
	if not door then
		local way = garage and garage:FindFirstChild("Doorway") :: BasePart?
		local floor = plot:FindFirstChild("Floor") :: BasePart?
		if way then
			local right = way.CFrame.RightVector
			local toward = floor and (floor.Position - way.Position) or right
			local dir = right * ((toward:Dot(right) >= 0) and 1 or -1)
			local pos = way.Position + dir * (way.Size.X / 2 + 0.08)
			local p = Instance.new("Part")
			p.Name = "DoorPanel"
			p.Size = Vector3.new(way.Size.Z + 0.6, way.Size.Y + 0.6, 0.14)
			p.CFrame = CFrame.lookAt(pos, pos + dir)
			p.Color = Color3.fromRGB(120, 122, 126)
			p.Material = Enum.Material.Metal
			anchored(p)
			p.Parent = garage
			door = p
		end
	end
	if door then
		local sg = Instance.new("SurfaceGui")
		sg.Name = "DoorArt"
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 48
		sg.LightInfluence = 1
		sg.MaxDistance = 400
		sg.Parent = door
		local holder = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = sg })
		node.doorHolder = holder
	end

	-- the brass plate on the rig's front sleeper
	local rig = plot:FindFirstChild("LauncherRig")
	if rig and base then
		local best: BasePart? = nil
		for _, s in ipairs(rig:GetChildren()) do
			if s:IsA("BasePart") and s.Name == "Sleeper" then
				if not best or base:PointToObjectSpace(s.Position).Z > base:PointToObjectSpace((best :: BasePart).Position).Z then best = s end
			end
		end
		if best then
			local sl = best :: BasePart
			local depth = math.min(sl.Size.X, sl.Size.Z)
			local pos = sl.Position + base.ZVector * (depth / 2 + 0.06)
			local plate = Instance.new("Part")
			plate.Name = "NamePlate"
			plate.Size = Vector3.new(7, 1.05, 0.1)
			plate.CFrame = CFrame.lookAt(pos, pos + base.ZVector)
			plate.Color = BRASS
			plate.Material = Enum.Material.Metal
			plate.Reflectance = 0.08
			anchored(plate)
			plate.Transparency = 1
			plate.Parent = rig
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Front
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 60
			sg.LightInfluence = 1
			sg.MaxDistance = 160
			sg.Enabled = false
			sg.Parent = plate
			local text = UI.text("", 34, "display", ENGRAVE)
			text.Size = UDim2.new(1, -60, 1, -8)
			text.Position = UDim2.fromOffset(30, 4)
			text.TextXAlignment = Enum.TextXAlignment.Center
			text.TextScaled = true
			text.TextStrokeColor3 = Color3.fromRGB(236, 206, 140)
			text.TextStrokeTransparency = 0.55
			text.Parent = sg
			UI.mk("UITextSizeConstraint", { MaxTextSize = 40, Parent = text })
			for _, x in ipairs({ 0.03, 0.97 }) do
				local bolt = UI.mk("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.5), Size = UDim2.fromOffset(14, 14),
					BackgroundColor3 = Color3.fromRGB(110, 84, 40), BorderSizePixel = 0, Parent = sg,
				})
				UI.corner(7).Parent = bolt
			end
			node.plate, node.plateGui, node.plateText = plate, sg, text
		end
	end

	-- the honk prompt, on the lever zone
	local lc = plot:FindFirstChild("LaunchControl")
	local zone = lc and lc:FindFirstChild("Zone")
	if zone then
		local pr = Instance.new("ProximityPrompt")
		pr.Name = "HonkPrompt"
		pr.ActionText = "Honk"
		pr.ObjectText = ""
		pr.KeyboardKeyCode = Enum.KeyCode.H
		pr.GamepadKeyCode = Enum.KeyCode.ButtonX
		pr.HoldDuration = 0
		pr.MaxActivationDistance = 16
		pr.RequiresLineOfSight = false
		pr.Enabled = false
		pr.Parent = zone
		pr.Triggered:Connect(function() self:honk(i) end)
		node.honkPrompt = pr
	end
end

--==============================================================
-- the snapshot
--==============================================================
function Yard:apply(snapshot, myUserId: number)
	self.snapshot = snapshot or {}
	local cat = WheelAssembly.stickers()
	for i, node in pairs(self.byIndex) do
		local info = self.snapshot[i]
		local owned = type(info) == "table"
		node.info = owned and info or nil
		local mine = owned and info.userId == myUserId

		-- door
		if node.doorHolder then
			local key = "empty"
			if owned then
				local ok, stickers = pcall(function() return HttpService:JSONEncode(info.stickers or {}) end)
				key = table.concat({ tostring(info.userId), info.doorPaint or "", info.doorStencil or "", info.rigName or "", ok and stickers or "" }, "|")
			end
			if self.keys[i] ~= key then
				self.keys[i] = key
				DoorArt.paint(node.doorHolder, owned and {
					paint = info.doorPaint, stencil = info.doorStencil, name = info.rigName, number = i,
					stickers = info.stickers, catalogue = cat, seed = (info.userId or 0) % 100000 + 7, stickerScale = 1.3,
				} or { paint = "steel", stencil = "number", number = i })
			end
		end

		-- plate
		if node.plate then
			local name = owned and type(info.rigName) == "string" and info.rigName or ""
			node.plate.Transparency = name ~= "" and 0 or 1
			node.plateGui.Enabled = name ~= ""
			node.plateText.Text = string.upper(name)
		end

		-- the garage door: go inside yours, look round anyone else's
		if node.garagePrompt == nil then
			node.garagePrompt = false
			for _, d in ipairs(node.plot:GetDescendants()) do
				if d:IsA("ProximityPrompt") and d:GetAttribute("TCAction") == "Garage" then node.garagePrompt = d end
			end
		end
		if node.garagePrompt then
			local gp = node.garagePrompt :: ProximityPrompt
			gp.ActionText = mine and "Go inside" or "Look inside"
			gp.ObjectText = owned and (mine and "Your garage" or (tostring(info.name) .. "'s garage")) or ""
			node.garageOwned = owned
		end

		-- honk
		if node.honkPrompt then
			node.honkPrompt.ObjectText = owned and (tostring(info.name) .. "'s yard") or ""
			node.honkAllowed = owned and not mine
		end
	end
	self:refreshPrompts()
end

-- someone else's lever shows HONK instead of the launch and workbench prompts
function Yard:refreshPrompts()
	local on = self.promptsOn ~= false
	for _, node in pairs(self.byIndex) do
		local foreign = node.honkAllowed == true
		if node.honkPrompt then node.honkPrompt.Enabled = on and foreign end
		if node.garagePrompt then (node.garagePrompt :: ProximityPrompt).Enabled = on and node.garageOwned == true end
		if foreign then
			for _, d in ipairs(node.plot:GetDescendants()) do
				if d:IsA("ProximityPrompt") and d.Name ~= "HonkPrompt" then
					local action = d:GetAttribute("TCAction")
					if action == "Launch" or action == "Workbench" then d.Enabled = false end
				end
			end
		end
	end
end

function Yard:setPromptsEnabled(on: boolean)
	self.promptsOn = on
	self:refreshPrompts()
end

--==============================================================
-- honking
--==============================================================
function Yard:honk(i: number)
	local ok, res = pcall(function() return (Remotes :: any).Honk:InvokeServer(i) end)
	if ok and type(res) == "table" and res.ok == false and res.err and self.hooks.toast then
		self.hooks.toast(res.err, T.bad)
	end
end

function Yard:onHonked(index: number, userId: number, count: number)
	if self.hooks.onHonked then self.hooks.onHonked(index, count) end
	local honker = Players:GetPlayerByUserId(userId)
	local info = self.snapshot[index]
	if type(info) == "table" and info.userId == Players.LocalPlayer.UserId and honker and self.hooks.toast then
		self.hooks.toast(("%s HONKED AT YOUR YARD"):format(string.upper(honker.DisplayName)), T.warn)
	end
	if honker and honker.Character then self:blast(honker.Character) end
end

-- out comes the vuvuzela, up goes the arm, and a HONK pops over their head
function Yard:blast(char: Model)
	local arm = char:FindFirstChild("Right Arm") :: BasePart?
	local head = char:FindFirstChild("Head") :: BasePart?
	local tpl = Root.Assets.Props:FindFirstChild("Vuvuzela") :: BasePart?
	if arm and tpl then
		local horn = tpl:Clone()
		anchored(horn)
		horn.Anchored = false
		horn.Massless = true
		horn.CFrame = arm.CFrame * CFrame.new(0, -1.1, -0.9) * CFrame.Angles(0, math.rad(90), 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = arm
		weld.Part1 = horn
		weld.Parent = horn
		horn.Parent = char
		local s = horn:FindFirstChildOfClass("Sound")
		if s then
			s.SoundGroup = game:GetService("SoundService"):FindFirstChild("Effects") :: SoundGroup?
			pcall(function() s:Play() end)
		end
		task.delay(1.4, function() horn:Destroy() end)
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://182393478"
		local ok, track = pcall(function() return (animator :: Animator):LoadAnimation(a) end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action3
			track:Play(0.1)
			task.delay(1.3, function() track:Stop(0.25) end)
		end
	end
	if head then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(160, 60)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.MaxDistance = 200
		bb.Adornee = head
		bb.Parent = head
		local l = UI.text("HONK", 30, "display", T.warn)
		l.Size = UDim2.fromScale(1, 1)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.Rotation = -8
		l.Parent = bb
		UI.mk("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3, Parent = l })
		local sc = UI.mk("UIScale", { Scale = 0.3, Parent = l })
		UI.tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		UI.tween(bb, 1.1, { StudsOffset = Vector3.new(0, 4.4, 0) }, Enum.EasingStyle.Quad)
		task.delay(0.7, function() UI.tween(l, 0.4, { TextTransparency = 1 }) end)
		task.delay(1.2, function() bb:Destroy() end)
	end
end

--==============================================================
-- rigs ticking over: exhaust puffs from any SmokePoint on an engine model
--==============================================================
function Yard:startPuffs()
	local puffs = {}
	for _, node in pairs(self.byIndex) do
		local rig = node.plot:FindFirstChild("LauncherRig")
		local engine = rig and rig:FindFirstChild("Engine")
		if engine then
			for _, d in ipairs(engine:GetDescendants()) do
				if d:IsA("Attachment") and d.Name == "SmokePoint" then
					local e = Instance.new("ParticleEmitter")
					e.Name = "IdlePuff"
					e.Texture = "rbxasset://textures/particles/smoke_main.dds"
					e.Rate = 0
					e.Lifetime = NumberRange.new(1.2, 2)
					e.Speed = NumberRange.new(2, 4)
					e.SpreadAngle = Vector2.new(14, 14)
					e.Acceleration = Vector3.new(0.6, 2.4, 0)
					e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 2.4) })
					e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
					e.Color = ColorSequence.new(Color3.fromRGB(120, 116, 110))
					e.RotSpeed = NumberRange.new(-30, 30)
					e.LightInfluence = 1
					e.Parent = d
					table.insert(puffs, { e = e, t = math.random() * 2 })
				end
			end
		end
	end
	if #puffs == 0 then return end
	RunService.Heartbeat:Connect(function(dt)
		for _, p in ipairs(puffs) do
			p.t -= dt
			if p.t <= 0 then
				p.t = 0.9 + math.random() * 1.4
				local density = math.clamp(tonumber(Prefs.get("particles")) or 1, 0.2, 1)
				p.e:Emit(math.max(1, math.floor((1 + math.random(0, 2)) * density + 0.5)))
			end
		end
	end)
end

return Yard
