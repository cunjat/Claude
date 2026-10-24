--!strict
-- TYRE CANNON :: Workshop / Retread
-- The anvil. Three toolboxes of one rarity go on, and three hammer strikes beat them
-- together into one glowing lump. The tongs quench it, and it comes up out of the
-- steam as a toolbox of the next rarity. The strikes decide its quality.
-- Toolboxes on the anvil are the Assets.Workshop toolbox models with a rarity outline;
-- heat is a Highlight overlay on the model, never a light.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))
local UI = require(script.Parent.Parent.UI)
local VFX = require(script.Parent.Parent.VFX)
local T = UI.Theme

local Retread = {}
Retread.__index = Retread

local RARITY_INDEX = {}
for i, r in ipairs(Config.ToolboxRarities) do RARITY_INDEX[r.id] = i end
local TOP_RARITY = Config.ToolboxRarities[#Config.ToolboxRarities].id
local LEVEL = { common = 0, uncommon = 0, rare = 1, epic = 2, legendary = 3 }
local HOT = Color3.fromRGB(255, 96, 18)
local WHITE_HOT = Color3.fromRGB(255, 176, 52)
local MAXED = "Legendary is the highest rarity, so it can't be forged."

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function frameWait(): number
	return RunService.RenderStepped:Wait()
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function centred(parent: Instance, text: string, size: number, role: string, color: Color3, y: number, h: number): TextLabel
	local l = UI.text(text, size, role, color)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.Size = UDim2.new(1, -12, 0, h)
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.ZIndex = 24
	l.Parent = parent
	return l
end

local function rarityEdge(frame: GuiObject, color: Color3, thickness: number): UIStroke
	local edge = UI.stroke(Color3.new(1, 1, 1), thickness)
	edge.Parent = frame
	UI.mk("UIGradient", {
		Rotation = 35,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.45)),
			ColorSequenceKeypoint.new(0.5, color),
			ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.5)),
		}),
		Parent = edge,
	})
	return edge
end

-- how hot a toolbox looks: 0 is its plain rarity outline, 1 glows white-orange
local function setHeat(m: Model, heat: number, base: Color3)
	local h = m:FindFirstChildOfClass("Highlight")
	if not h then return end
	heat = math.clamp(heat, 0, 1)
	-- dull red, then forge orange, then a yellow edge only at the very top
	local glow = Color3.fromRGB(190, 40, 14):Lerp(HOT, math.clamp(heat * 1.6, 0, 1)):Lerp(WHITE_HOT, math.clamp((heat - 0.85) * 6, 0, 1))
	h.FillColor = base:Lerp(glow, math.min(1, heat * 1.6))
	h.FillTransparency = 0.82 - 0.52 * heat
	h.OutlineColor = base:Lerp(Color3.fromRGB(255, 150, 40), math.min(1, heat * 1.3))
	h.OutlineTransparency = 0.1
end

--==============================================================
function Retread.new(ws)
	local self = setmetatable({}, Retread)
	self.ws = ws
	self.inputs = {}
	self.forging = false
	self.phase = nil
	self.active = false
	self.blocks = {}
	self.homes = {}
	self.result = nil

	local frame = UI.mk("Frame", {
		Name = "Retread", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(1140, 276), BackgroundTransparency = 1, Visible = false, ZIndex = 22, Parent = ws.root,
	})
	UI.autoScale(frame, 1240, 780)
	self.frame = frame
	centred(frame, "THREE IN, ONE OUT", 20, "display", T.text, 0, 24)
	centred(frame, "Three toolboxes of one rarity make one of the next. Hit the marks for a better one.", 14, "body", T.dim, 26, 18)

	local rowFrame = UI.mk("Frame", {
		Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 92), BackgroundTransparency = 1, ZIndex = 22, Parent = frame,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	self.slots = {}
	for i = 1, Config.Forge.Inputs do
		local b = UI.mk("TextButton", {
			Size = UDim2.fromOffset(150, 88), BackgroundTransparency = 1, BorderSizePixel = 0,
			AutoButtonColor = false, Text = "", LayoutOrder = i, ZIndex = 23, Parent = rowFrame,
		})
		UI.plate("slot", { Name = "Plate", Size = UDim2.fromScale(1, 1), ZIndex = 23, Parent = b })
		local edge = UI.plate("cardTrim", {
			Name = "Trim", Size = UDim2.fromScale(1, 1), ImageColor3 = T.line, ImageTransparency = 0.3, ZIndex = 24, Parent = b,
		})
		local name = centred(b, "EMPTY", 16, "display", T.faint, 26, 20)
		local sub = centred(b, "", 11, "monoBold", T.dim, 50, 14)
		b.Activated:Connect(function()
			if self.forging then return end
			self.inputs[i] = nil
			self:refresh()
		end)
		self.slots[i] = { button = b, edge = edge, name = name, sub = sub }
	end
	local arrow = UI.text(">", 26, "display", T.faint)
	arrow.Size = UDim2.fromOffset(24, 88)
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.LayoutOrder = 10
	arrow.ZIndex = 23
	arrow.Parent = rowFrame
	local out = UI.mk("Frame", {
		Size = UDim2.fromOffset(250, 88), BackgroundTransparency = 1,
		LayoutOrder = 11, ZIndex = 23, Parent = rowFrame,
	})
	UI.plate("slot", { Name = "Plate", Size = UDim2.fromScale(1, 1), ZIndex = 23, Parent = out })
	self.outEdge = UI.plate("cardTrim", {
		Name = "Trim", Size = UDim2.fromScale(1, 1), ImageColor3 = T.line, ImageTransparency = 0.3, ZIndex = 24, Parent = out,
	})
	self.outText = centred(out, "", 16, "display", T.faint, 24, 20)
	self.outSub = centred(out, "", 11, "monoBold", T.dim, 48, 14)
	self.forgeButton = UI.button("FORGE", "off", 150, 52)
	self.forgeButton.LayoutOrder = 12
	self.forgeButton.ZIndex = 23
	self.forgeButton.Parent = rowFrame
	self.forgeButton.Activated:Connect(function() self:forge() end)

	centred(frame, "YOUR TOOLBOXES", 13, "monoBold", T.faint, 156, 16)
	-- each card sits inset inside its cell, so the scroll area never clips its border
	local drawer = UI.mk("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 176), Size = UDim2.new(1, 0, 0, 96), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = T.lineHi, ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ElasticBehavior = Enum.ElasticBehavior.Never,
		ZIndex = 22, Parent = frame,
	})
	local drawerLayout = UI.list(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	drawerLayout.Parent = drawer
	UI.centreScroll(drawer, drawerLayout)
	self.drawer = drawer

	-- strike bar, above the tray while the hammer is up
	-- its own layer at the foot of the screen, since the tray drops away while you strike
	local strike = UI.mk("Frame", {
		Name = "StrikeBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.fromOffset(620, 66),
		BackgroundTransparency = 1, Visible = false, ZIndex = 22, Parent = ws.root,
	})
	UI.autoScale(strike, 1240, 780)
	self.strike = strike
	self.strikeText = centred(strike, "", 16, "monoBold", T.text, 0, 20)
	local bar = UI.mk("Frame", {
		Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(16, 15, 14),
		BorderSizePixel = 0, ZIndex = 23, Parent = strike,
	})
	UI.corner(4).Parent = bar
	UI.stroke(T.line, 1).Parent = bar
	self.sweet = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromScale(Config.Forge.SweetWidth, 1), BackgroundColor3 = T.good,
		BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 24, Parent = bar,
	})
	self.marker = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(5, 46),
		BackgroundColor3 = T.text, BorderSizePixel = 0, ZIndex = 25, Parent = bar,
	})
	return self
end

--==============================================================
-- the toolboxes as blocks on the anvil
--==============================================================
local KIND_MODEL = { drum = "Toolbox", trophy = "ToolboxRed", stake = "ToolboxBlue" }

function Retread:box(color: Color3, scale: number, kind: string?, rarity: string?): Model
	local W = Root:FindFirstChild("Assets") and Root.Assets:FindFirstChild("Workshop")
	local name = (rarity == "legendary" and "Boombox") or KIND_MODEL[kind or ""] or "Toolbox"
	local tpl = W and (W:FindFirstChild(name) or W:FindFirstChild("Toolbox"))
	local m = Instance.new("Model")
	if tpl and tpl:IsA("BasePart") then
		local p = tpl:Clone()
		p.Parent = m
	elseif tpl and tpl:IsA("Model") then
		m = tpl:Clone()
	else
		local p = Instance.new("Part")
		p.Size = Vector3.new(0.74, 0.46, 0.46)
		p.Color = color
		p.Material = Enum.Material.Metal
		p.Parent = m
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Camera") or d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("LuaSourceContainer") or d:IsA("Light") then d:Destroy() end
	end
	local _, size0 = m:GetBoundingBox()
	m:ScaleTo(m:GetScale() * (1.25 * scale / math.max(size0.X, size0.Z, 0.01)))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local bb, size = m:GetBoundingBox()
	m.WorldPivot = CFrame.new(bb.Position - Vector3.new(0, size.Y / 2, 0))
	-- rarity reads from an outline; the model keeps its own colours
	local h = Instance.new("Highlight")
	h.FillColor = color
	h.FillTransparency = 0.82
	h.OutlineColor = color
	h.OutlineTransparency = 0.1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = m
	m:SetAttribute("Model", name)
	m.Name = "Toolbox"
	m:SetAttribute("BoxHeight", size.Y)
	return m
