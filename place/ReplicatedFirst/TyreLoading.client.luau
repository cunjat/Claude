--!strict
-- TYRE CANNON :: Loading (ReplicatedFirst)
-- The loading plate: a grey, scratched steel plate (art/ui/ps/intro.jsx, made in Photoshop). The
-- three words of the logo come in one after another (UNTITLED slides in, TYRE drops and lands with a
-- shake and a puff of dust, GAME pops up), then the tyre rolls onto the bar, and the bar fills one
-- step at a time: waking up, fetching your save, then each of Preload's stages. Every step stays on
-- screen a moment even when it loads instantly, so the bar glides instead of jumping, and it never
-- lifts before 100%. When it's full the tyre drives off the screen and the plate goes with it,
-- straight into the game: no title, no cannon.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

-- the plate's art. The ids are filled in by tools/apply_ids.py after the images are uploaded
local ART = {
	bg = "rbxassetid://89257500947701",       -- loading_bg.png
	untitled = { id = "rbxassetid://131747573380630", w = 817, h = 146 },
	tyre = { id = "rbxassetid://83705757823133", w = 808, h = 273 },
	game = { id = "rbxassetid://85510895823582", w = 965, h = 279 },
}
local TYRE = "rbxassetid://126515425222861" -- the game tyre, face-on (the icon studio's)
local TIPS = {
	"Hills are your speed. Tuck on the way down, leave the crest, land on the slope.",
	"Crates open with keys. Grab them off the road.",
	"Five copies of a tyre fuse into a Gold one.",
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
local MIN_STEP = 0.5       -- seconds every step stays on screen, however fast it really was
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
		Image = w.id, ScaleType = Enum.ScaleType.Fit, ImageTransparency = 1, ZIndex = 6, Parent = holder,
	})
	return holder, img
end
local wUntitled, iUntitled = word(ART.untitled, (LOGO_W - uw) / 2, 0, uw, uh)
local wTyre, iTyre = word(ART.tyre, rowX, uh + 10, tw_, th)
local wGame, iGame = word(ART.game, rowX + tw_ + gap, uh + 10, gw, gh)
local restUntitled, restTyre = wUntitled.Position, wTyre.Position
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
local status = mk("TextLabel", {
	Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(420, 24), BackgroundTransparency = 1,
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
	local base = wTyre.AbsolutePosition + Vector2.new(wTyre.AbsoluteSize.X / 2, wTyre.AbsoluteSize.Y)
	puff(base.X, base.Y, 12, math.floor(wTyre.AbsoluteSize.X * 0.45))
end
-- the plate's own art first, so it's never shown half-drawn
pcall(function() ContentProvider:PreloadAsync({ doorImg, iUntitled, iTyre, iGame, roller, status }) end)

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
	local shake = t > land and 5 * math.exp(-(t - land) * 10) or 0
	door.Position = UDim2.fromOffset(math.sin(t * 70) * shake, math.cos(t * 55) * shake * 0.6)
	if t > 1.3 then
		-- idle: the words rock a hair out of step with each other
		local sw = t - 1.3
		iUntitled.Rotation = math.sin(sw * 1.7) * 0.7
		iTyre.Rotation = math.sin(sw * 1.7 + 1.2) * 0.9
		iGame.Rotation = math.sin(sw * 1.7 + 2.4) * 0.9
	end
	local tg = easeOut(clamp01((t - 1.0) / 0.35))
	tagline.TextTransparency = 1 - tg
	local tgs = tagline:FindFirstChildOfClass("UIStroke")
	if tgs then tgs.Transparency = 1 - tg * 0.85 end
	tagline.Position = taglineRest + UDim2.fromOffset(0, 10 * (1 - tg))
	local ui = easeOut(clamp01((t - 1.05) / 0.35))
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
		status.Text = finished and "READY" or labelFor(stepNames[current] or "LOADING")
	end

	-- the fill grows; the tyre rolls to the end of it
	fillClip.Size = UDim2.new(0, (BAR_W - 6) * shown, 1, -6)
	local rollIn = easeOut(clamp01((t - 0.7) / 0.7))
	local x = barLeft + BAR_W * shown
	local startX = -120
	local rx = startX + (x - startX) * rollIn
	roller.Position = UDim2.fromOffset(rx, 60 - math.abs(math.sin(rollIn * math.pi * 2)) * 10 * (1 - rollIn))
	roller.Rotation = (rx - startX) / 26 * (180 / math.pi)
	roller.ImageTransparency = 1 - clamp01((t - 0.7) / 0.15)
	pct.Text = math.floor(shown * 100 + 0.5) .. "%"
end)
task.delay(0.62, landingDust)

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

-- the bar reaches the end only when Preload has really finished every stage; TyreReady follows it
local t0 = os.clock()
while not (finished and playerGui:GetAttribute("TyreReady")) and os.clock() - t0 < 90 do
	task.wait(0.05)
end
local char = player.Character or player.CharacterAdded:Wait()
char:WaitForChild("HumanoidRootPart", 20)
mark("yard ready")
task.wait(0.35)
rollConn:Disconnect()
door.Position = UDim2.fromScale(0, 0)

--==============================================================
-- the tyre drives off, and the plate goes with it: straight into the game
--==============================================================
do
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
	status.Text = "GO"
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
end

-- hand the world over: the camera behind the character, the menus back
do
	local cam = workspace.CurrentCamera
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local back = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
		back = back.Magnitude > 0.01 and back.Unit or Vector3.new(0, 0, -1)
		cam.CFrame = CFrame.lookAt(hrp.Position - back * 16 + Vector3.new(0, 7, 0), hrp.Position + Vector3.new(0, 1.5, 0))
	end
	cam.CameraType = Enum.CameraType.Custom
	if hum then cam.CameraSubject = hum end
end
mark("done")
playerGui:SetAttribute("IntroPlaying", false)
task.delay(0.8, function() gui:Destroy() end)
