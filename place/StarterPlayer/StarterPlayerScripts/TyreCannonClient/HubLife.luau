--!strict
-- TYRE CANNON :: HubLife
-- The hub's life without people (2026-10-22, the owner: "get rid of the npcs entirely, we need
-- something else to make it feel more lively"). Things that move on their own, cheaply (everything
-- through one BulkMoveTo a frame, nothing physical):
--   the trees     sway in a gusting breeze, all leaning the same way as a real wind does, each on its
--                 own phase (the canopy and trunk mesh only: the trunk's collider stays put)
--   the birds     three flocks wheeling slowly over the hub, each bird flapping and gliding on its own
--                 rhythm, in a loose cluster that breathes; by day (at night the season's bats fly)
--   butterflies   fluttering round the flower drifts, by day
--   kites         high over the park on long strings from pegs in the lawn, drifting in slow figure-8s
-- Built into the plaza's folder (it hides with the lobby during a run).
--   HubLife.start(folder)

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Models = require(script.Parent:WaitForChild("Models"))

local HubLife = {}

local C = Vector3.new(-6000, 0, 6000)
local WIND = Vector3.new(0.8, 0, 0.6).Unit   -- the breeze blows this way

local function part(parent: Instance, size: Vector3, color: Color3, shape: Enum.PartType?, wedge: boolean?): BasePart
	local p: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	if shape and p:IsA("Part") then p.Shape = shape end
	p.Parent = parent
	return p
end

local function daytime(): boolean
	local c = Lighting.ClockTime
	return c > 6.6 and c < 18.4
end

function HubLife.start(folder: Instance)
	local life = Instance.new("Folder")
	life.Name = "HubLife"
	life.Parent = folder
	local rng = Random.new(20261022)
	local movers: { { parts: { BasePart }, step: (number, { BasePart }, { CFrame }) -> () } } = {}

	--------------------------------------------------------------
	-- the trees
	--------------------------------------------------------------
	local trees = {}
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and string.find(m.Name, "^Tree") then
			local base = m:GetPivot().Position
			local parts, rest = {}, {}
			for _, p in ipairs(m:GetDescendants()) do
				if p:IsA("BasePart") and p.Name ~= "TrunkCollider" then
					table.insert(parts, p)
					table.insert(rest, p.CFrame)
				end
			end
			if #parts > 0 then
				local _, size = m:GetBoundingBox()
				-- (tall slim trees bend more than broad ones)
				local bend = math.clamp(0.006 + size.Y / math.max(size.X, size.Z) * 0.004, 0.006, 0.02)
				table.insert(trees, { base = base, parts = parts, rest = rest, bend = bend, phase = rng:NextNumber(0, 6.28), rate = rng:NextNumber(0.8, 1.15) })
			end
		end
	end
	local axis = Vector3.yAxis:Cross(WIND)    -- leaning downwind turns about this
	local treeAcc = 0

	--------------------------------------------------------------
	-- the birds
	--------------------------------------------------------------
	local flocks = {}
	-- (2026-10-23, the owner: the birds were squares and triangles) the Blender bird (Props/Bird: a body,
	-- and wings as their own meshes that flap about the shoulder); the part-built one stays as the fallback
	local birdTpl = Models.get("Props/Bird")
	local BIRD_SCALE = 1.7
	local function modelBird(tone: Color3): any?
		if not birdTpl then return nil end
		local m = Models.place(birdTpl, life, CFrame.new(), BIRD_SCALE)
		local rest = m:GetPivot()
		-- (a placed model is turned half round from its Blender front: turn it back so it flies -Z)
		local turn = CFrame.Angles(0, math.pi, 0)
		local body, bodyOff, wings = nil, nil, {}
		for _, p in ipairs(Models.parts(m)) do
			p.CastShadow = false
			local sa = p:FindFirstChildOfClass("SurfaceAppearance")
			if sa then sa.Color = tone else p.Color = tone end
			local off = turn * rest:ToObjectSpace(p.CFrame)
			if string.find(p.Name, "Wing") then
				local s = if off.Position.X >= 0 then 1 else -1
				-- its hinge: the wing's inner edge, against the body
				local h = Vector3.new(off.Position.X - s * p.Size.X / 2, off.Position.Y, off.Position.Z)
				table.insert(wings, { part = p, side = s, off = off, hinge = h })
			else
				body, bodyOff = p, off
			end
		end
		if not body or #wings < 2 then m:Destroy() return nil end
		return { body = body, bodyOff = bodyOff, wings = wings, model = true }
	end
	for f = 1, 3 do
		local birds = {}
		local n = rng:NextInteger(5, 8)
		local tone = if f == 2 then Color3.fromRGB(236, 236, 230) else Color3.fromRGB(58, 56, 60)
		for i = 1, n do
			-- (the model is painted light grey and the tone multiplies it: the dark flocks are pigeon grey,
			-- 58/56/60 turned the model black)
			-- (2026-10-24, the owner: "darken all the birds") slate grey, and the pale flock a dove grey
			local b = modelBird(if f == 2 then Color3.fromRGB(150, 150, 156) else Color3.fromRGB(74, 76, 86))
			if not b then
				local body = part(life, Vector3.new(0.5, 0.45, 1.3), tone, nil, false)
				local wings = {}
				for _, side in ipairs({ -1, 1 }) do
					table.insert(wings, { part = part(life, Vector3.new(0.08, 0.7, 1.9), tone, nil, true), side = side })
				end
				b = { body = body, wings = wings }
			end
			b.off = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-3, 3), rng:NextNumber(-9, 9))
			b.flap, b.phase, b.glide = rng:NextNumber(8, 11), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)
			table.insert(birds, b)
		end
		table.insert(flocks, { birds = birds, r = rng:NextNumber(150, 300), h = rng:NextNumber(55, 85), speed = rng:NextNumber(0.05, 0.08) * (if f == 2 then -1 else 1),
			phase = rng:NextNumber(0, 6.28), wobble = rng:NextNumber(0.3, 0.6) })
	end

	--------------------------------------------------------------
	-- butterflies, round the flowers
	--------------------------------------------------------------
	local flowers = {}
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and string.find(m.Name, "^Flowers") then table.insert(flowers, m:GetPivot().Position) end
	end
	local butterflies = {}
	local COLOURS = { Color3.fromRGB(255, 170, 40), Color3.fromRGB(250, 240, 120), Color3.fromRGB(150, 200, 255), Color3.fromRGB(255, 255, 255), Color3.fromRGB(230, 110, 200) }
	-- (2026-10-24, the owner: "remove the shitty butterflies") none
	for i = 1, 0 do
		local home = flowers[rng:NextInteger(1, #flowers)]
		local col = COLOURS[rng:NextInteger(1, #COLOURS)]
		local wings = {}
		for _, side in ipairs({ -1, 1 }) do
			table.insert(wings, { part = part(life, Vector3.new(0.04, 0.55, 0.5), col, nil, false), side = side })
		end
		table.insert(butterflies, { home = home, wings = wings, phase = rng:NextNumber(0, 6.28), a = rng:NextNumber(0.4, 0.9), b = rng:NextNumber(0.5, 1.1), r = rng:NextNumber(1.5, 3.5) })
	end

	--------------------------------------------------------------
	-- kites over the park, on strings from pegs in the lawn
	--------------------------------------------------------------
	local kites = {}
	for i, name in ipairs({ "Park/KiteA", "Park/KiteB", "Park/KiteC", "Park/KiteA" }) do
		local tpl = Models.get(name)
		local a = (i - 1) / 4 * math.pi * 2 + 0.4
		local peg = C + Vector3.new(math.cos(a), 0, math.sin(a)) * 372
		local kite: BasePart? = nil
		if tpl then
			local m = Models.place(tpl, life, CFrame.new(), 5)
			kite = m:FindFirstChildWhichIsA("BasePart", true)
			if kite then
				kite.Parent = life
				m:Destroy()
			end
		end
		if not kite then
			kite = part(life, Vector3.new(0.15, 4, 3), Color3.fromHSV(i / 4, 0.75, 1), nil, false)
		end
		local kiteP = kite :: BasePart
		local pegPart = part(life, Vector3.new(0.4, 1.4, 0.4), Color3.fromRGB(120, 90, 60))
		pegPart.CFrame = CFrame.new(peg + Vector3.new(0, 0.7, 0))
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.6, 0)
		a0.Parent = pegPart
		local a1 = Instance.new("Attachment")
		a1.Parent = kiteP
		local string_ = Instance.new("Beam")
		string_.Attachment0 = a0
		string_.Attachment1 = a1
		string_.Width0, string_.Width1 = 0.05, 0.035
		string_.Transparency = NumberSequence.new(0.25, 0.45)
		string_.Color = ColorSequence.new(Color3.fromRGB(240, 240, 235))
		string_.FaceCamera = true
		string_.CurveSize0 = -14
		string_.Segments = 12
		string_.Parent = kiteP
		table.insert(kites, { part = kiteP, peg = peg, phase = rng:NextNumber(0, 6.28), h = rng:NextNumber(46, 60), beam = string_ })
	end

	--------------------------------------------------------------
	-- every frame
	--------------------------------------------------------------
	local wasDay = nil
	RunService.Heartbeat:Connect(function(dt)
		if not life.Parent or not folder.Parent then return end
		local t = os.clock()
		local parts, cfs = {}, {}
		-- trees (30 a second is plenty for a sway)
		treeAcc += dt
		if treeAcc > 1 / 30 then
			treeAcc = 0
			local gust = 0.65 + 0.35 * math.sin(t * 0.21) * math.sin(t * 0.077 + 1)
			for _, tr in ipairs(trees) do
				local lean = tr.bend * gust * (0.6 + 0.4 * math.sin(t * tr.rate + tr.phase)) + tr.bend * 0.25 * math.sin(t * 2.3 * tr.rate + tr.phase * 2)
				local turn = CFrame.new(tr.base) * CFrame.fromAxisAngle(axis, lean) * CFrame.new(-tr.base)
				for i, p in ipairs(tr.parts) do
					table.insert(parts, p)
					table.insert(cfs, turn * tr.rest[i])
				end
			end
		end
		-- the day's things show by day only
		local day = daytime()
		if day ~= wasDay then
			wasDay = day
			for _, f in ipairs(flocks) do
				for _, b in ipairs(f.birds) do
					b.body.Transparency = if day then 0 else 1
					for _, w in ipairs(b.wings) do w.part.Transparency = if day then 0 else 1 end
				end
			end
			for _, bf in ipairs(butterflies) do
				for _, w in ipairs(bf.wings) do w.part.Transparency = if day then 0 else 1 end
			end
		end
		if day then
			for _, f in ipairs(flocks) do
				local a = f.phase + t * f.speed
				local r = f.r * (1 + 0.15 * math.sin(t * 0.1 + f.phase))
				local centre = C + Vector3.new(math.cos(a) * r, f.h + math.sin(t * f.wobble) * 6, math.sin(a) * r)
				local ahead = C + Vector3.new(math.cos(a + 0.05 * math.sign(f.speed)) * r, f.h, math.sin(a + 0.05 * math.sign(f.speed)) * r)
				local heading = CFrame.lookAt(centre, Vector3.new(ahead.X, centre.Y, ahead.Z))
				for _, b in ipairs(f.birds) do
					local breathe = 1 + 0.25 * math.sin(t * 0.4 + b.phase)
					local p = (heading * CFrame.new(b.off * breathe)).Position + Vector3.new(0, math.sin(t * 1.3 + b.phase) * 0.8, 0)
					local cf = heading.Rotation + p
					-- flap for a while, then glide with the wings level
					local flapping = math.sin(t * 0.5 + b.glide) > -0.2
					local beat = if flapping then math.sin(t * b.flap + b.phase) * 0.8 else 0.12
					table.insert(parts, b.body)
					if b.model then
						-- the body bobs a touch against each downstroke; each wing turns about its own shoulder
						table.insert(cfs, cf * CFrame.new(0, -beat * 0.08, 0) * b.bodyOff)
						for _, w in ipairs(b.wings) do
							table.insert(parts, w.part)
							table.insert(cfs, cf * CFrame.new(0, -beat * 0.08, 0) * CFrame.new(w.hinge) * CFrame.Angles(0, 0, w.side * beat) * CFrame.new(-w.hinge) * w.off)
						end
					else
						table.insert(cfs, cf)
						for _, w in ipairs(b.wings) do
							table.insert(parts, w.part)
							table.insert(cfs, cf * CFrame.new(w.side * 0.25, 0.1, 0) * CFrame.Angles(0, 0, w.side * beat) * CFrame.new(w.side * 0.95, 0, 0) * CFrame.Angles(0, 0, w.side * math.pi / 2))
						end
					end
				end
			end
			for _, bf in ipairs(butterflies) do
				local u = t + bf.phase
				local p = bf.home + Vector3.new(math.sin(u * bf.a) * bf.r, 1.6 + math.sin(u * 2.7) * 0.6 + math.sin(u * bf.b) * 0.5, math.sin(u * bf.b * 1.3) * bf.r)
				local cf = CFrame.new(p) * CFrame.Angles(0, u * 0.7, 0)
				local beat = math.sin(t * 22 + bf.phase) * 1.1
				for _, w in ipairs(bf.wings) do
					table.insert(parts, w.part)
					table.insert(cfs, cf * CFrame.Angles(0, 0, w.side * beat) * CFrame.new(w.side * 0.27, 0, 0))
				end
			end
		end
		-- (2026-10-23: a string with an end behind the camera draws as a line from the horizon to the bottom
		-- of the screen, the "stray line" over the yards and the run; it's hidden while either end is)
		local camCF = workspace.CurrentCamera.CFrame
		for _, k in ipairs(kites) do
			local zPeg = camCF:PointToObjectSpace(k.peg).Z
			local zKite = camCF:PointToObjectSpace(k.part.Position).Z
			k.beam.Enabled = zPeg < -6 and zKite < -6
			local u = t * 0.18 + k.phase
			local out = (k.peg - C).Unit
			local side = Vector3.new(-out.Z, 0, out.X)
			-- (2026-10-23: lower and further out, so the string leans like a kite's; a near-vertical string
			-- with its kite off the top of the screen read as a stray line over the yards)
			local p = k.peg + out * 64 + side * math.sin(u) * 22 + Vector3.new(0, k.h + math.sin(u * 2) * 5, 0)
			-- the kite faces into the wind, tipping as it swings
			table.insert(parts, k.part)
			table.insert(cfs, CFrame.lookAt(p, p - out) * CFrame.Angles(0, 0, math.cos(u) * 0.5))
		end
		if #parts > 0 then workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
	end)
end

return HubLife
