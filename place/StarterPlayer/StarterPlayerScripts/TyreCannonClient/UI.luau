--!strict
-- TYRE CANNON :: UI
-- One look for the whole game: soot-black steel and hot-metal orange, set in
-- Builder Sans throughout.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Config"))
local Prefs = require(script.Parent.Prefs)

local UI = {}

UI.Theme = {
	void      = Color3.fromRGB(8, 7, 6),
	panel     = Color3.fromRGB(21, 19, 17),
	raised    = Color3.fromRGB(33, 30, 27),
	sunk      = Color3.fromRGB(13, 12, 11),
	line      = Color3.fromRGB(58, 52, 46),
	lineHi    = Color3.fromRGB(92, 83, 74),
	text      = Color3.fromRGB(244, 238, 228),
	dim       = Color3.fromRGB(172, 162, 150),
	faint     = Color3.fromRGB(112, 104, 96),
	-- the house amber (Kit.C.accent), so the older screens match the revamp's panels
	accent    = Color3.fromRGB(232, 140, 40),
	accentDeep = Color3.fromRGB(140, 76, 18),
	accentInk = Color3.fromRGB(255, 246, 244),
	heat      = Color3.fromRGB(255, 138, 31),
	good      = Color3.fromRGB(98, 222, 140),
	info      = Color3.fromRGB(110, 186, 255),
	bad       = Color3.fromRGB(255, 98, 84),
	warn      = Color3.fromRGB(255, 200, 72),
	bronze    = Color3.fromRGB(205, 128, 70),
	silver    = Color3.fromRGB(196, 206, 218),
	gold      = Color3.fromRGB(246, 196, 64),
}
local T = UI.Theme

local function family(name: string): string
	return "rbxasset://fonts/families/" .. name .. ".json"
end

