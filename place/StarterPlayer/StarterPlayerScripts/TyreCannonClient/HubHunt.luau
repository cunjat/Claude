--!strict
-- TYRE CANNON :: HubHunt (client)
-- The lost lug nuts (server: HubHunt; 2026-10-22, the owner: "some sort of incentive for looking
-- around"). Today's nuts you haven't found stand in their spots round the hub, turning slowly just
-- over the grass, with a glint and a warm glow you can catch from down a walk. Walk into one to pick it
-- up: the server checks and pays, and its banner says how many are left. A new six each UTC day.
--   HubHunt.start(folder)   (the plaza's folder: the nuts hide with the lobby during a run)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Models = require(script.Parent:WaitForChild("Models"))

local HubHunt = {}

local GOLD = Color3.fromRGB(255, 196, 64)
local PICK = 5.5          -- studs from the nut (flat) that picks it up
local HOVER = 1.5

local function groundAt(p: Vector3, skip: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(p.X, 120, p.Z), Vector3.new(0, -240, 0), params)
	return if hit then hit.Position.Y else 0
end

-- the nut: the game's own model if it's in, else a gold hex nut of parts
local function makeNut(): Model
	local tpl = Models.get("Props/LugNut")
	local m: Model
	if tpl then
		m = Models.place(tpl, nil :: any, CFrame.new(), 1, false)
		local _, s = m:GetBoundingBox()
		local big = math.max(s.X, s.Y, s.Z)
		if big > 0 then m:ScaleTo(m:GetScale() * 2 / big) end
	else
		m = Instance.new("Model")
		local body = Instance.new("Part")
		body.Shape = Enum.PartType.Cylinder
		body.Size = Vector3.new(1, 1.9, 1.9)
		body.CFrame = CFrame.Angles(0, 0, math.pi / 2)
		body.Parent = m
		local cap = Instance.new("Part")
		cap.Shape = Enum.PartType.Ball
		cap.Size = Vector3.new(1.3, 1.3, 1.3)
		cap.CFrame = CFrame.new(0, 0.45, 0)
		cap.Parent = m
		m.PrimaryPart = body
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			if not tpl then
				d.Material = Enum.Material.Metal
				d.Color = GOLD
			end
		end
	end
	local core = m:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 9
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = core
	local glint = Instance.new("ParticleEmitter")
	glint.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glint.Color = ColorSequence.new(Color3.fromRGB(255, 236, 160))
	glint.LightEmission = 1
	glint.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	glint.Lifetime = NumberRange.new(0.6, 1.1)
	glint.Rate = 5
	glint.Speed = NumberRange.new(0.6, 1.6)
	glint.SpreadAngle = Vector2.new(180, 180)
	glint.Parent = core
	m.Name = "LugNut"
	return m
end

function HubHunt.start(folder: Instance)
	local remotes = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Remotes"):WaitForChild("V2")
	local State = remotes:WaitForChild("HuntState", 30) :: RemoteFunction?
	local Find = remotes:WaitForChild("HuntFind", 30) :: RemoteFunction?
	if not (State and Find) then return end
	local holder = Instance.new("Folder")
	holder.Name = "LugNuts"
	holder.Parent = folder
	local nuts: { [number]: { model: Model, base: CFrame, phase: number, busy: boolean } } = {}
	local day = -1

	local function refresh()
		local ok, st = pcall(function() return (State :: RemoteFunction):InvokeServer() end)
		if not ok or type(st) ~= "table" then return end
		if st.day == day then return end
		day = st.day
		holder:ClearAllChildren()
		table.clear(nuts)
		for i, p in ipairs(st.spots or {}) do
			if not (st.found and st.found[i]) and typeof(p) == "Vector3" then
				local y = groundAt(p, { holder })
				local m = makeNut()
				local base = CFrame.new(p.X, y + HOVER, p.Z)
				m:PivotTo(base)
				m.Parent = holder
				nuts[i] = { model = m, base = base, phase = i * 1.7, busy = false }
			end
		end
	end
	refresh()
	task.spawn(function()
		while holder.Parent do
			task.wait(300)
			refresh()
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if not holder.Parent then return end
		local t = os.clock()
		for _, n in pairs(nuts) do
			-- turning slowly, bobbing a little
			n.model:PivotTo(n.base * CFrame.new(0, math.sin(t * 1.6 + n.phase) * 0.25, 0) * CFrame.Angles(0, t * 1.2 + n.phase, 0.35))
		end
		acc += dt
		if acc < 0.15 then return end
		acc = 0
		local char = Players.LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return end
		for i, n in pairs(nuts) do
			local d = Vector3.new(root.Position.X - n.base.X, 0, root.Position.Z - n.base.Z).Magnitude
			if d < PICK and not n.busy and math.abs(root.Position.Y - n.base.Y) < 12 then
				n.busy = true
				task.spawn(function()
					local ok, res = pcall(function() return (Find :: RemoteFunction):InvokeServer(i) end)
					if ok and type(res) == "table" and res.ok then
						nuts[i] = nil
						-- a pop: up, bigger, gone
						local m = n.model
						local t0 = os.clock()
						local s0 = m:GetScale()
						while os.clock() - t0 < 0.35 and m.Parent do
							local k = (os.clock() - t0) / 0.35
							pcall(function() m:ScaleTo(s0 * (1 + k * 0.8)) end)
							m:PivotTo(n.base * CFrame.new(0, k * 3, 0) * CFrame.Angles(0, k * 8, 0))
							RunService.Heartbeat:Wait()
						end
						m:Destroy()
					else
						task.wait(1)
						n.busy = false
					end
				end)
			end
		end
	end)
end

return HubHunt
