--!strict
-- TYRE CANNON :: BenchPose
-- (2026-10-24, the owner) Three ways to sit on a bench, taking turns each time you sit:
--   1 lean back: one arm along the backrest, the other hand at your side, one leg crossed over the
--     other, head tipped back
--   2 the thinker: hunched forward, forearms on the knees, head down
--   3 talking to your own tyre (the easter egg): your tyre sits beside you on the bench, you turn to
--     it and chat with your hands, it nods along (2026-10-24, the owner: no speech bubble any more)
-- The rig is R6 (no knees or elbows) and nothing is uploaded: the poses are joint angles written
-- straight onto the Motor6Ds each frame after the Animator (RunService.Stepped), eased in. The pose
-- goes to the server (V2.BenchPose) and comes back as the character's BenchPose attribute, so every
-- client poses everyone the same way.
--   BenchPose.init()           once, from Main
--   BenchPose.sat() / .stood() from BenchKit, for the local player

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local WheelAssembly = require(Root:WaitForChild("Modules"):WaitForChild("WheelAssembly"))

local BenchPose = {}

local A = CFrame.Angles
local EASE = 0.4

-- each pose: lean (torso pitch, + is back), twist (torso yaw, - turns toward +X, the tyre's side),
-- then each limb's angle in the bench's upright frame (not the torso's), and an optional lift.
-- Angles: + about X swings a hanging limb forward; + about Z swings its foot toward +X; + about Y
-- swings a forward-pointing limb toward -X.
type Limb = { r: CFrame, up: Vector3? }
type Pose = { lean: number, twist: number, slide: Vector3, head: CFrame, la: CFrame, ra: CFrame, ll: Limb, rl: Limb }

-- (2026-10-24, the owner, third look: "fix the bench sitting animations") the legs hung straight down from
-- the hips, which on an R6 rig (no knees) reads as standing in front of the bench, and the lean-back arm
-- stuck up in the air. Now it's Roblox's own seated shape done properly: the thighs along the seat,
-- pointing forward, the torso upright against the backrest, the hands resting on the knees, the head
-- looking about; the second pose turns to the tyre and talks with one hand.
local SLIDE = Vector3.new(0, 0, 0.15)  -- (back into the seat a touch, against the backrest)
local SEAT = math.pi / 2 - 0.06        -- the thighs: forward, a hair above level (the knees up)

local function pose(k: number, t: number): Pose
	if k == 1 then
		local breathe = math.sin(t * 1.3) * 0.012
		local look = math.sin(t * 0.23) * 0.35 + math.sin(t * 0.61) * 0.1
		return {
			lean = 0.06 + breathe, twist = 0, slide = SLIDE,
			head = A(-0.04 + math.sin(t * 0.4) * 0.04, look, 0),
			-- the hands on the knees: the arms forward and a little in
			ra = A(0, 0, -0.08) * A(0.72, 0, 0),
			la = A(0, 0, 0.08) * A(0.72, 0, 0),
			ll = { r = A(0, 0, -0.05) * A(SEAT, 0, 0) },
			rl = { r = A(0, 0, 0.05) * A(SEAT, 0, 0) },
		}
	elseif k == 2 then
		local breathe = math.sin(t * 1.1) * 0.02
		return {
			lean = -0.3 + breathe, twist = 0, slide = SLIDE,
			head = A(-0.2 + math.sin(t * 0.4) * 0.05, math.sin(t * 0.27) * 0.12, 0), -- down, thinking it over
			ra = A(0, 0, -0.1) * A(1.05, 0, 0),
			la = A(0, 0, 0.1) * A(1.05, 0, 0),
			ll = { r = A(0, 0, -0.07) * A(SEAT, 0, 0) },
			rl = { r = A(0, 0, 0.07) * A(SEAT, 0, 0) },
		}
	end
	-- 3: turned to the tyre on your right, talking with your hands
	local talk = math.sin(t * 5.2) * 0.22 + math.sin(t * 2.3) * 0.12
	return {
		lean = 0.04, twist = -0.32, slide = SLIDE,
		head = A(-0.12 + math.sin(t * 3.1) * 0.06, -0.5, 0),
		ra = A(0, -0.45, 0) * A(1.15 + talk, 0, 0.12),
		la = A(0, 0, 0.08) * A(0.72, 0, 0),
		ll = { r = A(0, 0, -0.05) * A(SEAT, 0, 0) },
		rl = { r = A(0, 0, 0.05) * A(SEAT, 0, 0) },
	}
end

local NAMES = { "RootJoint", "Neck", "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }

type Rig = {
	char: Model, hum: Humanoid, k: number, t0: number, joints: { [string]: Motor6D },
	tyre: Model?, bubble: BillboardGui?, line: number, nextLine: number,
}
local rigs: { [Model]: Rig } = {}

-- a joint's Transform that turns its Part1 by r (given in Part0's space) about pivot, then shifts it by off
local function turn(j: Motor6D, r: CFrame, pivot: Vector3, off: Vector3?): CFrame
	local c0 = j.C0
	return c0:Inverse() * CFrame.new(off or Vector3.zero) * CFrame.new(pivot) * r * CFrame.new(-pivot) * c0
end

local function clear(rig: Rig)
	for _, j in pairs(rig.joints) do
		if j.Parent then j.Transform = CFrame.identity end
	end
	if rig.tyre then rig.tyre:Destroy() end
	if rig.bubble then rig.bubble:Destroy() end
	rigs[rig.char] = nil
end

local function tyreFor(rig: Rig)
	local root = rig.hum.RootPart
	if not root then return end
	local ok, m = pcall(WheelAssembly.build, nil, {
		diameter = 2.3,
		skin = rig.char:GetAttribute("BenchSkin") or "stock",
		rim = rig.char:GetAttribute("BenchRim") or "steel",
		detail = "low", name = "BenchBuddy",
	})
	if not ok or not m then return end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = true
		end
	end
	m.Parent = workspace
	rig.tyre = m
end

local function attach(char: Model)
	local k = char:GetAttribute("BenchPose")
	local hum = char:FindFirstChildOfClass("Humanoid")
	local old = rigs[char]
	local mine = char == Players.LocalPlayer.Character
	if old and (old.k ~= k or not hum or (mine and not hum.Sit)) then clear(old) end
	if type(k) ~= "number" or k < 1 or k > 3 or not hum or rigs[char] then return end
	local joints = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") and table.find(NAMES, d.Name) then joints[d.Name] = d end
	end
	if not joints.RootJoint then return end
	local rig: Rig = { char = char, hum = hum, k = k, t0 = os.clock(), joints = joints, line = 1, nextLine = 0 }
	rigs[char] = rig
	if k == 3 then tyreFor(rig) end
end

local function step()
	local now = os.clock()
	for char, rig in pairs(rigs) do
		-- (only your own Sit is trusted: others' poses end when the server clears their attribute)
		if not char.Parent or rig.hum.Health <= 0 or (char == Players.LocalPlayer.Character and not rig.hum.Sit) then
			clear(rig)
			continue
		end
		local t = now - rig.t0
		local a = math.min(1, t / EASE)
		a = a * a * (3 - 2 * a)
		local p = pose(rig.k, t)
		local J = rig.joints
		-- the torso, about the hips (in the root's upright frame)
		local tr = A(0, p.twist, 0) * A(p.lean, 0, 0)
		local inv = tr:Inverse()
		local function set(name: string, r: CFrame, pivot: Vector3, up: Vector3?)
			local j = J[name]
			if not j then return end
			local rel = inv * r                             -- from the bench's frame into the torso's
			local off = if up then inv:VectorToWorldSpace(up) else nil
			j.Transform = CFrame.identity:Lerp(turn(j, rel, pivot, off), a)
		end
		J.RootJoint.Transform = CFrame.identity:Lerp(turn(J.RootJoint, tr, Vector3.new(0, -1, 0), p.slide), a)
		set("Neck", tr * p.head, Vector3.new(0, 1, 0))       -- (the head turns with the torso, then its own way)
		set("Right Shoulder", p.ra, Vector3.new(1, 0.5, 0))
		set("Left Shoulder", p.la, Vector3.new(-1, 0.5, 0))
		set("Right Hip", p.rl.r, Vector3.new(1, -1, 0), p.rl.up)
		set("Left Hip", p.ll.r, Vector3.new(-1, -1, 0), p.ll.up)
		-- the tyre beside you, on its tread, nodding along (no speech bubble: the animation says it)
		local root = rig.hum.RootPart
		if rig.tyre and root then
			local nod = math.max(0, math.sin(t * 2.2)) ^ 6 * 0.25
			local cf = root.CFrame * CFrame.new(2.75, -1.5 + 1.15 + nod * 0.4, -0.25) * A(0, -0.35, 0) * A(0, 0, nod * 0.6)
			rig.tyre:PivotTo(cf * CFrame.Angles(0, 0.5, 0))   -- its face toward you, turned a little to the front
		end
	end
end

local remote: RemoteEvent? = nil
local nextK = 1

function BenchPose.sat()
	local k = nextK
	nextK = if nextK == 1 then 3 else 1     -- (2026-10-24, the owner: just the plain sit and the tyre chat)
	local char = Players.LocalPlayer.Character
	if char then
		char:SetAttribute("BenchPose", k)     -- at once here; the server's copy follows for everyone
		attach(char)
	end
	if remote then remote:FireServer(k) end
end

function BenchPose.stood()
	local char = Players.LocalPlayer.Character
	if char then
		char:SetAttribute("BenchPose", nil)
		local rig = rigs[char]
		if rig then clear(rig) end
	end
	if remote then remote:FireServer(0) end
end

local started = false
function BenchPose.init()
	if started then return end
	started = true
	task.spawn(function()
		local v2 = Root:WaitForChild("Remotes"):WaitForChild("V2", 30)
		local r = v2 and v2:WaitForChild("BenchPose", 30)
		if r and r:IsA("RemoteEvent") then remote = r end
	end)
	local function watch(pl: Player)
		local function onChar(char: Model)
			char:GetAttributeChangedSignal("BenchPose"):Connect(function() attach(char) end)
			attach(char)
		end
		if pl.Character then onChar(pl.Character) end
		pl.CharacterAdded:Connect(onChar)
	end
	for _, pl in ipairs(Players:GetPlayers()) do watch(pl) end
	Players.PlayerAdded:Connect(watch)
	RunService.Stepped:Connect(step)
end

return BenchPose