end

function Retread:boxByUid(uid: number?)
	local p = self.ws.profile
	if not (p and uid) then return nil end
	for _, tb in ipairs(p.toolboxes or {}) do
		if tb.uid == uid then return tb end
	end
	return nil
end

function Retread:syncBlocks()
	-- mid-forge the blocks belong to the animation, even once the server has used them up
	if self.forging then return end
	local room = self.ws.room
	for i = 1, Config.Forge.Inputs do
		local tb = self.active and self:boxByUid(self.inputs[i]) or nil
		local b = self.blocks[i]
		if b and (not tb or b:GetAttribute("Uid") ~= tb.uid) then
			b:Destroy()
			self.blocks[i] = nil
			self.homes[i] = nil
			b = nil
		end
		if tb and not b and room then
			local rar = Config.ToolboxRaritiesById[tb.rarity]
			local m = self:box(rar.color, 1, tb.kind, tb.rarity)
			m:SetAttribute("Uid", tb.uid)
			local stagger = (i == 2) and -0.25 or 0.2
			local home = CFrame.new(room.strikePoint + Vector3.new((i - 2) * 1.35, 0, stagger)) * CFrame.Angles(0, math.rad((i - 2) * 9), 0)
			m:PivotTo(home)
			m.Parent = room.folder
			self.blocks[i] = m
			self.homes[i] = home
		end
	end
end

function Retread:clearResult()
	if self.result then
		self.result:Destroy()
		self.result = nil
	end
end

--==============================================================
-- motion
--==============================================================
local function easeOutCubic(k: number): number return 1 - (1 - k) ^ 3 end
local function easeInCubic(k: number): number return k * k * k end
local function easeInOut(k: number): number return -(math.cos(math.pi * k) - 1) / 2 end
local function easeOutBack(k: number): number
	local c1 = 1.70158
	return 1 + (c1 + 1) * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
end
local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t)
end

-- a Workspace attribute for reviewing the forge frame by frame: 0 freezes it, 0.2 is slow
local function animRate(): number
	local r = workspace:GetAttribute("ForgeAnimRate")
	return typeof(r) == "number" and r or 1
end

-- runs fn(k, dt) every frame for dur seconds; false if the station closed under it
function Retread:tween(dur: number, fn: (number, number) -> ()): boolean
	local t = 0
	while t < dur do
		local dt = frameWait() * animRate()
		t += dt
		if not (self.active and self.ws.isOpen) then return false end
		fn(math.clamp(t / dur, 0, 1), dt)
	end
	return true
end

-- everything holds still for a beat on impact, so a blow lands with weight
function Retread:hitstop(sec: number)
	local t = 0
	while t < sec do t += frameWait() * animRate() end
end

-- a camera jolt and a quick push in of the lens
function Retread:punch(shake: number, fov: number)
	local ws = self.ws
	ws:shake(shake)
	ws.camFov = math.max(20, (ws.camFov or 42) - fov)
end

local WATER = Color3.fromRGB(196, 216, 230)
-- small specks borrowed from the VFX pack's emitters, for droplets, bubbles and embers
local TEX = {
	specks = { "Blowout", "Main", "Specks1" },
}
-- animated sheets from the realistic effects kit: each particle plays its 4x4 sheet once
local SHEET = {
	flame = "rbxassetid://11858203067",
	lick = "rbxassetid://11844017484",
	steam = "rbxassetid://13743483729",
	plume = "rbxassetid://13726321388",
	splash = "rbxassetid://12356442287",
	ripple = "rbxassetid://13953700240",
}
local function ns(pairs_: { { number } }): NumberSequence
	local k = {}
	for _, p in ipairs(pairs_) do table.insert(k, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(k)
end
local function sheet(id: string, fps: NumberRange)
	return { Texture = id, FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, FlipbookFramerate = fps }
end
local function with(base: { [string]: any }, extra: { [string]: any })
	local t = table.clone(base)
	for k, v in pairs(extra) do t[k] = v end
	return t
end
local PRESETS = {
	-- water
	droplets = {
		Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(35, 35),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -46, 0),
		Size = ns({ { 0, 0.14 }, { 1, 0.05 } }), Transparency = ns({ { 0, 0.1 }, { 1, 1 } }),
		Color = ColorSequence.new(WATER), LightInfluence = 0.8, Shape = Enum.ParticleEmitterShape.Box, tex = "specks",
	},
	splash = with(sheet(SHEET.splash, NumberRange.new(34, 38)), {
		Lifetime = NumberRange.new(0.44, 0.48), Speed = NumberRange.new(0, 0), EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(-12, 12), Size = ns({ { 0, 1.7 }, { 1, 2.8 } }), Transparency = ns({ { 0, 0.05 }, { 1, 0.2 } }),
		Color = ColorSequence.new(Color3.fromRGB(226, 238, 246)), LightEmission = 0.1, LightInfluence = 0.6, Brightness = 1.6,
		ZOffset = 0.5, Shape = Enum.ParticleEmitterShape.Box,
	}),
	ripple = with(sheet(SHEET.ripple, NumberRange.new(18, 22)), {
		Lifetime = NumberRange.new(0.75, 0.85), Speed = NumberRange.new(0.01, 0.01), EmissionDirection = Enum.NormalId.Top,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, Size = ns({ { 0, 1.1 }, { 1, 3 } }),
		Transparency = ns({ { 0, 0.2 }, { 1, 0.85 } }), Color = ColorSequence.new(Color3.fromRGB(214, 230, 240)),
		LightInfluence = 0.6, Brightness = 1.4, Shape = Enum.ParticleEmitterShape.Box,
	}),
	bubbles = {
		Lifetime = NumberRange.new(0.25, 0.5), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Size = ns({ { 0, 0.08 }, { 1, 0.22 } }), Transparency = ns({ { 0, 0.35 }, { 1, 1 } }),
		Color = ColorSequence.new(Color3.fromRGB(236, 242, 246)), LightInfluence = 1, Shape = Enum.ParticleEmitterShape.Box, tex = "specks",
	},
	drips = {
		Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(0, 1), Acceleration = Vector3.new(0, -34, 0),
		Size = NumberSequence.new(0.08), Transparency = ns({ { 0, 0.2 }, { 1, 0.9 } }),
		Color = ColorSequence.new(WATER), LightInfluence = 1, Shape = Enum.ParticleEmitterShape.Box, tex = "specks",
	},
	-- steam: soft wisps rising, and a heavier plume for the moment it goes in
	steam = with(sheet(SHEET.steam, NumberRange.new(15, 20)), {
		Lifetime = NumberRange.new(0.95, 1.05), Speed = NumberRange.new(2.5, 4.5), SpreadAngle = Vector2.new(14, 14),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 1.5, 0), Drag = 1.2,
		Rotation = NumberRange.new(-25, 25), RotSpeed = NumberRange.new(-15, 15),
		Size = ns({ { 0, 1.3 }, { 1, 3.4 } }), Transparency = ns({ { 0, 0.5 }, { 0.3, 0.3 }, { 1, 0.55 } }),
		Color = ColorSequence.new(Color3.fromRGB(236, 238, 240)), LightEmission = 0.05, LightInfluence = 0.7, Brightness = 1.3,
		Shape = Enum.ParticleEmitterShape.Box,
	}),
	plume = with(sheet(SHEET.plume, NumberRange.new(17, 20)), {
		Lifetime = NumberRange.new(0.85, 0.95), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 2, 0), Drag = 1.5,
		Rotation = NumberRange.new(-30, 30), Size = ns({ { 0, 2 }, { 1, 4.6 } }), Transparency = ns({ { 0, 0.3 }, { 1, 0.5 } }),
		Color = ColorSequence.new(Color3.fromRGB(240, 241, 243)), LightEmission = 0.05, LightInfluence = 0.7, Brightness = 1.2,
		Shape = Enum.ParticleEmitterShape.Box,
	}),
	-- the furnace: rolling flames in the arch, thinner tongues licking out of it, soot off the chimney
	flames = with(sheet(SHEET.flame, NumberRange.new(24, 28)), {
		Lifetime = NumberRange.new(0.6, 0.66), Speed = NumberRange.new(0.8, 1.8), SpreadAngle = Vector2.new(10, 10),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 1.5, 0), Rotation = NumberRange.new(-12, 12),
		Size = ns({ { 0, 1.3 }, { 1, 1.8 } }), Transparency = NumberSequence.new(0),
		Color = ColorSequence.new(Color3.fromRGB(255, 176, 86), Color3.fromRGB(255, 92, 30)), LightEmission = 0.75,
		LightInfluence = 0.1, Brightness = 3, Shape = Enum.ParticleEmitterShape.Box,
	}),
	lick = with(sheet(SHEET.lick, NumberRange.new(28, 32)), {
		Lifetime = NumberRange.new(0.5, 0.56), Speed = NumberRange.new(1.5, 3), SpreadAngle = Vector2.new(16, 16),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 2, 0), Rotation = NumberRange.new(-15, 15),
		Size = ns({ { 0, 0.8 }, { 1, 1.2 } }), Transparency = NumberSequence.new(0),
		Color = ColorSequence.new(Color3.fromRGB(255, 190, 100), Color3.fromRGB(255, 100, 34)), LightEmission = 0.8,
		LightInfluence = 0.1, Brightness = 3, Shape = Enum.ParticleEmitterShape.Box,
	}),
	soot = with(sheet(SHEET.steam, NumberRange.new(12, 15)), {
		Lifetime = NumberRange.new(1.2, 1.3), Speed = NumberRange.new(2, 3), SpreadAngle = Vector2.new(8, 8),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0.5, 1, 0), Drag = 0.8, Rotation = NumberRange.new(-20, 20),
		Size = ns({ { 0, 1 }, { 1, 3 } }), Transparency = ns({ { 0, 0.55 }, { 1, 0.7 } }),
		Color = ColorSequence.new(Color3.fromRGB(58, 54, 52)), LightInfluence = 1, Brightness = 1,
		Shape = Enum.ParticleEmitterShape.Box,
	}),
	embers = {
		Lifetime = NumberRange.new(0.5, 1.1), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(35, 35),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 3, 0),
		Size = ns({ { 0, 0.12 }, { 1, 0.03 } }), Transparency = ns({ { 0, 0 }, { 1, 1 } }),
		Color = ColorSequence.new(Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 90, 20)), LightEmission = 0.5,
		LightInfluence = 0.3, Shape = Enum.ParticleEmitterShape.Box, tex = "specks",
	},
}

