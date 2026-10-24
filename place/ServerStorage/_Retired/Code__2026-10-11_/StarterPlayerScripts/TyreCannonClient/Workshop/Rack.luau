--!strict
-- TYRE CANNON :: Workshop / Rack
-- The FIT station's tray. Category tabs on top, the shop's cards in the first
-- row and everything you own in the row under it. Each card's name sits above
-- it and its border carries the rarity from the price band; Epic and up turn
-- slowly. Tap a card, or drag it onto the wheel, to fit it. Parts you don't
-- own go on as a try-on first, with BUY and PUT BACK in the header.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Config = require(Modules.Config)
local WheelAssembly = require(Modules.WheelAssembly)
local UI = require(script.Parent.Parent.UI)
local Prefs = require(script.Parent.Parent.Prefs)
local DoorArt = require(Modules:WaitForChild("DoorArt"))
local T = UI.Theme

local Rack = {}
Rack.__index = Rack

Rack.KINDS = {
	{ key = "Tyres", kind = "skin", list = Config.Skins, cat = "skins", field = "skin", default = "stock", label = "TYRE" },
	{ key = "Rims", kind = "rim", list = Config.Rims, cat = "rims", field = "rim", default = "steel", label = "RIM" },
	{ key = "Trails", kind = "trail", list = Config.Trails, cat = "trails", field = "trail", default = "none", label = "TRAIL" },
}

local TABS = { "Tyres", "Rims", "Trails", "Pressure", "Door" }
local CARD_W, CARD_H = 112, 112
local TIER_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Premium = 6 }

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 70)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 150)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90, 170, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 110, 255)),
})

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function centred(parent: Instance, text: string, size: number, role: string, color: Color3, y: number, h: number): TextLabel
	local l = UI.text(text, size, role, color)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.Size = UDim2.new(1, 0, 0, h)
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.ZIndex = 24
	l.Parent = parent
	return l
end

local function row(parent: Instance, y: number, h: number): ScrollingFrame
	local sf = UI.mk("ScrollingFrame", {
		Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = T.lineHi, ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ElasticBehavior = Enum.ElasticBehavior.Never,
		ZIndex = 22, Parent = parent,
	})
	local layout = UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	layout.Parent = sf
	UI.centreScroll(sf, layout)
	return sf
end

