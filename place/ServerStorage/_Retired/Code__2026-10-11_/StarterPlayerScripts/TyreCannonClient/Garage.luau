--!strict
-- TYRE CANNON :: Garage
-- The walk-in garage behind every yard's door. Press E at any garage door: the shutter
-- comes down, and you're standing inside that player's garage, built on your client from
-- their save. Nothing in it is bought; it fills up with what happened on their runs:
--   tyre wall      every tyre they own on a hook, chalked with its runs, distance and best
--   rig stand      the build on the rig, turning on a plinth in the middle. Inspect it.
--   trophy shelves one trophy per record, bronze to platinum, and the longest-run photo
--   road signs     a street sign for every road they've set a best on
--   stop sign      pulled off the furthest checkpoint they've reached
--   corkboard      their last run photos, pinned up
--   counter        total distance on a flip counter
--   medals         bronze, silver and gold, with their counts
--   honks          the vuvuzela on a plaque, with how many honks the yard has had
--   guestbook      visitors stamp it; the stamp sits on a shelf underneath
--   bay 2          under a tarp until it's bought; then it holds a second build to swap in
-- It works like the workbench: you don't walk in. The camera moves between set shots of the
-- room (tabs along the top, or keys 1 to 7), and each shot has a tray at the bottom with what
-- it's showing and anything you can do there. Each yard's garage has its own spot far above
-- the map.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Remotes = Root:WaitForChild("Remotes")
local Assets = Root:WaitForChild("Assets")
local Config = require(Modules.Config)
local WheelAssembly = require(Modules.WheelAssembly)
local UI = require(script.Parent.UI)
local RunPhoto = require(script.Parent.RunPhoto)
local PackFX = require(script.Parent.PackFX) :: any
local T = UI.Theme

-- a stand rises out of the floor (or sinks into it) over this long, with a little overshoot
local RISE_TIME, RISE_DEPTH = 0.9, 6
local function backOut(t: number): number
	local c1 = 1.4
	return 1 + (c1 + 1) * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local Garage = {}
Garage.__index = Garage

-- the set shots, in the room's own frame (door wall at +Z, tyre wall at -Z)
local STATIONS = {
	{ id = "Room", label = "ROOM", eye = Vector3.new(15.5, 11.5, 13.5), look = Vector3.new(-6, 5, -7), fov = 62 },
	{ id = "Tyres", label = "TYRES", eye = Vector3.new(0, 12.6, -2), look = Vector3.new(0, 12.6, -16), fov = 58 },
	{ id = "Build", label = "BUILD", eye = Vector3.new(-6.2, 5.8, 6.4), look = Vector3.new(0, 3.3, -3), fov = 42 },
	{ id = "Shelves", label = "SHELVES", eye = Vector3.new(-3.5, 8.8, -1.9), look = Vector3.new(-24, 8.2, -1.9), fov = 58 },
	{ id = "Board", label = "BOARD", eye = Vector3.new(6.5, 9.6, -2), look = Vector3.new(24, 9.4, -2), fov = 58 },
	{ id = "Guestbook", label = "GUESTBOOK", eye = Vector3.new(16.8, 7.9, 5.5), look = Vector3.new(16.8, 7.4, 16), fov = 50 },
	{ id = "Bay", label = "BAY 2", eye = Vector3.new(-3.5, 8.6, 15), look = Vector3.new(-14.2, 0.8, 9.6), fov = 46 },
}
local STATION_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7,
}

-- a critically damped spring, as on the workbench camera
local function spring(x: Vector3, v: Vector3, target: Vector3, w: number, dt: number): (Vector3, Vector3)
	local d = x - target
	local e = math.exp(-w * dt)
	local j = v + d * w
	return target + (d + j * dt) * e, (v - j * (w * dt)) * e
end

local function spring1(x: number, v: number, target: number, w: number, dt: number): (number, number)
	local d = x - target
	local e = math.exp(-w * dt)
	local j = v + d * w
	return target + (d + j * dt) * e, (v - j * (w * dt)) * e
end

-- which way a look points, as a turn and a tilt
local function aim(from: Vector3, to: Vector3): (number, number)
	local d = to - from
	if d.Magnitude < 1e-3 then return 0, 0 end
	d = d.Unit
	return math.atan2(-d.X, -d.Z), math.asin(math.clamp(d.Y, -1, 1))
end

local ORIGIN = CFrame.new(-6400, 2400, 6000)
local WIDTH, DEPTH, HEIGHT = 48, 32, 18
local HALF_W, HALF_D = WIDTH / 2, DEPTH / 2
local M = Config.Physics.StudsToMetres
local STEEL = Color3.fromRGB(150, 154, 160)
local CHALK = Color3.fromRGB(228, 226, 218)
local SLATE = Color3.fromRGB(38, 42, 44)
local PAPER = Color3.fromRGB(236, 230, 214)
local INK = Color3.fromRGB(40, 36, 32)
local LIGHT_KEYS = {
	"Ambient", "OutdoorAmbient", "Brightness", "EnvironmentDiffuseScale",
	"EnvironmentSpecularScale", "ExposureCompensation", "GlobalShadows", "ClockTime",
}

--==============================================================
-- building blocks
--==============================================================
local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- a model from the assets, anchored and inert
local function prop(tpl: Instance?, parent: Instance): Model?
	if not tpl then return nil end
	local m: Model
	if tpl:IsA("Model") then
		m = tpl:Clone()
	elseif tpl:IsA("BasePart") then
		m = Instance.new("Model")
		m.Name = tpl.Name
		tpl:Clone().Parent = m
	else
		return nil
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("ClickDetector") or d:IsA("Camera") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	m.Parent = parent
	return m
end

-- a model's extent along the world axes, however it's turned
local function worldBounds(m: Model): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local c = d.CFrame
			local h = d.Size / 2
			local r, u, l = c.RightVector, c.UpVector, c.LookVector
			local e = Vector3.new(
				math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
				math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
				math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z)
			lo = lo:Min(c.Position - e)
			hi = hi:Max(c.Position + e)
		end
	end
	return lo, hi
end

-- moves a model so the bottom centre of its world extent sits at pos
local function standAt(m: Model, pos: Vector3)
	local lo, hi = worldBounds(m)
	local bottom = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	m:PivotTo(m:GetPivot() + (pos - bottom))
end

local function centreAt(m: Model, pos: Vector3)
	local lo, hi = worldBounds(m)
	m:PivotTo(m:GetPivot() + (pos - (lo + hi) / 2))
end

-- turns a model so that one direction in it (along) comes out as another (to), keeping
-- a second pair (upFrom, upTo) lined up too
local function turn(m: Model, fromX: Vector3, fromY: Vector3, toX: Vector3, toY: Vector3)
	local cur = CFrame.fromMatrix(Vector3.zero, fromX.Unit, fromY.Unit)
	local want = CFrame.fromMatrix(Vector3.zero, toX.Unit, toY.Unit)
	local pivot = m:GetPivot()
	m:PivotTo(CFrame.new(pivot.Position) * (want * cur:Inverse()) * pivot.Rotation)
end

-- where surfaces with a 3D photo on them go: a ViewportFrame only draws in a SurfaceGui
-- that lives under PlayerGui, pointed at its part
local photoLayer: Folder? = nil
local function photoFolder(): Folder
	if photoLayer and photoLayer.Parent then return photoLayer end
	local f = Instance.new("Folder")
	f.Name = "GaragePhotos"
	f.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	photoLayer = f
	return f
end

local function surface(p: BasePart, face: Enum.NormalId, ppu: number, forPhoto: boolean?): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu
	sg.LightInfluence = forPhoto and 0.35 or 1
	sg.MaxDistance = 120
	if forPhoto then
		sg.Adornee = p
		sg.ResetOnSpawn = false
		sg.Parent = photoFolder()
	else
		sg.Parent = p
	end
	return sg
end

local function label(parent: Instance, text: string, size: number, role: string, color: Color3, pos: UDim2, dims: UDim2, align: Enum.TextXAlignment?): TextLabel
	local l = UI.text(text, size, role, color)
	l.Position = pos
	l.Size = dims
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.TextScaled = true
	l.Parent = parent
	UI.mk("UITextSizeConstraint", { MaxTextSize = size, Parent = l })
	return l
end

local function comma(n: number): string
	return UI.comma(math.floor(n + 0.5))
end

local function owned(v, id: string): boolean
	return id == "stock" or (v.skins and v.skins[id] == true)
end

