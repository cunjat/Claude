--!strict
-- TYRE CANNON :: PlotPaths
-- Paths that join every yard to the plaza, so the lobby reads as one place (2026-10-15):
--   the walkway   from the plaza's rim out to each yard's way in (the gap between its building and
--                 the street fence, plot z 17), a raised stone walk level with the plaza and the
--                 yards (top at y 2) with darker kerbs. It runs beside the frontage (plot z 30),
--                 clear of the building and its stock at every stage, then turns in at the gate.
--   the yard path inside an owned yard, from the gate to behind its cannon, routed round the machines,
--                 the decor and the fixed stations of that yard's own layout (a grid search on the
--                 layout, Game.yardBoxes / decorBox), so it moves when the yard is rearranged. It's
--                 paint on the floor: nothing to walk round, and decor can go on it.
-- Built on the client from plot attributes (BaseCFrame, V2_Owner, V2_Tier, V2_Layout), like
-- PlotStage; no Workspace objects are added to the place. workspace attribute PlotPaths = false
-- turns it all off (for building the map round it). A yard being edited (TC_Editing, set by
-- YardEdit on the client) hides its yard path until it's saved.
--   PlotPaths.new() -> watches every plot

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))

local PlotPaths = {}
PlotPaths.__index = PlotPaths

local PLAZA_R = 110.5          -- the plaza disc's radius (Lobby.Plaza.PlazaFloor), a touch inside it
local TOP = 2                  -- the plaza's and the yards' floor top
-- (2026-10-16) the walkway's top: level with the brick ring round the plaza and the yards' own
-- edging (both 1.2), so it meets both flush; at 2 it rode 0.8 proud over the bricks at each end
local WALK_TOP = 1.2
local WALK_W = 7
local WALK_Z = 30              -- plot z the walkway runs along, beside the frontage
local GATE_Z = 17              -- plot z of the way in, between the building and the street fence
local TURN_X = -44             -- plot x where it turns in toward the gate
local STONE = Color3.fromRGB(158, 146, 128)
local KERB = Color3.fromRGB(96, 90, 82)
local PAINT = Color3.fromRGB(122, 104, 82)
local GRID = 2

local function slab(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, y0: number, y1: number, color: Color3, mat: Enum.Material, solid: boolean)
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = d.Magnitude
	if len < 0.05 then return end
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	p.CastShadow = false
	p.Material = mat
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(w, y1 - y0, len)
	local mid = (a + b) / 2
	p.CFrame = CFrame.lookAt(Vector3.new(mid.X, (y0 + y1) / 2, mid.Z), Vector3.new(b.X, (y0 + y1) / 2, b.Z))
	p.Parent = parent
end

local function disc(parent: Instance, at: Vector3, dia: number, y0: number, y1: number, color: Color3, mat: Enum.Material, solid: boolean)
	local p = Instance.new("Part")
	p.Name = "Joint"
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	p.CastShadow = false
	p.Material = mat
	p.Color = color
	p.Size = Vector3.new(y1 - y0, dia, dia)
	p.CFrame = CFrame.new(at.X, (y0 + y1) / 2, at.Z) * CFrame.Angles(0, 0, math.pi / 2)
	p.Parent = parent
end

function PlotPaths.new()
	local self = setmetatable({}, PlotPaths)
	self.keys = {} :: { [Instance]: string }
	local root = Instance.new("Folder")
	root.Name = "PlotPaths"
	root.Parent = workspace
	self.root = root
	task.spawn(function()
		local lobby = workspace:WaitForChild("Lobby", 30)
		local plots = lobby and lobby:WaitForChild("Plots", 30)
		local plaza = lobby and lobby:FindFirstChild("Plaza")
		local floor = plaza and plaza:FindFirstChild("PlazaFloor") :: BasePart?
		if not plots then return end
		self.center = if floor then floor.Position else Vector3.new(-6000, 0, 6000)
		for _, plot in ipairs(plots:GetChildren()) do self:watch(plot) end
		plots.ChildAdded:Connect(function(plot) self:watch(plot) end)
	end)
	workspace:GetAttributeChangedSignal("PlotPaths"):Connect(function()
		root.Parent = if workspace:GetAttribute("PlotPaths") == false then nil else workspace
	end)
	if workspace:GetAttribute("PlotPaths") == false then root.Parent = nil end
	return self