local function borrowLook(e: ParticleEmitter, key: string?)
	local path = key and TEX[key]
	if not path then return end
	local node: Instance? = Root:FindFirstChild("Assets")
	node = node and node:FindFirstChild("VFX")
	for _, n in ipairs(path) do node = node and node:FindFirstChild(n) end
	if node and node:IsA("ParticleEmitter") then
		e.Texture = node.Texture
		e.FlipbookLayout = node.FlipbookLayout
		e.FlipbookMode = node.FlipbookMode
		e.FlipbookFramerate = node.FlipbookFramerate
		e.FlipbookStartRandom = node.FlipbookStartRandom
	end
end

-- an emitter on a hidden part: emits a burst now, and can keep going while you hold it.
-- dir, when given, is the way the particles fly out
function Retread:emitter(preset: string, at: Vector3, burst: number, life: number?, boxSize: Vector3?, dir: Vector3?)
	local room = self.ws.room
	local p = Instance.new("Part")
	p.Size = boxSize or Vector3.new(0.6, 0.1, 0.6)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if dir and dir.Magnitude > 1e-3 then
		p.CFrame = CFrame.lookAt(at, at + dir) * CFrame.Angles(-math.pi / 2, 0, 0)
	else
		p.CFrame = CFrame.new(at)
	end
	p.Parent = room.folder
	local e = Instance.new("ParticleEmitter")
	local def = PRESETS[preset]
	for k, v in pairs(def) do
		if k ~= "tex" then (e :: any)[k] = v end
	end
	borrowLook(e, def.tex)
	e.Rate = 0
	e.Parent = p
	if burst > 0 then e:Emit(math.max(1, math.floor(burst * VFX.density()))) end
	task.delay(life or 2.5, function() p:Destroy() end)
	return p, e
end

--==============================================================
-- the boxes on the anvil
--==============================================================
-- height of a box model as built (its pivot is the middle of its base)
local function heightOf(b: Model): number
	return (b:GetAttribute("BoxHeight") :: number?) or 0.6
end

-- the three stacked for the forge: two side by side, one across the top.
-- p is how far they've been beaten together (0 to 1)
function Retread:stackPose(i: number, base: CFrame, p: number, h: number): (CFrame, number)
	local spread = 0.64 * (1 - 0.55 * p)
	local scale = 1 - 0.12 * p
	if i == 1 then
		return base * CFrame.new(-spread, 0, 0) * CFrame.Angles(0, math.rad(6), 0), scale
	elseif i == 2 then
		return base * CFrame.new(spread, 0, 0.05) * CFrame.Angles(0, math.rad(-5), 0), scale
	end
	return base * CFrame.new(0, h * scale * (1 - 0.48 * p), -0.02) * CFrame.Angles(0, math.rad(90), math.rad(3)), scale
end

function Retread:setStack(base: CFrame, p: number, squash: number)
	for i, b in pairs(self.blocks) do
		if b.Parent then
			if not b:GetAttribute("Scale0") then
				b:SetAttribute("Scale0", b:GetScale())
				b:SetAttribute("Height0", heightOf(b))
			end
			local h = b:GetAttribute("Height0") :: number
			local cf, scale = self:stackPose(i, base, p, h)
			local s = scale * squash
			b:ScaleTo((b:GetAttribute("Scale0") :: number) * s)
			b:SetAttribute("BoxHeight", h * s)
			if i == 3 then cf = base * CFrame.new(0, (cf.Position - base.Position).Y * squash, 0) * cf.Rotation end
			b:PivotTo(cf)
		end
	end
end

-- the hammer comes down on top of whatever is on the anvil
function Retread:strikeHeight(): number
	local room = self.ws.room
	local top = 0.62
	for _, blk in pairs(self.blocks) do
		if blk.Parent then
			top = math.max(top, (blk:GetPivot().Position.Y - room.strikePoint.Y) + heightOf(blk) + 0.02)
		end
	end
	if self.result and self.result.Parent then
		top = math.max(top, (self.result:GetPivot().Position.Y - room.strikePoint.Y) + heightOf(self.result) + 0.02)
	end
	return top
end

-- down (on the work), raised, cocked (wound back past raised) and recoil (bounced off).
-- The head's flat face is on the mesh's +X side and the claw on -X, so +X points down.
function Retread:hammerPoses(): (CFrame, CFrame, CFrame, CFrame)
	local room = self.ws.room
	local h = room.hammer
	local target = room.strikePoint + Vector3.new(0, self:strikeHeight(), 0)
	local up = Vector3.yAxis
	local dir = Vector3.new(-1, 0, -0.35).Unit
	local k = h.Size.Y / 1.315
	local down = CFrame.fromMatrix(target + up * 0.27 * k - dir * 0.56 * k, -up, dir)
	local grip = down.Position + dir * (-0.5 * k)
	local axis = up:Cross(dir)
	local function swing(deg: number): CFrame
		return CFrame.new(grip) * CFrame.fromAxisAngle(axis, math.rad(deg)) * CFrame.new(-grip) * down
	end
	return down, swing(-70), swing(-96), swing(-22)
end

function Retread:moveHammer(to: CFrame, dur: number, ease: ((number) -> number)?): boolean
	local h = self.ws.room.hammer
	local from = h.CFrame
	local ok = self:tween(dur, function(k)
		h.CFrame = from:Lerp(to, (ease or easeOutCubic)(k))
	end)
	h.CFrame = to
	return ok
end

-- the timing bar; onFrame keeps the cocked hammer trembling while you wait
function Retread:sweep(onFrame: ((number) -> ())?): number
	local center = 0.2 + math.random() * 0.6
	self.sweet.Position = UDim2.fromScale(center, 0)
	local t = 0
	local hit: number? = nil
	local grace = os.clock() + 0.2
	local conn = UserInputService.InputBegan:Connect(function(input)
		if os.clock() < grace or hit then return end
		local k = input.KeyCode
		if isPress(input) or k == Enum.KeyCode.Space or k == Enum.KeyCode.ButtonA then
			local v = math.abs(((t / Config.Forge.SweepSeconds) % 2) - 1)
			hit = 1 - math.clamp(math.abs(v - center) / (Config.Forge.SweetWidth * 1.5), 0, 1)
		end
	end)
	while not hit and t < Config.Forge.SweepSeconds * 4 and self.active do
		t += frameWait()
		local v = math.abs(((t / Config.Forge.SweepSeconds) % 2) - 1)
		self.marker.Position = UDim2.fromScale(v, 0.5)
		if onFrame then onFrame(t) end
	end
	conn:Disconnect()
	return hit or 0
end

--==============================================================
-- tongs
--==============================================================
local TONG_TILT = CFrame.Angles(0, 0, math.rad(-12))
-- the jaws close this far up whatever they hold: just under the top of its handle
local JAW_H = 0.93

-- The tongs taking hold of something whose base is at pos, h tall. The jaw tips meet at the
-- handle and close across it: yaw turns the tongs so their jaws close along its Z, which
-- for a toolbox is across the handle bar. lean tips them about the jaws as a load swings.
local function gripAt(room, pos: Vector3, h: number, clamp: number, yaw: CFrame?, lean: CFrame?): CFrame
	local jaw = (room and room.tongsJaw) or Vector3.zero
	return CFrame.new(pos + Vector3.new(0, h * JAW_H, 0)) * (lean or CFrame.identity) * (yaw or CFrame.identity)
		* TONG_TILT * CFrame.Angles(math.rad(clamp), 0, 0) * CFrame.new(-jaw)
end

local function newSway()
	return { x = 0, z = 0, vx = 0, vz = 0, last = nil :: Vector3?, lastV = Vector3.zero }
end
local function stepSway(s, pos: Vector3, dt: number)
	if dt <= 0 then return end
	local v = s.last and (pos - s.last) / dt or Vector3.zero
	local a = (v - s.lastV) / math.max(dt, 1 / 240)
	s.last, s.lastV = pos, v
	local tx = math.clamp(a.Z * 0.0022 + v.Z * 0.018, -0.45, 0.45)
	local tz = math.clamp(-a.X * 0.0022 - v.X * 0.018, -0.45, 0.45)
	s.vx += (tx - s.x) * 110 * dt
	s.vx *= math.exp(-dt * 6)
	s.x += s.vx * dt
	s.vz += (tz - s.z) * 110 * dt
	s.vz *= math.exp(-dt * 6)
	s.z += s.vz * dt
