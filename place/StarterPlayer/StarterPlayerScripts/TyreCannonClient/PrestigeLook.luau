--!strict
-- TYRE CANNON :: PrestigeLook
-- What a prestige looks like on your things (Game.PrestigeLooks, from the Prestige & Neon design
-- canvas, 2026-10-12). Both work on any tyre model and any cannon build, because they add parts on
-- top instead of repainting meshes:
--   PrestigeLook.dressTyre(model, level)   each tyre's own look (TYRE below): mostly a lip on the bead in the
--                                         milestone colour (the prism cycles three), and a gold pip a level past it
--   PrestigeLook.trimCannon(model, level, scale)  each cannon build's own kit (KIT below); any other a neon
--                                         muzzle ring and barrel tube, collars and a strap in
--                                         the trim's colours, and a P badge each side of the breech
-- The tubes are thin Neon parts with no lights (the art rules: colour, never glow). The cannon's trim
-- parts are named Barrel* so LaunchShow2 swings them with the barrel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local Models = require(script.Parent:WaitForChild("Models"))

local PrestigeLook = {}

-- "neon" tubes: flat bright paint unless Game.NeonTubes (Neon blooms, and the art rules say no glow)
local NEON = if Game.NeonTubes then Enum.Material.Neon else Enum.Material.SmoothPlastic
local NAVY = Color3.fromRGB(31, 42, 68)
local INK = Color3.fromRGB(14, 15, 19)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
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

-- a ring of blocks round `at`'s local Z axis; `colors` repeat round it
local function ring(parent: Instance, name: string, at: CFrame, r: number, n: number, thick: number, depth: number, colors: { Color3 }, mat: Enum.Material?)
	local len = 2 * math.pi * r / n * 1.1
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		part(parent, name, Vector3.new(len, thick, depth), at * CFrame.Angles(0, 0, a) * CFrame.new(0, r, 0), colors[i % #colors + 1], mat)
	end
end

-- a model's extents in its pivot's space (half sizes)
local function extents(model: Model): Vector3
	local pivot = model:GetPivot()
	local hx, hy, hz = 0, 0, 0
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local q = pivot:PointToObjectSpace(p.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)))
						hx, hy, hz = math.max(hx, math.abs(q.X)), math.max(hy, math.abs(q.Y)), math.max(hz, math.abs(q.Z))
					end
				end
			end
		end
	end
	return Vector3.new(hx, hy, hz)
end

local function clear(model: Instance, name: string)
	local old = model:FindFirstChild(name)
	if old then old:Destroy() end
end