--==============================================================
function Rack.new(ws)
	local self = setmetatable({}, Rack)
	self.ws = ws
	self.tab = "Tyres"
	self.sig = ""
	self.spinners = {}
	self.drag = nil
	self.dragOver = false
	self.knobDrag = false
	self.pressureValue = Config.Pressure.Default

	local frame = UI.mk("Frame", {
		Name = "Rack", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(1140, 340), BackgroundTransparency = 1, Visible = false, ZIndex = 22, Parent = ws.root,
	})
	UI.autoScale(frame, 1240, 780)
	self.frame = frame

	local tabs = UI.mk("Frame", {
		Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, ZIndex = 22, Parent = frame,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	self.tabButtons = {}
	for i, name in ipairs(TABS) do
		local b = UI.button(string.upper(name), "ghost", 118, 32)
		b.TextSize = 15
		b.LayoutOrder = i
		b.ZIndex = 23
		b.Parent = tabs
		b.Activated:Connect(function()
			self.tab = name
			self.sig = ""
			self:refresh()
		end)
		self.tabButtons[name] = b
	end

	-- header: FOR SALE, or the try-on controls while a part is on the wheel
	local header = UI.mk("Frame", {
		Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, ZIndex = 22, Parent = frame,
	})
	self.header = header
	self.shopLabel = centred(header, "FOR SALE", 13, "monoBold", T.faint, 12, 16)
	local banner = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1, Visible = false, ZIndex = 23, Parent = header,
	}, { UI.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	self.banner = banner
	local bannerName = UI.text("", 18, "display", T.text)
	bannerName.AutomaticSize = Enum.AutomaticSize.X
	bannerName.Size = UDim2.fromOffset(0, 36)
	bannerName.LayoutOrder = 1
	bannerName.ZIndex = 24
	bannerName.Parent = banner
	self.bannerName = bannerName
	local bannerTier = UI.chip("common", T.dim)
	bannerTier.LayoutOrder = 2
	bannerTier.ZIndex = 24
	bannerTier.Parent = banner
	self.bannerTier = bannerTier
	local buy = UI.button("BUY", "primary", 200, 34)
	buy.TextSize = 15
	buy.LayoutOrder = 3
	buy.ZIndex = 24
	buy.Parent = banner
	buy.Activated:Connect(function() ws:buyTryOn() end)
	self.buyButton = buy
	local back = UI.button("PUT BACK", "ghost", 120, 34)
	back.TextSize = 15
	back.LayoutOrder = 4
	back.ZIndex = 24
	back.Parent = banner
	back.Activated:Connect(function() ws:putBack() end)
	local gift = UI.button("GIFT", "ghost", 96, 34)
	gift.Name = "GiftButton"
	gift.TextSize = 15
	gift.LayoutOrder = 5
	gift.ZIndex = 24
	gift.Parent = banner
	gift.Activated:Connect(function()
		local t = ws.tryOn
		if t and ws.gifts then ws.gifts:openPicker(t.def, t.item) end
	end)
	UI.tooltip(gift, "Buy this for someone else in the server. It waits on their bench, wrapped.")
	self.giftButton = gift

	self.shopRow = row(frame, 80, CARD_H + 6)
	self.rackLabel = centred(frame, "ON YOUR RACK", 13, "monoBold", T.faint, 202, 16)
	self.rackRow = row(frame, 220, CARD_H + 6)

	self:buildPressure()
	self:buildDoor()

	-- the card that follows the pointer while dragging
	local ghost = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(120, 40), BackgroundColor3 = T.panel,
		BackgroundTransparency = 0.05, BorderSizePixel = 0, Visible = false, ZIndex = 300, Parent = ws.root,
	})
	UI.corner(5).Parent = ghost
	self.ghostStroke = UI.stroke(T.accent, 2)
	self.ghostStroke.Parent = ghost
	local gt = UI.text("", 14, "display", T.text)
	gt.Size = UDim2.fromScale(1, 1)
	gt.TextXAlignment = Enum.TextXAlignment.Center
	gt.TextTruncate = Enum.TextTruncate.AtEnd
	gt.ZIndex = 301
	gt.Parent = ghost
	self.ghost = ghost
	self.ghostText = gt

	UserInputService.InputEnded:Connect(function(input)
		if not isPress(input) then return end
		if self.knobDrag then
			self.knobDrag = false
			local v = self.pressureValue
			task.spawn(function() ws:call("SetPressure", v) end)
		end
		local d = self.drag
		if not d then return end
		local over = ws.isOpen and ws:overWheel(UserInputService:GetMouseLocation())
		self:cancelDrag()
		if over then ws:useItem(d.def, d.item) end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if self.knobDrag and isMove(input) then
			self:pressureFromX(UserInputService:GetMouseLocation().X)
		end
	end)
	return self
end