end

--==============================================================
-- the forge
--==============================================================
-- the tray drops off the bottom of the screen for the show; the strike bar rides along
-- at the bottom edge
function Retread:trayAway(away: boolean)
	local rest = UDim2.new(0.5, 0, 1, -10)
	UI.tween(self.frame, away and 0.35 or 0.4, { Position = away and UDim2.new(0.5, 0, 1, 330) or rest },
		away and Enum.EasingStyle.Quad or Enum.EasingStyle.Back, away and Enum.EasingDirection.In or Enum.EasingDirection.Out)
end

-- an offset in the room's own frame: x across, y up, z out toward the front of the room.
-- Every shot of the forge sits in the open front of the smithy corner.
function Retread:off(x: number, y: number, z: number): Vector3
	return self.ws.room.origin:VectorToWorldSpace(Vector3.new(x, y, z))
end

-- the flat sideways direction from dir that faces into the room
function Retread:frontSide(dir: Vector3): Vector3
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 then return self:off(1, 0, 0) end
	local p = Vector3.new(-flat.Z, 0, flat.X).Unit
	if p:Dot(self:off(0, 0, 1)) < 0 then p = -p end
	return p
end

-- when a load isn't swinging, what swing it had dies away instead of freezing
local function calmSway(s, dt: number)
	local d = math.exp(-dt * 10)
	s.x *= d
	s.z *= d
	s.vx *= d
	s.vz *= d
	s.last = nil
	s.lastV = Vector3.zero
end

-- before the reveal a new box glows and cools as plain steel, so its rarity stays a secret
local STEEL = Color3.fromRGB(214, 206, 196)
-- how far each model has to turn for its front to face along its LookVector
local FRONT_YAW = { Toolbox = math.pi, ToolboxRed = math.pi, ToolboxBlue = math.pi, Boombox = math.pi }

-- a box standing at pos, turned so its front faces the workbench camera
function Retread:facingCamera(pos: Vector3, m: Model?): CFrame
	local room = self.ws.room
	local eye = room.stations.Retread.cf.Position
	local flat = Vector3.new(eye.X - pos.X, 0, eye.Z - pos.Z)
	if flat.Magnitude < 1e-3 then flat = self:off(0, 0, 1) end
	local turn = m and FRONT_YAW[(m:GetAttribute("Model") :: string?) or ""] or 0
	return CFrame.lookAt(pos, pos + flat.Unit) * CFrame.Angles(0, turn, 0)
end

function Retread:forge()
	if self.forging or not self.active then return end
	local uids = {}
	for i = 1, Config.Forge.Inputs do
		if not self.inputs[i] then
			self.ws:toast("Three toolboxes on the anvil first.", T.bad)
			return
		end
		uids[i] = self.inputs[i]
	end
	local first = self:boxByUid(uids[1])
	for i = 2, #uids do
		local b = self:boxByUid(uids[i])
		if not (first and b) or first.rarity ~= b.rarity then
			self.ws:toast("All three need the same rarity.", T.bad)
			return
		end
	end
	if not first or first.rarity == TOP_RARITY then
		self.ws:toast(MAXED, T.bad)
		return
	end

	local ws = self.ws
	local room = ws.room
	local fromColor = Config.ToolboxRaritiesById[first.rarity].color
	self.forging = true
	self.phase = "strike"
	self:clearResult()
	self:refresh()
	self:trayAway(true)

	local ok = self:loadAndHeat(fromColor)
	local hits = {}
	if ok then ok, hits = self:strikes(fromColor) end
	for i = #hits + 1, Config.Forge.Strikes do hits[i] = 0 end

	-- the server decides while the stack shudders white-hot and the camera creeps in
	local res: any = nil
	local answered = false
	task.spawn(function()
		res = ws:call("Forge", uids, hits)
		answered = true
	end)
	task.spawn(function() self:moveHammer(room.hammerRest, 0.5, easeInOut) end)

	local S = room.strikePoint
	local up = Vector3.yAxis
	local stackBase = CFrame.new(S)
	ws:shot(S + self:off(-3.1, 1.5, 4.4), S + up * 0.6, 34, 3)
	local shakeT = 0
	local function shudder(dt: number)
		shakeT += dt
		local k = math.min(1, shakeT / 0.45)
		for _, b in pairs(self.blocks) do
			if b.Parent then setHeat(b, 0.85 + 0.15 * k, fromColor) end
		end
		local j = 0.05 * k
		local c = os.clock()
		local jitter = CFrame.new(math.noise(c * 40, 1) * j, 0, math.noise(c * 40, 7) * j)
			* CFrame.Angles(0, math.noise(c * 33, 3) * 0.12 * k, 0)
		self:setStack(stackBase * jitter, 1, 1)
	end
	local shook = self:tween(0.45, function(_, dt) shudder(dt) end)
	local waited = 0
	while not answered and waited < 5 and self.active do
		local dt = frameWait()
		waited += dt
		shudder(dt)
	end

	if not (shook and ok and res and res.ok and res.result) then
		-- nothing made: the boxes cool, spread back out, and it's over
		for _, b in pairs(self.blocks) do
			if b.Parent then setHeat(b, 0, fromColor) end
			b:Destroy()
		end
		self.blocks, self.homes = {}, {}
		self.forging = false
		self.phase = nil
		ws:shot(nil)
		if room.hammer then room.hammer.CFrame = room.hammerRest end
		if room.tongs and room.tongsRest then room.tongs:PivotTo(room.tongsRest) end
		if res and res.err then ws:toast(res.err, T.bad) end
		self:trayAway(false)
		self:refresh()
		return
	end

	local outBox = res.result
	local rar = Config.ToolboxRaritiesById[outBox.rarity]
	local kind = Config.ToolboxKindsById[outBox.kind]
	self.inputs = {}

	-- three become one: the stack swells, folds into the middle in a burst of sparks, and
	-- the new box pops up out of it spinning and drops onto the anvil facing you
	ws:shot(S + self:off(-3.6, 2.2, 5.4), S + up * 0.6, 38, 7)
	local starts = {}
	for i, b in pairs(self.blocks) do starts[i] = { cf = b:GetPivot(), scale = b:GetScale() } end
	self:tween(0.16, function(k)
		local e = easeOutCubic(k)
		for i, b in pairs(self.blocks) do
			local s0 = starts[i]
			if b.Parent and s0 then b:ScaleTo(s0.scale * (1 + 0.08 * e)) end
		end
	end)
	for i, b in pairs(self.blocks) do
		if b.Parent and starts[i] then starts[i].scale = b:GetScale() end
	end
	local core = CFrame.new(S + up * 0.3)
	self:tween(0.12, function(k)
		local e = easeInCubic(k)
		for i, b in pairs(self.blocks) do
			local s0 = starts[i]
			if b.Parent and s0 then
				b:ScaleTo(s0.scale * (1 - 0.72 * e))
				b:PivotTo(s0.cf:Lerp(core * s0.cf.Rotation * CFrame.Angles(0, 1.2, 0), e))
			end
		end
	end)
	if VFX.has("Sparks") then
		VFX.emit("Sparks", CFrame.new(S + up * 0.4), { scale = 1, countMult = 2.4, parent = room.folder })
		task.delay(0.07, function()
			VFX.emit("Sparks", CFrame.new(S + up * 0.3), { scale = 0.7, countMult = 1.5, color = HOT, parent = room.folder })
		end)
	end
	self:emitter("embers", S + up * 0.4, 44, 1.6)
	self:punch(0.9, 7)
	self:hitstop(0.1)
	for i, b in pairs(self.blocks) do
		b:Destroy()
		self.blocks[i] = nil
		self.homes[i] = nil
	end

	local m = self:box(rar.color, 1.3, outBox.kind, outBox.rarity)
	local restCF = self:facingCamera(S, m)
	local scale1 = m:GetScale()
	m:ScaleTo(scale1 * 0.25)
	m:PivotTo(restCF)
	setHeat(m, 1, STEEL)
	m.Parent = room.folder
	self.result = m
	self.keepResult = true
	self.phase = "quench"
	self.outText.Text = "STILL HOT"
	self.outText.TextColor3 = HOT
	self.outSub.Text = "INTO THE BUCKET"
	self.outEdge.ImageColor3 = HOT
	self:refresh()
	local turns = math.pi * 2
	self:tween(0.3, function(k)
		local e = easeOutCubic(k)
		m:ScaleTo(scale1 * (0.25 + 0.75 * easeOutBack(math.min(1, k * 1.4))))
		m:PivotTo(restCF * CFrame.new(0, 1.1 * e, 0) * CFrame.Angles(0, turns * e, 0))
	end)
	self:tween(0.16, function(k)
		m:PivotTo(restCF * CFrame.new(0, 1.1 * (1 - easeInCubic(k)), 0))
	end)
	m:PivotTo(restCF)
	m:ScaleTo(scale1)
	self:punch(0.35, 2.5)
	if VFX.has("Sparks") then VFX.emit("Sparks", CFrame.new(S + up * 0.1), { scale = 0.35, countMult = 0.7, parent = room.folder }) end
	self:tween(0.2, function(k) m:ScaleTo(scale1 * (1 - 0.12 * (1 - easeOutBack(k)))) end)
	m:ScaleTo(scale1)

	self:quench(m)
	self:revealOnAnvil(m, rar, kind, outBox)
	ws:shot(nil)
	self:trayAway(false)
	if room.hammer then room.hammer.CFrame = room.hammerRest end
	self.phase = nil
	self.forging = false
	self:refresh()
	self.keepResult = false