UI.Fonts = {
	-- Montserrat (Roblox's Gotham): the heavy rounded-geometric face Anime Expeditions uses
	display    = Font.new(family("Montserrat"), Enum.FontWeight.Heavy),
	displayMed = Font.new(family("Montserrat"), Enum.FontWeight.Bold),
	body       = Font.new(family("Montserrat"), Enum.FontWeight.Medium),
	bodySemi   = Font.new(family("Montserrat"), Enum.FontWeight.Bold),
	bodyBold   = Font.new(family("Montserrat"), Enum.FontWeight.Bold),
	mono       = Font.new(family("BuilderSans"), Enum.FontWeight.Medium),
	monoBold   = Font.new(family("BuilderSans"), Enum.FontWeight.Bold),
}

-- The steel kit: plates drawn from the logo's palette, stretched from their edges so
-- one image serves any size. Slice margins are in the image's own pixels.
UI.Kit = {
	panel        = { id = "rbxassetid://97778618709793", slice = Rect.new(56, 56, 200, 200), soft = 280 },
	header       = { id = "rbxassetid://105592095684302", slice = Rect.new(64, 0, 448, 112), soft = 220 },
	steelNormal  = { id = "rbxassetid://98887928626691", slice = Rect.new(36, 36, 220, 60), soft = 110 },
	steelHover   = { id = "rbxassetid://110668795548117", slice = Rect.new(36, 36, 220, 60), soft = 110 },
	steelPressed = { id = "rbxassetid://86457219947735", slice = Rect.new(36, 36, 220, 60), soft = 110 },
	steelOff     = { id = "rbxassetid://129077549724041", slice = Rect.new(36, 36, 220, 60), soft = 110 },
	redNormal    = { id = "rbxassetid://89079240238364", slice = Rect.new(36, 36, 220, 60), soft = 110 },
	redHover     = { id = "rbxassetid://106570912481096", slice = Rect.new(36, 36, 220, 60), soft = 110 },
	redPressed   = { id = "rbxassetid://140543045010920", slice = Rect.new(36, 36, 220, 60), soft = 110 },
	close        = { id = "rbxassetid://73722292003573", slice = Rect.new(0, 0, 64, 64), soft = 64 },
	tab          = { id = "rbxassetid://72018992188358", slice = Rect.new(28, 0, 164, 64), soft = 70 },
	tabOn        = { id = "rbxassetid://121538701822534", slice = Rect.new(28, 0, 164, 64), soft = 70 },
	card         = { id = "rbxassetid://70696084122100", slice = Rect.new(40, 40, 152, 200), soft = 200 },
	cardTrim     = { id = "rbxassetid://127264759921823", slice = Rect.new(40, 40, 152, 200), soft = 200 },
	divider      = { id = "rbxassetid://103341354622371", slice = Rect.new(16, 0, 496, 14), soft = 20 },
	slot         = { id = "rbxassetid://122581976835359", slice = Rect.new(32, 32, 128, 88), soft = 130 },
	scroll       = { id = "rbxassetid://124665387692716", slice = Rect.new(0, 8, 16, 120), soft = 40 },
}

-- pixel icons from the cursor pack, recoloured to match
UI.Icons = {
	lock = "rbxassetid://120982646703853",
	unlock = "rbxassetid://133582138377684",
	reticle = "rbxassetid://103620879873672",
	arrowDown = "rbxassetid://76497606234776",
}

-- a kit plate that keeps its corners crisp as it is stretched
function UI.plate(kind: string, props: { [string]: any }?): ImageLabel
	local k = UI.Kit[kind] or UI.Kit.panel
	local img = UI.mk("ImageLabel", props or {})
	img.BackgroundTransparency = 1
	img.Image = k.id
	img.ScaleType = Enum.ScaleType.Slice
	img.SliceCenter = k.slice
	local function fit()
		local a = img.AbsoluteSize
		img.SliceScale = math.clamp(math.min(a.X, a.Y) / k.soft, 0.25, 1)
	end
	img:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	return img
end

--==============================================================
-- primitives
--==============================================================
function UI.mk(class: string, props: { [string]: any }?, children: { Instance }?): any
	local o = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then (o :: any)[k] = v end
		end
	end
	if children then
		for _, c in ipairs(children) do c.Parent = o end
	end
	if props and props.Parent then o.Parent = props.Parent end
	return o
end

function UI.corner(r: number): UICorner
	return UI.mk("UICorner", { CornerRadius = UDim.new(0, r) })
end

function UI.stroke(color: Color3?, thickness: number?, trans: number?): UIStroke
	return UI.mk("UIStroke", {
		Color = color or T.line,
		Thickness = thickness or 1,
		Transparency = trans or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.pad(all: number, l: number?, r: number?, t: number?, b: number?): UIPadding
	return UI.mk("UIPadding", {
		PaddingLeft = UDim.new(0, l or all), PaddingRight = UDim.new(0, r or all),
		PaddingTop = UDim.new(0, t or all), PaddingBottom = UDim.new(0, b or all),
	})
end

function UI.list(dir: Enum.FillDirection, gap: number, halign: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?): UIListLayout
	return UI.mk("UIListLayout", {
		FillDirection = dir,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
	})
end

function UI.grid(w: number, h: number, gap: number): UIGridLayout
	return UI.mk("UIGridLayout", {
		CellSize = UDim2.fromOffset(w, h),
		CellPadding = UDim2.fromOffset(gap, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})
end

-- role: display | displayMed | body | bodySemi | bodyBold | mono | monoBold
-- A horizontal ScrollingFrame row: centred while everything fits, and
-- scrolling from its left edge once it doesn't (a centred UIListLayout alone
-- pushes the first items off the left side, out of reach).
function UI.centreScroll(sf: ScrollingFrame, layout: UIListLayout)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local pad = sf:FindFirstChild("CentrePad") or UI.mk("UIPadding", { Name = "CentrePad", Parent = sf })
	local function fit()
		local scale = 1
		local node: Instance? = sf
		while node and node:IsA("GuiObject") do
			local s = node:FindFirstChildOfClass("UIScale")
			if s then scale *= s.Scale end
			node = node.Parent
		end
		local spare = (sf.AbsoluteSize.X - layout.AbsoluteContentSize.X) / 2
		pad.PaddingLeft = UDim.new(0, math.max(0, math.floor(spare / math.max(scale, 0.01))))
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	sf:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end

function UI.text(text: string, size: number, role: string?, color: Color3?): TextLabel
	return UI.mk("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		FontFace = (UI.Fonts :: any)[role or "body"] or UI.Fonts.body,
		TextColor3 = color or T.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = true,
	})
end

function UI.hex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

function UI.comma(n: number): string
	local neg = n < 0
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	out = out:gsub("^,", "")
	return (neg and "-" or "") .. out
end

function UI.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

function UI.tween(o: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(o, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- "30 BRONZE · 2 SILVER", coloured, for rich text labels
function UI.money(cost: { [string]: number }): string
	local bits = {}
	local colors = { credits = T.accent, bronze = T.bronze, silver = T.silver, gold = T.gold }
	for _, cur in ipairs({ "credits", "bronze", "silver", "gold" }) do
		local v = cost[cur]
		if v and v > 0 then
			table.insert(bits, ('<font color="%s">%s %s</font>'):format(UI.hex(colors[cur]), UI.comma(v), cur == "credits" and "CR" or string.upper(cur)))
		end
	end
	return table.concat(bits, "  ")
end

--==============================================================
-- surfaces
--==============================================================
-- A steel plate, screwed down at the corners and lit from the top left.
function UI.panel(props: { [string]: any }?): Frame
	local p = UI.mk("Frame", props or {})
	local fade = (props and props.BackgroundTransparency) or 0
	p.BackgroundTransparency = 1
	p.BorderSizePixel = 0
	UI.plate("panel", {
		Name = "Plate", Size = UDim2.fromScale(1, 1), ImageTransparency = fade,
		ZIndex = p.ZIndex, Parent = p,
	})
	return p
end

function UI.bar(bg: Color3, fill: Color3, h: number): (Frame, Frame)
	local track = UI.mk("Frame", { Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = bg, BorderSizePixel = 0 })
	UI.corner(math.max(1, math.floor(h / 2))).Parent = track
	local f = UI.mk("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = fill, BorderSizePixel = 0, Parent = track })
	UI.corner(math.max(1, math.floor(h / 2))).Parent = f
	return track, f
end

function UI.chip(text: string, color: Color3?): TextLabel
	local c = color or T.dim
	local l = UI.text(string.upper(text), 11, "monoBold", c)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, 18)
	l.TextXAlignment = Enum.TextXAlignment.Center
	UI.pad(0, 6, 6, 0, 0).Parent = l
	UI.stroke(c, 1, 0.45).Parent = l
	UI.corner(2).Parent = l
	return l
end

--==============================================================
-- buttons
--==============================================================
-- Painted red for anything that commits, bare steel for everything else.
local STYLES = {
	primary = { set = "red", fg = T.accentInk },
	good    = { set = "red", fg = T.accentInk },
	bad     = { set = "red", fg = T.accentInk },
	ghost   = { set = "steel", fg = T.text },
	off     = { set = "off", fg = T.faint },
}

function UI.setButtonStyle(b: TextButton, style: any)
	local s = (typeof(style) == "Color3") and STYLES.ghost or ((STYLES :: any)[style or "primary"] or STYLES.primary)
	local n, h, p
	if s.set == "red" then
		n, h, p = UI.Kit.redNormal, UI.Kit.redHover, UI.Kit.redPressed
	elseif s.set == "off" then
		n, h, p = UI.Kit.steelOff, UI.Kit.steelOff, UI.Kit.steelOff
	else
		n, h, p = UI.Kit.steelNormal, UI.Kit.steelHover, UI.Kit.steelPressed
	end
	b:SetAttribute("Off", style == "off")
	b:SetAttribute("ImgN", n.id)
	b:SetAttribute("ImgH", h.id)
	b:SetAttribute("ImgP", p.id)
	b.TextColor3 = s.fg
	local plate = b:FindFirstChild("Plate") :: ImageLabel?
	if plate then
		plate.Image = n.id
		-- a rarity colour washes over the steel instead of a flat fill
		plate.ImageColor3 = (typeof(style) == "Color3") and style:Lerp(Color3.new(1, 1, 1), 0.45) or Color3.new(1, 1, 1)
	end
end

-- The button's own text would sit under its plate, so it's hidden and copied onto a label
-- above the plate. Callers keep setting b.Text, b.TextColor3 and the rest as before.
local MIRROR = {
	"Text", "TextColor3", "TextSize", "FontFace", "TextTransparency", "RichText", "TextScaled", "TextWrapped",
	"TextXAlignment", "TextYAlignment", "TextTruncate", "LineHeight", "TextStrokeColor3", "TextStrokeTransparency",
}

-- A backdrop that closes a menu when clicked, but only when the press also started on
-- the backdrop itself. Letting go of a slider (or any drag) over it does nothing.
function UI.guardBackdrop(backdrop: GuiButton, onClose: () -> ())
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local pressedHere = false
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		pressedHere = false
		if not backdrop.Visible then return end
		local layer = backdrop:FindFirstAncestorWhichIsA("LayerCollector")
		local pg = layer and layer.Parent
		if not (pg and pg:IsA("PlayerGui")) then return end
		local pos = input.UserInputType == Enum.UserInputType.Touch and Vector2.new(input.Position.X, input.Position.Y)
			or (UserInputService:GetMouseLocation() - Vector2.new(0, GuiService:GetGuiInset().Y))
		local ok, hits = pcall(function() return (pg :: PlayerGui):GetGuiObjectsAtPosition(pos.X, pos.Y) end)
		if not ok then return end
		-- anything solid of this screen sitting above the backdrop (a panel, its plate, a
		-- button, a label) means the press started on the menu, not on the dim around it
		local function solid(o: GuiObject): boolean
			if o:IsA("GuiButton") then return true end
			if o.BackgroundTransparency < 1 then return true end
			if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and (o :: ImageLabel).Image ~= "" and (o :: ImageLabel).ImageTransparency < 1 then return true end
			if o:IsA("TextLabel") and (o :: TextLabel).Text ~= "" then return true end
			if o:IsA("ViewportFrame") or o:IsA("ScrollingFrame") then return true end
			return false
		end
		-- works whatever order the hits come back in: find the backdrop, then look for
		-- anything solid in a top-level piece of the screen drawn over it
		local found, blocked = false, false
		for _, o in ipairs(hits) do
			if o == backdrop then
				found = true
			elseif o:IsDescendantOf(layer :: Instance) and solid(o) then
				local top: Instance = o
				while top.Parent and top.Parent ~= layer do top = top.Parent :: Instance end
				if top ~= backdrop and top:IsA("GuiObject") and (top :: GuiObject).ZIndex >= backdrop.ZIndex then
					blocked = true
				end
			end
		end
		pressedHere = found and not blocked
	end)
	backdrop.Activated:Connect(function()
		if pressedHere then
			pressedHere = false
			onClose()
		end
	end)
end

-- keys are cut square, so rounded corners or outlines added later are flattened
local function squareUp(c: Instance)
	if c:IsA("UICorner") then
		c.CornerRadius = UDim.new(0, 0)
	elseif c:IsA("UIStroke") and c.Name ~= "TextEdge" and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
		c.Enabled = false
	end
end

-- A pressed-steel key: square plate, black-outlined text, sinks when you press it.
function UI.button(text: string, style: any, w: number, h: number): TextButton
	local b = UI.mk("TextButton", {
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text,
		FontFace = UI.Fonts.display,
		TextSize = math.floor(h * 0.44),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local plate = UI.plate("steelNormal", { Name = "Plate", Size = UDim2.fromScale(1, 1), ZIndex = b.ZIndex, Parent = b })
	local label = UI.mk("TextLabel", {
		Name = "Label", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = b.ZIndex, Parent = b,
	})
	for _, prop in ipairs(MIRROR) do
		(label :: any)[prop] = (b :: any)[prop]
		b:GetPropertyChangedSignal(prop):Connect(function() (label :: any)[prop] = (b :: any)[prop] end)
	end
	b.MaxVisibleGraphemes = 0
	b:GetPropertyChangedSignal("ZIndex"):Connect(function()
		plate.ZIndex = b.ZIndex
		label.ZIndex = b.ZIndex
	end)
	UI.mk("UIStroke", { Name = "TextEdge", Color = Color3.fromRGB(8, 8, 9), Thickness = math.max(1, h * 0.04), Transparency = 0.2, Parent = label })
	b.ChildAdded:Connect(squareUp)
	local sc = UI.mk("UIScale", { Parent = b })
	UI.setButtonStyle(b, style)

	local function img(key: string)
		local id = b:GetAttribute(key)
		if type(id) == "string" then plate.Image = id end
	end
	b.MouseEnter:Connect(function() img("ImgH") end)
	b.MouseLeave:Connect(function()
		img("ImgN")
		UI.tween(sc, 0.12, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		img("ImgP")
		UI.tween(sc, 0.05, { Scale = 0.96 })
	end)
	b.MouseButton1Up:Connect(function()
		img("ImgH")
		UI.tween(sc, 0.14, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	return b
end

--==============================================================
-- showing and hiding menus: a fade with a short slide
--==============================================================
-- While it fades, a menu rides inside a CanvasGroup the size of its parent, so everything
-- in it fades together; it goes back to its parent when the fade ends.
local fades: { [GuiObject]: any } = setmetatable({}, { __mode = "k" }) :: any

function UI.isFading(obj: GuiObject): boolean
	local st = fades[obj]
	return st ~= nil and st.group ~= nil
end

-- Shows or hides obj. opts: rest (where it sits when shown), dur, offset (how far it slides),
-- delay (a show waits this long, hidden, so the menu before it can finish going).
-- done runs when it has finished, unless another call took over first.
function UI.fade(obj: GuiObject, show: boolean, opts: { [string]: any }?, done: (() -> ())?)
	local o = opts or {}
	local st = fades[obj]
	if not st then
		st = { token = 0 }
		fades[obj] = st
	end
	st.token += 1
	local token = st.token
	local rest: UDim2 = o.rest or st.rest or obj.Position
	st.rest = rest
	local dur = o.dur or (show and 0.32 or 0.22)
	local drop = UDim2.fromOffset(0, o.offset or (show and 26 or 20))

	local function wrap(): CanvasGroup?
		if st.group and st.group.Parent then return st.group end
		local parent = obj.Parent
		if not parent then return nil end
		local g = Instance.new("CanvasGroup")
		g.Name = "Fade"
		g.BackgroundTransparency = 1
		g.BorderSizePixel = 0
		g.Size = UDim2.fromScale(1, 1)
		g.ZIndex = obj.ZIndex
		g.Parent = parent
		obj.Parent = g
		st.group = g
		return g
	end
	local function unwrap()
		local g = st.group
		st.group = nil
		if g then
			if obj.Parent == g then obj.Parent = g.Parent end
			g:Destroy()
		end
	end
	local function run()
		if st.token ~= token then return end
		local g = wrap()
		if not g then
			obj.Visible = show
			obj.Position = rest
			if done then done() end
			return
		end
		if show then
			if not obj.Visible then
				g.GroupTransparency = 1
				obj.Position = rest + drop
			end
			obj.Visible = true
			UI.tween(g, dur, { GroupTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			UI.tween(obj, dur, { Position = rest }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		else
			UI.tween(g, dur, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			UI.tween(obj, dur, { Position = rest + drop }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		task.delay(dur + 0.03, function()
			if st.token ~= token then return end
			if not show then obj.Visible = false end
			obj.Position = rest
			unwrap()
			if done then done() end
		end)
	end
	if show and (o.delay or 0) > 0 then
		if not st.group then obj.Visible = false end
		task.delay(o.delay, run)
	else
		run()
	end
end

--==============================================================
-- screen fitting: layouts are drawn for 1280x760 and scaled from there
--==============================================================
-- every scaled layout, so the UI size setting can refit them all at once
local scaled: { [UIScale]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

function UI.autoScale(obj: GuiObject, designW: number?, designH: number?): UIScale
	local sc = obj:FindFirstChildOfClass("UIScale") or UI.mk("UIScale", { Parent = obj })
	local function fit()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local v = cam.ViewportSize
		sc.Scale = math.clamp(math.min(v.X / (designW or 1280), v.Y / (designH or 760)), 0.5, 1.15) * (Prefs.get("uiScale") or 1)
	end
	scaled[sc] = fit
	fit()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end
	return sc
end

Prefs.watch("uiScale", function()
	for sc, fit in pairs(scaled) do
		if sc.Parent then fit() end
	end
end)

--==============================================================
-- controls: sliders and choice rows, in the same steel
--==============================================================
-- A slot with a red fill and a steel knob. onChange runs while dragging, onDone on release.
function UI.slider(width: number, value: number, onChange: (number) -> (), onDone: ((number) -> ())?): (Frame, (number) -> ())
	local UserInputService = game:GetService("UserInputService")
	local root = UI.mk("Frame", { Size = UDim2.fromOffset(width, 28), BackgroundTransparency = 1, Active = true })
	local track = UI.plate("slot", {
		Name = "Track", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 14), Parent = root,
	})
	local fill = UI.mk("Frame", {
		Name = "Fill", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(value, -6, 1, -6),
		BackgroundColor3 = T.accent, BorderSizePixel = 0, Parent = track,
	})
	UI.mk("UIGradient", { Rotation = 90, Color = ColorSequence.new(T.accent, T.accentDeep), Parent = fill })
	local knob = UI.plate("steelNormal", {
		Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(value, 0.5), Size = UDim2.fromOffset(14, 26), Parent = root,
	})
	local current = value
	local function show(v: number)
		current = math.clamp(v, 0, 1)
		fill.Size = UDim2.new(current, current > 0 and -6 * (1 - current) or 0, 1, -6)
		fill.Visible = current > 0.005
		knob.Position = UDim2.fromScale(current, 0.5)
	end
	show(value)
	local dragging = false
	local function fromX(x: number)
		local a, s = root.AbsolutePosition.X, math.max(1, root.AbsoluteSize.X)
		show((x - a) / s)
		onChange(current)
	end
	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			knob.Image = UI.Kit.steelPressed.id
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			knob.Image = UI.Kit.steelNormal.id
			if onDone then onDone(current) end
		end
	end)
	return root, show
end

-- A row of steel keys where the chosen one is painted red.
function UI.choices(options: { { id: string, label: string } }, current: string, w: number, h: number, onPick: (string) -> ()): (Frame, (string) -> ())
	local row = UI.mk("Frame", {
		Size = UDim2.fromOffset((#options * (w + 6)) - 6, h), BackgroundTransparency = 1,
	}, { UI.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	local buttons = {}
	local function set(id: string)
		for oid, b in pairs(buttons) do UI.setButtonStyle(b, oid == id and "primary" or "ghost") end
	end
	for i, o in ipairs(options) do
		local b = UI.button(string.upper(o.label), "ghost", w, h)
		b.TextSize = math.min(15, math.floor(h * 0.42))
		b.LayoutOrder = i
		b.Parent = row
		b.Activated:Connect(function()
			set(o.id)
			onPick(o.id)
		end)
		buttons[o.id] = b
	end
	set(current)
	return row, set
end

--==============================================================
-- tooltips: hover (or hold, on touch) anything that explains itself
--==============================================================
local tip: any = nil

local function tipLayer()
	if tip then return tip end
	local Players = game:GetService("Players")
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return nil end
	local layer = UI.mk("ScreenGui", {
		Name = "TyreTips", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4990,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = pg,
	})
	local box = UI.mk("Frame", {
		Name = "Tip", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0),
		Visible = false, Parent = layer,
	})
	UI.plate("slot", { Name = "Plate", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = box })
	UI.pad(0, 12, 12, 8, 9).Parent = box
	local label = UI.text("", 14, "bodySemi", T.text)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.TextWrapped = true
	label.ZIndex = 2
	label.Parent = box
	UI.mk("UISizeConstraint", { MaxSize = Vector2.new(280, math.huge), Parent = label })
	tip = { layer = layer, box = box, label = label, owner = nil, token = 0, at = nil }
	RunService.RenderStepped:Connect(function()
		if not box.Visible then return end
		local owner = tip.owner
		if not owner or not owner.Parent or not owner.Visible then
			box.Visible = false
			return
		end
		local UserInputService = game:GetService("UserInputService")
		local m = tip.at or UserInputService:GetMouseLocation()
		local size = box.AbsoluteSize
		local screen = layer.AbsoluteSize
		local x = math.clamp(m.X + 18, 8, screen.X - size.X - 8)
		local y = m.Y + 24
		if y + size.Y > screen.Y - 8 then y = m.Y - size.Y - 14 end
		box.Position = UDim2.fromOffset(x, y)
	end)
	return tip
end

local function showTip(owner: GuiObject, text: string | (() -> string), at: Vector2?)
	local t = tipLayer()
	if not t then return end
	local s = type(text) == "function" and (text :: any)() or text
	if type(s) ~= "string" or s == "" then return end
	t.owner = owner
	t.at = at
	t.label.Text = s
	t.box.Visible = true
end

local function hideTip(owner: GuiObject?)
	if tip and (owner == nil or tip.owner == owner) then
		tip.token += 1
		tip.box.Visible = false
		tip.owner = nil
	end
end

function UI.tooltip(obj: GuiObject, text: string | (() -> string))
	local token = 0
	obj.MouseEnter:Connect(function()
		token += 1
		local mine = token
		task.delay(0.3, function()
			if token == mine then showTip(obj, text, nil) end
		end)
	end)
	obj.MouseLeave:Connect(function()
		token += 1
		hideTip(obj)
	end)
	obj.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		token += 1
		local mine = token
		local at = Vector2.new(input.Position.X, input.Position.Y + 36)
		task.delay(0.45, function()
			if token == mine then showTip(obj, text, at) end
		end)
	end)
	obj.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		token += 1
		task.delay(1.2, function() hideTip(obj) end)
	end)
	obj.SelectionGained:Connect(function()
		local p = obj.AbsolutePosition
		showTip(obj, text, Vector2.new(p.X, p.Y + obj.AbsoluteSize.Y + 34))
	end)
	obj.SelectionLost:Connect(function() hideTip(obj) end)
	obj.Destroying:Connect(function() hideTip(obj) end)
end

--==============================================================
-- the purchase stamp: a steel plate slams down mid-screen, kicks sparks in the
-- item's colour and lifts away. Particles only, no lights.
--==============================================================
function UI.stamp(gui: Instance, headline: string, color: Color3, sub: string?)
	local group = UI.mk("CanvasGroup", {
		Name = "Stamp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(420, 112),
		BackgroundTransparency = 1, ZIndex = 480, Parent = gui,
	})
	local scale = UI.mk("UIScale", { Scale = 2.4, Parent = group })
	UI.plate("panel", { Name = "Plate", Size = UDim2.fromScale(1, 1), ZIndex = 480, Parent = group })
	local band = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -44, 0, 4),
		BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 481, Parent = group,
	})
	band.Name = "Band"
	local head = UI.text(string.upper(headline), 34, "display", color)
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.new(0.5, 0, 0, sub and 14 or 24)
	head.Size = UDim2.new(1, -40, 0, 40)
	head.TextXAlignment = Enum.TextXAlignment.Center
	head.TextScaled = true
	head.ZIndex = 482
	head.Parent = group
	UI.mk("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.1, Parent = head })
	UI.mk("UITextSizeConstraint", { MaxTextSize = 34, Parent = head })
	if sub then
		local s = UI.text(sub, 15, "monoBold", T.dim)
		s.AnchorPoint = Vector2.new(0.5, 0)
		s.Position = UDim2.new(0.5, 0, 0, 58)
		s.Size = UDim2.new(1, -40, 0, 18)
		s.TextXAlignment = Enum.TextXAlignment.Center
		s.ZIndex = 482
		s.Parent = group
	end
	group.Rotation = math.random(-6, 6)
	group.GroupTransparency = 1
	UI.tween(group, 0.1, { GroupTransparency = 0 })
	local slam = UI.tween(scale, 0.13, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	slam.Completed:Once(function()
		-- the hit: a jolt and a fan of sparks off both ends
		local layer = gui
		local centre = group.AbsolutePosition + group.AbsoluteSize / 2
		for i = 1, 30 do
			local p = UI.mk("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 479, Size = UDim2.fromOffset(8, 2),
				BackgroundColor3 = (i % 3 == 0) and Color3.fromRGB(255, 244, 220) or color, Parent = layer,
			})
			local side = (i % 2 == 0) and 1 or -1
			local x = centre.X + side * (group.AbsoluteSize.X / 2 - 10)
			local y = centre.Y + (math.random() - 0.5) * group.AbsoluteSize.Y
			local vx = side * (180 + math.random() * 520)
			local vy = -(120 + math.random() * 420)
			local life = 0.35 + math.random() * 0.35
			local age = 0
			local conn
			conn = RunService.RenderStepped:Connect(function(dt)
				age += dt
				if age >= life or not p.Parent then
					conn:Disconnect()
					p:Destroy()
					return
				end
				vy += 1400 * dt
				x += vx * dt
				y += vy * dt
				p.Position = UDim2.fromOffset(x, y)
				p.Rotation = math.deg(math.atan2(vy, vx))
				p.BackgroundTransparency = (age / life) ^ 2
			end)
		end
		group.Position = UDim2.new(0.5, 0, 0.44, 5)
		UI.tween(group, 0.18, { Position = UDim2.fromScale(0.5, 0.44) }, Enum.EasingStyle.Back)
		task.delay(0.95, function()
			if not group.Parent then return end
			UI.tween(group, 0.28, { GroupTransparency = 1, Position = UDim2.fromScale(0.5, 0.4) })
			task.delay(0.3, function() group:Destroy() end)
		end)
	end)
end

--==============================================================
-- titles: the tier decides the treatment
--==============================================================
local titleFx: { [TextLabel]: any } = setmetatable({}, { __mode = "k" }) :: any

local function sample(colors: { Color3 }, u: number): Color3
	local n = #colors
	u = u % 1
	local f = u * n
	local i = math.floor(f)
	return colors[(i % n) + 1]:Lerp(colors[((i + 1) % n) + 1], f - i)
end

function UI.applyTitle(label: TextLabel, titleId: string?)
	local t = titleId and Config.TitlesById[titleId]
	local grad = label:FindFirstChild("TitleFX") :: UIGradient?
	if not t then
		label.Text = ""
		label.Visible = false
		titleFx[label] = nil
		if grad then grad.Enabled = false end
		return
	end
	local tier = Config.TitleTiers[t.tier]
	label.Visible = true
	label.Text = string.upper(t.name)
	label.TextStrokeColor3 = tier.colors[1]:Lerp(Color3.new(0, 0, 0), 0.82)
	label.TextStrokeTransparency = tier.stroke and 0.25 or 0.7
	if tier.style == "solid" then
		label.TextColor3 = tier.colors[1]
		if grad then grad.Enabled = false end
		titleFx[label] = nil
		return
	end
	label.TextColor3 = Color3.new(1, 1, 1)
	if not grad then
		grad = Instance.new("UIGradient")
		grad.Name = "TitleFX"
		grad.Parent = label
	end
	local g = grad :: UIGradient
	g.Enabled = true
	if tier.style == "gradient" then
		g.Color = ColorSequence.new(tier.colors[1], tier.colors[2])
		titleFx[label] = nil
	else
		titleFx[label] = { grad = g, tier = tier, seed = math.random() }
	end
end

function UI.titleLabel(titleId: string?, size: number): TextLabel
	local l = UI.text("", size, "display")
	UI.applyTitle(l, titleId)
	return l
end

if RunService:IsClient() then
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / 30 then return end
		acc = 0
		local now = os.clock()
		for label, fx in pairs(titleFx) do
			if label.Parent and label.Visible then
				local tier = fx.tier
				local c = tier.colors
				if tier.style == "flow" or tier.style == "cycle" then
					local cycle = tier.style == "cycle"
					local phase = now * (cycle and 0.32 or 0.16) + fx.seed
					local keys = table.create(5)
					for k = 0, 4 do
						local u = k / 4
						keys[k + 1] = ColorSequenceKeypoint.new(u, sample(c, phase + u * (cycle and 1 or 0.55)))
					end
					fx.grad.Color = ColorSequence.new(keys)
				elseif tier.style == "shine" then
					local s = ((now * 0.5 + fx.seed) % 1.8) - 0.3
					local pts = { { 0, c[1] } }
					local lo, hi = s - 0.12, s + 0.12
					if lo > 0.01 and lo < 0.97 then table.insert(pts, { lo, c[1] }) end
					if s > 0.02 and s < 0.98 then table.insert(pts, { s, c[2] }) end
					if hi > 0.03 and hi < 0.99 then table.insert(pts, { hi, c[1] }) end
					table.insert(pts, { 1, c[3] })
					local keys = table.create(#pts)
					for i, pt in ipairs(pts) do keys[i] = ColorSequenceKeypoint.new(pt[1], pt[2]) end
					fx.grad.Color = ColorSequence.new(keys)
				end
			end
		end
	end)
end

--==============================================================
-- build tag, bottom middle. Three quick clicks open the debug console.
--==============================================================
function UI.buildTag(parent: Instance, onSecret: (() -> ())?): TextButton
	local b = UI.mk("TextButton", {
		Name = "BuildTag",
		-- tucked in the bottom-left corner, clear of the centred buttons and the lock badge
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -6),
		Size = UDim2.fromOffset(110, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Selectable = false,
		Text = Config.VersionLabel,
		FontFace = UI.Fonts.mono,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(196, 196, 196),
		TextTransparency = 0.3,
		ZIndex = 95,
		Parent = parent,
	})
	local clicks = {}
	b.Activated:Connect(function()
		local now = os.clock()
		table.insert(clicks, now)
		while clicks[1] and now - clicks[1] > 0.9 do table.remove(clicks, 1) end
		if #clicks >= 3 then
			clicks = {}
			if onSecret then onSecret() end
		end
	end)
	return b
end

--==============================================================
-- the cursor: our own steel pointer, with some life in it
--==============================================================
-- hot is where the click lands, as a fraction of the image
local CURSORS = {
	-- art/ui/cursors.py: the kit's look (thick ink outline, light gradient, race-orange accent)
	pointer  = { id = "rbxassetid://109460595654364", hot = Vector2.new(0.094, 0.0625) },
	point    = { id = "rbxassetid://134412393638705", hot = Vector2.new(0.094, 0.0625) },
	grab     = { id = "rbxassetid://85482924896747", hot = Vector2.new(0.5, 0.5) },
	grabbing = { id = "rbxassetid://103142178999155", hot = Vector2.new(0.5, 0.5) },
	place    = { id = "rbxassetid://135412822896978", hot = Vector2.new(0.5, 0.5) },
	busy     = { id = "rbxassetid://124937633432138", hot = Vector2.new(0.5, 0.5) },
	no       = { id = "rbxassetid://120875830744262", hot = Vector2.new(0.5, 0.5) },
	text     = { id = "rbxassetid://95719418541052", hot = Vector2.new(0.5, 0.5) },
}
local cursor: any = nil

-- what the game wants the cursor to be right now; nil hands it back to hover.
-- A pointing hand asked for by something in the world only lasts while it keeps being
-- asked for, and a grab lets go by itself once no button is held.
function UI.setCursor(name: string?)
	if cursor then
		cursor.forced = name
		cursor.forcedAt = os.clock()
	end
end

function UI.startCursor(gui: ScreenGui)
	if cursor or not RunService:IsClient() then return end
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local playerGui = gui.Parent
	if not playerGui then return end
	local layer = UI.mk("ScreenGui", {
		Name = "TyreCursor", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui,
	})
	local BASE = 34
	local img = UI.mk("ImageLabel", {
		Name = "Cursor", BackgroundTransparency = 1, Image = CURSORS.pointer.id,
		AnchorPoint = CURSORS.pointer.hot,
		Size = UDim2.fromOffset(BASE, BASE), ZIndex = 10, Parent = layer,
	})
	-- while the mouse is held at the centre (shift lock, first person) a crosshair takes its place
	local reticle = UI.mk("ImageLabel", {
		Name = "Reticle", BackgroundTransparency = 1, Image = UI.Icons.reticle,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 30), ImageTransparency = 0,
		Visible = false, ZIndex = 10, Parent = layer,
	})
	cursor = { forced = nil, hover = nil, state = "pointer", scale = 1, vel = 0, tilt = 0, tiltVel = 0, breathe = 0, sparks = {}, at = Vector2.zero }

	local function apply(name: string)
		local c = CURSORS[name] or CURSORS.pointer
		img.Image = c.id
		img.AnchorPoint = c.hot
		cursor.state = name
		cursor.scale = 1.22
		cursor.vel = 0
	end

	-- a few sparks off the tip when you click, like the door hitting the floor
	local function sparks(at: Vector2)
		for i = 1, 6 do
			local p = UI.mk("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 9,
				BackgroundColor3 = (i % 3 == 0) and T.accent or Color3.fromRGB(226, 231, 236),
				Size = UDim2.fromOffset(3, 2), Position = UDim2.fromOffset(at.X, at.Y), Parent = layer,
			})
			local a = math.random() * math.pi * 2
			table.insert(cursor.sparks, {
				ui = p, x = at.X, y = at.Y,
				vx = math.cos(a) * (90 + math.random() * 200),
				vy = math.sin(a) * (90 + math.random() * 200) - 80,
				life = 0.22 + math.random() * 0.2, age = 0,
			})
		end
	end

	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and layer.Enabled then
			cursor.scale = 0.78
			cursor.vel = 0
			sparks(cursor.at)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			cursor.scale = math.max(cursor.scale, 1.1)
		end
	end)

	local hoverAt = 0
	RunService.RenderStepped:Connect(function(dt)
		-- ours whenever there's a mouse: it holds still through a right-click camera turn, and
		-- becomes a crosshair while the mouse is locked to the centre
		local shown = UserInputService.MouseEnabled
		layer.Enabled = shown
		if UserInputService.MouseIconEnabled == shown then UserInputService.MouseIconEnabled = not shown end
		if not shown then return end
		local centred = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		reticle.Visible = centred
		img.Visible = not centred
		if centred then
			reticle.Rotation = cursor.tilt
			return
		end

		-- the mouse is measured from the very top of the screen, which is also where this
		-- layer's own offsets start; the hit test below counts from under the top bar
		local m = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset().Y
		local at = Vector2.new(m.X, m.Y)
		local moved = at - cursor.at
		cursor.at = at

		local now = os.clock()
		if now - hoverAt > 0.05 then
			hoverAt = now
			local found = nil
			local ok, list = pcall(function() return playerGui:GetGuiObjectsAtPosition(m.X, m.Y - inset) end)
			if ok and type(list) == "table" then
				-- buttons are a transparent hit area over a plate, so look up from what was hit
				for _, o in ipairs(list) do
					local node: Instance? = o
					-- only things actually on screen count: every ancestor visible, its layer enabled
					local shown = true
					local walk: Instance? = o
					while walk and walk ~= playerGui do
						if walk:IsA("GuiObject") and not (walk :: GuiObject).Visible then shown = false break end
						if walk:IsA("LayerCollector") and not (walk :: LayerCollector).Enabled then shown = false break end
						if walk:IsA("BillboardGui") then
							local ad = (walk :: BillboardGui).Adornee
							local at = ad and (ad:IsA("BasePart") and (ad :: BasePart).Position or (ad:IsA("Attachment") and (ad :: Attachment).WorldPosition))
							if at then
								local _, onScreen = workspace.CurrentCamera:WorldToViewportPoint(at)
								if not onScreen then shown = false break end
							end
						end
						walk = walk.Parent
					end
					if not shown then continue end
					for _ = 1, 4 do
						if not node or node == playerGui then break end
						if node:IsA("TextBox") then
							found = "text"
							break
						end
						if node:IsA("GuiButton") and (node :: GuiButton).Active and (node :: GuiButton).Visible then
							found = node:GetAttribute("Off") and "no" or "point"
							break
						end
						node = node.Parent
					end
					if found then break end
				end
			end
			cursor.hover = found
		end
		local forced = cursor.forced
		if forced == "point" and os.clock() - (cursor.forcedAt or 0) > 0.3 then
			cursor.forced = nil
			forced = nil
		elseif forced == "grabbing" and os.clock() - (cursor.forcedAt or 0) > 0.2
			and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and #UserInputService:GetTouches() == 0 then
			cursor.forced = nil
			forced = nil
		end
		local want = forced or cursor.hover or "pointer"
		if want ~= cursor.state then apply(want) end

		-- leans into the movement and swings back, breathes while it sits still
		local lean = math.clamp(moved.X * 1.1, -18, 18)
		cursor.tiltVel += (lean - cursor.tilt) * 24 * dt
		cursor.tiltVel *= math.exp(-dt * 8)
		cursor.tilt += cursor.tiltVel * dt
		cursor.breathe += dt
		cursor.vel += (1 - cursor.scale) * 260 * dt
		cursor.vel *= math.exp(-dt * 11)
		cursor.scale += cursor.vel * dt
		local s = math.clamp(cursor.scale * (1 + math.sin(cursor.breathe * 2.1) * 0.035), 0.6, 1.7)
		img.Size = UDim2.fromOffset(math.floor(BASE * s), math.floor(BASE * s))
		img.Position = UDim2.fromOffset(at.X, at.Y)
		img.Rotation = cursor.tilt

		for i = #cursor.sparks, 1, -1 do
			local sp = cursor.sparks[i]
			sp.age += dt
			if sp.age >= sp.life or not sp.ui.Parent then
				sp.ui:Destroy()
				table.remove(cursor.sparks, i)
			else
				sp.vy += 900 * dt
				sp.x += sp.vx * dt
				sp.y += sp.vy * dt
				sp.ui.Position = UDim2.fromOffset(sp.x, sp.y)
				sp.ui.Rotation = math.deg(math.atan2(sp.vy, sp.vx))
				sp.ui.BackgroundTransparency = (sp.age / sp.life) ^ 2
			end
		end
	end)
end

return UI
