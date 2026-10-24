--!strict
-- TYRE CANNON :: BenchKit
-- (2026-10-23, the owner: "the benches at the centre are old. Make the benches bigger and make them
-- able to be sat") One bench everywhere in the hub: the Blender one (Props/Bench, hubkit.bench:
-- cast-iron ends, wooden slats, 8.9 wide) with a seat pad on it, so walking onto it (or pressing the
-- prompt) sits you down (see sit below). Falls back to the park pack's bench (Park/Bench).
--   BenchKit.place(parent, cf, scale?, solid?) -> Model?
--     cf: the bench's spot on the ground, its back toward cf's look (as Models.place leaves it)

local Models = require(script.Parent:WaitForChild("Models"))
local Physical = require(script.Parent:WaitForChild("Physical"))
local BenchPose = require(script.Parent:WaitForChild("BenchPose"))

local BenchKit = {}

local SEAT_H = 2.1     -- the seat's top above the ground, in the model's units (hubkit.bench)
local Players = game:GetService("Players")

-- These benches are built on the client, and a client-side Seat never sits anyone (Seat:Sit and touch
-- sitting are the server's), so sitting is done by hand: Humanoid.Sit plus the same weld a Seat makes
-- (Roblox's SeatWeld: C0 = top of the pad, C1 = 1.5 below the root for R6, both turned -90 on X).
-- The character is the player's own, so where it sits replicates; jumping (Sit -> false) stands up.
local ROT = CFrame.Angles(-math.pi / 2, 0, 0)
local lastUp = 0

local function sit(seat: BasePart, prompt: ProximityPrompt, hum: Humanoid)
	local root = hum.RootPart
	if not root or hum.Health <= 0 or hum.SeatPart or hum.Sit or seat:GetAttribute("Taken") then return end
	local up = if hum.RigType == Enum.HumanoidRigType.R6 then 1.5 else root.Size.Y / 2 + 0.6
	local back = 0.3     -- (sat back against the backrest, not on the front edge)
	root.CFrame = seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + up, back)
	local w = Instance.new("Weld")
	w.Name = "BenchWeld"
	w.Part0 = seat
	w.Part1 = root
	w.C0 = CFrame.new(0, seat.Size.Y / 2, back) * ROT
	w.C1 = CFrame.new(0, -up, 0) * ROT
	w.Parent = seat
	seat:SetAttribute("Taken", true)
	prompt.Enabled = false
	hum.Sit = true
	local conns: { RBXScriptConnection } = {}
	local function stand()
		for _, c in ipairs(conns) do c:Disconnect() end
		w:Destroy()
		seat:SetAttribute("Taken", nil)
		prompt.Enabled = true
		lastUp = os.clock()
		BenchPose.stood()
	end
	table.insert(conns, hum:GetPropertyChangedSignal("Sit"):Connect(function()
		if not hum.Sit then stand() end
	end))
	table.insert(conns, hum.Died:Connect(stand))
	table.insert(conns, hum.AncestryChanged:Connect(function(_, p) if not p then stand() end end))
	BenchPose.sat()      -- one of the three poses, in turn
end

function BenchKit.place(parent: Instance, cf: CFrame, scale: number?, solid: boolean?): Model?
	local s = scale or 1
	local tpl = Models.get("Props/Bench")
	local fresh = tpl ~= nil
	tpl = tpl or Models.get("Park/Bench")
	if not tpl then return nil end
	local m = Models.place(tpl, parent, cf, s)
	-- stand it on the ground at cf
	local box, size = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + Vector3.new(0, cf.Position.Y - (box.Position.Y - size.Y / 2), 0))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.CastShadow = true end
	end
	if solid ~= false then pcall(Physical.solidify, m) end
	if not fresh then return m end
	-- the seat: a thin invisible pad on the slats, facing away from the backrest
	local piv = m:GetPivot()
	local look = Vector3.new(piv.LookVector.X, 0, piv.LookVector.Z).Unit
	local at = Vector3.new(piv.Position.X, cf.Position.Y + SEAT_H * s + 0.05, piv.Position.Z) - look * (0.15 * s)
	local seat = Instance.new("Part")
	seat.Name = "BenchSeat"
	seat.Size = Vector3.new(7.6 * s, 0.25, 1.6 * s)
	seat.CFrame = CFrame.lookAt(at, at - look)
	seat.Transparency = 1
	seat.Anchored = true
	seat.CanCollide = false
	seat.CanTouch = true
	seat.Massless = true
	seat.CanQuery = false
	seat.Parent = m
	-- a prompt to sit, and walking (or dropping) onto the slats sits you too, like a real Seat
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Sit"
	prompt.ObjectText = "Bench"
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = seat
	prompt.Triggered:Connect(function(player: Player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and player == Players.LocalPlayer then sit(seat, prompt, hum) end
	end)
	seat.Touched:Connect(function(hit: BasePart)
		local char = Players.LocalPlayer.Character
		if not char or hit.Parent ~= char or os.clock() - lastUp < 2 then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.MoveDirection.Magnitude > 0.1 then sit(seat, prompt, hum) end
	end)
	return m
end

return BenchKit
