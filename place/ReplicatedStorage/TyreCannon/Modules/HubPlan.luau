--!strict
-- TYRE CANNON :: HubPlan
-- The hub's ground plan (2026-10-22, the owner: "the hub needs to not just have random straight lines
-- ... paths, the greenery surrounding the paths, trees a little further back but slightly more dense
-- ... fix the glitchy connector paths ... keep in mind the size of the plots ... everything should feel
-- interconnected"). One plan, worked out from the lobby's fixed geometry (not guessed), shared by the
-- client, which builds it (HubPark), and the server, which hides the hunt's finds on it (HubHunt).
--
-- What's fixed (measured in the place, 2026-10-22):
--   the plaza   floor to r 110 (top 2), brick ring to r 118 (top 1.2)
--   the yards   eight at r 204, every 45 deg from +X (Plot1 at 0). In plot space x runs out from the
--               plaza and z round it (+z = +theta). Floor x -33 (fixed) to 73..104 (stage 1..5), z +-38
--               to +-60, edging out to x -36 (top 1.2), the fence on z +-(z1) and past x1.
--               An owned yard's building stands in front of it, toward the plaza: x -33 to -68.5 at
--               stage 3+ (GarageBay, 34 deep, 48 wide), z -38..10; its props further out (to x -80),
--               the tier-4 gantry hoist at x -75, z 16. The way in is between the building and the
--               front fence (owned: fence from z 24, so z 10..24, centre 17) or between the posts of an
--               unclaimed yard (z 5.6..17, centre 11.3).
--   the park    LobbyPark's footpath ring, r 338, 7 wide (top 0.2), its inner kerb open at the
--               centre of every gap
--
-- The paths, a hierarchy after park practice (the direct routes people want are the main walks; the
-- others wind past things worth stopping for; curves are gentle, never wiggles, or people cut across):
--   mouth k    leaves the plaza between yards k and k+1 (8 wide, two lanterns), out to a fork
--   yard k     from the fork, an S into yard k's way in (8 wide)
--   gap k      from the fork, out between the yards (straight through the pinch where two full-grown
--              yards come within ~16 studs of each other), then meandering through the open ground to
--              the park's ring (6 wide)
-- So every yard is on a loop with the plaza and the park, and the park's ring joins all the gaps.
-- Every walk is flush: ramped into the plaza's brick ring and the yards' edging, on the lawn just
-- proud of the grass. No kerbs, no steps.
--
--   HubPlan.paths(owned?)       -> { { id, kind, k, w, pts = { Vector3 (Y = the walk's top) } } }
--   HubPlan.pathDist(p)         -> distance from p to the nearest walk's edge (negative: on it), path
--   HubPlan.yardDist(p)         -> how far p is outside every full-grown yard, building and the plaza
--   HubPlan.free(p, pad)        -> p stands clear of the walks, the yards, the plaza and the ring by pad
--   HubPlan.gapAt(k, r, off)    -> a point r out along gap k's centre line, off to its side
--   HubPlan.spots()             -> the hunt's hiding places (deterministic)

local HubPlan = {}

local C = Vector3.new(-6000, 0, 6000)
HubPlan.CENTRE = C
HubPlan.PLAZA_R = 118
HubPlan.RING_R = 338
HubPlan.RING_W = 7
HubPlan.YARD_R = 204
HubPlan.GRADE = 0.14           -- a walk's top out on the lawn (the lawn's top is 0)
HubPlan.EDGE = 1.2             -- the plaza's brick ring and the yards' edging
HubPlan.MAIN_W = 8
HubPlan.GAP_W = 6
local RAMP = 10                -- studs a walk takes to come down from the edging to the lawn

local function dir(th: number): Vector3 return Vector3.new(math.cos(th), 0, math.sin(th)) end
local function tang(th: number): Vector3 return Vector3.new(-math.sin(th), 0, math.cos(th)) end
local function flat(v: Vector3): Vector3 return Vector3.new(v.X, 0, v.Z) end
local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function HubPlan.at(r: number, th: number): Vector3
	return C + dir(th) * r
end

-- yard k's frame, as its BaseCFrame: x out, z round (+theta)
function HubPlan.plotFrame(k: number): CFrame
	local th = k * math.pi / 4
	return CFrame.fromMatrix(C + dir(th) * HubPlan.YARD_R, dir(th), Vector3.yAxis)
end

-- the gap between yards k and k+1: r out along its centre line, `off` to the side (+ toward k+1)
function HubPlan.gapAt(k: number, r: number, off: number?): Vector3
	local g = (k + 0.5) * math.pi / 4
	return C + dir(g) * r + tang(g) * (off or 0)
end

--==============================================================
-- curves
--==============================================================
local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: number): { Vector3 }
	local out = {}
	for i = 0, n do
		local t = i / n
		local u = 1 - t
		table.insert(out, p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t))
	end
	return out
end

-- a Catmull-Rom (centripetal enough at these spacings) through `ctrl`, `per` samples a span
local function catmull(ctrl: { Vector3 }, per: number): { Vector3 }
	local out = {}
	local n = #ctrl
	for i = 1, n - 1 do
		local p0 = ctrl[math.max(1, i - 1)]
		local p1 = ctrl[i]
		local p2 = ctrl[i + 1]
		local p3 = ctrl[math.min(n, i + 2)]
		for j = 0, per - 1 do
			local t = j / per
			local t2, t3 = t * t, t * t * t
			table.insert(out, (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5)
		end
	end
	table.insert(out, ctrl[n])
	return out
end

-- give a flat polyline its heights: up on the edging at the ends that meet one, down on the lawn
-- between, eased (startH / endH nil: that end is on the lawn)
local function heights(pts: { Vector3 }, startH: number?, endH: number?): { Vector3 }
	local s = { 0 }
	for i = 2, #pts do s[i] = s[i - 1] + (flat(pts[i]) - flat(pts[i - 1])).Magnitude end
	local L = s[#pts]
	local out = {}
	for i, p in ipairs(pts) do
		local h = HubPlan.GRADE
		if startH then h = math.max(h, HubPlan.GRADE + (startH - HubPlan.GRADE) * (1 - smooth(s[i] / RAMP))) end
		if endH then h = math.max(h, HubPlan.GRADE + (endH - HubPlan.GRADE) * (1 - smooth((L - s[i]) / RAMP))) end
		out[i] = Vector3.new(p.X, h, p.Z)
	end
	return out
end

--==============================================================
-- the paths
--==============================================================
local MOUTH_TH = math.rad(18)      -- the mouth leaves the plaza this far round from yard k's line
local FORK_R = 136

-- the fork: where the mouth splits for the yard and the gap
local function forkOf(k: number): Vector3
	return HubPlan.at(FORK_R, k * math.pi / 4 + MOUTH_TH + math.rad(0.6))
end

-- the gap walk's meander: { r, offset } along gap k's centre line, mirrored on alternate gaps
local MEANDER = { { 186, 0 }, { 204, 0 }, { 232, 5 }, { 262, -4.5 }, { 292, 7 }, { 318, 1.5 }, { 334.5, 0 } }

function HubPlan.paths(owned: { [number]: boolean }?): { any }
	local list = {}
	for k = 0, 7 do
		local th = k * math.pi / 4
		local thM = th + MOUTH_TH
		local fork = forkOf(k)
		-- the mouth: from just inside the brick ring (under its top) straight out to the fork
		local a = HubPlan.at(HubPlan.PLAZA_R - 1.5, thM)
		local mouth = {}
		for i = 0, 6 do table.insert(mouth, a:Lerp(fork, i / 6)) end
		table.insert(list, { id = "mouth" .. k, kind = "mouth", k = k, w = HubPlan.MAIN_W, pts = heights(mouth, HubPlan.EDGE - 0.01, nil) })
		-- the yard's branch: an S from the fork into the way in, square to the yard's front
		local frame = HubPlan.plotFrame(k)
		local z = if owned and owned[k] then 17 else 11.3
		local gate = frame:PointToWorldSpace(Vector3.new(-36, 0, z))
		local inside = frame:PointToWorldSpace(Vector3.new(-34.4, 0, z))
		local outDir = (fork - HubPlan.at(HubPlan.PLAZA_R, thM)).Unit
		-- (the last stretch, up the ramp onto the edging, is dead straight and square to the yard:
		-- a bend on a slope shows its joints as steps)
		local lead = gate - dir(th) * 12
		local yard = bezier(fork, fork + outDir * 9, lead - dir(th) * 12, lead, 20)
		for i = 1, 4 do table.insert(yard, lead:Lerp(gate, i / 4)) end
		table.insert(yard, inside)
		table.insert(list, { id = "yard" .. k, kind = "yard", k = k, w = HubPlan.MAIN_W, pts = heights(yard, nil, HubPlan.EDGE - 0.01) })
		-- the gap's walk: from the fork onto the gap's centre line, straight through the pinch, then
		-- meandering out to the ring (into the opening in its kerb, under its top)
		local s = if k % 2 == 0 then 1 else -1
		local ctrl = { fork, fork + outDir * 10, HubPlan.gapAt(k, 168, 0) }
		for _, m in ipairs(MEANDER) do table.insert(ctrl, HubPlan.gapAt(k, m[1], s * m[2])) end
		table.insert(ctrl, HubPlan.gapAt(k, HubPlan.RING_R - 1.5, 0))
		local gap = heights(catmull(ctrl, 6), nil, nil)
		-- the last stretch rises the hair to the ring's top (0.2)
		local last = gap[#gap]
		gap[#gap] = Vector3.new(last.X, 0.19, last.Z)
		table.insert(list, { id = "gap" .. k, kind = "gap", k = k, w = HubPlan.GAP_W, pts = gap })
	end
	return list
end

--==============================================================
-- where things may stand
--==============================================================
-- (the plan as the server and every client see it before any yard is claimed: both ways in kept clear)
local planCache: { any }? = nil
local function plan(): { any }
	if not planCache then
		local both = HubPlan.paths(nil)
		local owned = {}
		for k = 0, 7 do owned[k] = true end
		for _, p in ipairs(HubPlan.paths(owned)) do
			if p.kind == "yard" then
				p.id ..= "_owned"
				table.insert(both, p)
			end
		end
		planCache = both
	end
	return planCache :: { any }
end

local function segDist(p: Vector3, a: Vector3, b: Vector3): number
	local ab = flat(b - a)
	local ap = flat(p - a)
	local l2 = ab:Dot(ab)
	local t = if l2 > 0 then math.clamp(ap:Dot(ab) / l2, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

-- the walks' segments in a grid of CELL-stud cells, so a query only looks at its neighbourhood
-- (the planting asks thousands of times). A query sees walks within REACH; past that it says REACH.
local CELL, REACH = 16, 30
local gridCache: { [number]: { { a: Vector3, b: Vector3, path: any } } }? = nil
local function cellKey(ix: number, iz: number): number return ix * 4096 + iz end
local function grid(): { [number]: { { a: Vector3, b: Vector3, path: any } } }
	if gridCache then return gridCache end
	local g = {}
	local span = REACH + 6
	for _, path in ipairs(plan()) do
		local pts = path.pts
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local x0 = math.floor((math.min(a.X, b.X) - span) / CELL)
			local x1 = math.floor((math.max(a.X, b.X) + span) / CELL)
			local z0 = math.floor((math.min(a.Z, b.Z) - span) / CELL)
			local z1 = math.floor((math.max(a.Z, b.Z) + span) / CELL)
			for ix = x0, x1 do
				for iz = z0, z1 do
					local key = cellKey(ix, iz)
					local list = g[key]
					if not list then
						list = {}
						g[key] = list
					end
					table.insert(list, { a = a, b = b, path = path })
				end
			end
		end
	end
	gridCache = g
	return g
end

-- distance from p to the nearest walk's edge (the park's ring included); negative on a walk. Walks
-- further than REACH read as REACH
function HubPlan.pathDist(p: Vector3): (number, any?)
	local best, which = REACH, nil
	local list = grid()[cellKey(math.floor(p.X / CELL), math.floor(p.Z / CELL))]
	for _, s in ipairs(list or {}) do
		local d = segDist(p, s.a, s.b) - s.path.w / 2
		if d < best then best, which = d, s.path end
	end
	local r = flat(p - C).Magnitude
	local ring = math.abs(r - HubPlan.RING_R) - HubPlan.RING_W / 2
	if ring < best then best, which = ring, nil end
	return best, which
end

-- how far p is outside every yard (full grown, its building and props, its fence) and the plaza;
-- negative inside one
function HubPlan.yardDist(p: Vector3): number
	local best = flat(p - C).Magnitude - HubPlan.PLAZA_R
	for k = 0, 7 do
		local l = HubPlan.plotFrame(k):PointToObjectSpace(Vector3.new(p.X, 0, p.Z))
		-- boxes in plot space: the yard to stage 5 with its fence, the building and props in front
		for _, b in ipairs({ { -36, -61.5, 110, 61.5 }, { -81, -40, -33, 11.5 } }) do
			local dx = math.max(b[1] - l.X, 0, l.X - b[3])
			local dz = math.max(b[2] - l.Z, 0, l.Z - b[4])
			local d = if dx == 0 and dz == 0 then -math.min(l.X - b[1], b[3] - l.X, l.Z - b[2], b[4] - l.Z) else math.sqrt(dx * dx + dz * dz)
			best = math.min(best, d)
		end
	end
	return best
end

-- can something `pad` round stand at p: off the walks, out of the yards and the plaza, inside the ring
function HubPlan.free(p: Vector3, pad: number): boolean
	local r = flat(p - C).Magnitude
	if r > HubPlan.RING_R - HubPlan.RING_W / 2 - pad then return false end
	if HubPlan.yardDist(p) < pad then return false end
	return HubPlan.pathDist(p) >= pad
end

-- the hunt's hiding places: tucked in where a curious player looks (by the benches, among the roots
-- of the avenues, in the forks' islands, out at each gap's far end), worked from the plan alone so
-- the server and every client agree without sending positions. { p, kind }
function HubPlan.spots(): { { p: Vector3, kind: string } }
	local out = {}
	for k = 0, 7 do
		local s = if k % 2 == 0 then 1 else -1
		-- the island between the fork's two branches
		local f = forkOf(k)
		local th = k * math.pi / 4
		table.insert(out, { p = f + dir(th + MOUTH_TH) * 9 - tang(th + MOUTH_TH) * 4, kind = "island" })
		-- in the pinch, at the foot of the yards' fences
		table.insert(out, { p = HubPlan.gapAt(k, 196, -s * 7.5), kind = "pinch" })
		-- among the avenue's roots, both sides
		table.insert(out, { p = HubPlan.gapAt(k, 248, s * 16), kind = "roots" })
		table.insert(out, { p = HubPlan.gapAt(k, 282, -s * 19), kind = "roots" })
		-- the far end, by the ring
		table.insert(out, { p = HubPlan.gapAt(k, 324, s * 24), kind = "end" })
	end
	return out
end

return HubPlan
