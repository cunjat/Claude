--!strict
-- TYRE CANNON :: Workshop / Wall
-- The parts wall. Every tyre and rim in the game has a hook on the pegboard down the
-- workshop's left wall: rims along the top row, tyres below. Parts you own hang on
-- their hooks as real parts; the rest are empty hooks with a paper tag that hints at
-- what goes there. Hover a part and it sways on its hook. Click one you own and the
-- camera swings back to the bench and fits it; click a tag to try that part on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Config = require(Modules.Config)
local WheelAssembly = require(Modules.WheelAssembly)
local UI = require(script.Parent.Parent.UI)
local Rack = require(script.Parent.Rack)
local T = UI.Theme

local Wall = {}
Wall.__index = Wall

local HANG_D = 2.4
local TAG_PAPER = Color3.fromRGB(226, 218, 196)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

function Wall.new(ws)
	local self = setmetatable({}, Wall)
	self.ws = ws
	self.built = false
	self.entries = {}
	self.hover = nil
	self.active = false
	self.conns = {}

	local frame = UI.mk("Frame", {
		Name = "Wall", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(900, 84),
		BackgroundTransparency = 1, Visible = false, ZIndex = 22, Parent = ws.root,
	})
	UI.autoScale(frame, 1240, 780)
	self.frame = frame
	local function line(text: string, size: number, role: string, color: Color3, y: number): TextLabel
		local l = UI.text(text, size, role, color)
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, 0, y)
		l.Size = UDim2.new(1, 0, 0, size + 6)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.ZIndex = 23
		l.Parent = frame
		return l
	end
	self.title = line("PARTS WALL", 20, "display", T.text, 0)
	self.info = line("", 15, "monoBold", T.dim, 30)
	self.hint = line("Rims up top, tyres below. Click a part to fit it. Empty hooks are parts you haven't got yet.", 14, "body", T.faint, 56)

	self.highlight = Instance.new("Highlight")
	self.highlight.Name = "WallHover"
	self.highlight.FillTransparency = 1
	self.highlight.OutlineTransparency = 0
	self.highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	self.highlight.Enabled = false
	return self
end