--==============================================================
-- pressure
--==============================================================
function Rack:buildPressure()
	local pane = UI.mk("Frame", {
		Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44), BackgroundTransparency = 1,
		Visible = false, ZIndex = 22, Parent = self.frame,
	})
	self.pressure = pane
	centred(pane, "TYRE PRESSURE", 18, "display", T.text, 18, 24)
	self.pValue = centred(pane, "", 30, "display", T.accent, 44, 34)
	local track = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(620, 10),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = true, ZIndex = 23, Parent = pane,
	})
	UI.corner(5).Parent = track
	UI.mk("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, T.good), ColorSequenceKeypoint.new(0.5, T.warn), ColorSequenceKeypoint.new(1, T.bad),
		}),
		Parent = track,
	})
	local knob = UI.mk("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = T.text, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 24, Parent = track,
	})
	UI.corner(13).Parent = knob
	UI.stroke(T.accentDeep, 2).Parent = knob
	self.track = track
	self.knob = knob
	local soft = UI.text("SOFT", 12, "monoBold", T.good)
	soft.AnchorPoint = Vector2.new(1, 0.5)
	soft.Position = UDim2.new(0, -14, 0.5, 0)
	soft.Size = UDim2.fromOffset(50, 16)
	soft.TextXAlignment = Enum.TextXAlignment.Right
	soft.ZIndex = 23
	soft.Parent = track
	local hard = UI.text("HARD", 12, "monoBold", T.bad)
	hard.AnchorPoint = Vector2.new(0, 0.5)
	hard.Position = UDim2.new(1, 14, 0.5, 0)
	hard.Size = UDim2.fromOffset(50, 16)
	hard.ZIndex = 23
	hard.Parent = track
	self.pEffect = centred(pane, "", 14, "monoBold", T.dim, 134, 18)
	centred(pane, "Soft grips and soaks up landings. Hard bounces higher and rolls further.", 14, "body", T.faint, 160, 18)

	local function grab(input: InputObject)
		if not isPress(input) then return end
		self.knobDrag = true
		self:pressureFromX(UserInputService:GetMouseLocation().X)
	end
	knob.InputBegan:Connect(grab)
	track.InputBegan:Connect(grab)
end

function Rack:pressureFromX(x: number)
	local a, s = self.track.AbsolutePosition, self.track.AbsoluteSize
	self:setPressureVisual((x - a.X) / math.max(1, s.X) * 100)
end

function Rack:setPressureVisual(v: number)
	local pressure = math.clamp(math.floor(v + 0.5), 0, 100)
	self.pressureValue = pressure
	self.knob.Position = UDim2.fromScale(pressure / 100, 0.5)
	self.pValue.Text = ("%d PSI"):format(math.floor(20 + pressure * 0.4 + 0.5))
	local pm = Config.PressureMods(pressure)
	local function pct(x: number): string
		local d = math.floor((x - 1) * 100 + 0.5)
		return (d >= 0 and "+" or "") .. d .. "%"
	end
	self.pEffect.Text = ("GRIP %s     BOUNCE %s     ROLLING DRAG %s"):format(pct(pm.grip), pct(pm.bounce), pct(pm.roll))
end