end

function PlotPaths:watch(plot: Instance)
	local function refresh() self:build(plot) end
	for _, a in ipairs({ "BaseCFrame", "V2_Owner", "V2_Tier", "V2_Layout", "TC_Editing" }) do
		plot:GetAttributeChangedSignal(a):Connect(refresh)
	end
	refresh()
end

-- the walkway: plaza rim -> along the frontage -> turn in -> the gate
function PlotPaths:walkway(f: Instance, base: CFrame)
	local c = self.center or Vector3.new(-6000, 0, 6000)
	-- where the line z = WALK_Z (plot space) meets the plaza's rim
	local o = base:PointToObjectSpace(Vector3.new(c.X, 0, c.Z))
	local dz = WALK_Z - o.Z
	local reach = math.sqrt(math.max(0, PLAZA_R * PLAZA_R - dz * dz))
	local startX = o.X + reach
	local floor = Game.yardFloor(1)
	local pts = {
		Vector3.new(startX, 0, WALK_Z),
		Vector3.new(TURN_X, 0, WALK_Z),
		Vector3.new(TURN_X + 4, 0, GATE_Z),
		Vector3.new(floor.x0 - 1, 0, GATE_Z),
	}
	local world = {}
	for i, p in ipairs(pts) do world[i] = base:PointToWorldSpace(p) end
	for i = 1, #world - 1 do
		slab(f, "Kerb", world[i], world[i + 1], WALK_W + 1.6, -0.5, WALK_TOP - 0.12, KERB, Enum.Material.Concrete, true)
		slab(f, "Walk", world[i], world[i + 1], WALK_W, -0.5, WALK_TOP, STONE, Enum.Material.Cobblestone, true)
	end
	for i = 2, #world - 1 do
		disc(f, world[i], WALK_W + 1.6, -0.5, WALK_TOP - 0.12, KERB, Enum.Material.Concrete, true)
		disc(f, world[i], WALK_W, -0.5, WALK_TOP, STONE, Enum.Material.Cobblestone, true)
	end
end

