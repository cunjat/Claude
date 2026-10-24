--!strict
-- TYRE CANNON :: RoadDecor
-- The Roadside Decor Pack (2026-10-15, from the "Tyre Cannon Decor Pack 2" design canvas): twelve yard
-- pieces from the road the game drives (the Backroad, the Grand Trunk, the Thar), built from parts like
-- NeonDecor so they need no imported model. Chunky toy shapes in bright paint; no lights, no glow.
-- NeonDecor.build hands any kind it doesn't know to RoadDecor.BUILD.
--   planter     Tyre Planter       two tyres, the top one kerb-painted, full of marigolds
--   milestone   Milestone          the yellow-capped highway stone: THAR 12 KM
--   charpai     Charpai            the dhaba's rope cot, a steel tumbler of chai on it
--   matka       Matka Stand        clay water pots on a wooden rack
--   chaicart    Chai Cart          a red cart under a fringed blue canopy, kettle on
--   tyreswing   Tyre Swing         a tyre on ropes from a wooden A-frame
--   tyrepyramid Tyre Pyramid       six tyres 3-2-1, every rim a different paint
--   toran       Marigold Toran     bamboo poles strung with marigolds and mango leaves
--   scooter     Old Scooter        a teal 70s scooter on its stand
--   toolwall    Tool Wall          a pegboard of spanners, a hammer, a tyre lever, an inner tube
--   fuelpump    Vintage Fuel Pump  red, a round painted top, a dial and a hose
--   hornok      Honk Please        a goods-truck tailgate up on posts

local RoadDecor = {}

