--!strict
-- TYRE CANNON :: YardLook
-- A yard's look (Game.YardLooks, from the Prestige & Neon design canvas, 2026-10-12), laid over the
-- stage's own floor. Only the floor and its edges are dressed: the machines, the decor and the
-- stage's buildings stay exactly where they are.
--   Hall of Prestige   the owner's milestone colour as a tube round the floor, posts at the corners,
--                      chevrons down the launch lane, a gold laurel round the launcher, and a stud
--                      per milestone along one edge that fills in as they're reached
--   Midnight Garage    a night floor with a grid, a double neon edge in the colourway, a bump lane
--                      with neon borders and a checker line, a neon hex round the launcher and tyre
--                      towers in three corners
-- The tubes are thin Neon parts. The Midnight Garage also lights its outer edge, the launcher's hex and
-- the tyre towers (2026-10-17: the owner lifted the no-glow rule so the neon pack really glows).
--   YardLook.apply(plot, layout, override?)   override "id:way" previews a look (the yard editor)
--   YardLook.build(folder, base, tier, layout, "id:way", level)   the same pieces anywhere (the shop's preview)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))

local YardLook = {}

-- "neon" tubes: flat bright paint unless Game.NeonTubes (Neon blooms, and the art rules say no glow)
local NEON = if Game.NeonTubes then Enum.Material.Neon else Enum.Material.SmoothPlastic
local Y = 2 -- the floor's top, in plot space
local function rgb(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end
local NAVY, NAVY2 = rgb(31, 42, 68), rgb(44, 58, 94)
local GOLD, RUBBER = rgb(255, 194, 58), rgb(30, 31, 36)
local RED, WHITE, INK = rgb(229, 53, 43), rgb(244, 241, 232), rgb(14, 15, 19)

local shown: { [Instance]: string } = {}

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

-- a tube round the floor `inset` in from its edge, cut in lengths that take `colors` in turn
local function edge(parent: Instance, base: CFrame, F, inset: number, colors: { Color3 }, h: number, w: number)
	local x0, z0, x1, z1 = F.x0 + inset, F.z0 + inset, F.x1 - inset, F.z1 - inset
	local runs = {
		{ Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0) }, { Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1) },
		{ Vector3.new(x1, 0, z1), Vector3.new(x0, 0, z1) }, { Vector3.new(x0, 0, z1), Vector3.new(x0, 0, z0) },
	}
	local k, made = 0, {}
	for _, r in ipairs(runs) do
		local d = r[2] - r[1]
		local n = if #colors > 1 then math.max(1, math.floor(d.Magnitude / 12 + 0.5)) else 1
		for i = 0, n - 1 do
			local a, b = r[1] + d * (i / n), r[1] + d * ((i + 1) / n)
			local mid = (a + b) / 2
			k += 1
			table.insert(made, part(parent, Vector3.new(w, h, (b - a).Magnitude + w), base * CFrame.lookAt(mid + Vector3.new(0, Y + h / 2, 0), b + Vector3.new(0, Y + h / 2, 0)),
				colors[(k - 1) % #colors + 1], NEON))
		end
	end
	return made
end

-- a light on a tube, in its colour (none while Game.NeonTubes is off)
local function lamp(p: BasePart, range: number, brightness: number)
	if not Game.NeonTubes then return end
	local l = Instance.new("PointLight")
	l.Color = p.Color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
end

-- the launcher's spot and the way the lane runs from it (plot space, flat)
local function lane(layout: Game.YardLayout): (Vector3, Vector3)
	local s = layout.launcher or Game.YardUnits.launcher
	local a = ((s.r or 0) % 4) * math.pi / 2
	return Vector3.new(s.x, 0, s.z), Vector3.new(math.cos(a), 0, -math.sin(a))
end

-- how far along `dir` from `p` the floor goes (less `margin`)
local function reach(F, p: Vector3, dir: Vector3, margin: number): number
	local best = math.huge
	if dir.X > 1e-3 then best = math.min(best, (F.x1 - margin - p.X) / dir.X) end
	if dir.X < -1e-3 then best = math.min(best, (F.x0 + margin - p.X) / dir.X) end
	if dir.Z > 1e-3 then best = math.min(best, (F.z1 - margin - p.Z) / dir.Z) end
	if dir.Z < -1e-3 then best = math.min(best, (F.z0 + margin - p.Z) / dir.Z) end
	return math.max(0, best)
end

local function flatAt(base: CFrame, p: Vector3, dir: Vector3, y: number): CFrame
	return base * CFrame.lookAt(p + Vector3.new(0, y, 0), p + dir + Vector3.new(0, y, 0))
end

local function buildPrestige(f: Instance, base: CFrame, F, layout, level: number)
	local look = Game.prestigeLook(level)
	local colors = Game.lookColors(look)
	if #colors == 0 then colors = { rgb(63, 184, 255) } end
	edge(f, base, F, 0.8, colors, 0.35, 0.5)
	for _, c in ipairs({ { F.x0, F.z0 }, { F.x1, F.z0 }, { F.x0, F.z1 }, { F.x1, F.z1 } }) do
		local p = Vector3.new(c[1] + (c[1] < 0 and 0.9 or -0.9), Y, c[2] + (c[2] < 0 and 0.9 or -0.9))
		part(f, Vector3.new(1.6, 4, 1.6), base * CFrame.new(p + Vector3.new(0, 2, 0)), NAVY)
		part(f, Vector3.new(1.9, 0.5, 1.9), base * CFrame.new(p + Vector3.new(0, 4.25, 0)), colors[1], NEON)
	end
	-- a stud per milestone along the far edge, filled with its colour once it's reached
	for i, l in ipairs(Game.PrestigeLooks) do
		local reached = level >= l.n
		local c = if l.prism then l.prism[1] else l.color
		part(f, Vector3.new(1.4, 0.8, 1.4), base * CFrame.new(F.x0 + 4 + (i - 1) * 3.2, Y + 0.4, F.z0 + 2.6),
			if reached then c else NAVY2, if reached then NEON else nil)
	end
	-- chevrons down the lane and a laurel round the launcher
	local at, dir = lane(layout)
	local far = reach(F, at, dir, 4)
	local d = 30
	while d < far do
		local p = at + dir * d
		for _, s in ipairs({ -1, 1 }) do
			local arm = flatAt(base, p, dir, Y + 0.06) * CFrame.new(s * 1.4, 0, 1.2) * CFrame.Angles(0, s * math.rad(40), 0)
			part(f, Vector3.new(0.7, 0.1, 4.2), arm, colors[1], NEON)
		end
		d += 9
	end
	for i = 0, 25 do
		local a = i / 26 * math.pi * 2
		part(f, Vector3.new(2.6, 0.12, 1.1), base * CFrame.new(at.X, Y + 0.06, at.Z) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -14)
			* CFrame.Angles(0, if i % 2 == 0 then 0.45 else -0.45, 0), GOLD)
	end
end

local function buildMidnight(f: Instance, base: CFrame, F, layout, wayName: string?)
	local way = Game.yardWay(wayName)
	local cx, cz = (F.x0 + F.x1) / 2, (F.z0 + F.z1) / 2
	local w, dz = F.x1 - F.x0, F.z1 - F.z0
	part(f, Vector3.new(w - 0.4, 0.06, dz - 0.4), base * CFrame.new(cx, Y + 0.03, cz), way.floor)
	for x = F.x0 + 12, F.x1 - 6, 12 do part(f, Vector3.new(0.25, 0.04, dz - 0.4), base * CFrame.new(x, Y + 0.07, cz), way.grid) end
	for z = F.z0 + 12, F.z1 - 6, 12 do part(f, Vector3.new(w - 0.4, 0.04, 0.25), base * CFrame.new(cx, Y + 0.07, z), way.grid) end
	for _, p in ipairs(edge(f, base, F, 0.6, { way.a }, 0.35, 0.5)) do lamp(p, 18, 1.4) end
	edge(f, base, F, 2.2, { way.b }, 0.2, 0.3)
	-- the bump lane: neon borders, red-and-white bumps, a checker line at the end
	local at, dir = lane(layout)
	local far = reach(F, at, dir, 3.5)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	if far > 28 then
		for _, s in ipairs({ -1, 1 }) do
			local a, b = at + dir * 26 + side * s * 6, at + dir * far + side * s * 6
			part(f, Vector3.new(0.3, 0.12, (b - a).Magnitude), flatAt(base, (a + b) / 2, dir, Y + 0.1), way.b, NEON)
		end
		local d = 32
		while d < far - 6 do
			local p = at + dir * d
			local cf = flatAt(base, p, dir, Y + 0.14)
			part(f, Vector3.new(11.4, 0.22, 1.6), cf, RED)
			for _, o in ipairs({ -3.6, 0, 3.6 }) do part(f, Vector3.new(1.4, 0.24, 1.62), cf * CFrame.new(o, 0, 0), WHITE) end
			d += 14
		end
		local endCf = flatAt(base, at + dir * (far - 1.5), dir, Y + 0.1)
		for i = 0, 7 do
			for j = 0, 1 do
				part(f, Vector3.new(1.42, 0.08, 1.42), endCf * CFrame.new(-4.97 + i * 1.42, 0, -0.71 + j * 1.42), if (i + j) % 2 == 0 then INK else WHITE)
			end
		end
	end
	-- a neon hexagon round the launcher
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + math.pi / 6
		local cf = base * CFrame.new(at.X, Y + 0.1, at.Z) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -14 * math.cos(math.pi / 6))
		local hex = part(f, Vector3.new(14, 0.14, 0.45), cf, way.b, NEON)
		if i % 2 == 0 then lamp(hex, 10, 1.2) end
	end
	-- tyre towers in three corners (the street corner stays clear for the way in)
	for _, c in ipairs({ { F.x1 - 3.6, F.z0 + 3.6 }, { F.x1 - 3.6, F.z1 - 3.6 }, { F.x0 + 3.6, F.z1 - 3.6 } }) do
		for i = 0, 2 do
			local cf = base * CFrame.new(c[1], Y + 0.75 + i * 1.55, c[2]) * CFrame.Angles(0, 0, math.pi / 2)
			part(f, Vector3.new(1.5, 4.6, 4.6), cf, RUBBER, nil, Enum.PartType.Cylinder)
			local band = part(f, Vector3.new(0.35, 4.7, 4.7), cf, if i % 2 == 0 then way.a else way.b, NEON, Enum.PartType.Cylinder)
			if i == 1 then lamp(band, 12, 1.4) end
		end
	end
end

function YardLook.build(f: Instance, base: CFrame, tier: number, layout: Game.YardLayout, lookStr: string, level: number?)
	local id, way = string.match(lookStr, "^([%w_]+):?(.*)$")
	local F = Game.yardFloor(tier)
	if id == "prestige" then buildPrestige(f, base, F, layout, level or 1)
	elseif id == "midnight" then buildMidnight(f, base, F, layout, way) end
end

function YardLook.apply(plot: Instance, layout: Game.YardLayout, override: string?)
	local base = plot:GetAttribute("BaseCFrame") :: CFrame?
	local tier = plot:GetAttribute("V2_Tier") :: number?
	local lookStr = override or (plot:GetAttribute("V2_Look") :: string?) or "stage"
	local id, way = string.match(lookStr, "^([%w_]+):?(.*)$")
	local level = (plot:GetAttribute("V2_Prestige") :: number?) or 0
	if not (base and tier) then id = "stage" end
	local s = layout.launcher or { x = 0, z = 0, r = 0 }
	local key = table.concat({ tostring(id), tostring(way), tostring(tier), tostring(level), s.x, s.z, s.r }, "|")
	if shown[plot] == key and plot:FindFirstChild("YardLook") then return end
	shown[plot] = key
	local old = plot:FindFirstChild("YardLook")
	if old then old:Destroy() end
	if id == "stage" or not (base and tier) then return end
	local f = Instance.new("Folder")
	f.Name = "YardLook"
	local F = Game.yardFloor(tier)
	if id == "prestige" then buildPrestige(f, base :: CFrame, F, layout, level)
	elseif id == "midnight" then buildMidnight(f, base :: CFrame, F, layout, way) end
	f.Parent = plot
end

return YardLook
