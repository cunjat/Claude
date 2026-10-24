--!strict
-- TYRE CANNON :: HubPark
-- Builds the hub's ground from HubPlan (2026-10-22, the owner, with a photo of a park walk: "paths, the
-- greenery surrounding the paths, trees a little further back but slightly more dense ... fix the
-- glitchy connector paths ... everything should feel interconnected"). Worked in layers, the way a
-- park is laid out, each layer only where the plan says it may stand:
--   1 the walks     HubPlan's curves drawn as short pitched slabs with a round joint at every bend (a
--                   world-tiled material, so the stone runs on unbroken), on a darker edging, in the
--                   park ring's sandstone so the whole lobby is one paving. Flush: ramped into the
--                   plaza's brick ring and the yards' edging.
--   2 the furniture bench pull-outs off the gap walks (a paved bay, two benches facing the walk, a
--                   lamp at one end, a bin at the other, in sight of the next); lamps along the walks
--                   on alternate sides; a planted island in every fork; lamps at every yard's way in
--   3 the trees     an avenue each side of every gap walk, staggered, trunks set ~5 back from the edge
--                   so the canopies lean over the walk; a looser second row behind; then groves out
--                   in the open ground (Poisson-spaced, canopies apart, never over a full-grown yard)
--   4 the verges    grass along the walks' edges in clumps, flowers at the bays, the island and the
--                   mouths, shrubs and long grass round the roots
-- Built on the client into the plaza's folder (it hides with the lobby during a run), from fixed seeds
-- so everyone sees the same park. A yard's way in moves when it's claimed (its building takes the
-- old line), so that walk is redrawn then; nothing else is planted on either line.
--   HubPark.build(folder) -> clear(p, r, margin): number?   (yields)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HubPlan = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("HubPlan"))
local Models = require(script.Parent:WaitForChild("Models"))

local HubPark = {}