-- Each tyre's own prestige look (2026-10-15), measured off its mesh at 8 studs across (H: its half
-- size then, so other sizes scale). Most get the lip on the bead, where the rubber meets the rim
-- (bead = radius, z = how far the face stands out there); the odd ones get what suits them:
--   donut       sprinkles on the icing in the milestone's colours (no lip)
--   square      a square frame round the plate
--   gyro        one more gimbal ring, tilted through the hub
--   orbital     the planet's ring coloured, and a moon on it
--   whitewall   the white band repainted
--   slick       a pinstripe round the sidewall
--   scarab      four gems round the bead
--   cartwheel, wheelbarrow, hubcap, monster...  the felloe or bead, and a painted hub cap
--   stock       (the tyres not yet modelled) the bead, and caps on the wheel nuts
-- The gold pips (a level past the milestone) run along the top of the sidewall at `pip`.
local TYRE = {
	baldspare = { H = 3.75, bead = 2.65, z = 1.45, pip = { 3.1, 1.4 }, cap = { 0.55, 1.3 } },
	balloon = { H = 3.8, bead = 1.5, z = 1.35, pip = { 2.6, 1.95 } },
	beadlock = { H = 3.85, bead = 2.35, z = 1.65, pip = { 3.1, 1.55 } },
	cartwheel = { H = 4.0, bead = 2.8, z = 0.6, pip = { 3.3, 0.6 }, cap = { 0.8, 1.25 } },
	donut = { H = 4.15, sprinkles = true, pip = { 2.5, 1.6 } },
	drill = { H = 4.1, bead = 3.25, z = 1.42, pip = { 2.2, 1.55 } },
	dumper = { H = 3.95, bead = 1.75, z = 1.5, pip = { 2.8, 1.75 } },
	gyro = { H = 4.0, gimbal = 2.55, pip = { 3.4, 0.85 } },
	hubcap = { H = 3.8, bead = 2.7, z = 1.35, pip = { 3.2, 1.25 }, cap = { 0.6, 1.35 } },
	monster = { H = 4.0, bead = 1.25, z = 1.75, pip = { 2.6, 2.15 } },
	orbital = { H = 3.8, orbit = { 1.9, 0.7 }, pip = { 2.9, 1.3 } },
	original = { H = 3.85, bead = 2.75, z = 1.35, pip = { 3.2, 1.35 } },
	paddle = { H = 4.0, bead = 1.75, z = 1.4, pip = { 2.6, 1.65 } },
	scarab = { H = 3.9, bead = 2.25, z = 1.2, gems = { 3.0, 1.55 }, pip = { 3.2, 1.5 } },
	slick = { H = 3.75, stripe = { 3.3, 1.55 }, pip = { 2.7, 1.55 } },
	spinner = { H = 3.8, bead = 2.35, z = 1.25, pip = { 3.0, 1.35 } },
	splitfive = { H = 3.9, bead = 2.65, z = 1.45, pip = { 3.2, 1.45 } },
	square = { H = 4.05, square = { 3.0, 1.3 }, pip = { 3.5, 1.25 } },
	steelie = { H = 3.85, bead = 2.6, z = 1.35, pip = { 3.1, 1.35 } },
	tractorlug = { H = 3.9, bead = 1.45, z = 1.35, pip = { 2.6, 1.45 } },
	turbofan = { H = 3.8, bead = 2.65, z = 1.3, pip = { 3.1, 1.3 } },
	wheelbarrow = { H = 3.85, bead = 2.05, z = 1.15, pip = { 2.6, 1.15 }, cap = { 0.45, 1.15 } },
	whitewall = { H = 3.8, band = { 3.1, 0.55, 1.48 }, pip = { 3.55, 1.15 } },
	stock = { H = 4.0, bead = 3.3, z = 1.05, pip = { 3.65, 1.05 }, nuts = true },
}
PrestigeLook.Tyre = TYRE

-- which tyre a model is: its mesh's name (Tyre_<id>), or the stock wheel
local function tyreOf(model: Model): any?
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") then
			local id = string.match(d.Name, "^Tyre_(.+)$")
			if id and TYRE[id] then return TYRE[id] end
		end
		if d.Name == "Carcass" then return TYRE.stock end
	end
	return nil
end

