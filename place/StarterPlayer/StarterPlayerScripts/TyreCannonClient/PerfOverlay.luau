--!strict
-- TYRE CANNON :: PerfOverlay
-- Frame time, frames per second and memory in the bottom-left corner, for anyone who
-- turns it on in Settings. Updates twice a second; the frame time turns amber past
-- 30 fps and red past 20.

local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Prefs = require(script.Parent.Prefs)
local T = UI.Theme

local PerfOverlay = {}

function PerfOverlay.start(gui: ScreenGui)
	local box = UI.mk("Frame", {
		Name = "Perf", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(236, 30),
		BackgroundTransparency = 1, Visible = false, ZIndex = 90, Parent = gui,
	})
	Kit.slice("counter", nil, box, 90, 30 / Kit.Art.counter.h)
	local label = Kit.text("", 13, Color3.new(1, 1, 1), 1.5, Kit.Body)
	label.Size = UDim2.new(1, -16, 1, -4)
	label.Position = UDim2.fromOffset(8, 2)
	label.RichText = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 91
	label.Parent = box
	UI.tooltip(box, "Frame time is how long each frame takes to draw. Under 16.7 ms is a smooth 60 fps. Memory is what the game is using on this device.")

	local frames, acc, worst = 0, 0, 0
	RunService.RenderStepped:Connect(function(dt)
		if not box.Visible then return end
		frames += 1
		acc += dt
		worst = math.max(worst, dt)
		if acc < 0.5 then return end
		local avg = acc / frames
		local ms = avg * 1000
		local color = ms <= 34 and (ms <= 20 and T.good or T.warn) or T.bad
		if ms > 50 then color = T.bad end
		local mem = 0
		pcall(function() mem = Stats:GetTotalMemoryUsageMb() end)
		label.Text = ('<font color="%s">%.1f MS</font>   %d FPS   %s MB'):format(UI.hex(color), ms, math.floor(1 / avg + 0.5), UI.comma(math.floor(mem)))
		frames, acc, worst = 0, 0, 0
	end)
	Prefs.watch("perf", function(v) box.Visible = v == true end)
end

return PerfOverlay
