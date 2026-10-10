--!strict
-- TYRE CANNON :: LaunchTap (Rev & Shift)
-- The launch: the cannon revs through three gears on the rev gauge (the speedo's housing, its shift
-- zone painted on). Each gear the segments climb; tap (click, Space, A) in the zone to shift up:
--   gold (two segments)  PERFECT      green round it  GOOD
--   below the green      EARLY        into the red / the limiter  OVER-REV
-- Each gear climbs faster than the last. The three shifts grade the launch:
--   all three perfect PERFECT, 4-5 points GREAT, 2-3 GOOD, less WEAK   (perfect 2, good 1)
--   LaunchTap.run(gui, auto, onShift) -> grade, ratings
--   onShift(gear, rating) fires on every shift, so the cutscene can build with the launch
-- Grades and what they pay (Main): LaunchTap.Grades[grade] = { push, show, nitro }

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Gauge = require(script.Parent.Gauge)
local C = Kit.C

local LaunchTap = {}

-- the zones in segments (art/ui/hud_gauges.py PERFECT, GOOD, OVER), a little forgiveness on PERFECT
local N = Gauge.N
local GOOD_FROM, PERF_FROM, PERF_TO, GOOD_TO = 21 / N, 23.7 / N, 26.3 / N, 27 / N
local GEAR_TIME = { 1.3, 1.08, 0.9 }		-- seconds from the drop to the limiter
local DROP = 0.18							-- where the revs fall to after a shift

LaunchTap.Grades = {
	perfect = { push = 1.45, show = 1.0, nitro = 1.6, label = "PERFECT LAUNCH!", color = C.yellow },
	great = { push = 1.2, show = 0.85, nitro = 0, label = "GREAT LAUNCH!", color = C.green },
	good = { push = 1.0, show = 0.6, nitro = 0, label = "GOOD LAUNCH", color = C.white },
	weak = { push = 0.85, show = 0.3, nitro = 0, label = "WEAK LAUNCH", color = C.red },
}
LaunchTap.Art = Gauge.Art

local RATING = {
	perfect = { text = "PERFECT", color = Color3.fromRGB(255, 214, 92), pts = 2 },
	good = { text = "GOOD", color = Color3.fromRGB(86, 232, 122), pts = 1 },
	early = { text = "EARLY", color = Color3.fromRGB(150, 196, 255), pts = 0 },
	over = { text = "OVER-REV", color = Color3.fromRGB(255, 84, 72), pts = 0 },
}
LaunchTap.Rating = RATING

local function rate(u: number): string
	if u >= PERF_FROM and u <= PERF_TO then return "perfect" end
	if u >= GOOD_FROM and u < GOOD_TO then return "good" end
	if u < GOOD_FROM then return "early" end
	return "over"
end

-- a lit segment's colour: the zone it sits in
local function zoneColour(i: number, _n: number): Color3
	if i == 24 or i == 25 then return RATING.perfect.color end
	if i >= 21 and i <= 26 then return RATING.good.color end
	if i >= 27 then return RATING.over.color end
	return Color3.fromRGB(232, 238, 255)
end

-- the rev bar: N slanted segments rising left to right on a tilted strip, the shift zones painted
-- on the unlit ones (faint green, gold for PERFECT, red past it) so you can see where to shift;
-- lit, each takes its zone's colour. Same language as the run's speed bar.
local ITALIC = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local function revBar(parent: Instance, width: number)
	local bar = {}
	local strip = UI.mk("Frame", { Name = "Revs", Size = UDim2.fromOffset(width, 74), BackgroundTransparency = 1, Rotation = -6, Parent = parent })
	local back = UI.mk("Frame", { Position = UDim2.fromOffset(-12, -10), Size = UDim2.new(1, 24, 1, 20), BackgroundTransparency = 1, Parent = strip })
	Kit.slice("panel_body", nil, back, 1, 0.4)
	Kit.slice("panel_ring", C.accent, back, 2, 0.4)
	bar.ring = back:FindFirstChild("panel_ring") :: ImageLabel
	local segs = {}
	local gap = 3
	local w = (width - gap * (N - 1)) / N
	for i = 1, N do
		local h = 18 + 44 * (i / N) ^ 1.3
		local unlit = zoneColour(i, N)
		local base = (i >= 21) and unlit:Lerp(Color3.fromRGB(20, 20, 24), 0.72) or Color3.fromRGB(38, 38, 44)
		local seg = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, (i - 1) * (w + gap), 1, -4), Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = base, BorderSizePixel = 0, ZIndex = 4, Parent = strip,
		}, { UI.corner(3) })
		segs[i] = { frame = seg, base = base }
	end
	bar.segs = segs
	bar.root = strip
	function bar:set(u: number, colourOf: (number, number) -> Color3)
		local lit = u * N
		for i, sg in ipairs(segs) do
			local k = math.clamp(lit - (i - 1), 0, 1)
			sg.frame.BackgroundColor3 = if k > 0 then sg.base:Lerp(colourOf(i, N), 0.35 + 0.65 * k) else sg.base
		end
	end
	return bar
end