--==============================================================
-- door: your shutter's paint and stencil, and the name stamped on your rig
--==============================================================
function Rack:buildDoor()
	local pane = UI.mk("Frame", {
		Name = "DoorPane", Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44), BackgroundTransparency = 1,
		Visible = false, ZIndex = 22, Parent = self.frame,
	})
	self.doorPane = pane

	-- the preview, framed like the slot it sits in
	local frame = UI.plate("slot", {
		Name = "Preview", Position = UDim2.fromOffset(120, 18), Size = UDim2.fromOffset(360, 214), ZIndex = 23, Parent = pane,
	})
	local inner = UI.mk("Frame", {
		Name = "Inner", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 24, Parent = frame,
	})
	self.doorPreview = inner
	local cap = UI.text("YOUR DOOR", 12, "monoBold", T.faint)
	cap.AnchorPoint = Vector2.new(0.5, 0)
	cap.Position = UDim2.new(0.5, 0, 1, 6)
	cap.Size = UDim2.fromOffset(360, 16)
	cap.TextXAlignment = Enum.TextXAlignment.Center
	cap.ZIndex = 23
	cap.Parent = frame

	local col = 540
	local function label(text: string, y: number, tip: string)
		local l = UI.text(text, 13, "monoBold", T.dim)
		l.Position = UDim2.fromOffset(col, y)
		l.Size = UDim2.fromOffset(300, 16)
		l.ZIndex = 23
		l.Parent = pane
		UI.tooltip(l, tip)
	end

	label("PAINT", 12, "Paint for the roller door. It shows on the workbench shutter and on your yard's garage.")
	self.swatches = {}
	for i, paint in ipairs(Config.DoorPaints) do
		local b = UI.mk("TextButton", {
			Name = "Paint_" .. paint.id, Position = UDim2.fromOffset(col + (i - 1) * 54, 32), Size = UDim2.fromOffset(46, 46),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 23, Parent = pane,
		})
		UI.plate("slot", { Size = UDim2.fromScale(1, 1), ZIndex = 23, Parent = b })
		UI.mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = Color3.fromRGB(150, 152, 156):Lerp(paint.tint, 0.85), BorderSizePixel = 0, ZIndex = 24, Parent = b,
		})
		local trim = UI.plate("cardTrim", { Name = "Trim", Size = UDim2.fromScale(1, 1), ImageColor3 = T.line, ImageTransparency = 0.45, ZIndex = 25, Parent = b })
		UI.tooltip(b, paint.name)
		b.Activated:Connect(function() Prefs.set("doorPaint", paint.id, true) end)
		self.swatches[paint.id] = trim
	end

	label("STENCIL", 92, "Sprayed over the paint. Rig Name uses the name below.")
	local options = {}
	for _, s in ipairs(Config.DoorStencils) do table.insert(options, { id = s.id, label = s.name }) end
	local stencils, setStencil = UI.choices(options, Prefs.get("doorStencil") or "none", 112, 32, function(id)
		Prefs.set("doorStencil", id, true)
	end)
	stencils.Position = UDim2.fromOffset(col, 112)
	stencils.Parent = pane
	for _, b in ipairs(stencils:GetChildren()) do
		if b:IsA("TextButton") then
			b.TextSize = 12
			b.ZIndex = 23
		end
	end

	label("RIG NAME", 160, "Stamped on a brass plate on your rig and shown on your yard sign. Roblox's text filter checks it.")
	local box = UI.plate("slot", { Name = "NameBox", Position = UDim2.fromOffset(col, 180), Size = UDim2.fromOffset(300, 38), ZIndex = 23, Parent = pane })
	local input = UI.mk("TextBox", {
		Name = "RigName", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), BackgroundTransparency = 1,
		Text = Prefs.get("rigName") or "", PlaceholderText = "Name your rig", PlaceholderColor3 = T.faint, ClearTextOnFocus = false,
		FontFace = UI.Fonts.display, TextSize = 17, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 24, Parent = box,
	})
	input:GetPropertyChangedSignal("Text"):Connect(function()
		local max = Config.RigName.MaxLength
		if #input.Text > max then input.Text = input.Text:sub(1, max) end
	end)
	local stamp = UI.button("STAMP IT", "primary", 130, 38)
	stamp.Name = "StampName"
	stamp.TextSize = 15
	stamp.Position = UDim2.fromOffset(col + 310, 180)
	stamp.ZIndex = 23
	stamp.Parent = pane
	local function submit()
		local text = input.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if text == (Prefs.get("rigName") or "") then return end
		Prefs.set("rigName", text, true)
		UI.stamp(self.ws.gui, text == "" and "Name cleared" or text, Color3.fromRGB(214, 170, 90), "RIG NAME  ·  STAMPED ON YOUR PLATE")
	end
	stamp.Activated:Connect(submit)
	input.FocusLost:Connect(function(enter) if enter then submit() end end)

	local function repaint()
		for id, trim in pairs(self.swatches) do
			local on = id == (Prefs.get("doorPaint") or "steel")
			trim.ImageColor3 = on and T.accent or T.line
			trim.ImageTransparency = on and 0 or 0.45
		end
		setStencil(Prefs.get("doorStencil") or "none")
		if not input:IsFocused() then input.Text = Prefs.get("rigName") or "" end
		if pane.Visible then self:paintDoorPreview() end
	end
	Prefs.watch("doorPaint", repaint)
	Prefs.watch("doorStencil", repaint)
	Prefs.watch("rigName", repaint)
