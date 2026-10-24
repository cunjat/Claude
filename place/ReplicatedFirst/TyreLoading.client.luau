--!strict
-- TYRE CANNON :: Loading (ReplicatedFirst)
-- The loading plate: the steel plate (art/ui/ps/intro.jsx) covers everything until the game is
-- ready (the world is never seen behind it). The title is drawn here in the kit's look (a gold-to-orange fill, a thick near-black edge,
-- a drop shadow): its letters slam in one after another, settle with a squash, a shine runs across
-- and they ride a slow wave. Then the tyre rolls onto the bar, and the bar fills one step at a
-- time: waking up, fetching your save, then each of Preload's stages. Every step stays on
-- screen a moment even when it loads instantly, so the bar glides instead of jumping, and it never
-- lifts before 100%. The plate carries only the bar at first (the logo is kept for the scene).
-- As soon as the game's scripts are in, the plate dissolves into the loading scene behind it: the
-- tyre comes rocketing in from behind the camera and brakes into slow motion, and as it arrives
-- TYRE GAME punches in letter by letter toward you, the last one with a flash, a jolt, a burst of
-- dust and a thump; UNTITLED slides on like a sticker; a shine runs across. The scene (LoadScene: a tyre in slow motion high over the Backroad, the run's own wind and
-- light) with the logo and the bar still on top; when loading's done the tyre takes off down the
-- road, the screen washes over to a high shot of your yard and the camera glides down behind you:
-- straight into the game, no title in between. If the scene can't be built, the old way: the
-- bar's tyre drives off the screen and the plate goes with it.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

-- the plate's art. The ids are filled in by tools/apply_ids.py after the images are uploaded
local ART = {
	-- (2026-10-22, the owner: "lets finally do something about that opening menu") the grey scratched
	-- steel said nothing about the game: a road at dusk rushing to the horizon (art/ui/loading_bg2.py)
	bg = "rbxassetid://83897135339661",       -- loading_bg2.png
	untitled = { id = "rbxassetid://131747573380630", w = 817, h = 146 },
	tyre = { id = "rbxassetid://83705757823133", w = 808, h = 273 },
	game = { id = "rbxassetid://85510895823582", w = 965, h = 279 },
}
local TYRE = "rbxassetid://126515425222861" -- the game tyre, face-on (the icon studio's)
-- the title, drawn as text (set USE_ART to show the old word images instead)
local USE_ART = false
-- (2026-10-22: the game's name, as the Welcome and the store say it, not the working title)
local TITLE_TOP = "TYRE"
local TITLE_WORDS = { "CANNON" }
local TIPS = {
	"Hills are your speed. Tuck on the way down, leave the crest, land on the slope.",
	"Crates open with keys. Grab them off the road.",
	"Rarer tyres fuse with fewer copies: six Commons, four Legendaries, two Secrets.",
	"Hold TUCK as you touch down to brace the landing. A timed landing is never a crash.",
	"Tyres from the Highway and Dunes crates pay x2 and x4, at every rarity.",
	"Your best run rolls beside you as a ghost. Beat it.",
	"Upgrade your plot to move up a stage: a new cannon and a faster start.",
	"A Heat starts every few minutes. Join it from the top of the screen.",
}
-- the kit's progress bar pieces (art/ui/kit4.py): a groove and a strip (tinted)
local TRACK = { id = "rbxassetid://129587575566396", slice = Rect.new(52, 46, 476, 50) }
local FILL = { id = "rbxassetid://112159920394542", slice = Rect.new(46, 40, 482, 44) }

-- the two steps this script owns, then Preload's stages (Main reports how many there are)
local OWN_STEPS = { "WAKING UP", "FETCHING YOUR SAVE" }
local DEFAULT_PRELOAD_STAGES = 6
local MIN_STEP = 0.8       -- seconds every step stays on screen, however fast it really was
local ENTRANCE = 1.5       -- the logo finishes coming in before the bar starts moving
local BAR_W = 560
local LOGO_W = 640         -- the logo's row of words is this wide, before the screen scales it

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
playerGui:SetAttribute("IntroPlaying", true)
-- a short trail of what the loading screen did and when, for testing
local started = os.clock()
local function mark(what: string)
	local prev = playerGui:GetAttribute("IntroLog") or ""
	playerGui:SetAttribute("IntroLog", prev .. ("%.1f %s; "):format(os.clock() - started, what))
end
mark("start")

local DISPLAY = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
local MONO = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)

local function mk(class: string, props: { [string]: any }): any
	local o = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then (o :: any)[k] = v end
	end
	o.Parent = props.Parent
	return o
end

local function tween(o: Instance, t: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end
local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end
local function easeIn(t: number): number
	return t * t * t
end
local function backOut(t: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

--==============================================================
-- the plate
--==============================================================
local gui = mk("ScreenGui", {
	Name = "TyreLoading", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui,
})
ReplicatedFirst:RemoveDefaultLoadingScreen()

local black = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 8, 9), BorderSizePixel = 0, ZIndex = 1, Parent = gui })
local door = mk("CanvasGroup", { Name = "Door", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(70, 72, 76), BorderSizePixel = 0, ZIndex = 2, Parent = gui })
local doorImg = mk("ImageLabel", {
	Name = "DoorImage", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.08, 1.08),
	BackgroundTransparency = 1, Image = ART.bg, ScaleType = Enum.ScaleType.Crop, ZIndex = 3, Parent = door,
})
tween(doorImg, 14, { Size = UDim2.fromScale(1.0, 1.0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
-- the whole plate fades up out of black at the start
local fade = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 8, 9), BorderSizePixel = 0, ZIndex = 40, Parent = door })

-- the logo: three words in a holder scaled to the screen; UNTITLED over TYRE and GAME
local ROW = ART.tyre.w + ART.game.w + 80
local k0 = LOGO_W / ROW
local function wordSize(w): (number, number)
	return math.floor(w.w * k0), math.floor(w.h * k0)
end
local uw, uh = wordSize(ART.untitled)
local tw_, th = wordSize(ART.tyre)
local gw, gh = wordSize(ART.game)
local gap = math.floor(80 * k0)
local rowH = math.max(th, gh)
local logoH = uh + 10 + rowH
local logoRest = UDim2.fromScale(0.5, 0.36)
local logoHolder = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = logoRest, Size = UDim2.fromOffset(LOGO_W, logoH), BackgroundTransparency = 1, ZIndex = 6, Parent = door,
})
do
	local sc = mk("UIScale", { Scale = 1, Parent = logoHolder })
	local function fit()
		local v = gui.AbsoluteSize
		if v.X > 50 and v.Y > 50 then sc.Scale = math.clamp(math.min(v.X / 900, v.Y / 560), 0.55, 1.6) end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end
local rowX = (LOGO_W - (tw_ + gap + gw)) / 2
local function word(w, x: number, y: number, width: number, height: number)
	local holder = mk("Frame", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height), BackgroundTransparency = 1, ZIndex = 6, Parent = logoHolder })
	local img = mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Image = w.id, ScaleType = Enum.ScaleType.Fit, ImageTransparency = 1, ZIndex = 6, Parent = holder, Visible = USE_ART,
	})
	return holder, img
end
local wUntitled, iUntitled = word(ART.untitled, (LOGO_W - uw) / 2, 0, uw, uh)
local wTyre, iTyre = word(ART.tyre, rowX, uh + 10, tw_, th)
local wGame, iGame = word(ART.game, rowX + tw_ + gap, uh + 10, gw, gh)
local restUntitled, restTyre = wUntitled.Position, wTyre.Position

-- the drawn title: one label a letter (fill, edge, shadow), laid out by its real width
local ITALIC = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local TextService = game:GetService("TextService")
local letters: { { holder: Frame, label: TextLabel, shadow: TextLabel, scale: UIScale, rest: UDim2, delay: number, big: boolean } } = {}
local shineGrads: { UIGradient } = {}
local function letterWidth(ch: string, size: number): number
	local ok, v = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = ch
		params.Font = ITALIC
		params.Size = size
		params.Width = 1000
		return TextService:GetTextBoundsAsync(params)
	end)
	if ok and v then return v.X end
	return size * 0.68