end

-- The three hop into a stack. The tongs close on the top box's handle, carry the stack over
-- and slide it end first into the furnace mouth, work it in the fire until it glows, and set
-- it back down on the anvil with a clank.
function Retread:loadAndHeat(fromColor: Color3): boolean
	local ws = self.ws
	local room = ws.room
	local S = room.strikePoint
	local base = CFrame.new(S)
	local up = Vector3.yAxis
	ws:shot(S + self:off(-4.2, 2.1, 6.4), S + up * 0.5, 40, 4)

	-- each box dips, hops to its place and lands with a squash; the hops overlap
	local DIP, HOP, SETTLE, GAP = 0.08, 0.3, 0.18, 0.17
	local jobs = {}
	for i = 1, Config.Forge.Inputs do
		local b = self.blocks[i]
		if b and b.Parent then
			b:SetAttribute("Scale0", b:GetScale())
			b:SetAttribute("Height0", heightOf(b))
			table.insert(jobs, {
				b = b, from = b:GetPivot(), to = (self:stackPose(i, base, 0, heightOf(b))),
				scale0 = b:GetScale(), t0 = #jobs * GAP, lift = 0.9 + 0.3 * i, landed = false,
			})
		end
	end
	local total = (#jobs > 0 and jobs[#jobs].t0 or 0) + DIP + HOP + SETTLE
	if not self:tween(total, function(k)
		local t = k * total
		for _, j in ipairs(jobs) do
			local lt = t - j.t0
			if lt <= 0 then continue end
			if lt < DIP then
				local e = math.sin(lt / DIP * math.pi / 2)
				j.b:ScaleTo(j.scale0 * (1 - 0.07 * e))
				j.b:PivotTo(j.from * CFrame.Angles(math.rad(-5) * e, 0, 0))
			elseif lt < DIP + HOP then
				local u = (lt - DIP) / HOP
				local arc = 4 * u * (1 - u)
				j.b:ScaleTo(j.scale0 * (1 + 0.04 * arc))
				local p = j.from.Position:Lerp(j.to.Position, easeInOut(u)) + up * (arc * j.lift)
				local r = j.from.Rotation:Lerp(j.to.Rotation, u) * CFrame.Angles(math.rad(22) * arc, 0, math.rad(-8) * arc)
				j.b:PivotTo(CFrame.new(p) * r)
			else
				if not j.landed then
					j.landed = true
					self:punch(0.1, 0.8)
				end
				local u = math.clamp((lt - DIP - HOP) / SETTLE, 0, 1)
				j.b:PivotTo(j.to)
				j.b:ScaleTo(j.scale0 * (1 - 0.1 * (1 - easeOutBack(u))))
			end
		end
	end) then return false end
	for _, j in ipairs(jobs) do
		if j.b.Parent then j.b:ScaleTo(j.scale0) end
	end
	self:setStack(base, 0, 1)

	local tongs, rest = room.tongs, room.tongsRest
	local F = room.furnace
	local H = 0
	for _, b in pairs(self.blocks) do H = math.max(H, (b:GetPivot().Position.Y - S.Y) + heightOf(b)) end
	if not (tongs and rest and F) then
		-- no furnace to hand: they heat where they sit
		return self:tween(0.7, function(k)
			for _, b in pairs(self.blocks) do setHeat(b, 0.7 * k, fromColor) end
		end)
	end

	local out = F.out
	local side = self:frontSide(out)
	-- the stack goes in end first, its length along the mouth. sign picks the shorter turn.
	local sign = out:Dot(self:off(1, 0, 0)) >= 0 and 1 or -1
	local faceIn = CFrame.fromMatrix(Vector3.zero, out * sign, up)
	-- the top box lies across the stack, so its handle runs along the stack's Z and the
	-- jaws close along the stack's X
	local ACROSS = CFrame.Angles(0, math.rad(90), 0)
	-- about half the stack goes in, so its glowing outer end stays in view
	local inside = Vector3.new(F.centre.X, F.floorY + 0.06, F.centre.Z) + out * (F.lip + 0.2)
	local approach = inside + out * 2.4
	local lifted = S + up * 1.9
	local offsets = {}
	for i, b in pairs(self.blocks) do offsets[i] = base:ToObjectSpace(b:GetPivot()) end
	local sway = newSway()
	-- pos is the middle of the stack's base
	local function carry(pos: Vector3, rot: CFrame, dt: number, swing: boolean, clamp: number?)
		local jawAt = pos + up * (H * JAW_H)
		if swing then stepSway(sway, jawAt, dt) else calmSway(sway, dt) end
		local lean = CFrame.Angles(sway.x * 0.35, 0, sway.z * 0.35)
		tongs:PivotTo(gripAt(room, pos, H, clamp or 10, rot * ACROSS, lean))
		local hang = CFrame.new(jawAt) * CFrame.Angles(sway.x, 0, sway.z) * CFrame.new(0, -H * JAW_H, 0) * rot
		for i, b in pairs(self.blocks) do
			if offsets[i] then b:PivotTo(hang * offsets[i]) end
		end
	end

	-- the tongs swing up off the stump, come down over the top box and close on its handle
	local restCF = tongs:GetPivot()
	local hover = gripAt(room, S, H, 0, ACROSS) + up * 0.6
	local peak = (restCF.Position + hover.Position) / 2 + up * 1.6
	if not self:tween(0.36, function(k)
		local e = easeOutCubic(k)
		tongs:PivotTo(CFrame.new(bezier(restCF.Position, peak, hover.Position, e)) * restCF.Rotation:Lerp(hover.Rotation, e))
	end) then return false end
	if not self:tween(0.12, function(k)
		tongs:PivotTo(hover:Lerp(gripAt(room, S, H, 10, ACROSS), easeInCubic(k)))
	end) then return false end

	-- up with a jerk, then across to the furnace in an arc, turning end first on the way
	local wideEye = (S + F.mouth) / 2 + self:off(-1.4, 3.4, 8.8)
	ws:shot(wideEye, S + up * 0.8, 42, 4)
	if not self:tween(0.22, function(k, dt) carry(S:Lerp(lifted, easeOutBack(k)), CFrame.identity, dt, false) end) then return false end
	local arcMid = (lifted + approach) / 2 + up * 1.8
	if not self:tween(0.62, function(k, dt)
		local e = easeInOut(k)
		local p = bezier(lifted, arcMid, approach, e)
		carry(p, CFrame.identity:Lerp(faceIn, e), dt, true)
		ws:shot(wideEye, p:Lerp(F.mouth, 0.35) + up * 0.4, 42, 4.5)
	end) then return false end

	-- the camera comes round to the side of the furnace while the swing settles, so the
	-- stack is seen going into the arch, then in it goes
	local closeEye = F.mouth + out * 4.2 + side * 5.6 + up * 1.8
	local nearEye = F.mouth + out * 3.7 + side * 4.9 + up * 1.4
	local closeLook = F.mouth + out * 0.5 - up * 0.3
	ws:shot(closeEye, closeLook, 40, 4.5)
	if not self:tween(0.14, function(_, dt) carry(approach, faceIn, dt, true) end) then return false end
	if not self:tween(0.3, function(k, dt) carry(approach:Lerp(inside, easeOutCubic(k)), faceIn, dt, false) end) then return false end

	-- in the fire: flames roll in the arch and lick out round the stack, embers spit out of
	-- the mouth, soot leaves the chimney, and it's worked back and forth while it heats
	room.fireGoal = 6
	-- the fire sits where the stack isn't: either side of it in the arch, deeper in behind it,
	-- and tongues curling out under the top of the arch
	local across = self:frontSide(out)
	local fireBase = Vector3.new(F.centre.X, F.floorY, F.centre.Z)
	local fires = {}
	local function fire(preset: string, at: Vector3, size: Vector3, rate: number, lo: number, hi: number, accel: Vector3)
		local p, e = self:emitter(preset, at, math.ceil(rate / 3), 3.6, size)
		p.CFrame = CFrame.lookAt(at, at + out)
		e.Acceleration = accel
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, lo), NumberSequenceKeypoint.new(1, hi) })
		e.Rate = rate * VFX.density()
		table.insert(fires, e)
	end
	for _, s in ipairs({ -1, 1 }) do
		fire("flames", fireBase + out * 2.0 + across * (0.85 * s) + up * 0.2, Vector3.new(0.5, 0.2, 0.5), 14, 0.8, 1.15, out * 0.6 + up * 1.4)
	end
	fire("flames", fireBase + out * 0.9 + up * 0.25, Vector3.new(1.2, 0.2, 1.0), 16, 1.1, 1.5, up * 1.6)
	fire("lick", Vector3.new(F.mouth.X, F.centre.Y + 0.5, F.mouth.Z) + out * 0.05, Vector3.new(0.2, 0.1, 1.2), 12, 0.5, 0.8, out * 2.5 + up)
	local _, sootE = self:emitter("soot", F.top + up * 0.3, 2, 5, Vector3.new(0.8, 0.2, 0.8))
	sootE.Rate = 3 * VFX.density()
	self:emitter("embers", F.mouth + out * 0.3, 14, 1.4, Vector3.new(0.8, 0.8, 0.2), out + up * 0.6)
	self:punch(0.2, 1)
	local spit = 0
	local heated = self:tween(1.15, function(k, dt)
		for _, b in pairs(self.blocks) do
			local flick = math.noise(os.clock() * 9, b:GetAttribute("Uid") or 0) * 0.08
			setHeat(b, math.clamp(0.9 * easeOutCubic(k) + flick, 0, 1), fromColor)
		end
		spit -= dt
		if spit <= 0 then
			spit = 0.1 + math.random() * 0.08
			self:emitter("embers", F.mouth + out * 0.2, 6, 1.2, Vector3.new(0.8, 0.8, 0.2), out + up * (0.4 + math.random() * 0.6))
		end
		local work = math.sin(k * math.pi * 4) * 0.14 * (1 - 0.5 * k)
		carry(inside + out * work, faceIn * CFrame.Angles(math.sin(k * math.pi * 2) * 0.06, 0, 0), dt, false)
		ws:shot(closeEye:Lerp(nearEye, easeInOut(k)), closeLook, 40 - 3 * k, 4.5)
	end)
	for _, e in ipairs(fires) do e.Rate = 0 end
	sootE.Rate = 0
	room.fireGoal = 2
	if not heated then return false end

	-- out with a yank and a spray of sparks, back over to the anvil, and down with a clank
	if not self:tween(0.2, function(k, dt) carry(inside:Lerp(approach, easeInCubic(k)), faceIn, dt, false) end) then return false end
	if VFX.has("Sparks") then VFX.emit("Sparks", CFrame.new(F.mouth + out * 0.6), { scale = 0.45, color = HOT, countMult = 0.9, parent = room.folder }) end
	local backEye = S + self:off(-4.0, 2.2, 6.2)
	local backMid = (approach + lifted) / 2 + up * 1.9
	if not self:tween(0.56, function(k, dt)
		local e = easeInOut(k)
		local p = bezier(approach, backMid, lifted, e)
		carry(p, faceIn:Lerp(CFrame.identity, e), dt, true)
		ws:shot(backEye, p:Lerp(S, 0.5) + up * 0.4, 40, 4.5)
	end) then return false end
	if not self:tween(0.14, function(k, dt) carry(lifted:Lerp(S, easeInCubic(k)), CFrame.identity, dt, false) end) then return false end
	self:setStack(base, 0, 1)
	self:punch(0.4, 2.5)
	if VFX.has("Sparks") then VFX.emit("Sparks", CFrame.new(S + up * 0.1), { scale = 0.35, countMult = 0.6, parent = room.folder }) end
	self:tween(0.16, function(k) self:setStack(base, 0, 1 - 0.1 * (1 - easeOutBack(k))) end)
	self:setStack(base, 0, 1)

	-- the jaws open, and the tongs lift off the handle and swing back to the stump while the
	-- hammer comes up
	task.spawn(function()
		local from = tongs:GetPivot()
		local openAt = gripAt(room, S, H, -6, ACROSS) + up * 0.45
		self:tween(0.1, function(k) tongs:PivotTo(from:Lerp(openAt, easeOutCubic(k))) end)
		local open = tongs:GetPivot()
		local mid = (open.Position + rest.Position) / 2 + up * 1.4
		self:tween(0.46, function(k)
			local e = easeInOut(k)
			tongs:PivotTo(CFrame.new(bezier(open.Position, mid, rest.Position, e)) * open.Rotation:Lerp(rest.Rotation, e))
		end)
		if tongs.Parent then tongs:PivotTo(rest) end
	end)
	return true