local C = HubPlan.CENTRE
local STONE = Color3.fromRGB(214, 188, 146)     -- LobbyPark's sandstone
local EDGING = Color3.fromRGB(176, 150, 112)    -- its kerb
local TUFTS = { "Nature/GrassTuftA", "Nature/GrassTuftA", "Nature/GrassTuftB" }
local FLOWERS = { "Nature/FlowersMarigold", "Nature/FlowersPink", "Nature/FlowersMustard" }
-- each gap's avenue: the neck (between the yards) in columnar ashokas, the open ground in a broadleaf
-- (the pale apple reads as a fruit tree, an accent: it's kept to the gardens, not the avenues)
local BROAD = { "TreeNeem", "TreeMango2" }
local TREE_SCALE = { TreeNeem = 1.75, TreeMango2 = 1.7, TreeApple = 1.85, TreeAshoka = 1.3 }
local function spread(name: string, scale: number): number
	return (if name == "TreeAshoka" then 2 else 7) * scale
end

local function flat(v: Vector3): Vector3 return Vector3.new(v.X, 0, v.Z) end

local function newPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, collide: boolean, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Pavement
	p.Color = color
	if shape then p.Shape = shape end
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

--==============================================================
-- 1 the walks
--==============================================================
-- merge runs that barely turn (fewer, longer slabs), keep every real bend
local function simplify(pts: { Vector3 }): { Vector3 }
	local out = { pts[1] }
	local i = 1
	while i < #pts do
		local j = i + 1
		local d0 = flat(pts[j] - pts[i]).Unit
		local slope0 = (pts[j].Y - pts[i].Y) / math.max(0.01, flat(pts[j] - pts[i]).Magnitude)
		while j < #pts do
			local nxt = pts[j + 1]
			local d1 = flat(nxt - pts[j]).Unit
			local slope1 = (nxt.Y - pts[j].Y) / math.max(0.01, flat(nxt - pts[j]).Magnitude)
			if d0:Dot(d1) < math.cos(math.rad(1.2)) or math.abs(slope1 - slope0) > 0.02 or flat(nxt - pts[i]).Magnitude > 14 then break end
			j += 1
		end
		table.insert(out, pts[j])
		i = j
	end
	return out
end

-- one walk: slabs pitched to its heights, a disc at every bend, on a wider darker edging. `parity`
-- lifts every other slab a hair so overlapping corners never shimmer
local function drawWalk(parent: Instance, path: any)
	local pts = simplify(path.pts)
	local w = path.w
	for layer = 1, 2 do
		local width = if layer == 1 then w + 1.3 else w
		local drop = if layer == 1 then 0.035 else 0
		local color = if layer == 1 then EDGING else STONE
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local top = Vector3.new(0, -drop + (if layer == 2 and i % 2 == 0 then 0.006 else 0), 0)
			local len = (b - a).Magnitude
			if len > 0.05 then
				local thick = math.max(a.Y, b.Y) + 0.55
				local cf = CFrame.lookAt((a + b) / 2 + top, b + top) * CFrame.new(0, -thick / 2, 0)
				local p = newPart(parent, Vector3.new(width, thick, len), cf, color, layer == 2)
				p.Name = if layer == 2 then "Walk" else "Edging"
			end
			if i > 1 then
				local prev = pts[i - 1]
				local turn = flat(a - prev).Unit:Dot(flat(b - a).Unit)
				local onRamp = math.abs(a.Y - prev.Y) > 0.02 or math.abs(b.Y - a.Y) > 0.02
				if turn < 0.99998 and not (onRamp and turn > math.cos(math.rad(4))) then
					local thick = a.Y + 0.55
					local d = newPart(parent, Vector3.new(thick, width, width),
						CFrame.new(a.X, a.Y - drop - 0.012 - thick / 2, a.Z) * CFrame.Angles(0, 0, math.pi / 2), color, false, Enum.PartType.Cylinder)
					d.Name = "Joint"
				end
			end
		end
	end
end

--==============================================================
-- placing things
--==============================================================
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

local function isLawn(inst: Instance?): boolean
	return inst ~= nil and (inst.Name == "Land" or inst.Name == "FarLand")
end

-- a piece of the park's set stood on the ground at p (p.Y the ground): `how` "tree" (soft canopy, a
-- trunk you bump into), "solid", or nil (soft, no shadow: grass and flowers)
local function natural(f: Instance, path: string, p: Vector3, yaw: number, scale: number, how: string?): Model?
	local tpl = Models.get(path)
	if not tpl then return nil end
	local okP, m = pcall(function()
		return Models.place(tpl, nil :: any, CFrame.new(p) * CFrame.Angles(0, yaw, 0), scale, how == "solid")
	end)
	if not okP or not m then return nil end
	local box, s = m:GetBoundingBox()
	local sink = if how == nil then 0.12 elseif how == "tree" then 0.3 else 0
	m:PivotTo(m:GetPivot() + Vector3.new(0, p.Y - sink - (box.Position.Y - s.Y / 2), 0))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.CastShadow = how ~= nil end
	end
	if how == "tree" then
		local w = math.clamp(math.min(s.X, s.Z) * 0.09, 1.4, 3.6)
		local h = s.Y * 0.5
		local trunk = Instance.new("Part")
		trunk.Name = "TrunkCollider"
		trunk.Shape = Enum.PartType.Cylinder
		trunk.Size = Vector3.new(h, w, w)
		trunk.CFrame = CFrame.new(p + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		trunk.Anchored = true
		trunk.Transparency = 1
		trunk.CanTouch = false
		trunk.Parent = m
	end
	m.Parent = f
	return m
end

-- a lamp on the walks: lit at dusk with the rest (DayNight)
local function lamp(f: Instance, p: Vector3, face: Vector3)
	local y = groundAt(p, { f }) or 0
	local m = natural(f, "Park/ParkLamp", Vector3.new(p.X, y, p.Z), math.atan2(-face.X, -face.Z), 1.15, "solid")
	local glow = m and m:FindFirstChild("Glow", true) :: BasePart?
	if glow then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 206, 140)
		light.Range = 22
		light.Brightness = 1.3
		light.Shadows = false
		light.Enabled = false
		light.Parent = glow
		local okD, DayNight = pcall(require, script.Parent:FindFirstChild("DayNight") :: ModuleScript)
		local dn = okD and (DayNight :: any).current
		if dn then dn:addLamp(light) end
	end
end

