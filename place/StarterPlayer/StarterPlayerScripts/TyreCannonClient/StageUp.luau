--!strict
-- TYRE CANNON :: StageUp
-- The plot upgrade, as a scene. You press Upgrade; the menus go, the camera swings in low on your
-- yard and the old stage shakes and drops through the ground (PlotStage:demolish), then the new one
-- is built up out of the ground piece by piece with dust and thuds (PlotStage:rise) while the camera
-- swings up and back to show the whole yard, then the stage's name lands on the screen with what it
-- brings, and the camera comes home.
--   StageUp.new(gui, hooks) · :play(plot, startServer) -> boolean
--     hooks.hideHub() / hooks.showHub() / hooks.restoreCamera()
--   startServer() runs the purchase (returns the server's answer): the scene starts first so the
--   camera is already moving when the yard changes; a refusal puts everything back at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local Kit = require(script.Parent.Kit)
local Sound = require(script.Parent.Sound)
local C = Kit.C

local StageUp = {}
StageUp.__index = StageUp

-- what each stage brings, for the end card
StageUp.BRINGS = {
	[2] = { "Gravel yard, chain-link fence", "A rusted shed on the street", "The Steel Mortar cannon" },
	[3] = { "Concrete yard and street lamps", "Your own garage, name over the door", "The Air Cannon" },
	[4] = { "Painted lanes, green palisade", "A gantry hoist and tyre racks", "The Howitzer" },
	[5] = { "A hazard-marked launch lane", "Floodlight masts", "The Mag Rail" },
}

function StageUp.new(gui: ScreenGui, plotStage, hooks)
	local self = setmetatable({}, StageUp)
	self.gui = gui
	self.plotStage = plotStage
	self.hooks = hooks
	self.playing = false
	return self
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- the yard's own frame: +X runs out from the street down the launch lane, the floor is x -34..74,
-- z -39..39, its top at y 2
local function shot(base: CFrame, k: number): (CFrame, number)
	-- k 0..1: low on the old yard from the street side, then up and back, ending high on the whole yard
	local s = smooth(k)
	local from = Vector3.new(-62, 9, -46)
	local to = Vector3.new(-58, 46, 74)
	local look0 = Vector3.new(14, 6, 0)
	local look1 = Vector3.new(18, 8, 0)
	local pos = from:Lerp(to, s)
	-- a gentle sweep round the front of the yard in between
	pos += Vector3.new(0, 0, 0) + Vector3.new(math.sin(s * math.pi) * -22, math.sin(s * math.pi) * 6, 0)
	local look = look0:Lerp(look1, s)
	return CFrame.lookAt(base:PointToWorldSpace(pos), base:PointToWorldSpace(look)), 62 + 12 * s
end

function StageUp:play(plot: Instance, startServer: () -> any): boolean
	if self.playing then return false end
	local base = plot:GetAttribute("BaseCFrame") :: CFrame?
	if not base then return false end
	self.playing = true
	local cam = workspace.CurrentCamera
	local hooks = self.hooks
	hooks.hideHub()
	cam.CameraType = Enum.CameraType.Scriptable
	local c0, f0 = shot(base, 0)
	cam.CFrame = c0
	cam.FieldOfView = f0
	-- the camera moves from here on; the purchase answers in the background
	local t = 0
	local answered, ok, res = false, false, nil
	self.plotStage:expect(plot)
	task.spawn(function()
		local good, got = pcall(startServer)
		answered = true
		ok = good and type(got) == "table" and got.ok == true
		res = got
	end)
	local DURATION = 5.2
	local shown = { building = false, card = false }
	local conn
	local done = false
	conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		local k = math.clamp(t / DURATION, 0, 1)
		-- refused? back out at once
		if answered and not ok then
			conn:Disconnect()
			done = true
			return
		end
		local cf, fov = shot(base, k)
		local shake = 0
		if t > 0.5 and t < 1.5 then shake = (1 - math.abs(t - 1.0) / 0.5) * 0.9 end
		cam.CFrame = cf * CFrame.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0)
		cam.FieldOfView = fov
		if not shown.building and t > 1.2 then
			shown.building = true
			Sound.play("land", { volume = 0.9, pitch = 0.7 })
		end
		if not shown.card and t > 3.4 then
			shown.card = true
			local tier = (plot:GetAttribute("V2_Tier") :: number?) or 2
			local name = Game.Tiers[math.clamp(tier, 1, #Game.Tiers)].name
			Kit.callout(self.gui, "STAGE UP!", C.accent, UDim2.fromScale(0.5, 0.2), 78)
			task.delay(0.35, function() Kit.callout(self.gui, string.upper(name), C.white, UDim2.fromScale(0.5, 0.31), 52) end)
			local mult = math.floor(Game.stageCash(tier - 1) + 0.5)
			task.delay(0.8, function() Kit.callout(self.gui, ("CASH x%d"):format(mult), C.gold, UDim2.fromScale(0.5, 0.4), 40) end)
		end
		if t >= DURATION + 1.4 then
			conn:Disconnect()
			done = true
		end
	end)
	while not done do task.wait(0.05) end
	hooks.restoreCamera()
	hooks.showHub()
	self.playing = false
	if not ok and answered then
		self.plotStage:cancelExpect(plot)
		return false, res
	end
	return true, res
end

return StageUp