end
local function drawWord(text: string, size: number, y: number, big: boolean, delay0: number, fillTop: Color3, fillBottom: Color3)
	local widths, total = {}, 0
	for i = 1, #text do
		local w = letterWidth(text:sub(i, i), size) + (big and 2 or 1)
		widths[i] = w
		total += w
	end
	local x = (LOGO_W - total) / 2
	for i = 1, #text do
		local ch = text:sub(i, i)
		local h = mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(x + widths[i] / 2, y + size), Size = UDim2.fromOffset(widths[i] + 8, size + 10),
			BackgroundTransparency = 1, ZIndex = 6, Parent = logoHolder,
		})
		local sc = mk("UIScale", { Scale = 1, Parent = h })
		local shadow = mk("TextLabel", {
			Position = UDim2.fromOffset(4, 7), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = ch, FontFace = ITALIC,
			TextSize = size, TextColor3 = Color3.new(0, 0, 0), TextTransparency = 1, ZIndex = 6, Parent = h,
		})
		local l = mk("TextLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = ch, FontFace = ITALIC, TextSize = size,
			TextColor3 = Color3.new(1, 1, 1), TextTransparency = 1, ZIndex = 7, Parent = h,
		})
		mk("UIGradient", { Rotation = 90, Color = ColorSequence.new(fillTop, fillBottom), Parent = l })
		mk("UIStroke", { Color = Color3.fromRGB(16, 12, 10), Thickness = big and 5 or 3, Transparency = 1, LineJoinMode = Enum.LineJoinMode.Round, Parent = l })
		-- the shine: a white copy over the letter, shown only where a bright band passes
		local shine = mk("TextLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = ch, FontFace = ITALIC, TextSize = size,
			TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.15, ZIndex = 8, Visible = false, Parent = h,
		})
		local g = mk("UIGradient", {
			Rotation = 20, Offset = Vector2.new(-1.6, 0),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.1),
				NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = shine,
		})
		table.insert(shineGrads, g)
		table.insert(letters, { holder = h, label = l, shadow = shadow, scale = sc, rest = h.Position, delay = delay0 + (i - 1) * 0.055, big = big })
		x += widths[i]
	end
end
if not USE_ART then
	local topSize, bigSize = 40, 104
	drawWord(TITLE_TOP, topSize, 0, false, 0.95, Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 200, 210))
	drawWord(table.concat(TITLE_WORDS, " "), bigSize, topSize + 12, true, 0.0, Color3.fromRGB(255, 226, 92), Color3.fromRGB(255, 120, 30))
	logoHolder.Size = UDim2.fromOffset(LOGO_W, topSize + 12 + bigSize + 14)
end
-- the logo's own clock: nil until it plays (on the scene, or on the plate when there's none)
local logoStart: number? = nil
local logoRest = UDim2.fromScale(0.5, 0.36)
local logoShake = 0
local impactDone = false
local onImpact: (() -> ())? = nil
-- each letter punches in toward you (from big, tilted, to its place) and lands with a squash; the
-- big word's letters jolt the logo as they land, and the last one is the impact; then a shine, and
-- they ride a slow wave
local shineDone = false
local lastBig = 0
for _, L in ipairs(letters) do
	if L.big then lastBig = math.max(lastBig, L.delay) end
end
local function animateLetters(t: number)
	for i, L in ipairs(letters) do
		local a = clamp01((t - L.delay) / 0.2)
		local settle = 0
		local squash = 1
		if a >= 1 then
			local s = t - L.delay - 0.2
			settle = -8 * math.exp(-s * 9) * math.abs(math.sin(s * 15))
			squash = 1 - 0.2 * math.exp(-s * 12) * math.cos(s * 22) ^ 2
			if t > lastBig + 1.6 then settle += math.sin((t - lastBig - 1.6) * 2.2 - i * 0.45) * (L.big and 3 or 2) end
			if not (L :: any).landed then
				(L :: any).landed = true
				if L.big then
					logoShake = math.max(logoShake, 4)
					if L.delay >= lastBig and not impactDone then
						impactDone = true
						logoShake = 12
						if onImpact then task.spawn(onImpact) end
					end
				end
			end
		end
		local slide = if L.big then 0 else (1 - easeOut(a)) * -60
		L.holder.Position = L.rest + UDim2.fromOffset(slide, settle + (1 - a) * -14)
		L.scale.Scale = if a < 1 then 1 + (1 - easeIn(a)) * (L.big and 2.2 or 0.6) else squash
		L.holder.Rotation = (1 - a) * (if L.big then (i % 2 == 0 and 14 or -14) else -6)
		local vis = clamp01((t - L.delay) / 0.05)
		L.label.TextTransparency = 1 - vis
		L.shadow.TextTransparency = 1 - vis * 0.55
		local st = L.label:FindFirstChildOfClass("UIStroke")
		if st then st.Transparency = 1 - vis end
	end
	-- the shine, once everything has landed
	if not shineDone and t > 1.6 then
		shineDone = true
		for _, g in ipairs(shineGrads) do
			local sh = g.Parent :: TextLabel
			sh.Visible = true
			local tw = tween(g, 0.8, { Offset = Vector2.new(1.6, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			tw.Completed:Connect(function() sh.Visible = false end)
		end
	end
end
local tagline = mk("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.36, 110), Size = UDim2.fromOffset(600, 22),
	BackgroundTransparency = 1, Text = "LAUNCH IT   ·   UPGRADE IT   ·   SEND IT FURTHER", FontFace = DISPLAY, TextSize = 17,
	TextColor3 = Color3.fromRGB(255, 255, 255), TextTransparency = 1, ZIndex = 6, Parent = door,
})
mk("UIStroke", { Color = Color3.fromRGB(14, 12, 18), Thickness = 2.5, Transparency = 0.15, Parent = tagline })
local taglineRest = tagline.Position

-- the bar block sizes to the screen: smaller on a phone, a touch larger on a big monitor
local bottom = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -44), Size = UDim2.fromOffset(BAR_W + 40, 136),
	BackgroundTransparency = 1, ZIndex = 6, Parent = door,
})
do
	local sc = mk("UIScale", { Scale = 1, Parent = bottom })
	local function fit()
		local v = gui.AbsoluteSize
		if v.X > 50 and v.Y > 50 then sc.Scale = math.clamp(math.min(v.X / 700, v.Y / 620), 0.6, 1.2) end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end
-- (the bar's tyre sits at the bar's left end: the step's name starts clear of it)
local status = mk("TextLabel", {
	Position = UDim2.fromOffset(62, 0), Size = UDim2.fromOffset(380, 24), BackgroundTransparency = 1,
	Text = "WAKING UP", FontFace = DISPLAY, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 255, 255), TextTransparency = 1, ZIndex = 7, Parent = bottom,
})
local pct = mk("TextLabel", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 0), Size = UDim2.fromOffset(120, 24), BackgroundTransparency = 1,
	Text = "0%", FontFace = DISPLAY, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = Color3.fromRGB(255, 196, 58), TextTransparency = 1, ZIndex = 7, Parent = bottom,
})
local strokes = {}
for _, l in ipairs({ status, pct }) do
	table.insert(strokes, mk("UIStroke", { Color = Color3.fromRGB(14, 12, 18), Thickness = 2.5, Transparency = 1, Parent = l }))