--==============================================================
-- construction
--==============================================================
function Garage.new(gui: ScreenGui, hub, workshop, card)
	local self = setmetatable({}, Garage)
	self.gui = gui
	self.hub = hub
	self.workshop = workshop
	self.card = card
	self.isOpen = false
	self.busy = false
	self.view = nil
	self.conns = {}
	self.prompts = {}
	self.spinners = {}
	self.onEnter = nil
	self.onExit = nil

	-- the shots along the top, and the way out
	local top = UI.mk("Frame", {
		Name = "GarageTop", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(940, 80),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui,
	})
	UI.autoScale(top, 1040, 760)
	self.top = top
	self.title = UI.text("", 12, "monoBold", T.faint)
	self.title.AnchorPoint = Vector2.new(0.5, 0)
	self.title.Position = UDim2.fromScale(0.5, 0)
	self.title.Size = UDim2.new(1, 0, 0, 14)
	self.title.TextXAlignment = Enum.TextXAlignment.Center
	self.title.ZIndex = 31
	self.title.Parent = top
	local tabs = UI.mk("Frame", {
		Name = "Shots", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1, ZIndex = 31, Parent = top,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	self.tabButtons = {}
	for i, st in ipairs(STATIONS) do
		local b = UI.button(st.label, "ghost", 106, 38)
		b.Name = "Shot_" .. st.id
		b.TextSize = 15
		b.LayoutOrder = i
		b.ZIndex = 32
		b.Parent = tabs
		b.Activated:Connect(function()
			if self.isOpen and not self.busy then self:setStation(i) end
		end)
		self.tabButtons[i] = b
	end
	local leave = UI.button("LEAVE", "ghost", 106, 38)
	leave.Name = "GarageLeave"
	leave.TextSize = 15
	leave.LayoutOrder = 99
	leave.ZIndex = 32
	leave.Parent = tabs
	leave.Activated:Connect(function() self:close() end)
	self.sub = UI.text("", 13, "monoBold", T.dim)
	self.sub.AnchorPoint = Vector2.new(0.5, 0)
	self.sub.Position = UDim2.new(0.5, 0, 0, 62)
	self.sub.Size = UDim2.new(1, 0, 0, 16)
	self.sub.TextXAlignment = Enum.TextXAlignment.Center
	self.sub.ZIndex = 31
	self.sub.Parent = top

	-- the tray: what this shot is of, and what you can do there
	local tray = UI.mk("Frame", {
		Name = "GarageTray", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(760, 132),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui,
	})
	UI.autoScale(tray, 1240, 780)
	self.tray = tray
	local function line(size: number, role: string, color: Color3, y: number, h: number): TextLabel
		local l = UI.text("", size, role, color)
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, 0, y)
		l.Size = UDim2.new(1, 0, 0, h)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.TextWrapped = true
		l.ZIndex = 31
		l.Parent = tray
		return l
	end
	self.trayTitle = line(24, "display", T.text, 0, 28)
	self.trayInfo = line(14, "monoBold", T.text:Lerp(T.dim, 0.45), 32, 36)
	-- soft dark bands behind the tabs and the tray, so the words read over any wall
	local function scrim(name: string, edge: number, height: number): Frame
		local f = UI.mk("Frame", {
			Name = name, AnchorPoint = Vector2.new(0.5, edge), Position = UDim2.fromScale(0.5, edge), Size = UDim2.fromScale(1, height),
			BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Visible = false, ZIndex = 29, Parent = gui,
		})
		UI.mk("UIGradient", {
			Rotation = edge == 0 and -90 or 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.72),
				NumberSequenceKeypoint.new(1, 0.28),
			}),
			Parent = f,
		})
		return f
	end
	self.scrims = { scrim("GarageScrimTop", 0, 0.2), scrim("GarageScrimBottom", 1, 0.36) }
	self.trayAction = UI.button("", "primary", 250, 46)
	self.trayAction.AnchorPoint = Vector2.new(0.5, 1)
	self.trayAction.Position = UDim2.fromScale(0.5, 1)
	self.trayAction.TextSize = 17
	self.trayAction.ZIndex = 32
	self.trayAction.Visible = false
	self.trayAction.Parent = tray
	self.trayAction.Activated:Connect(function()
		if self.isOpen and not self.busy and self.actionFn then self.actionFn() end
	end)

	-- the stamp picker
	local picker = UI.panel({
		Name = "StampPicker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 300), Visible = false, ZIndex = 40, Parent = gui,
	})
	UI.autoScale(picker, 640, 380)
	self.picker = picker
	local pt = UI.text("STAMP THE GUESTBOOK", 24, "display", T.text)
	pt.AnchorPoint = Vector2.new(0.5, 0)
	pt.Position = UDim2.new(0.5, 0, 0, 18)
	pt.Size = UDim2.new(1, -40, 0, 28)
	pt.TextXAlignment = Enum.TextXAlignment.Center
	pt.ZIndex = 41
	pt.Parent = picker
	local ps = UI.text("Pick what goes in their book. They see it next time they're in.", 14, "body", T.dim)
	ps.AnchorPoint = Vector2.new(0.5, 0)
	ps.Position = UDim2.new(0.5, 0, 0, 50)
	ps.Size = UDim2.new(1, -40, 0, 18)
	ps.TextXAlignment = Enum.TextXAlignment.Center
	ps.ZIndex = 41
	ps.Parent = picker
	local grid = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 86), Size = UDim2.fromOffset(500, 150),
		BackgroundTransparency = 1, ZIndex = 41, Parent = picker,
	})
	UI.mk("UIGridLayout", {
		CellSize = UDim2.fromOffset(158, 66), CellPadding = UDim2.fromOffset(12, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid,
	})
	for i, s in ipairs(Config.Garage.Stamps) do
		local b = UI.mk("TextButton", {
			Size = UDim2.fromOffset(158, 66), BackgroundColor3 = PAPER, BorderSizePixel = 0, AutoButtonColor = false,
			Text = "", LayoutOrder = i, ZIndex = 42, Parent = grid,
		})
		local ink = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -18, 1, -18),
			BackgroundTransparency = 1, Rotation = (i % 2 == 0) and 4 or -4, ZIndex = 43, Parent = b,
		})
		UI.mk("UIStroke", { Color = s.color, Thickness = 3, Parent = ink })
		local t = UI.text(s.text, 20, "display", s.color)
		t.Size = UDim2.fromScale(1, 1)
		t.TextXAlignment = Enum.TextXAlignment.Center
		t.ZIndex = 44
		t.Parent = ink
		b.MouseEnter:Connect(function() UI.setCursor("point") end)
		b.Activated:Connect(function() self:stamp(s.id) end)
	end
	local cancel = UI.button("NOT NOW", "ghost", 140, 36)
	cancel.AnchorPoint = Vector2.new(0.5, 1)
	cancel.Position = UDim2.new(0.5, 0, 1, -16)
	cancel.TextSize = 14
	cancel.ZIndex = 42
	cancel.Parent = picker
	cancel.Activated:Connect(function() self:showPicker(false) end)

	self.doorShutter = workshop
	return self
end

function Garage:originFor(index: number): CFrame
	return ORIGIN * CFrame.new(0, 0, (math.max(1, index) - 1) * 140)
end

function Garage:at(x: number, y: number, z: number): CFrame
	return self.origin * CFrame.new(x, y, z)
end

function Garage:pos(x: number, y: number, z: number): Vector3
	return self.origin * Vector3.new(x, y, z)
end

function Garage:dir(x: number, y: number, z: number): Vector3
	return self.origin:VectorToWorldSpace(Vector3.new(x, y, z))
end

--==============================================================
-- the room itself: built once, moved to whichever yard's spot is being visited
--==============================================================
function Garage:buildShell()
	if self.folder then return end
	self.origin = ORIGIN
	local folder = Instance.new("Model")
	folder.Name = "GarageRoom"
	folder.WorldPivot = ORIGIN
	self.folder = folder
	local shell = Instance.new("Model")
	shell.Name = "Shell"
	shell.Parent = folder

	local wall = Color3.fromRGB(162, 158, 150)
	local band = Color3.fromRGB(70, 86, 100)
	local stripe = Color3.fromRGB(226, 178, 44)
	-- floor, ceiling and the four walls; the front wall has the door opening in it
	part(shell, "Floor", Vector3.new(WIDTH + 2, 1, DEPTH + 2), self:at(0, -0.5, 0), Color3.fromRGB(116, 114, 110), Enum.Material.Concrete, true)
	part(shell, "Ceiling", Vector3.new(WIDTH + 2, 1, DEPTH + 2), self:at(0, HEIGHT + 0.5, 0), Color3.fromRGB(66, 66, 68), Enum.Material.Concrete, true)
	part(shell, "BackWall", Vector3.new(WIDTH + 2, HEIGHT, 1), self:at(0, HEIGHT / 2, -HALF_D - 0.5), wall, Enum.Material.Concrete, true)
	part(shell, "WallL", Vector3.new(1, HEIGHT, DEPTH + 2), self:at(-HALF_W - 0.5, HEIGHT / 2, 0), wall, Enum.Material.Concrete, true)
	part(shell, "WallR", Vector3.new(1, HEIGHT, DEPTH + 2), self:at(HALF_W + 0.5, HEIGHT / 2, 0), wall, Enum.Material.Concrete, true)
	-- the roller door is 19.25 wide by 15 tall as modelled, so the opening is cut to fit it
	local doorH = 14.6
	local doorW = 19.25 * doorH / 15 + 0.4
	local sideW = (WIDTH + 2 - doorW) / 2
	part(shell, "FrontL", Vector3.new(sideW, HEIGHT, 1), self:at(-(doorW / 2 + sideW / 2), HEIGHT / 2, HALF_D + 0.5), wall, Enum.Material.Concrete, true)
	part(shell, "FrontR", Vector3.new(sideW, HEIGHT, 1), self:at(doorW / 2 + sideW / 2, HEIGHT / 2, HALF_D + 0.5), wall, Enum.Material.Concrete, true)
	part(shell, "FrontTop", Vector3.new(doorW, HEIGHT - doorH, 1), self:at(0, doorH + (HEIGHT - doorH) / 2, HALF_D + 0.5), wall, Enum.Material.Concrete, true)
	part(shell, "DoorBlock", Vector3.new(doorW, doorH, 1), self:at(0, doorH / 2, HALF_D + 1.2), Color3.fromRGB(20, 20, 20), Enum.Material.Concrete, true)
	-- a painted band round the bottom of the walls with a yellow line on top
	local function bandAlong(name: string, size: Vector3, cf: CFrame)
		part(shell, name, size, cf, band, Enum.Material.SmoothPlastic)
		part(shell, name .. "Line", Vector3.new(size.X, 0.22, size.Z), cf * CFrame.new(0, size.Y / 2 + 0.11, 0), stripe, Enum.Material.SmoothPlastic)
	end
	bandAlong("BandBack", Vector3.new(WIDTH, 3.4, 0.06), self:at(0, 1.7, -HALF_D + 0.03))
	bandAlong("BandL", Vector3.new(0.06, 3.4, DEPTH), self:at(-HALF_W + 0.03, 1.7, 0))
	bandAlong("BandR", Vector3.new(0.06, 3.4, DEPTH), self:at(HALF_W - 0.03, 1.7, 0))
	bandAlong("BandFL", Vector3.new(sideW - 1, 3.4, 0.06), self:at(-(doorW / 2 + (sideW - 1) / 2), 1.7, HALF_D - 0.03))
	bandAlong("BandFR", Vector3.new(sideW - 1, 3.4, 0.06), self:at(doorW / 2 + (sideW - 1) / 2, 1.7, HALF_D - 0.03))
	-- steel posts either side of the opening
	for _, side in ipairs({ -1, 1 }) do
		part(shell, "DoorPost", Vector3.new(0.5, doorH + 0.5, 0.6), self:at(side * (doorW / 2 + 0.25), (doorH + 0.5) / 2, HALF_D - 0.2), Color3.fromRGB(62, 64, 68), Enum.Material.Metal)
	end
	part(shell, "DoorHeader", Vector3.new(doorW + 1, 0.5, 0.6), self:at(0, doorH + 0.25, HALF_D - 0.2), Color3.fromRGB(62, 64, 68), Enum.Material.Metal)
	-- steel beams across the ceiling
	for _, z in ipairs({ -10, 0, 10 }) do
		part(shell, "Beam", Vector3.new(WIDTH, 0.9, 0.5), self:at(0, HEIGHT - 0.45, z), Color3.fromRGB(52, 54, 58), Enum.Material.Metal)
	end
	-- the strip lights
	for _, x in ipairs({ -12, 12 }) do
		for _, z in ipairs({ -8, 1, 10 }) do
			local housing = part(shell, "LightHousing", Vector3.new(6, 0.3, 0.9), self:at(x, HEIGHT - 1.05, z), Color3.fromRGB(196, 196, 196), Enum.Material.Metal)
			part(shell, "Tube", Vector3.new(5.6, 0.16, 0.36), self:at(x, HEIGHT - 1.28, z), Color3.fromRGB(242, 246, 255), Enum.Material.Neon)
			local l = Instance.new("SurfaceLight")
			l.Face = Enum.NormalId.Bottom
			l.Brightness = 1.4
			l.Range = 26
			l.Angle = 120
			l.Color = Color3.fromRGB(242, 244, 255)
			l.Shadows = true
			l.Parent = housing
		end
	end
	-- bay lines on the floor: round the stand, and bay 2 by the door
	local paint = Color3.fromRGB(214, 172, 44)
	local function line(size: Vector3, cf: CFrame)
		part(shell, "FloorLine", size, cf, paint, Enum.Material.SmoothPlastic)
	end
	line(Vector3.new(0.3, 0.02, 18), self:at(-8, 0.01, -3))
	line(Vector3.new(0.3, 0.02, 18), self:at(8, 0.01, -3))
	line(Vector3.new(0.3, 0.02, 9), self:at(-9.5, 0.01, 10))
	line(Vector3.new(0.3, 0.02, 9), self:at(-20.5, 0.01, 10))
	line(Vector3.new(11.3, 0.02, 0.3), self:at(-15, 0.01, 5.65))
	-- a few old oil stains
	for i, s in ipairs({ { -1.4, -2.2, 3.4 }, { 1.8, -4.1, 2.2 }, { -15.6, 10.8, 2.8 }, { 4.5, 9.4, 1.6 } }) do
		local stain = part(shell, "Stain" .. i, Vector3.new(0.02, s[3], s[3] * 0.7), self:at(s[1], 0.015, s[2]) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(i * 37), 0, 0), Color3.fromRGB(58, 56, 54), Enum.Material.SmoothPlastic)
		stain.Shape = Enum.PartType.Cylinder
		stain.Transparency = 0.55
	end
	local bayText = part(shell, "BayText", Vector3.new(1.6, 0.02, 5), self:at(-15, 0.012, 13.6) * CFrame.Angles(0, math.rad(90), 0), paint, Enum.Material.SmoothPlastic)
	bayText.Transparency = 1
	local bsg = surface(bayText, Enum.NormalId.Top, 60)
	label(bsg, "BAY 2", 90, "display", paint, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))

	-- the roller door, from the inside
	local door = prop(Assets:FindFirstChild("Garage") and Assets.Garage:FindFirstChild("RollupDoor"), folder)
	if door then
		door.Name = "RollupDoor"
		local panel = door:FindFirstChild("Door", true) :: BasePart?
		if panel then
			-- the panel is thin along its X, 19.25 wide along its Y and 15 tall along its Z, with
			-- the roll along its top edge at +Z
			turn(door, panel.CFrame.RightVector, -panel.CFrame.LookVector, self:dir(0, 0, -1), self:dir(0, 1, 0))
			door:ScaleTo(door:GetScale() * doorH / 15)
			standAt(door, self:pos(0, 0, HALF_D - 0.45))
			self.doorSounds = { open = panel:FindFirstChild("DoorOpen", true), close = panel:FindFirstChild("DoorClose", true) }
		end
		for _, d in ipairs(door:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name == "Button1" or d.Name == "Button2") then d:Destroy() end
		end
	end

	self.dyn = Instance.new("Model")
	self.dyn.Name = "Contents"
	self.dyn.Parent = folder