end

function Rack:paintDoorPreview()
	local ws = self.ws
	local opts = ws:doorOptions()
	opts.paint = Prefs.get("doorPaint")
	opts.stencil = Prefs.get("doorStencil")
	opts.name = Prefs.get("rigName")
	opts.zIndex = 24
	opts.stickerScale = 1
	DoorArt.paint(self.doorPreview, opts)
end

--==============================================================
-- cards
--==============================================================
function Rack:def()
	for _, d in ipairs(Rack.KINDS) do
		if d.key == self.tab then return d end
	end
	return Rack.KINDS[1]
end

function Rack:swatch(box: Frame, def, item)
	local p = self.ws.profile
	if def.kind == "trail" then
		if item.a then
			local band = UI.mk("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.new(0.84, 0, 0, 16),
				BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 25, Parent = box,
			})
			UI.corner(8).Parent = band
			UI.mk("UIGradient", {
				Color = item.rainbow and RAINBOW or ColorSequence.new(item.b or item.a, item.a),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0),
				}),
				Parent = band,
			})
		else
			centred(box, "NO TRAIL", 12, "monoBold", T.faint, 20, 16).ZIndex = 25
		end
		return
	end
	local vpf = UI.mk("ViewportFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 25,
		Ambient = Color3.fromRGB(120, 116, 112), LightColor = Color3.fromRGB(255, 236, 214),
		LightDirection = Vector3.new(-0.4, -0.6, -1), Parent = box,
	})
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(7.2, 1.5, 12.2), Vector3.new(0, -0.45, 0))
	cam.Parent = vpf
	vpf.CurrentCamera = cam
	local model = WheelAssembly.build(nil, {
		diameter = 6,
		skin = def.kind == "skin" and item.id or (p and p.skin or "stock"),
		rim = def.kind == "rim" and item.id or (p and p.rim or "steel"),
		detail = "low",
	})
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Light") then d:Destroy() end
	end
	model.Parent = vpf
end

function Rack:pressable(button: GuiButton, onTap: () -> (), onDrag: (Vector2) -> ())
	button.InputBegan:Connect(function(input)
		if not isPress(input) then return end
		local start = UserInputService:GetMouseLocation()
		local started = false
		local moveConn, endConn
		moveConn = UserInputService.InputChanged:Connect(function(i2)
			if not isMove(i2) then return end
			local pos = UserInputService:GetMouseLocation()
			if not started and (pos - start).Magnitude > 8 then
				started = true
				onDrag(pos)
			end
		end)
		endConn = UserInputService.InputEnded:Connect(function(i2)
			if not isPress(i2) then return end
			moveConn:Disconnect()
			endConn:Disconnect()
			if not started then onTap() end
		end)
	end)
end

