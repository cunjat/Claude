--!strict
-- TYRE CANNON :: PlazaLife
-- Brings the plaza to life round the Trophy Pillar (owner's brief, 2026-10-15: "not too extravagant,
-- but it can't be bland"):
--   a rangoli ring painted on the floor round the pillar's steps
--   eight tyre planters full of marigolds, and a bench in front of each leaderboard
--   bunting strung from the pillar's cap out to the eight street lamps
--   a chai corner (cart, rope cots, water pots) and a tyre swing with a tyre pyramid
-- Built on the client from RoadDecor's pieces and plain parts, by LobbyVista, so it hides with the
-- vista. Flat paint only: no lights, no glow. workspace:SetAttribute("PlazaLife", false) turns it off.
-- (2026-10-16, the owner's ask: "update some of the assets with what we made, and make them
-- physical") The planters, chai cart, cots, pots, swing, tyre pyramid and toran are now the Blender
-- models (Assets/Roadside, art/blender/roadside.py) wherever they've been imported, and solid
-- (Models.place's `solid`: players walk round them, not through); RoadDecor's built pieces stay as
-- the fallback.
-- (2026-10-16, the owner: "everything is slightly too organised ... the grey ground isn't helping,
-- and the old street lights") Also: the plaza floor in warm sandstone pavers with a terracotta edge
-- instead of grey concrete (recoloured here, on the client: nothing in the place is moved); the old
-- sodium lamps hidden and lanterns on posts standing in their places (the bunting runs to them);
-- the rangoli one painted texture (art/ui/rangoli.py) instead of 48 boxes round a curve; and the
-- lawn between the yards' paths dressed in small clusters, a garden corner, a mechanic's pile, a
-- parked scooter, placed by a seeded scatter: jittered, turned and sized a little differently each,
-- so it reads as put there by hand, and is the same for everyone.

local PlazaLife = {}

-- the Blender model standing in for each RoadDecor piece
local MODEL = {
	planter = "Roadside/RoadPlanter", chaicart = "Roadside/RoadChaiCart", charpai = "Roadside/RoadCharpai",
	matka = "Roadside/RoadMatka", tyreswing = "Roadside/RoadTyreSwing", tyrepyramid = "Roadside/RoadTyrePyramid",
	toran = "Roadside/RoadToran",
}

local CENTRE = Vector3.new(-6000, 2, 6000) -- the plaza floor's top
-- Halloween (2026-10-22): one switch, DayNight.halloween(); outside the season none of it is built
local okDN, DayNight = pcall(require, script.Parent:WaitForChild("DayNight"))
local function halloween(): boolean
	return okDN and (DayNight :: any).halloween() == true
end
local SPOOKY_FLAGS = { Color3.fromRGB(255, 122, 24), Color3.fromRGB(110, 52, 168), Color3.fromRGB(30, 26, 34), Color3.fromRGB(150, 214, 60) }
local FLAGS = { Color3.fromRGB(255, 138, 30), Color3.fromRGB(242, 194, 48), Color3.fromRGB(217, 79, 154),
	Color3.fromRGB(63, 174, 106), Color3.fromRGB(42, 111, 214) }
local WOOD = Color3.fromRGB(150, 98, 58)

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = parent
	return p
end

local function at(r: number, a: number, y: number?): Vector3
	return CENTRE + Vector3.new(math.cos(a) * r, y or 0, math.sin(a) * r)
end

-- a frame on the floor at r, a, its -Z facing the pillar
local function facing(r: number, a: number): CFrame
	local p = at(r, a)
	return CFrame.lookAt(p, Vector3.new(CENTRE.X, p.Y, CENTRE.Z))
end

-- one of RoadDecor's pieces, scaled, standing on the floor
local function decor(parent: Instance, kind: string, cf: CFrame, scale: number)
	-- our model, solid, when it's there
	local okM, Models = pcall(require, script.Parent:FindFirstChild("Models") :: ModuleScript)
	local tpl = okM and MODEL[kind] and (Models :: any).get(MODEL[kind])
	if tpl then
		local okP, m = pcall(function() return (Models :: any).place(tpl, nil, CFrame.new(), scale, true) end)
		if okP and m then
			m.Name = kind
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then d.CastShadow = false end
			end
			m:PivotTo(cf)
			local box, size = m:GetBoundingBox()
			m:PivotTo(m:GetPivot() + Vector3.new(0, CENTRE.Y - (box.Position.Y - size.Y / 2), 0))
			m.Parent = parent
			return
		end
	end
	local mod = script.Parent:FindFirstChild("RoadDecor")
	if not mod then return end
	local ok, RoadDecor = pcall(require, mod)
	local build = ok and (RoadDecor :: any).BUILD and (RoadDecor :: any).BUILD[kind]
	if not build then return end
	local m = Instance.new("Model")
	m.Name = kind
	local okb = pcall(build, m, {})
	if not okb or #m:GetChildren() == 0 then m:Destroy() return end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CastShadow = false
			-- (solid too: the plaza's things are walked round, not through)
			d.CanCollide = true
			d.CanQuery = true
		end
	end
	-- (a model takes its first part's frame as its pivot, often a turned cylinder: square it up)
	m.WorldPivot = CFrame.new((m:GetBoundingBox()).Position)
	pcall(function() m:ScaleTo(scale) end)
	m:PivotTo(cf)
	local box, size = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + Vector3.new(0, CENTRE.Y - (box.Position.Y - size.Y / 2), 0))
	m.Parent = parent
end

local RANGOLI = "rbxassetid://140263977505246"   -- art/ui/rangoli.py

local function rangoliPainted(f: Instance): boolean
	if RANGOLI == "rbxassetid://0" then return false end
	local p = part(f, Vector3.new(72, 0.1, 72), CFrame.new(CENTRE + Vector3.new(0, 0.06, 0)), Color3.new(1, 1, 1))
	p.Transparency = 1
	p.Name = "Rangoli"
	local d = Instance.new("Decal")
	d.Face = Enum.NormalId.Top
	d.Texture = RANGOLI
	d.Parent = p
	return true
end

local function rangoli(f: Instance)
	if rangoliPainted(f) then return end
	local n = 48
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local w = 2 * math.pi * 30 / n + 0.3
		part(f, Vector3.new(w, 0.1, 6), facing(30, a) + Vector3.new(0, 0.05, 0), FLAGS[i % #FLAGS + 1])
		-- white dots on both edges
		if i % 2 == 0 then
			for _, rr in ipairs({ 26.4, 33.6 }) do
				local d = part(f, Vector3.new(0.12, 1.1, 1.1), CFrame.new(at(rr, a, 0.07)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(244, 241, 232))
				d.Shape = Enum.PartType.Cylinder
				d.Size = Vector3.new(0.12, 1.1, 1.1)
			end
		end
	end
end

local function bench(f: Instance, cf: CFrame)
	-- (2026-10-23, the owner: "the benches at the centre are old") the new bench (BenchKit), its back
	-- where this one's was (cf's +Z)
	local okB, BenchKit = pcall(require, script.Parent:WaitForChild("BenchKit"))
	if okB and (BenchKit :: any).place(f, cf * CFrame.Angles(0, math.pi, 0), 1.12) then return end
	part(f, Vector3.new(10, 0.6, 2.4), cf * CFrame.new(0, 2.1, 0), WOOD, true)
	part(f, Vector3.new(10, 2.2, 0.5), cf * CFrame.new(0, 3.4, 1.3), WOOD, true)
	for _, x in ipairs({ -4, 4 }) do
		part(f, Vector3.new(0.6, 1.8, 2.2), cf * CFrame.new(x, 0.9, 0), Color3.fromRGB(60, 62, 70), true)
	end
end

-- a string of bunting hanging between two points, sagging in the middle
local function bunting(f: Instance, p0: Vector3, p1: Vector3, sag: number, seed: number)
	local span = (p1 - p0).Magnitude
	local n = math.max(2, math.floor(span / 3.2))
	local function point(t: number): Vector3
		return p0:Lerp(p1, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
	end
	local prev = point(0)
	for i = 1, n do
		local t = i / n
		local p = point(t)
		local mid = (prev + p) / 2
		part(f, Vector3.new(0.15, 0.15, (p - prev).Magnitude + 0.1), CFrame.lookAt(mid, p), Color3.fromRGB(240, 236, 228))
		if i < n then
			-- a pennant hanging point-down under the string
			local dir = (p - prev).Unit
			local flag = Instance.new("WedgePart")
			flag.Anchored = true
			flag.CanCollide = false
			flag.CanQuery = false
			flag.CanTouch = false
			flag.CastShadow = false
			flag.Material = Enum.Material.SmoothPlastic
			local set = if halloween() then SPOOKY_FLAGS else FLAGS
			flag.Color = set[(i + seed) % #set + 1]
			flag.Size = Vector3.new(0.1, 1.8, 1.4)
			local side = dir:Cross(Vector3.yAxis).Unit
			flag.CFrame = CFrame.fromMatrix(p - Vector3.new(0, 0.95, 0), side, -Vector3.yAxis) * CFrame.Angles(0, 0, 0)
			flag.Parent = f
		end
		prev = p
	end
end

-- seeded, so everyone sees the same "hand-placed" plaza
local rng = Random.new(20261016)
local function jitter(cf: CFrame, move: number, turn: number): CFrame
	return cf * CFrame.new(rng:NextNumber(-move, move), 0, rng:NextNumber(-move, move)) * CFrame.Angles(0, math.rad(rng:NextNumber(-turn, turn)), 0)
end

-- a model from the game's assets, sized to a height, standing on the floor at cf
local function asset(parent: Instance, path: string, cf: CFrame, height: number, solid: boolean): Model?
	local okM, Models = pcall(require, script.Parent:FindFirstChild("Models") :: ModuleScript)
	local tpl = okM and (Models :: any).get(path)
	if not tpl then return nil end
	local okP, m = pcall(function() return (Models :: any).place(tpl, nil, CFrame.new(), 1, solid) end)
	if not okP or not m then return nil end
	local _, size = m:GetBoundingBox()
	if size.Y > 0.01 then pcall(function() m:ScaleTo(m:GetScale() * height / size.Y) end) end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.CastShadow = true end
	end
	m:PivotTo(cf)
	local box, s2 = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + Vector3.new(0, cf.Position.Y - (box.Position.Y - s2.Y / 2), 0))
	m.Parent = parent
	return m
end

-- the floor: warm pavers instead of grey concrete
local function floor()
	local plaza = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("Plaza")
	if not plaza then return end
	local fl = plaza:FindFirstChild("PlazaFloor") :: BasePart?
	local trim = plaza:FindFirstChild("PlazaTrim") :: BasePart?
	if fl then
		fl.Material = Enum.Material.Pavement
		fl.Color = Color3.fromRGB(206, 178, 136)
	end
	if trim then
		trim.Material = Enum.Material.Brick
		trim.Color = Color3.fromRGB(168, 92, 62)
	end
	local plinth = plaza:FindFirstChild("Plinth") :: BasePart?
	if plinth then plinth.Color = Color3.fromRGB(150, 122, 92) end
end

local Players = game:GetService("Players")
local function groundAt(p: Vector3, skip: { Instance }): (number?, Instance?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex = table.clone(skip)
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then table.insert(ex, pl.Character) end
	end
	params.FilterDescendantsInstances = ex
	local hit = workspace:Raycast(Vector3.new(p.X, 120, p.Z), Vector3.new(0, -240, 0), params)
	if hit then return hit.Position.Y, hit.Instance end
	return nil, nil
end


-- the old sodium lamps step aside; a lantern on a post stands in each one's place. Returns the
-- lanterns' tops, for the bunting.
local function lamps(f: Instance): { Vector3 }
	local tops = {}
	local holder = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("NightLamps")
	-- (2026-10-22) the old lamps stood dead in the middle of each gap, where the walks out of the plaza
	-- run now: they step aside (hidden here, their light put out), and a pair of lanterns flanks every
	-- walk's mouth instead (HubPlan: the mouth leaves the plaza 18 deg round from each yard's line)
	if holder then
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
				d.CanCollide = false
				d.CanQuery = false
			elseif d:IsA("Light") then
				d.Range = 0
			end
		end
	end
	local holderF = Instance.new("Folder")
	holderF.Name = "Lanterns"
	holderF.Parent = f
	for k = 0, 7 do
		local th = k * math.pi / 4 + math.rad(18)
		local out = Vector3.new(math.cos(th), 0, math.sin(th))
		local side = Vector3.new(-out.Z, 0, out.X)
		for i, sd in ipairs({ -1, 1 }) do
			local p = CENTRE + out * 123.6 + side * sd * 6.3
			local gy = groundAt(p, { f }) or 0
			local base = Vector3.new(p.X, gy, p.Z)
			local new = asset(holderF, "Props/Lantern", CFrame.lookAt(base, base - side * sd), 22, true)
			if new and i == 2 then
				local b, s = new:GetBoundingBox()
				table.insert(tops, b.Position + Vector3.new(0, s.Y / 2 - 2.5, 0))
			end
		end
	end
	return tops
end

--==============================================================
-- (2026-10-16, second go) where things may stand, worked out from the place itself, not guessed:
--   the ground   a ray straight down finds what's under a spot; lawn pieces only go where that's
--                the lawn (Lobby.Ground.Land), and they're stood ON it (its top), not at the plaza's
--                height (which left them floating)
--   the clear    nothing goes within a margin of anything else that's there: the paths and their
--                kerbs (PlotPaths, built a moment after the plaza, so the scatter waits for them),
--                the yards, their fences, the plaza, the lamps, or a piece already placed
-- Clusters are seeded spots on the lawn ring, each tried a few times until one is clear; a piece
-- that can't find room is left out rather than forced in.
--==============================================================
local function isLawn(inst: Instance?): boolean
	return inst ~= nil and (inst.Name == "Land" or inst.Name == "FarLand")
end

--==============================================================
-- (2026-10-22, the owner: "the hub needs to not just have random straight lines ... fix the glitchy
-- connector paths ... everything should feel interconnected") The ground round the plaza is HubPark's
-- now, built from HubPlan: the walks out of the plaza, into every yard and on to the park, the bays,
-- the avenues and groves, the verges. What's left here is the plaza itself and the season.
--==============================================================
local okHP, HubPlan = pcall(function()
	return require(game:GetService("ReplicatedStorage"):WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("HubPlan"))
end)

local function makeScatter(f: Instance)
	local okP, HubPark = pcall(require, script.Parent:WaitForChild("HubPark"))
	if not okP then
		warn("[TyreCannon] HubPark:", HubPark)
		return nil, nil, nil
	end
	local ok, clear = pcall((HubPark :: any).build, f)
	if not ok then
		warn("[TyreCannon] HubPark build:", clear)
		return nil, nil, nil
	end
	return nil, clear, if okHP then (HubPlan :: any).gapAt else nil
end

-- October: jack-o'-lanterns by the lamps and the benches, and two scarecrows out on the lawn
local JACK_FACE = "rbxassetid://125218837989581"
-- (2026-10-16, the owner's own pumpkin: Assets/Props/Pumpkin, a carved mesh with its light inside;
-- the part-built ones looked bad) stood on the ground at `base`, its face toward base's front
-- (the model's face is its -Z; Models.place turns a model half round, so it's turned back here)
local function pumpkin(parent: Instance, base: CFrame, s: number, lit: boolean)
	local m = asset(parent, "Props/Pumpkin", base * CFrame.Angles(0, math.pi, 0), s * 1.25, true)
	if m and not lit then
		-- (a few lights, not one in every pumpkin)
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("Light") then d.Enabled = false end
		end
	end
	return m
end

-- (2026-10-23, the owner: the crow should fly away when you go near it) the crow on a scarecrow's arm
-- (its own meshes: Crow and WingL/WingR, hubkit.scarecrow): walk within a few strides and it opens its
-- wings and flaps off up and away from you, then circles back and lands on the arm again a little later
local function crowLife(model: Model)
	local body = model:FindFirstChild("Crow", true) :: BasePart?
	local wl = model:FindFirstChild("WingL", true) :: BasePart?
	local wr = model:FindFirstChild("WingR", true) :: BasePart?
	if not (body and wl and wr) then return end
	local RunService = game:GetService("RunService")
	local Players = game:GetService("Players")
	for _, p in ipairs({ body, wl, wr }) do
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	end
	-- its rest: the body's frame looking out along the arm (away from the post), the wings in it
	local post = model:GetPivot().Position
	local perch = body.Position
	local out = Vector3.new(perch.X - post.X, 0, perch.Z - post.Z)
	out = if out.Magnitude > 0.01 then out.Unit else Vector3.new(1, 0, 0)
	local rest = CFrame.lookAt(perch, perch + out)
	local bodyOff = rest:ToObjectSpace(body.CFrame)
	local wings = {}
	for _, w in ipairs({ wl, wr }) do
		local off = rest:ToObjectSpace(w.CFrame)
		local s = if off.Position.X >= 0 then 1 else -1
		-- the shoulder: where the wing meets the back, toward the middle of the body
		table.insert(wings, { part = w, off = off, s = s, shoulder = Vector3.new(off.Position.X * 0.25, off.Position.Y, off.Position.Z + body.Size.Magnitude * 0.08) })
	end
	local size = body.Size.Magnitude
	local state, t0, from, away = "perched", 0, perch, out
	local function pose(cf: CFrame, open: number, flap: number)
		local parts, cfs = { body }, { cf * bodyOff }
		for _, w in ipairs(wings) do
			local a = w.s * (open * 1.25 + flap)
			table.insert(parts, w.part)
			table.insert(cfs, cf * CFrame.new(w.shoulder) * CFrame.Angles(0, 0, a) * CFrame.new(-w.shoulder) * w.off)
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- a flight along a curve: up and away, or back down onto the arm
	local function along(u: number, a: Vector3, b: Vector3, lift: number): (Vector3, Vector3)
		local mid = a:Lerp(b, 0.5) + Vector3.new(0, lift, 0)
		local p = a:Lerp(mid, u):Lerp(mid:Lerp(b, u), u)
		local q = a:Lerp(mid, math.min(1, u + 0.02)):Lerp(mid:Lerp(b, math.min(1, u + 0.02)), math.min(1, u + 0.02))
		return p, q
	end
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not body.Parent then conn:Disconnect() return end
		local now = os.clock()
		if state == "perched" then
			local char = Players.LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - perch).Magnitude < 14 + size * 2 then
				-- off it goes, away from whoever came near
				local d = Vector3.new(perch.X - root.Position.X, 0, perch.Z - root.Position.Z)
				away = if d.Magnitude > 0.1 then d.Unit else out
				state, t0 = "off", now
			end
		elseif state == "off" then
			local u = math.clamp((now - t0) / 2.8, 0, 1)
			local target = perch + away * 70 + Vector3.new(0, 40, 0)
			local p, q = along(u * u, perch, target, 12)
			local dir = q - p
			local cf = if dir.Magnitude > 1e-3 then CFrame.lookAt(p, p + dir) else rest
			pose(cf * CFrame.Angles(0, 0, math.sin(now * 3) * 0.15), math.min(1, u * 6), math.sin(now * 26) * 0.75)
			if u >= 1 then
				state, t0 = "gone", now
				for _, x in ipairs({ body, wl, wr }) do x.LocalTransparencyModifier = 1 end
			end
		elseif state == "gone" then
			if now - t0 > 22 then
				state, t0 = "back", now
				from = perch + (-out) * 60 + out:Cross(Vector3.yAxis) * 40 + Vector3.new(0, 35, 0)
				for _, x in ipairs({ body, wl, wr }) do x.LocalTransparencyModifier = 0 end
			end
		elseif state == "back" then
			local u = math.clamp((now - t0) / 3.2, 0, 1)
			local e = 1 - (1 - u) * (1 - u)
			local p, q = along(e, from, perch, 6)
			local dir = Vector3.new(q.X - p.X, q.Y - p.Y, q.Z - p.Z)
			-- (it turns to face out along the arm as it settles)
			local face = if u < 0.85 and dir.Magnitude > 1e-3 then CFrame.lookAt(p, p + dir) else CFrame.lookAt(p, p + out)
			local open = if u < 0.8 then 1 else (1 - u) / 0.2
			pose(face, open, math.sin(now * (if u < 0.7 then 26 else 14)) * 0.75 * open)
			if u >= 1 then
				state = "perched"
				pose(rest, 0, 0)
			end
		end
	end)
end

local function scarecrow(parent: Instance, base: CFrame)
	-- (2026-10-22, the owner: the part-built one "looks genuinely terrible": its own model,
	-- Assets/Props/Scarecrow, facing the plaza, a lit jack-o'-lantern at its foot)
	local own = asset(parent, "Props/Scarecrow", base * CFrame.Angles(0, math.pi, 0), 11, true)
	if own then
		pumpkin(parent, base * CFrame.new(2.2, 0, -1.2) * CFrame.Angles(0, 0.3, 0), 2.4, true)
		pcall(crowLife, own)
		return
	end
	local m = Instance.new("Model")
	m.Name = "Scarecrow"
	local wood, straw = Color3.fromRGB(120, 84, 50), Color3.fromRGB(226, 188, 96)
	part(m, Vector3.new(0.6, 10, 0.6), base * CFrame.new(0, 5, 0), wood, true).Material = Enum.Material.Wood
	part(m, Vector3.new(7, 0.5, 0.5), base * CFrame.new(0, 7.4, 0), wood, false).Material = Enum.Material.Wood
	local shirt = part(m, Vector3.new(2.6, 2.8, 1.2), base * CFrame.new(0, 6.4, 0), Color3.fromRGB(150, 44, 40), true)
	shirt.Material = Enum.Material.Fabric
	for _, x in ipairs({ -2.3, 2.3 }) do
		part(m, Vector3.new(2.2, 1, 1), base * CFrame.new(x, 7.4, 0), Color3.fromRGB(70, 92, 140), false).Material = Enum.Material.Fabric
		part(m, Vector3.new(0.5, 0.9, 0.6), base * CFrame.new(x + (x > 0 and 1.3 or -1.3), 7.2, 0) * CFrame.Angles(0, 0, x > 0 and -0.5 or 0.5), straw, false)
	end
	-- its head is a tyre (the owner's call), facing the plaza
	local okM, Models = pcall(require, script.Parent:FindFirstChild("Models") :: ModuleScript)
	local tpl = okM and ((Models :: any).get("Tyres/Tyre_tractorlug") or (Models :: any).get("Wheel/Tyre"))
	if tpl then
		local head = (Models :: any).place(tpl, m, CFrame.new(), 1, false)
		local _, size = head:GetBoundingBox()
		local big = math.max(size.X, size.Y, size.Z)
		if big > 0 then pcall(function() head:ScaleTo(head:GetScale() * 2.6 / big) end) end
		head:PivotTo(base * CFrame.new(0, 8.9, 0))
	else
		local head = part(m, Vector3.new(2, 2, 2), base * CFrame.new(0, 8.9, 0), Color3.fromRGB(214, 190, 140), false)
		head.Shape = Enum.PartType.Ball
		head.Material = Enum.Material.Fabric
	end
	local brim = part(m, Vector3.new(0.25, 3.4, 3.4), base * CFrame.new(0, 9.8, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 44, 30), false)
	brim.Shape = Enum.PartType.Cylinder
	local crown = part(m, Vector3.new(1.4, 1.8, 1.8), base * CFrame.new(0, 10.5, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 44, 30), false)
	crown.Shape = Enum.PartType.Cylinder
	pumpkin(m, base * CFrame.new(1.6, 0, -1.4), 2.4, true)
	m.Parent = parent
end

local function october(f: Instance, clear, gapAt)
	if not halloween() or not clear or not gapAt then return end
	-- by each lamp: two or three pumpkins at its foot, one carved
	local lamps = f:FindFirstChild("Lanterns")
	for _, lamp in ipairs(if lamps then lamps:GetChildren() else {}) do
		if lamp:IsA("Model") then
			local cf = lamp:GetPivot()
			for k = 1, rng:NextInteger(2, 3) do
				local a = rng:NextNumber(0, math.pi * 2)
				local p = cf.Position + Vector3.new(math.cos(a) * rng:NextNumber(2.5, 4), 0, math.sin(a) * rng:NextNumber(2.5, 4))
				local s = rng:NextNumber(1.6, 2.6)
				local y = clear(p, s * 0.45, 0.2)
				if y then
					local face = CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(CENTRE.X, y, CENTRE.Z))
					pumpkin(f, face * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), s, k == 1)
				end
			end
		end
	end
	-- by each bench, a carved one on the plaza
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + math.rad(rng:NextNumber(7, 10))
		pumpkin(f, facing(43, a) * CFrame.Angles(0, math.pi, 0) + Vector3.new(0, 0, 0), rng:NextNumber(2, 2.6), true)
	end
	-- two scarecrows, out in two of the gardens' bulbs (beside the flowers, looking at the plaza)
	local made = 0
	for _ = 1, 30 do
		if made >= 2 then break end
		local k = if made == 0 then 1 else 5
		local q = gapAt(k, rng:NextNumber(150, 172), rng:NextNumber(-30, 30))
		local y = clear(q, 4, 3)
		if y then
			scarecrow(f, CFrame.lookAt(Vector3.new(q.X, y, q.Z), Vector3.new(CENTRE.X, y, CENTRE.Z)))
			made += 1
		end
	end
	-- jack-o'-lanterns among the roots of the trees along the walks (one tree in three), one in three lit
	local n = 0
	for _, tree in ipairs(f:GetChildren()) do
		local base = tree:IsA("Model") and tree:GetPivot().Position
		if base and string.find(tree.Name, "^Tree") and tree.Name ~= "TreeAshoka" and rng:NextNumber() < 0.34
			and (not okHP or (HubPlan :: any).pathDist(base) < 9) then
			for _ = 1, 1 do
				for _ = 1, 6 do
					local a = rng:NextNumber(0, math.pi * 2)
					local p = base + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(4, 7)
					local s = rng:NextNumber(1.8, 2.6)
					local y = clear(p, s * 0.5, 0.2)
					if y then
						n += 1
						local face = CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(CENTRE.X, y, CENTRE.Z))
						pumpkin(f, face * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0), s, n % 3 == 1)
						break
					end
				end
			end
		end
	end
	-- three little graveyards, out where the gardens open onto the park: crooked stones in a ragged
	-- row or two, a lantern-lit pumpkin among them
	for _, k in ipairs({ 0, 3, 6 }) do
		-- (off the gap's walk, on the side its meander leaves open, among the trees)
		local row0 = rng:NextNumber(298, 306)
		local side = if k % 2 == 0 then -1 else 1
		for i = 1, rng:NextInteger(4, 6) do
			local row = (i - 1) // 3
			local p = gapAt(k, row0 + row * 6 + rng:NextNumber(-0.8, 0.8), side * (24 + ((i - 1) % 3) * 5.5) + rng:NextNumber(-1, 1))
			local y = clear(p, 1.6, 0.3)
			if y then
				local face = CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(CENTRE.X, y, CENTRE.Z))
					* CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), 0) * CFrame.Angles(rng:NextNumber(-0.12, 0.08), 0, rng:NextNumber(-0.14, 0.14))
				-- (headstones mostly, a stone cross here and there)
				local cross = rng:NextNumber() < 0.3
				local stone = asset(f, if cross then "Props/GraveCross" else "Props/Gravestone", face * CFrame.Angles(0, math.pi, 0),
					if cross then rng:NextNumber(4.6, 5.4) else rng:NextNumber(3.6, 4.6), true)
				if not stone then
					local s = part(f, Vector3.new(2.6, 3.6, 0.7), face * CFrame.new(0, 1.6, 0), Color3.fromRGB(128, 128, 136), true)
					s.Material = Enum.Material.Slate
				end
			end
		end
		local p = gapAt(k, row0 - 4, side * rng:NextNumber(22, 30))
		local y = clear(p, 1.2, 0.2)
		if y then pumpkin(f, CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(CENTRE.X, y, CENTRE.Z)), 2.2, true) end
	end
	-- bats wheeling round the trophy pillar, high up, flapping (client only, a few parts each)
	local bats = Instance.new("Folder")
	bats.Name = "Bats"
	bats.Parent = f
	local list = {}
	for i = 1, 9 do
		local body = part(bats, Vector3.new(0.7, 0.6, 1.1), CFrame.new(), Color3.fromRGB(26, 22, 30), false)
		body.Material = Enum.Material.SmoothPlastic
		local wings = {}
		for _, side in ipairs({ -1, 1 }) do
			local w = Instance.new("WedgePart")
			w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow = true, false, false, false, false
			w.Color = Color3.fromRGB(34, 28, 40)
			w.Size = Vector3.new(0.1, 0.9, 1.6)
			w.Parent = bats
			table.insert(wings, { part = w, side = side })
		end
		table.insert(list, { body = body, wings = wings, r = rng:NextNumber(26, 60), h = rng:NextNumber(44, 72),
			speed = rng:NextNumber(0.25, 0.45) * (if i % 3 == 0 then -1 else 1), phase = rng:NextNumber(0, 6.28), flap = rng:NextNumber(9, 13) })
	end
	local RunService = game:GetService("RunService")
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not bats.Parent then conn:Disconnect() return end
		local t = os.clock()
		local parts, cfs = {}, {}
		for _, b in ipairs(list) do
			local a = b.phase + t * b.speed
			local bob = math.sin(t * 1.3 + b.phase) * 3
			local pos = CENTRE + Vector3.new(math.cos(a) * b.r, b.h + bob, math.sin(a) * b.r)
			local ahead = CENTRE + Vector3.new(math.cos(a + 0.05 * math.sign(b.speed)) * b.r, b.h + bob, math.sin(a + 0.05 * math.sign(b.speed)) * b.r)
			local cf = CFrame.lookAt(pos, ahead)
			table.insert(parts, b.body)
			table.insert(cfs, cf)
			local beat = math.sin(t * b.flap + b.phase) * 0.7
			for _, w in ipairs(b.wings) do
				table.insert(parts, w.part)
				table.insert(cfs, cf * CFrame.new(w.side * 0.35, 0, 0) * CFrame.Angles(0, 0, w.side * beat) * CFrame.new(w.side * 0.8, 0, 0) * CFrame.Angles(0, 0, w.side * math.pi / 2))
			end
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

local function scatter(f: Instance)
	-- (the paths are built just after the plaza: wait for them, so nothing lands on one)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 15 do
			local paths = workspace:FindFirstChild("PlotPaths")
			if paths and #paths:GetDescendants() > 20 and f.Parent then break end
			task.wait(0.5)
		end
		task.wait(0.5)
		local placed, clear, gapAt = makeScatter(f)
		october(f, clear, gapAt)
		-- the lost lug nuts, hidden round the park (HubHunt)
		local okH, Hunt = pcall(require, script.Parent:WaitForChild("HubHunt"))
		if okH then task.spawn((Hunt :: any).start, f) end
		-- the hub's life without people: swaying trees, birds, butterflies, kites (HubLife)
		local okL, Life = pcall(require, script.Parent:WaitForChild("HubLife"))
		if okL then pcall((Life :: any).start, f) end
		local _ = placed
	end)
end

function PlazaLife.build(parent: Instance): Folder?
	if workspace:GetAttribute("PlazaLife") == false then return nil end
	local f = Instance.new("Folder")
	f.Name = "PlazaLife"
	floor()
	rangoli(f)
	-- planters between the boards, benches in front of them (each nudged a little: not stamped out)
	for k = 0, 7 do
		local a = (k + 0.5) / 8 * math.pi * 2
		decor(f, "planter", jitter(facing(40, a), 1.2, 12), 1.7 * rng:NextNumber(0.92, 1.08))
	end
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2
		bench(f, jitter(facing(40, a), 0.8, 6))
	end
	local tops = lamps(f)
	-- bunting from the pillar's cap to each street lamp
	if #tops > 0 and workspace:GetAttribute("TrophyPillar") ~= false then
		for i, top in ipairs(tops) do
			local flat = Vector3.new(top.X - CENTRE.X, 0, top.Z - CENTRE.Z)
			local corner = CENTRE + Vector3.new(if flat.X >= 0 then 14 else -14, 46.4, if flat.Z >= 0 then 14 else -14)
			bunting(f, corner, top, 9, i)
		end
	end
	-- a chai corner by the spawn side, a swing and a tyre pyramid across from it
	decor(f, "chaicart", facing(84, math.rad(118)), 1.8)
	decor(f, "charpai", facing(80, math.rad(104)) * CFrame.Angles(0, 0.4, 0), 1.8)
	decor(f, "charpai", facing(84, math.rad(132)) * CFrame.Angles(0, -0.3, 0), 1.8)
	decor(f, "matka", facing(88, math.rad(144)), 1.8)
	decor(f, "tyreswing", facing(84, math.rad(-62)), 1.8)
	decor(f, "tyrepyramid", facing(86, math.rad(-80)), 1.8)
	decor(f, "toran", facing(96, math.rad(90)), 2.4)
	scatter(f)
	f.Parent = parent
	return f
end

return PlazaLife
