--!strict
-- TYRE CANNON :: CannonWorker
-- A worker lives in every yard's garage. When the yard's cannon fires he comes out of a back door
-- in the garage wall, walks across to the cannon, hits the button, watches the shot go and walks
-- back in; the door shuts behind him. For your own launch he comes out as the cutscene starts and
-- goes back in once you're away. Everyone sees every yard's worker (the auto-cannon's shots too).
--   CannonWorker.new(plot2) -> workers
--   workers:fire(plot, onFire)   walk out, press, onFire() at the press, walk back
--   workers:attend(plot)         walk out and wait by the cannon (your launch)
--   workers:dismiss(plot)        walk back in

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Game = require(Root:WaitForChild("Modules"):WaitForChild("Game"))
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))
local Assets = Root:WaitForChild("Assets")

local CannonWorker = {}
CannonWorker.__index = CannonWorker

local WALK = 13             -- studs a second
local BUILD_Z = -14         -- the garage's middle along the street edge (PlotStage)
local WALL_X = -34.5        -- its wall facing into the yard
local DOOR_W, DOOR_H = 4.2, 7.4
-- where he stands to fire, in the launcher's own frame (beside it, on the garage side)
local STAND = CFrame.new(-6, 0, -14)

local function load(animator: Animator, id: string?, looped: boolean): AnimationTrack?
	if type(id) ~= "string" or id == "" then return nil end
	local a = Instance.new("Animation")
	a.AnimationId = id
	local ok, track = pcall(function() return animator:LoadAnimation(a) end)
	if not ok or not track then return nil end
	track.Looped = looped
	return track
end

function CannonWorker.new(plot2)
	local self = setmetatable({}, CannonWorker)
	self.plot2 = plot2
	self.yards = {} :: { [Instance]: any }
	return self
end