end
-- the bar: one segment per step, so it visibly moves a thing at a time
local track = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.fromOffset(BAR_W, 22),
	BackgroundTransparency = 1, ZIndex = 7, Parent = bottom,
})
local trackArt = mk("ImageLabel", {
	Position = UDim2.fromOffset(-12, -12), Size = UDim2.new(1, 24, 1, 24), BackgroundTransparency = 1, Image = TRACK.id,
	ScaleType = Enum.ScaleType.Slice, SliceCenter = TRACK.slice, SliceScale = 22 / 48, ImageTransparency = 1, ZIndex = 7, Parent = track,
})
local fillClip = mk("Frame", {
	Position = UDim2.fromOffset(3, 3), Size = UDim2.new(0, 0, 1, -6), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 8, Parent = track,
})
local fillBox = mk("Frame", { Size = UDim2.fromOffset(BAR_W - 6, 16), BackgroundTransparency = 1, ZIndex = 8, Parent = fillClip })
mk("ImageLabel", {
	Position = UDim2.fromOffset(-8, -8), Size = UDim2.new(1, 16, 1, 16), BackgroundTransparency = 1, Image = FILL.id,
	ScaleType = Enum.ScaleType.Slice, SliceCenter = FILL.slice, SliceScale = 16 / 36, ImageColor3 = Color3.fromRGB(255, 160, 40), ZIndex = 8, Parent = fillBox,
})
local segments: { { bg: Frame, fill: Frame } } = {}
local function buildSegments(count: number)
	for _, s in ipairs(segments) do s.bg:Destroy() end
	table.clear(segments)
	local gap2 = 6
	local w = (BAR_W - gap2 * (count - 1)) / count
	for i = 1, count do
		local bg = mk("Frame", {
			Position = UDim2.fromOffset((i - 1) * (w + gap2), 0), Size = UDim2.fromOffset(w, 12),
			BackgroundColor3 = Color3.fromRGB(34, 36, 41), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 7, Visible = false, Parent = track,
		})
		mk("UICorner", { CornerRadius = UDim.new(0, 4), Parent = bg })
		local fill = mk("Frame", {
			Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 8, Parent = bg,
		})
		mk("UICorner", { CornerRadius = UDim.new(0, 4), Parent = fill })
		table.insert(segments, { bg = bg, fill = fill })
	end