function LaunchTap.run(gui: ScreenGui, auto: boolean?, onShift: ((number, string) -> ())?): (string, { string })
	local W = 520
	local root = UI.mk("Frame", {
		Name = "LaunchTap", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(W + 150, 170), BackgroundTransparency = 1, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	local gauge = revBar(root, W)
	gauge.root.Position = UDim2.fromOffset(140, 40)
	local face = gauge.root
	-- the gear, big and italic, left of the bar
	local gearLabel = Kit.text("GEAR", 14, C.muted, 1.5, Kit.Body)
	gearLabel.Position = UDim2.fromOffset(18, 30)
	gearLabel.Size = UDim2.fromOffset(100, 16)
	gearLabel.Parent = root
	local gearText = Kit.text("1", 78, C.white, 3.5, ITALIC)
	gearText.Position = UDim2.fromOffset(10, 42)
	gearText.Size = UDim2.fromOffset(110, 84)
	gearText.Parent = root
	-- three pips under the gear: one per shift, lit in its rating's colour
	local pips = {}
	for g = 1, 3 do
		pips[g] = UI.mk("Frame", {
			Position = UDim2.fromOffset(22 + (g - 1) * 30, 128), Size = UDim2.fromOffset(24, 12), BackgroundColor3 = Color3.fromRGB(56, 54, 66),
			BorderSizePixel = 0, Parent = root,
		}, { UI.corner(4) })
		UI.stroke(C.ink, 2, 0).Parent = pips[g]
	end
	-- how to shift, on a counter plate under the bar
	local how = UserInputService.TouchEnabled and "Tap" or (UserInputService.GamepadEnabled and "Press A" or "Click or Space")
	local chip = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0, 140 + W / 2, 1, 0), Size = UDim2.fromOffset(280, 34),
		BackgroundTransparency = 1, ZIndex = 6, Parent = root,
	})
	Kit.slice("counter", nil, chip, 6, 34 / Kit.Art.counter.h)
	local label = Kit.text(how .. " in the <font color=\"#FFD65C\">gold</font> to shift", 16, C.white, 2)
	label.Size = UDim2.new(1, -24, 1, -6)
	label.Position = UDim2.fromOffset(12, 3)
	Kit.fit(label, 16)
	label.ZIndex = 7
	label.Parent = chip
	Kit.appear(root, 0, 60)
	local D = W

	local tapped = false
	ContextActionService:BindActionAtPriority("TC_Fire", function(_, state)
		if state == Enum.UserInputState.Begin then tapped = true end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch)

	local ratings: { string } = {}
	local u = DROP
	for gear = 1, 3 do
		gearText.Text = tostring(gear)
		Kit.pop(gearText, 1.25, 0.2)
		tapped = false
		local t = 0
		local T = GEAR_TIME[gear]
		-- the auto launcher shifts somewhere in the zone, now and then perfectly
		local autoAt = auto and (math.random() < 0.45 and (PERF_FROM + PERF_TO) / 2 or GOOD_FROM + math.random() * (PERF_FROM - GOOD_FROM)) or nil
		local limiter = nil :: number?
		local result: string? = nil
		while not result do
			local dt = RunService.RenderStepped:Wait()
			t += dt
			if limiter then
				-- bouncing off the limiter: the top segments flicker, then the gear's gone
				u = 1 - (math.sin((os.clock() - limiter) * 60) * 0.5 + 0.5) * 0.06
				if os.clock() - limiter > 0.28 then result = "over" end
			else
				local x = math.clamp(t / T, 0, 1)
				u = DROP + (1 - DROP) * x ^ 1.12
				if x >= 1 then limiter = os.clock() end
			end
			if autoAt and not limiter and u >= autoAt then tapped = true end
			if tapped and not result then result = if limiter then "over" else rate(u) end
			gauge:set(u, zoneColour)
		end
		local r = result :: string
		table.insert(ratings, r)
		local look = RATING[r]
		pips[gear].BackgroundColor3 = look.color
		gauge.ring.ImageColor3 = look.color
		Kit.pop(pips[gear], 1.6, 0.25)
		Kit.callout(gui, look.text, look.color, UDim2.new(0.5, 0, 1, -220), r == "perfect" and 40 or 32)
		Kit.shake(face, r == "perfect" and 8 or 4, 0.18)
		if r == "perfect" then Kit.pop(face, 1.08, 0.2) end
		if onShift then task.spawn(onShift, gear, r) end
		-- the revs drop as the next gear bites
		if gear < 3 then
			local from = u
			local t0 = os.clock()
			while os.clock() - t0 < 0.16 do
				local k = (os.clock() - t0) / 0.16
				gauge:set(from + (DROP - from) * (1 - (1 - k) ^ 2), zoneColour)
				RunService.RenderStepped:Wait()
			end
		end
	end
	ContextActionService:UnbindAction("TC_Fire")

	local pts = 0
	for _, r in ipairs(ratings) do pts += RATING[r].pts end
	local grade = if pts >= 6 then "perfect" elseif pts >= 4 then "great" elseif pts >= 2 then "good" else "weak"
	local G = LaunchTap.Grades[grade]
	Kit.callout(gui, G.label, G.color, UDim2.new(0.5, 0, 1, -290), grade == "perfect" and 58 or 46)
	local _ = D
	task.delay(0.35, function()
		Kit.vanish(root, 0.18, function() root:Destroy() end)
	end)
	return grade, ratings
end

return LaunchTap