--==============================================================
-- building the wall
--==============================================================
function Wall:build()
	local room = self.ws.room
	if self.built or not room or not room.wall then return end
	self.built = true
	local w = room.wall
	local folder = Instance.new("Model")
	folder.Name = "PartsWall"
	folder.Parent = room.folder
	self.folder = folder
	self.highlight.Parent = folder

	local rows = {
		{ def = Rack.KINDS[2], y = w.top - 2.3 },
		{ def = Rack.KINDS[1], y = w.top - 7.9 },
	}
	local steel = Color3.fromRGB(150, 154, 160)
	for _, row in ipairs(rows) do
		local list = row.def.list
		local n = #list
		local span = w.width - 3
		for i, item in ipairs(list) do
			local z = w.z - span / 2 + (i - 0.5) * (span / n)
			local hook = Vector3.new(w.x, row.y, z)
			-- the hook: a peg out of the board with a turned-up tip
			part(folder, "Peg", Vector3.new(0.9, 0.16, 0.16), CFrame.new(hook + Vector3.new(0.45, 0, 0)) * CFrame.Angles(0, 0, 0), steel, Enum.Material.Metal, Enum.PartType.Cylinder)
			part(folder, "Tip", Vector3.new(0.14, 0.3, 0.14), CFrame.new(hook + Vector3.new(0.86, 0.12, 0)), steel, Enum.Material.Metal)

			local entry = { def = row.def, item = item, hook = hook + Vector3.new(0.55, 0, 0), sway = 0, swayT = 99 }

			-- the part itself, hanging by its inner edge; a tyre hangs without its rim, a rim without its tyre
			local model = WheelAssembly.build(nil, {
				diameter = HANG_D,
				skin = row.def.kind == "skin" and item.id or "stock",
				rim = row.def.kind == "rim" and item.id or "steel",
				detail = row.def.kind == "skin" and "low" or nil,
				name = "Hang_" .. item.id,
			})
			if row.def.kind == "skin" then
				local hub = model:FindFirstChild("Hub")
				if hub then hub:Destroy() end
			else
				local carcass = model:FindFirstChild("Carcass")
				if carcass then carcass:Destroy() end
			end
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("Light") then d:Destroy() end
				if d:IsA("BasePart") then
					d.CastShadow = true
					d.CanQuery = false
				end
			end
			local inner = (model:GetAttribute("InnerRadius") :: number?) or HANG_D * 0.4
			local drop = row.def.kind == "skin" and (inner - 0.08) or (inner * 0.92)
			entry.offset = CFrame.new(0.2, -drop, 0) * CFrame.Angles(0, math.rad(90), 0)
			entry.model = model
			model.Parent = folder
			model:PivotTo(CFrame.new(entry.hook) * entry.offset)

			-- what the mouse actually hits
			local hit = part(folder, "Hit", Vector3.new(1.4, HANG_D + 0.4, HANG_D + 0.2), CFrame.new(entry.hook + Vector3.new(0.2, -drop, 0)), steel, Enum.Material.SmoothPlastic)
			hit.Transparency = 1
			hit.CastShadow = false
			hit.CanQuery = true
			entry.hit = hit

			-- the paper tag on an empty hook: a question mark and what it costs
			local tag = part(folder, "Tag", Vector3.new(0.04, 1.05, 0.8), CFrame.new(entry.hook + Vector3.new(0.34, -0.72, 0)) * CFrame.Angles(math.rad(6), 0, 0), TAG_PAPER, Enum.Material.Fabric)
			tag.CastShadow = false
			local string_ = part(folder, "String", Vector3.new(0.03, 0.26, 0.03), CFrame.new(entry.hook + Vector3.new(0.34, -0.1, 0)), Color3.fromRGB(60, 52, 44), Enum.Material.Fabric)
			string_.CastShadow = false
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Right
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 120
			sg.LightInfluence = 1
			sg.Parent = tag
			local tier = Config.CosmeticTier(item)
			local color = Config.TierColor(tier)
			UI.mk("Frame", { Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = color, BorderSizePixel = 0, Parent = sg })
			local q = UI.text("?", 60, "display", Color3.fromRGB(40, 36, 32))
			q.Position = UDim2.fromOffset(0, 10)
			q.Size = UDim2.new(1, 0, 0, 66)
			q.TextXAlignment = Enum.TextXAlignment.Center
			q.Parent = sg
			local price = UI.text("", 17, "monoBold", Color3.fromRGB(70, 62, 54))
			price.Position = UDim2.new(0, 0, 1, -40)
			price.Size = UDim2.new(1, 0, 0, 34)
			price.TextXAlignment = Enum.TextXAlignment.Center
			price.TextScaled = true
			price.Parent = sg
			UI.pad(0, 6, 6, 0, 0).Parent = price
			entry.tag, entry.tagString, entry.tagQ, entry.tagPrice = tag, string_, q, price
			table.insert(self.entries, entry)
		end
	end
end

