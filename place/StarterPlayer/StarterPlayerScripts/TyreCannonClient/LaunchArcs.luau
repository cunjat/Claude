--!strict
-- TYRE CANNON :: LaunchArcs (v3)
-- The server you can see: whenever anyone fires (a run's launch, or a yard's auto-cannon), every
-- player sees a tyre leave that yard's cannon with a boom and a smoke ring, arc out high over the
-- lobby trailing smoke, and drop out of sight beyond the wall. Your own run's launch is the
-- cutscene, so it isn't drawn twice; your own auto-cannon also shows what it paid.
--   LaunchArcs.start(remotes, plot2, hub)   (hub:toast for the auto-cannon's pay)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Game = require(Modules.Game)
local TyreLook = require(script.Parent.TyreLook)
local PackFX = require(script.Parent.PackFX)
local Sound = require(script.Parent.Sound)

local LaunchArcs = {}
-- the yards' workers (CannonWorker), set by Main: a shot waits for its worker to press the button
LaunchArcs.workers = nil :: any

local GRAVITY = Vector3.new(0, -140, 0)
local LIFE = 4.2
local live = 0

local function plotByIndex(i: number?): Instance?
	if not i then return nil end
	local lobby = workspace:FindFirstChild("Lobby")
	local plots = lobby and lobby:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot" .. i) or nil
end

-- where a yard's cannon fires from, and which way: its machine model's top front, down its lane
local function muzzleOf(plot: Instance, plot2): (Vector3?, Vector3?)
	local base = plot:GetAttribute("BaseCFrame")
	if typeof(base) ~= "CFrame" then return nil, nil end
	local layout = Game.yardDecode(plot:GetAttribute("V2_Layout") :: string?)
	local spot = base * Game.yardSpot(layout, "cannon")
	local dir = spot.RightVector
	local cannon = plot2 and plot2:cannonOf(plot)
	if cannon then
		local cf, size = cannon:GetBoundingBox()
		return cf.Position + Vector3.new(0, size.Y * 0.45, 0) + dir * size.X * 0.3, dir
	end
	return spot.Position + Vector3.new(0, 14, 0) + dir * 12, dir
end

function LaunchArcs.fire(plot: Instance, plot2, small: boolean?)
	-- a busy server never stacks up more than a handful of these
	if live >= 6 then return end
	local from, dir = muzzleOf(plot, plot2)
	if not from or not dir then return end
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - from).Magnitude > 900 then return end
	live += 1
	local d = (dir :: Vector3) * Vector3.new(1, 0, 1)
	d = d.Magnitude > 0.01 and d.Unit or Vector3.new(1, 0, 0)
	local speed = small and 150 or 210
	local vel = d * speed + Vector3.new(0, small and 120 or 165, 0)
	local tyre = TyreLook.model("baldspare", small and 4.5 or 6, "ArcTyre")
	for _, p in ipairs(tyre:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	tyre.Parent = workspace
	-- the boom
	PackFX.burst("dustRing", CFrame.new(from), small and 10 or 18, Color3.fromRGB(210, 206, 198), small and 1.2 or 1.8)
	Sound.play("land", { volume = small and 0.35 or 0.6, pitch = 0.7 })
	-- the smoke trail
	local root = tyre.PrimaryPart or tyre:FindFirstChildWhichIsA("BasePart")
	if root then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 1.5, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -1.5, 0)
		a1.Parent = root
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Lifetime = 0.8
		trail.Color = ColorSequence.new(Color3.fromRGB(230, 226, 220))
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new(1, 2.5)
		trail.FaceCamera = true
		trail.Parent = root
	end
	local pos = from
	local spin = 0
	local t = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		vel += GRAVITY * dt
		pos += vel * dt
		spin -= dt * 14
		tyre:PivotTo(CFrame.lookAt(pos, pos + d) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, spin))
		if t > LIFE or pos.Y < -60 then
			conn:Disconnect()
			tyre:Destroy()
			live -= 1
		end
	end)
	Debris:AddItem(tyre, LIFE + 1)
end

function LaunchArcs.start(remotes: Instance, plot2, hub)
	local me = Players.LocalPlayer.UserId
	local launched = remotes:WaitForChild("Launched", 20) :: RemoteEvent?
	local auto = remotes:WaitForChild("AutoFire", 20) :: RemoteEvent?
	if launched then
		launched.OnClientEvent:Connect(function(userId: number, plotIndex: number?)
			if userId == me then return end
			local plot = plotByIndex(plotIndex)
			if not plot then return end
			-- the yard's worker comes out and fires it (CannonWorker), if there is one
			if LaunchArcs.workers then
				LaunchArcs.workers:fire(plot, function() LaunchArcs.fire(plot, plot2, false) end)
			else
				LaunchArcs.fire(plot, plot2, false)
			end
		end)
	end
	if auto then
		auto.OnClientEvent:Connect(function(plotIndex: number?, cash: number?)
			local plot = plotByIndex(plotIndex)
			if plot then
				if LaunchArcs.workers then
					LaunchArcs.workers:fire(plot, function() LaunchArcs.fire(plot, plot2, true) end)
				else
					LaunchArcs.fire(plot, plot2, true)
				end
			end
			if cash and hub and hub.toast then
				hub:toast(("AUTO-CANNON  +$%s"):format(Game.short(cash)), Color3.fromRGB(236, 196, 120))
			end
		end)
	end
end

return LaunchArcs