end

-- Three timed blows. Each one: the camera glides to a new angle, the hammer winds back and
-- trembles while the camera leans in, it comes down fast face first, the world freezes for a
-- beat, the stack squashes and springs back a little tighter, and the hammer bounces off.
function Retread:strikes(fromColor: Color3): (boolean, { number })
	local ws = self.ws
	local room = ws.room
	local S = room.strikePoint
	local base = CFrame.new(S)
	local angles = {
		{ eye = self:off(-4.2, 0.95, 4.2), look = Vector3.new(0, 0.7, 0), fov = 40 },
		{ eye = self:off(3.4, 3.3, 4.6), look = Vector3.new(0, 0.5, 0), fov = 38 },
		{ eye = self:off(-2.5, 0.6, 3.9), look = Vector3.new(0.2, 0.9, 0), fov = 33 },
	}
	local hits = {}
	local _, raised, cocked = self:hammerPoses()
	if not self:moveHammer(raised, 0.3, easeOutBack) then return false, hits end
	self.strike.Visible = true
	for i = 1, Config.Forge.Strikes do
		local a = angles[math.min(i, #angles)]
		ws:shot(S + a.eye, S + a.look, a.fov, 5)
		local down: CFrame
		local recoil: CFrame
		down, raised, cocked, recoil = self:hammerPoses()
		if not self:moveHammer(cocked, 0.34, easeOutCubic) then break end
		self.strikeText.Text = ("STRIKE %d OF %d  ·  CLICK OR SPACE ON THE GREEN"):format(i, Config.Forge.Strikes)
		self.strikeText.TextColor3 = T.text
		local hammer = room.hammer
		local h = self:sweep(function(t)
			local shiver = math.noise(t * 6, i) * 0.035
			hammer.CFrame = cocked * CFrame.Angles(shiver, 0, math.noise(t * 5, i + 3) * 0.02)
			local lean = easeOutCubic(math.min(1, t / 1.6))
			ws:shot(S + a.eye * (1 - 0.1 * lean), S + a.look, a.fov - 3 * lean, 5)
		end)
		if not self.active then break end
		hits[i] = h
		-- the blow
		if not self:moveHammer(down, 0.07, easeInCubic) then break end
		local p = i / Config.Forge.Strikes
		self:setStack(base, p, 0.84)
		local impact = S + Vector3.new(0, self:strikeHeight(), 0)
		if VFX.has("Sparks") then
			VFX.emit("Sparks", CFrame.new(impact), { scale = 0.35 + h * 0.5, countMult = 0.6 + h * 1.3, parent = room.folder })
			if h >= 0.8 then
				VFX.emit("Sparks", CFrame.new(impact + Vector3.new(0, -0.2, 0)), { scale = 0.45, countMult = 0.9, color = HOT, parent = room.folder })
			end
		end
		self:emitter("embers", impact, 6 + h * 16, 1.4)
		room.kick = 0.5 + h
		self:punch(0.3 + h * 0.6, 2 + h * 3)
		self:hitstop(0.05 + h * 0.06)
		for _, b in pairs(self.blocks) do setHeat(b, 0.85 + 0.15 * p, fromColor) end
		local call = h >= 0.8 and "CLEAN" or (h >= 0.4 and "OK" or "MISS")
		self.strikeText.Text = ("STRIKE %d:  %s"):format(i, call)
		self.strikeText.TextColor3 = h >= 0.8 and T.good or (h >= 0.4 and T.warn or T.bad)
		task.spawn(function()
			self:tween(0.2, function(k) self:setStack(base, p, 0.84 + 0.16 * easeOutBack(k)) end)
			self:setStack(base, p, 1)
		end)
		if not self:moveHammer(recoil, 0.1, easeOutCubic) then break end
		if not self:moveHammer(raised, 0.22, easeInOut) then break end
	end
	self.strike.Visible = false
	return self.active, hits
end

--==============================================================
-- the quench
--==============================================================
-- The tongs close on the hot box's handle, yank it up and swing it over to the bucket while
-- the camera follows. A beat over the water as the camera drops low, then it plunges: a
-- splash, rings on the water, a plume of steam, the water boiling while the tongs shake. It
-- rises dripping, cooled to plain steel, and is carried back to the anvil, turning to face
-- you as it's set down.
function Retread:quench(result: Model)
	local ws = self.ws
	local room = ws.room
	local tongs = room and room.tongs
	if not (tongs and room.tongsRest and room.quenchTop and result.Parent) then return end
	self.quenching = true
	local _, bsize = result:GetBoundingBox()
	local Hb = bsize.Y
	local home = result:GetPivot()
	local rot = home.Rotation
	local rest = room.tongsRest
	local q = room.quenchTop
	local S = home.Position
	local up = Vector3.yAxis
	local lifted = S + up * 2.1
	local over = q + up * 2.4
	local dunk = q - up * math.min(1.25, Hb + 0.45)
	local held = q + up * 1.8
	local sway = newSway()
	local wideEye = (S + q) / 2 + self:off(-1.6, 3.8, 8.4)

	local function hold(pos: Vector3, dt: number, clamp: number, swing: boolean, jitter: Vector3?)
		local p = pos + (jitter or Vector3.zero)
		local jawAt = p + up * (Hb * JAW_H)
		if swing then stepSway(sway, jawAt, dt) else calmSway(sway, dt) end
		local lean = CFrame.Angles(sway.x * 0.35, 0, sway.z * 0.35)
		tongs:PivotTo(gripAt(room, p, Hb, clamp, rot, lean))
		result:PivotTo(CFrame.new(jawAt) * CFrame.Angles(sway.x, 0, sway.z) * CFrame.new(0, -Hb * JAW_H, 0) * rot)
	end
	local function done()
		self.quenching = false
		if tongs.Parent then tongs:PivotTo(rest) end
	end

	-- the tongs come down over the handle and close on it
	ws:shot(wideEye, S + up * 0.6, 42, 4)
	local from = tongs:GetPivot()
	local hover = gripAt(room, S, Hb, 0, rot) + up * 0.6
	local peak = (from.Position + hover.Position) / 2 + up * 1.6
	if not self:tween(0.36, function(k)
		local e = easeOutCubic(k)
		tongs:PivotTo(CFrame.new(bezier(from.Position, peak, hover.Position, e)) * from.Rotation:Lerp(hover.Rotation, e))
	end) then return done() end
	if not self:tween(0.12, function(k) tongs:PivotTo(hover:Lerp(gripAt(room, S, Hb, 10, rot), easeInCubic(k))) end) then return done() end
	-- wisps of steam off the hot box while it travels
	local trail, trailE = self:emitter("steam", S + up * Hb, 0, 9, Vector3.new(0.5, 0.2, 0.5))
	trailE.Rate = 5 * VFX.density()
	trailE.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	local function trailAt()
		if trail.Parent then trail.CFrame = CFrame.new(result:GetPivot().Position + up * (Hb * 0.9)) end
	end

	-- yank up, then an arc over to the bucket with the box swinging behind
	if not self:tween(0.22, function(k, dt) hold(S:Lerp(lifted, easeOutBack(k)), dt, 10, false); trailAt() end) then return done() end
	local arcMid = (lifted + over) / 2 + up * 1.8
	if not self:tween(0.62, function(k, dt)
		local p = bezier(lifted, arcMid, over, easeInOut(k))
		hold(p, dt, 10, true)
		trailAt()
		ws:shot(wideEye, p:Lerp(q, 0.35) + up * 0.2, 42, 4.5)
	end) then return done() end
	-- a beat over the water while the swing settles and the camera drops in low
	local lowEye = q + self:off(-4.4, 2.7, 4.8)
	ws:shot(lowEye, q + up * 0.5, 38, 6)
	if not self:tween(0.26, function(_, dt) hold(over, dt, 10, true); trailAt() end) then return done() end

	-- plunge: the splash, rings spreading on the water, and a plume of steam
	if not self:tween(0.12, function(k, dt) hold(over:Lerp(dunk, easeInCubic(k)), dt, 10, false); trailAt() end) then return done() end
	trailE.Rate = 0
	self:emitter("splash", q + up * 0.35, 3, 1.2, Vector3.new(1.2, 0.1, 1.2))
	self:emitter("droplets", q + up * 0.1, 40, 1.2, Vector3.new(1.4, 0.1, 1.4))
	local _, rippleE = self:emitter("ripple", q + up * 0.05, 2, 4, Vector3.new(0.6, 0.05, 0.6))
	rippleE.Rate = 2.5
	local _, plumeE = self:emitter("plume", q + up * 0.4, 4, 5, Vector3.new(1.2, 0.2, 1.2))
	plumeE.Rate = 5 * VFX.density()
	local _, steamE = self:emitter("steam", q + up * 0.5, 3, 6, Vector3.new(1.4, 0.2, 1.4))
	steamE.Rate = 10 * VFX.density()
	local _, bubbleE = self:emitter("bubbles", q, 0, 3, Vector3.new(1.5, 0.1, 1.5))
	bubbleE.Rate = 70 * VFX.density()
	self:punch(0.55, 4)
	self:hitstop(0.07)

	-- it boils: the tongs shake, the steam rolls, the heat drains out of it
	if not self:tween(0.9, function(k, dt)
		local jit = Vector3.new(math.noise(os.clock() * 45, 1), 0, math.noise(os.clock() * 45, 2)) * 0.05 * (1 - k)
		hold(dunk, dt, 10, false, jit)
		setHeat(result, (1 - easeOutCubic(k)) * 0.6, STEEL)
		plumeE.Rate = 5 * (1 - k) * VFX.density()
		steamE.Rate = 10 * (1 - k * 0.6) * VFX.density()
		bubbleE.Rate = 70 * (1 - k) * VFX.density()
		if k > 0.3 and k < 0.35 then ws:shake(0.15) end
	end) then return done() end
	setHeat(result, 0, STEEL)
	plumeE.Rate = 0
	steamE.Rate = 3 * VFX.density()
	bubbleE.Rate = 0
	rippleE.Rate = 1

	-- up out of the steam, slowly, dripping
	local _, dripE = self:emitter("drips", dunk, 0, 4, Vector3.new(0.8, 0.1, 0.8))
	local dripPart = dripE.Parent :: BasePart
	dripE.Rate = 30 * VFX.density()
	if not self:tween(0.7, function(k, dt)
		hold(dunk:Lerp(held, easeOutCubic(k)), dt, 10, false)
		dripPart.CFrame = CFrame.new(result:GetPivot().Position)
		dripE.Rate = 30 * (1 - 0.5 * k) * VFX.density()
	end) then return done() end
	rippleE.Rate = 0

	-- back to the anvil, turning to face you on the way, and down with a settle
	local faceRot = self:facingCamera(S, result).Rotation
	local startRot = rot
	local backMid = (held + lifted) / 2 + up * 1.6
	if not self:tween(0.56, function(k, dt)
		local e = easeInOut(k)
		rot = startRot:Lerp(faceRot, e)
		local p = bezier(held, backMid, lifted, e)
		hold(p, dt, 10, true)
		dripPart.CFrame = CFrame.new(result:GetPivot().Position)
		dripE.Rate = 15 * (1 - k) * VFX.density()
		ws:shot(wideEye, p:Lerp(S, 0.4) + up * 0.3, 42, 4.5)
	end) then return done() end
	dripE.Rate = 0
	steamE.Rate = 0
	rot = faceRot
	if not self:tween(0.15, function(k, dt) hold(lifted:Lerp(S, easeInCubic(k)), dt, 10, false) end) then return done() end
	result:PivotTo(CFrame.new(S) * rot)
	self:punch(0.2, 1.5)
	local scale0 = result:GetScale()
	task.spawn(function()
		self:tween(0.2, function(k) if result.Parent then result:ScaleTo(scale0 * (1 - 0.08 * (1 - easeOutBack(k)))) end end)
		if result.Parent then result:ScaleTo(scale0) end
	end)
	-- jaws open, the tongs lift off the handle and swing home
	local open = gripAt(room, S, Hb, -6, rot) + up * 0.45
	local from2 = tongs:GetPivot()
	self:tween(0.1, function(k) tongs:PivotTo(from2:Lerp(open, easeOutCubic(k))) end)
	local mid2 = (open.Position + rest.Position) / 2 + up * 1.4
	self:tween(0.46, function(k)
		local e = easeInOut(k)
		tongs:PivotTo(CFrame.new(bezier(open.Position, mid2, rest.Position, e)) * open.Rotation:Lerp(rest.Rotation, e))
	end)
	done()
end

-- The reveal: with the box sat on the anvil facing you, the camera pushes slowly in on it.
-- As it arrives the outline floods with the rarity's colour, sparks in that colour fly off
-- it, it gives a little hop, and the stamp lands.
function Retread:revealOnAnvil(m: Model, rar, kind, outBox)
	local ws = self.ws
	local room = ws.room
	if not m.Parent then return end
	local up = Vector3.yAxis
	local S = room.strikePoint
	local _, size = m:GetBoundingBox()
	local eye = room.stations.Retread.cf.Position
	local flat = Vector3.new(eye.X - S.X, 0, eye.Z - S.Z)
	local toward = flat.Magnitude > 1e-3 and flat.Unit or self:off(0, 0, 1)
	local look = S + up * (size.Y * 0.5)
	local farEye = S + toward * 6.2 + up * 2.6
	local nearEye = S + toward * 4.3 + up * 1.55
	ws:shot(farEye, look, 38, 4)
	self:tween(0.35, function() end)
	local revealed = false
	local rest = m:GetPivot()
	local scale0 = m:GetScale()
	self:tween(1.5, function(k)
		local e = easeInOut(k)
		ws:shot(farEye:Lerp(nearEye, e), look, 38 - 6 * e, 6)
		if not revealed and k >= 0.72 then
			revealed = true
			self:punch(0.35, 2.5)
			if VFX.has("Sparks") then
				VFX.emit("Sparks", rest + up * (size.Y * 0.6), { scale = 0.6, color = rar.color, countMult = 1.8, parent = room.folder })
			end
			room:pulse(rar.color, math.max(1, LEVEL[outBox.rarity] or 1))
			self.outText.Text = ("%s %s"):format(string.upper(rar.name), string.upper(kind.name))
			self.outText.TextColor3 = rar.color
			self.outSub.Text = ("QUALITY %.2f  ·  +%d%% %s"):format(outBox.q, math.floor(rar.bonus * outBox.q * 100 + 0.5), string.upper(kind.label))
			self.outEdge.ImageColor3 = rar.color
			UI.stamp(ws.gui, ("%s %s"):format(rar.name, kind.name), rar.color, ("QUALITY %.2f  ·  FORGED"):format(outBox.q))
			task.spawn(function()
				-- the outline floods with colour while the box hops
				local hopT = 0
				while hopT < 0.45 and m.Parent do
					local dt = frameWait()
					hopT += dt
					local u = math.min(1, hopT / 0.45)
					setHeat(m, 0, STEEL:Lerp(rar.color, easeOutCubic(math.min(1, u * 1.6))))
					local hop = math.sin(u * math.pi) * 0.35
					m:PivotTo(rest * CFrame.new(0, hop, 0))
					m:ScaleTo(scale0 * (1 + 0.06 * math.sin(u * math.pi)))
				end
				if m.Parent then
					m:PivotTo(rest)
					m:ScaleTo(scale0)
					setHeat(m, 0, rar.color)
				end
			end)
		end
	end)
	if m.Parent then setHeat(m, 0, rar.color) end
	-- a moment to take it in, drifting a touch closer
	self:tween(0.9, function(k)
		ws:shot(nearEye:Lerp(S + toward * 3.95 + up * 1.45, k), look, 32, 3)
	end)
end

--==============================================================
-- tray
--==============================================================
function Retread:refresh()
	local p = self.ws.profile
	if not p then return end
	local sameRarity: any = nil
	for i = 1, Config.Forge.Inputs do
		local tb = self:boxByUid(self.inputs[i])
		if self.inputs[i] and not tb then self.inputs[i] = nil end
		local s = self.slots[i]
		if tb then
			local rar = Config.ToolboxRaritiesById[tb.rarity]
			local kind = Config.ToolboxKindsById[tb.kind]
			s.name.Text = string.upper(kind.name)
			s.name.TextColor3 = rar.color
			s.sub.Text = ("%s  Q%.2f"):format(string.upper(rar.name), tb.q or 1)
			s.edge.ImageColor3 = rar.color
			if sameRarity == nil then
				sameRarity = tb.rarity
			elseif sameRarity ~= tb.rarity then
				sameRarity = false
			end
		else
			s.name.Text = "EMPTY"
			s.name.TextColor3 = T.faint
			s.sub.Text = "tap a box below"
			s.edge.ImageColor3 = T.line
		end
	end
	local full = true
	for i = 1, Config.Forge.Inputs do
		if not self.inputs[i] then full = false end
	end
	if not self.keepResult then
		if full and sameRarity then
			local nextR = Config.ToolboxRarities[(RARITY_INDEX[sameRarity] or 99) + 1]
			if nextR then
				local article = nextR.name:match("^[AEIOUaeiou]") and "AN " or "A "
				self.outText.Text = "MAKES " .. article .. string.upper(nextR.name)
				self.outText.TextColor3 = nextR.color
				self.outSub.Text = ("QUALITY %.2f TO %.2f"):format(Config.Forge.QualityMin, Config.Forge.QualityMax)
				self.outEdge.ImageColor3 = nextR.color
			else
				self.outText.Text = "ALREADY MAXED"
				self.outText.TextColor3 = T.bad
				self.outSub.Text = "LEGENDARY CAN'T BE FORGED"
				self.outEdge.ImageColor3 = T.line
			end
		elseif not self.forging then
			self.outText.Text = full and "RARITIES DON'T MATCH" or "PUT THREE ON THE ANVIL"
			self.outText.TextColor3 = full and T.bad or T.faint
			self.outSub.Text = ""
			self.outEdge.ImageColor3 = T.line
		end
	end
	local ready = full and sameRarity and Config.ToolboxRarities[(RARITY_INDEX[sameRarity] or 99) + 1] ~= nil
	UI.setButtonStyle(self.forgeButton, (ready and not self.forging) and "primary" or "off")
	self.forgeButton.Text = self.forging and (self.phase == "quench" and "QUENCHING" or "STRIKING") or "FORGE"

	-- the drawer: one card per kind and rarity, with how many you have
	for _, c in ipairs(self.drawer:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local used = {}
	for i = 1, Config.Forge.Inputs do
		if self.inputs[i] then used[self.inputs[i]] = true end
	end
	local fitted = {}
	for _, u in pairs(p.equipped or {}) do fitted[u] = true end
	local groups, order = {}, {}
	for _, tb in ipairs(p.toolboxes or {}) do
		local key = tb.rarity .. "|" .. tb.kind
		local g = groups[key]
		if not g then
			g = { rarity = tb.rarity, kind = tb.kind, boxes = {} }
			groups[key] = g
			table.insert(order, g)
		end
		table.insert(g.boxes, tb)
	end
	-- forgeable rarities first, lowest up; legendary, which can't go higher, last
	table.sort(order, function(a, b)
		local ta, tb2 = a.rarity == TOP_RARITY, b.rarity == TOP_RARITY
		if ta ~= tb2 then return tb2 end
		local ra, rb = RARITY_INDEX[a.rarity] or 0, RARITY_INDEX[b.rarity] or 0
		if ra ~= rb then return ra < rb end
		return a.kind < b.kind
	end)
	if #order == 0 then
		local l = UI.text("No toolboxes yet. They turn up out on the road.", 15, "body", T.dim)
		l.Size = UDim2.fromOffset(420, 60)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.ZIndex = 23
		l.Parent = self.drawer
	end
	for i, g in ipairs(order) do
		local rar = Config.ToolboxRaritiesById[g.rarity]
		local kind = Config.ToolboxKindsById[g.kind]
		local top = g.rarity == TOP_RARITY
		local free, onAnvil, fittedCount, best = {}, 0, 0, 0
		for _, tb in ipairs(g.boxes) do
			best = math.max(best, tb.q or 1)
			if used[tb.uid] then onAnvil += 1 else table.insert(free, tb) end
			if fitted[tb.uid] then fittedCount += 1 end
		end
		-- the one that goes on next: not fitted to your rig, then the lowest quality.
		-- Quality from a forge comes from the strikes alone, so your best boxes stay.
		table.sort(free, function(x, y)
			local fx, fy = fitted[x.uid] and 1 or 0, fitted[y.uid] and 1 or 0
			if fx ~= fy then return fx < fy end
			if (x.q or 1) ~= (y.q or 1) then return (x.q or 1) < (y.q or 1) end
			return x.uid < y.uid
		end)
		local dim = top or #free == 0
		local cell = UI.mk("TextButton", {
			Size = UDim2.fromOffset(166, 88), BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
			LayoutOrder = i, ZIndex = 23, Parent = self.drawer,
		})
		local card = UI.mk("Frame", {
			Position = UDim2.fromOffset(4, 5), Size = UDim2.fromOffset(158, 78), BackgroundTransparency = 1,
			ZIndex = 23, Parent = cell,
		})
		UI.plate("card", { Name = "Plate", Size = UDim2.fromScale(1, 1), ImageTransparency = dim and 0.4 or 0, ZIndex = 23, Parent = card })
		local edge = UI.plate("cardTrim", {
			Name = "Trim", Size = UDim2.fromScale(1, 1), ImageColor3 = rar.color,
			ImageTransparency = dim and 0.55 or 0.1, ZIndex = 24, Parent = card,
		})
		centred(card, string.upper(kind.name), 15, "display", top and rar.color:Lerp(T.faint, 0.35) or rar.color, 7, 18)
		centred(card, ("%s  ·  ×%d"):format(string.upper(rar.name), #g.boxes), 11, "monoBold", T.dim, 27, 14)
		local status, statusColor
		if top then
			status, statusColor = "MAX RARITY", T.faint
		elseif #free == 0 then
			status, statusColor = "ALL ON THE ANVIL", T.accent
		elseif onAnvil > 0 then
			status, statusColor = ("%d ON THE ANVIL  ·  TAP FOR MORE"):format(onAnvil), T.accent
		else
			status, statusColor = "TAP TO ADD", T.faint
		end
		centred(card, status, 10, "monoBold", statusColor, 45, 13)
		centred(card, ("BEST Q%.2f%s"):format(best, fittedCount > 0 and ("  ·  %d FITTED"):format(fittedCount) or ""), 10, "monoBold", T.faint, 59, 13)
		if not dim then
			cell.MouseEnter:Connect(function() edge.ImageTransparency = 0 end)
			cell.MouseLeave:Connect(function() edge.ImageTransparency = 0.1 end)
		end
		cell.Activated:Connect(function()
			if self.forging then return end
			if top then
				self.ws:toast(MAXED, T.bad)
				return
			end
			local pick = free[1]
			if not pick then
				self.ws:toast("They're all on the anvil already.", T.bad)
				return
			end
			for k = 1, Config.Forge.Inputs do
				if not self.inputs[k] then
					self.inputs[k] = pick.uid
					self:clearResult()
					self:refresh()
					return
				end
			end
			self.ws:toast("The anvil is full. Tap a slot to take one off.", T.bad)
		end)
	end
	self:syncBlocks()
end

function Retread:enter()
	self.active = true
	local room = self.ws.room
	if room then room.hammer.CFrame = room.hammerRest end
	self:refresh()
end

function Retread:leave()
	self.active = false
	self.quenching = false
	local room = self.ws.room
	if room and room.tongs and room.tongsRest then room.tongs:PivotTo(room.tongsRest) end
	self:clearResult()
	self:syncBlocks()
	self.strike.Visible = false
end

function Retread:setVisible(v: boolean)
	self.frame.Visible = v
end

function Retread:step(_dt: number)
end

return Retread