function PrestigeLook.dressTyre(model: Model?, level: number?)
	if not model then return end
	clear(model, "PrestigeLip")
	local look, pips = Game.prestigeLook(level)
	if not look then return end
	local e = extents(model)
	local R = math.max(e.X, e.Y)
	if R <= 0 then return end
	local f = Instance.new("Model")
	f.Name = "PrestigeLip"
	local pivot = model:GetPivot()
	local colors = Game.lookColors(look)
	local second = look.strap or look.collar or Color3.fromRGB(244, 241, 232)
	local t = tyreOf(model)
	if not t then
		-- (a tyre we don't know: a lip round each sidewall)
		for _, side in ipairs({ -1, 1 }) do
			local at = pivot * CFrame.new(0, 0, side * (e.Z * 0.9 + R * 0.02))
			ring(f, "Lip", at, R * 0.6, 24, R * 0.075, R * 0.07, colors, NEON)
		end
		t = { pip = { R * 0.78, e.Z * 0.9 }, H = R, generic = true }
	end
	local s = if t.generic then 1 else R / t.H
	for _, side in ipairs({ -1, 1 }) do
		-- this sidewall's frame: z out of the face
		local function at(z: number): CFrame
			return pivot * CFrame.new(0, 0, side * z * s) * (if side < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new())
		end
		if t.bead then ring(f, "Lip", at(t.z + 0.08), t.bead * s, 28, 0.3 * s, 0.22 * s, colors, NEON) end
		if t.band then ring(f, "Lip", at(t.band[3] + 0.06), t.band[1] * s, 36, t.band[2] * s, 0.16 * s, colors, NEON) end
		if t.stripe then ring(f, "Lip", at(t.stripe[2] + 0.06), t.stripe[1] * s, 36, 0.14 * s, 0.14 * s, colors, NEON) end
		if t.cap then
			part(f, "Lip", Vector3.new(0.2 * s, t.cap[1] * 2 * s, t.cap[1] * 2 * s), at(t.cap[2] + 0.1) * CFrame.Angles(0, math.pi / 2, 0), colors[1], NEON, Enum.PartType.Cylinder)
		end
		if t.square then
			local hs, z = t.square[1] * s, t.square[2] + 0.08
			local w, d = 0.3 * s, 0.22 * s
			for _, q in ipairs({ { 0, hs, 2 * hs + w, w }, { 0, -hs, 2 * hs + w, w }, { hs, 0, w, 2 * hs + w }, { -hs, 0, w, 2 * hs + w } }) do
				part(f, "Lip", Vector3.new(q[3], q[4], d), at(z) * CFrame.new(q[1], q[2], 0), colors[1], NEON)
			end
		end
		if t.gimbal and side > 0 then
			ring(f, "Lip", pivot * CFrame.Angles(0, math.rad(58), 0), t.gimbal * s, 30, 0.24 * s, 0.24 * s, colors, NEON)
			ring(f, "Lip", pivot * CFrame.Angles(math.rad(58), 0, 0), t.gimbal * 0.86 * s, 26, 0.2 * s, 0.2 * s, { second }, NEON)
		end
		if t.orbit then
			ring(f, "Lip", at(t.orbit[2]), t.orbit[1] * s, 28, 0.22 * s, 0.18 * s, colors, NEON)
			local m = math.rad(if side > 0 then 40 else 220)
			part(f, "Lip", Vector3.one * 0.6 * s, at(t.orbit[2] + 0.15) * CFrame.new(math.cos(m) * t.orbit[1] * s, math.sin(m) * t.orbit[1] * s, 0), second, nil, Enum.PartType.Ball)
		end
		if t.gems then
			for k = 0, 3 do
				local g = math.pi / 4 + k * math.pi / 2
				part(f, "Lip", Vector3.new(0.5, 0.5, 0.3) * s, at(t.gems[2] + 0.1) * CFrame.new(math.cos(g) * t.gems[1] * s, math.sin(g) * t.gems[1] * s, 0) * CFrame.Angles(0, 0, math.pi / 4), colors[(k % #colors) + 1], NEON)
			end
		end
		if t.sprinkles then
			-- (the same scatter every time: a fixed seed; the icing's height measured at each radius)
			local icing = { { 1.3, 0.7 }, { 1.6, 1.1 }, { 1.9, 1.3 }, { 2.2, 1.4 }, { 2.5, 1.5 }, { 2.8, 1.4 }, { 3.1, 1.4 }, { 3.4, 1.2 }, { 3.7, 0.9 } }
			local rng = Random.new(if side > 0 then 7 else 11)
			local palette = { colors[1], second, colors[#colors], Color3.fromRGB(244, 241, 232) }
			for k = 1, 26 do
				local band = icing[rng:NextInteger(2, 8)]
				local r = band[1] + rng:NextNumber(-0.12, 0.12)
				local g = rng:NextNumber(0, math.pi * 2)
				part(f, "Lip", Vector3.new(0.5, 0.16, 0.16) * s, at(band[2] + 0.05) * CFrame.new(math.cos(g) * r * s, math.sin(g) * r * s, 0) * CFrame.Angles(0, 0, rng:NextNumber(0, math.pi)), palette[(k % #palette) + 1], NEON)
			end
		end
		-- a gold pip a level past the milestone, along the top of the sidewall
		for k = 1, math.min(pips, 4) do
			local g = math.pi / 2 + (k - (pips + 1) / 2) * 0.24
			part(f, "Pip", Vector3.one * 0.42 * s, at(t.pip[2] + 0.1) * CFrame.new(math.cos(g) * t.pip[1] * s, math.sin(g) * t.pip[1] * s, 0), Game.PrestigePip, nil, Enum.PartType.Ball)
		end
	end
	-- the stock wheel's nuts, capped in the colour
	if t.nuts then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Nut" then
				part(f, "Lip", d.Size * Vector3.new(1.3, 1.25, 1.25), d.CFrame, colors[1], NEON)
			end
		end
	end
	f.Parent = model
end

-- how far out from the axis the barrel's surface is at `p` (a ray from outside, against the barrel
-- parts only; they're made queryable for the moment it takes)
local function radiusAt(parts: { BasePart }, p: Vector3, out: Vector3): number?
	local was = {}
	for i, b in ipairs(parts) do was[i] = b.CanQuery; b.CanQuery = true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local hit = workspace:Raycast(p + out * 40, -out * 40, params)
	for i, b in ipairs(parts) do b.CanQuery = was[i] end
	return hit and (40 - hit.Distance) or nil
end

-- the barrel of an imported cannon: its muzzle and bore direction from AssetInfo (as LaunchShow2 aims
-- it), the breech as far behind the trunnion as LaunchShow2 puts it, and its radius measured off the mesh
local function boreOf(model: Model, scale: number): (Vector3?, Vector3, number, number, { BasePart })
	for _, child in ipairs(model:GetChildren()) do
		local info = child:IsA("Model") and Models.info(child.Name) :: any
		if info and info.muzzle and info.elev then
			local pivot = child:GetPivot()
			local m = info.muzzle
			local muzzle = pivot * (Models.toRoblox(m[1], m[2], m[3]) * scale)
			local e = math.rad(info.elev)
			local dir = pivot:VectorToWorldSpace(Vector3.new(math.cos(e), math.sin(e), 0)).Unit
			local parts = {}
			local trunnion = nil
			for _, d in ipairs(child:GetDescendants()) do
				if d:IsA("BasePart") and d.Name:sub(1, 6) == "Barrel" and d.Transparency < 0.99 then
					table.insert(parts, d)
					if d.Name == "Barrel" then trunnion = d.Position end
				end
			end
			local t = info.pivot
			trunnion = if t then pivot * (Models.toRoblox(t[1], t[2], t[3]) * scale) else trunnion or (muzzle - dir * 10)
			-- the trunnion onto the bore line
			trunnion = muzzle + dir * (trunnion - muzzle):Dot(dir)
			local breech = trunnion - (muzzle - trunnion) * 0.85
			local len = (muzzle - breech).Magnitude
			local up = (Vector3.yAxis - dir * dir.Y).Unit
			local r = radiusAt(parts, muzzle - dir * len * 0.08, up) or len * 0.12
			return (muzzle + breech) / 2, dir, len, math.clamp(r, len * 0.05, len * 0.3), parts
		end
	end
	return nil, Vector3.zero, 0, 0, {}
end

-- the barrel: the biggest part named Barrel*; its long axis and which end is the muzzle (the higher)
local function barrelOf(model: Model): (BasePart?, Vector3, Vector3, number, number)
	local best: BasePart? = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:sub(1, 6) == "Barrel" and d.Name ~= "BarrelTrim" and d.Transparency < 0.99 then
			if not best or d.Size.Magnitude > best.Size.Magnitude then best = d end
		end
	end
	if not best then return nil, Vector3.zero, Vector3.zero, 0, 0 end
	local s = best.Size
	local cf = best.CFrame
	local axis, len, r
	if s.X >= s.Y and s.X >= s.Z then axis, len, r = cf.RightVector, s.X, (s.Y + s.Z) / 4
	elseif s.Y >= s.Z then axis, len, r = cf.UpVector, s.Y, (s.X + s.Z) / 4
	else axis, len, r = cf.LookVector, s.Z, (s.X + s.Y) / 4 end
	if axis.Y < 0 then axis = -axis end
	return best, cf.Position, axis, len, r
end

-- a point `t` of the way from the breech (0) to the muzzle (1)
local function along(mid: Vector3, axis: Vector3, len: number, t: number): Vector3
	return mid + axis * (t - 0.5) * len
end

local function badge(parent: Instance, cf: CFrame, size: number, text: string, color: Color3, name: string?)
	local p = part(parent, name or "BarrelTrim", Vector3.new(size, size * 0.62, size * 0.08), cf, NAVY)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0.5
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = color
	t.Parent = sg
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = INK
	s.Parent = t
end

-- Each cannon build has its own kit (2026-10-15), fitted to its shape (measured off the meshes at
-- ModelScale 0.667, the yard's; other scales stretch it). Every piece unlocks at a look index (1 =
-- the first milestone, P1 .. 9 = P25), so each milestone adds to the cannon rather than repainting it:
--   1 Junk Pipe     painted pipe clamps on the orange, the muzzle flange's face, a rebar pennant on the
--                   pallet, then the inner flanges in the trim's collar colour
--   2 Steel Mortar  colour in the grooves between the black ribs, a crown on the bell's mouth, the
--                   turntable's rim, then a second rim
--   3 Air Cannon    the teal bands and the muzzle collar's lip repainted, twin racing stripes down the
--                   white barrel, hubcaps on the carriage wheels
--   4 Howitzer      a band on the muzzle brake, victory rings on the thin barrel (one more each
--                   milestone), a roundel on each side of the hull, a pennant on a whip aerial
--   5 Mag Rail      floating accelerator hoops round both rails (one more each milestone), caps on the
--                   rails' tips, a ring round the plinth
-- The P badge sits where each build has a flat face for it. Barrel pieces are named BarrelTrim so
-- LaunchShow2 swings them with the barrel; the rest are Trim.
-- (t: 0 breech .. 1 muzzle along the bore; r, w in studs; pos in the cannon's pivot frame: x the way
-- it fires, y up, z its left)
local KIT = {
	{ -- Junk Pipe
		lip = { t = 1.0, r = 5.15, w = 1.3, from = 1 },
		bands = { { t = 0.77, r = 5.55, w = 1.2, from = 1 }, { t = 0.3, r = 5.55, w = 1.2, from = 2 } },
		collars = { { t = 0.12, r = 5.95, w = 0.5, from = 5 }, { t = 0.6, r = 5.95, w = 0.5, from = 5 } },
		badge = { t = 0.42, out = 5.75, size = 3.2, from = 1 },
		flags = { { pos = Vector3.new(-12, 4, -4), h = 16, from = 3 }, { pos = Vector3.new(-12, 4, 4), h = 14, from = 8 } },
	},
	{ -- Steel Mortar
		lip = { t = 0.97, r = 7.35, w = 0.9, from = 1 },
		bands = { { t = 0.675, r = 6.55, w = 0.8, from = 1 }, { t = 0.5, r = 6.55, w = 0.8, from = 2 }, { t = 0.8, r = 6.55, w = 0.8, from = 3 } },
		hub = { pos = Vector3.new(0, 9, 11.75), size = 3.4, from = 1 },
		rims = { { r = 12.6, y = 2.7, w = 0.9, from = 5 }, { r = 11.2, y = 2.75, w = 0.5, from = 8 } },
	},
	{ -- Air Cannon
		lip = { t = 0.995, r = 5.55, w = 0.9, from = 1 },
		bands = { { t = 0.6, r = 5.72, w = 1.5, from = 2 }, { t = 0.755, r = 5.72, w = 1.5, from = 2 } },
		stripes = { t0 = 0.17, t1 = 0.88, r = 5.25, w = 0.8, gap = 0.2, from = 3 },
		badge = { t = 0.36, out = 5.4, size = 3, from = 1 },
		hubcaps = { pos = Vector3.new(2, 5.5, 11.3), r = 1.9, from = 5 },
	},
	{ -- Howitzer
		bands = { { t = 0.875, r = 6.6, w = 0.9, from = 1 } },
		victory = { t = 0.6, step = 0.06, r = 5.2, w = 0.55 },
		roundel = { pos = Vector3.new(-3, 12, 6.25), r = 2.6, from = 1 },
		flags = { { pos = Vector3.new(-11, 18.5, -3.5), h = 10, whip = true, from = 3 } },
		collars = { { t = 0.45, r = 6.05, w = 0.6, from = 5 } },
	},
	{ -- Mag Rail
		hoops = { t = 0.55, step = 0.2, r = 10.6, w = 0.6, max = 3 },
		hub = { pos = Vector3.new(0, 14, 6.3), size = 3, from = 1 },
		rims = { { r = 8.6, y = 2.4, w = 0.8, from = 5 } },
		tips = { t = 0.98, off = 7, r = 1.1, from = 8 },
	},
}
PrestigeLook.Kit = KIT

-- which build a placed cannon is (its Cannons/CannonN model), or nil
local function buildOf(model: Model): (number?, Model?)
	for _, child in ipairs(model:GetChildren()) do
		local n = child:IsA("Model") and tonumber(string.match(child.Name, "^Cannon(%d)$"))
		if n and KIT[n] then return n, child end
	end
	return nil, nil
end

-- the look's index in Game.PrestigeLooks (1..9)
local function lookIndex(look: any): number
	for i, l in ipairs(Game.PrestigeLooks) do
		if l == look then return i end
	end
	return 1
end

-- a pennant: a pole and a triangle flag in the colour, the P number on it
local function pennant(f: Instance, foot: CFrame, h: number, color: Color3, k: number, text: string, whip: boolean?)
	local poleW = if whip then 0.18 * k else 0.35 * k
	part(f, "Trim", Vector3.new(poleW, h * k, poleW), foot * CFrame.new(0, h * k / 2, 0), if whip then INK else Color3.fromRGB(92, 64, 44))
	part(f, "Trim", Vector3.one * poleW * 1.8, foot * CFrame.new(0, h * k, 0), color, NEON, Enum.PartType.Ball)
	local fl = 3.2 * k
	local fh = 2.0 * k
	local w = Instance.new("WedgePart")
	w.Name = "Trim"
	w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow, w.Massless = true, false, false, false, false, true
	w.Size = Vector3.new(0.12 * k, fh, fl)
	-- the wedge's tall end at the pole, tapering away from it (the flag streams out along -x)
	w.CFrame = foot * CFrame.new(-fl / 2 - poleW / 2, h * k - fh / 2 - 0.3 * k, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	w.Color = color
	w.Material = NEON
	w.Parent = f
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Right
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0.5
	sg.Parent = w
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0, 1)
	t.Position = UDim2.fromScale(0.08, 0.98)
	t.Size = UDim2.fromScale(0.45, 0.55)
	t.Font = Enum.Font.FredokaOne
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Parent = sg
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Color = INK
	s.Parent = t
end

-- a flat ring lying level, round `c` (the pivot frame)
local function flatRing(f: Instance, pivot: CFrame, c: Vector3, r: number, w: number, colors: { Color3 })
	ring(f, "Trim", pivot * CFrame.new(c) * CFrame.Angles(math.pi / 2, 0, 0), r, 36, w, w * 0.4, colors, NEON)
end

local function trimKit(model: Model, child: Model, kit: any, look: any, idx: number, level: number, scale: number)
	local info = Models.info(child.Name) :: any
	if not (info and info.muzzle and info.elev) then return false end
	local k = scale / 0.667
	local pivot = child:GetPivot()
	local muzzle = pivot * (Models.toRoblox(info.muzzle[1], info.muzzle[2], info.muzzle[3]) * scale)
	local e = math.rad(info.elev)
	local axis = pivot:VectorToWorldSpace(Vector3.new(math.cos(e), math.sin(e), 0)).Unit
	local trunnion: Vector3? = nil
	for _, d in ipairs(child:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Barrel" then trunnion = d.Position end
	end
	if not trunnion then return false end
	local tr = muzzle + axis * ((trunnion :: Vector3) - muzzle):Dot(axis)
	local breech = tr - (muzzle - tr) * 0.85
	local len = (muzzle - breech).Magnitude
	local up = (Vector3.yAxis - axis * axis.Y).Unit
	local side = axis:Cross(up).Unit
	local function frame(t: number): CFrame
		local p = breech + axis * len * t
		return CFrame.lookAt(p, p + axis, up)
	end
	local colors = Game.lookColors(look)
	local second = look.strap or look.collar or look.color
	local collar = look.collar or look.strap or look.color
	local tag = "P" .. math.floor(level)
	local f = Instance.new("Model")
	f.Name = "PrestigeTrim"
	local function band(b, cs: { Color3 })
		if idx >= (b.from or 1) then ring(f, "BarrelTrim", frame(b.t), b.r * k, 24, b.w * k * 0.45, b.w * k, cs, NEON) end
	end
	if kit.lip then band(kit.lip, colors) end
	for i, b in ipairs(kit.bands or {}) do band(b, if i == 1 then colors else { second }) end
	for _, b in ipairs(kit.collars or {}) do band(b, { collar }) end
	-- victory rings: one more each milestone, up to five
	if kit.victory then
		local v = kit.victory
		for i = 1, math.min(idx, 5) do
			ring(f, "BarrelTrim", frame(v.t + (i - 1) * v.step), v.r * k, 22, v.w * k * 0.45, v.w * k, if i == 1 then colors else { second }, NEON)
		end
	end
	-- accelerator hoops: floating round both rails, one more each milestone
	if kit.hoops then
		local hp = kit.hoops
		for i = 1, math.min(idx, hp.max) do
			local t = hp.t + (i - 1) * hp.step
			ring(f, "BarrelTrim", frame(t), hp.r * k, 32, hp.w * k, hp.w * k, colors, NEON)
			-- (two struts tie each hoop to the rails, so it doesn't float in nothing)
			for _, s in ipairs({ -1, 1 }) do
				local a = frame(t).Position + up * s * 8.4 * k
				local b = frame(t).Position + up * s * (hp.r - 0.3) * k
				part(f, "BarrelTrim", Vector3.new(0.3 * k, 0.3 * k, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), INK)
			end
		end
	end
	if kit.tips and idx >= kit.tips.from then
		for _, s in ipairs({ -1, 1 }) do
			part(f, "BarrelTrim", Vector3.one * kit.tips.r * 2 * k, frame(kit.tips.t) * CFrame.new(0, s * kit.tips.off * k, 0), second, NEON, Enum.PartType.Ball)
		end
	end
	-- twin racing stripes along the top
	if kit.stripes and idx >= kit.stripes.from then
		local st = kit.stripes
		local l = (st.t1 - st.t0) * len
		for _, s in ipairs({ -1, 1 }) do
			local a = s * st.gap
			local off = (up * math.cos(a) + side * math.sin(a)) * st.r * k
			local p = breech + axis * len * (st.t0 + st.t1) / 2 + off
			part(f, "BarrelTrim", Vector3.new(st.w * k, 0.2 * k, l), CFrame.lookAt(p, p + axis, off.Unit), colors[1], NEON)
		end
	end
	-- the P badge: on the barrel's side, or on the trunnion hub, or a roundel on the hull
	if kit.badge and idx >= kit.badge.from then
		for _, s in ipairs({ -1, 1 }) do
			local p = breech + axis * len * kit.badge.t + side * s * kit.badge.out * k
			badge(f, CFrame.lookAt(p, p + side * s, up), kit.badge.size * k, tag, look.color)
		end
	end
	if kit.hub and idx >= kit.hub.from then
		-- (on the mount the barrel turns on: it stays put, so these are Trim)
		local hb = kit.hub
		for _, s in ipairs({ -1, 1 }) do
			local p = (pivot * CFrame.new(hb.pos.X * k, hb.pos.Y * k, s * hb.pos.Z * k)).Position
			local out = pivot:VectorToWorldSpace(Vector3.new(0, 0, s))
			local face = CFrame.lookAt(p, p + out)
			part(f, "Trim", Vector3.new(0.3 * k, hb.size * 1.15 * k, hb.size * 1.15 * k), face * CFrame.Angles(0, math.pi / 2, 0), colors[1], NEON, Enum.PartType.Cylinder)
			badge(f, face * CFrame.new(0, 0, -0.17 * k), hb.size * 0.8 * k, tag, Color3.new(1, 1, 1), "Trim")
		end
	end
	if kit.roundel and idx >= kit.roundel.from then
		local rd = kit.roundel
		for _, s in ipairs({ -1, 1 }) do
			local c = pivot * CFrame.new(rd.pos.X * k, rd.pos.Y * k, s * rd.pos.Z * k)
			local out = pivot:VectorToWorldSpace(Vector3.new(0, 0, s))
			local face = CFrame.lookAt(c.Position, c.Position + out)
			part(f, "Trim", Vector3.new(0.2 * k, rd.r * 2 * k, rd.r * 2 * k), face * CFrame.Angles(0, math.pi / 2, 0), colors[1], NEON, Enum.PartType.Cylinder)
			part(f, "Trim", Vector3.new(0.24 * k, rd.r * 1.55 * k, rd.r * 1.55 * k), face * CFrame.new(0, 0, -0.03 * k) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(244, 241, 232), nil, Enum.PartType.Cylinder)
			badge(f, face * CFrame.new(0, 0, -0.16 * k), rd.r * 1.15 * k, tag, colors[1], "Trim")
		end
	end
	for _, fl in ipairs(kit.flags or {}) do
		if idx >= fl.from then
			pennant(f, pivot * CFrame.new(fl.pos * k), fl.h, look.color, k, tag, fl.whip)
		end
	end
	for _, rm in ipairs(kit.rims or {}) do
		if idx >= rm.from then flatRing(f, pivot, Vector3.new(0, rm.y * k, 0), rm.r * k, rm.w * k, if rm.from > 5 then { second } else colors) end
	end
	if kit.hubcaps and idx >= kit.hubcaps.from then
		local hc = kit.hubcaps
		for _, s in ipairs({ -1, 1 }) do
			local c = pivot * CFrame.new(hc.pos.X * k, hc.pos.Y * k, s * hc.pos.Z * k)
			local out = pivot:VectorToWorldSpace(Vector3.new(0, 0, s))
			local face = CFrame.lookAt(c.Position, c.Position + out)
			part(f, "Trim", Vector3.new(0.35 * k, hc.r * 2 * k, hc.r * 2 * k), face * CFrame.Angles(0, math.pi / 2, 0), collar, NEON, Enum.PartType.Cylinder)
			part(f, "Trim", Vector3.new(0.45 * k, hc.r * 0.8 * k, hc.r * 0.8 * k), face * CFrame.Angles(0, math.pi / 2, 0), colors[1], NEON, Enum.PartType.Cylinder)
		end
	end
	f.Parent = model
	return true
end

function PrestigeLook.trimCannon(model: Model?, level: number?, scale: number?)
	if not model then return end
	clear(model, "PrestigeTrim")
	local look = Game.prestigeLook(level)
	if not look then return end
	-- the build's own kit
	local n, child = buildOf(model)
	if n and child and trimKit(model, child, KIT[n], look, lookIndex(look), level or 0, scale or 1) then return end
	-- (anything else: the general trim, fitted to whatever barrel it finds)
	local mid, axis, len, r, parts = boreOf(model, scale or 1)
	if not mid then
		local barrel
		barrel, mid, axis, len, r = barrelOf(model)
		if not barrel then return end
		parts = { barrel :: BasePart }
	end
	if len <= 0 then return end
	local f = Instance.new("Model")
	f.Name = "PrestigeTrim"
	local colors = Game.lookColors(look)
	local up = (Vector3.yAxis - axis * axis:Dot(Vector3.yAxis))
	up = if up.Magnitude > 1e-3 then up.Unit else Vector3.zAxis
	local side = axis:Cross(up).Unit
	-- the barrel's radius `t` of the way along it: the cannons flare at the muzzle, so the body is about
	-- four fifths of the muzzle (the meshes collide as boxes, so a ray can't measure the body itself)
	local function rAt(t: number): number
		return r * (if t >= 0.9 then 1 else 0.78)
	end
	local function frame(t: number): CFrame
		local p = along(mid, axis, len, t)
		return CFrame.lookAt(p, p + axis, up)
	end
	-- the muzzle ring and the collars
	ring(f, "BarrelTrim", frame(0.97), r * 1.04, 18, r * 0.12, r * 0.3, colors, NEON)
	if look.collar then
		for _, t in ipairs({ 0.3, 0.68 }) do ring(f, "BarrelTrim", frame(t), rAt(t) * 1.03, 18, r * 0.11, r * 0.24, { look.collar }) end
	end
	if look.strap then ring(f, "BarrelTrim", frame(0.5), rAt(0.5) * 1.025, 18, r * 0.09, r * 0.11, { look.strap }) end
	-- the tube along the top of the barrel (the prism in three lengths)
	local n = #colors
	local tubeLen = len * 0.36
	for i, c in ipairs(colors) do
		local t = 0.5 - 0.18 + (i - 0.5) / n * 0.36 + 0.02
		local p = along(mid, axis, len, t) + up * rAt(t) * 1.02
		part(f, "BarrelTrim", Vector3.new(r * 0.2, r * 0.13, tubeLen / n * 0.96), CFrame.lookAt(p, p + axis, up), c, NEON)
	end
	-- a P badge on each side by the breech
	for _, s in ipairs({ -1, 1 }) do
		local p = along(mid, axis, len, 0.2) + side * s * rAt(0.2) * 1.04
		badge(f, CFrame.lookAt(p, p + side * s, up), r * 0.8, "P" .. math.floor(level or 0), look.color)
	end
	f.Parent = model
end

return PrestigeLook