-- a grid search across the yard's floor from the gate to beside the launcher, round everything
-- standing in the yard; returns plot-space points (corners only) or nil
local function route(layout, tier: number): { Vector3 }?
	local F = Game.yardFloor(tier)
	local blocked: { { number } } = {}
	local function block(b: { number }, m: number)
		table.insert(blocked, { b[1] - m, b[2] - m, b[3] + m, b[4] + m })
	end
	for _, u in ipairs(Game.Yard.Units) do
		local s = layout[u.id]
		if s then
			for _, b in ipairs(Game.yardBoxes(u.id, s.x, s.z, s.r)) do block(b, 2) end
		end
	end
	for _, d in ipairs(layout.decor or {}) do block(Game.decorBox(d), 1.5) end
	for _, b in ipairs(Game.Yard.Fixed) do block(b, 1.5) end
	local nx = math.floor((F.x1 - F.x0) / GRID)
	local nz = math.floor((F.z1 - F.z0) / GRID)
	local function pos(i: number, j: number): (number, number)
		return F.x0 + (i + 0.5) * GRID, F.z0 + (j + 0.5) * GRID
	end
	local function free(i: number, j: number): boolean
		if i < 0 or j < 0 or i >= nx or j >= nz then return false end
		local x, z = pos(i, j)
		for _, b in ipairs(blocked) do
			if x > b[1] and x < b[3] and z > b[2] and z < b[4] then return false end
		end
		return true
	end
	-- the goal: behind the cannon, where it's loaded (the launcher's back edge, whichever way it's
	-- turned: the unit's -x end, as Game.yardBoxes turns it)
	local ls = layout.launcher
	local lu = Game.YardUnits.launcher
	if not (ls and lu) then return nil end
	local back = lu.boxes[1][1] - 3
	local a = (ls.r % 4) * math.pi / 2
	local gx = ls.x + back * math.cos(a)
	local gz = ls.z - back * math.sin(a)
	local function goal(i: number, j: number): boolean
		local x, z = pos(i, j)
		return math.abs(x - gx) + math.abs(z - gz) <= 4
	end
	local si = 0
	local sj = math.clamp(math.floor((GATE_Z - F.z0) / GRID), 0, nz - 1)
	-- (the gate's cell, or the nearest free one along the street edge)
	if not free(si, sj) then
		local found = false
		for k = 1, 8 do
			for _, jj in ipairs({ sj + k, sj - k }) do
				if not found and free(si, jj) then sj, found = jj, true end
			end
		end
		if not found then return nil end
	end
	-- breadth first over 8 neighbours (the grid is small: a few thousand cells)
	local key = function(i: number, j: number) return i * 1000 + j end
	local prev: { [number]: number } = {}
	local q = { key(si, sj) }
	prev[q[1]] = -1
	local head = 1
	local hit: number? = nil
	local dirs = { { 1, 0 }, { 0, 1 }, { 0, -1 }, { -1, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
	while head <= #q do
		local k = q[head]
		head += 1
		local i, j = k // 1000, k % 1000
		if goal(i, j) then
			hit = k
			break
		end
		for _, d in ipairs(dirs) do
			local a, b = i + d[1], j + d[2]
			local kk = key(a, b)
			-- (diagonals only where both sides are open, so it never cuts a corner)
			if prev[kk] == nil and free(a, b) and (d[1] == 0 or d[2] == 0 or (free(i + d[1], j) and free(i, j + d[2]))) then
				prev[kk] = k
				table.insert(q, kk)
			end
		end
	end
	if not hit then return nil end
	local cells = {}
	local k: number = hit
	while k ~= -1 do
		table.insert(cells, 1, k)
		k = prev[k]
	end
	-- corners only
	local pts = {}
	local lastDir = nil
	for n, c in ipairs(cells) do
		local i, j = c // 1000, c % 1000
		local x, z = pos(i, j)
		if n == 1 then
			table.insert(pts, Vector3.new(F.x0 - 0.5, 0, z))
			table.insert(pts, Vector3.new(x, 0, z))
		else
			local pc = cells[n - 1]
			local dir = (i - pc // 1000) .. "," .. (j - pc % 1000)
			if dir ~= lastDir and n > 2 then
				local qi, qj = pc // 1000, pc % 1000
				local px, pz = pos(qi, qj)
				table.insert(pts, Vector3.new(px, 0, pz))
			end
			lastDir = dir
			if n == #cells then table.insert(pts, Vector3.new(x, 0, z)) end
		end
	end
	return pts
end

function PlotPaths:yardPath(f: Instance, base: CFrame, plot: Instance, tier: number)
	local layout = Game.yardDecode(plot:GetAttribute("V2_Layout") :: string?)
	local pts = route(layout, tier)
	if not pts then return end
	local world = {}
	for i, p in ipairs(pts) do world[i] = base:PointToWorldSpace(p) end
	for i = 1, #world - 1 do
		slab(f, "Path", world[i], world[i + 1], 4, TOP, TOP + 0.08, PAINT, Enum.Material.Cobblestone, false)
	end
	for i = 2, #world - 1 do
		disc(f, world[i], 4, TOP, TOP + 0.08, PAINT, Enum.Material.Cobblestone, false)
	end
end

function PlotPaths:build(plot: Instance)
	local base = plot:GetAttribute("BaseCFrame") :: CFrame?
	if not base then return end
	local owner = plot:GetAttribute("V2_Owner")
	local tier = (plot:GetAttribute("V2_Tier") :: number?) or 0
	local editing = plot:GetAttribute("TC_Editing") == true
	local key = table.concat({ tostring(base), tostring(owner), tostring(tier), tostring(plot:GetAttribute("V2_Layout")), tostring(editing) }, "|")
	if self.keys[plot] == key then return end
	self.keys[plot] = key
	local old = self.root:FindFirstChild(plot.Name)
	if old then old:Destroy() end
	local f = Instance.new("Folder")
	f.Name = plot.Name
	-- (2026-10-22: the walk from the plaza to the yard's way in is HubPark's now, a curve on the
	-- hub's plan, flush with the plaza and the edging; this only paints the path inside the yard)
	if owner and tier >= 1 and not editing then
		local ok, err = pcall(function() self:yardPath(f, base, plot, tier) end)
		if not ok then warn("[PlotPaths] " .. tostring(err)) end
	end
	f.Parent = self.root
end

return PlotPaths
