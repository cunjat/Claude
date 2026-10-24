--!strict
-- TYRE CANNON :: NeonDecor
-- The neon decor pack (Game.YardDecor kinds with `build`, from the Prestige & Neon design canvas,
-- 2026-10-12): chunky pieces built from parts, so they need no imported model. The tubes are thin
-- Neon parts, and each piece carries one light in its tube colour (2026-10-17: the owner lifted the
-- no-glow rule so the pack really glows; the lamp shines down like a street lamp). Prestige pieces take the
-- owner's milestone colour; the Midnight Garage pieces take the yard's colourway.
--   NeonDecor.build(kindId, opts?) -> Model (unparented, standing on y 0) or nil
--   NeonDecor.optsFor(plot) -> the colours a yard's pieces use

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
-- the Roadside Decor Pack (2026-10-15) is built the same way, in its own module
local RoadDecor = require(script.Parent:WaitForChild("RoadDecor"))
local Models = require(script.Parent:WaitForChild("Models"))

-- the real models (Blender, bundled and filed into Assets by tools/sort_import.luau): the prestige
-- pieces (art/blender/prestige.py, TC_Prestige), each a Body and an Accent mesh with the Accent
-- painted the owner's milestone colour, and the Roadside Decor Pack (roadside.py, TC_Roadside).
-- Until they're imported, the part-built ones below (and RoadDecor's) stand in.
local MODEL: { [string]: string } = {
	laurel = "Prestige/PrestigeLaurel", pillar = "Prestige/PrestigePillar", podium = "Prestige/PrestigePodium",
	goldtyre = "Prestige/PrestigeGoldTyre", crownarch = "Prestige/PrestigeCrownArch", prismbanner = "Prestige/PrestigeBanner",
	planter = "Roadside/RoadPlanter", milestone = "Roadside/RoadMilestone", charpai = "Roadside/RoadCharpai",
	matka = "Roadside/RoadMatka", chaicart = "Roadside/RoadChaiCart", tyreswing = "Roadside/RoadTyreSwing",
	tyrepyramid = "Roadside/RoadTyrePyramid", toran = "Roadside/RoadToran", scooter = "Roadside/RoadScooter",
	toolwall = "Roadside/RoadToolWall", fuelpump = "Roadside/RoadFuelPump", hornok = "Roadside/RoadHonk",
}

local NeonDecor = {}