end
-- the tyre that rolls along the top of the bar (and drives off at the end)
local roller = mk("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(0, 60), Size = UDim2.fromOffset(60, 60),
	BackgroundTransparency = 1, Image = TYRE, ImageTransparency = 1, ZIndex = 9, Parent = bottom,
})
local tip = mk("TextLabel", {
	Position = UDim2.fromOffset(0, 94), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, TextWrapped = true,
	Text = TIPS[math.random(1, #TIPS)], FontFace = MONO, TextSize = 16, TextColor3 = Color3.fromRGB(236, 232, 222),
	TextTransparency = 1, ZIndex = 7, Parent = bottom,
})
mk("UIStroke", { Color = Color3.fromRGB(14, 12, 18), Thickness = 2, Transparency = 0.2, Parent = tip })
-- dust kicked up where TYRE lands and behind the tyre as it leaves: a few soft puffs
local dustLayer = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 12, Parent = gui })
local function puff(x: number, y: number, count: number, spread: number)
	for i = 1, count do
		local side = (i % 2 == 0) and 1 or -1
		local p = mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + side * math.random(4, spread), y - 4),
			Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(170, 168, 164), BackgroundTransparency = 0.5,
			BorderSizePixel = 0, ZIndex = 12, Parent = dustLayer,
		})
		mk("UICorner", { CornerRadius = UDim.new(1, 0), Parent = p })
		local dx = side * math.random(40, 150)
		tween(p, 0.6, {
			Position = UDim2.fromOffset(x + side * math.random(4, spread) + dx, y - math.random(10, 44)),
			Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.65, function() p:Destroy() end)
	end
end
local function landingDust()
	if not USE_ART and #letters > 0 then
		-- under the big word, where its letters land
		local a = letters[#letters].holder
		local first = nil
		for _, L in ipairs(letters) do if L.big and not first then first = L.holder end end
		local f = first or a
		local x0, x1 = f.AbsolutePosition.X, a.AbsolutePosition.X + a.AbsoluteSize.X
		puff((x0 + x1) / 2, a.AbsolutePosition.Y + a.AbsoluteSize.Y, 16, math.floor((x1 - x0) * 0.45))
		return
	end
	local base = wTyre.AbsolutePosition + Vector2.new(wTyre.AbsoluteSize.X / 2, wTyre.AbsoluteSize.Y)
	puff(base.X, base.Y, 12, math.floor(wTyre.AbsoluteSize.X * 0.45))
end
-- the bar's own art first (the intro brings its own; the old plate's logo isn't shown any more)
pcall(function() ContentProvider:PreloadAsync({ roller, status }) end)

--==============================================================
-- the steps: every step shows for at least MIN_STEP, and never runs ahead of what's really done
--==============================================================
local stepNames: { string } = table.clone(OWN_STEPS)
local stepsKnown = false
local function syncStepNames()
	local n = playerGui:GetAttribute("LoadStages")
	if typeof(n) == "number" and n > 0 and not stepsKnown then
		stepsKnown = true
		stepNames = table.clone(OWN_STEPS)
		-- Preload's names arrive one by one; until then they read generically
		for i = 1, n do stepNames[#OWN_STEPS + i] = "LOADING" end
		buildSegments(#stepNames)
	end
end
for i = 1, DEFAULT_PRELOAD_STAGES do stepNames[#OWN_STEPS + i] = "LOADING" end
buildSegments(#stepNames)

local ownDone = { 0, 0 }
local function realDone(i: number): number
	if i <= #OWN_STEPS then return ownDone[i] end
	-- if Preload never reported (it failed), the yard being ready counts for everything
	if playerGui:GetAttribute("TyreReady") and playerGui:GetAttribute("LoadStage") == nil then return 1 end
	local stage = playerGui:GetAttribute("LoadStage")
	local k = playerGui:GetAttribute("LoadStageK")
	if typeof(stage) ~= "number" then return 0 end
	local idx = i - #OWN_STEPS
	if idx < stage then return 1 end
	if idx == stage then return typeof(k) == "number" and k or 0 end
	return 0
end
local function labelFor(name: string): string
	if name:sub(1, 4) == "THE " then return "LOADING " .. name end
	return name
end

local entranceStart = os.clock()
local current, currentStart = 1, nil :: number?
local shown = 0
local finished = false
local barLeft = (BAR_W + 40 - BAR_W) / 2
local rollConn = RunService.RenderStepped:Connect(function(dt)
	local t = os.clock() - entranceStart
	syncStepNames()
	local stageName = playerGui:GetAttribute("LoadStageName")
	local stageIdx = playerGui:GetAttribute("LoadStage")
	if typeof(stageName) == "string" and typeof(stageIdx) == "number" then
		stepNames[#OWN_STEPS + stageIdx] = stageName
	end

	-- the logo: UNTITLED slides in, TYRE drops and lands, GAME pops up; then they sway a little
	fade.BackgroundTransparency = clamp01(t / 0.35)
	local lt = if logoStart then os.clock() - logoStart else -1
	if not USE_ART then animateLetters(lt) end
	logoShake *= math.exp(-dt * 9)
	logoHolder.Position = logoRest + UDim2.fromOffset(math.sin(lt * 70) * logoShake, math.cos(lt * 55) * logoShake * 0.6)
	local land = 0.62
	local a = clamp01((t - 0.12) / 0.45)
	wUntitled.Position = restUntitled + UDim2.fromOffset(-360 * (1 - backOut(a)), 0)
	iUntitled.ImageTransparency = 1 - clamp01((t - 0.12) / 0.1)
	local drop = clamp01((t - 0.3) / 0.32)
	local yOff = -300 * (1 - easeIn(drop))
	local squash = 1
	if t > land then
		local s = t - land
		yOff = -16 * math.exp(-s * 7) * math.abs(math.sin(s * 13))
		squash = 1 - 0.14 * math.exp(-s * 12) * math.cos(s * 22) ^ 2
	end
	wTyre.Position = restTyre + UDim2.fromOffset(0, yOff)
	iTyre.Size = UDim2.fromScale(1, squash)
	iTyre.ImageTransparency = 1 - clamp01((t - 0.3) / 0.1)
	local pop = clamp01((t - 0.72) / 0.35)
	local sg = 0.2 + 0.8 * backOut(pop)
	iGame.Size = UDim2.fromScale(sg, sg)
	iGame.ImageTransparency = 1 - clamp01((t - 0.72) / 0.08)
	local _ = land
	if t > 1.3 then
		-- idle: the words rock a hair out of step with each other
		local sw = t - 1.3
		iUntitled.Rotation = math.sin(sw * 1.7) * 0.7
		iTyre.Rotation = math.sin(sw * 1.7 + 1.2) * 0.9
		iGame.Rotation = math.sin(sw * 1.7 + 2.4) * 0.9
	end
	local tg = easeOut(clamp01((lt - 1.3) / 0.35))
	tagline.TextTransparency = 1 - tg
	local tgs = tagline:FindFirstChildOfClass("UIStroke")
	if tgs then tgs.Transparency = 1 - tg * 0.85 end
	tagline.Position = taglineRest + UDim2.fromOffset(0, 10 * (1 - tg))
	local ui = easeOut(clamp01((t - 0.2) / 0.35))
	status.TextTransparency = 1 - ui
	pct.TextTransparency = 1 - ui
	tip.TextTransparency = 1 - ui
	trackArt.ImageTransparency = 1 - ui
	for _, st in ipairs(strokes) do st.Transparency = 1 - ui * 0.9 end

	-- the steps, once the logo is in
	if t >= ENTRANCE then
		currentStart = currentStart or os.clock()
		local timeK = clamp01((os.clock() - (currentStart :: number)) / MIN_STEP)
		local k = math.min(realDone(current), timeK)
		if k >= 1 and current < #stepNames then
			current += 1
			currentStart = os.clock()
			k = 0
		end
		local target = (current - 1 + k) / #stepNames
		shown += (target - shown) * (1 - math.exp(-dt * 7))
		if current == #stepNames and k >= 1 and target - shown < 0.004 then
			shown = 1
			finished = true
		end
		local label = labelFor(stepNames[current] or "LOADING")
		local count = playerGui:GetAttribute("LoadStageCount")
		if current > #OWN_STEPS and current - #OWN_STEPS == playerGui:GetAttribute("LoadStage") and typeof(count) == "string" and count ~= "" then
			label ..= "   " .. count
		end
		status.Text = finished and "READY" or label
	end

	-- the fill grows; the tyre rolls to the end of it
	fillClip.Size = UDim2.new(0, (BAR_W - 6) * shown, 1, -6)
	local rollIn = easeOut(clamp01((t - 0.3) / 0.7))
	local x = barLeft + BAR_W * shown
	local startX = -120
	local rx = startX + (x - startX) * rollIn
	roller.Position = UDim2.fromOffset(rx, 60 - math.abs(math.sin(rollIn * math.pi * 2)) * 10 * (1 - rollIn))
	roller.Rotation = (rx - startX) / 26 * (180 / math.pi)
	roller.ImageTransparency = 1 - clamp01((t - 0.3) / 0.15)
	pct.Text = math.floor(shown * 100 + 0.5) .. "%"
end)
-- the impact: a white flash, dust along the word's foot, a thump
local flash = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 50, Parent = gui })
local function sfx(id: string, volume: number, pitch: number)
	local snd = Instance.new("Sound")
	snd.SoundId = id
	snd.Volume = volume
	snd.PlaybackSpeed = pitch
	snd.Parent = game:GetService("SoundService")
	snd:Play()
	task.delay(6, function() snd:Destroy() end)
end
onImpact = function()
	flash.BackgroundTransparency = 0.45
	tween(flash, 0.4, { BackgroundTransparency = 1 })
	landingDust()
	sfx("rbxassetid://9114036511", 0.8, 0.9)
end

--==============================================================
-- the intro (2026-10-22, the owner: "a tyre screeching into the scene, with a black background to
-- start, the black background then fades and you get different views of the landmarks on the map
-- that fade and change as things load ... play out centre screen so the tyre can come in clearly and
-- make it move upwards as it fades into the series of views ... these landmarks should also pan
-- slowly"). All 2D, all art made outside Studio (art/blender/intro_tyre.py, art/ui/intro_art.py,
-- art/ui/landmarks_grade.py), on one clock:
--   0.0  black
--   0.35 the tyre bursts in from the left, spinning, braking hard: smoke pours off its contact patch,
--        sparks spray back, the skid mark draws itself behind it; it stops dead centre with a bounce
--   1.9  UNTITLED punches in, then TYRE GAME letter by letter, each landing with a squash and a jolt;
--        the last lands with a flash
--   3.4  the whole emblem eases up to the top and shrinks while the black fades into the first view
--        and the bar comes up at the bottom
--   then the tour: each landmark held ~4.6 s, panning and pushing in slowly, cross-fading into the
--        next, its name sliding in at the bottom left; the emblem floats gently up top
-- When loading's done (and the tour has had at least one full view) the view pushes in, the emblem
-- and the bar go, the screen washes to the sky and the camera glides down behind you as before.
--==============================================================
local INTRO = {
	tyre = "rbxassetid://71686851559800", tyreBlur = "rbxassetid://91800575368756",
	smoke = { "rbxassetid://95608350638883", "rbxassetid://74386028827148", "rbxassetid://134532651776221" },
	skid = "rbxassetid://136736565215145", spark = "rbxassetid://99094210000915",
	-- (2026-10-23, the owner: "we'll go with tyre cannon")
	top = { id = "rbxassetid://80413462775910", w = 573, h = 315 },
	-- CANNON a letter at a time: the image, its size, its centre from the word's centre (wordmark.json)
	letters = {
		{ id = "rbxassetid://123856925664750", w = 627, h = 624, cx = -488.5 },
		{ id = "rbxassetid://139184218720445", w = 671, h = 620, cx = -322.1 },
		{ id = "rbxassetid://136153169132759", w = 684, h = 624, cx = -128.3 },
		{ id = "rbxassetid://137127330347866", w = 684, h = 624, cx = 76.4 },
		{ id = "rbxassetid://118929773779982", w = 662, h = 608, cx = 271.1 },
		{ id = "rbxassetid://140390481630648", w = 684, h = 624, cx = 466.3 },
	},
	-- (2026-10-23, the owner: the landmark grabs "stink") renders of the game's own models
	-- (art/blender/showcase.py), each 2048x1152 in four 1024x576 tiles (Roblox shrinks anything bigger)
	views = {
		{ tiles = { "rbxassetid://102793839520950", "rbxassetid://124171132828845", "rbxassetid://107769955111745", "rbxassetid://84875170399333" }, name = "FIVE CANNONS", sub = "Upgrade your yard, unlock a bigger gun" },
		{ tiles = { "rbxassetid://124031136366846", "rbxassetid://89456005535975", "rbxassetid://137983370543513", "rbxassetid://83764411342848" }, name = "LEGENDARY TYRES", sub = "23 to find, from crates on the road" },
		{ tiles = { "rbxassetid://100707855367018", "rbxassetid://123571364180626", "rbxassetid://72538345617051", "rbxassetid://107780420353550" }, name = "BUILD YOUR YARD", sub = "From a dirt lot to a launch complex" },
		{ tiles = { "rbxassetid://104609854440815", "rbxassetid://92253764575180", "rbxassetid://121418844841408", "rbxassetid://135592333881134" }, name = "THE BACKROAD", sub = "Where every run begins" },
		{ tiles = { "rbxassetid://73673310644843", "rbxassetid://106321767207673", "rbxassetid://85648990303918", "rbxassetid://135226256380735" }, name = "THE GRAND TRUNK", sub = "4 km out: the Highway" },
		{ tiles = { "rbxassetid://82835039943367", "rbxassetid://99806928132859", "rbxassetid://129926961432816", "rbxassetid://94507987382248" }, name = "THE THAR", sub = "12 km out: the Dunes" },
	},
}
local SCALE_L = 0.6       -- the big letters' images are drawn at 300 pt; on the stage at this scale
local SCALE_T = 0.55      -- TYRE's image
local HOLD, FADE = 4.6, 0.9
local introOn = true
local introStart = os.clock()
local introRevealed: number? = nil

-- the layers: the tour (above the old plate), the black, the stage (tyre, smoke, title)
local tour = mk("Frame", { Name = "Tour", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 8, 10), BorderSizePixel = 0, ZIndex = 3, ClipsDescendants = true, Parent = gui })
local introBlack = mk("Frame", { Name = "IntroBlack", Size = UDim2.new(1, 0, 1, 120), Position = UDim2.fromOffset(0, -60), BackgroundColor3 = Color3.fromRGB(4, 4, 6), BorderSizePixel = 0, ZIndex = 4, Parent = gui })
local shadeTop = mk("Frame", { Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = Color3.fromRGB(6, 6, 10), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4, Parent = gui })
mk("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }), Parent = shadeTop })
local shadeBottom = mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.36), BackgroundColor3 = Color3.fromRGB(6, 6, 10), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4, Parent = gui })
mk("UIGradient", { Rotation = -90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }), Parent = shadeBottom })
-- the stage: a 1280x720 canvas in the middle of the screen, scaled to fit it
local stage = mk("Frame", { Name = "Stage", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, ZIndex = 5, Parent = gui })
local stageScale = mk("UIScale", { Scale = 1, Parent = stage })
local function fitStage()
	local v = gui.AbsoluteSize
	if v.X > 50 and v.Y > 50 then stageScale.Scale = math.min(v.X / 1280, v.Y / 720) end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitStage)
