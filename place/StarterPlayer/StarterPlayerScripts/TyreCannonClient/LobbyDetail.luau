--!strict
-- TYRE CANNON :: LobbyDetail
-- The land's small detail (owner, 2026-10-17: "make the background scenery in the lobby, the grass and
-- the landscapes more detailed"). LobbyVista's rings are big flat strips; this dresses them so they
-- read as real ground from the yards:
--   the lawn     (between the yards and the canal, r 410-605, kept off every yard's line of fire)
--                the park first (LobbyPark, 2026-10-17: ponds, playground, fountain, people, trees),
--                then round it: patches of lighter, darker and drier grass; grass tufts; drifts of
--                marigold, mustard and pink wildflowers; shrubs and rocks
--   the canal    reeds along the inner bank
--   the fields   an earth bund round each field strip, trees along the bunds, flowers on the near
--                verges, and haystacks and a shade tree by every village
-- The models are the Blender set (art/blender/nature.py, trees.py) under Assets/Nature; pieces whose
-- model isn't imported are skipped, so the patches and bunds (plain parts) show either way.
-- Built on the client into the vista's folder (it hides with it during a run), from a fixed seed so
-- everyone sees the same land. Less of it on lower graphics settings. Flat paint, no lights.
-- workspace:SetAttribute("LobbyDetail", false) turns it off.
--   LobbyDetail.build(root, heightAt) -> park (LobbyPark, or nil)   (yields)

local MaterialService = game:GetService("MaterialService")
local UserInputService = game:GetService("UserInputService")
local Models = require(script.Parent:WaitForChild("Models"))

local LobbyDetail = {}

local CENTRE = Vector3.new(-6000, 0, 6000)
-- (2026-10-18: the lobby drawn in by LobbyVista.S = 0.6. The yards end at 280; the canal wall now stands at 366)
-- (2026-10-21, the owner: a stage-5 yard ran over the park's footpath. Yards reach 316 studs out at stage 5
-- (Game.YardGrowth: x1 104, z 60, the fence and palisade past that), so every ring is pushed out to clear it.)
local LAWN = { 328, 400 }
local FIRE_CLEAR = 60          -- studs kept clear either side of each yard's line of fire
local CANAL_R = 640 * 0.66
-- level -> { tufts, flower drifts, reeds, field-tree chance }
local DENSITY = {
	{ tufts = 160, drifts = 10, reeds = 0, trees = 0.15 },
	{ tufts = 500, drifts = 28, reeds = 90, trees = 0.3 },
	{ tufts = 900, drifts = 40, reeds = 160, trees = 0.45 },
}

local function quality(): number
	local ok, q = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	local v = ok and tonumber(q) or 0
	-- (2026-10-22, the owner: graphics always high. A game can't move the player's own slider, so on
	-- Automatic (nearly everyone) the park is built at its top level, and never below the middle one)
	-- (2026-10-23, the review: a phone or tablet on Automatic gets the middle level: the lobby is
	-- ~12,800 parts at the top one, and most players are on phones)
	if v == 0 then return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then 2 else 3 end
	if v <= 7 then return 2 end
	return 3
end

local function newPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

local function textured(p: BasePart, variant: string)
	local v = MaterialService:FindFirstChild(variant)
	if not (v and v:IsA("MaterialVariant")) then return end
	p.Material = v.BaseMaterial
	p.MaterialVariant = variant
	p.Color = Color3.new(1, 1, 1):Lerp(p.Color, 0.35)
end

local function at(r: number, a: number, y: number): Vector3
	return CENTRE + Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
end

-- the park (LobbyPark, 2026-10-17), built first: the lawn's scatter keeps off its ponds and set pieces
local park: any = nil

-- a Blender piece standing at `p`, turned by yaw, scaled; nil while its model isn't imported (or the
-- spot is the park's)
local function put(folder: Instance, name: string, p: Vector3, yaw: number, scale: number, shadow: boolean?): Model?
	local tpl = Models.get("Nature/" .. name)
	if not tpl then return nil end
	if park and not park:clear(p, 2) then return nil end
	local m = Models.place(tpl, folder, CFrame.new(p) * CFrame.Angles(0, yaw, 0), scale)
	for _, part in ipairs(Models.parts(m)) do part.CastShadow = shadow == true end
	return m
end

-- a random point on the lawn, in one of the eight gaps between the lines of fire
local function lawnPoint(rng: Random, gap: number?, rMin: number?, rMax: number?): (number, number)
	local r = rng:NextNumber(rMin or LAWN[1], rMax or LAWN[2])
	local k = gap or rng:NextInteger(0, 7)
	local half = math.pi / 8 - FIRE_CLEAR / r
	return r, (k + 0.5) * math.pi / 4 + rng:NextNumber(-half, half)
end

local function pickWeighted(rng: Random, list: { { any } }): string
	local total = 0
	for _, e in ipairs(list) do total += e[2] end
	local x = rng:NextNumber(0, total)
	for _, e in ipairs(list) do
		x -= e[2]
		if x <= 0 then return e[1] end
	end
	return list[1][1]
end

--==============================================================
function LobbyDetail.lawn(f: Instance, rng: Random, d: any, level: number)
	-- worn patches: only where people gather (the picnics, benches, the cricket strip, the fountain), a
	-- touch drier than the lawn and in its own material, so they read as wear, not stains. (Before the
	-- park pack is in, a dozen faint ones anywhere.)
	local land = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("Ground") and workspace.Lobby.Ground:FindFirstChild("Land")
	local lawnCol = if land and land:IsA("BasePart") then land.Color else Color3.fromRGB(128, 136, 84)
	local dry = lawnCol:Lerp(Color3.fromRGB(176, 160, 110), 0.18)
	local wear = if park and park.wear then park.wear else {}
	if #wear == 0 then
		for _ = 1, 12 do
			local r, a = lawnPoint(rng)
			table.insert(wear, { p = at(r, a, 0), r = rng:NextNumber(6, 10) })
		end
	end
	-- (2026-10-24, the owner: "remove the splotches of sand ... fix the glitching of terrain") no worn patches:
	-- the discs sat a hair over the lawn and flickered against it, and read as sand stains
	for i, w in ipairs(if false then wear else {}) do
		for j = 1, 3 do
			local size = w.r * rng:NextNumber(2.0, 2.8)
			-- (2026-10-21: thin and low, so the disc's rim doesn't draw a dark outline on the lawn)
			local off = Vector3.new(rng:NextNumber(-0.5, 0.5) * w.r, 0.006 + j * 0.004, rng:NextNumber(-0.5, 0.5) * w.r)
			local disc = newPart(f, Vector3.new(0.04, size, size), CFrame.new(w.p + off) * CFrame.Angles(0, 0, math.pi / 2), dry, Enum.Material.Grass, Enum.PartType.Cylinder)
			disc.Name = "Wear"
			if land and land:IsA("BasePart") and land.MaterialVariant ~= "" then
				disc.Material = land.Material
				disc.MaterialVariant = land.MaterialVariant
			end
		end
		if i % 10 == 0 then task.wait() end
	end
	-- grass tufts in clumps at a lawn's natural edges: round the park's set pieces, benches and tree
	-- bases (ground cover grows where the mower doesn't reach), the rest out past the footpath; kept
	-- small, as on a mown lawn, and off the stretch right in front of the plaza
	local zones = if park and park.zones then park.zones else {}
	local placed = 0
	while placed < d.tufts do
		local centre: Vector3
		if #zones > 0 and rng:NextNumber() < 0.6 then
			local z = zones[rng:NextInteger(1, #zones)]
			local a = rng:NextNumber(0, math.pi * 2)
			centre = z.p + Vector3.new(math.cos(a), 0, math.sin(a)) * (z.r + rng:NextNumber(1, 4))
		else
			local r, a = lawnPoint(rng, nil, 348)
			centre = at(r, a, 0)
		end
		for j = 1, rng:NextInteger(3, 6) do
			local off = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
			put(f, if rng:NextNumber() < 0.6 then "GrassTuftA" else "GrassTuftB", centre + off, rng:NextNumber(0, math.pi * 2), rng:NextNumber(0.9, 1.4))
			placed += 1
		end
		if placed % 60 < 8 then task.wait() end
	end
	-- wildflower drifts: a handful of clumps of one kind together, as they grow
	local kinds = { { "FlowersMarigold", 3 }, { "FlowersMustard", 3 }, { "FlowersPink", 2 } }
	for i = 1, d.drifts do
		local r, a = lawnPoint(rng)
		local kind = pickWeighted(rng, kinds)
		local centre = at(r, a, 0)
		for j = 1, rng:NextInteger(5, 9) do
			local off = Vector3.new(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9))
			put(f, kind, centre + off, rng:NextNumber(0, math.pi * 2), rng:NextNumber(1.0, 1.4))
		end
		if i % 8 == 0 then task.wait() end
	end
	-- shrubs in little clusters at the foot of the park's trees, rocks only at the pond rims (a lone
	-- shrub or rock out on mown lawn reads as a blob)
	-- (these go right against the park's pieces, so they skip its clearance check)
	local function hug(name: string, p: Vector3, scale: number)
		local tpl = Models.get("Nature/" .. name)
		if not tpl or (park and park:onPath(p, 1)) then return end
		local m = Models.place(tpl, f, CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), scale)
		for _, part in ipairs(Models.parts(m)) do part.CastShadow = false end
	end
	-- (2026-10-24, the owner: "remove the poo bushes") no shrub clusters at the tree bases
	local trees = {}
	for i = 1, math.min(18, #trees) do
		local t = trees[rng:NextInteger(1, #trees)]
		local a0 = rng:NextNumber(0, math.pi * 2)
		for j = 1, rng:NextInteger(3, 5) do
			local a = a0 + j * rng:NextNumber(0.5, 0.9)
			hug("Shrub", t + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(4, 7), rng:NextNumber(0.9, 1.6))
		end
		if i % 6 == 0 then task.wait() end
	end
	for _, pond in ipairs(if park and park.pondSpots then park.pondSpots else {}) do
		for j = 1, 4 do
			local a = j / 4 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
			hug("Rocks", (pond.cf * CFrame.new(math.cos(a) * (pond.r1 + 2.5), 0, math.sin(a) * (pond.r2 + 2.5))).Position, rng:NextNumber(0.8, 1.2))
		end
	end
	-- reeds along the canal's inner bank, in clumps
	local n = d.reeds
	for i = 0, n - 1 do
		local a = (i + rng:NextNumber(-0.3, 0.3)) / math.max(n, 1) * math.pi * 2
		put(f, "Reeds", at(CANAL_R - 14 + rng:NextNumber(-1.5, 1.5), a, 0.6), rng:NextNumber(0, math.pi * 2), rng:NextNumber(1.6, 2.4))
		if i % 40 == 0 then task.wait() end
	end
end

--==============================================================
function LobbyDetail.fields(f: Instance, root: Instance, rng: Random, d: any, level: number)
	local punjab = root:FindFirstChild("Punjab")
	if not punjab then return end
	local trees = { { "TreeNeem", 4 }, { "TreeMango2", 3 }, { "TreeAshoka", 2 }, { "TreeApple", 1 } }
	local made = 0
	for _, field in ipairs(punjab:GetChildren()) do
		if field:IsA("BasePart") and field.Name == "Field" then
			-- the field part: X runs round the ring, -Z faces the plaza, its top is the ground
			local cf, s = field.CFrame, field.Size
			local top = cf * CFrame.new(0, s.Y / 2, 0)
			local inner = newPart(f, Vector3.new(s.X, 1.2, 2.6), top * CFrame.new(0, 0.3, -s.Z / 2 + 1.3), Color3.fromRGB(138, 112, 78), Enum.Material.Ground)
			inner.Name = "Bund"
			textured(inner, "TC_Dirt")
			local ends = newPart(f, Vector3.new(2.6, 1.2, s.Z), top * CFrame.new(s.X / 2 - 1.3, 0.3, 0), Color3.fromRGB(138, 112, 78), Enum.Material.Ground)
			ends.Name = "Bund"
			textured(ends, "TC_Dirt")
			local r = (Vector3.new(top.Position.X, 0, top.Position.Z) - CENTRE).Magnitude
			local grow = 1.3 + math.clamp((r - 680) / 1220, 0, 1) * 1.3 -- further out stands bigger, like the vista
			-- a tree or two along the bund
			if rng:NextNumber() < d.trees then
				local x = rng:NextNumber(-s.X / 2 + 8, s.X / 2 - 8)
				local p = (top * CFrame.new(x, 0, -s.Z / 2 + 4)).Position
				put(f, pickWeighted(rng, trees), p, rng:NextNumber(0, math.pi * 2), grow * rng:NextNumber(0.9, 1.1), level >= 3)
			end
			-- flowers on the near verges
			if r < 1150 and level >= 2 then
				for j = 1, 3 do
					local x = rng:NextNumber(-s.X / 2 + 4, s.X / 2 - 4)
					local p = (top * CFrame.new(x, 0.9, -s.Z / 2 + 1.3)).Position
					put(f, if rng:NextNumber() < 0.5 then "FlowersMustard" else "FlowersMarigold", p, rng:NextNumber(0, math.pi * 2), grow * 1.4)
				end
			end
			made += 1
			if made % 20 == 0 then task.wait() end
		end
	end
	-- haystacks and a shade tree by every village (beside its tube well)
	local villages = punjab:FindFirstChild("Villages")
	if villages then
		for _, m in ipairs(villages:GetChildren()) do
			if m:IsA("Model") and m.Name == "TubeWell" then
				local cf = m:GetPivot()
				local base = Vector3.new(cf.Position.X, 0, cf.Position.Z)
				local cbox, size = m:GetBoundingBox()
				local ground = cbox.Position.Y - size.Y / 2
				local out = (base - CENTRE).Unit
				local side = Vector3.new(-out.Z, 0, out.X)
				for j, off in ipairs({ side * 34 + out * 10, side * 50 - out * 6 }) do
					put(f, "Haystack", base + off + Vector3.new(0, ground, 0), rng:NextNumber(0, math.pi * 2), 2.4 * (j == 1 and 1 or 0.85))
				end
				put(f, if rng:NextNumber() < 0.5 then "TreeMango2" else "TreeNeem", base - side * 40 + out * 24 + Vector3.new(0, ground, 0), rng:NextNumber(0, math.pi * 2), 2.3, level >= 2)
			end
		end
	end
end

--==============================================================
function LobbyDetail.build(root: Instance, heightAt: (number) -> number)
	park = nil -- (never check scatter against a park from an earlier build)
	if workspace:GetAttribute("LobbyDetail") == false then return end
	local level = quality()
	local d = DENSITY[level]
	local rng = Random.new(20261017)
	local f = Instance.new("Folder")
	f.Name = "Detail"
	local lawn = Instance.new("Folder")
	lawn.Name = "Lawn"
	lawn.Parent = f
	local fields = Instance.new("Folder")
	fields.Name = "Fields"
	fields.Parent = f
	f.Parent = root
	local mod = script.Parent:FindFirstChild("LobbyPark")
	if mod then
		local ok, made = pcall(function() return (require(mod) :: any).new(lawn, level) end)
		if ok then park = made else warn("[TyreCannon] LobbyPark:", made) end
	end
	local ok, err = pcall(LobbyDetail.lawn, lawn, rng, d, level)
	if not ok then warn("[TyreCannon] LobbyDetail lawn:", err) end
	ok, err = pcall(LobbyDetail.fields, fields, root, rng, d, level)
	if not ok then warn("[TyreCannon] LobbyDetail fields:", err) end
	return park
end

return LobbyDetail