-- "neon" tubes: flat bright paint unless Game.NeonTubes (Neon blooms, and the art rules say no glow)
local NEON = if Game.NeonTubes then Enum.Material.Neon else Enum.Material.SmoothPlastic
local PLASTIC = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local function rgb(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end
local NAVY, NAVY2 = rgb(31, 42, 68), rgb(44, 58, 94)
local INK, WHITE, GREY = rgb(14, 15, 19), rgb(244, 241, 232), rgb(154, 163, 181)
local GOLD, GOLD2 = rgb(255, 194, 58), rgb(255, 224, 138)
local ORANGE, RED, BLUE = rgb(242, 122, 26), rgb(229, 53, 43), rgb(47, 111, 214)
local RUBBER = rgb(30, 31, 36)
local VERT = CFrame.Angles(0, 0, math.pi / 2)    -- a cylinder standing up
local FACING = CFrame.Angles(0, math.pi / 2, 0)  -- a cylinder facing +Z (a disc you look at)

export type Opts = { color: Color3?, colors: { Color3 }?, level: number?, a: Color3?, b: Color3?, showcase: string? }

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = mat ~= NEON
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

-- a ring of `n` blocks round `at`'s local Z axis
local function ring(parent: Instance, at: CFrame, r: number, n: number, thick: number, depth: number, color: Color3 | { Color3 }, mat: Enum.Material?)
	local len = 2 * math.pi * r / n * 1.08
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local c = if typeof(color) == "Color3" then color else (color :: { Color3 })[i % #(color :: { Color3 }) + 1]
		part(parent, Vector3.new(len, thick, depth), at * CFrame.Angles(0, 0, a) * CFrame.new(0, r, 0), c, mat)
	end
end

-- big flat text on a part's front face
local function label(p: BasePart, text: string, color: Color3, face: Enum.NormalId?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0.6
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

-- one light per built piece, in the colour of its biggest Neon tube (none while Game.NeonTubes is off)
local function glow(m: Model, kindId: string)
	if not Game.NeonTubes then return end
	local best: BasePart? = nil
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p.Material == Enum.Material.Neon and (best == nil or p.Size.Magnitude > (best :: BasePart).Size.Magnitude) then
			best = p
		end
	end
	if not best then return end
	local l: Light
	if kindId == "neonlamp" then
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 80
		spot.Range = 22
		spot.Brightness = 3
		l = spot
	else
		local point = Instance.new("PointLight")
		point.Range = 12
		point.Brightness = 1.6
		l = point
	end
	l.Color = (best :: BasePart).Color
	l.Shadows = false
	l.Parent = best
end

local function main(o: Opts): Color3 return o.color or rgb(63, 184, 255) end
local function tubeA(o: Opts): Color3 return o.a or rgb(224, 64, 251) end
local function tubeB(o: Opts): Color3 return o.b or rgb(46, 230, 242) end

-- the Tyre Showcase (v4): the owner's three best tyres on stands, the best raised in the middle, a
-- strip in each one's rarity colour and a mutation ring on its stand
local function showcase(m: Model, o: Opts)
	local TyreLook = require(script.Parent:WaitForChild("TyreLook")) :: any
	local list = {}
	for entry in string.gmatch(o.showcase or "", "[^,]+") do
		local id, mut = string.match(entry, "^([%w_]+):?([%w_]*)")
		if id and Game.TyresById[id] then table.insert(list, { id = id, mut = if mut ~= "" then mut else nil }) end
	end
	if #list == 0 then list = { { id = Game.StarterTyre } } end
	part(m, Vector3.new(9.2, 0.6, 3.6), CFrame.new(0, 0.3, 0), NAVY)
	part(m, Vector3.new(9.4, 0.18, 0.2), CFrame.new(0, 0.52, -1.82), GOLD, METAL)
	part(m, Vector3.new(8.6, 0.12, 3.0), CFrame.new(0, 0.66, 0), NAVY2)
	-- best in the middle, raised; then left and right
	local slots = { { x = 0, h = 1.6 }, { x = -3.0, h = 0.9 }, { x = 3.0, h = 0.9 } }
	for i, s in ipairs(slots) do
		local t = list[i]
		local def = t and Game.TyresById[t.id]
		local rar = def and Game.RaritiesById[def.rarity]
		cyl(m, s.h, 1.6, CFrame.new(s.x, 0.66 + s.h / 2, 0.2) * VERT, GREY, METAL)
		cyl(m, 0.14, 1.9, CFrame.new(s.x, 0.66 + s.h, 0.2) * VERT, if rar then rar.color else GREY, NEON)
		part(m, Vector3.new(2.2, 0.08, 0.16), CFrame.new(s.x, 0.62, -1.6), if rar then rar.color else GREY, NEON)
		local mu = t and t.mut and Game.MutationsById[t.mut]
		if mu then cyl(m, 0.1, 1.75, CFrame.new(s.x, 0.66 + s.h * 0.5, 0.2) * VERT, mu.color, NEON) end
		if t then
			local ok, tyre = pcall(function() return TyreLook.model(t.id, if i == 1 then 3.4 else 2.8, "ShowTyre") end)
			if ok and tyre then
				for _, p in ipairs(tyre:GetDescendants()) do
					if p:IsA("BasePart") then
						p.Anchored = true
						p.CanCollide = false
						p.CanQuery = false
						p.CanTouch = false
					end
				end
				local r = if i == 1 then 1.7 else 1.4
				tyre:PivotTo(CFrame.new(s.x, 0.66 + s.h + 0.1 + r, 0.2) * CFrame.Angles(0, math.rad(if i == 2 then 18 elseif i == 3 then -18 else 0), 0))
				tyre.Parent = m
			end
		end
	end
end

local BUILD: { [string]: (Model, Opts) -> () } = {
	showcase = showcase,
	-- prestige rewards
	laurel = function(m, o)
		cyl(m, 0.12, 11, CFrame.new(0, 0.06, 0) * VERT, NAVY)
		cyl(m, 0.14, 7.2, CFrame.new(0, 0.07, 0) * VERT, NAVY2)
		for i = 0, 21 do
			local a = i / 22 * math.pi * 2
			local tilt = if i % 2 == 0 then 0.5 else -0.5
			part(m, Vector3.new(1.7, 0.22, 0.8), CFrame.Angles(0, a, 0) * CFrame.new(0, 0.24, -4.5) * CFrame.Angles(0, tilt, 0), GOLD)
		end
	end,
	pillar = function(m, o)
		part(m, Vector3.new(3, 0.6, 3), CFrame.new(0, 0.3, 0), NAVY2)
		local col = part(m, Vector3.new(2.2, 6, 2.2), CFrame.new(0, 3.6, 0), NAVY)
		label(col, "P" .. tostring(o.level or 2), main(o))
		part(m, Vector3.new(3, 0.8, 3), CFrame.new(0, 7, 0), main(o), NEON)
	end,
	podium = function(m, o)
		local steps = { { -3.1, 2.4, rgb(154, 163, 181), "2" }, { 0, 3.6, GOLD, "1" }, { 3.1, 1.6, rgb(201, 143, 85), "3" } }
		for _, s in ipairs(steps) do
			local p = part(m, Vector3.new(3, s[2], 3), CFrame.new(s[1], s[2] / 2, 0), s[3])
			label(p, s[4], WHITE)
			part(m, Vector3.new(3.02, 0.2, 0.2), CFrame.new(s[1], s[2] - 0.1, -1.5), main(o), NEON)
		end
	end,
	goldtyre = function(m, o)
		part(m, Vector3.new(4.6, 1.2, 2.8), CFrame.new(0, 0.6, 0), NAVY)
		cyl(m, 2, 6.4, CFrame.new(0, 4.4, 0) * FACING, rgb(184, 121, 26), METAL)
		cyl(m, 2.1, 4.4, CFrame.new(0, 4.4, 0) * FACING, GOLD, METAL)
		cyl(m, 2.2, 1.6, CFrame.new(0, 4.4, 0) * FACING, GOLD2, METAL)
	end,
	crownarch = function(m, o)
		for _, x in ipairs({ -4.6, 4.6 }) do part(m, Vector3.new(1.4, 9, 1.4), CFrame.new(x, 4.5, 0), NAVY) end
		for i = 0, 8 do
			local a = (i + 0.5) / 9 * math.pi
			local p = CFrame.new(math.cos(a) * 4.6, 9 + math.sin(a) * 3.2, 0)
			part(m, Vector3.new(1.9, 0.6, 0.6), p * CFrame.Angles(0, 0, a + math.pi / 2), main(o), NEON)
		end
		part(m, Vector3.new(2.6, 0.7, 0.8), CFrame.new(0, 12.75, 0), GOLD)
		for _, x in ipairs({ -0.9, 0, 0.9 }) do
			part(m, Vector3.new(0.55, 0.55, 0.55), CFrame.new(x, 13.5 + (x == 0 and 0.25 or 0), 0) * CFrame.Angles(0, 0, math.pi / 4), GOLD)
		end
	end,
	prismbanner = function(m, o)
		cyl(m, 10, 0.5, CFrame.new(-2, 5, 0) * VERT, GREY, METAL)
		local cs = o.colors or { rgb(63, 184, 255), rgb(255, 194, 58), rgb(255, 79, 163) }
		for i = 1, 3 do
			part(m, Vector3.new(4, 1.1, 0.15), CFrame.new(0.25, 9.3 - (i - 1) * 1.1, 0), cs[(i - 1) % #cs + 1])
		end
	end,
	-- the Midnight Garage pass
	neonsign = function(m, o)
		part(m, Vector3.new(0.6, 6, 0.6), CFrame.new(0, 3, 0), GREY, METAL)
		local c = CFrame.new(0, 8.4, 0)
		cyl(m, 0.4, 6.2, c * FACING, rgb(11, 8, 24))
		ring(m, c * CFrame.new(0, 0, -0.3), 2.6, 18, 0.4, 0.25, tubeB(o), NEON)
		ring(m, c * CFrame.new(0, 0, -0.3), 1.1, 10, 0.35, 0.25, tubeA(o), NEON)
		part(m, Vector3.new(3.4, 0.4, 0.25), c * CFrame.new(0, 0, -0.32), tubeA(o), NEON)
		part(m, Vector3.new(0.4, 3.4, 0.25), c * CFrame.new(0, 0, -0.32), tubeA(o), NEON)
	end,
	neonarrow = function(m, o)
		for _, x in ipairs({ -3, 3 }) do part(m, Vector3.new(0.5, 3.4, 0.5), CFrame.new(x, 1.7, 0), GREY, METAL) end
		local c = CFrame.new(0, 5, 0)
		part(m, Vector3.new(7.6, 3.4, 0.4), c, rgb(11, 8, 24))
		part(m, Vector3.new(4.2, 0.5, 0.25), c * CFrame.new(-0.7, 0, -0.3), tubeA(o), NEON)
		part(m, Vector3.new(2, 0.5, 0.25), c * CFrame.new(1.7, 0.55, -0.3) * CFrame.Angles(0, 0, -0.75), tubeA(o), NEON)
		part(m, Vector3.new(2, 0.5, 0.25), c * CFrame.new(1.7, -0.55, -0.3) * CFrame.Angles(0, 0, 0.75), tubeA(o), NEON)
	end,
	neonbump = function(m, o)
		part(m, Vector3.new(10, 0.7, 3), CFrame.new(0, 0.35, 0), RED)
		for _, x in ipairs({ -3.2, 0, 3.2 }) do part(m, Vector3.new(1.4, 0.72, 3.02), CFrame.new(x, 0.36, 0), WHITE) end
		for _, z in ipairs({ -1.55, 1.55 }) do part(m, Vector3.new(10, 0.2, 0.25), CFrame.new(0, 0.75, z), tubeB(o), NEON) end
	end,
	neonstack = function(m, o)
		for i = 0, 2 do
			local y = 0.75 + i * 1.55
			cyl(m, 1.5, 4.4, CFrame.new(0, y, 0) * VERT, RUBBER)
			cyl(m, 0.35, 4.5, CFrame.new(0, y, 0) * VERT, if i % 2 == 0 then tubeA(o) else tubeB(o), NEON)
		end
		cyl(m, 0.06, 2.2, CFrame.new(0, 4.62, 0) * VERT, INK)
	end,
	neoncones = function(m, o)
		for _, x in ipairs({ -2.4, 0, 2.4 }) do
			part(m, Vector3.new(1.8, 0.3, 1.8), CFrame.new(x, 0.15, 0), INK)
			cyl(m, 1, 1.4, CFrame.new(x, 0.8, 0) * VERT, ORANGE)
			cyl(m, 0.3, 1.25, CFrame.new(x, 1.45, 0) * VERT, tubeB(o), NEON)
			cyl(m, 0.9, 0.95, CFrame.new(x, 2.05, 0) * VERT, ORANGE)
			cyl(m, 0.7, 0.55, CFrame.new(x, 2.85, 0) * VERT, ORANGE)
		end
	end,
	neonbarrier = function(m, o)
		for _, x in ipairs({ -4.2, 4.2 }) do part(m, Vector3.new(0.7, 2.6, 0.7), CFrame.new(x, 1.3, 0), GREY, METAL) end
		part(m, Vector3.new(10, 2, 0.5), CFrame.new(0, 3.2, 0), WHITE)
		for _, x in ipairs({ -3.4, -0.2, 3 }) do part(m, Vector3.new(1.6, 2, 0.52), CFrame.new(x, 3.2, 0), RED) end
		part(m, Vector3.new(10, 0.3, 0.3), CFrame.new(0, 4.35, 0), tubeA(o), NEON)
	end,
	neonlamp = function(m, o)
		part(m, Vector3.new(1.6, 0.4, 1.6), CFrame.new(0, 0.2, 0), NAVY)
		part(m, Vector3.new(0.5, 9, 0.5), CFrame.new(0, 4.6, 0), GREY, METAL)
		part(m, Vector3.new(3, 0.4, 0.4), CFrame.new(1.3, 9, 0), GREY, METAL)
		part(m, Vector3.new(1.8, 0.45, 0.45), CFrame.new(2.4, 8.6, 0), tubeB(o), NEON)
	end,
	checkerflag = function(m, o)
		cyl(m, 9, 0.45, CFrame.new(-1.8, 4.5, 0) * VERT, GREY, METAL)
		for cx = 0, 4 do
			for cy = 0, 2 do
				part(m, Vector3.new(0.8, 0.9, 0.12), CFrame.new(-1.15 + cx * 0.8, 8.4 - cy * 0.9, 0),
					if (cx + cy) % 2 == 0 then INK else WHITE)
			end
		end
		part(m, Vector3.new(4, 0.25, 0.25), CFrame.new(0.05, 6.4, 0), tubeA(o), NEON)
	end,
	-- yard stage unlocks
	neondrum = function(m, o)
		cyl(m, 4.2, 3, CFrame.new(0, 2.1, 0) * VERT, BLUE)
		for _, y in ipairs({ 1.3, 2.9 }) do cyl(m, 0.3, 3.08, CFrame.new(0, y, 0) * VERT, rgb(63, 184, 255), NEON) end
		cyl(m, 0.1, 3, CFrame.new(0, 4.25, 0) * VERT, rgb(31, 79, 168))
	end,
	litpallets = function(m, o)
		local wood, dark = rgb(201, 143, 85), rgb(158, 108, 60)
		for i = 0, 1 do
			local y0 = i * 1.4
			for _, x in ipairs({ -2.6, 0, 2.6 }) do part(m, Vector3.new(0.9, 0.55, 4.4), CFrame.new(x, y0 + 0.28, 0), dark) end
			part(m, Vector3.new(6.4, 0.35, 4.4), CFrame.new(0, y0 + 0.73, 0), wood)
		end
		for _, z in ipairs({ -2.1, 2.1 }) do part(m, Vector3.new(5.4, 0.2, 0.2), CFrame.new(0, 1.2, z), rgb(245, 197, 24), NEON) end
	end,
	gaugesign = function(m, o)
		part(m, Vector3.new(0.5, 3, 0.5), CFrame.new(0, 1.5, 0.3), GREY, METAL)
		local c = CFrame.new(0, 5, 0)
		part(m, Vector3.new(4.6, 4.2, 0.4), c, NAVY)
		local hub = c * CFrame.new(0, -0.7, -0.3)
		for i = 0, 8 do
			local a = math.pi - (i + 0.5) / 9 * math.pi
			part(m, Vector3.new(0.62, 0.35, 0.2), hub * CFrame.new(math.cos(a) * 1.5, math.sin(a) * 1.5, 0) * CFrame.Angles(0, 0, a + math.pi / 2),
				if i >= 6 then GOLD else NAVY2, if i >= 6 then NEON else PLASTIC)
		end
		part(m, Vector3.new(1.6, 0.18, 0.15), hub * CFrame.Angles(0, 0, math.rad(40)) * CFrame.new(0.7, 0, -0.05), RED)
		cyl(m, 0.3, 0.5, hub * FACING, WHITE)
	end,
	bollards = function(m, o)
		for _, x in ipairs({ -1.8, 1.8 }) do
			cyl(m, 3, 1.1, CFrame.new(x, 1.5, 0) * VERT, GREY)
			for _, y in ipairs({ 1.6, 2.3 }) do cyl(m, 0.3, 1.14, CFrame.new(x, y, 0) * VERT, ORANGE, NEON) end
		end
	end,
}

function NeonDecor.has(kindId: string): boolean
	return BUILD[kindId] ~= nil or RoadDecor.BUILD[kindId] ~= nil
end

-- the Accent meshes in the milestone colour: the baked shading kept, tinted (or, where a
-- SurfaceAppearance can't be tinted, flat paint in that colour)
local function tint(m: Model, color: Color3)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("MeshPart") and p.Name == "Accent" then
			local sa = p:FindFirstChildOfClass("SurfaceAppearance")
			local ok = sa ~= nil and pcall(function() (sa :: any).Color = color end)
			if not ok then
				if sa then sa:Destroy() end
				p.TextureID = ""
				p.Color = color
				p.Material = PLASTIC
			end
		end
	end
end

local function fromModel(kindId: string, o: Opts): Model?
	local path = MODEL[kindId]
	local tpl = path and Models.get(path)
	if not tpl then return nil end
	local m = Models.place(tpl, nil :: any, CFrame.new(), 1)
	m.Name = kindId
	tint(m, main(o))
	if kindId == "pillar" then
		-- the level on the gold plaque at the foot (prestige.py: the plaque's centre; the bundle's
		-- models come in facing +Z, so the plaque is on that side)
		-- (lettered like the podium's numbers: gold, shaded top to bottom, a thin dark edge, lit by
		-- the scene like the metal round it)
		local p = part(m, Vector3.new(1.8, 0.62, 0.05), CFrame.new(0, 0.78, 1.73), INK)
		p.Transparency = 1
		p.CastShadow = false
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 90
		sg.LightInfluence = 1
		sg.Parent = p
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
		t.Text = "P" .. tostring(o.level or 2)
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Parent = sg
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0.1, 0), UDim.new(0.06, 0)
		pad.Parent = t
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 232, 140)), ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 190, 52)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 128, 20)),
		})
		grad.Parent = t
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(70, 40, 6)
		stroke.Thickness = 2.5
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = t
	end
	return m
end

function NeonDecor.build(kindId: string, opts: Opts?): Model?
	local real = fromModel(kindId, opts or {})
	if real then return real end
	local fn = BUILD[kindId] or RoadDecor.BUILD[kindId]
	if not fn then return nil end
	local m = Instance.new("Model")
	m.Name = kindId
	fn(m, opts or {})
	glow(m, kindId)
	-- the pivot is the ground centre, unturned (no PrimaryPart: a part's own turn would tip the piece)
	m.WorldPivot = CFrame.new()
	return m
end

-- the colours a yard's pieces use: its owner's milestone colour, its Midnight Garage colourway
function NeonDecor.optsFor(plot: Instance?): Opts
	local level = plot and (plot:GetAttribute("V2_Prestige") :: number?) or 0
	local look = Game.prestigeLook(level)
	local lookStr = plot and (plot:GetAttribute("V2_Look") :: string?) or ""
	local way = Game.yardWay(string.match(lookStr or "", ":(.+)$"))
	return {
		color = look and look.color or nil,
		colors = look and look.prism or nil,
		level = level,
		a = way.a, b = way.b,
		showcase = plot and (plot:GetAttribute("V2_Showcase") :: string?) or nil,
	}
end

return NeonDecor