end

-- moves the whole room to a yard's own spot
function Garage:moveTo(index: number)
	local target = self:originFor(index)
	if self.folder:GetPivot() ~= target then
		self.folder:PivotTo(target)
	end
	self.origin = target
end

--==============================================================
-- what's in it
--==============================================================
function Garage:clearContents()
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
	self.prompts = {}
	self.spinners = {}
	if self.dyn then self.dyn:ClearAllChildren() end
	if photoLayer then photoLayer:ClearAllChildren() end
end

-- the garage's interactions are clicks on the room, not proximity prompts (switched off)
function Garage:prompt(_host: BasePart, _action: string, _object: string, _hold: number?, _onTrigger: () -> ()): ProximityPrompt?
	return nil
end

function Garage:dress(v)
	self:clearContents()
	local mine = v.userId == Players.LocalPlayer.UserId
	self.mine = mine
	self:dressName(v)
	self:dressTyreWall(v)
	self:dressStand(v)
	self:dressShelves(v, mine)
	self:dressSigns(v)
	self:dressCorkboard(v)
	self:dressCounter(v)
	self:dressMedals(v)
	self:dressHonks(v)
	self:dressGuestbook(v, mine)
	self:dressBay(v, mine)
end

-- the owner's name painted across the back wall
function Garage:dressName(v)
	local name = (type(v.rigName) == "string" and v.rigName ~= "") and v.rigName or (tostring(v.name) .. "'S")
	local p = part(self.dyn, "PaintedName", Vector3.new(36, 3.2, 0.05), self:at(0, 15.4, -HALF_D + 0.06), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	p.Transparency = 1
	local sg = surface(p, Enum.NormalId.Back, 30)
	local l = label(sg, string.upper(name) .. "  GARAGE", 96, "display", Color3.fromRGB(236, 232, 222), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	l.TextTransparency = 0.12
end

-- every tyre they own on a hook along the back wall, with a slate tag chalked with how it's done
function Garage:dressTyreWall(v)
	local list = {}
	for _, s in ipairs(Config.Skins) do
		if owned(v, s.id) then table.insert(list, s) end
	end
	table.sort(list, function(a, b) return (a.cost or 0) < (b.cost or 0) end)
	local perRow, gap = 12, 3.4
	local wallZ = -HALF_D + 0.1
	local rails = { 12.2, 7.1 }
	self.tyreRows = #list > perRow and 2 or 1
	for r = 1, 2 do
		local count = math.clamp(#list - (r - 1) * perRow, 0, perRow)
		if count > 0 then
			local span = (math.max(count, 6) - 1) * gap + 2.4
			part(self.dyn, "Rail", Vector3.new(span, 0.22, 0.12), self:at(0, rails[r] + 0.25, wallZ + 0.08), Color3.fromRGB(88, 92, 98), Enum.Material.Metal)
		end
	end
	for i, s in ipairs(list) do
		local r = math.floor((i - 1) / perRow) + 1
		if r > 2 then break end
		local col = (i - 1) % perRow
		local count = math.clamp(#list - (r - 1) * perRow, 0, perRow)
		local x = (col - (count - 1) / 2) * gap
		local hookY = rails[r]
		local hook = self:pos(x, hookY, wallZ + 0.1)
		-- the hook: a peg out of the rail with a turned-up tip, as on the parts wall
		part(self.dyn, "Peg", Vector3.new(0.9, 0.16, 0.16), CFrame.new(hook + self:dir(0, 0, 0.45)) * self.origin.Rotation * CFrame.Angles(0, math.rad(90), 0), STEEL, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		part(self.dyn, "Tip", Vector3.new(0.14, 0.3, 0.14), CFrame.new(hook + self:dir(0, 0.12, 0.86)) * self.origin.Rotation, STEEL, Enum.Material.Metal)
		local fitted = s.id == v.skin
		local log = v.tyreLog and v.tyreLog[s.id]
		local D = 2.6
		local tyreBottom = hookY - 0.4
		if not fitted then
			local model = WheelAssembly.build(nil, { diameter = D, skin = s.id, rim = "steel", detail = "low", name = "Hung_" .. s.id })
			local hub = model:FindFirstChild("Hub")
			if hub then hub:Destroy() end
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("Light") then d:Destroy() end
				if d:IsA("BasePart") then
					d.CastShadow = true
					d.CanQuery = false
					d.CanCollide = false
				end
			end
			local inner = (model:GetAttribute("InnerRadius") :: number?) or D * 0.4
			model.Parent = self.dyn
			model:PivotTo(CFrame.new(hook + self:dir(0, -(inner - 0.08), 0.5)) * self.origin.Rotation)
			tyreBottom = hookY - (inner - 0.08) - D / 2
		end
		-- the tag
		local tagY = tyreBottom - 0.75
		local tag = part(self.dyn, "Tag", Vector3.new(2.3, 1.2, 0.06), self:at(x, tagY, wallZ + 0.35) * CFrame.Angles(math.rad(-4), 0, 0), SLATE, Enum.Material.Slate)
		tag.CastShadow = false
		part(self.dyn, "TagString", Vector3.new(0.03, math.max(0.2, hookY - tagY - 0.6), 0.03), self:at(x, (hookY + tagY + 0.6) / 2, wallZ + 0.3), Color3.fromRGB(70, 60, 50), Enum.Material.Fabric).CastShadow = false
		local sg = surface(tag, Enum.NormalId.Back, 110)
		local tier = Config.CosmeticTier(s)
		UI.mk("Frame", { Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = Config.TierColor(tier), BorderSizePixel = 0, Parent = sg })
		label(sg, string.upper(s.name), 30, "display", CHALK, UDim2.new(0, 10, 0, 12), UDim2.new(1, -20, 0, 34))
		local runs = log and log.runs or 0
		local line2 = fitted and "ON THE STAND" or (runs > 0 and ("%s RUN%s  ·  %.1f KM"):format(comma(runs), runs == 1 and "" or "S", (log.dist * M) / 1000) or "NEVER RUN")
		label(sg, line2, 20, "monoBold", CHALK, UDim2.new(0, 10, 0, 50), UDim2.new(1, -20, 0, 26))
		if runs > 0 then
			label(sg, "BEST " .. comma(log.best * M) .. " M", 20, "monoBold", Color3.fromRGB(196, 194, 186), UDim2.new(0, 10, 0, 82), UDim2.new(1, -20, 0, 26))
		end
	end
end

-- the build on the rig, on a stand in the middle of the floor, turning
function Garage:standBuild(name: string, x: number, z: number, build, scale: number)
	local plinth = part(self.dyn, name .. "Plinth", Vector3.new(0.4, 7 * scale, 7 * scale), self:at(x, 0.2, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 40, 42), Enum.Material.Rubber, true)
	plinth.Shape = Enum.PartType.Cylinder
	local rim = part(self.dyn, name .. "Edge", Vector3.new(0.26, 7.3 * scale, 7.3 * scale), self:at(x, 0.13, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(214, 172, 44), Enum.Material.SmoothPlastic)
	rim.Shape = Enum.PartType.Cylinder
	local D = 5 * scale
	local centre = self:pos(x, 0.4 + 0.5 + D / 2 + 0.2, z)
	local steel = Color3.fromRGB(44, 46, 50)
	local postH = centre.Y - self:pos(0, 0.4, 0).Y
	local postP = centre + self:dir(0, 0, -(D * 0.32 + 0.55))
	local turning = Instance.new("Model")
	turning.Name = name
	turning.Parent = self.dyn
	part(turning, name .. "Post", Vector3.new(0.42, postH, 0.42), CFrame.new(postP.X, centre.Y - postH / 2, postP.Z) * self.origin.Rotation, steel, Enum.Material.Metal)
	part(turning, name .. "Foot", Vector3.new(0.3, 2.2, 2.2), CFrame.new(postP.X, self:pos(0, 0.55, 0).Y, postP.Z) * self.origin.Rotation * CFrame.Angles(0, 0, math.rad(90)), steel, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
	local mid = (postP + centre) / 2
	part(turning, name .. "Spindle", Vector3.new((centre - postP).Magnitude + 0.3, 0.3, 0.3), CFrame.lookAt(mid, centre) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(150, 154, 160), Enum.Material.Metal).Shape = Enum.PartType.Cylinder
	local wheel = WheelAssembly.build(nil, {
		diameter = D, skin = build.skin or "stock", rim = build.rim or "steel", stickers = build.stickers, name = name .. "Wheel",
	})
	for _, d in ipairs(wheel:GetDescendants()) do
		if d:IsA("Light") then d:Destroy() end
		if d:IsA("BasePart") then
			d.CastShadow = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	wheel.Parent = turning
	wheel:PivotTo(CFrame.new(centre) * self.origin.Rotation)
	local base = CFrame.new(self:pos(x, 0.4, z)) * self.origin.Rotation
	turning.WorldPivot = base
	table.insert(self.spinners, { model = turning, base = base, roll = (x + z) * 0.1 })
	local hit = part(self.dyn, name .. "Hit", Vector3.new(4, 5, 4), CFrame.new(centre), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	hit.Transparency = 1
	return hit
end

function Garage:dressStand(v)
	local hit = self:standBuild("Stand", 0, -3, v, 1)
	self:prompt(hit, "Inspect", "The build", 0, function()
		self.card:open(v.plot or 0, {
			name = v.name, skin = v.skin, rim = v.rim, trail = v.trail, stickers = v.stickers, pressure = v.pressure,
			best = math.floor((v.bestDistance or 0) * M), rigName = v.rigName,
		})
	end)
end

-- which step of a trophy they've reached, and the number it's about
local function trophyValue(v, id: string): number
	local st = v.stats or {}
	if id == "distance" then return ((v.totals and v.totals.distance) or 0) * M / 1000 end
	if id == "runs" then return st.runs or 0 end
	if id == "best" then return (v.bestDistance or 0) * M end
	if id == "forged" then return st.forged or 0 end
	if id == "flawless" then return st.flawless or 0 end
	if id == "contracts" then return st.contracts or 0 end
	return 0
end

-- the shelves up the left wall: trophies on one, the longest-run photo and the legendary box
-- on the other
function Garage:dressShelves(v, mine: boolean)
	local tpl = Assets.Workshop:FindFirstChild("Shelves")
	local function shelf(z: number): (Model?, { number })
		local m = prop(tpl, self.dyn)
		if not m then return nil, {} end
		local _, s0 = m:GetBoundingBox()
		m:ScaleTo(m:GetScale() * 12 / s0.Y)
		-- the open side faces into the room
		local cf = m:GetBoundingBox()
		turn(m, cf.LookVector * -1, cf.UpVector, self:dir(1, 0, 0), self:dir(0, 1, 0))
		local _, s = m:GetBoundingBox()
		standAt(m, self:pos(-HALF_W + math.min(s.X, s.Z) / 2 + 0.15, 0, z))
		-- the tops of its planks
		local levels = {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				local c = d.CFrame
				local ext = math.abs(c.RightVector.Y) * d.Size.X / 2 + math.abs(c.UpVector.Y) * d.Size.Y / 2 + math.abs(c.LookVector.Y) * d.Size.Z / 2
				local wide = math.max(d.Size.X, d.Size.Y, d.Size.Z)
				if ext < 0.35 and wide > 4 then
					local topY = c.Position.Y + ext
					local dup = false
					for _, l in ipairs(levels) do if math.abs(l - topY) < 0.2 then dup = true end end
					if not dup then table.insert(levels, topY) end
				end
			end
		end
		table.sort(levels)
		return m, levels
	end
	local shelfA, levelsA = shelf(-8.4)
	local shelfB, levelsB = shelf(4.6)
	local frontX = -HALF_W + 2.1

	-- trophies: three to a plank, on the second and third planks
	local tt = Assets:FindFirstChild("Garage") and Assets.Garage:FindFirstChild("Trophy")
	for i, def in ipairs(Config.Garage.Trophies) do
		local levelY = levelsA[(i <= 3) and 2 or 3]
		if not (shelfA and levelY) then break end
		local z = -8.4 + (((i - 1) % 3) - 1) * 3.2
		local value = trophyValue(v, def.id)
		local step = 0
		for k, need in ipairs(def.steps) do
			if value >= need then step = k end
		end
		local shown = def.unit == "KM" and ("%.1f KM"):format(value) or (comma(value) .. (def.unit ~= "" and (" " .. def.unit) or ""))
		if step > 0 then
			local tier = Config.Garage.TrophyTiers[step]
			local m = prop(tt, self.dyn)
			if m then
				local plaque: BasePart? = nil
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") and d.Material ~= Enum.Material.Wood then
						-- unions keep their own colour unless told to take the part's
						if d:IsA("PartOperation") then (d :: PartOperation).UsePartColor = true end
						d.Color = tier.color
						d.Material = Enum.Material.Metal
						d.Reflectance = 0.12
						if d:FindFirstChildOfClass("SurfaceGui") then plaque = d end
					end
				end
				local _, s = m:GetBoundingBox()
				m:ScaleTo(m:GetScale() * 2 / s.Y)
				-- the plaque is on the model's +X side: turn it to face into the room
				m:PivotTo(m:GetPivot() * CFrame.Angles(0, math.pi, 0))
				standAt(m, Vector3.new(0, 0, 0) + self:pos(frontX - 0.2, 0, z) + Vector3.new(0, levelY - self:pos(0, 0, 0).Y + 0.02, 0))
				if plaque then
					local sg = plaque:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui
					for _, c in ipairs(sg:GetChildren()) do c:Destroy() end
					sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
					sg.PixelsPerStud = 300
					label(sg, def.name, 26, "display", Color3.fromRGB(30, 24, 18), UDim2.new(0, 6, 0, 4), UDim2.new(1, -12, 0.5, -4))
					label(sg, shown, 24, "monoBold", Color3.fromRGB(30, 24, 18), UDim2.new(0, 6, 0.5, 0), UDim2.new(1, -12, 0.5, -4))
				end
			end
		elseif mine then
			-- an empty spot with a tag saying what fills it
			local tag = part(self.dyn, "TrophyTag", Vector3.new(0.05, 0.9, 1.9), CFrame.new(self:pos(frontX, 0, z).X, levelY + 0.5, self:pos(frontX, 0, z).Z) * self.origin.Rotation * CFrame.Angles(0, 0, math.rad(-8)), PAPER, Enum.Material.Fabric)
			local sg = surface(tag, Enum.NormalId.Right, 120)
			label(sg, def.name, 22, "display", INK, UDim2.new(0, 8, 0, 6), UDim2.new(1, -16, 0.5, -6))
			label(sg, ("%s%s TO GO"):format(def.unit == "KM" and "" or "", def.unit == "KM" and ("%.1f KM"):format(def.steps[1] - value) or (comma(def.steps[1] - value) .. (def.unit ~= "" and (" " .. def.unit) or ""))), 18, "monoBold", Color3.fromRGB(96, 88, 76), UDim2.new(0, 8, 0.5, 0), UDim2.new(1, -16, 0.5, -6))
		end
	end

	-- the longest run's photo in a frame on top of the second shelf
	local photos = v.photos or {}
	local bestPhoto = nil
	for _, ph in ipairs(photos) do
		if ph.best and (not bestPhoto or (ph.metres or 0) > (bestPhoto.metres or 0)) then bestPhoto = ph end
	end
	bestPhoto = bestPhoto or photos[1]
	local topB = levelsB[#levelsB]
	local ft = Assets:FindFirstChild("Garage") and Assets.Garage:FindFirstChild("PictureFrame")
	if bestPhoto and topB and shelfB then
		local m = prop(ft, self.dyn)
		if m then
			local _, s = m:GetBoundingBox()
			m:ScaleTo(m:GetScale() * 2.1)
			standAt(m, Vector3.new(self:pos(frontX - 0.4, 0, 4.6).X, topB + 0.02, self:pos(frontX - 0.4, 0, 4.6).Z))
			local pic = m:FindFirstChild("Picture", true) :: BasePart?
			if pic then
				for _, d in ipairs(pic:GetChildren()) do
					if d:IsA("Decal") then d:Destroy() end
				end
				local sg = surface(pic, Enum.NormalId.Right, 190, true)
				local vpf = UI.mk("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = sg })
				pcall(function() RunPhoto.render(vpf, bestPhoto) end)
			end
			local glass = m:FindFirstChild("Glass", true) :: BasePart?
			if glass then glass.Transparency = 0.9 end
		end
		-- a brass plate in front of it
		local plate = part(self.dyn, "BestPlate", Vector3.new(0.05, 0.5, 3.4), CFrame.new(self:pos(frontX + 0.35, 0, 4.6).X, topB + 0.28, self:pos(0, 0, 4.6).Z) * self.origin.Rotation * CFrame.Angles(0, 0, math.rad(-12)), Color3.fromRGB(184, 144, 74), Enum.Material.Metal)
		local sg = surface(plate, Enum.NormalId.Right, 140)
		local cfgT = Config.TracksById[bestPhoto.track]
		label(sg, ("LONGEST RUN  ·  %s M  ·  %s"):format(comma(bestPhoto.metres or 0), string.upper(cfgT and cfgT.name or "")), 26, "display", Color3.fromRGB(62, 42, 20), UDim2.new(0, 8, 0, 4), UDim2.new(1, -16, 1, -8))
	end

	-- a forged legendary gets pride of place on the middle plank
	local midB = levelsB[3]
	if (v.stats and (v.stats.forgedLegendary or 0) > 0) and midB and shelfB then
		local bb = prop(Assets.Workshop:FindFirstChild("Boombox"), self.dyn)
		if bb then
			local _, s = bb:GetBoundingBox()
			bb:ScaleTo(bb:GetScale() * 2.6 / math.max(s.X, s.Z))
			turn(bb, bb:GetPivot().LookVector, bb:GetPivot().UpVector, self:dir(1, 0, 0), self:dir(0, 1, 0))
			standAt(bb, Vector3.new(self:pos(frontX - 0.5, 0, 4.6).X, midB + 0.02, self:pos(0, 0, 4.6).Z))
			local h = Instance.new("Highlight")
			h.FillTransparency = 1
			h.OutlineColor = (Config.ToolboxRaritiesById.legendary and Config.ToolboxRaritiesById.legendary.color) or Color3.fromRGB(255, 190, 60)
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Parent = bb
		end
	end
end

-- a green street sign on the left wall for each road they've set a best on, and the stop sign
-- off the furthest checkpoint they've reached, standing in the back corner
function Garage:dressSigns(v)
	local stop = Assets:FindFirstChild("Garage") and Assets.Garage:FindFirstChild("StopSign")
	local plateTpl = stop and stop:FindFirstChild("2-Way")
	local tracks = {}
	for _, t in ipairs(Config.Tracks) do
		local r = v.records and v.records[t.id]
		if r and (r.dist or 0) > 0 then table.insert(tracks, { t = t, dist = r.dist }) end
	end
	for i, e in ipairs(tracks) do
		if not plateTpl then break end
		local m = prop(plateTpl, self.dyn)
		if not m then break end
		local z = -12.6 + (i - 1) * 5.8
		-- find the coloured face, stand it upright and face it into the room
		local face: BasePart? = nil
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d:FindFirstChildOfClass("SurfaceGui") then face = d end
		end
		if face then
			local long = face.Size.X >= face.Size.Y and face.CFrame.RightVector or face.CFrame.UpVector
			local out = face.CFrame.LookVector
			turn(m, long, -out:Cross(long), self:dir(0, 0, 1), self:dir(0, 1, 0))
			if face.CFrame.LookVector:Dot(self:dir(1, 0, 0)) < 0 then
				turn(m, self:dir(0, 0, 1), self:dir(0, 1, 0), self:dir(0, 0, -1), self:dir(0, 1, 0))
			end
			m:ScaleTo(m:GetScale() * 3.2)
			centreAt(m, self:pos(-HALF_W + 0.2, 14.6, z))
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") and d.Color.R > 0.6 and d.Color.G < 0.3 then d.Color = Color3.fromRGB(18, 104, 64) end
			end
			local sg = face:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui
			for _, c in ipairs(sg:GetChildren()) do c:Destroy() end
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 90
			label(sg, string.upper(e.t.name), 70, "display", Color3.new(1, 1, 1), UDim2.new(0, 10, 0, 6), UDim2.new(1, -20, 0.6, -6))
			label(sg, "BEST  " .. comma(e.dist * M) .. " M", 44, "monoBold", Color3.fromRGB(226, 240, 230), UDim2.new(0, 10, 0.6, 0), UDim2.new(1, -20, 0.4, -6))
		end
	end

	local tier = (v.stats and v.stats.maxTier) or 0
	if stop and tier > 0 then
		local m = prop(stop, self.dyn)
		if m then
			local pole = m:FindFirstChild("Pole", true) :: BasePart?
			local textPart = m:FindFirstChild("Text", true) :: BasePart?
			local plate = m:FindFirstChild("2-Way")
			if plate then plate:Destroy() end
			if pole and textPart then
				local along = pole.CFrame.RightVector
				if (textPart.Position - pole.Position):Dot(along) < 0 then along = -along end
				local facing = textPart.CFrame.LookVector
				facing = (facing - along * facing:Dot(along)).Unit
				local toward = self:dir(-1, 0, 1).Unit
				local poleLength = math.max(pole.Size.X, pole.Size.Y, pole.Size.Z)
				turn(m, along, facing, self:dir(0, 1, 0), toward)
				m:ScaleTo(m:GetScale() * 12 / poleLength)
				local foot = self:pos(HALF_W - 2.4, 0, -HALF_D + 2.4)
				standAt(m, foot)
				-- leaning back against the corner, like it was carried in and propped there
				local piv = m:GetPivot()
				m:PivotTo(CFrame.new(foot) * CFrame.fromAxisAngle(toward:Cross(Vector3.yAxis).Unit, math.rad(6)) * CFrame.new(-foot) * piv)
				standAt(m, foot)
				local label_ = textPart:FindFirstChildWhichIsA("TextLabel", true)
				if label_ then
					label_.Text = "CP " .. tier
					label_.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
				end
			end
		end
	end
end

-- their photos pinned to the corkboard on the right wall
function Garage:dressCorkboard(v)
	local tpl = Assets:FindFirstChild("Garage") and Assets.Garage:FindFirstChild("Corkboard")
	local m = prop(tpl, self.dyn)
	if not m then return end
	local board: BasePart? = nil
	local pins = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Material == Enum.Material.Concrete then board = d end
			if d:IsA("UnionOperation") then table.insert(pins, d) end
		end
	end
	local zc, yc = -4.5, 8.4
	-- stand it on the wall with the cork facing into the room
	if board then
		local thin = board.CFrame.RightVector
		if board.Size.Y < board.Size.X and board.Size.Y < board.Size.Z then thin = board.CFrame.UpVector end
		if board.Size.Z < board.Size.X and board.Size.Z < board.Size.Y then thin = board.CFrame.LookVector end
		local up = Vector3.yAxis
		turn(m, thin, up, self:dir(-1, 0, 0), self:dir(0, 1, 0))
	end
	centreAt(m, self:pos(HALF_W - 0.35, yc, zc))
	local photos = v.photos or {}
	for i, pin in ipairs(pins) do pin.Transparency = 1 end
	for i = 1, math.min(6, #photos) do
		local ph = photos[i]
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local z = zc + (col - 1) * 3.45
		local y = yc + (row == 0 and 1.75 or -1.85)
		local roll = math.rad(((i * 37) % 9) - 4)
		local cf = self:at(HALF_W - 0.62, y, z) * CFrame.Angles(roll, 0, 0)
		local print_ = part(self.dyn, "Photo", Vector3.new(0.03, 2.8, 3.2), cf, Color3.fromRGB(246, 244, 238), Enum.Material.SmoothPlastic)
		local sg = surface(print_, Enum.NormalId.Left, 200, true)
		local vpf = UI.mk("ViewportFrame", {
			Position = UDim2.new(0, 26, 0, 26), Size = UDim2.new(1, -52, 1, -112), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = sg,
		})
		pcall(function() RunPhoto.render(vpf, ph) end)
		local cap = RunPhoto.caption(ph)
		label(sg, cap, 44, "monoBold", INK, UDim2.new(0, 26, 1, -78), UDim2.new(1, -52, 0, 56))
		local pin = pins[i]
		if pin then
			pin.Transparency = 0
			pin.CFrame = CFrame.new((cf * CFrame.new(-0.12, 1.2, 0)).Position) * self.origin.Rotation * CFrame.Angles(0, 0, math.rad(90))
		end
	end
	if #photos == 0 then
		local note = part(self.dyn, "EmptyNote", Vector3.new(0.03, 2.2, 4), self:at(HALF_W - 0.62, yc, zc) * CFrame.Angles(math.rad(3), 0, 0), PAPER, Enum.Material.Fabric)
		local sg = surface(note, Enum.NormalId.Left, 100)
		label(sg, "NO PHOTOS YET", 40, "display", INK, UDim2.new(0, 10, 0, 20), UDim2.new(1, -20, 0.5, -20))
		label(sg, "Runs over 40 m get one", 28, "body", Color3.fromRGB(96, 88, 76), UDim2.new(0, 10, 0.5, 0), UDim2.new(1, -20, 0.5, -20))
		if pins[1] then
			pins[1].Transparency = 0
			pins[1].CFrame = CFrame.new(self:pos(HALF_W - 0.72, yc + 1, zc)) * self.origin.Rotation * CFrame.Angles(0, 0, math.rad(90))
		end
	end
end

-- total distance on a flip counter above the corkboard
function Garage:dressCounter(v)
	local metres = ((v.totals and v.totals.distance) or 0) * M
	local box = part(self.dyn, "Counter", Vector3.new(0.4, 2.1, 11.2), self:at(HALF_W - 0.3, 14.1, -4.5), Color3.fromRGB(18, 18, 20), Enum.Material.Metal)
	part(self.dyn, "CounterTrim", Vector3.new(0.3, 2.35, 11.45), self:at(HALF_W - 0.22, 14.1, -4.5), Color3.fromRGB(110, 112, 118), Enum.Material.Metal)
	local sg = surface(box, Enum.NormalId.Left, 80)
	label(sg, "TOTAL DISTANCE", 26, "monoBold", Color3.fromRGB(170, 170, 176), UDim2.new(0, 20, 0, 8), UDim2.new(0.3, 0, 0, 30), Enum.TextXAlignment.Left)
	local digits = ("%09d"):format(math.min(999999999, math.floor(metres)))
	local row = UI.mk("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -110, 0.5, 8), Size = UDim2.new(0.62, 0, 0, 112),
		BackgroundTransparency = 1, Parent = sg,
	}, { UI.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
	for i = 1, #digits do
		-- a flap per digit: lit from above, split across the middle
		local cell = UI.mk("Frame", { Size = UDim2.fromOffset(62, 104), BackgroundColor3 = Color3.fromRGB(58, 58, 64), BorderSizePixel = 0, LayoutOrder = i, Parent = row })
		UI.mk("UICorner", { CornerRadius = UDim.new(0, 6), Parent = cell })
		UI.mk("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(0.49, Color3.fromRGB(190, 190, 196)),
				ColorSequenceKeypoint.new(0.51, Color3.fromRGB(150, 150, 156)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(96, 96, 102)),
			}),
			Parent = cell,
		})
		UI.mk("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = Color3.fromRGB(8, 8, 10), BorderSizePixel = 0, ZIndex = 3, Parent = cell })
		local l = label(cell, digits:sub(i, i), 90, "display", Color3.fromRGB(240, 236, 226), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
		l.ZIndex = 2
	end
	label(sg, "M", 60, "display", Color3.fromRGB(214, 172, 44), UDim2.new(1, -96, 0.5, -34), UDim2.fromOffset(80, 80))
end

-- bronze, silver and gold hanging to the right of the corkboard
function Garage:dressMedals(v)
	local tpl = Assets:FindFirstChild("Garage") and Assets.Garage:FindFirstChild("Medal")
	if not tpl then return end
	local ribbons = { bronze = Color3.fromRGB(150, 30, 30), silver = Color3.fromRGB(34, 64, 150), gold = Color3.fromRGB(24, 110, 60) }
	for i, metal in ipairs(Config.Metals) do
		local count = (v.metals and v.metals[metal.id]) or 0
		local z = 4.6 + (i - 1) * 2.9
		local hook = self:pos(HALF_W - 0.1, 11.6, z)
		part(self.dyn, "MedalPeg", Vector3.new(0.7, 0.14, 0.14), CFrame.new(hook + self:dir(-0.35, 0, 0)) * self.origin.Rotation, STEEL, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local m = prop(tpl, self.dyn)
		if m then
			local parts = {}
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then table.insert(parts, d) end
			end
			-- the disc is the thicker of the two meshes; the ribbon is the long thin one
			table.sort(parts, function(a, b) return a.Size.Y < b.Size.Y end)
			local disc, ribbon = parts[1], parts[#parts]
			if disc then
				disc.Color = metal.color
				disc.Material = Enum.Material.Metal
				disc.Reflectance = 0.15
			end
			if ribbon and ribbon ~= disc then ribbon.Color = ribbons[metal.id] or ribbon.Color end
			if count == 0 then
				for _, p in ipairs(parts) do p.Transparency = 0.7 end
			end
			local cf = m:GetBoundingBox()
			turn(m, disc and disc.CFrame.RightVector or cf.RightVector, Vector3.yAxis, self:dir(-1, 0, 0), self:dir(0, 1, 0))
			m:ScaleTo(m:GetScale() * 2.2)
			local lo, hi = worldBounds(m)
			m:PivotTo(m:GetPivot() + (hook + self:dir(-0.45, 0.05, 0) - Vector3.new((lo.X + hi.X) / 2, hi.Y, (lo.Z + hi.Z) / 2)))
		end
		local tag = part(self.dyn, "MedalTag", Vector3.new(0.05, 0.8, 2.3), self:at(HALF_W - 0.35, 5.9, z) * CFrame.Angles(math.rad(3), 0, 0), SLATE, Enum.Material.Slate)
		local sg = surface(tag, Enum.NormalId.Left, 110)
		label(sg, ("%s  ×%s"):format(string.upper(metal.name), comma(count)), 30, "display", CHALK, UDim2.new(0, 8, 0, 6), UDim2.new(1, -16, 1, -12))
	end
end

-- the vuvuzela on a plaque by the door, with the yard's honk count
function Garage:dressHonks(v)
	local x, y, z = 20, 9.2, HALF_D - 0.3
	local plaque = part(self.dyn, "HonkPlaque", Vector3.new(4.2, 2.6, 0.25), self:at(x, y, z), Color3.fromRGB(96, 64, 40), Enum.Material.Wood)
	plaque.CastShadow = true
	local horn = prop(Root.Assets.Props:FindFirstChild("Vuvuzela"), self.dyn)
	if horn then
		for _, d in ipairs(horn:GetDescendants()) do
			if d:IsA("Sound") then d:Destroy() end
		end
		local cf, s = horn:GetBoundingBox()
		local long = cf.RightVector
		if s.Y > s.X and s.Y > s.Z then long = cf.UpVector elseif s.Z > s.X and s.Z > s.Y then long = cf.LookVector end
		local side = long:Cross(Vector3.yAxis)
		if side.Magnitude < 0.1 then side = long:Cross(Vector3.xAxis) end
		turn(horn, long, side:Cross(long).Unit, self:dir(1, 0, 0), self:dir(0, 1, 0))
		local _, s2 = horn:GetBoundingBox()
		horn:ScaleTo(horn:GetScale() * 3.4 / math.max(s2.X, s2.Y, s2.Z))
		centreAt(horn, self:pos(x, y + 0.35, z - 0.55))
	end
	local tag = part(self.dyn, "HonkTag", Vector3.new(3.4, 0.6, 0.05), self:at(x, y - 0.85, z - 0.16), Color3.fromRGB(184, 144, 74), Enum.Material.Metal)
	local sg = surface(tag, Enum.NormalId.Front, 120)
	label(sg, ("HONKS  ·  %s"):format(comma(v.honks or 0)), 40, "display", Color3.fromRGB(62, 42, 20), UDim2.new(0, 8, 0, 4), UDim2.new(1, -16, 1, -8))
end

-- the guestbook by the door: a clipboard of stamps, and the stamp on a shelf underneath
function Garage:dressGuestbook(v, mine: boolean)
	local x, y, z = 13.6, 8.2, HALF_D - 0.2
	part(self.dyn, "Clipboard", Vector3.new(4.2, 5.4, 0.2), self:at(x, y, z), Color3.fromRGB(110, 76, 44), Enum.Material.Wood)
	part(self.dyn, "Clip", Vector3.new(1.6, 0.5, 0.3), self:at(x, y + 2.55, z - 0.12), Color3.fromRGB(170, 172, 178), Enum.Material.Metal)
	local paper = part(self.dyn, "GuestbookPage", Vector3.new(3.8, 4.8, 0.04), self:at(x, y - 0.15, z - 0.13), PAPER, Enum.Material.Fabric)
	self.page = paper
	self:paintGuestbook(v)
	part(self.dyn, "StampShelf", Vector3.new(3, 0.25, 1.1), self:at(x, 4.35, z - 0.55), Color3.fromRGB(96, 64, 40), Enum.Material.Wood)
	local stampTpl = Assets:FindFirstChild("Garage") and Assets.Garage:FindFirstChild("Stamp")
	local st = prop(stampTpl, self.dyn)
	if st then
		local grip = st:FindFirstChild("Grip")
		if grip then grip:Destroy() end
		local _, s = st:GetBoundingBox()
		st:ScaleTo(st:GetScale() * 1.1 / math.max(s.Y, 0.1))
		standAt(st, self:pos(x, 4.48, z - 0.55))
		local last = v.guestbook and v.guestbook[1]
		local ink = last and Config.Garage.StampsById[last.stamp]
		for _, d in ipairs(st:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Stamp" then
				d.Color = ink and ink.color or Color3.fromRGB(40, 40, 44)
				for _, c in ipairs(d:GetChildren()) do
					if c:IsA("Decal") then c:Destroy() end
				end
			end
		end
	end
	local hit = part(self.dyn, "GuestbookHit", Vector3.new(4, 6, 2), self:at(x, 6.5, z - 1.4), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	hit.Transparency = 1
	if not mine then
		self:prompt(hit, "Stamp it", tostring(v.name) .. "'s guestbook", 0, function() self:showPicker(true) end)
	end
end

function Garage:paintGuestbook(v)
	local paper = self.page
	if not paper then return end
	for _, c in ipairs(paper:GetChildren()) do c:Destroy() end
	local sg = surface(paper, Enum.NormalId.Front, 80)
	label(sg, "GUESTBOOK", 40, "display", INK, UDim2.new(0, 16, 0, 10), UDim2.new(1, -32, 0, 40))
	UI.mk("Frame", { Position = UDim2.new(0, 16, 0, 54), Size = UDim2.new(1, -32, 0, 2), BackgroundColor3 = Color3.fromRGB(180, 170, 150), BorderSizePixel = 0, Parent = sg })
	local list = v.guestbook or {}
	if #list == 0 then
		label(sg, "No stamps yet.", 26, "body", Color3.fromRGB(120, 110, 96), UDim2.new(0, 16, 0, 80), UDim2.new(1, -32, 0, 30))
		return
	end
	for i = 1, math.min(12, #list) do
		local g = list[i]
		local s = Config.Garage.StampsById[g.stamp]
		if s then
			local col = (i - 1) % 3
			local row = math.floor((i - 1) / 3)
			local cell = UI.mk("Frame", {
				Position = UDim2.new(col / 3, 8, 0, 70 + row * 78), Size = UDim2.new(1 / 3, -16, 0, 72), BackgroundTransparency = 1, Parent = sg,
			})
			local ink = UI.mk("Frame", {
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.new(1, -6, 0, 42),
				BackgroundTransparency = 1, Rotation = ((i * 53) % 17) - 8, Parent = cell,
			})
			UI.mk("UIStroke", { Color = s.color, Thickness = 3, Transparency = 0.1, Parent = ink })
			local t = label(ink, s.text, 26, "display", s.color, UDim2.new(0, 4, 0, 4), UDim2.new(1, -8, 1, -8))
			t.TextTransparency = 0.08
			label(cell, string.upper(g.name or ""), 16, "monoBold", Color3.fromRGB(110, 102, 92), UDim2.new(0, 0, 0, 48), UDim2.new(1, 0, 0, 20))
		end
	end
end

-- bay 2: a build under a tarp until it's bought, then a second stand
function Garage:dressBay(v, mine: boolean)
	local bay = v.bay or {}
	local x, z = -15, 10
	if bay.unlocked then
		local hit = self:standBuild("Bay", x, z, bay, 0.8)
		if mine then
			self:prompt(hit, "Swap builds", "Bay 2", 0.6, function() self:swapBay() end)
		end
		return
	end
	-- a lump under a tarp: a top sheet and four sides hanging to the floor
	local tarpTpl = Assets:FindFirstChild("Garage") and Assets.Garage:FindFirstChild("Tarp")
	local sheet = tarpTpl and tarpTpl:FindFirstChildWhichIsA("BasePart", true)
	local tarp = Instance.new("Model")
	tarp.Name = "Tarp"
	tarp.Parent = self.dyn
	local function panel(size: Vector3, cf: CFrame)
		local p: BasePart
		if sheet then
			p = sheet:Clone()
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Size = Vector3.new(0.14, size.Y, size.Z)
			p.CFrame = cf
			p.Parent = tarp
		else
			p = part(tarp, "Sheet", Vector3.new(0.14, size.Y, size.Z), cf, Color3.fromRGB(33, 84, 185), Enum.Material.Fabric)
		end
		p.CastShadow = true
		return p
	end
	local c = self:pos(x, 0, z)
	local up = self:dir(0, 1, 0)
	local cover = prop(Assets:FindFirstChild("Garage") and Assets.Garage:FindFirstChild("TarpCover"), tarp)
	if cover then
		-- a tarp thrown over a wheel on its stand
		local lo, hi = worldBounds(cover)
		local span = hi - lo
		cover:ScaleTo(cover:GetScale() * 5.4 / math.max(span.Y, 0.1))
		for _, d in ipairs(cover:GetDescendants()) do
			if d:IsA("BasePart") then d.CastShadow = true end
		end
		standAt(cover, c)
	end
	-- the lump under it is a wheel on a stand: tall and rounded, a little longer than wide
	local PANELS = cover and 0 or 14
	local topY, topR = 4.9, 1.05
	for i = 1, PANELS do
		local a = (i - 0.5) / PANELS * math.pi * 2
		local stretch = 1 + 0.35 * math.abs(math.cos(a))
		local hemR = (2.75 + ((i % 2 == 0) and 0.3 or -0.05)) * stretch
		local r = self:dir(math.cos(a), 0, math.sin(a))
		local slopeRun = hemR - topR * stretch
		local len = math.sqrt(topY * topY + slopeRun * slopeRun)
		local phi = math.atan2(slopeRun, topY)
		local n = r * math.cos(phi) + up * math.sin(phi)
		local s = up * math.cos(phi) - r * math.sin(phi)
		local mid = c + r * ((hemR + topR * stretch) / 2) + up * (topY / 2)
		local width = 2 * math.pi * hemR / PANELS + 0.35
		panel(Vector3.new(0, len + 0.2, width), CFrame.fromMatrix(mid, n, s))
	end
	-- the cap over the top
	for k = 0, (cover and -1 or 2) do
		panel(Vector3.new(0, 2.5, 3.4), CFrame.new(c + up * (topY + 0.05)) * self.origin.Rotation * CFrame.Angles(0, math.rad(60 * k), 0) * CFrame.Angles(0, 0, math.rad(90)))
	end
	local d = 6.2
	self.tarp = tarp
	-- a slate on the bay's open side, facing into the room
	-- propped at the bay's front corner, angled so both the room and the bay shots can read it
	local sign = part(self.dyn, "BaySign", Vector3.new(0.08, 1.4, 3.4), self:at(x + 4.1, 0.75, z - 1.8) * CFrame.Angles(0, math.atan2(-0.6, 0.8), 0) * CFrame.Angles(0, 0, math.rad(10)), SLATE, Enum.Material.Slate)
	local sg = surface(sign, Enum.NormalId.Right, 110)
	label(sg, "BAY 2", 40, "display", CHALK, UDim2.new(0, 8, 0, 6), UDim2.new(1, -16, 0.5, -6))
	label(sg, ("HOLDS A SECOND BUILD  ·  %s CR"):format(comma(Config.Garage.BayCost)), 22, "monoBold", CHALK, UDim2.new(0, 8, 0.5, 2), UDim2.new(1, -16, 0.5, -8))
	if mine then
		local hit = part(self.dyn, "BayHit", Vector3.new(5, 5, 7), CFrame.new(c + Vector3.new(0, 2.6, 0)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		hit.Transparency = 1
		self:prompt(hit, ("Open it  ·  %s CR"):format(comma(Config.Garage.BayCost)), "Bay 2", 0.8, function() self:unlockBay() end)
	end
end

function Garage:dressDoor()
	local hit = part(self.dyn, "DoorHit", Vector3.new(10, 8, 2), self:at(0, 4, HALF_D - 1.8), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	hit.Transparency = 1
	self:prompt(hit, "Leave", "Garage door", 0, function() self:close() end)
end

--==============================================================
-- visiting
--==============================================================
local function waitFrames(seconds: number, frames: number)
	local t0, n = os.clock(), 0
	while (os.clock() - t0 < seconds or n < frames) and os.clock() - t0 < 4 do
		RunService.RenderStepped:Wait()
		n += 1
	end
end

local function comma1(n: number): string
	return UI.comma(math.floor(n + 0.5))
end

-- what the tray says for each shot, and the button if there's something to do
function Garage:trayFor(i: number): (string, string, string?, (() -> ())?)
	local v = self.view or {}
	local st = STATIONS[i]
	local mine = self.mine
	if st.id == "Room" then
		return mine and "YOUR GARAGE" or (string.upper(tostring(v.name)) .. "'S GARAGE"),
			mine and "EVERYTHING IN HERE WAS EARNED ON THE ROAD" or "HAVE A LOOK ROUND"
	elseif st.id == "Tyres" then
		local n, top, topRuns = 0, nil, 0
		for _, s in ipairs(Config.Skins) do
			if owned(v, s.id) then
				n += 1
				local log = v.tyreLog and v.tyreLog[s.id]
				if log and log.runs > topRuns then top, topRuns = s, log.runs end
			end
		end
		return "TYRE WALL", top and ("%d TYRE%s  ·  MOST RUN: %s, %s RUNS"):format(n, n == 1 and "" or "S", string.upper(top.name), comma1(topRuns))
			or ("%d TYRE%s  ·  NONE RUN YET"):format(n, n == 1 and "" or "S")
	elseif st.id == "Build" then
		local skin = Config.SkinsById[v.skin or "stock"] or Config.SkinsById.stock
		local rim = Config.RimsById[v.rim or "steel"] or Config.RimsById.steel
		local trail = Config.TrailsById[v.trail or "none"] or Config.TrailsById.none
		return "THE BUILD", ("%s  ·  %s  ·  %s"):format(string.upper(skin.name), string.upper(rim.name), trail.id == "none" and "NO TRAIL" or string.upper(trail.name)),
			"SPEC CARD", function()
				self.card:open(v.plot or 0, {
					name = v.name, skin = v.skin, rim = v.rim, trail = v.trail, stickers = v.stickers, pressure = v.pressure,
					best = math.floor((v.bestDistance or 0) * M), rigName = v.rigName,
				})
			end
	elseif st.id == "Shelves" then
		local got = 0
		for _, def in ipairs(Config.Garage.Trophies) do
			local value = 0
			local s = v.stats or {}
			if def.id == "distance" then value = ((v.totals and v.totals.distance) or 0) * M / 1000
			elseif def.id == "runs" then value = s.runs or 0
			elseif def.id == "best" then value = (v.bestDistance or 0) * M
			elseif def.id == "forged" then value = s.forged or 0
			elseif def.id == "flawless" then value = s.flawless or 0
			elseif def.id == "contracts" then value = s.contracts or 0 end
			if value >= def.steps[1] then got += 1 end
		end
		local roads = 0
		for _ in pairs(v.records or {}) do roads += 1 end
		return "TROPHIES AND ROADS", ("%d OF %d TROPHIES  ·  A BEST ON %d ROAD%s  ·  FURTHEST GATE %d"):format(
			got, #Config.Garage.Trophies, roads, roads == 1 and "" or "S", (v.stats and v.stats.maxTier) or 0)
	elseif st.id == "Board" then
		local m = v.metals or {}
		return "PHOTOS AND MEDALS", ("%s M ROLLED  ·  %s BRONZE  ·  %s SILVER  ·  %s GOLD"):format(
			comma1(((v.totals and v.totals.distance) or 0) * M), comma1(m.bronze or 0), comma1(m.silver or 0), comma1(m.gold or 0))
	elseif st.id == "Guestbook" then
		local n = #(v.guestbook or {})
		return "GUESTBOOK", ("%d STAMP%s  ·  %s HONKS"):format(n, n == 1 and "" or "S", comma1(v.honks or 0)),
			(not mine) and "STAMP IT" or nil, (not mine) and function() self:showPicker(true) end or nil
	elseif st.id == "Bay" then
		local bay = v.bay or {}
		if bay.unlocked then
			local skin = Config.SkinsById[bay.skin or "stock"] or Config.SkinsById.stock
			return "BAY 2", "HOLDING " .. string.upper(skin.name), mine and "SWAP BUILDS" or nil, mine and function() self:swapBay() end or nil
		end
		return "BAY 2", "UNDER A TARP  ·  HOLDS A SECOND BUILD TO SWAP IN",
			mine and ("OPEN IT  ·  %s CR"):format(comma1(Config.Garage.BayCost)) or nil, mine and function() self:unlockBay() end or nil
	end
	return "", ""
end

function Garage:paintTray(i: number)
	local title, info, action, fn = self:trayFor(i)
	self.trayTitle.Text = title
	self.trayInfo.Text = info
	self.trayAction.Text = action or ""
	self.trayAction.Visible = action ~= nil
	self.actionFn = fn
end

-- moves to a shot: the tabs light, the tray fades out and back in with its new contents
function Garage:setStation(i: number, instant: boolean?)
	if not STATIONS[i] then return end
	local old = self.stationIndex
	self.stationIndex = i
	for n, b in pairs(self.tabButtons) do
		UI.setButtonStyle(b, n == i and "primary" or "ghost")
	end
	local st = STATIONS[i]
	local eyeL, lookL = st.eye, st.look
	if st.id == "Tyres" and (self.tyreRows or 1) > 1 then
		-- a second rail of tyres: step back and take both in
		eyeL, lookL = Vector3.new(0, 10.6, 0), Vector3.new(0, 10.3, -16)
	end
	local eye, look = self:pos(eyeL.X, eyeL.Y, eyeL.Z), self:pos(lookL.X, lookL.Y, lookL.Z)
	self.camGoal = { eye = eye, look = look, fov = st.fov }
	if instant or not self.camEye then
		self.camEye, self.camLook, self.camFov = eye, look, st.fov
		self.camEyeV, self.camLookV = Vector3.zero, Vector3.zero
		self.camYaw, self.camPitch = aim(eye, look)
		self.camYawV, self.camPitchV = 0, 0
	end
	if instant or old == nil then
		self:paintTray(i)
		self.tray.Visible = true
	elseif old ~= i then
		UI.fade(self.tray, false, { rest = UDim2.new(0.5, 0, 1, -22), dur = 0.18, offset = 16 }, function()
			if self.stationIndex ~= i or not self.isOpen then return end
			self:paintTray(i)
			UI.fade(self.tray, true, { rest = UDim2.new(0.5, 0, 1, -22), dur = 0.3, offset = 22 })
		end)
	end
end

function Garage:open(ownerId: number, index: number, plot: Instance?)
	if self.isOpen or self.busy then return false end
	self.busy = true
	self.plot = plot
	self.index = index
	task.spawn(function()
		local fetched = nil
		local done = false
		task.spawn(function()
			local ok, res = pcall(function() return (Remotes :: any).GetGarage:InvokeServer(ownerId) end)
			fetched = ok and type(res) == "table" and res.ok and res.garage or nil
			if ok and type(res) == "table" and res.err then fetched = { err = res.err } end
			done = true
		end)
		local ws = self.workshop
		if ws and ws.shutterTo then ws:shutterTo(true) end
		local t0 = os.clock()
		while not done and os.clock() - t0 < 6 do task.wait(0.05) end
		if not (fetched and fetched.userId) then
			if ws and ws.shutterTo then ws:shutterTo(false) end
			self.hub:toast((fetched and fetched.err) or "Couldn't open the garage.", T.bad)
			self.busy = false
			if self.onFail then pcall(self.onFail) end
			return
		end
		self.view = fetched
		if self.onEnter then pcall(self.onEnter) end
		local ok, err = pcall(function()
			self:buildShell()
			self:moveTo(index)
			self:dress(fetched)
			self.folder.Parent = workspace
			self:lighting(true)
			self:addMotes()
		end)
		if not ok then warn("[TyreCannon] garage failed to open: " .. tostring(err)) end
		-- load everything in it before the door lifts
		local loaded = false
		task.spawn(function()
			pcall(function() ContentProvider:PreloadAsync(self.folder:GetDescendants()) end)
			loaded = true
		end)
		self.isOpen = true
		self.camEye = nil
		self:setStation(1, true)
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(self.camEye, self.camLook)
		cam.FieldOfView = self.camFov
		table.insert(self.conns, RunService.RenderStepped:Connect(function(dt) self:step(dt) end))
		if self.inputConn then self.inputConn:Disconnect() end
		self.inputConn = UserInputService.InputBegan:Connect(function(input, gpe)
			if not self.isOpen or self.busy then return end
			if input.KeyCode == Enum.KeyCode.ButtonB then
				self:close()
				return
			end
			if gpe or UserInputService:GetFocusedTextBox() then return end
			local n = STATION_KEYS[input.KeyCode]
			if n then self:setStation(n) end
		end)
		local waited = os.clock()
		while not loaded and os.clock() - waited < 3 do task.wait(0.05) end
		waitFrames(0.9, 30)
		self.title.Text = self.mine and "YOUR GARAGE" or (string.upper(tostring(fetched.name)) .. "'S GARAGE")
		self.sub.Text = ""
		self.top.Visible = true
		for _, s in ipairs(self.scrims) do s.Visible = true end
		if ws and ws.shutterTo then ws:shutterTo(false) end
		self.busy = false
	end)
	return true
end

-- slow dust hanging in the air under the strip lights: particles, no light
function Garage:addMotes()
	if not self.folder or self.folder:FindFirstChild("Motes") then return end
	local box = Instance.new("Part")
	box.Name = "Motes"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.Transparency = 1
	box.Size = Vector3.new(WIDTH - 6, HEIGHT - 5, DEPTH - 6)
	box.CFrame = self:at(0, HEIGHT / 2, 0)
	box.Parent = self.folder
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxassetid://84291297587243"
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Rate = 14
	e.Lifetime = NumberRange.new(7, 11)
	e.Speed = NumberRange.new(0.05, 0.25)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -0.02, 0)
	e.RotSpeed = NumberRange.new(-20, 20)
	e.Size = NumberSequence.new(0.07)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(0.8, 0.45), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(Color3.fromRGB(236, 228, 214))
	e.LightInfluence = 1
	e.Parent = box
	e:Emit(90)
end

function Garage:close()
	if not self.isOpen or self.busy then return end
	self.busy = true
	self:showPicker(false)
	task.spawn(function()
		local ws = self.workshop
		if ws and ws.shutterTo then ws:shutterTo(true) end
		self.isOpen = false
		self.top.Visible = false
		self.tray.Visible = false
		for _, s in ipairs(self.scrims) do s.Visible = false end
		self.stationIndex = nil
		if self.inputConn then
			self.inputConn:Disconnect()
			self.inputConn = nil
		end
		pcall(function() self.card:close() end)
		pcall(function() self:clearContents() end)
		pcall(function() self:lighting(false) end)
		if self.folder then self.folder.Parent = nil end
		if self.onExit then pcall(self.onExit) end
		task.wait(0.15)
		if ws and ws.shutterTo then ws:shutterTo(false) end
		self.busy = false
	end)
end

-- the room's lighting: no sky, the strip lights doing the work
function Garage:lighting(on: boolean)
	if on then
		if self.saved then return end
		local saved = { props = {}, effects = {}, atmosphere = nil }
		for _, k in ipairs(LIGHT_KEYS) do saved.props[k] = (Lighting :: any)[k] end
		for _, e in ipairs(Lighting:GetChildren()) do
			if e:IsA("PostEffect") then
				saved.effects[e] = e.Enabled
				e.Enabled = false
			elseif e:IsA("Atmosphere") then
				saved.atmosphere = { inst = e, Density = e.Density, Haze = e.Haze, Glare = e.Glare }
				e.Density = 0
				e.Haze = 0
				e.Glare = 0
			end
		end
		self.saved = saved
		Lighting.Ambient = Color3.fromRGB(58, 56, 54)
		Lighting.OutdoorAmbient = Color3.fromRGB(16, 16, 18)
		Lighting.Brightness = 0
		Lighting.EnvironmentDiffuseScale = 0.1
		Lighting.EnvironmentSpecularScale = 0.3
		Lighting.ExposureCompensation = 0.25
		Lighting.GlobalShadows = true
		local cam = workspace.CurrentCamera
		self.post = {
			UI.mk("ColorCorrectionEffect", { Name = "GarageGrade", Contrast = 0.08, Saturation = -0.02, TintColor = Color3.fromRGB(255, 250, 244), Parent = cam }),
			UI.mk("BloomEffect", { Name = "GarageBloom", Intensity = 0.4, Size = 24, Threshold = 1.6, Parent = cam }),
		}
	else
		local saved = self.saved
		if not saved then return end
		self.saved = nil
		for k, v in pairs(saved.props) do (Lighting :: any)[k] = v end
		for e, enabled in pairs(saved.effects) do
			if e.Parent then e.Enabled = enabled end
		end
		local a = saved.atmosphere
		if a and a.inst.Parent then
			a.inst.Density = a.Density
			a.inst.Haze = a.Haze
			a.inst.Glare = a.Glare
		end
		for _, e in ipairs(self.post or {}) do e:Destroy() end
		self.post = nil
	end
end

function Garage:step(dt: number)
	for _, s in ipairs(self.spinners) do
		s.roll += dt * 0.35
		if s.model.Parent then
			-- rising out of the floor, or sinking back into it
			local drop = 0
			if s.rise then
				local k = math.clamp((os.clock() - s.rise) / RISE_TIME, 0, 1)
				drop = (1 - backOut(k)) * RISE_DEPTH
				if k >= 1 then s.rise = nil end
			elseif s.sink then
				local k = math.clamp((os.clock() - s.sink) / 0.4, 0, 1)
				drop = k * k * RISE_DEPTH
			end
			s.model:PivotTo(s.base * CFrame.new(0, -drop, 0) * CFrame.Angles(0, s.roll, 0))
		end
	end
	local goal = self.camGoal
	if not (goal and self.isOpen) then return end
	local cam = workspace.CurrentCamera
	local vp = cam.ViewportSize
	local mouse = UserInputService:GetMouseLocation()
	local mx = math.clamp(mouse.X / math.max(vp.X, 1) - 0.5, -0.5, 0.5)
	local my = math.clamp(mouse.Y / math.max(vp.Y, 1) - 0.5, -0.5, 0.5)
	local fwd = (goal.look - goal.eye)
	local right = fwd.Magnitude > 0.01 and fwd.Unit:Cross(Vector3.yAxis) or Vector3.xAxis
	if right.Magnitude < 0.01 then right = Vector3.xAxis end
	right = right.Unit
	local eye = goal.eye + right * (mx * 0.7) - Vector3.yAxis * (my * 0.4)
	self.camEye, self.camEyeV = spring(self.camEye, self.camEyeV or Vector3.zero, eye, 5, dt)
	-- the camera turns toward the new shot rather than chasing a look point across the room:
	-- between shots that face opposite walls, a chased point passes through the lens and the
	-- view flips; a turn pans smoothly the short way round
	local goalYaw, goalPitch = aim(goal.eye, goal.look)
	if not self.camYaw then
		self.camYaw, self.camPitch = goalYaw, goalPitch
		self.camYawV, self.camPitchV = 0, 0
	end
	local turn = (goalYaw - self.camYaw + math.pi) % (math.pi * 2) - math.pi
	self.camYaw, self.camYawV = spring1(self.camYaw, self.camYawV or 0, self.camYaw + turn, 3.6, dt)
	self.camPitch, self.camPitchV = spring1(self.camPitch, self.camPitchV or 0, goalPitch, 5, dt)
	self.camFov += (goal.fov - self.camFov) * (1 - math.exp(-dt * 5))
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.new(self.camEye) * CFrame.Angles(0, self.camYaw, 0) * CFrame.Angles(self.camPitch, 0, 0)
	cam.FieldOfView = self.camFov
end

--==============================================================
-- the guestbook and bay 2
--==============================================================
function Garage:showPicker(on: boolean)
	if on == self.pickerOn then return end
	self.pickerOn = on
	UI.fade(self.picker, on, { rest = UDim2.fromScale(0.5, 0.5) })
end

function Garage:stamp(stampId: string)
	local v = self.view
	if not v or self.stamping then return end
	self.stamping = true
	self:showPicker(false)
	task.spawn(function()
		local ok, res = pcall(function() return (Remotes :: any).StampGuestbook:InvokeServer(v.userId, stampId) end)
		self.stamping = false
		if ok and type(res) == "table" and res.ok then
			v.guestbook = res.guestbook
			self:paintGuestbook(v)
			if self.stationIndex then self:paintTray(self.stationIndex) end
			local s = Config.Garage.StampsById[stampId]
			UI.stamp(self.gui, s and s.text or "STAMPED", s and s.color or T.good, "IN " .. string.upper(tostring(v.name)) .. "'S GUESTBOOK")
		else
			self.hub:toast((type(res) == "table" and res.err) or "Couldn't stamp it.", T.bad)
		end
	end)
end

-- the owner's garage as the server has it now, without redressing the room
function Garage:fetchOwn()
	local ok, res = pcall(function() return (Remotes :: any).GetGarage:InvokeServer(Players.LocalPlayer.UserId) end)
	if ok and type(res) == "table" and res.ok and type(res.garage) == "table" then
		return res.garage
	end
	return nil
end

-- a stand comes up out of the floor: the plinth and the turning build ride up together
function Garage:riseStand(name: string)
	local now = os.clock()
	for _, s in ipairs(self.spinners) do
		if s.model.Name == name then s.rise = now end
	end
	for _, suffix in ipairs({ "Plinth", "Edge" }) do
		local p = self.dyn and self.dyn:FindFirstChild(name .. suffix)
		if p and p:IsA("BasePart") then
			local goal = p.CFrame
			p.CFrame = goal - Vector3.new(0, RISE_DEPTH, 0)
			UI.tween(p, RISE_TIME, { CFrame = goal }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end
	local at = self:pos(name == "Bay" and -15 or 0, 0.3, name == "Bay" and 10 or -3)
	task.delay(RISE_TIME * 0.45, function()
		if self.isOpen then pcall(PackFX.burst, "dustRing", CFrame.new(at), 18, nil, 1.3) end
	end)
end

-- the stand sinks back into the floor, then its parts go
function Garage:sinkStand(name: string)
	local now = os.clock()
	for _, s in ipairs(self.spinners) do
		if s.model.Name == name then s.sink = now end
	end
	for _, suffix in ipairs({ "Plinth", "Edge" }) do
		local p = self.dyn and self.dyn:FindFirstChild(name .. suffix)
		if p and p:IsA("BasePart") then
			UI.tween(p, 0.4, { CFrame = p.CFrame - Vector3.new(0, RISE_DEPTH, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end
end

function Garage:dropStand(name: string)
	for i = #self.spinners, 1, -1 do
		if self.spinners[i].model.Name == name then table.remove(self.spinners, i) end
	end
	for _, suffix in ipairs({ "", "Plinth", "Edge", "Hit" }) do
		local p = self.dyn and self.dyn:FindFirstChild(name .. suffix)
		if p then p:Destroy() end
	end
end

function Garage:unlockBay()
	local v = self.view
	if not v or self.bayBusy then return end
	self.bayBusy = true
	task.spawn(function()
		local res = self.hub:call("UnlockBay")
		if type(res) == "table" and res.ok then
			local fresh = self:fetchOwn()
			-- the sign goes first, then the tarp is yanked off backwards and up in one pull
			local sign = self.dyn and self.dyn:FindFirstChild("BaySign")
			if sign and sign:IsA("BasePart") then
				UI.tween(sign, 0.3, { Transparency = 1 })
				for _, d in ipairs(sign:GetDescendants()) do
					if d:IsA("TextLabel") then UI.tween(d, 0.25, { TextTransparency = 1 }) end
				end
			end
			local hit = self.dyn and self.dyn:FindFirstChild("BayHit")
			if hit then hit:Destroy() end
			local tarp = self.tarp
			if tarp and tarp.Parent then
				local box = tarp:GetBoundingBox()
				tarp.WorldPivot = box
				-- pulled across the shot, deeper into the room, clear of the side wall
				local away = self:dir(-0.2, 0, -1).Unit
				local tilt = away:Cross(Vector3.yAxis).Unit
				local parts = {}
				for _, p in ipairs(tarp:GetDescendants()) do
					if p:IsA("BasePart") then table.insert(parts, p) end
				end
				local t0 = os.clock()
				local PULL = 0.85
				local conn
				conn = RunService.RenderStepped:Connect(function()
					local k = math.clamp((os.clock() - t0) / PULL, 0, 1)
					-- a short squash as it's gripped, then the pull accelerates away
					local grip = math.clamp(k / 0.18, 0, 1)
					local pull = math.clamp((k - 0.18) / 0.82, 0, 1)
					local e = pull * pull
					local dip = math.sin(grip * math.pi) * 0.25 * (1 - pull)
					local pos = box.Position + away * (e * 5.5) + Vector3.yAxis * (e * 6.5 - dip)
					local rot = CFrame.fromAxisAngle(tilt, -e * math.rad(55))
					if tarp.Parent then tarp:PivotTo(CFrame.new(pos) * rot * box.Rotation) end
					local fade = math.clamp((pull - 0.35) / 0.65, 0, 1)
					for _, p in ipairs(parts) do p.LocalTransparencyModifier = fade end
					if k >= 1 then conn:Disconnect() end
				end)
				table.insert(self.conns, conn)
				task.delay(0.2, function()
					if self.isOpen then pcall(PackFX.burst, "dustPuff", CFrame.new(box.Position - Vector3.yAxis * (box.Position.Y - self:pos(0, 0.4, 0).Y)), 14, nil, 1.2) end
				end)
				task.wait(PULL)
				tarp:Destroy()
				self.tarp = nil
			end
			if sign then sign:Destroy() end
			if not self.isOpen then self.bayBusy = false return end
			if fresh then self.view = fresh end
			local view = self.view
			view.bay = view.bay or {}
			view.bay.unlocked = true
			-- the second stand comes up out of the floor where the tarp was
			self:standBuild("Bay", -15, 10, view.bay, 0.8)
			self:riseStand("Bay")
			if self.stationIndex then self:paintTray(self.stationIndex) end
			task.wait(RISE_TIME * 0.6)
			UI.stamp(self.gui, "Bay 2", T.good, "OPEN  ·  SWAP BUILDS ON THE STAND")
		elseif type(res) == "table" and res.err then
			self.hub:toast(res.err, T.bad)
		end
		self.bayBusy = false
	end)
end

function Garage:swapBay()
	if self.bayBusy then return end
	self.bayBusy = true
	task.spawn(function()
		local res = self.hub:call("SwapBay")
		if type(res) == "table" and res.ok then
			local fresh = self:fetchOwn()
			-- both stands sink into the floor and come back up holding each other's build
			self:sinkStand("Stand")
			self:sinkStand("Bay")
			task.wait(0.45)
			if self.isOpen and fresh then
				self.view = fresh
				self:dropStand("Stand")
				self:dropStand("Bay")
				self:dressStand(fresh)
				self:standBuild("Bay", -15, 10, fresh.bay or {}, 0.8)
				self:riseStand("Stand")
				self:riseStand("Bay")
				if self.stationIndex then self:paintTray(self.stationIndex) end
			elseif self.isOpen then
				self:refreshOwn()
			end
			self.hub:toast("BUILDS SWAPPED", T.good)
		elseif type(res) == "table" and res.err then
			self.hub:toast(res.err, T.bad)
		end
		self.bayBusy = false
	end)
end

function Garage:refreshOwn()
	if not self.isOpen or not self.mine then return end
	local ok, res = pcall(function() return (Remotes :: any).GetGarage:InvokeServer(Players.LocalPlayer.UserId) end)
	if ok and type(res) == "table" and res.ok then
		self.view = res.garage
		self:dress(res.garage)
		table.insert(self.conns, RunService.RenderStepped:Connect(function(dt) self:step(dt) end))
		if self.stationIndex then self:paintTray(self.stationIndex) end
	end
end

return Garage