local PLASTIC = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local WOOD = Enum.Material.Wood
local FABRIC = Enum.Material.Fabric
local function rgb(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end
local INK, WHITE, GREY, STEEL = rgb(14, 15, 19), rgb(244, 241, 232), rgb(138, 143, 156), rgb(201, 207, 220)
local RED, ORANGE, YELLOW, BLUE = rgb(229, 53, 43), rgb(242, 122, 26), rgb(255, 194, 58), rgb(47, 111, 214)
local GREEN, LEAF, TEAL = rgb(63, 174, 106), rgb(46, 140, 72), rgb(47, 179, 166)
local RUBBER, RUBBER2 = rgb(30, 31, 36), rgb(44, 46, 54)
local TIMBER, TIMBER2, ROPE = rgb(201, 143, 85), rgb(138, 90, 46), rgb(240, 217, 168)
local CLAY, CLAY2, SOIL = rgb(196, 100, 58), rgb(143, 63, 28), rgb(91, 58, 34)
local BAMBOO, BAMBOO2 = rgb(201, 168, 106), rgb(160, 128, 70)
local VERT = CFrame.Angles(0, 0, math.pi / 2)    -- a cylinder standing up
local ACROSS = CFrame.Angles(0, math.pi / 2, 0)  -- a cylinder lying along Z (a wheel facing X)

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or PLASTIC
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

local function cyl(parent: Instance, length: number, dia: number, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	return part(parent, Vector3.new(length, dia, dia), cf, color, mat, Enum.PartType.Cylinder)
end

local function ball(parent: Instance, dia: number, at: Vector3, color: Color3, mat: Enum.Material?): Part
	return part(parent, Vector3.new(dia, dia, dia), CFrame.new(at), color, mat, Enum.PartType.Ball)
end

-- a beam from a to b
local function beam(parent: Instance, a: Vector3, b: Vector3, w: number, color: Color3, mat: Enum.Material?): Part
	local mid = (a + b) / 2
	return part(parent, Vector3.new(w, w, (b - a).Magnitude), CFrame.lookAt(mid, b), color, mat)
end

-- a ring of n blocks round at's local Z axis (a tyre's tread paint, an inner tube)
local function ring(parent: Instance, at: CFrame, r: number, n: number, thick: number, depth: number, colors: { Color3 }, mat: Enum.Material?)
	local len = 2 * math.pi * r / n * 1.08
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		part(parent, Vector3.new(len, thick, depth), at * CFrame.Angles(0, 0, a) * CFrame.new(0, r, 0), colors[i % #colors + 1], mat)
	end
end

-- a tyre lying flat (on its side): tread, sidewall lip and the dark hole
local function flatTyre(parent: Instance, at: Vector3, dia: number, h: number)
	local cf = CFrame.new(at) * VERT
	cyl(parent, h, dia, cf, RUBBER)
	cyl(parent, h + 0.06, dia * 0.5, cf, INK)
	cyl(parent, h * 0.2, dia + 0.08, cf * CFrame.new(h * 0.3, 0, 0), RUBBER2)
	cyl(parent, h * 0.2, dia + 0.08, cf * CFrame.new(-h * 0.3, 0, 0), RUBBER2)
end

-- a tyre standing on its tread, facing along Z, with a painted rim
local function upTyre(parent: Instance, at: CFrame, dia: number, w: number, rim: Color3)
	cyl(parent, w, dia, at * ACROSS, RUBBER)
	cyl(parent, w + 0.04, dia * 0.6, at * ACROSS, RUBBER2)
	cyl(parent, w + 0.08, dia * 0.46, at * ACROSS, rim, METAL)
	cyl(parent, w + 0.12, dia * 0.14, at * ACROSS, GREY, METAL)
end

-- flat text on a part's face
local function label(p: BasePart, text: string, color: Color3, face: Enum.NormalId?, stroke: Color3?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0.8
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = color
	t.Parent = sg
	if stroke then
		local s = Instance.new("UIStroke")
		s.Thickness = 2.5
		s.Color = stroke
		s.Parent = t
	end
end

-- a marigold: a ball of petals with a darker heart
local function marigold(parent: Instance, at: Vector3, dia: number, color: Color3)
	ball(parent, dia, at, color, FABRIC)
	ball(parent, dia * 0.45, at + Vector3.new(0, dia * 0.32, 0), if color == YELLOW then rgb(217, 138, 16) else rgb(184, 69, 26), FABRIC)
end

RoadDecor.BUILD = {} :: { [string]: (Model, any) -> () }
local B = RoadDecor.BUILD

B.planter = function(m)
	flatTyre(m, Vector3.new(0, 0.8, 0), 4.6, 1.6)
	flatTyre(m, Vector3.new(0, 2.35, 0), 4.6, 1.5)
	-- the top tyre painted like a kerb
	ring(m, CFrame.new(0, 2.35, 0) * CFrame.Angles(math.pi / 2, 0, 0), 2.32, 16, 0.12, 1.3, { RED, WHITE })
	cyl(m, 0.3, 3.3, CFrame.new(0, 3.0, 0) * VERT, SOIL)
	local spots = { { 0, 0, 1.0, ORANGE }, { 0.9, 0.5, 0.85, YELLOW }, { -0.9, 0.4, 0.85, YELLOW }, { 0.5, -0.9, 0.8, ORANGE },
		{ -0.6, -0.8, 0.8, ORANGE }, { 1.1, -0.4, 0.7, YELLOW }, { -1.2, -0.1, 0.7, ORANGE } }
	for i, s in ipairs(spots) do
		local h = 3.55 + (i % 3) * 0.22
		cyl(m, h - 3.1, 0.12, CFrame.new(s[1], (h + 3.1) / 2, s[2]) * VERT, LEAF)
		marigold(m, Vector3.new(s[1], h, s[2]), s[3], s[4])
	end
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		part(m, Vector3.new(0.9, 0.12, 0.45), CFrame.new(math.cos(a) * 1.25, 3.3, math.sin(a) * 1.25) * CFrame.Angles(0, -a, 0.35), GREEN)
	end
end

B.milestone = function(m)
	part(m, Vector3.new(3, 0.5, 1.7), CFrame.new(0, 0.25, 0), GREY, Enum.Material.Concrete)
	part(m, Vector3.new(2.2, 3.2, 1.2), CFrame.new(0, 2.1, 0), WHITE, Enum.Material.Concrete)
	cyl(m, 1.2, 2.2, CFrame.new(0, 3.7, 0) * ACROSS, YELLOW)
	part(m, Vector3.new(2.22, 0.35, 1.22), CFrame.new(0, 3.55, 0), YELLOW)
	local plate = part(m, Vector3.new(1.9, 2.2, 0.05), CFrame.new(0, 2.05, -0.62), WHITE)
	label(plate, "THAR\n12 KM", RED, Enum.NormalId.Front)
	local back = part(m, Vector3.new(1.9, 2.2, 0.05), CFrame.new(0, 2.05, 0.62), WHITE)
	label(back, "THAR\n12 KM", RED, Enum.NormalId.Back)
end

B.charpai = function(m)
	for _, x in ipairs({ -3.2, 3.2 }) do
		for _, z in ipairs({ -1.5, 1.5 }) do
			cyl(m, 1.7, 0.6, CFrame.new(x, 0.85, z) * VERT, TIMBER2, WOOD)
			ball(m, 0.7, Vector3.new(x, 1.75, z), TIMBER2, WOOD)
		end
	end
	for _, z in ipairs({ -1.5, 1.5 }) do part(m, Vector3.new(7, 0.4, 0.4), CFrame.new(0, 1.6, z), TIMBER, WOOD) end
	for _, x in ipairs({ -3.2, 3.2 }) do part(m, Vector3.new(0.4, 0.4, 3.4), CFrame.new(x, 1.6, 0), TIMBER, WOOD) end
	-- the rope weave: two layers of diagonals
	for i = -6, 6 do
		local x = i * 0.5
		part(m, Vector3.new(0.14, 0.08, 3.4), CFrame.new(x, 1.66, 0) * CFrame.Angles(0, 0.45, 0), ROPE, FABRIC)
		part(m, Vector3.new(0.14, 0.08, 3.4), CFrame.new(x, 1.7, 0) * CFrame.Angles(0, -0.45, 0), ROPE, FABRIC)
	end
	cyl(m, 0.65, 0.45, CFrame.new(1.4, 2.1, 0.3) * VERT, STEEL, METAL)
	cyl(m, 0.06, 0.38, CFrame.new(1.4, 2.4, 0.3) * VERT, rgb(176, 112, 60))
end

B.matka = function(m)
	for _, x in ipairs({ -2.7, 2.7 }) do
		for _, z in ipairs({ -0.9, 0.9 }) do part(m, Vector3.new(0.35, 2.2, 0.35), CFrame.new(x, 1.1, z), TIMBER2, WOOD) end
	end
	part(m, Vector3.new(6, 0.35, 2.2), CFrame.new(0, 2.25, 0), TIMBER, WOOD)
	part(m, Vector3.new(5.6, 0.25, 1.9), CFrame.new(0, 0.6, 0), TIMBER, WOOD)
	for _, p in ipairs({ { -1.9, 1.9 }, { 0, 2.3 }, { 1.9, 1.9 } }) do
		local x, d = p[1], p[2]
		local y = 2.4 + d * 0.48
		ball(m, d, Vector3.new(x, y, 0), CLAY)
		cyl(m, 0.12, d * 0.86, CFrame.new(x, y + d * 0.1, 0) * VERT, WHITE)
		cyl(m, 0.5, d * 0.42, CFrame.new(x, y + d * 0.52, 0) * VERT, CLAY)
		cyl(m, 0.18, d * 0.55, CFrame.new(x, y + d * 0.74, 0) * VERT, CLAY2)
		cyl(m, 0.08, d * 0.5, CFrame.new(x, y + d * 0.8, 0) * VERT, STEEL, METAL)
	end
	beam(m, Vector3.new(3.05, 2.3, 0), Vector3.new(3.4, 4.2, 0), 0.12, STEEL, METAL)
	cyl(m, 0.3, 0.6, CFrame.new(3.05, 2.2, 0) * VERT, STEEL, METAL)
end

B.chaicart = function(m)
	part(m, Vector3.new(6, 1.8, 3), CFrame.new(0, 2.2, 0), RED)
	part(m, Vector3.new(6.2, 0.2, 3.2), CFrame.new(0, 3.15, 0), TIMBER, WOOD)
	local board = part(m, Vector3.new(5, 1.2, 0.1), CFrame.new(0, 2.2, -1.53), WHITE)
	label(board, "CHAI  ₹10", RED, Enum.NormalId.Front)
	for _, z in ipairs({ -1.75, 1.75 }) do
		local at = CFrame.new(0.4, 1.25, z)
		cyl(m, 0.25, 2.5, at * CFrame.Angles(0, math.pi / 2, 0), RUBBER)
		cyl(m, 0.28, 2.0, at * CFrame.Angles(0, math.pi / 2, 0), STEEL, METAL)
		cyl(m, 0.32, 0.4, at * CFrame.Angles(0, math.pi / 2, 0), GREY, METAL)
	end
	for _, z in ipairs({ -1.2, 1.2 }) do beam(m, Vector3.new(-3, 2.0, z), Vector3.new(-4.4, 2.4, z), 0.2, TIMBER2, WOOD) end
	beam(m, Vector3.new(-2.6, 1.3, 0), Vector3.new(-2.6, 0, 0), 0.25, TIMBER2, WOOD)
	for _, x in ipairs({ -2.8, 2.8 }) do
		for _, z in ipairs({ -1.35, 1.35 }) do cyl(m, 2.9, 0.16, CFrame.new(x, 4.7, z) * VERT, GREY, METAL) end
	end
	part(m, Vector3.new(6.6, 0.3, 3.6), CFrame.new(0, 6.2, 0), BLUE, FABRIC)
	part(m, Vector3.new(6.0, 0.4, 3.0), CFrame.new(0, 6.5, 0), rgb(37, 92, 184), FABRIC)
	for i = 0, 10 do
		local x = -3.0 + i * 0.6
		for _, z in ipairs({ -1.8, 1.8 }) do
			part(m, Vector3.new(0.38, 0.38, 0.06), CFrame.new(x, 5.95, z) * CFrame.Angles(0, 0, math.pi / 4), YELLOW, FABRIC)
		end
	end
	cyl(m, 0.9, 1.0, CFrame.new(-1.2, 3.7, 0) * VERT, STEEL, METAL)
	ball(m, 0.5, Vector3.new(-1.2, 4.2, 0), STEEL, METAL)
	beam(m, Vector3.new(-0.75, 3.6, 0), Vector3.new(-0.3, 4.0, 0), 0.16, STEEL, METAL)
	for i = 0, 2 do
		local g = cyl(m, 0.5, 0.32, CFrame.new(0.6 + i * 0.5, 3.5, 0.6) * VERT, rgb(214, 156, 92), Enum.Material.Glass)
		g.Transparency = 0.2
	end
end

B.tyreswing = function(m)
	for _, x in ipairs({ -3.6, 3.6 }) do
		for _, z in ipairs({ -1.6, 1.6 }) do beam(m, Vector3.new(x, 0, z), Vector3.new(x, 7.6, 0), 0.5, TIMBER2, WOOD) end
	end
	cyl(m, 8, 0.65, CFrame.new(0, 7.7, 0), TIMBER, WOOD)
	for _, x in ipairs({ -0.7, 0.7 }) do beam(m, Vector3.new(x, 7.4, 0), Vector3.new(x * 0.6, 3.7, 0), 0.13, ROPE, FABRIC) end
	local at = CFrame.new(0, 2.5, 0)
	cyl(m, 1.1, 3.2, at * ACROSS, RUBBER)
	cyl(m, 1.14, 1.7, at * ACROSS, INK)
	cyl(m, 0.16, 3.25, at * ACROSS, YELLOW)
end

B.tyrepyramid = function(m)
	local rims = { YELLOW, RED, BLUE, WHITE, YELLOW, RED }
	local k = 0
	for row, xs in ipairs({ { -3.1, 0, 3.1 }, { -1.55, 1.55 }, { 0 } }) do
		for _, x in ipairs(xs) do
			k += 1
			upTyre(m, CFrame.new(x, 1.5 + (row - 1) * 2.62, 0), 3.0, 1.3, rims[k])
		end
	end
end

B.toran = function(m)
	for _, x in ipairs({ -5, 5 }) do
		cyl(m, 9, 0.5, CFrame.new(x, 4.5, 0) * VERT, BAMBOO, WOOD)
		for y = 1, 8, 1.8 do cyl(m, 0.18, 0.58, CFrame.new(x, y, 0) * VERT, BAMBOO2, WOOD) end
		part(m, Vector3.new(1.2, 0.3, 1.2), CFrame.new(x, 0.15, 0), GREY, Enum.Material.Concrete)
	end
	local function sag(x: number): number return 8.4 - 1.6 * (1 - (x / 5) ^ 2) end
	local x = -4.6
	local i = 0
	while x <= 4.6 do
		i += 1
		marigold(m, Vector3.new(x, sag(x), 0), 0.62, if i % 2 == 0 then ORANGE else YELLOW)
		x += 0.52
	end
	for s, sx in ipairs({ -3.4, -1.7, 0, 1.7, 3.4 }) do
		local top = sag(sx)
		local n = if s % 2 == 1 then 6 else 4
		for j = 1, n do marigold(m, Vector3.new(sx, top - j * 0.55, 0), 0.5, if j % 2 == 0 then YELLOW else ORANGE) end
		part(m, Vector3.new(0.5, 0.9, 0.08), CFrame.new(sx + 0.85, sag(sx + 0.85) - 0.55, 0) * CFrame.Angles(0, 0, 0.15), LEAF)
	end
end

B.scooter = function(m)
	for _, x in ipairs({ -2.2, 2.0 }) do
		local at = CFrame.new(x, 0.75, 0)
		cyl(m, 0.6, 1.5, at * ACROSS, RUBBER)
		cyl(m, 0.66, 0.8, at * ACROSS, STEEL, METAL)
	end
	part(m, Vector3.new(2.6, 1.4, 1.6), CFrame.new(1.4, 1.7, 0), TEAL)
	cyl(m, 1.6, 1.9, CFrame.new(2.1, 1.9, 0) * ACROSS, TEAL)
	part(m, Vector3.new(2.4, 0.45, 1.2), CFrame.new(1.3, 2.75, 0), INK, FABRIC)
	part(m, Vector3.new(0.6, 0.35, 1.0), CFrame.new(2.9, 2.2, 0), RED)
	part(m, Vector3.new(2.2, 0.35, 1.3), CFrame.new(-0.6, 1.0, 0), TEAL)
	part(m, Vector3.new(0.4, 2.6, 1.5), CFrame.new(-1.75, 2.1, 0) * CFrame.Angles(0, 0, -0.18), TEAL)
	part(m, Vector3.new(1.3, 0.35, 0.9), CFrame.new(-2.2, 1.6, 0), TEAL)
	beam(m, Vector3.new(-2.0, 3.2, 0), Vector3.new(-2.25, 4.3, 0), 0.4, TEAL)
	cyl(m, 2.0, 0.22, CFrame.new(-2.3, 4.4, 0) * ACROSS, STEEL, METAL)
	part(m, Vector3.new(0.6, 0.6, 0.8), CFrame.new(-2.35, 4.35, 0), TEAL)
	cyl(m, 0.2, 0.62, CFrame.new(-2.67, 4.35, 0), WHITE)
	cyl(m, 0.08, 0.66, CFrame.new(-2.76, 4.35, 0), STEEL, METAL)
	beam(m, Vector3.new(-2.3, 4.5, -0.8), Vector3.new(-2.2, 5.2, -0.9), 0.08, STEEL, METAL)
	cyl(m, 0.08, 0.5, CFrame.new(-2.2, 5.3, -0.9), STEEL, METAL)
	beam(m, Vector3.new(0.6, 0.9, 0.4), Vector3.new(0.4, 0, 0.6), 0.14, GREY, METAL)
end

B.toolwall = function(m)
	for _, x in ipairs({ -3.6, 3.6 }) do part(m, Vector3.new(0.4, 7, 0.4), CFrame.new(x, 3.5, 0.25), GREY, METAL) end
	part(m, Vector3.new(8, 5, 0.25), CFrame.new(0, 4.4, 0), TIMBER, WOOD)
	for _, s in ipairs({ { 0, 6.95, 8.3, 0.35 }, { 0, 1.85, 8.3, 0.35 } }) do part(m, Vector3.new(s[3], s[4], 0.35), CFrame.new(s[1], s[2], 0), TIMBER2, WOOD) end
	for _, x in ipairs({ -4, 4 }) do part(m, Vector3.new(0.35, 5.4, 0.35), CFrame.new(x, 4.4, 0), TIMBER2, WOOD) end
	for ix = 0, 9 do
		for iy = 0, 5 do
			part(m, Vector3.new(0.12, 0.12, 0.04), CFrame.new(-3.4 + ix * 0.76, 2.4 + iy * 0.8, -0.13), TIMBER2)
		end
	end
	local f = -0.2
	for i, x in ipairs({ -3.0, -2.4 }) do
		local len = 2.6 - i * 0.5
		part(m, Vector3.new(0.26, len, 0.1), CFrame.new(x, 4.3, f), STEEL, METAL)
		cyl(m, 0.12, 0.62, CFrame.new(x, 4.3 + len / 2, f) * ACROSS, STEEL, METAL)
	end
	part(m, Vector3.new(0.22, 2.4, 0.12), CFrame.new(-1.2, 4.0, f), TIMBER2, WOOD)
	part(m, Vector3.new(1.2, 0.5, 0.3), CFrame.new(-1.2, 5.3, f - 0.05), RED, METAL)
	part(m, Vector3.new(0.26, 2.4, 0.12), CFrame.new(0.4, 4.2, f), BLUE, METAL)
	part(m, Vector3.new(0.26, 0.8, 0.12), CFrame.new(0.62, 5.6, f) * CFrame.Angles(0, 0, -0.5), BLUE, METAL)
	ring(m, CFrame.new(2.4, 4.5, f - 0.1), 1.15, 16, 0.42, 0.42, { RUBBER })
	cyl(m, 0.5, 0.2, CFrame.new(2.4, 5.7, f) * ACROSS, GREY, METAL)
end

B.fuelpump = function(m)
	part(m, Vector3.new(3.2, 0.4, 2.4), CFrame.new(0, 0.2, 0), GREY, Enum.Material.Concrete)
	part(m, Vector3.new(2.4, 5, 1.6), CFrame.new(0, 2.9, 0), RED)
	part(m, Vector3.new(2.6, 0.3, 1.8), CFrame.new(0, 5.45, 0), STEEL, METAL)
	cyl(m, 0.1, 1.4, CFrame.new(0, 3.9, -0.82) * CFrame.Angles(0, math.pi / 2, 0), WHITE)
	part(m, Vector3.new(0.06, 0.55, 0.05), CFrame.new(0.15, 4.05, -0.88) * CFrame.Angles(0, 0, -0.7), INK)
	part(m, Vector3.new(1.8, 0.5, 0.05), CFrame.new(0, 2.6, -0.82), YELLOW)
	cyl(m, 0.5, 0.7, CFrame.new(0, 5.85, 0) * VERT, STEEL, METAL)
	ball(m, 2.2, Vector3.new(0, 7.1, 0), WHITE)
	cyl(m, 0.45, 2.25, CFrame.new(0, 7.1, 0) * VERT, RED)
	local plate = part(m, Vector3.new(1.6, 0.7, 0.05), CFrame.new(0, 7.1, -1.14), RED)
	label(plate, "FUEL", WHITE, Enum.NormalId.Front)
	beam(m, Vector3.new(1.2, 3.6, 0), Vector3.new(1.9, 3.0, 0), 0.24, RUBBER)
	beam(m, Vector3.new(1.9, 3.0, 0), Vector3.new(2.0, 1.4, 0), 0.24, RUBBER)
	part(m, Vector3.new(0.4, 0.8, 0.3), CFrame.new(1.35, 3.8, 0), GREY, METAL)
	beam(m, Vector3.new(2.0, 1.4, 0), Vector3.new(1.6, 1.0, 0), 0.24, RUBBER)
end

B.hornok = function(m)
	for _, x in ipairs({ -4.8, 4.8 }) do part(m, Vector3.new(0.5, 9, 0.5), CFrame.new(x, 4.5, 0.3), GREY, METAL) end
	part(m, Vector3.new(11.6, 5, 0.35), CFrame.new(0, 6.5, 0), YELLOW)
	part(m, Vector3.new(10.6, 4, 0.1), CFrame.new(0, 6.5, -0.2), BLUE)
	part(m, Vector3.new(10.6, 4, 0.1), CFrame.new(0, 6.5, 0.2), BLUE)
	for _, c in ipairs({ { -5.1, 8.3 }, { 5.1, 8.3 }, { -5.1, 4.7 }, { 5.1, 4.7 } }) do
		for _, z in ipairs({ -0.26, 0.26 }) do
			part(m, Vector3.new(0.9, 0.9, 0.06), CFrame.new(c[1], c[2], z) * CFrame.Angles(0, 0, math.pi / 4), RED)
		end
	end
	for _, x in ipairs({ -4.2, 4.2 }) do
		for _, z in ipairs({ -0.28, 0.28 }) do cyl(m, 0.08, 0.9, CFrame.new(x, 6.5, z) * CFrame.Angles(0, math.pi / 2, 0), RED) end
	end
	local top = part(m, Vector3.new(7, 1.5, 0.05), CFrame.new(0, 7.3, -0.27), BLUE)
	label(top, "HONK", YELLOW, Enum.NormalId.Front, INK)
	local bottom = part(m, Vector3.new(6, 1.3, 0.05), CFrame.new(0, 5.6, -0.27), BLUE)
	label(bottom, "PLEASE", WHITE, Enum.NormalId.Front, INK)
	local top2 = part(m, Vector3.new(7, 1.5, 0.05), CFrame.new(0, 7.3, 0.27), BLUE)
	label(top2, "HONK", YELLOW, Enum.NormalId.Back, INK)
	local bottom2 = part(m, Vector3.new(6, 1.3, 0.05), CFrame.new(0, 5.6, 0.27), BLUE)
	label(bottom2, "PLEASE", WHITE, Enum.NormalId.Back, INK)
end

return RoadDecor