function Rack:card(parent: Instance, def, item, order: number, owned: boolean)
	local ws = self.ws
	local p = ws.profile
	local tier = Config.CosmeticTier(item)
	local color = Config.TierColor(tier)
	local trying = ws.tryOn ~= nil and ws.tryOn.item == item
	local on = (p[def.field] or def.default) == item.id and not (ws.tryOn and ws.tryOn.def == def)

	local cell = UI.mk("TextButton", {
		Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		LayoutOrder = order, ZIndex = 23, Parent = parent,
	})
	local title = centred(cell, string.upper(item.name), 12, "display", owned and T.text or T.dim, 0, 14)
	title.TextTruncate = Enum.TextTruncate.AtEnd

	-- the same pressed slot as the sticker sheet; the rarity tints its trim, softly until the
	-- part is on the wheel. Epic and up turn slowly.
	local box = UI.mk("Frame", {
		Position = UDim2.fromOffset(4, 17), Size = UDim2.fromOffset(CARD_W - 8, 74),
		BackgroundTransparency = 1, ZIndex = 23, Parent = cell,
	})
	UI.plate("slot", { Name = "Plate", Size = UDim2.fromScale(1, 1), ZIndex = 23, Parent = box })
	local lit = on or trying
	local restColor = lit and color or color:Lerp(T.line, 0.5)
	local restTrans = lit and 0 or 0.25
	local edge = UI.plate("cardTrim", {
		Name = "Trim", Size = UDim2.fromScale(1, 1), ImageColor3 = restColor,
		ImageTransparency = restTrans, ZIndex = 26, Parent = box,
	})
	local grad = UI.mk("UIGradient", {
		Rotation = 35,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(190, 190, 190)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 120, 120)),
		}),
		Parent = edge,
	})
	if (TIER_ORDER[tier] or 0) >= 4 then table.insert(self.spinners, grad) end
	self:swatch(box, def, item)
	local tierLabel = UI.text(string.upper(tier), 9, "monoBold", color)
	tierLabel.AnchorPoint = Vector2.new(0.5, 1)
	tierLabel.Position = UDim2.new(0.5, 0, 1, -4)
	tierLabel.Size = UDim2.new(1, 0, 0, 11)
	tierLabel.TextXAlignment = Enum.TextXAlignment.Center
	tierLabel.TextStrokeTransparency = 0.2
	tierLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	tierLabel.ZIndex = 26
	tierLabel.Parent = box

	local text, tc
	if trying then
		text, tc = "ON THE WHEEL", T.info
	elseif on then
		text, tc = "FITTED", T.accent
	elseif owned then
		text, tc = "OWNED", T.good
	elseif item.robux then
		text, tc = "R$ " .. item.robux, Config.PremiumColor
	elseif item.locked then
		text, tc = "EARNED", T.faint
	else
		text, tc = UI.comma(item.cost) .. " CR", (p.credits >= item.cost) and T.text or T.faint
	end
	centred(cell, text, 11, "monoBold", tc, 95, 14)

	cell.MouseEnter:Connect(function()
		edge.ImageTransparency = 0
		if not lit then edge.ImageColor3 = color:Lerp(T.lineHi, 0.35) end
	end)
	cell.MouseLeave:Connect(function()
		edge.ImageTransparency = restTrans
		edge.ImageColor3 = restColor
	end)
	self:pressable(cell, function()
		ws:useItem(def, item)
	end, function(pos)
		self:beginDrag(def, item, color, pos)
	end)
end

function Rack:beginDrag(def, item, color: Color3, pos: Vector2)
	self.drag = { def = def, item = item, color = color }
	self.ghostText.Text = string.upper(item.name)
	self.ghostStroke.Color = color
	self.ghost.Position = UDim2.fromOffset(pos.X, pos.Y)
	self.ghost.Visible = true
	UI.setCursor("grabbing")
	self.ws.turning = false
end

function Rack:cancelDrag()
	self.drag = nil
	self.dragOver = false
	self.ghost.Visible = false
	UI.setCursor(nil)
	self.ws:highlightWheel(nil)
end

--==============================================================
function Rack:showBanner()
	local ws = self.ws
	local t = ws.tryOn
	local p = ws.profile
	self.banner.Visible = t ~= nil
	self.shopLabel.Visible = t == nil
	if not t or not p then return end
	local item = t.item
	local tier = Config.CosmeticTier(item)
	local color = Config.TierColor(tier)
	self.bannerName.Text = "TRYING  " .. string.upper(item.name)
	self.giftButton.Visible = ws.gifts ~= nil and ws.gifts:canGift(item)
	self.bannerTier.Text = string.upper(tier)
	self.bannerTier.TextColor3 = color
	local st = self.bannerTier:FindFirstChildOfClass("UIStroke")
	if st then st.Color = color end
	if item.robux then
		self.buyButton.Text = "BUY  R$ " .. item.robux
		UI.setButtonStyle(self.buyButton, (item.devProductId or 0) ~= 0 and "good" or "off")
	elseif item.locked then
		self.buyButton.Text = "EARNED ONLY"
		UI.setButtonStyle(self.buyButton, "off")
	else
		self.buyButton.Text = "BUY  " .. UI.comma(item.cost) .. " CR"
		UI.setButtonStyle(self.buyButton, p.credits >= item.cost and "primary" or "off")
	end