-- the back door in the garage wall: a frame and a panel on a hinge (built once per yard)
function CannonWorker:door(plot: Instance, base: CFrame)
	local y = self.yards[plot]
	if y.door and y.door.Parent then return y.door, y.hinge, y.panel end
	local m = Instance.new("Model")
	m.Name = "WorkerDoor"
	local at = base * CFrame.new(WALL_X + 0.15, 2, BUILD_Z) * CFrame.Angles(0, math.pi / 2, 0)
	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.Parent = m
		return p
	end
	-- the dark doorway, its frame, and the panel hung on its left post
	part("Opening", Vector3.new(DOOR_W, DOOR_H, 0.2), at * CFrame.new(0, DOOR_H / 2, 0.1), Color3.fromRGB(16, 16, 18), Enum.Material.SmoothPlastic)
	part("FrameL", Vector3.new(0.4, DOOR_H + 0.4, 0.5), at * CFrame.new(-DOOR_W / 2 - 0.2, DOOR_H / 2, 0), Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
	part("FrameR", Vector3.new(0.4, DOOR_H + 0.4, 0.5), at * CFrame.new(DOOR_W / 2 + 0.2, DOOR_H / 2, 0), Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
	part("FrameTop", Vector3.new(DOOR_W + 0.8, 0.4, 0.5), at * CFrame.new(0, DOOR_H + 0.2, 0), Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
	local hinge = at * CFrame.new(-DOOR_W / 2, 0, -0.15)
	local panel = part("Panel", Vector3.new(DOOR_W, DOOR_H, 0.25), hinge * CFrame.new(DOOR_W / 2, DOOR_H / 2, 0), Color3.fromRGB(176, 96, 52), Enum.Material.Metal)
	m.PrimaryPart = panel
	m.Parent = plot
	y.door, y.hinge, y.panel = m, hinge, panel
	return m, hinge, panel
end

-- swing the door open (a quarter turn out into the yard) or shut
function CannonWorker:swing(plot: Instance, open: boolean)
	local y = self.yards[plot]
	if not (y and y.panel and y.hinge) then return end
	local hinge: CFrame = y.hinge
	local target = hinge * CFrame.Angles(0, if open then -math.rad(100) else 0, 0) * CFrame.new(DOOR_W / 2, DOOR_H / 2, 0)
	local cv = Instance.new("CFrameValue")
	cv.Value = y.panel.CFrame
	cv.Changed:Connect(function(v) if y.panel then y.panel.CFrame = v end end)
	local tw = TweenService:Create(cv, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
	tw.Completed:Connect(function() cv:Destroy() end)
	tw:Play()
end

-- the worker himself: the yard's operator, standing in the doorway, hidden until he steps out
function CannonWorker:spawn(plot: Instance, base: CFrame): Model?
	local tpl = Assets:FindFirstChild("Characters") and Assets.Characters:FindFirstChild("Operator")
	if not tpl then return nil end
	local m = tpl:Clone() :: Model
	m.Name = "CannonWorker"
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = false
			d.LocalTransparencyModifier = 1
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local hrp = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = m:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum) then
		m:Destroy()
		return nil
	end
	hrp.Anchored = true
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	m.PrimaryPart = hrp
	local _, size = m:GetBoundingBox()
	local door = base * CFrame.new(WALL_X - 0.6, 2 + size.Y / 2, BUILD_Z)
	m:PivotTo(door * CFrame.Angles(0, -math.pi / 2, 0))
	m.Parent = plot
	return m
end

local function fadeIn(m: Model, on: boolean, time: number)
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local k = math.clamp((os.clock() - t0) / time, 0, 1)
		local v = if on then 1 - k else k
		for _, d in ipairs(m:GetDescendants()) do
			if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then (d :: any).LocalTransparencyModifier = v end
		end
		if k >= 1 then conn:Disconnect() end
	end)
end

-- walk the worker's root along a straight line, facing the way he goes (blocks)
local function walk(m: Model, to: Vector3, faceAfter: Vector3?)
	local hrp = m.PrimaryPart :: BasePart
	local from = hrp.Position
	local goal = Vector3.new(to.X, from.Y, to.Z)
	local dist = (goal - from).Magnitude
	local t = dist / WALK
	local t0 = os.clock()
	local dir = if dist > 0.01 then (goal - from).Unit else hrp.CFrame.LookVector
	while m.Parent do
		local k = math.clamp((os.clock() - t0) / math.max(t, 0.01), 0, 1)
		local p = from:Lerp(goal, k)
		hrp.CFrame = CFrame.lookAt(p, p + dir)
		if k >= 1 then break end
		RunService.Heartbeat:Wait()
	end
	if faceAfter and m.Parent then
		local p = hrp.Position
		local look = Vector3.new(faceAfter.X, p.Y, faceAfter.Z)
		if (look - p).Magnitude > 0.1 then hrp.CFrame = CFrame.lookAt(p, look) end
	end
end

-- the yard's state for a plot
function CannonWorker:yard(plot: Instance)
	local y = self.yards[plot]
	if not y then
		y = { busy = false }
		self.yards[plot] = y
	end
	return y
end

-- where he walks to, and the cannon's middle (to face), in the world
function CannonWorker:spotFor(plot: Instance, base: CFrame): (Vector3, Vector3)
	local layout = Game.yardDecode(plot:GetAttribute("V2_Layout") :: string?)
	local spot = base * Game.yardSpot(layout, "cannon")
	return (spot * STAND).Position, spot.Position
end

-- out to the cannon: the door opens, he steps out and walks over; returns the worker or nil
function CannonWorker:goOut(plot: Instance): Model?
	local base = plot:GetAttribute("BaseCFrame")
	if typeof(base) ~= "CFrame" or plot:GetAttribute("V2_Tier") == nil then return nil end
	local y = self:yard(plot)
	y.outDone = false
	self:door(plot, base)
	local m = self:spawn(plot, base)
	if not m then return nil end
	y.worker = m
	local hum = m:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	y.walkTrack = load(animator :: Animator, Config.Animations.walk, true)
	y.idleTrack = load(animator :: Animator, Config.Animations.idle, true)
	y.pressTrack = load(animator :: Animator, Config.Animations.land, false)
	self:swing(plot, true)
	task.wait(0.2)
	fadeIn(m, true, 0.25)
	if y.walkTrack then y.walkTrack:Play(0.15) end
	local stand, cannon = self:spotFor(plot, base)
	walk(m, stand, cannon)
	if y.walkTrack then y.walkTrack:Stop(0.2) end
	if y.idleTrack then y.idleTrack:Play(0.2) end
	y.outDone = true
	return m
end

-- back in: he walks to the door, steps through and it shuts behind him
function CannonWorker:goBack(plot: Instance)
	local y = self.yards[plot]
	local m = y and y.worker
	local base = plot:GetAttribute("BaseCFrame")
	if not (m and m.Parent and typeof(base) == "CFrame") then
		if y then y.busy = false end
		return
	end
	if y.idleTrack then y.idleTrack:Stop(0.2) end
	if y.walkTrack then y.walkTrack:Play(0.15) end
	local door = (base * CFrame.new(WALL_X - 0.6, 2, BUILD_Z)).Position
	walk(m, (base * CFrame.new(WALL_X + 2.5, 2, BUILD_Z)).Position)
	fadeIn(m, false, 0.25)
	walk(m, door)
	m:Destroy()
	y.worker = nil
	self:swing(plot, false)
	y.busy = false
end

-- a shot from this yard: out, press (onFire), watch, back in. Busy already: fire straight away.
function CannonWorker:fire(plot: Instance, onFire: () -> ())
	local y = self:yard(plot)
	local cam = workspace.CurrentCamera
	local base = plot:GetAttribute("BaseCFrame")
	local far = typeof(base) ~= "CFrame" or (cam and (cam.CFrame.Position - (base :: CFrame).Position).Magnitude > 700)
	if y.busy or far then
		onFire()
		return
	end
	y.busy = true
	task.spawn(function()
		local m = self:goOut(plot)
		if m and y.pressTrack then y.pressTrack:Play(0.1) end
		task.wait(m and 0.25 or 0)
		pcall(onFire)
		task.wait(1.1)
		self:goBack(plot)
	end)
end

-- your launch: he comes out and waits by the cannon until dismissed
function CannonWorker:attend(plot: Instance)
	local y = self:yard(plot)
	if y.busy then return end
	y.busy = true
	y.attending = true
	task.spawn(function()
		local m = self:goOut(plot)
		if not m then
			y.busy, y.attending = false, false
			return
		end
		-- dismissed while still walking out: go straight back
		if not y.attending then self:goBack(plot) end
	end)
end

function CannonWorker:dismiss(plot: Instance)
	local y = self.yards[plot]
	if not (y and y.attending) then return end
	y.attending = false
	-- still on his way out: attend's own task takes him back when he gets there
	if y.outDone and y.worker and y.worker.Parent then
		task.spawn(function() self:goBack(plot) end)
	end
end

return CannonWorker