--==============================================================
-- the build
--==============================================================
function HubPark.build(f: Instance)
	local placed: { { p: Vector3, r: number } } = {}
	local canopies: { { p: Vector3, r: number } } = {}
	local anchors: { { p: Vector3, r: number } } = {}
	local walks = Instance.new("Folder")
	walks.Name = "Walks"
	walks.Parent = f

	-- clear: on the lawn, in the plan's free ground, apart from what's already standing
	local function clear(p: Vector3, r: number, margin: number): number?
		if not HubPlan.free(p, r * 0.5 + margin) then return nil end
		local y, under = groundAt(p, { f })
		if not y or not isLawn(under) then return nil end
		for _, e in ipairs(placed) do
			if (flat(e.p - p)).Magnitude < e.r + r + 0.4 then return nil end
		end
		return y
	end
	local function claim(p: Vector3, r: number)
		table.insert(placed, { p = p, r = r })
	end
	-- a tree, if its trunk has room, its canopy stays clear of the yards and of other canopies
	local function tree(name: string, p: Vector3, scale: number, yaw: number, pathPad: number?): Model?
		local reach = spread(name, scale)
		if HubPlan.yardDist(p) < reach * 0.75 + 1 then return nil end
		if HubPlan.pathDist(p) < (pathPad or 4) then return nil end
		for _, c in ipairs(canopies) do
			if (flat(c.p - p)).Magnitude < (c.r + reach) * 0.78 then return nil end
		end
		local y = clear(p, 2.4, 0.5)
		if not y then return nil end
		claim(p, 2.6)
		table.insert(canopies, { p = p, r = reach })
		table.insert(anchors, { p = p, r = 2.6 })
		return natural(f, "Nature/" .. name, Vector3.new(p.X, y, p.Z), yaw, scale, "tree")
	end
	local function piece(path: string, p: Vector3, yaw: number, scale: number, how: string?, foot: number, pathPad: number?): Model?
		if pathPad and HubPlan.pathDist(p) < pathPad then return nil end
		local y = clear(p, foot, if how then 0.6 else 0.1)
		if not y then return nil end
		claim(p, foot)
		if how then table.insert(anchors, { p = p, r = foot }) end
		return natural(f, path, Vector3.new(p.X, y, p.Z), yaw, scale, how)
	end
	local function flowers(g: Random, path: string, c: Vector3, n: number, rx: number, rz: number, turn: number)
		for _ = 1, n do
			local u = g:NextNumber() ^ 0.7
			local a = g:NextNumber(0, math.pi * 2)
			local x, z = math.cos(a) * rx * u, math.sin(a) * rz * u
			local q = c + Vector3.new(x * math.cos(turn) - z * math.sin(turn), 0, x * math.sin(turn) + z * math.cos(turn))
			piece(path, q, g:NextNumber(0, math.pi * 2), g:NextNumber(1.6, 2.4), nil, 0.7, 0.4)
		end
	end

	--------------------------------------------------------------
	-- 1 the walks (the yards' ways in drawn per yard, redrawn when one is claimed)
	--------------------------------------------------------------
	local plots = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("Plots")
	local function plotOf(k: number): Instance?
		return plots and plots:FindFirstChild("Plot" .. (k + 1))
	end
	local function ownedK(k: number): boolean
		local plot = plotOf(k)
		local tier = plot and tonumber(plot:GetAttribute("V2_Tier")) or 0
		return plot ~= nil and plot:GetAttribute("V2_Owner") ~= nil and (tier or 0) >= 1
	end
	local yardWalks: { [number]: Folder } = {}
	local function drawYard(k: number)
		local owned = {}
		owned[k] = ownedK(k)
		for _, path in ipairs(HubPlan.paths(owned)) do
			if path.kind == "yard" and path.k == k then
				local old = yardWalks[k]
				local fo = Instance.new("Folder")
				fo.Name = "Yard" .. k
				drawWalk(fo, path)
				fo.Parent = walks
				yardWalks[k] = fo
				if old then old:Destroy() end
			end
		end
	end
	local paths = HubPlan.paths(nil)
	for _, path in ipairs(paths) do
		if path.kind ~= "yard" then drawWalk(walks, path) end
	end
	for k = 0, 7 do
		drawYard(k)
		local plot = plotOf(k)
		if plot then
			local last = ownedK(k)
			local function check()
				local now = ownedK(k)
				if now ~= last then
					last = now
					drawYard(k)
				end
			end
			plot:GetAttributeChangedSignal("V2_Owner"):Connect(check)
			plot:GetAttributeChangedSignal("V2_Tier"):Connect(check)
		end
	end
	task.wait()

	--------------------------------------------------------------
	-- 2 the furniture
	--------------------------------------------------------------
	local byId = {}
	for _, path in ipairs(paths) do byId[path.id] = path end
	-- a point and its frame `s` studs along a walk
	local function along(path: any, s: number): (Vector3, Vector3)
		local pts = path.pts
		local acc = 0
		for i = 1, #pts - 1 do
			local seg = flat(pts[i + 1] - pts[i]).Magnitude
			if acc + seg >= s or i == #pts - 1 then
				local t = math.clamp((s - acc) / math.max(seg, 0.01), 0, 1)
				local p = pts[i]:Lerp(pts[i + 1], t)
				return Vector3.new(p.X, 0, p.Z), flat(pts[i + 1] - pts[i]).Unit
			end
			acc += seg
		end
		return flat(pts[#pts]), Vector3.new(1, 0, 0)
	end
	local function lengthOf(path: any): number
		local acc = 0
		for i = 1, #path.pts - 1 do acc += flat(path.pts[i + 1] - path.pts[i]).Magnitude end
		return acc
	end
	local function rOf(p: Vector3): number return flat(p - C).Magnitude end

	local bays: { { p: Vector3 } } = {}
	for k = 0, 7 do
		local g = Random.new(20261022 + k * 131)
		local gap = byId["gap" .. k]
		local mouth = byId["mouth" .. k]
		local L = lengthOf(gap)
		local s = if k % 2 == 0 then 1 else -1
		-- the bays: two along the open stretch, on alternate sides, looking across the walk
		for b, frac in ipairs({ 0.5, 0.82 }) do
			local at, fwd = along(gap, L * frac + g:NextNumber(-4, 4))
			local side = Vector3.new(-fwd.Z, 0, fwd.X) * (if b == 1 then -s else s)
			local depth = 4.4
			local centre = at + side * (gap.w / 2 + depth / 2 - 0.2)
			local y = groundAt(centre, { f }) or 0
			if HubPlan.yardDist(centre) > 8 then
				local face = CFrame.lookAt(Vector3.new(centre.X, y, centre.Z), Vector3.new(centre.X, y, centre.Z) - side)
				local pad = newPart(walks, Vector3.new(12, 0.55 + HubPlan.GRADE - 0.01, depth), face * CFrame.new(0, (HubPlan.GRADE - 0.01 - 0.55) / 2, 0), STONE, true)
				pad.Name = "Bay"
				local edge = newPart(walks, Vector3.new(13.3, 0.5 + HubPlan.GRADE - 0.045, depth + 0.65), face * CFrame.new(0, (HubPlan.GRADE - 0.045 - 0.5) / 2, 0.32), EDGING, false)
				edge.Name = "Edging"
				claim(centre, 7)
				table.insert(bays, { p = centre })
				-- (2026-10-23, the owner: bigger benches you can sit on) one of the new benches across the bay
				-- (BenchKit), or the park pack's two side by side if it isn't imported
				local BenchKit = require(script.Parent:WaitForChild("BenchKit"))
				local bp = (face * CFrame.new(0, 0, 0.9)).Position
				local yaw = math.atan2(side.X, side.Z) + math.pi
				if not BenchKit.place(f, CFrame.new(bp.X, y + HubPlan.GRADE - 0.01, bp.Z) * CFrame.Angles(0, yaw, 0), 1) then
					for _, x in ipairs({ -2.9, 2.9 }) do
						local bq = (face * CFrame.new(x, 0, 0.9)).Position
						natural(f, "Park/Bench", Vector3.new(bq.X, y + HubPlan.GRADE - 0.01, bq.Z), yaw, 1, "solid")
					end
				end
				lamp(f, (face * CFrame.new(-7.4, 0, 1.6)).Position, side)
				natural(f, "Park/Bin", (face * CFrame.new(5.5, 0, 1.3)).Position + Vector3.new(0, y + HubPlan.GRADE - (face.Position.Y), 0), g:NextNumber(0, 6.28), 1.1, "solid")
				-- flowers behind the benches, as if planted there
				flowers(g, FLOWERS[(k + b) % #FLOWERS + 1], (face * CFrame.new(g:NextNumber(-3, 3), 0, depth / 2 + 2.2)).Position, g:NextInteger(7, 11), 5, 1.6, math.atan2(fwd.Z, fwd.X))
			end
		end
		-- lamps up the gap walk, on alternate sides, every ~28 studs, not by a bay
		local sAt = 18
		local flip = 1
		while sAt < L - 10 do
			local at, fwd = along(gap, sAt)
			local near = false
			for _, b in ipairs(bays) do
				if (flat(b.p - at)).Magnitude < 14 then near = true end
			end
			if not near and rOf(at) > 150 then
				local side = Vector3.new(-fwd.Z, 0, fwd.X) * flip
				local p = at + side * (gap.w / 2 + 1.7)
				if HubPlan.yardDist(p) > 2 then
					lamp(f, p, -side)
					claim(p, 1)
					flip = -flip
				end
			end
			sAt += g:NextNumber(25, 31)
		end
		-- the fork's island: a bed of flowers between the two branches, edged in shrubs
		local fork = mouth.pts[#mouth.pts]
		local outDir = flat(fork - mouth.pts[1]).Unit
		-- (out along the fork until the branches have parted enough to hold it)
		local isle = fork + outDir * 12
		for d = 12, 34, 2 do
			local q = fork + outDir * d
			if HubPlan.pathDist(q) >= 4.6 then
				isle = q
				break
			end
		end
		-- (2026-10-24, the owner: the tyre planter from the plaza in place of the old round beds)
		local okBed = piece(if Models.get("Roadside/RoadPlanter") then "Roadside/RoadPlanter" else "Park/FlowerBed", isle, math.atan2(outDir.X, outDir.Z), 0.9, "solid", 3.4, 2.6)
		if not okBed then flowers(g, FLOWERS[k % #FLOWERS + 1], isle, 10, 3, 2, 0) end
		-- the mouth: drifts of flowers either side as it leaves the plaza
		for _, sd in ipairs({ -1, 1 }) do
			local side = Vector3.new(-outDir.Z, 0, outDir.X) * sd
			flowers(g, FLOWERS[(k + 1) % #FLOWERS + 1], mouth.pts[1] + outDir * 10 + side * 11.5, g:NextInteger(8, 12), 4, 2, math.atan2(outDir.Z, outDir.X))
		end
		-- a lamp at the yard's way in, on the street-fence side (the other side is the building's)
		local frame = HubPlan.plotFrame(k)
		local wayIn = frame:PointToWorldSpace(Vector3.new(-41, 0, 23.8))
		if HubPlan.pathDist(wayIn) > 0.8 and HubPlan.yardDist(wayIn) > 1 then
			lamp(f, wayIn, frame.RightVector)
			claim(wayIn, 1)
		end
		task.wait()
	end

	--------------------------------------------------------------
	-- 3 the trees
	--------------------------------------------------------------
	for k = 0, 7 do
		local g = Random.new(20261122 + k * 173)
		local gap = byId["gap" .. k]
		local L = lengthOf(gap)
		local broad = BROAD[k % #BROAD + 1]
		local second = BROAD[(k + 1) % #BROAD + 1]
		-- the avenue: staggered either side, trunks ~5 back from the edge
		local sAt = 14
		local side = if k % 2 == 0 then 1 else -1
		while sAt < L - 6 do
			local at, fwd = along(gap, sAt)
			local r = rOf(at)
			if r > 192 then
				local name = if r < 248 then "TreeAshoka" else broad
				local sc = TREE_SCALE[name] * g:NextNumber(0.86, 1.1)
				-- (a broadleaf's canopy hangs ~10 up: its trunk stands back so the canopy just reaches the
				-- walk's edge, or a player's camera walks into the leaves; the slim ashoka stands close)
				local back = if name == "TreeAshoka" then g:NextNumber(4.2, 6.2) else spread(name, sc) - 1 + g:NextNumber(0, 2.2)
				local nrm = Vector3.new(-fwd.Z, 0, fwd.X) * side
				tree(name, at + nrm * (gap.w / 2 + back), sc, g:NextNumber(0, 6.28), back - 0.6)
				-- (now and then a pair across the walk, as avenues are planted)
				if g:NextNumber() < 0.3 then
					tree(name, at - nrm * (gap.w / 2 + back) + fwd * g:NextNumber(-2, 2), sc * g:NextNumber(0.9, 1.05), g:NextNumber(0, 6.28), back - 0.6)
				end
				side = -side
			end
			sAt += if r < 248 then g:NextNumber(11, 15) else g:NextNumber(14, 19)
		end
		-- the second row: further back, closer together, mixed
		sAt = 20
		while sAt < L - 6 do
			local at, fwd = along(gap, sAt)
			if rOf(at) > 232 then
				for _, sd in ipairs({ -1, 1 }) do
					if g:NextNumber() < 0.8 then
						local name = if g:NextNumber() < 0.6 then second else broad
						local sc = TREE_SCALE[name] * g:NextNumber(0.72, 0.95)
						local nrm = Vector3.new(-fwd.Z, 0, fwd.X) * sd
						tree(name, at + nrm * (gap.w / 2 + spread(name, sc) + g:NextNumber(9, 14)) + fwd * g:NextNumber(-3, 3), sc, g:NextNumber(0, 6.28), 12)
					end
				end
			end
			sAt += g:NextNumber(10, 14)
		end
		-- groves out in the open ground: Poisson-spaced by canopy, well back from the walks
		local tries = 0
		local made = 0
		while tries < 90 and made < 7 do
			tries += 1
			local p = HubPlan.gapAt(k, g:NextNumber(236, 328), g:NextNumber(-70, 70))
			local name = if g:NextNumber() < 0.2 then "TreeApple" elseif g:NextNumber() < 0.6 then broad else second
			if tree(name, p, TREE_SCALE[name] * g:NextNumber(0.75, 1.05), g:NextNumber(0, 6.28), 16) then made += 1 end
		end
		-- the garden by the next yard's building: a fruit tree or two and a bed
		for _ = 1, 12 do
			local p = HubPlan.gapAt(k, g:NextNumber(140, 178), g:NextNumber(4, 16))
			if tree("TreeApple", p, TREE_SCALE.TreeApple * g:NextNumber(0.7, 0.85), g:NextNumber(0, 6.28), 4) then break end
		end
		task.wait()
	end

	--------------------------------------------------------------
	-- 4 the verges: grass along every walk's edge in clumps; shrubs and long grass round the roots
	--------------------------------------------------------------
	local g = Random.new(20261222)
	for _, path in ipairs(paths) do
		local L = lengthOf(path)
		local sAt = g:NextNumber(1, 4)
		while sAt < L do
			local at, fwd = along(path, sAt)
			if g:NextNumber() < 0.6 then
				local sd = if g:NextNumber() < 0.5 then -1 else 1
				local nrm = Vector3.new(-fwd.Z, 0, fwd.X) * sd
				local c = at + nrm * (path.w / 2 + 0.65 + g:NextNumber(0.2, 1.3))
				for _ = 1, g:NextInteger(2, 4) do
					local q = c + fwd * g:NextNumber(-1.4, 1.4) + nrm * g:NextNumber(-0.25, 0.9)
					piece(TUFTS[g:NextInteger(1, #TUFTS)], q, g:NextNumber(0, 6.28), g:NextNumber(1.2, 1.8), nil, 0.5, 0.25)
				end
			end
			sAt += g:NextNumber(3.5, 7)
		end
	end
	local nAnchors = #anchors
	for i = 1, nAnchors do
		local an = anchors[i]
		-- (2026-10-24, the owner: "remove the poo bushes") no blob shrubs round the roots
		if false then
			local a = g:NextNumber(0, math.pi * 2)
			piece("Nature/Shrub", an.p + Vector3.new(math.cos(a), 0, math.sin(a)) * (an.r + g:NextNumber(1.6, 2.8)), g:NextNumber(0, 6.28), g:NextNumber(1.3, 2), "solid", 1.8, 1.5)
		end
		if g:NextNumber() < 0.7 then
			local a0 = g:NextNumber(0, math.pi * 2)
			for j = 1, g:NextInteger(2, 4) do
				local a = a0 + j * g:NextNumber(0.5, 1.1)
				piece(TUFTS[g:NextInteger(1, #TUFTS)], an.p + Vector3.new(math.cos(a), 0, math.sin(a)) * (an.r + g:NextNumber(0.8, 2.4)), g:NextNumber(0, 6.28), g:NextNumber(1.4, 2.1), nil, 0.5, 0.4)
			end
		end
		if i % 60 == 0 then task.wait() end
	end
	return clear
end

return HubPark