end

function Rack:prebuild()
	self.sig = ""
	self:refresh(true)
end

function Rack:refresh(force: boolean?)
	local ws = self.ws
	local p = ws.profile
	for n, b in pairs(self.tabButtons) do
		UI.setButtonStyle(b, n == self.tab and "primary" or "ghost")
	end
	self:showBanner()
	if not p or (not self.frame.Visible and not force) then return end
	local isPressure = self.tab == "Pressure"
	local isDoor = self.tab == "Door"
	local cards = not (isPressure or isDoor)
	self.pressure.Visible = isPressure
	self.doorPane.Visible = isDoor
	self.header.Visible = cards
	self.shopRow.Visible = cards
	self.rackRow.Visible = cards
	self.rackLabel.Visible = cards
	if isPressure then
		if not self.knobDrag then self:setPressureVisual(p.pressure or Config.Pressure.Default) end
		return
	end
	if isDoor then
		self:paintDoorPreview()
		return
	end

	local def = self:def()
	local shop, owned = {}, {}
	local bits = { self.tab, p.skin or "", p.rim or "", p.trail or "", ws.tryOn and ws.tryOn.item.id or "" }
	for _, item in ipairs(def.list) do
		if ws:ownsItem(def, item) then
			table.insert(owned, item)
			table.insert(bits, "o" .. item.id)
		else
			table.insert(shop, item)
			table.insert(bits, ((p.credits or 0) >= (item.cost or 0)) and "y" or "n")
		end
	end
	local sig = table.concat(bits, "|")
	if sig == self.sig then return end
	self.sig = sig

	for _, sf in ipairs({ self.shopRow, self.rackRow }) do
		for _, c in ipairs(sf:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
	end
	self.spinners = {}
	table.sort(shop, function(a, b)
		local ra, rb = a.robux ~= nil, b.robux ~= nil
		if ra ~= rb then return rb end
		local ta, tb = TIER_ORDER[Config.CosmeticTier(a)] or 0, TIER_ORDER[Config.CosmeticTier(b)] or 0
		if ta ~= tb then return ta < tb end
		return (a.cost or 0) < (b.cost or 0)
	end)
	for i, item in ipairs(shop) do self:card(self.shopRow, def, item, i, false) end
	for i, item in ipairs(owned) do self:card(self.rackRow, def, item, i, true) end
	if #shop == 0 then
		local l = UI.text("YOU OWN EVERY ONE", 14, "monoBold", T.good)
		l.Size = UDim2.fromOffset(300, 60)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.ZIndex = 24
		l.Parent = self.shopRow
	end
end

function Rack:setVisible(v: boolean)
	self.frame.Visible = v
	if not v then
		self:cancelDrag()
	else
		self.sig = ""
	end
end

function Rack:step(_dt: number)
	if #self.spinners > 0 then
		local r = (os.clock() * 45) % 360
		for _, g in ipairs(self.spinners) do
			if g.Parent then g.Rotation = r end
		end
	end
	local d = self.drag
	if d then
		local pos = UserInputService:GetMouseLocation()
		self.ghost.Position = UDim2.fromOffset(pos.X, pos.Y)
		local over = self.ws:overWheel(pos)
		if over ~= self.dragOver then
			self.dragOver = over
			self.ws:highlightWheel(over and d.color or nil)
			self.ghost.BackgroundTransparency = over and 0.55 or 0.05
		end
	end
end

return Rack