-- owned parts hang, the rest show their tags, and whatever is on the wheel leaves its hook bare
function Wall:refresh()
	if not self.built then return end
	local ws = self.ws
	local p = ws.profile
	if not p then return end
	for _, e in ipairs(self.entries) do
		local owned = ws:ownsItem(e.def, e.item)
		local fitted = (p[e.def.field] or e.def.default) == e.item.id
		e.owned, e.fitted = owned, fitted
		local hang = owned and not fitted
		for _, d in ipairs(e.model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Root" then d.LocalTransparencyModifier = hang and 0 or 1 end
		end
		local showTag = not hang
		e.tag.Transparency = showTag and 0 or 1
		e.tagString.Transparency = showTag and 0 or 1
		local sg = e.tag:FindFirstChildOfClass("SurfaceGui")
		if sg then sg.Enabled = showTag end
		if fitted then
			e.tagQ.Text = "ON"
			e.tagPrice.Text = "THE WHEEL"
		elseif e.item.robux then
			e.tagQ.Text = "?"
			e.tagPrice.Text = "R$ " .. e.item.robux
		elseif e.item.locked then
			e.tagQ.Text = "?"
			e.tagPrice.Text = "EARNED"
		else
			e.tagQ.Text = "?"
			e.tagPrice.Text = UI.comma(e.item.cost or 0) .. " CR"
		end
	end
	self:describe(self.hover)
end

--==============================================================
-- hovering and clicking
--==============================================================
function Wall:entryAt(pos: Vector2)
	local ray = self.ws:mouseRay(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local hits = {}
	for _, e in ipairs(self.entries) do table.insert(hits, e.hit) end
	params.FilterDescendantsInstances = hits
	local r = workspace:Raycast(ray.Origin, ray.Direction * 80, params)
	if not r then return nil end
	for _, e in ipairs(self.entries) do
		if e.hit == r.Instance then return e end
	end
	return nil
end

function Wall:describe(e)
	if not e then
		self.info.Text = ""
		return
	end
	local tier = Config.CosmeticTier(e.item)
	local color = Config.TierColor(tier)
	local state
	if e.fitted then
		state = "ON THE WHEEL"
	elseif e.owned then
		state = "YOURS  ·  CLICK TO FIT"
	elseif e.item.locked then
		state = "EARNED, NOT BOUGHT  ·  CLICK TO TRY IT ON"
	else
		state = "NOT YOURS YET  ·  CLICK TO TRY IT ON"
	end
	self.info.Text = ('%s  <font color="%s">%s</font>  ·  %s'):format(string.upper(e.item.name), UI.hex(color), string.upper(tier), state)
end

function Wall:setHover(e)
	if self.hover == e then return end
	self.hover = e
	local h = self.highlight
	if e then
		local color = Config.TierColor(Config.CosmeticTier(e.item))
		h.Adornee = (e.owned and not e.fitted) and e.model or e.tag
		h.OutlineColor = color
		h.Enabled = true
		e.swayT = 0
		UI.setCursor("point")
	else
		h.Enabled = false
		UI.setCursor(nil)
	end
	self:describe(e)
end

function Wall:activate(e)
	local ws = self.ws
	if not e or e.fitted or ws.busy then return end
	e.swayT = 0
	ws:setStation("Fit")
	ws.rack.tab = e.def.key
	ws.rack.sig = ""
	ws.rack:refresh()
	-- let the camera swing most of the way back before the swap plays
	task.delay(0.45, function()
		if ws.isOpen and ws.station == "Fit" then ws:useItem(e.def, e.item) end
	end)
end

--==============================================================
-- station lifecycle
--==============================================================
function Wall:enter()
	self:build()
	self:refresh()
	self.active = true
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
	table.insert(self.conns, UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or not self.active or self.ws.busy then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local pos = input.UserInputType == Enum.UserInputType.Touch and Vector2.new(input.Position.X, input.Position.Y) or UserInputService:GetMouseLocation()
			self:activate(self:entryAt(pos))
		end
	end))
end

function Wall:leave()
	if not self.active then return end
	self.active = false
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
	self:setHover(nil)
end

function Wall:setVisible(v: boolean)
	self.frame.Visible = v
end

function Wall:step(dt: number)
	if not self.active then return end
	self:setHover(self:entryAt(UserInputService:GetMouseLocation()))
	-- the hand cursor lapses unless it's asked for every frame
	if self.hover then UI.setCursor("point") end
	-- a hovered part sways on its hook and settles
	for _, e in ipairs(self.entries) do
		if e.swayT < 3 then
			e.swayT += dt
			local a = math.rad(9) * math.sin(e.swayT * 5.2) * math.exp(-e.swayT * 1.6)
			local swing = CFrame.new(e.hook) * CFrame.Angles(a, 0, 0)
			e.model:PivotTo(swing * e.offset)
			e.tag.CFrame = swing * CFrame.new(0.34, -0.72, 0) * CFrame.Angles(math.rad(6), 0, 0)
			e.tagString.CFrame = swing * CFrame.new(0.34, -0.1, 0)
		end
	end
end

return Wall