fitStage()
-- the emblem: the tyre and the title together, so they rise and shrink as one
local emblem = mk("Frame", { Name = "Emblem", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 0), Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, ZIndex = 6, Parent = stage })
local emblemScale = mk("UIScale", { Scale = 1, Parent = emblem })
local TYRE_SIZE, TYRE_X, TYRE_Y = 270, 640, 210
local GROUND = TYRE_Y + TYRE_SIZE / 2
local skidClip = mk("Frame", { Position = UDim2.fromOffset(-400, GROUND - 14), Size = UDim2.fromOffset(0, 22), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 6, Parent = emblem })
local skid = mk("ImageLabel", { Size = UDim2.fromOffset(1100, 22), BackgroundTransparency = 1, Image = INTRO.skid, ImageTransparency = 0.15, ScaleType = Enum.ScaleType.Stretch, ZIndex = 6, Parent = skidClip })
local smokeLayer = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 7, Parent = emblem })
local tyreHolder = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(-300, TYRE_Y), Size = UDim2.fromOffset(TYRE_SIZE, TYRE_SIZE), BackgroundTransparency = 1, ZIndex = 8, Parent = emblem })
local tyreImg = mk("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = INTRO.tyre, ImageTransparency = 1, ZIndex = 9, Parent = tyreHolder })
local tyreBlur = mk("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = INTRO.tyreBlur, ImageTransparency = 0, ZIndex = 9, Parent = tyreHolder })
local sparkLayer = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10, Parent = emblem })
-- the title pieces, each in a holder (its own scale, so it can punch in)
local titlePieces = {}
local function titlePiece(id: string, w: number, h: number, cx: number, cy: number, s: number, delay: number, big: boolean)
	local holder = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(w * s, h * s), BackgroundTransparency = 1, ZIndex = 11, Parent = emblem })
	local sc = mk("UIScale", { Scale = 0, Parent = holder })
	local img = mk("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = id, ImageTransparency = 1, ZIndex = 11, Parent = holder })
	table.insert(titlePieces, { holder = holder, scale = sc, img = img, rest = holder.Position, delay = delay, big = big, landed = false })
end
titlePiece(INTRO.top.id, INTRO.top.w, INTRO.top.h, 640, 392, SCALE_T, 1.95, false)
for i, L in ipairs(INTRO.letters) do
	titlePiece(L.id, L.w, L.h, 640 + L.cx * SCALE_L, 528, SCALE_L, 2.25 + (i - 1) * 0.075, true)
end
local LAST_LETTER = 2.25 + (#INTRO.letters - 1) * 0.075
local introFlash = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 20, Parent = gui })
-- the captions, bottom left
local capHolder = mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 34, 1, -40), Size = UDim2.fromOffset(520, 64), BackgroundTransparency = 1, ZIndex = 9, Parent = gui })
do
	local sc = mk("UIScale", { Scale = 1, Parent = capHolder })
	local function fit()
		local v = gui.AbsoluteSize
		if v.X > 50 and v.Y > 50 then sc.Scale = math.clamp(math.min(v.X / 1280, v.Y / 720), 0.6, 1.4) end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end
local capName = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Text = "", FontFace = DISPLAY, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1), TextTransparency = 1, ZIndex = 9, Parent = capHolder })
local capNameStroke = mk("UIStroke", { Color = Color3.fromRGB(14, 12, 18), Thickness = 3, Transparency = 1, Parent = capName })
local capSub = mk("TextLabel", { Position = UDim2.fromOffset(2, 36), Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Text = "", FontFace = DISPLAY, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 200, 80), TextTransparency = 1, ZIndex = 9, Parent = capHolder })
local capSubStroke = mk("UIStroke", { Color = Color3.fromRGB(14, 12, 18), Thickness = 2.5, Transparency = 1, Parent = capSub })
local capBar = mk("Frame", { Position = UDim2.fromOffset(-14, 4), Size = UDim2.fromOffset(6, 54), BackgroundColor3 = Color3.fromRGB(255, 176, 40), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 9, Parent = capHolder })

-- the old plate's logo and tagline step aside; the bar comes up over the tour
logoHolder.Visible = false
tagline.Visible = false
bottom.Parent = gui
bottom.ZIndex = 12
bottom.Visible = false

-- smoke, sparks: little particles in 2D
local puffs: { any } = {}
local function smokePuff(x: number, y: number, vx: number, vy: number, size: number, life: number, alpha: number)
	local img = mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1,
		Image = INTRO.smoke[math.random(1, #INTRO.smoke)], ImageColor3 = Color3.fromRGB(226, 222, 218), ImageTransparency = 1, Rotation = math.random(0, 360), ZIndex = 7, Parent = smokeLayer,
	})
	table.insert(puffs, { img = img, x = x, y = y, vx = vx, vy = vy, size = size, grow = size * 1.6, life = life, age = 0, alpha = alpha, spin = math.random(-40, 40) })
end
local sparks: { any } = {}
local function spark(x: number, y: number)
	local a = math.rad(math.random(185, 215))
	local sp = math.random(500, 900)
	local img = mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(math.random(26, 46), 8), BackgroundTransparency = 1,
		Image = INTRO.spark, ZIndex = 10, Parent = sparkLayer,
	})
	table.insert(sparks, { img = img, x = x, y = y, vx = math.cos(a) * sp, vy = math.sin(a) * sp - math.random(80, 220), age = 0, life = math.random(25, 45) / 100 })
end

-- the tour
local views: { any } = {}
local viewOrder = {}
for i = 1, #INTRO.views do viewOrder[i] = i end
-- (a view is a box of four tiles in a holder that pans; its transparency is set on all four together)
local function setA(v: Frame, a: number)
	if v:GetAttribute("A") == a then return end
	v:SetAttribute("A", a)
	for _, t in ipairs(v:GetChildren()) do
		if t:IsA("ImageLabel") then t.ImageTransparency = a end
	end
end
local function getA(v: Frame): number
	return (v:GetAttribute("A") :: number?) or 1
