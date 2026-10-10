--!strict
-- TYRE CANNON :: Kit
-- The UI kit. The art is drawn in Inkscape (art/ui/kit3/*.svg -> png), mixing The Forge (dark
-- near-black panels, flat tinted buttons) with Anime Expeditions (a thin coloured border, a crest
-- breaking out of the header, rarity-washed item wells):
--   panel + panel_edge   near-black, a tyre-tread band pressed into the top; the border tinted
--   crest                a tyre over the end of a pennant in the screen's colour (the header)
--   button               flat paint, a lit top edge, tread cuts in the right end (tinted)
--   tab                  dark: a tab you're not on (the one you're on is a button)
--   slot + slot_edge     a dark well; the rarity as a line round it and a wash from the bottom
--   section, track, fill, stripes, close
-- The motion is part of the kit: screens fade in rising and settling while the crest's tyre rolls
-- in and its pennant unrolls; contents cascade; buttons lift, brighten and catch a shine on hover,
-- squash on press and spring back; disabled ones shake. Labels always fit their art (Kit.fit).
-- Built on UI.mk; colours come from Kit.C.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UI = require(script.Parent.UI)

local Kit = {}

Kit.C = {
	ink = Color3.fromRGB(14, 13, 12),
	text = Color3.fromRGB(244, 240, 232),
	muted = Color3.fromRGB(170, 164, 156),
	gold = Color3.fromRGB(236, 196, 120),
	panel = Color3.fromRGB(46, 47, 50),
	well = Color3.fromRGB(34, 35, 38),
	bar = Color3.fromRGB(58, 59, 63),
	line = Color3.fromRGB(80, 80, 86),
	accent = Color3.fromRGB(246, 156, 38),
	cream = Color3.fromRGB(46, 47, 50),
	paper = Color3.fromRGB(34, 35, 38),
	night = Color3.fromRGB(20, 20, 22),
	white = Color3.fromRGB(255, 255, 255),
	red = Color3.fromRGB(214, 52, 48),
	yellow = Color3.fromRGB(250, 190, 54),
	green = Color3.fromRGB(86, 194, 72),
	blue = Color3.fromRGB(64, 142, 236),
	teal = Color3.fromRGB(48, 178, 184),
	purple = Color3.fromRGB(152, 98, 236),
	orange = Color3.fromRGB(246, 156, 38),
	grey = Color3.fromRGB(128, 128, 134),
	pink = Color3.fromRGB(255, 70, 110),
}
local C = Kit.C
Kit.Font = UI.Fonts.display
Kit.FontMed = UI.Fonts.displayMed
Kit.Body = UI.Fonts.bodyBold

local function darker(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end
Kit.darker = darker
local function lift(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end
Kit.lift = lift

-- the pieces: id, the 9-slice centre (in the image's own pixels, padding included), the padding
-- baked round it (its shadow) and the scale its corners are drawn at. Kit 4 (art/ui/kit4.py): the
-- treatment of the hub tiles, after Anime Expeditions: a vivid gradient border drawn white to grey
-- (tinted per use), a near-black outline, a dark inside. Drawn at 2x, shown at 0.5.
-- `h` is the height of a piece's box in its own pixels (for pieces scaled to fit a height).
Kit.Art = {
	tile = { id = "rbxassetid://130145535953089", slice = Rect.new(80, 80, 224, 224), scale = 0.5, pad = 24 },
	-- a panel in two: a neutral dark body and the gradient ring tinted to the screen
	panel_body = { id = "rbxassetid://94367956220692", slice = Rect.new(80, 80, 224, 224), scale = 0.5, pad = 24 },
	panel_ring = { id = "rbxassetid://84493048513872", slice = Rect.new(80, 80, 224, 224), scale = 0.5, pad = 24 },
	well = { id = "rbxassetid://123038138191206", slice = Rect.new(72, 72, 232, 232), scale = 0.5, pad = 24 },
	button = { id = "rbxassetid://120982835708680", slice = Rect.new(54, 54, 314, 90), scale = 0.5, pad = 24, h = 96 },
	counter = { id = "rbxassetid://104038801313035", slice = Rect.new(74, 68, 374, 72), scale = 0.5, pad = 24, h = 92 },
	plate = { id = "rbxassetid://77837190332396", slice = Rect.new(54, 50, 234, 54), scale = 0.5, pad = 24, h = 56 },
	track = { id = "rbxassetid://129587575566396", slice = Rect.new(52, 46, 476, 50), scale = 0.5, pad = 24, h = 48 },
	fill = { id = "rbxassetid://112159920394542", slice = Rect.new(46, 40, 482, 44), scale = 0.5, pad = 24, h = 36 },
	section = { id = "rbxassetid://108163614693478", slice = Rect.new(44, 44, 484, 64), scale = 0.5, pad = 24, h = 60 },
	banner = { id = "rbxassetid://121811877097045", slice = Rect.new(60, 60, 600, 116), scale = 0.5, pad = 24, h = 128 },
	glow = "rbxassetid://118235342602435",     -- the soft glow rising inside a tile (tinted)
	badge = "rbxassetid://127849010951163",    -- the hotkey badge
	close = "rbxassetid://106023319120668",
	-- the header crest: the game's tyre (rendered in the icon studio) over the end of the banner
	crestTyre = "rbxassetid://126515425222861",
	crestBanner = "rbxassetid://121811877097045",
	-- diagonal stripes that tile, scrolled over progress fills
	stripes = "rbxassetid://129153187316226",
	-- the bay a tyre is shown in, behind its 3D view (the turntable top is 76% down, 50% across)
	showcase = "rbxassetid://82094282006502",
	-- a dark edge to the screen, for behind whatever's open
	vignette = "rbxassetid://98303487108134",
}
local Art = Kit.Art
-- older names still asked for by some screens
Art.panel = Art.tile
Art.slot = Art.well
Art.tab = Art.button
Art.tag = Art.counter
Art.pill = Art.plate
Art.header = Art.button
-- the padding baked round a piece (shadows live in it): a piece's frame is drawn this much bigger
-- than the box it stands for, so the box lines up with the art
local PAD = 12

-- a 9-slice of one piece filling its parent (and its padding past the parent's edges)
function Kit.slice(kind: string, tint: Color3?, parent: Instance, z: number?, scale: number?): ImageLabel
	local a = Art[kind]
	local s = scale or (a and a.scale) or 0.5
	local p = ((a and a.pad) or PAD) * s
	local img = UI.mk("ImageLabel", {
		Name = kind, Position = UDim2.fromOffset(-p, -p), Size = UDim2.new(1, 2 * p, 1, 2 * p), BackgroundTransparency = 1,
		Image = a and a.id or "", ImageColor3 = tint or Color3.new(1, 1, 1), ScaleType = Enum.ScaleType.Slice,
		SliceCenter = a and a.slice or Rect.new(0, 0, 0, 0), SliceScale = s, ZIndex = z or 1, Visible = a ~= nil, Parent = parent,
	})
	return img
end

function Kit.tween(o: Instance, t: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	-- (workspace attribute KitSlow slows every kit motion down, for checking it frame by frame)
	t *= (workspace:GetAttribute("KitSlow") or 1)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

--==============================================================
-- text: Builder Sans with a dark edge
--==============================================================
function Kit.text(text: string, size: number, color: Color3?, stroke: number?, font: Font?): TextLabel
	local l = UI.mk("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextSize = size, FontFace = font or Kit.Font,
		TextColor3 = color or C.text, RichText = true, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(math.max(40, #text * size * 0.62), size + 6),
	})
	local s = stroke or 2
	if s > 0 then
		UI.mk("UIStroke", { Color = C.ink, Thickness = math.min(s, 2.5), Transparency = 0.1, LineJoinMode = Enum.LineJoinMode.Round, Parent = l })
	end
	return l
end

-- a label that always fits its box: it shrinks (never past `min`) rather than running over the art
function Kit.fit(l: TextLabel, max: number, min: number?)
	l.TextScaled = true
	local c = l:FindFirstChildOfClass("UITextSizeConstraint") or UI.mk("UITextSizeConstraint", { Parent = l })
	c.MaxTextSize = math.max(1, math.floor(max))
	c.MinTextSize = math.min(c.MaxTextSize, min or 9)
end

-- every label in a screen that doesn't fit its box (now, or when its text changes) is made to fit
function Kit.fitAll(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and not d:GetAttribute("KitFit") then
			d:SetAttribute("KitFit", true)
			local base = d.TextSize
			local function check()
				if d.TextScaled or d.Text == "" or d.AbsoluteSize.X < 2 then return end
				if not d.TextFits then Kit.fit(d :: TextLabel, base) end
			end
			check()
			d:GetPropertyChangedSignal("Text"):Connect(function() task.defer(check) end)
		end
	end
end

--==============================================================
-- panels
--==============================================================
-- dress a frame as a panel: a neutral dark inside in a vivid gradient ring of the screen's colour
-- (set by Kit.header)
local NEUTRAL = Color3.fromRGB(118, 120, 130)
Kit.NEUTRAL = NEUTRAL
function Kit.panel(face: GuiObject, accent: Color3?, z: number?)
	Kit.slice("panel_body", nil, face, z or 1, 0.6).Name = "Body"
	Kit.slice("panel_ring", accent or C.accent, face, (z or 1) + 1, 0.6).Name = "Plate"
end

-- cards: a panel, or with C.paper / C.well a recessed well to sit inside one
function Kit.card(size: UDim2, fill: Color3?, _radius: number?, _shadow: number?): (Frame, Frame)
	local holder = UI.mk("Frame", { Size = size, BackgroundTransparency = 1 })
	local face = UI.mk("Frame", {
		Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = holder,
	})
	if fill == C.paper or fill == C.well then
		Kit.slice("well", NEUTRAL, face, 2).Name = "Well"
	else
		Kit.panel(face, nil, 1)
	end
	return holder, face
end

-- a section heading inside a panel: a dark strip, its ends fading, the title on it
function Kit.section(parent: Instance, text: string, pos: UDim2, size: UDim2, z: number?): Frame
	local zi = z or 4
	local bar = UI.mk("Frame", {
		Name = "Section", Position = pos, Size = size, BackgroundTransparency = 1, ZIndex = zi, Parent = parent,
	})
	Kit.slice("section", nil, bar, zi, math.min(0.5, size.Y.Offset / Art.section.h))
	local t = Kit.text(string.upper(text), 16, Color3.fromRGB(206, 206, 212), 1.5)
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.Size = UDim2.new(1, -60, 1, -6)
	Kit.fit(t, size.Y.Offset * 0.55)
	t.ZIndex = zi + 1
	t.Name = "Label"
	t.Parent = bar
	-- labels set later keep the capitals
	t:GetPropertyChangedSignal("Text"):Connect(function()
		local up = string.upper(t.Text)
		if t.Text ~= up then t.Text = up end
	end)
	return bar
end

function Kit.divider(parent: Instance, pos: UDim2, width: UDim, z: number?): Frame
	local f = UI.mk("Frame", {
		Name = "Divider", AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.new(width, UDim.new(0, 2)),
		BackgroundColor3 = Color3.fromRGB(6, 6, 8), BorderSizePixel = 0, ZIndex = z or 3, Parent = parent,
	})
	-- a light edge under the dark line: a groove pressed into the plate
	UI.mk("Frame", { Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(90, 90, 98),
		BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = z or 3, Parent = f })
	UI.mk("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = f })
	return f
end

-- the panel's crest, breaking out of its top-left corner: the game's tyre (rendered face-on) over
-- the end of a banner in the screen's colour, the title on the banner. The panel's border takes the
-- same colour. It rolls in when the panel opens (Kit.open).
function Kit.header(face: Frame, text: string, color: Color3?, h: number?): Frame
	local col = color or C.accent
	local plate = face:FindFirstChild("Plate") :: ImageLabel?
	if plate then plate.ImageColor3 = col end
	local ts = math.floor(math.clamp(h or 60, 44, 66) * 0.56)
	local bh = math.floor(ts * 1.55)
	local ty = math.floor(bh * 1.9)
	local bw = math.clamp(math.floor(#text * ts * 0.72) + ty * 0.55 + 56, 240, 640)
	local band = UI.mk("Frame", {
		Name = "Header", Position = UDim2.fromOffset(-ty * 0.28, -bh * 0.78), Size = UDim2.fromOffset(bw + ty * 0.3, ty),
		BackgroundTransparency = 1, ZIndex = 8, Parent = face,
	})
	-- the banner runs from behind the tyre's middle
	local box = UI.mk("Frame", {
		Name = "BannerBox", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, ty * 0.45, 0.5, 0), Size = UDim2.fromOffset(bw - ty * 0.15, bh),
		BackgroundTransparency = 1, ZIndex = 8, Parent = band,
	})
	-- the banner is kept (crestIn reveals it) but drawn clear: the title stands on the panel's edge
	local banner = Kit.slice("banner", col, box, 8, math.min(0.5, bh / Art.banner.h))
	banner.Name = "Banner"
	banner.ImageTransparency = 1
	UI.mk("UIGradient", { Name = "Reveal", Parent = banner })
	local t = Kit.text(string.upper(text), math.floor(ts * 1.18), Color3.fromRGB(255, 255, 255), 2.5)
	local st = t:FindFirstChildOfClass("UIStroke")
	if st then st.Thickness = 3.5 end
	-- a soft shadow under the letters so they read over anything behind the panel
	local sh = Kit.text(string.upper(text), math.floor(ts * 1.18), Color3.new(0, 0, 0), 0)
	sh.TextTransparency = 0.45
	t.AnchorPoint = Vector2.new(0, 0.5)
	t.Position = UDim2.new(0, ty * 0.45 + ty * 0.5, 0.5, -1)
	t.Size = UDim2.fromOffset(bw - ty * 0.95, ts + 8)
	t.TextXAlignment = Enum.TextXAlignment.Left
	Kit.fit(t, ts * 1.18)
	t.ZIndex = 10
	t.Name = "Title"
	t.Parent = band
	sh.AnchorPoint = t.AnchorPoint
	sh.Position = t.Position + UDim2.fromOffset(2, 4)
	sh.Size = t.Size
	sh.TextXAlignment = Enum.TextXAlignment.Left
	Kit.fit(sh, ts * 1.18)
	sh.ZIndex = 9
	sh.Name = "TitleShadow"
	sh.Parent = band
	t:GetPropertyChangedSignal("Text"):Connect(function() sh.Text = t.Text end)
	t:GetPropertyChangedSignal("Position"):Connect(function() sh.Position = t.Position + UDim2.fromOffset(2, 4) end)
	t:GetPropertyChangedSignal("TextTransparency"):Connect(function() sh.TextTransparency = 0.45 + 0.55 * t.TextTransparency end)
	UI.mk("ImageLabel", {
		Name = "Tyre", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, ty * 0.5, 0.5, 0),
		Size = UDim2.fromOffset(ty, ty), BackgroundTransparency = 1, Image = Art.crestTyre, ZIndex = 11, Parent = band,
	})
	return band
end

-- the crest's entrance: the tyre rolls in from the left and rocks to a stop, the pennant unrolls
-- from behind it, the title slides in along it
function Kit.crestIn(band: Frame, delay: number?)
	local tyre = band:FindFirstChild("Tyre") :: ImageLabel?
	local banner = band:FindFirstChild("Banner", true) :: ImageLabel?
	local title = band:FindFirstChild("Title") :: TextLabel?
	if not (tyre and banner and title) then return end
	local reveal = banner:FindFirstChild("Reveal") :: UIGradient
	local tRest = tyre:GetAttribute("Rest") or tyre.Position
	tyre:SetAttribute("Rest", tRest)
	local lRest = title:GetAttribute("Rest") or title.Position
	title:SetAttribute("Rest", lRest)
	local stroke = title:FindFirstChildOfClass("UIStroke")
	-- start: tyre off to the left and wound back, pennant rolled up, title hidden
	tyre.Position = (tRest :: UDim2) - UDim2.fromOffset(170, 0)
	tyre.Rotation = -300
	tyre.ImageTransparency = 1
	reveal.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.499, 0),
		NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) })
	reveal.Offset = Vector2.new(-0.5, 0)
	title.Position = (lRest :: UDim2) - UDim2.fromOffset(24, 0)
	title.TextTransparency = 1
	if stroke then stroke.Transparency = 1 end
	local k = workspace:GetAttribute("KitSlow") or 1
	task.delay((delay or 0) * k, function()
		Kit.tween(tyre, 0.12, { ImageTransparency = 0 })
		Kit.tween(tyre, 0.5, { Position = tRest }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		local roll = Kit.tween(tyre, 0.5, { Rotation = 14 }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		roll.Completed:Connect(function()
			Kit.tween(tyre, 0.35, { Rotation = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end)
		task.delay(0.18 * k, function()
			Kit.tween(reveal, 0.42, { Offset = Vector2.new(0.5, 0) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		end)
		task.delay(0.36 * k, function()
			Kit.tween(title, 0.3, { Position = lRest, TextTransparency = 0 }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			if stroke then Kit.tween(stroke, 0.3, { Transparency = 0.1 }) end
		end)
	end)
end

--==============================================================
-- buttons: flat paint with a dark outline; hover brightens it, lifts it and runs a shine across,
-- press squashes it, release springs it back
--==============================================================
export type Button = {
	root: TextButton,
	face: ImageLabel,
	label: TextLabel,
	setEnabled: (boolean) -> (),
	setText: (string) -> (),
	setColor: (Color3) -> (),
	onClick: ((() -> ())?),
}

-- a shine that sweeps across a piece's own shape once (Kit.shine: cards use it too, so every
-- shine in the game is the same one)
local function shine(over: ImageLabel, z: number): () -> ()
	local s = UI.mk("ImageLabel", {
		Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = over.Image, ImageColor3 = Color3.new(1, 1, 1),
		ImageTransparency = 0.6, ScaleType = Enum.ScaleType.Slice, SliceCenter = over.SliceCenter, SliceScale = over.SliceScale,
		ZIndex = z, Visible = false, Parent = over,
	})
	local g = UI.mk("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.25),
			NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }),
		Offset = Vector2.new(-1, 0), Parent = s,
	})
	return function()
		s.Image = over.Image
		s.SliceCenter = over.SliceCenter
		s.Visible = true
		g.Offset = Vector2.new(-1, 0)
		local tw = Kit.tween(g, 0.45, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tw.Completed:Connect(function() s.Visible = false end)
	end
end

Kit.shine = shine

local MUTED = Color3.fromRGB(176, 176, 184)

function Kit.button(text: string, color: Color3, size: UDim2, textSize: number?): Button
	local root = UI.mk("TextButton", { Size = size, BackgroundTransparency = 1, Text = "", AutoButtonColor = false })
	local scale = UI.mk("UIScale", { Parent = root })
	-- the face rides in a holder so it can lift and press without moving the button's hit box
	local holder = UI.mk("Frame", { Name = "Holder", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = root })
	local face = Kit.slice("button", color, holder, 2, math.min(0.5, (size.Y.Offset > 0 and size.Y.Offset or 48) / Art.button.h))
	face.Name = "Face"
	local sweep = shine(face, 3)
	-- the label sits on the face with room either side, and shrinks rather than touch the edges
	local h = size.Y.Offset > 0 and size.Y.Offset or 48
	local label = Kit.text(string.upper(text), textSize or 24, C.white, 2)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.5, -1)
	label.Size = UDim2.new(1, -28, 1, -12)
	Kit.fit(label, math.min(textSize or 24, h * 0.46))
	label.ZIndex = 4
	label.Parent = holder
	local enabled, hovered = true, false
	-- dark: drawn as an unlit tab (a tab you're not on)
	local dark = false
	local api: Button
	local function paint()
		if dark then
			face.Image = Art.tab.id
			face.SliceCenter = Art.tab.slice
			face.ImageColor3 = if hovered then Color3.fromRGB(96, 98, 110) else Color3.fromRGB(68, 70, 80)
			label.TextColor3 = if hovered then C.white else MUTED
			label.TextTransparency = 0
			return
		end
		face.Image = Art.button.id
		face.SliceCenter = Art.button.slice
		local c = if enabled then color else Color3.fromRGB(84, 85, 92)
		face.ImageColor3 = if hovered and enabled then lift(c, 0.14) else c
		label.TextColor3 = if enabled then C.white else Color3.fromRGB(160, 160, 166)
		label.TextTransparency = 0
	end
	root.MouseEnter:Connect(function()
		hovered = true
		paint()
		if enabled then
			Kit.tween(holder, 0.14, { Position = UDim2.fromOffset(0, -3) }, Enum.EasingStyle.Back)
			if not dark then sweep() end
		end
	end)
	root.MouseLeave:Connect(function()
		hovered = false
		paint()
		Kit.tween(holder, 0.14, { Position = UDim2.fromOffset(0, 0) })
		Kit.tween(scale, 0.12, { Scale = 1 })
	end)
	root.MouseButton1Down:Connect(function()
		if not enabled then return end
		Kit.tween(holder, 0.06, { Position = UDim2.fromOffset(0, 1) })
		Kit.tween(scale, 0.06, { Scale = 0.95 })
	end)
	root.MouseButton1Up:Connect(function()
		Kit.tween(holder, 0.22, { Position = UDim2.fromOffset(0, if hovered then -3 else 0) }, Enum.EasingStyle.Back)
		Kit.tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	root.Activated:Connect(function()
		if not enabled then
			Kit.shake(root, 6, 0.25)
			return
		end
		if api.onClick then api.onClick() end
	end)
	api = {
		root = root, face = face, label = label, onClick = nil,
		setEnabled = function(on: boolean)
			enabled = on
			paint()
		end,
		setText = function(t: string) label.Text = string.upper(t) end,
		setColor = function(c: Color3)
			color = c
			paint()
		end,
	}
	;(api :: any).setDark = function(on: boolean)
		dark = on
		paint()
	end
	paint()
	return api
end

-- the round red close button for a panel's corner: turns a quarter on hover, sinks when pressed
function Kit.close(size: number?): Button
	local s = size or 52
	local root = UI.mk("TextButton", { Size = UDim2.fromOffset(s, s), BackgroundTransparency = 1, Text = "", AutoButtonColor = false })
	local scale = UI.mk("UIScale", { Parent = root })
	local face = UI.mk("ImageLabel", {
		Name = "Face", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(152 / 128, 152 / 128),
		BackgroundTransparency = 1, Image = Art.close, ZIndex = 2, Parent = root,
	})
	local api: Button
	root.MouseEnter:Connect(function()
		Kit.tween(scale, 0.14, { Scale = 1.1 }, Enum.EasingStyle.Back)
		Kit.tween(face, 0.22, { Rotation = 90 }, Enum.EasingStyle.Back)
	end)
	root.MouseLeave:Connect(function()
		Kit.tween(scale, 0.14, { Scale = 1 })
		Kit.tween(face, 0.22, { Rotation = 0 })
	end)
	root.MouseButton1Down:Connect(function() Kit.tween(scale, 0.06, { Scale = 0.9 }) end)
	root.MouseButton1Up:Connect(function() Kit.tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back) end)
	root.Activated:Connect(function() if api.onClick then api.onClick() end end)
	local label = UI.mk("TextLabel", { BackgroundTransparency = 1, Text = "", Visible = false, Parent = root })
	api = {
		root = root, face = face, label = label, onClick = nil,
		setEnabled = function(_on: boolean) end,
		setText = function(_t: string) end,
		setColor = function(_c: Color3) end,
	}
	return api
end

-- the game's icons: small 3D objects rendered in the icon studio (art/blender/icon_studio.py), full
-- colour (don't tint them). Machines are keyed by their Game.Machines id. The ids marked (new) are
-- the second pass: art/blender/icon_studio.py names coin, key, crate_backroad/highway/dunes, flag,
-- cog, workbench and shop.
Kit.Icon = {
	plot = "rbxassetid://75617194165835",
	tyre = "rbxassetid://132441359707022",
	crate = "rbxassetid://79538710202735",
	zones = "rbxassetid://112950866877470",
	key = "rbxassetid://126105696183622",
	cash = "rbxassetid://112224652485442",
	shop = "rbxassetid://127004312530571",
	bench = "rbxassetid://117024553375534",
	event = "rbxassetid://136486086110090",
	crate_dunes = "rbxassetid://71798850722071",
	crate_highway = "rbxassetid://73585666449045",
	crate_backroad = "rbxassetid://79538710202735",
	settings = "rbxassetid://111693823944212",
	lock = "rbxassetid://137479926917187",
	bronze = "rbxassetid://123262345242723",
	silver = "rbxassetid://101063235276625",
	gold = "rbxassetid://110896553272051",
	cannon = "rbxassetid://82387767874659",
	fuel = "rbxassetid://138262830652175",
	cooling = "rbxassetid://120752078418155",
	compressor = "rbxassetid://91830884613298",
	rack = "rbxassetid://116237732254681",
}
-- older names
Kit.Icon.wrench = Kit.Icon.plot
Kit.Icon.pin = Kit.Icon.zones
-- icons are drawn a touch smaller than the boxes they sit in (everything below multiplies by this)
Kit.IconScale = 0.85

-- a counter: the dark pill a count sits in, its icon (a full-colour studio render) breaking out of
-- the left end; the number bounces when it changes
function Kit.chip(icon: string, tint: Color3?, width: number): (Frame, TextLabel)
	local chip = UI.mk("Frame", { Size = UDim2.fromOffset(width, 46), BackgroundTransparency = 1 })
	Kit.slice("counter", nil, chip, 1, 0.5)
	local img = UI.mk("ImageLabel", {
		Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 10, 0.5, -2), Size = UDim2.fromOffset(math.floor(70 * Kit.IconScale), math.floor(70 * Kit.IconScale)),
		BackgroundTransparency = 1, Image = icon, ImageColor3 = tint or Color3.new(1, 1, 1), ZIndex = 3, Parent = chip,
	})
	local l = Kit.text("", 26, C.white, 2.5)
	l.Position = UDim2.fromOffset(52, 5)
	l.Size = UDim2.new(1, -66, 1, -10)
	l.TextXAlignment = Enum.TextXAlignment.Left
	Kit.fit(l, 26)
	l.ZIndex = 3
	l.Parent = chip
	local last = ""
	l:GetPropertyChangedSignal("Text"):Connect(function()
		if last ~= "" and l.Text ~= last then Kit.pop(img, 1.25, 0.25) end
		last = l.Text
	end)
	return chip, l
end

-- a menu tile (after Anime Expeditions' side menu): a vivid gradient frame in the menu's colour,
-- a dark inside lit by a glow of that colour, the icon (a full-colour studio render) breaking out
-- of the top, the name in heavy outlined capitals across the bottom edge, and a hotkey badge.
-- Hover lifts it, brightens the glow and bobs the icon; press squashes it.
function Kit.tile(icon: string, label: string, color: Color3, size: number, hotkey: string?): Button
	local root = UI.mk("TextButton", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Text = "", AutoButtonColor = false })
	local scale = UI.mk("UIScale", { Parent = root })
	local holder = UI.mk("Frame", { Name = "Holder", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = root })
	local face = Kit.slice("tile", color, holder, 2, math.min(0.5, size / 256 * 1.1))
	local glow = UI.mk("ImageLabel", {
		Name = "Glow", Position = UDim2.fromScale(0.08, 0.08), Size = UDim2.fromScale(0.84, 0.84), BackgroundTransparency = 1,
		Image = Art.glow, ImageColor3 = color, ImageTransparency = 0.25, ZIndex = 3, Parent = holder,
	}, { UI.corner(math.floor(size * 0.14)) })
	local img = UI.mk("ImageLabel", {
		Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromScale(0.96 * Kit.IconScale, 0.96 * Kit.IconScale),
		BackgroundTransparency = 1, Image = icon, ZIndex = 4, Parent = holder,
	})
	local l = Kit.text(string.upper(label), math.floor(size * 0.2), C.white, 3)
	l.AnchorPoint = Vector2.new(0.5, 1)
	l.Position = UDim2.new(0.5, 0, 1, -3)
	l.Size = UDim2.new(1, 4, 0, math.floor(size * 0.26))
	Kit.fit(l, size * 0.2)
	l.ZIndex = 6
	l.Parent = holder
	if hotkey then
		-- the badge's square is 68 of the art's 116 px (the rest is its shadow), so the image is drawn
		-- bigger than the square it stands for; the letter fills the square, which sits on the corner
		local sq = math.max(20, math.floor(size * 0.24))
		local b = UI.mk("Frame", {
			Name = "Hotkey", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(math.floor(sq * 0.3), math.floor(sq * 0.3)),
			Size = UDim2.fromOffset(sq, sq), BackgroundTransparency = 1, ZIndex = 7, Parent = holder,
		})
		local art = sq * 116 / 68
		UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(art, art),
			BackgroundTransparency = 1, Image = Art.badge, ZIndex = 7, Parent = b,
		})
		local bt = Kit.text(hotkey, math.floor(sq * 0.62), C.white, 0)
		bt.AnchorPoint = Vector2.new(0.5, 0.5)
		bt.Position = UDim2.fromScale(0.5, 0.5)
		bt.Size = UDim2.fromScale(1, 1)
		bt.TextYAlignment = Enum.TextYAlignment.Center
		bt.ZIndex = 8
		bt.Parent = b
	end
	local hovered = false
	local bob: RBXScriptConnection? = nil
	local api: Button
	root.MouseEnter:Connect(function()
		hovered = true
		face.ImageColor3 = lift(color, 0.16)
		Kit.tween(glow, 0.16, { ImageTransparency = 0 })
		Kit.tween(holder, 0.16, { Position = UDim2.fromOffset(0, -5) }, Enum.EasingStyle.Back)
		-- the icon hops and settles on a little spring while you're on it
		local t0 = os.clock()
		if bob then bob:Disconnect() end
		bob = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			img.Position = UDim2.new(0.5, 0, 0.38, -math.abs(math.sin(t * 7)) * 7 * math.exp(-t * 2.4))
			img.Rotation = math.sin(t * 9) * 5 * math.exp(-t * 2.2)
		end)
	end)
	root.MouseLeave:Connect(function()
		hovered = false
		face.ImageColor3 = color
		Kit.tween(glow, 0.2, { ImageTransparency = 0.25 })
		Kit.tween(holder, 0.16, { Position = UDim2.fromOffset(0, 0) })
		Kit.tween(scale, 0.12, { Scale = 1 })
		if bob then
			bob:Disconnect()
			bob = nil
		end
		Kit.tween(img, 0.15, { Rotation = 0, Position = UDim2.fromScale(0.5, 0.38) })
	end)
	root.MouseButton1Down:Connect(function()
		Kit.tween(holder, 0.06, { Position = UDim2.fromOffset(0, 1) })
		Kit.tween(scale, 0.06, { Scale = 0.93 })
	end)
	root.MouseButton1Up:Connect(function()
		Kit.tween(holder, 0.2, { Position = UDim2.fromOffset(0, if hovered then -5 else 0) }, Enum.EasingStyle.Back)
		Kit.tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	root.Activated:Connect(function() if api.onClick then api.onClick() end end)
	api = {
		root = root, face = face, label = l, onClick = nil,
		setEnabled = function(_on: boolean) end,
		setText = function(t: string) l.Text = string.upper(t) end,
		setColor = function(c: Color3)
			color = c
			face.ImageColor3 = c
			glow.ImageColor3 = c
		end,
	}
	return api
end

-- an item well filling its parent: a dark inside, its border in the item's rarity colour. Returns
-- the well; "EdgeArt" is the drawn well (its tint is the rarity), and its "Edge" frame keeps a
-- hidden "Rarity" UIStroke for the screens that read or set the colour.
function Kit.slot(parent: Instance, color: Color3, z: number?): Frame
	local zi = z or 5
	local well = UI.mk("Frame", { Name = "Slot", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = zi, Parent = parent })
	local art = Kit.slice("well", color, well, zi, 0.45)
	art.Name = "EdgeArt"
	-- a soft wash of the rarity rising from the bottom
	UI.mk("ImageLabel", {
		Name = "Wash", Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1, Image = Art.glow,
		ImageColor3 = color, ImageTransparency = 0.45, ZIndex = zi, Parent = well,
	}, { UI.corner(10) })
	local edge = UI.mk("Frame", {
		Name = "Edge", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), BackgroundTransparency = 1, ZIndex = zi + 1, Parent = well,
	}, { UI.corner(7) })
	local stroke = UI.mk("UIStroke", { Name = "Rarity", Color = color, Thickness = 2.5, Transparency = 1, Parent = edge })
	stroke:GetPropertyChangedSignal("Color"):Connect(function()
		art.ImageColor3 = stroke.Color
		;(well:FindFirstChild("Wash") :: ImageLabel).ImageColor3 = stroke.Color
	end)
	return well
end

-- a name plate: a pill in a colour with white capitals (a slot's rarity, a badge)
function Kit.plate(parent: Instance, text: string, color: Color3, pos: UDim2, size: UDim2, z: number?): (Frame, TextLabel)
	local zi = z or 7
	local f = UI.mk("Frame", { Name = "Plate", Position = pos, Size = size, BackgroundTransparency = 1, ZIndex = zi, Parent = parent })
	Kit.slice("plate", color, f, zi, math.min(0.5, size.Y.Offset / Art.plate.h))
	local t = Kit.text(string.upper(text), 14, C.white, 2)
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.new(0.5, 0, 0.5, -1)
	t.Size = UDim2.new(1, -14, 1, -4)
	Kit.fit(t, size.Y.Offset * 0.58)
	t.ZIndex = zi + 1
	t.Parent = f
	return f, t
end

-- a tab: the screen's colour when it's the one you're on, dark when not; setColor(C.grey) turns it
-- off, any other colour on
function Kit.tab(text: string, size: UDim2, on: boolean): Button
	local b = Kit.button(text, if on then C.accent else C.grey, size, math.floor(size.Y.Offset * 0.44))
	local setDark = (b :: any).setDark
	local setColor = b.setColor
	local wasOn = on
	setDark(not on)
	b.setColor = function(c: Color3)
		local nowOn = c ~= C.grey
		setColor(c)
		setDark(not nowOn)
		if nowOn and not wasOn then Kit.pop(b.root:FindFirstChild("Holder") :: Frame, 0.88, 0.25) end
		wasOn = nowOn
	end
	return b
end
--==============================================================
-- controls: a slider, a segmented choice, a switch
--==============================================================
-- a slider: the kit's bar with a round knob on its end. value 0..1; onChange runs while it's dragged
-- (and on a click), returns the control and a function to set it from outside
function Kit.slider(width: number, value: number, onChange: (number) -> (), color: Color3?): (Frame, (number) -> ())
	local UserInputService = game:GetService("UserInputService")
	local root = UI.mk("Frame", { Size = UDim2.fromOffset(width, 34), BackgroundTransparency = 1, Active = true })
	local track, fill = Kit.bar(width, 22, color or C.accent)
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(0, 0.5)
	track.Parent = root
	local knob = UI.mk("Frame", {
		Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = C.white, ZIndex = 20, Parent = root,
	}, { UI.corner(14) })
	UI.mk("UIStroke", { Color = C.ink, Thickness = 3, Parent = knob })
	local current = value
	local function show(v: number)
		current = math.clamp(v, 0, 1)
		fill.Size = UDim2.fromScale(current, 1)
		knob.Position = UDim2.new(current, 0, 0.5, 0)
	end
	show(value)
	local dragging = false
	local function fromX(x: number)
		local a, w = root.AbsolutePosition.X, math.max(1, root.AbsoluteSize.X)
		show((x - a) / w)
		onChange(current)
	end
	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			Kit.tween(knob, 0.1, { Size = UDim2.fromOffset(34, 34) })
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
			Kit.tween(knob, 0.14, { Size = UDim2.fromOffset(28, 28) }, Enum.EasingStyle.Back)
		end
	end)
	return root, show
end

-- a row of choices, the picked one lit: options are { id, label }; returns the row and set(id)
function Kit.segment(options: { { id: string, label: string } }, current: string, w: number, h: number, onPick: (string) -> ()): (Frame, (string) -> ())
	local row = UI.mk("Frame", { Size = UDim2.fromOffset(w * #options + 8 * (#options - 1), h), BackgroundTransparency = 1 })
	local tabs = {}
	local function set(id: string)
		for k, t in pairs(tabs) do t.setColor(if k == id then C.accent else C.grey) end
	end
	for i, o in ipairs(options) do
		local t = Kit.tab(o.label, UDim2.fromOffset(w, h), o.id == current)
		t.root.Position = UDim2.fromOffset((i - 1) * (w + 8), 0)
		t.root.Parent = row
		t.onClick = function()
			set(o.id)
			onPick(o.id)
		end
		tabs[o.id] = t
	end
	return row, set
end

-- a switch: a pill that goes green when on, its knob sliding across
function Kit.toggle(on: boolean, onChange: (boolean) -> ()): (TextButton, (boolean) -> ())
	local root = UI.mk("TextButton", { Size = UDim2.fromOffset(84, 40), BackgroundTransparency = 1, Text = "", AutoButtonColor = false })
	local pill = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.grey, Parent = root }, { UI.corner(20) })
	UI.mk("UIStroke", { Color = C.ink, Thickness = 3, Parent = pill })
	local knob = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = C.white, ZIndex = 3, Parent = pill }, { UI.corner(15) })
	UI.mk("UIStroke", { Color = C.ink, Thickness = 2.5, Parent = knob })
	local label = Kit.text("", 14, C.white, 2)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	label.Parent = pill
	local state = on
	local function show(v: boolean, instant: boolean?)
		state = v
		local goal = if v then UDim2.new(1, -22, 0.5, 0) else UDim2.new(0, 22, 0.5, 0)
		if instant then knob.Position = goal else Kit.tween(knob, 0.16, { Position = goal }, Enum.EasingStyle.Back) end
		Kit.tween(pill, 0.16, { BackgroundColor3 = if v then C.green else C.grey })
		label.Text = if v then "ON" else "OFF"
		label.TextXAlignment = if v then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
		label.Position = UDim2.fromOffset(if v then 12 else -12, 0)
	end
	show(on, true)
	root.Activated:Connect(function()
		show(not state)
		onChange(state)
	end)
	return root, function(v: boolean) show(v) end
end

--==============================================================
-- animation helpers
--==============================================================
local function scaleOf(g: GuiObject): UIScale
	local s = g:FindFirstChild("KitScale") :: UIScale?
	if not s then
		s = UI.mk("UIScale", { Name = "KitScale", Parent = g })
	end
	return s :: UIScale
end
Kit.scaleOf = scaleOf

-- squash in from `from` (default 0.6) past 1 and settle: the house "something happened" move
function Kit.pop(g: GuiObject, from: number?, time: number?)
	local s = scaleOf(g)
	s.Scale = from or 0.6
	Kit.tween(s, time or 0.32, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- appear: fade and pop in from slightly below
function Kit.appear(g: GuiObject, delay: number?, rise: number?)
	local rest = g.Position
	local s = scaleOf(g)
	g.Visible = true
	s.Scale = 0.7
	g.Position = rest + UDim2.fromOffset(0, rise or 24)
	task.delay(delay or 0, function()
		Kit.tween(g, 0.35, { Position = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		Kit.tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
end

function Kit.vanish(g: GuiObject, time: number?, after: (() -> ())?)
	local s = scaleOf(g)
	Kit.tween(s, time or 0.18, { Scale = 0.6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.delay(time or 0.18, function()
		g.Visible = false
		s.Scale = 1
		if after then after() end
	end)
end

function Kit.shake(g: GuiObject, amp: number, time: number)
	local rest = g.Position
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t >= time or not g.Parent then
			conn:Disconnect()
			g.Position = rest
			return
		end
		local k = (1 - t / time)
		g.Position = rest + UDim2.fromOffset(math.sin(t * 60) * amp * k, math.cos(t * 47) * amp * 0.4 * k)
	end)
end

-- a gentle idle bob for things that want attention (a ready button, a gift)
function Kit.bob(g: GuiObject, amp: number?, speed: number?): () -> ()
	local rest = g.Position
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		if not g.Parent then return end
		local t = os.clock() - t0
		g.Position = rest + UDim2.fromOffset(0, math.sin(t * (speed or 3)) * (amp or 4))
	end)
	return function()
		conn:Disconnect()
		g.Position = rest
	end
end

-- roll a number up on a label, ticking as it goes
function Kit.countUp(label: TextLabel, from: number, to: number, time: number, fmt: (number) -> string, onTick: (() -> ())?)
	local t0 = os.clock()
	local last = -1
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / time, 0, 1)
		local e = 1 - (1 - k) ^ 3
		local v = from + (to - from) * e
		label.Text = fmt(v)
		local step = math.floor(k * 20)
		if step ~= last then
			last = step
			if onTick then onTick() end
		end
		if k >= 1 then
			conn:Disconnect()
			Kit.pop(label, 1.25, 0.25)
		end
	end)
end

-- a big outlined word that pops up and floats away ("PERFECT!", "SMASH!", "+1 KEY")
function Kit.callout(parent: Instance, text: string, color: Color3, pos: UDim2, size: number?)
	local l = Kit.text(text, size or 46, color, 3.5)
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = pos
	l.Size = UDim2.fromOffset(600, (size or 46) + 10)
	l.ZIndex = 50
	l.Rotation = math.random(-6, 6)
	l.Parent = parent
	Kit.pop(l, 0.3, 0.28)
	task.delay(0.55, function()
		Kit.tween(l, 0.45, { Position = pos - UDim2.fromOffset(0, 60), TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then Kit.tween(st, 0.45, { Transparency = 1 }) end
		task.delay(0.5, function() l:Destroy() end)
	end)
	return l
end

--==============================================================
-- the dim behind an open menu: one shared sheet, faded in while any menu holds it
--==============================================================
local dimHolders: { [any]: boolean } = {}
local dimFrame: Frame? = nil
function Kit.dim(gui: Instance, holder: any, on: boolean)
	if not dimFrame then
		dimFrame = UI.mk("Frame", {
			-- reaches past the top inset too
			Name = "KitDim", Size = UDim2.new(1, 0, 1, 120), Position = UDim2.fromOffset(0, -60), BackgroundColor3 = Color3.fromRGB(10, 10, 14),
			BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 29, Visible = false, Parent = gui,
		})
	end
	dimHolders[holder] = on or nil
	local any = next(dimHolders) ~= nil
	local f = dimFrame :: Frame
	local vig = f:FindFirstChild("Vignette") :: ImageLabel?
	if not vig then
		-- a soft dark edge round the screen, so the eye goes to what's open
		vig = UI.mk("ImageLabel", {
			Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Art.vignette, ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Stretch, ZIndex = 29, Parent = f,
		}) :: ImageLabel
	end
	if any then
		f.Visible = true
		Kit.tween(f, 0.2, { BackgroundTransparency = 0.5 })
		Kit.tween(vig :: ImageLabel, 0.25, { ImageTransparency = 0.1 })
	else
		Kit.tween(vig :: ImageLabel, 0.18, { ImageTransparency = 1 })
		local tw = Kit.tween(f, 0.18, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function()
			if next(dimHolders) == nil then f.Visible = false end
		end)
	end
end

--==============================================================
-- bars and rings
--==============================================================
-- every bar's stripes, scrolled together on one clock
local stripeSet: { [ImageLabel]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local stripeConn: RBXScriptConnection? = nil
local function scrollStripes(img: ImageLabel)
	stripeSet[img] = true
	if stripeConn then return end
	stripeConn = RunService.RenderStepped:Connect(function()
		local x = (os.clock() * 26) % 32
		for s in pairs(stripeSet) do
			if s.Parent and s.Visible then s.Position = UDim2.fromOffset(-32 + x, 0) end
		end
	end)
end

-- a progress bar: a groove and a painted strip in it, diagonal stripes scrolling along the strip;
-- returns the track and the fill (set the fill's Size scale X to show progress)
function Kit.bar(width: number, height: number, color: Color3): (Frame, Frame)
	local track = UI.mk("Frame", { Size = UDim2.fromOffset(width, height), BackgroundTransparency = 1 })
	Kit.slice("track", nil, track, 1, math.min(0.5, height / Art.track.h))
	local fill = UI.mk("Frame", {
		Position = UDim2.fromOffset(3, 3), Size = UDim2.fromScale(0, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2, Parent = track,
	})
	-- the strip is full width and revealed from the left, so its rounded end never squashes
	local ih = height - 6
	local inner = UI.mk("Frame", { Size = UDim2.fromOffset(width - 6, ih), BackgroundTransparency = 1, ZIndex = 2, Parent = fill })
	local strip = Kit.slice("fill", color, inner, 2, math.min(0.5, ih / Art.fill.h))
	strip.Name = "Strip"
	local stripes = UI.mk("ImageLabel", {
		Name = "Stripes", Size = UDim2.new(1, 64, 1, 0), BackgroundTransparency = 1, Image = Art.stripes, ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(32, 32), ZIndex = 3, Parent = UI.mk("Frame", {
			Position = UDim2.fromOffset(4, 2), Size = UDim2.new(1, -8, 1, -4), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 3, Parent = inner,
		}, { UI.corner(math.floor(ih / 2)) }),
	})
	scrollStripes(stripes)
	-- colour changes on the fill reach the strip
	fill:GetPropertyChangedSignal("BackgroundColor3"):Connect(function() strip.ImageColor3 = fill.BackgroundColor3 end)
	-- the fill's size is set as a share of the track; keep it inside the groove's inset
	fill:GetPropertyChangedSignal("Size"):Connect(function()
		local s = fill.Size
		if s.Y.Offset ~= -6 then fill.Size = UDim2.new(s.X.Scale, math.min(s.X.Offset, 0) - math.floor(6 * s.X.Scale), 1, -6) end
	end)
	fill.Size = UDim2.new(0, 0, 1, -6)
	return track, fill
end

-- the panel inside a screen's root (scaled while it opens, so the root's own fit-to-screen
-- UIScale is left alone)
local function bodyOf(root: GuiObject): GuiObject
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("Frame") and c:FindFirstChild("Face") then return c end
	end
	return root
end

-- open a screen: it fades in rising and settling, the crest rolls in, the contents follow; any
-- label that doesn't fit its box is made to
function Kit.open(root: GuiObject)
	local body = bodyOf(root)
	local s = Kit.scaleOf(body)
	s.Scale = 0.95
	UI.fade(root, true, { dur = 0.3 * (workspace:GetAttribute("KitSlow") or 1), offset = 24 })
	Kit.tween(s, 0.4, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local crest = root:FindFirstChild("Header", true) :: Frame?
	if crest then Kit.crestIn(crest, 0.08) end
	task.defer(function() Kit.fitAll(root) end)
end

-- close a screen: it sinks and fades; `after` runs once it's fully gone
function Kit.close_(root: GuiObject, after: (() -> ())?)
	local body = bodyOf(root)
	local s = Kit.scaleOf(body)
	Kit.tween(s, 0.2, { Scale = 0.96 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UI.fade(root, false, { dur = 0.2 * (workspace:GetAttribute("KitSlow") or 1), offset = 18 }, function()
		s.Scale = 1
		if after then after() end
	end)
end

-- children appear one after another, each rising a little (a grid filling in)
function Kit.cascade(list: { GuiObject }, step: number?)
	for i, g in ipairs(list) do
		Kit.appear(g, (i - 1) * (step or 0.025), 14)
	end
end

-- a ring of chunky segments around a centre (the heat ring on the boost button)
function Kit.ring(parent: GuiObject, count: number, radius: number, segSize: Vector2): { Frame }
	local segs = {}
	for i = 1, count do
		local a = math.rad(-225 + (i - 0.5) / count * 270)
		local s = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(a) * radius, 0.5, math.sin(a) * radius),
			Size = UDim2.fromOffset(segSize.X, segSize.Y), Rotation = math.deg(a) + 90, BackgroundColor3 = C.night,
			BorderSizePixel = 0, ZIndex = 4, Parent = parent,
		}, { UI.corner(3) })
		UI.mk("UIStroke", { Color = C.ink, Thickness = 2, Parent = s })
		table.insert(segs, s)
	end
	return segs
end

return Kit