end
local function viewImage(i: number): Frame
	if views[i] then return views[i] end
	local holder = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.12, 1.12), BackgroundTransparency = 1, ZIndex = 3, Parent = tour })
	-- 16:9, covering the holder whatever the screen's shape
	local box = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = holder })
	local function cover()
		local hs = holder.AbsoluteSize
		if hs.X <= 0 then return end
		local w, h = hs.X, hs.X * 9 / 16
		if h < hs.Y then h, w = hs.Y, hs.Y * 16 / 9 end
		box.Size = UDim2.fromOffset(w + 2, h + 2)
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(cover)
	cover()
	for k, id in ipairs(INTRO.views[i].tiles) do
		mk("ImageLabel", {
			Position = UDim2.fromScale(((k - 1) % 2) * 0.5, ((k - 1) // 2) * 0.5), Size = UDim2.new(0.5, 1, 0.5, 1), BackgroundTransparency = 1,
			Image = id, ImageTransparency = 1, ScaleType = Enum.ScaleType.Stretch, ZIndex = 3, Parent = box,
		})
	end
	views[i] = box
	return box
end
-- each view's slow move: a drift across and a gentle push in (a different way each time)
local MOVES = { { -1, 0, 1 }, { 1, 0.3, 1 }, { 0, -1, 1 }, { -0.7, 0.7, -1 }, { 1, -0.4, 1 } }
local tourStart: number? = nil
local lastCap = -1
-- (2026-10-23, the owner: "the background images are worse ... it should be the map") the tour is the
-- lobby itself: slow camera moves over the real map, built behind the title, each one dipping through
-- black into the next. Camera from / to and what it looks at, round the plaza's centre (C), in studs.
local C = Vector3.new(-6000, 0, 6000)
local function around(r: number, deg: number, h: number): Vector3
	local a = math.rad(deg)
	return C + Vector3.new(math.cos(a) * r, h, math.sin(a) * r)
end
local LIVE = {
	{ from = around(62, 320, 14), to = around(54, 345, 18), look = around(0, 0, 26), name = "THE TROPHY PILLAR", sub = "This server's best launches" },
	{ from = around(372, 84, 24), to = around(372, 98, 26), look = around(360, 126, 4), name = "THE PARK", sub = "Ponds, kites and lost lug nuts" },
	{ from = around(560, 22, 44), to = around(620, 30, 52), look = around(1150, 34, 30), name = "THE BACKROAD", sub = "Where every run begins" },
	-- (the yards last: a new player's own is still a bare lot, so it's the ring of yards seen from above)
	{ from = around(230, 150, 120), to = around(230, 175, 110), look = around(0, 160, 0), name = "EIGHT YARDS", sub = "Upgrade yours, unlock a bigger cannon" },
	{ from = around(1250, 150, 70), to = around(1260, 160, 64), look = around(1352, 176, 64), name = "THE GRAND TRUNK", sub = "4 km out: the Highway" },
	{ from = around(1500, 290, 175), to = around(1560, 298, 185), look = around(2900, 300, 230), name = "THE THAR", sub = "12 km out: the Dunes" },
}
local liveAt: number? = nil      -- when the lobby was found built
local riseAt: number? = nil      -- when the title rose off the black (once the map is there)
local function liveReady(): boolean
	return workspace:FindFirstChild("LobbyVista") ~= nil
end

-- the art arrives first (it's small); never wait more than a few seconds for it
task.spawn(function()
	local list = { INTRO.tyre, INTRO.tyreBlur, INTRO.skid, INTRO.spark, INTRO.top.id }
	for _, s in ipairs(INTRO.smoke) do table.insert(list, s) end
	for _, L in ipairs(INTRO.letters) do table.insert(list, L.id) end
	local items = {}
	for _, id in ipairs(list) do
		local im = Instance.new("ImageLabel")
		im.Image = id
		table.insert(items, im)
	end
	pcall(function() ContentProvider:PreloadAsync(items) end)
end)

local function introFrame(dt: number)
	local t = os.clock() - introStart
	-- the screech: in from the left at speed, braking hard to dead centre
	local ENTER, STOP = 0.35, 1.75
	local u = clamp01((t - ENTER) / (STOP - ENTER))
	local e = 1 - (1 - u) ^ 3
	local x0 = -260
	local x = x0 + (TYRE_X - x0) * e
	local speed = (TYRE_X - x0) * 3 * (1 - u) ^ 2 / (STOP - ENTER)
	local bounce = 0
	if t > STOP then
		local s = t - STOP
		bounce = -18 * math.exp(-s * 6) * math.abs(math.sin(s * 11))
	end
	tyreHolder.Position = UDim2.fromOffset(x, TYRE_Y + bounce)
	-- (the squash as it lands from the bounce)
	local sq = if t > STOP then 1 - 0.08 * math.exp(-(t - STOP) * 8) * math.cos((t - STOP) * 22) ^ 2 else 1
	tyreHolder.Size = UDim2.fromOffset(TYRE_SIZE * (2 - sq), TYRE_SIZE * sq)
	tyreImg.Rotation += speed * dt / (TYRE_SIZE / 2) * (180 / math.pi) * (if u < 1 then 1 else 0)
	tyreBlur.Rotation = tyreImg.Rotation
	local blurK = clamp01(speed / 900)
	local vis = if t < ENTER then 1 else 0
	tyreBlur.ImageTransparency = math.max(vis, 1 - blurK)
	tyreImg.ImageTransparency = math.max(vis, blurK * 0.85)
	-- the skid mark grows behind it while it brakes, then stays
	local braking = t > ENTER + 0.25 and u < 1
	if t > ENTER + 0.25 then
		local startX = x0 + (TYRE_X - x0) * (1 - (1 - 0.18) ^ 3)
		skidClip.Position = UDim2.fromOffset(startX, GROUND - 14)
		skidClip.Size = UDim2.fromOffset(math.max(0, x - startX), 22)
		skid.Position = UDim2.fromOffset(-(1100 - math.max(0, x - startX)), 0)
	end
	-- smoke off the contact patch while braking (more the harder it brakes), sparks now and then
	if braking then
		local n = if speed > 500 then 2 else 1
		for _ = 1, n do
			smokePuff(x - TYRE_SIZE * 0.18 + math.random(-10, 10), GROUND - 8, -speed * 0.25 + math.random(-30, 30), -math.random(40, 120), math.random(90, 150), math.random(110, 170) / 100, 0.35)
		end
		if speed > 350 and math.random() < 0.45 then spark(x - TYRE_SIZE * 0.22, GROUND - 4) end
	end
	if t > STOP and t < STOP + 0.06 then
		for _ = 1, 6 do smokePuff(TYRE_X + math.random(-120, 60), GROUND - 10, math.random(-160, 60), -math.random(30, 90), math.random(120, 190), 1.6, 0.4) end
	end
	-- the title punches in
	local shake = 0
	for _, P in ipairs(titlePieces) do
		local a = clamp01((t - P.delay) / 0.18)
		if a > 0 then
			local s = if a < 1 then 2.3 - 1.3 * a * a else 1
			if a >= 1 then
				local q = t - P.delay - 0.18
				s = 1 - 0.16 * math.exp(-q * 12) * math.cos(q * 24) ^ 2
				if not P.landed then
					P.landed = true
					shake = math.max(shake, if P.big then 5 else 3)
					if P.delay >= LAST_LETTER then
						introFlash.BackgroundTransparency = 0.55
						tween(introFlash, 0.45, { BackgroundTransparency = 1 })
						for _ = 1, 8 do smokePuff(640 + math.random(-420, 420), 600, math.random(-120, 120), -math.random(20, 70), math.random(140, 220), 1.4, 0.3) end
					end
				end
				-- a slow ride once the whole title's in
				if t > LAST_LETTER + 0.8 then
					P.holder.Position = P.rest + UDim2.fromOffset(0, math.sin((t - LAST_LETTER) * 2 + P.rest.X.Offset / 160) * (if P.big then 4 else 3))
				end
			end
			P.scale.Scale = s
			P.img.ImageTransparency = 1 - clamp01(a * 3)
			P.holder.Rotation = (1 - a) * (if P.big then 10 else -6)
		end
	end
	stage.Position = UDim2.new(0.5, math.random(-1, 1) * shake, 0.5, math.random(-1, 1) * shake)
	-- the rise: the emblem eases to the top and shrinks; the black fades into the first view
	local RISE = LAST_LETTER + 0.95
	-- (the title holds on the black until the lobby's built behind it, then rises into the first shot;
	-- never longer than 20 s)
	if not riseAt and t >= RISE and (liveReady() or t > RISE + 20) then
		riseAt = t
		-- (the old plate and the base black step aside: the world itself shows under the tour now)
		if liveReady() then
			door.Visible = false
			black.BackgroundTransparency = 1
		end
	end
	local r = if riseAt then clamp01((t - (riseAt :: number)) / 1.2) else 0
	local re = r * r * (3 - 2 * r)
	-- (the emblem scales about its top edge: shrunk, it's already near the top; a nudge up finishes it)
	emblem.Position = UDim2.fromOffset(640, -6 * re)
	-- (2026-10-23: small enough up top that the slide's subject below it stays clear)
	emblemScale.Scale = 1 - 0.6 * re
	if r > 0 then
		introBlack.BackgroundTransparency = re
		shadeTop.BackgroundTransparency = 1 - re
		shadeBottom.BackgroundTransparency = 1 - re
		-- the smoke wipes across as the black goes
		if r < 0.6 and math.random() < 0.5 then
			smokePuff(math.random(0, 1280), math.random(360, 720), math.random(-80, 80), -math.random(30, 80), math.random(260, 420), 1.6, 0.25)
		end
		if not introRevealed then
			introRevealed = os.clock()
			tourStart = os.clock()
		end
		-- (the bar comes up once the emblem's out of its way)
		if r > 0.55 and not bottom.Visible then bottom.Visible = true end
	end
	-- the tour: the live map
	if tourStart and liveReady() then
		local tt = os.clock() - tourStart
		local cycle = HOLD + FADE
		local k = math.floor(tt / cycle)
		local inCycle = tt - k * cycle
		local cur = k % #LIVE + 1
		local nxt = (k + 1) % #LIVE + 1
		-- through the black between shots: the cut happens at the darkest point
		local dip = 0
		local shot, age = LIVE[cur], inCycle + FADE / 2
		if inCycle > HOLD then
			local f = (inCycle - HOLD) / FADE
			dip = 1 - math.abs(2 * f - 1)
			dip = dip * dip * (3 - 2 * dip)
			if f > 0.5 then shot, age = LIVE[nxt], (inCycle - HOLD) - FADE / 2 end
		end
		tour.BackgroundTransparency = 1 - dip
		local p = clamp01(age / (HOLD + FADE))
		p = p * p * (3 - 2 * p)
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = 62
		local eye = shot.from:Lerp(shot.to, p)
		cam.CFrame = CFrame.lookAt(eye, shot.look)
		-- the caption: in a beat after each shot lands, out before it goes
		local capA = clamp01((inCycle - 0.35) / 0.4) * (1 - clamp01((inCycle - HOLD + 0.3) / 0.3))
		if k ~= lastCap then
			lastCap = k
			capName.Text = LIVE[cur].name
			capSub.Text = LIVE[cur].sub
		end
		local slide = (1 - capA) * -24
		capHolder.Position = UDim2.new(0, 34 + slide, 1, -40)
		capName.TextTransparency = 1 - capA
		capNameStroke.Transparency = 1 - capA
		capSub.TextTransparency = 1 - capA
		capSubStroke.Transparency = 1 - capA
		capBar.BackgroundTransparency = 1 - capA
	end
	-- the particles
	for i = #puffs, 1, -1 do
		local p = puffs[i]
		p.age += dt
		local q = p.age / p.life
		if q >= 1 then
			p.img:Destroy()
			table.remove(puffs, i)
		else
			p.vx *= math.exp(-dt * 2.2)
			p.vy *= math.exp(-dt * 1.4)
			p.x += p.vx * dt
			p.y += p.vy * dt
			local s = p.size + (p.grow - p.size) * (1 - (1 - q) ^ 2)
			p.img.Position = UDim2.fromOffset(p.x, p.y)
			p.img.Size = UDim2.fromOffset(s, s)
			p.img.Rotation += p.spin * dt
			p.img.ImageTransparency = 1 - p.alpha * math.min(1, q * 6) * (1 - q)
		end
	end
	for i = #sparks, 1, -1 do
		local s = sparks[i]
		s.age += dt
		if s.age >= s.life then
			s.img:Destroy()
			table.remove(sparks, i)
		else
			s.vy += 1400 * dt
			s.x += s.vx * dt
			s.y += s.vy * dt
			s.img.Position = UDim2.fromOffset(s.x, s.y)
			s.img.Rotation = math.deg(math.atan2(s.vy, s.vx))
			s.img.ImageTransparency = s.age / s.life
		end
	end
end
local introConn = RunService.RenderStepped:Connect(function(dt) if introOn then introFrame(math.min(dt, 0.05)) end end)
-- (2026-10-23) its sound: the screech as the tyre brakes (Pro Sound Effects' skids, cut to the stop),
-- and a deep impact as the last letter lands
task.delay(0.42, function()
	if not introOn then return end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://9119186024"
	s.Volume = 0.65
	s.PlaybackSpeed = 1.08
	s.Parent = game:GetService("SoundService")
	s:Play()
	task.delay(1.15, function() tween(s, 0.35, { Volume = 0 }) end)
	task.delay(1.6, function() s:Destroy() end)
end)
task.delay(LAST_LETTER + 0.18, function()
	if introOn then sfx("rbxassetid://9114036511", 0.8, 0.9) end
end)
-- (the old plate's letters are hidden: nothing of theirs flashes or thumps)
onImpact = nil

-- a new tip every few seconds
task.spawn(function()
	local i = math.random(1, #TIPS)
	task.wait(ENTRANCE + 4)
	while gui.Parent and door.Visible do
		tween(tip, 0.25, { TextTransparency = 1 })
		task.wait(0.25)
		i = i % #TIPS + 1
		tip.Text = TIPS[i]
		tween(tip, 0.25, { TextTransparency = 0 })
		task.wait(4.5)
	end
end)

--==============================================================
-- load
--==============================================================
if not game:IsLoaded() then game.Loaded:Wait() end
ownDone[1] = 1
mark("game loaded")

local Root = ReplicatedStorage:WaitForChild("TyreCannon", 60)
if Root then
	local remotes = Root:WaitForChild("Remotes", 30)
	local req = remotes and remotes:WaitForChild("RequestProfile", 30)
	if req then pcall(function() (req :: RemoteFunction):InvokeServer() end) end
end
ownDone[2] = 1
mark("save fetched")

-- the loading scene, built behind the plate once the game's scripts are in; then the plate
-- dissolves to show it, the logo rises to the top and the bar stays at the bottom
local scene: any = nil
local sceneShownAt: number? = nil
local finishedLoading = false
task.delay(9, function()
	if not sceneShownAt and not logoStart then logoStart = os.clock() end
end)
local shades: { Frame } = {}
local function reveal()
	-- the logo, the tagline and the bar come out of the plate so they stay when it goes
	for _, o in ipairs({ logoHolder, bottom } :: { GuiObject }) do o.Parent = gui end
	tagline.Visible = false
	-- a soft darkening at the top and bottom, so the logo and the bar read over the sky and the road
	for _, top in ipairs({ true, false }) do
		local f = mk("Frame", {
			AnchorPoint = Vector2.new(0, if top then 0 else 1), Position = UDim2.fromScale(0, if top then 0 else 1),
			Size = UDim2.fromScale(1, if top then 0.36 else 0.34), BackgroundColor3 = Color3.fromRGB(8, 8, 12), BackgroundTransparency = 1,
			BorderSizePixel = 0, ZIndex = 4, Parent = gui,
		})
		mk("UIGradient", {
			Rotation = if top then 90 else -90,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }), Parent = f,
		})
		tween(f, 0.9, { BackgroundTransparency = 0 })
		table.insert(shades, f)
	end
	if logoStart then
		-- (the logo already played on the plate: it rises out of the way)
		local from = logoRest
		local t1 = os.clock()
		task.spawn(function()
			while os.clock() - t1 < 0.9 do
				logoRest = from:Lerp(UDim2.fromScale(0.5, 0.16), easeOut((os.clock() - t1) / 0.9))
				RunService.RenderStepped:Wait()
			end
			logoRest = UDim2.fromScale(0.5, 0.16)
		end)
	else
		-- the tyre comes in, and the logo lands as it arrives
		logoRest = UDim2.fromScale(0.5, 0.16)
		logoStart = os.clock() + 0.95
		pcall(function() scene:intro() end)
		sfx("rbxassetid://9114346802", 0.7, 0.85)
	end
	tween(door, 0.7, { GroupTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	tween(black, 0.9, { BackgroundTransparency = 1 })
	sceneShownAt = os.clock()
	mark("scene shown")
end
task.spawn(function()
	if introOn then return end -- (2026-10-22: the intro's tour replaces the live scene)
	local ok, err = pcall(function()
		local folder = player:WaitForChild("PlayerScripts"):WaitForChild("TyreCannonClient", 20)
		local mod = folder and folder:WaitForChild("LoadScene", 10)
		if mod then scene = (require(mod :: ModuleScript) :: any).new(playerGui) end
	end)
	if not ok then warn("[TyreCannon] loading scene: " .. tostring(err)) end
	if not scene then
		mark("no scene")
		-- no scene: the logo plays on the plate
		if not logoStart then logoStart = os.clock() end
		return
	end
		scene:start()
	mark("scene built")
	-- (the plate stays over it until everything it shows has arrived and been drawn: no land or
	-- props popping in)
	pcall(function() scene:prepare(10) end)
	mark("scene ready")
	while os.clock() - entranceStart < 0.6 do task.wait(0.05) end
	if not finishedLoading then reveal() end
end)

-- the bar reaches the end only when Preload has really finished every stage; TyreReady follows it
local t0 = os.clock()
while not (finished and playerGui:GetAttribute("TyreReady")) and os.clock() - t0 < 90 do
	task.wait(0.05)
end
local char = player.Character or player.CharacterAdded:Wait()
char:WaitForChild("HumanoidRootPart", 20)
mark("yard ready")
local withScene = scene ~= nil and sceneShownAt ~= nil
finishedLoading = true
if introOn then
	-- the intro plays through, and the tour shows at least one whole view, however fast the load
	while not introRevealed or os.clock() - (introRevealed :: number) < 5.6 do task.wait(0.05) end
end
if withScene then
	-- the whole intro plays and the tyre gets a moment in slow motion, however fast the load was
	while os.clock() - (sceneShownAt :: number) < 8 do task.wait(0.05) end
end
task.wait(0.25)
rollConn:Disconnect()
door.Position = UDim2.fromScale(0, 0)
status.Text = "GO"

local veil: Frame? = nil
local blur: BlurEffect? = nil
if introOn then
	--==============================================================
	-- the intro's way out: the view pushes in, the emblem lifts away, the bar drops, the screen
	-- washes to the sky's colour and the camera glides down behind you
	--==============================================================
	tween(bottom, 0.4, { Position = bottom.Position + UDim2.fromOffset(0, 220) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(emblem, 0.5, { Position = UDim2.fromOffset(640, -700) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(capHolder, 0.35, { Position = UDim2.new(0, -560, 1, -40) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- (the live shot pushes in as the veil comes up)
	do
		local cam = workspace.CurrentCamera
		local cf = cam.CFrame
		tween(cam, 0.9, { CFrame = cf * CFrame.new(0, 0, -40), FieldOfView = 54 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	veil = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(168, 184, 204), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 60, Parent = gui })
	task.wait(0.3)
	tween(veil :: Frame, 0.55, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	task.wait(0.6)
	introOn = false
	introConn:Disconnect()
	for _, o in ipairs({ tour, introBlack, stage, shadeTop, shadeBottom, introFlash, capHolder } :: { Instance }) do o:Destroy() end
	door.Visible = false
	black.BackgroundTransparency = 1
	if scene then pcall(function() scene:destroy() end) end
elseif withScene then
	--==============================================================
	-- the tyre takes off down the road; the screen washes over to the yard
	--==============================================================
	tween(bottom, 0.4, { Position = bottom.Position + UDim2.fromOffset(0, 220) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(logoHolder, 0.45, { Position = UDim2.fromScale(0.5, -0.3) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		-- the tyre goes; as it's lost in the haze the picture softens (a blur) and dissolves into the
	-- sky's own colour, never a flash
	blur = Instance.new("BlurEffect")
	;(blur :: BlurEffect).Size = 0
	;(blur :: BlurEffect).Parent = workspace.CurrentCamera
	veil = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(168, 184, 204), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 60, Parent = gui })
	task.delay(1.15, function()
		tween(blur :: BlurEffect, 0.6, { Size = 22 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		tween(veil :: Frame, 0.6, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		for _, f in ipairs(shades) do tween(f, 0.5, { BackgroundTransparency = 1 }) end
	end)
	pcall(function() scene:exit() end)
	task.wait(0.05)
	pcall(function() scene:destroy() end)
	for _, f in ipairs(shades) do f:Destroy() end
else
	--==============================================================
	-- no scene: the tyre drives off, and the plate goes with it, straight into the game
	--==============================================================
	local screen = gui.AbsoluteSize
	-- the tyre's screen position, so it can leave the bar and cross the whole screen
	local from = roller.AbsolutePosition + roller.AbsoluteSize / 2
	local big = mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(from.X, from.Y), Size = UDim2.fromOffset(roller.AbsoluteSize.X, roller.AbsoluteSize.Y),
		BackgroundTransparency = 1, Image = TYRE, ZIndex = 30, Parent = gui,
	})
	roller.Visible = false
	local startSize = roller.AbsoluteSize.X
	local endSize = math.max(screen.Y * 0.34, 160)
	local groundY = from.Y
	local x, vx, rot = from.X, 120, 0
	local timeOff = 0
	local lastPuff = 0
	local plateOut = false
	while x < screen.X + endSize do
		local dt = RunService.RenderStepped:Wait()
		timeOff += dt
		vx += (1500 + timeOff * 2600) * dt
		x += vx * dt
		local k = clamp01((x - from.X) / (screen.X * 0.9))
		local size = startSize + (endSize - startSize) * easeOut(k)
		-- the tyre sits on the same ground line, a little bigger as it comes toward you
		local y = groundY - (size - startSize) * 0.12 - math.abs(math.sin(timeOff * 14)) * 5 * (1 - k)
		rot += vx / math.max(size / 2, 1) * dt * (180 / math.pi)
		big.Position = UDim2.fromOffset(x, y)
		big.Size = UDim2.fromOffset(size, size)
		big.Rotation = rot
		if timeOff - lastPuff > 0.045 and x < screen.X then
			lastPuff = timeOff
			puff(x - size * 0.35, y + size * 0.45, 2, 16)
		end
		-- the plate fades once the tyre is across the middle of the screen
		if not plateOut and x > screen.X * 0.45 then
			plateOut = true
			tween(door, 0.55, { GroupTransparency = 1 })
			tween(black, 0.5, { BackgroundTransparency = 1 })
		end
	end
	big:Destroy()
	if scene then pcall(function() scene:destroy() end) end
end

-- hand the world over: the camera behind the character, the menus back
do
	local cam = workspace.CurrentCamera
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local back = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
		back = back.Magnitude > 0.01 and back.Unit or Vector3.new(0, 0, -1)
		local rest = CFrame.lookAt(hrp.Position - back * 16 + Vector3.new(0, 7, 0), hrp.Position + Vector3.new(0, 1.5, 0))
			if veil then
			-- the haze clears on a high shot over the yard, already moving, and the camera glides
			-- down behind you (the blur eases off as it comes)
			local high = CFrame.lookAt(hrp.Position - back * 70 + Vector3.new(18, 54, 0), hrp.Position + back * 8)
			cam.CameraType = Enum.CameraType.Scriptable
			cam.FieldOfView = 70
			cam.CFrame = high
			tween(veil, 0.9, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			if blur then tween(blur, 1.1, { Size = 0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out) end
			local t1 = os.clock()
			local GLIDE = 2.8
			while true do
				local k = clamp01((os.clock() - t1) / GLIDE)
				-- (moving from the first frame, settling gently at the end)
				local e = 1 - (1 - k) ^ 3
				cam.CFrame = high:Lerp(rest, e)
				if k >= 1 then break end
				RunService.RenderStepped:Wait()
			end
		end
		if blur then blur:Destroy() end
		cam.CFrame = rest
	end
	cam.CameraType = Enum.CameraType.Custom
	if hum then cam.CameraSubject = hum end
end
if blur then blur:Destroy() end
mark("done")
playerGui:SetAttribute("IntroPlaying", false)
task.delay(0.8, function() gui:Destroy() end)
