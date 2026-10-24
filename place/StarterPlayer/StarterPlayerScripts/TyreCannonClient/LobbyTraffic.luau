--!strict
-- TYRE CANNON :: LobbyTraffic
-- The roundabout (owner's brief, 2026-10-15): a ring road just past the canal's poplars, with the
-- whole lobby as its island. Eight roads leave it along the yards' lines of fire, climbing the
-- terraces to the Grand Trunk ring. Traffic drives round it clockwise (left-hand traffic, as in
-- India), and in and out along the roads: hatchbacks, taxis, autos, painted lorries, tankers,
-- buses, motorbikes and scooters with riders, and tractors with trolleys
-- (Claude Design canvas "Tyre Cannon Traffic").
-- Each vehicle is built from parts at one of three detail levels, chosen from the player's graphics
-- setting (8-10 high, 4-7 or Automatic mid, 1-3 low), with fewer vehicles at the lower levels. They
-- are rebuilt when the setting changes. No lights, no glow.
-- (2026-10-17) Where a kind's Blender model is imported (Assets/Vehicles, art/blender/vehicles.py) it
-- drives instead: a Paint mesh tinted per vehicle, a Detail mesh and a Shirt mesh tinted per rider.
-- LobbyVista builds this into its own folder, so it hides with the vista during a run.
-- workspace:SetAttribute("LobbyTraffic", false) turns it off.
--   LobbyTraffic.new(root, heightAt) -> traffic (yields) ; traffic:step(t) ; traffic:destroy()

local MaterialService = game:GetService("MaterialService")

local LobbyTraffic = {}
LobbyTraffic.__index = LobbyTraffic

local CENTRE = Vector3.new(-6000, 0, 6000)
-- (2026-10-18: the lobby's rings drawn in by LobbyVista's S = 0.6, the owner's smaller lobby)
-- (2026-10-21, the owner: a stage-5 yard ran over the park's footpath. Yards reach 316 studs out at stage 5
-- (Game.YardGrowth: x1 104, z 60, the fence and palisade past that), so every ring is pushed out to clear it.)
local S = 0.66
local RING_R = 760 * S      -- past the canal (640 S) and its outer poplars (666 S)
local RING_W = 40           -- two lanes, one way, clockwise
local RING_TOP = 11         -- the roundabout runs on a low bank above the first terrace
local SPOKE_W = 36          -- two lanes, one each way
local SPOKE_END = 2050 * S - 34 -- the Grand Trunk ring's inner edge (it sits at 2050 S, 72 wide)
local LANE = 8              -- a lane's centre, out from the road's centre line
local SCALE = 2             -- vehicles are drawn at 1x studs and stand at this size
local SPEED = 52            -- (the old single speed; kept as the default)
-- (2026-10-22, the owner: the traffic's "animations as they move in the background make it quality")
-- each kind drives at its own pace, eases off for the bends, keeps its distance from what's ahead
-- (so nothing drives through anything), and its wheels turn with the road
local PACE = { hatchback = 50, taxi = 46, auto = 34, lorry = 34, tanker = 32, bus = 36, motorbike = 54, scooter = 42, tractor = 20 }
local ACCEL, BRAKE = 14, 30  -- studs a second, a second
local COUNTS = { -- level -> ring vehicles, through vehicles per road
	{ ring = 6, per = 1 },
	{ ring = 10, per = 2 },
	{ ring = 16, per = 3 },
}

local ASPHALT = Color3.fromRGB(70, 72, 78)
local LINE = Color3.fromRGB(232, 232, 224)
local YELLOW = Color3.fromRGB(240, 196, 40)
local DIRT = Color3.fromRGB(150, 128, 96)
local DARK = Color3.fromRGB(34, 36, 42)
local GLASS = Color3.fromRGB(44, 52, 69)
local GREY = Color3.fromRGB(150, 156, 168)
local SKIN = { Color3.fromRGB(201, 143, 85), Color3.fromRGB(141, 90, 59), Color3.fromRGB(176, 118, 74) }
local SHIRTS = { Color3.fromRGB(42, 111, 214), Color3.fromRGB(229, 53, 43), Color3.fromRGB(242, 194, 48),
	Color3.fromRGB(244, 241, 232), Color3.fromRGB(63, 174, 106), Color3.fromRGB(217, 79, 154) }
local HATS = { Color3.fromRGB(255, 138, 30), Color3.fromRGB(229, 53, 43), Color3.fromRGB(43, 45, 51), Color3.fromRGB(42, 111, 214) }

local function quality(): number
	local ok, q = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	local v = ok and tonumber(q) or 0
	-- (2026-10-22, the owner: graphics always high. A game can't move the player's own slider, so the
	-- lobby builds at its top level on Automatic, and never below the middle one)
	if v == 0 then
		-- (2026-10-23: a phone or tablet gets the middle level)
		local UIS = game:GetService("UserInputService")
		return if UIS.TouchEnabled and not UIS.KeyboardEnabled then 2 else 3
	end
	if v <= 7 then return 2 end
	return 3
end

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
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
	p.Material = mat or Enum.Material.SmoothPlastic
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

local function radial(a: number): Vector3
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

--==============================================================
-- the vehicles: each a list of pieces at 1x, front toward -Z, ground at y = 0
--   { lv, size, pos, color, shape?, turn? }  lv: "A" all, "L" low only, "m" mid only, "M" mid+high, "H" high only
--==============================================================
local function piece(list: { any }, lv: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Color3, shape: string?, turn: boolean?)
	table.insert(list, { lv = lv, size = Vector3.new(sx, sy, sz), pos = Vector3.new(x, y, z), color = color, shape = shape, turn = turn })
end
local function wheels(list: { any }, x: number, y: number, d: number, w: number, zs: { number }, hub: boolean?)
	for _, z in ipairs(zs) do
		for _, s in ipairs({ -1, 1 }) do
			piece(list, "M", w, d, d, s * x, y, z, DARK, "Cylinder")
			if hub then piece(list, "H", w + 0.1, d * 0.45, d * 0.45, s * x, y, z, GREY, "Cylinder") end
		end
	end
end
local function head(list: { any }, lv: string, x: number, y: number, z: number, rng: Random, hat: boolean?)
	piece(list, lv, 1.2, 1.2, 1.2, x, y, z, SKIN[rng:NextInteger(1, #SKIN)], "Ball")
	if hat then piece(list, "H", 1.3, 0.7, 1.3, x, y + 0.45, z, HATS[rng:NextInteger(1, #HATS)]) end
end
local function rider(list: { any }, x: number, y: number, z: number, rng: Random)
	local shirt = SHIRTS[rng:NextInteger(1, #SHIRTS)]
	piece(list, "L", 1.6, 3.2, 1.2, x, y + 1.6, z, shirt)
	piece(list, "M", 1.6, 1.9, 1.1, x, y + 1.0, z, shirt)
	piece(list, "M", 1.3, 1.6, 1.4, x, y - 0.4, z - 0.6, Color3.fromRGB(58, 66, 88))
	head(list, "M", x, y + 2.6, z, rng, true)
	piece(list, "H", 0.5, 0.5, 1.8, x - 0.8, y + 1.3, z - 0.9, shirt)
	piece(list, "H", 0.5, 0.5, 1.8, x + 0.8, y + 1.3, z - 0.9, shirt)
end
local function pick(rng: Random, t: { Color3 }): Color3
	return t[rng:NextInteger(1, #t)]
end

local BUILD: { [string]: (Random) -> { any } } = {}

BUILD.hatchback = function(rng)
	local c = pick(rng, { Color3.fromRGB(216, 64, 46), Color3.fromRGB(240, 240, 236), Color3.fromRGB(176, 182, 192), Color3.fromRGB(92, 168, 222) })
	local l = {}
	piece(l, "A", 5.2, 2.2, 11, 0, 2.0, 0, c)
	piece(l, "A", 4.8, 1.8, 6, 0, 4.0, 0.6, c)
	piece(l, "L", 5.6, 2.0, 2.4, 0, 1.0, -3.4, DARK)
	piece(l, "L", 5.6, 2.0, 2.4, 0, 1.0, 3.4, DARK)
	piece(l, "m", 4.9, 1.2, 6.1, 0, 4.1, 0.6, GLASS)
	piece(l, "H", 4.9, 1.2, 6.1, 0, 4.1, 0.6, GLASS)
	wheels(l, 2.5, 1.2, 2.4, 0.9, { -3.4, 3.4 }, true)
	head(l, "H", 1.1, 4.3, -0.4, rng, false)
	piece(l, "H", 5.4, 0.6, 0.5, 0, 1.2, -5.6, GREY)
	piece(l, "H", 5.4, 0.6, 0.5, 0, 1.2, 5.6, GREY)
	piece(l, "H", 1.0, 0.6, 0.2, -1.8, 2.4, -5.55, LINE)
	piece(l, "H", 1.0, 0.6, 0.2, 1.8, 2.4, -5.55, LINE)
	piece(l, "H", 1.0, 0.6, 0.2, -1.8, 2.4, 5.55, Color3.fromRGB(200, 40, 34))
	piece(l, "H", 1.0, 0.6, 0.2, 1.8, 2.4, 5.55, Color3.fromRGB(200, 40, 34))
	return l
end

BUILD.taxi = function(rng)
	local y, b = Color3.fromRGB(242, 194, 48), Color3.fromRGB(30, 30, 34)
	local l = {}
	piece(l, "A", 5.4, 2.4, 12, 0, 2.1, 0, y)
	piece(l, "A", 5.0, 1.9, 5.6, 0, 4.3, 0.4, b)
	piece(l, "L", 5.8, 2.0, 2.4, 0, 1.0, -4.0, DARK)
	piece(l, "L", 5.8, 2.0, 2.4, 0, 1.0, 4.0, DARK)
	piece(l, "M", 5.1, 1.2, 5.7, 0, 4.3, 0.4, GLASS)
	wheels(l, 2.6, 1.2, 2.4, 0.9, { -4.0, 4.0 }, true)
	piece(l, "H", 1.8, 0.7, 0.6, 0, 5.6, 0.4, LINE)
	head(l, "H", 1.1, 4.5, -0.6, rng, true)
	piece(l, "H", 5.6, 0.6, 0.5, 0, 1.3, -6.1, GREY)
	piece(l, "H", 5.6, 0.6, 0.5, 0, 1.3, 6.1, GREY)
	piece(l, "H", 0.9, 0.9, 0.3, -1.9, 2.6, -6.05, LINE, "Ball")
	piece(l, "H", 0.9, 0.9, 0.3, 1.9, 2.6, -6.05, LINE, "Ball")
	return l
end

BUILD.auto = function(rng)
	local g, y = Color3.fromRGB(47, 154, 82), Color3.fromRGB(242, 194, 48)
	local l = {}
	piece(l, "A", 4.2, 3.0, 6.2, 0, 2.3, 0.4, g)
	piece(l, "A", 4.4, 0.6, 6.4, 0, 5.6, 0.3, y)
	piece(l, "L", 4.6, 1.6, 2.0, 0, 0.8, 2.4, DARK)
	piece(l, "M", 3.0, 2.6, 1.2, 0, 2.2, -3.2, g)
	piece(l, "M", 4.3, 1.0, 6.3, 0, 1.5, 0.4, y)
	piece(l, "M", 1.0, 1.8, 1.8, 0, 0.9, -2.9, DARK, "Cylinder")
	piece(l, "M", 0.8, 1.8, 1.8, -2.1, 0.9, 2.4, DARK, "Cylinder")
	piece(l, "M", 0.8, 1.8, 1.8, 2.1, 0.9, 2.4, DARK, "Cylinder")
	piece(l, "H", 0.3, 1.6, 0.3, -2.0, 4.6, -2.4, DARK)
	piece(l, "H", 0.3, 1.6, 0.3, 2.0, 4.6, -2.4, DARK)
	piece(l, "H", 3.8, 1.4, 0.2, 0, 4.6, -2.5, GLASS)
	head(l, "M", 0, 4.4, -1.4, rng, false)
	head(l, "H", -1.0, 4.3, 1.8, rng, false)
	head(l, "H", 1.0, 4.3, 1.8, rng, true)
	return l
end

local function cab(l: { any }, colour: Color3, rng: Random)
	piece(l, "A", 7.0, 6.0, 6.0, 0, 4.4, -8.0, colour)
	piece(l, "M", 6.2, 2.2, 0.3, 0, 5.8, -11.0, GLASS)
	piece(l, "H", 7.2, 1.2, 2.2, 0, 7.8, -9.4, Color3.fromRGB(42, 111, 214))
	piece(l, "H", 7.2, 0.8, 0.5, 0, 1.6, -11.1, GREY)
	head(l, "H", 1.6, 5.8, -9.6, rng, true)
end

BUILD.lorry = function(rng)
	local body = pick(rng, { Color3.fromRGB(229, 53, 43), Color3.fromRGB(242, 138, 34), Color3.fromRGB(42, 111, 214), Color3.fromRGB(47, 154, 82) })
	local l = {}
	piece(l, "A", 7.2, 7.0, 15, 0, 5.6, 3.0, body)
	cab(l, Color3.fromRGB(242, 194, 48), rng)
	piece(l, "L", 7.6, 2.4, 4.0, 0, 1.2, -8.0, DARK)
	piece(l, "L", 7.6, 2.4, 6.0, 0, 1.2, 5.5, DARK)
	piece(l, "M", 6.8, 1.0, 22, 0, 1.8, -1.0, DARK)
	wheels(l, 3.2, 1.4, 2.8, 1.2, { -8.0, 4.0, 7.4 }, true)
	piece(l, "H", 7.3, 1.0, 15.1, 0, 8.6, 3.0, Color3.fromRGB(47, 154, 82))
	piece(l, "H", 7.3, 0.6, 15.1, 0, 7.8, 3.0, Color3.fromRGB(242, 194, 48))
	for k = -2, 2 do
		piece(l, "H", 7.3, 1.6, 1.6, 0, 5.2, 3.0 + k * 2.8, if k % 2 == 0 then Color3.fromRGB(242, 194, 48) else Color3.fromRGB(42, 111, 214), nil, true)
	end
	return l
end

BUILD.tanker = function(rng)
	local band = pick(rng, { Color3.fromRGB(42, 111, 214), Color3.fromRGB(229, 53, 43), Color3.fromRGB(47, 154, 82) })
	local l = {}
	piece(l, "A", 14.5, 6.4, 6.4, 0, 5.2, 3.2, Color3.fromRGB(233, 236, 239), "Cylinder", true)
	cab(l, band, rng)
	piece(l, "L", 7.6, 2.4, 4.0, 0, 1.2, -8.0, DARK)
	piece(l, "L", 7.6, 2.4, 6.0, 0, 1.2, 5.5, DARK)
	piece(l, "M", 6.8, 1.0, 22, 0, 1.8, -1.0, DARK)
	piece(l, "M", 3.0, 6.6, 6.6, 0, 5.2, 3.2, band, "Cylinder", true)
	wheels(l, 3.2, 1.4, 2.8, 1.2, { -8.0, 4.0, 7.4 }, true)
	piece(l, "H", 2.0, 0.8, 2.0, 0, 8.6, 0.6, GREY)
	piece(l, "H", 2.0, 0.8, 2.0, 0, 8.6, 6.0, GREY)
	return l
end

BUILD.bus = function(rng)
	local o = pick(rng, { Color3.fromRGB(242, 138, 34), Color3.fromRGB(42, 111, 214), Color3.fromRGB(229, 53, 43) })
	local l = {}
	piece(l, "A", 7.4, 8.4, 26, 0, 5.4, 0, o)
	piece(l, "L", 7.8, 2.4, 3.0, 0, 1.2, -8.5, DARK)
	piece(l, "L", 7.8, 2.4, 3.0, 0, 1.2, 8.5, DARK)
	piece(l, "M", 7.5, 2.4, 24, 0, 7.0, 0.4, GLASS)
	piece(l, "M", 7.5, 1.0, 26.1, 0, 3.8, 0, LINE)
	wheels(l, 3.3, 1.4, 2.8, 1.2, { -8.5, 8.5 }, true)
	piece(l, "H", 6.0, 0.8, 10, 0, 10.0, 3.0, GREY)
	piece(l, "H", 2.4, 1.6, 2.6, -1.4, 11.2, 1.0, Color3.fromRGB(229, 53, 43))
	piece(l, "H", 2.6, 1.4, 3.0, 1.4, 11.1, 5.0, Color3.fromRGB(42, 111, 214))
	piece(l, "H", 2.0, 1.2, 2.0, 0.2, 11.0, 2.8, Color3.fromRGB(240, 210, 150))
	for k = 0, 4 do
		head(l, "H", if k % 2 == 0 then 2.6 else -2.6, 7.0, -8.0 + k * 4.0, rng, k == 2)
	end
	return l
end

BUILD.motorbike = function(rng)
	local l = {}
	piece(l, "L", 1.4, 2.6, 6.0, 0, 1.3, 0, DARK)
	piece(l, "M", 0.6, 1.4, 4.4, 0, 1.8, 0, DARK)
	piece(l, "M", 1.1, 0.9, 1.8, 0, 2.7, -0.8, pick(rng, { Color3.fromRGB(30, 30, 34), Color3.fromRGB(150, 24, 30), Color3.fromRGB(42, 111, 214) }))
	piece(l, "M", 0.7, 2.6, 2.6, 0, 1.3, -2.2, DARK, "Cylinder")
	piece(l, "M", 0.7, 2.6, 2.6, 0, 1.3, 2.2, DARK, "Cylinder")
	piece(l, "H", 2.6, 0.3, 0.3, 0, 3.6, -2.0, GREY)
	piece(l, "H", 0.8, 0.8, 1.6, 0.6, 1.3, 1.4, GREY)
	rider(l, 0, 2.6, 0.6, rng)
	return l
end

BUILD.scooter = function(rng)
	local c = pick(rng, { Color3.fromRGB(63, 182, 200), Color3.fromRGB(240, 226, 190), Color3.fromRGB(216, 64, 46) })
	local l = {}
	piece(l, "A", 1.4, 1.6, 4.0, 0, 1.4, 0.2, c)
	piece(l, "M", 1.4, 2.8, 0.6, 0, 2.4, -1.9, c)
	piece(l, "M", 0.6, 2.0, 2.0, 0, 1.0, -2.0, DARK, "Cylinder")
	piece(l, "M", 0.6, 2.0, 2.0, 0, 1.0, 2.0, DARK, "Cylinder")
	piece(l, "H", 2.4, 0.3, 0.3, 0, 3.8, -1.8, GREY)
	rider(l, 0, 2.2, 0.2, rng)
	piece(l, "H", 1.6, 1.8, 1.0, 0, 3.1, 1.6, pick(rng, SHIRTS))
	head(l, "H", 0, 4.6, 1.6, rng, false)
	return l
end

BUILD.tractor = function(rng)
	local r, g, hay = Color3.fromRGB(216, 64, 46), Color3.fromRGB(47, 154, 82), Color3.fromRGB(232, 196, 90)
	local l = {}
	piece(l, "A", 3.6, 2.6, 5.6, 0, 2.6, -7.4, r)
	piece(l, "A", 5.8, 2.6, 10.4, 0, 5.1, 5.5, hay)
	piece(l, "A", 6.0, 2.4, 11, 0, 2.6, 5.5, g)
	piece(l, "L", 6.6, 4.6, 2.6, 0, 2.3, -4.6, DARK)
	piece(l, "M", 1.6, 5.0, 5.0, -2.6, 2.5, -4.6, DARK, "Cylinder")
	piece(l, "M", 1.6, 5.0, 5.0, 2.6, 2.5, -4.6, DARK, "Cylinder")
	piece(l, "M", 1.0, 2.6, 2.6, -1.8, 1.3, -9.2, DARK, "Cylinder")
	piece(l, "M", 1.0, 2.6, 2.6, 1.8, 1.3, -9.2, DARK, "Cylinder")
	piece(l, "M", 1.0, 2.6, 2.6, -3.2, 1.3, 5.5, DARK, "Cylinder")
	piece(l, "M", 1.0, 2.6, 2.6, 3.2, 1.3, 5.5, DARK, "Cylinder")
	piece(l, "H", 1.7, 2.4, 2.4, -2.65, 2.5, -4.6, YELLOW, "Cylinder")
	piece(l, "H", 1.7, 2.4, 2.4, 2.65, 2.5, -4.6, YELLOW, "Cylinder")
	piece(l, "H", 0.5, 2.6, 0.5, 0.8, 5.0, -8.8, DARK)
	piece(l, "H", 0.6, 0.6, 2.4, 0, 1.8, -0.8, DARK)
	piece(l, "H", 1.6, 1.8, 1.0, 0, 4.9, -4.4, Color3.fromRGB(244, 241, 232))
	head(l, "H", 0, 6.4, -4.4, rng, true)
	return l
end

-- how often each kind turns up
-- (2026-10-23, the owner: the motorbikes and scooters, with their riders, go: only the Blender vehicles)
local MIX = { "hatchback", "hatchback", "hatchback", "taxi", "taxi", "auto", "auto", "lorry", "lorry", "tanker", "bus", "tractor" }

-- the Blender models: one to three meshes a vehicle at every level (Roblox's mesh LOD does the rest);
-- the part-built kinds above stay as the fallback for any kind that isn't imported
local Models = require(script.Parent:WaitForChild("Models"))
local PAINTS: { [string]: { Color3 } } = {
	hatchback = { Color3.fromRGB(216, 64, 46), Color3.fromRGB(240, 240, 236), Color3.fromRGB(176, 182, 192), Color3.fromRGB(92, 168, 222) },
	taxi = { Color3.fromRGB(242, 194, 48) },
	auto = { Color3.fromRGB(47, 154, 82) },
	lorry = { Color3.fromRGB(229, 53, 43), Color3.fromRGB(242, 138, 34), Color3.fromRGB(42, 111, 214), Color3.fromRGB(47, 154, 82) },
	tanker = { Color3.fromRGB(42, 111, 214), Color3.fromRGB(229, 53, 43), Color3.fromRGB(47, 154, 82) },
	bus = { Color3.fromRGB(242, 138, 34), Color3.fromRGB(42, 111, 214), Color3.fromRGB(229, 53, 43) },
	motorbike = { Color3.fromRGB(30, 30, 34), Color3.fromRGB(150, 24, 30), Color3.fromRGB(42, 111, 214) },
	scooter = { Color3.fromRGB(63, 182, 200), Color3.fromRGB(240, 226, 190), Color3.fromRGB(216, 64, 46) },
	tractor = { Color3.fromRGB(216, 64, 46) },
}
-- (2026-10-23) where the Blender models' own lamps are (vehicles2.py, in its units, which import 1:1):
-- height off the road, distance out from the centre line (or "in" from the side), round or not,
-- and the tail lamps' height; a lamp glows at night over the modelled one instead of floating at the
-- bounding box
local LAMPS = {
	-- (2026-10-23, the owner: "the lights on the car are off center") the modelled lamps' centres, read out
	-- of vehicles2.py's build: from the middle of the front axle, along the car, out to the side, up;
	-- Blender units, the axle length to scale them by; r the lamp's radius, round or a block
	-- (2026-10-24) hub pack 6's hatchback, taxi, lorry and tanker (hubpack6.py); heights are over the
	-- axle (the pack's own numbers are off the road, less the wheel's radius: 1.1, 1.15, 1.55)
	hatchback = { axle = 6.7, r = 0.3, lamp = { 1.89, 1.75, 1.2 }, tail = { -8.9, 2.0, 1.05 } },
	taxi = { axle = 7.8, r = 0.42, round = true, lamp = { 1.85, 1.85, 1.15 }, tail = { -9.95, 1.9, 1.25 } },
	auto = { axle = 5.1, r = 0.3, round = true, lamp = { 0.9, 0, 1.48 }, tail = { -6.132, 1.899, 0.98 } },
	lorry = { axle = 14.3, r = 0.42, round = true, lamp = { 3.65, 2.8, 1.35 }, tail = { -18.05, 3.1, 0.65 } },
	tanker = { axle = 14.3, r = 0.42, round = true, lamp = { 3.65, 2.8, 1.35 }, tail = { -18.05, 3.1, 0.65 } },
	bus = { axle = 16.4, r = 0.42, round = true, lamp = { 4.573, 3.6, 1.6 }, tail = { -21.657, 3.75, 1.85 } },
	tractor = { axle = 4.995, r = 0.24, round = true, lamp = { 1.42, 0.75, 2.35 }, tail = { -16.96, 2.6, 1.65 } },
}

local function meshVehicle(parent: Instance, kind: string, level: number, rng: Random): any
	-- (2026-10-22) the new models first: Assets/Vehicles2/<kind>, one or more painted variants with
	-- their wheels as their own parts ("... wheel"), so the wheels turn; a variant whose front is its
	-- +z carries Flip
	-- (Vehicles2/<kind> is the Blender model itself (vehicles2.py), or a folder of variants)
	local set = Models.get("Vehicles2/" .. kind)
	local variants = if set == nil then {} elseif set:IsA("Model") then { set } else set:GetChildren()
	local fresh = #variants > 0
	local tpl = if fresh then variants[rng:NextInteger(1, #variants)] else Models.get("Vehicles/" .. kind)
	if not tpl then return nil end
	-- (2026-10-23, the owner: "all the cars are moving backwards") Models gives every placed model the
	-- importer's frame turned half round, so a Blender vehicle (built facing -Y) faces its pivot's +Z;
	-- the road drives -Z, so it turns round (a variant marked NoFlip doesn't)
	local turn = if fresh and not tpl:GetAttribute("NoFlip") then CFrame.Angles(0, math.pi, 0) else CFrame.new()
	local m = Models.place(tpl, parent, CFrame.new(), SCALE)
	m.Name = kind
	local paint, shirt = pick(rng, PAINTS[kind] or { GREY }), pick(rng, SHIRTS)
	local parts, offsets = {}, {}
	local wheels: { [number]: number } = {} -- part index -> that wheel's radius
	local wheelR: number? = nil
	for _, p in ipairs(Models.parts(m)) do
		if fresh then
			p.CastShadow = level == 3
			-- the body panels, baked near-white, take this vehicle's paint
			if string.find(p.Name, "Paint") then
				local sa = p:FindFirstChildOfClass("SurfaceAppearance")
				if sa then sa.Color = paint else p.Color = paint end
			end
			table.insert(parts, p)
			table.insert(offsets, turn * p.CFrame)
			if string.find(string.lower(p.Name), "wheel") then
				-- (each wheel rolls at its own rate: a tractor's big back wheels turn slower than its fronts)
				local r = math.max(p.Size.Y, p.Size.Z) / 2
				wheels[#parts] = r
				wheelR = wheelR or r
			end
			continue
		end
		if p.Name == "Paint" then
			p.Color = paint
			p.Material = Enum.Material.SmoothPlastic
		elseif p.Name == "Shirt" then
			p.Color = shirt
			p.Material = Enum.Material.SmoothPlastic
		end
		p.CastShadow = level == 3
		table.insert(parts, p)
		table.insert(offsets, p.CFrame)
	end
	-- (2026-10-17) lamps that come on at night: neon headlights in front, tail lights behind (no
	-- light objects, so forty of them cost nothing); hidden by day
	local box, size = m:GetBoundingBox()
	local lamps = {}
	local function lamp(off: Vector3, color: Color3, sz: Vector3)
		local l = newPart(m, "Lamp", sz, CFrame.new(), color, Enum.Material.Neon)
		l.Transparency = 1
		table.insert(parts, l)
		table.insert(offsets, turn * box * CFrame.new(off))
		table.insert(lamps, l)
	end
	local y = -size.Y / 2 + size.Y * 0.3
	local front, back = -size.Z / 2 - 0.06, size.Z / 2 + 0.06
	-- (in a turned-round model's own box its front is +Z; `turn` then carries it to the road's front)
	if fresh and not tpl:GetAttribute("NoFlip") then front, back = -front, -back end
	local warm, red = Color3.fromRGB(255, 236, 190), Color3.fromRGB(230, 40, 32)
	local spec = if fresh then LAMPS[kind] else nil
	-- the axles, from the wheels as placed (the same frame the offsets are in)
	local fAxle, rAxle, nf, nr = Vector3.zero, Vector3.zero, 0, 0
	for _, p in ipairs(Models.parts(m)) do
		if string.match(p.Name, "^WheelF") then fAxle += p.Position nf += 1
		elseif string.match(p.Name, "^WheelR") then rAxle += p.Position nr += 1 end
	end
	if spec and nf > 0 and nr > 0 then
		fAxle /= nf
		rAxle /= nr
		local along = Vector3.new(fAxle.X - rAxle.X, 0, fAxle.Z - rAxle.Z)
		local k = along.Magnitude / spec.axle
		local fwd = along.Unit
		local side = fwd:Cross(Vector3.yAxis)
		local function at(off: { number }, sx: number): Vector3
			return fAxle + fwd * (off[1] * k) + side * (off[2] * k * sx) + Vector3.yAxis * (off[3] * k)
		end
		-- a lamp: a thin glowing disc (or block) on the lamp's face, facing out along the car
		local function glow(pos: Vector3, dir: Vector3, color: Color3, sz: Vector3, round: boolean)
			local l = newPart(m, "Lamp", sz, CFrame.new(), color, Enum.Material.Neon)
			l.Transparency = 1
			if round then l.Shape = Enum.PartType.Cylinder end
			table.insert(parts, l)
			-- (a cylinder's axis is its X: along the car)
			table.insert(offsets, turn * CFrame.fromMatrix(pos + dir * (0.09 * k), dir, Vector3.yAxis))
			table.insert(lamps, l)
		end
		local d = spec.r * 2 * k
		local fsz = if spec.round then Vector3.new(0.12 * k, d * 0.92, d * 0.92) else Vector3.new(0.12 * k, spec.r * 1.0 * k, spec.r * 2.3 * k)
		for _, sx in ipairs(if spec.lamp[2] < 0.05 then { 0 } else { -1, 1 }) do
			glow(at(spec.lamp, sx), fwd, warm, fsz, spec.round == true)
		end
		for _, sx in ipairs(if spec.tail[2] < 0.05 then { 0 } else { -1, 1 }) do
			glow(at(spec.tail, sx), -fwd, red, Vector3.new(0.1 * k, 0.45 * k, 0.6 * k), false)
		end
	elseif size.X > 3.5 * SCALE then
		for _, sx in ipairs({ -1, 1 }) do
			lamp(Vector3.new(sx * size.X * 0.32, y, front), warm, Vector3.new(0.9, 0.55, 0.12) * SCALE)
			lamp(Vector3.new(sx * size.X * 0.36, y + 0.4 * SCALE, back), red, Vector3.new(0.6, 0.45, 0.12) * SCALE)
		end
	else
		lamp(Vector3.new(0, size.Y * 0.1, front), warm, Vector3.new(0.6, 0.6, 0.12) * SCALE)
		lamp(Vector3.new(0, y, back), red, Vector3.new(0.4, 0.3, 0.12) * SCALE)
	end
	return { model = m, parts = parts, offsets = offsets, lamps = lamps, wheels = wheels, wheelR = wheelR }
end

-- a vehicle at one detail level: its parts and their offsets from its ground point
local function makeVehicle(parent: Instance, kind: string, level: number, seed: number): any
	local rng = Random.new(seed)
	local mesh = meshVehicle(parent, kind, level, rng)
	if mesh then return mesh end
	local spec = BUILD[kind](rng)
	local m = Instance.new("Model")
	m.Name = kind
	local parts, offsets = {}, {}
	local want = if level == 1 then { A = true, L = true } elseif level == 2 then { A = true, m = true, M = true } else { A = true, M = true, H = true }
	for _, pc in ipairs(spec) do
		if want[pc.lv] then
			local p = newPart(m, "P", pc.size * SCALE, CFrame.new(), pc.color)
			if pc.shape == "Cylinder" then p.Shape = Enum.PartType.Cylinder
			elseif pc.shape == "Ball" then p.Shape = Enum.PartType.Ball end
			p.Size = pc.size * SCALE
			if pc.color == GLASS and level == 3 then p.Transparency = 0.35 end
			if level == 3 then p.CastShadow = true end
			table.insert(parts, p)
			table.insert(offsets, CFrame.new(pc.pos * SCALE) * (if pc.turn then CFrame.Angles(0, math.pi / 2, 0) else CFrame.new()))
		end
	end
	m.Parent = parent
	return { model = m, parts = parts, offsets = offsets }
end

--==============================================================
-- the roads
--==============================================================
-- the road's height along a spoke: above every terrace it crosses, then up the embankment to the Grand Trunk
local function spokeY(heightAt: (number) -> number, r: number): number
	-- (2026-10-23: the ground is one continuous slope now, up a bank to the Grand Trunk, so the road
	-- just lies a little above it; it was stepped over terraces and ramped up a wall)
	return math.max(RING_TOP, heightAt(r) + 0.8)
end

function LobbyTraffic.new(root: Instance, heightAt: (number) -> number)
	local self = setmetatable({}, LobbyTraffic)
	self.heightAt = heightAt
	self.folder = Instance.new("Folder")
	self.folder.Name = "Roundabout"
	self.folder.Parent = root
	self.vehicles = {} :: { any }
	self:roads()
	self:clearLines(root)
	self.paths = self:makePaths()
	self.level = quality()
	self:spawn()
	local ok, settings = pcall(function() return UserSettings():GetService("UserGameSettings") end)
	if ok and settings then
		self.conn = (settings :: any):GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
			local q = quality()
			if q ~= self.level then
				self.level = q
				self:spawn()
			end
		end)
	end
	return self
end

function LobbyTraffic:roads()
	local f = Instance.new("Folder")
	f.Name = "Roads"
	f.Parent = self.folder
	-- the ring: asphalt on a dirt bank, white edges, a dashed lane line
	local n = 120
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local w = 2 * math.pi * (RING_R + RING_W / 2) / n + 2
		local p = CENTRE + radial(a) * RING_R
		local face = CFrame.lookAt(Vector3.new(p.X, 0, p.Z), Vector3.new(CENTRE.X, 0, CENTRE.Z))
		local road = newPart(f, "Ring", Vector3.new(w, 1.2, RING_W), face + Vector3.new(0, RING_TOP - 0.6, 0), ASPHALT, Enum.Material.Asphalt)
		textured(road, "TC_Asphalt")
		local bank = newPart(f, "Bank", Vector3.new(w, RING_TOP + 6, RING_W + 12), face + Vector3.new(0, (RING_TOP - 1.2) / 2 - 3, 0), DIRT, Enum.Material.Ground)
		textured(bank, "TC_Dirt")
		for _, side in ipairs({ -1, 1 }) do
			newPart(f, "Edge", Vector3.new(w, 0.2, 1.2), face * CFrame.new(0, RING_TOP + 0.1, side * (RING_W / 2 - 2)), LINE)
		end
		if i % 2 == 0 then newPart(f, "Lane", Vector3.new(w * 0.5, 0.2, 0.8), face + Vector3.new(0, RING_TOP + 0.1, 0), LINE) end
		if i % 30 == 0 then task.wait() end
	end
	-- the spokes: from the ring out along each yard's line of fire, on a causeway over the terraces
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local dir = radial(a)
		local r = RING_R + RING_W / 2 - 3
		local seg = 0
		while r < SPOKE_END do
			local r1 = math.min(r + 30, SPOKE_END)
			local p0 = CENTRE + dir * r + Vector3.new(0, spokeY(self.heightAt, r), 0)
			local p1 = CENTRE + dir * r1 + Vector3.new(0, spokeY(self.heightAt, r1), 0)
			local len = (p1 - p0).Magnitude
			local cf = CFrame.lookAt((p0 + p1) / 2, p1)
			local road = newPart(f, "Spoke", Vector3.new(SPOKE_W, 1.2, len + 0.6), cf * CFrame.new(0, -0.6, 0), ASPHALT, Enum.Material.Asphalt)
			textured(road, "TC_Asphalt")
			local drop = ((p0 + p1) / 2).Y - self.heightAt((r + r1) / 2) + 8
			local bank = newPart(f, "Causeway", Vector3.new(SPOKE_W + 12, drop, len), cf * CFrame.new(0, -1.2 - drop / 2, 0), DIRT, Enum.Material.Ground)
			textured(bank, "TC_Dirt")
			for _, side in ipairs({ -1, 1 }) do
				newPart(f, "Edge", Vector3.new(1.2, 0.2, len + 0.6), cf * CFrame.new(side * (SPOKE_W / 2 - 2), 0.1, 0), LINE)
			end
			if seg % 2 == 0 then newPart(f, "Centre", Vector3.new(0.9, 0.2, len * 0.55), cf * CFrame.new(0, 0.1, 0), YELLOW) end
			seg += 1
			r = r1
		end
		task.wait()
	end
end

-- move the field villages off the roads (they're the vista's own client-built models)
function LobbyTraffic:clearLines(root: Instance)
	local villages = root:FindFirstChild("Villages", true)
	if not villages then return end
	for _, m in ipairs(villages:GetChildren()) do
		if m:IsA("Model") then
			local pos = m:GetPivot().Position - CENTRE
			local r = Vector3.new(pos.X, 0, pos.Z).Magnitude
			local a = math.atan2(pos.Z, pos.X)
			local k = math.floor(a / (math.pi / 4) + 0.5)
			local off = a - k * math.pi / 4
			local lateral = math.sin(off) * r
			if math.abs(lateral) < 60 and r > RING_R then
				local push = ((if lateral >= 0 then 1 else -1) * 70 - lateral) / r
				local spin = CFrame.new(CENTRE) * CFrame.Angles(0, -push, 0) * CFrame.new(-CENTRE)
				m:PivotTo(spin * m:GetPivot())
			end
		end
	end
end

-- a path is a list of points (with y) and their running lengths
-- (2026-10-22) rounded corners: Chaikin's cut, a few times over, turns every corner into a curve
-- (a road into the ring was a right angle the vehicles snapped round in one frame)
local function rounded(points: { Vector3 }, loop: boolean, passes: number): { Vector3 }
	local pts = points
	for _ = 1, passes do
		local out = {}
		local n = #pts
		if not loop then table.insert(out, pts[1]) end
		for i = 1, (if loop then n else n - 1) do
			local a, b = pts[i], pts[i % n + 1]
			table.insert(out, a:Lerp(b, 0.25))
			table.insert(out, a:Lerp(b, 0.75))
		end
		if not loop then table.insert(out, pts[n]) end
		pts = out
	end
	return pts
end

-- the same line at an even spacing, so speed along it is speed on the ground
local function evenly(points: { Vector3 }, loop: boolean, step: number): { Vector3 }
	local pts = table.clone(points)
	if loop then table.insert(pts, points[1]) end
	local out = { pts[1] }
	local carry = 0
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude
		local d = step - carry
		while d <= len do
			table.insert(out, a:Lerp(b, d / len))
			d += step
		end
		carry = len - (d - step)
	end
	if loop then table.remove(out) end
	return out
end

local function newPath(points: { Vector3 }, loop: boolean): any
	points = evenly(rounded(points, loop, 4), loop, 2.5)
	local lengths = { 0 }
	for i = 2, #points do lengths[i] = lengths[i - 1] + (points[i] - points[i - 1]).Magnitude end
	local total = lengths[#points]
	if loop then total += (points[1] - points[#points]).Magnitude end
	-- how sharply it bends at each point (radians a stud), for easing off
	local bend = {}
	local n = #points
	for i = 1, n do
		local a = points[if i == 1 then (if loop then n else 1) else i - 1]
		local b = points[i]
		local c = points[if i == n then (if loop then 1 else n) else i + 1]
		local d1 = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local d2 = Vector3.new(c.X - b.X, 0, c.Z - b.Z)
		if d1.Magnitude > 1e-3 and d2.Magnitude > 1e-3 then
			local cross = d1.Unit:Cross(d2.Unit).Y
			bend[i] = math.asin(math.clamp(cross, -1, 1)) / ((d1.Magnitude + d2.Magnitude) / 2)
		else
			bend[i] = 0
		end
	end
	-- (looking a little ahead: a driver brakes before the bend, not in it)
	local ahead = {}
	for i = 1, n do
		local m = 0
		for j = 0, 8 do
			local k = i + j
			if k > n then k = if loop then k - n else n end
			m = math.max(m, math.abs(bend[k]))
		end
		ahead[i] = m
	end
	return { points = points, lengths = lengths, total = total, loop = loop, bend = bend, ahead = ahead }
end

function LobbyTraffic:makePaths(): any
	local ring = {}
	local rr = RING_R - LANE
	for i = 0, 179 do
		local a = i / 180 * math.pi * 2
		table.insert(ring, CENTRE + radial(a) * rr + Vector3.new(0, RING_TOP, 0))
	end
	local through = {}
	-- in along road k (left lane), clockwise round the outer lane, out along road k+m (left lane)
	for k = 0, 7 do
		through[k] = {}
		for m = 1, 7 do
			local pts = {}
			local ak = k / 8 * math.pi * 2
			local dk = radial(ak)
			local leftIn = Vector3.yAxis:Cross(-dk) * LANE
			local ro = RING_R + LANE
			-- (2026-10-23, the owner: "some things move sideways". The road met the ring at a right-angle
			-- kink, so a car swung round on the spot. Now it leaves the road early and sweeps onto the
			-- ring, and off it, on a curve)
			local rEdge = RING_R + RING_W / 2 + 26
			local r = SPOKE_END - 10
			while r > rEdge do
				table.insert(pts, CENTRE + dk * r + leftIn + Vector3.new(0, spokeY(self.heightAt, r), 0))
				r -= 20
			end
			local function curve(p0: Vector3, p1: Vector3, p2: Vector3)
				for i = 1, 9 do
					local u = i / 10
					table.insert(pts, p0:Lerp(p1, u):Lerp(p1:Lerp(p2, u), u))
				end
			end
			local sweep = (LANE + 30) / ro
			local a0 = ak + sweep
			local aj = (k + m) / 8 * math.pi * 2
			local a1 = aj - sweep
			local up = Vector3.new(0, RING_TOP, 0)
			curve(CENTRE + dk * rEdge + leftIn + Vector3.new(0, spokeY(self.heightAt, rEdge), 0), CENTRE + dk * ro + leftIn + up, CENTRE + radial(a0) * ro + up)
			local a = a0
			while a < a1 do
				table.insert(pts, CENTRE + radial(a) * ro + up)
				a += 0.02
			end
			local dj = radial(aj)
			local leftOut = Vector3.yAxis:Cross(dj) * LANE
			table.insert(pts, CENTRE + radial(a1) * ro + up)
			curve(CENTRE + radial(a1) * ro + up, CENTRE + dj * ro + leftOut + up, CENTRE + dj * rEdge + leftOut + Vector3.new(0, spokeY(self.heightAt, rEdge), 0))
			r = rEdge
			while r <= SPOKE_END - 10 do
				table.insert(pts, CENTRE + dj * r + leftOut + Vector3.new(0, spokeY(self.heightAt, r), 0))
				r += 20
			end
			through[k][m] = newPath(pts, false)
		end
	end
	return { ring = newPath(ring, true), through = through }
end

-- the point and heading at a distance along a path
local function sample(path: any, s: number): (Vector3, Vector3)
	local pts, lens = path.points, path.lengths
	local n = #pts
	s = s % path.total
	if path.loop and s >= lens[n] then
		local t = (s - lens[n]) / math.max(path.total - lens[n], 1e-3)
		local d = pts[1] - pts[n]
		return pts[n] + d * t, d.Unit
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if lens[mid] <= s then lo = mid else hi = mid end
	end
	local a, b = pts[lo], pts[hi]
	local seg = lens[hi] - lens[lo]
	local t = if seg > 0 then (s - lens[lo]) / seg else 0
	return a + (b - a) * t, (b - a).Unit
end

local function bendAt(path: any, s: number): (number, number)
	local lens, n = path.lengths, #path.points
	s = s % path.total
	local i = math.clamp(math.floor(s / 2.5) + 1, 1, n)
	return path.bend[i] or 0, path.ahead[i] or 0
end

--==============================================================
-- driving (2026-10-24, the owner: "fix the car physics and pathfinding, they're old and coded
-- terribly"). Each vehicle is driven, not slid along its line:
--   steering  a bicycle model: the rear axle follows the heading, the heading turns by the speed over
--             the wheelbase times tan(steer), and the steer chases a point a little down the road (pure
--             pursuit), rate-limited, so every turn is an arc the wheels could make and nothing ever moves
--             sideways. The front wheels turn with the steer.
--   speed     the Intelligent Driver Model: it eases up to its own pace, slows for the bends ahead
--             (the lateral grip it would need), and keeps a safe time gap behind whatever is in the
--             stretch of road it is about to drive over (its corridor), whichever way that thing faces.
--   priority  the ring has right of way. A car coming in off a road stops at the give-way line until
--             the ring is clear of anything arriving within a few seconds; two cars in each other's way
--             resolve by priority, then by who is further along, so nothing stands nose to nose for good.
--   body      pitched to the road under its two axles, rocked by its braking and leaning out in the
--             bends on soft springs, and a little bob at speed.
--==============================================================
local LOOK_STEP, LOOK_MAX = 4, 72   -- the corridor: checked every 4 studs, up to 72 ahead
local GAP_T, GAP_S0 = 1.3, 4        -- IDM: time gap (s) and the standing gap (studs)
local MAX_STEER, STEER_RATE = 0.62, 1.6
local GRIP = 14                     -- studs/s^2 of sideways pull a driver is happy with in a bend
local YIELD_T = 3.2                 -- seconds of clear ring a car wants before it pulls on

-- where the ring's priority lane is on a path (by radius) and where its give-way line is
local function priorities(path: any)
	local prio = {}
	local yieldS = nil
	local onRing = false
	for i, p in ipairs(path.points) do
		local r = Vector3.new(p.X - CENTRE.X, 0, p.Z - CENTRE.Z).Magnitude
		local ring = path.loop or math.abs(r - RING_R) < RING_W / 2 + 1
		prio[i] = if ring then 2 else 1
		if ring and not onRing and not path.loop and not yieldS then
			yieldS = math.max(0, path.lengths[i] - 6)
			path.mergeAt = p
		end
		onRing = ring
	end
	path.prio = prio
	path.yieldS = yieldS
end

local function prioAt(path: any, s: number): number
	local i = math.clamp(math.floor((s % path.total) / 2.5) + 1, 1, #path.points)
	return path.prio[i] or 1
end

-- the curvature the road will ask for over the next `span` studs (radians a stud)
local function bendAhead(path: any, s: number, span: number): number
	local n = #path.points
	local i0 = math.floor((s % path.total) / 2.5) + 1
	local m = 0
	for j = 0, math.ceil(span / 2.5) do
		local k = i0 + j
		if k > n then
			if not path.loop then break end
			k -= n
		end
		m = math.max(m, math.abs(path.bend[k] or 0))
	end
	return m
end

-- the axles and wheel radii of a vehicle, from its wheels as built (frame space: -z is the front)
local function chassis(v: any)
	local zF, zR, nf, nr = 0, 0, 0, 0
	v.front = {}
	for i, part in ipairs(v.parts) do
		local name = part.Name
		if string.match(name, "^WheelF") then
			zF += v.offsets[i].Position.Z
			nf += 1
			v.front[i] = true
		elseif string.match(name, "^WheelR") or string.match(name, "^WheelT") then
			zR += v.offsets[i].Position.Z
			nr += 1
		end
	end
	if nf > 0 and nr > 0 then
		zF /= nf
		zR /= nr
	end
	-- (a part-built stand-in has no named wheels: its axles at a fifth from each end)
	if nf == 0 or nr == 0 or zR - zF < 1 then
		zF, zR = -v.len * 0.3, v.len * 0.3
		v.front = {}
	end
	v.zF, v.zR = zF, zR
	v.base = zR - zF
end

function LobbyTraffic:spawn()
	for _, v in ipairs(self.vehicles) do v.model:Destroy() end
	self.vehicles = {}
	self.night = nil -- (the new vehicles' lamps get set on the next check)
	if workspace:GetAttribute("LobbyTraffic") == false then return end
	local count = COUNTS[self.level]
	local rng = Random.new(20261015)
	self.rng = Random.new(20261024)
	local ringPath = self.paths.ring
	if not ringPath.prio then
		priorities(ringPath)
		for k = 0, 7 do
			for m = 1, 7 do priorities(self.paths.through[k][m]) end
		end
	end
	local id = 0
	local function add(kind: string, path: any, s: number)
		id += 1
		local v = makeVehicle(self.folder, kind, self.level, rng:NextInteger(1, 1e6))
		v.id = id
		v.kind = kind
		v.path = path
		v.s = s % path.total
		local seed = Random.new(id * 7919)
		v.pace = (PACE[kind] or SPEED) * seed:NextNumber(0.9, 1.08)
		v.speed = v.pace * 0.6
		v.wob = seed:NextNumber(0, 6.28)
		local _, size = v.model:GetBoundingBox()
		v.len, v.wid = size.Z, size.X
		v.wheels = v.wheels or {}
		chassis(v)
		self:place(v)
		table.insert(self.vehicles, v)
	end
	for i = 1, count.ring do
		add(MIX[rng:NextInteger(1, #MIX)], ringPath, (i - 1) / count.ring * ringPath.total)
	end
	for k = 0, 7 do
		for j = 1, count.per do
			local path = self.paths.through[k][rng:NextInteger(1, 7)]
			add(MIX[rng:NextInteger(1, #MIX)], path, (j - 1) / count.per * path.total + k * 97)
		end
	end
end

-- set a vehicle down on its path at v.s, heading along it, its suspension at rest
function LobbyTraffic:place(v: any)
	local p, d = sample(v.path, v.s)
	local h = Vector3.new(d.X, 0, d.Z)
	h = if h.Magnitude > 1e-3 then h.Unit else Vector3.new(0, 0, -1)
	v.h = h
	v.rear = Vector3.new(p.X, 0, p.Z) - h * (v.base / 2)
	v.steer = 0
	v.pitch, v.pitchV, v.roll, v.rollV = 0, 0, 0, 0
	v.spin = v.spin or 0
	v.accel = 0
	v.held = 0
end

-- the distance along the path nearest to a point, searched around the last one
local function project(path: any, s0: number, p: Vector3, reach: number): number
	local best, bestD = s0, math.huge
	local step = 0.6
	local a = -1.5
	while a <= reach do
		local s = s0 + a
		if path.loop or (s >= 0 and s <= path.total) then
			local q = sample(path, s)
			local dx, dz = q.X - p.X, q.Z - p.Z
			local dd = dx * dx + dz * dz
			if dd < bestD then best, bestD = s, dd end
		end
		a += step
	end
	return best
end

-- what lies in v's corridor: the nearest thing its body would reach, how far, and how fast that is
-- going along v's way
function LobbyTraffic:corridor(v: any): (any?, number)
	local best, bestGap = nil, math.huge
	local reachW = v.wid / 2 + 0.6
	local pts = v.look
	for _, u in ipairs(self.vehicles) do
		if u ~= v and u.pos and not u.hidden then
			local d = u.pos - v.pos
			local dist2 = d.X * d.X + d.Z * d.Z
			if dist2 < (LOOK_MAX + 20) ^ 2 and (d.X * v.h.X + d.Z * v.h.Z) > -u.len then
				-- u's box, tested against each point down v's road
				local ux, uz = u.h.X, u.h.Z
				local hl, hw = u.len / 2, u.wid / 2 + reachW
				for j, q in ipairs(pts) do
					local qx, qz = q.X - u.pos.X, q.Z - u.pos.Z
					local along = qx * ux + qz * uz
					local side = -qx * uz + qz * ux
					if math.abs(along) < hl + 0.4 and math.abs(side) < hw then
						local gap = j * LOOK_STEP - v.len / 2 - 1
						if gap < bestGap then best, bestGap = u, gap end
						break
					end
				end
			end
		end
	end
	return best, bestGap
end

function LobbyTraffic:step(t: number)
	local dt = math.clamp(t - (self.lastT or t), 0, 0.1)
	self.lastT = t
	if dt <= 0 then return end
	-- the lamps follow the clock (checked every couple of seconds)
	self.frame = (self.frame or 0) + 1
	if self.frame % 120 == 1 then
		local c = game:GetService("Lighting").ClockTime
		local night = c >= 17.6 or c < 6.3
		if night ~= self.night then
			self.night = night
			for _, v in ipairs(self.vehicles) do
				v.fadeShown = nil -- (the fade below repaints the lamps at the new time of day)
				for _, l in ipairs(v.lamps or {}) do l.Transparency = if night then 0 else 1 end
			end
		end
	end
	-- 1 where everyone is, and the road each is about to drive over
	for _, v in ipairs(self.vehicles) do
		v.pos = v.rear + v.h * (v.base / 2)
		v.prio = prioAt(v.path, v.s)
		local look = v.look or {}
		local n = math.floor(LOOK_MAX / LOOK_STEP)
		for j = 1, n do
			local sj = v.s + j * LOOK_STEP
			if not v.path.loop and sj > v.path.total then sj = v.path.total end
			look[j] = sample(v.path, sj)
		end
		v.look = look
	end
	-- 2 who is in whose way
	for _, v in ipairs(self.vehicles) do
		v.leader, v.gap = self:corridor(v)
	end
	-- 3 two in each other's way: the one with the right of way (the ring), else the one further along,
	-- drives on; the other waits
	for _, v in ipairs(self.vehicles) do
		local u = v.leader
		if u and u.leader == v then
			local vFirst = v.prio > u.prio or (v.prio == u.prio and v.id < u.id)
			if vFirst then v.leader, v.gap = nil, math.huge end
		end
	end
	local parts, cfs = {}, {}
	for _, v in ipairs(self.vehicles) do
		-- the pace this stretch allows: no more sideways pull than GRIP in the bends ahead
		local span = math.max(20, v.speed * 2.2)
		local k = bendAhead(v.path, v.s, span)
		local vCurve = if k > 1e-4 then math.sqrt(GRIP / k) else math.huge
		local v0 = math.max(6, math.min(v.pace, vCurve))
		-- IDM toward that, behind the leader (or the give-way line)
		local a = 1 - (v.speed / v0) ^ 4
		local function behind(gap: number, otherSpeed: number)
			local sStar = GAP_S0 + v.speed * GAP_T + v.speed * (v.speed - otherSpeed) / (2 * math.sqrt(ACCEL * BRAKE))
			a -= (math.max(sStar, 0) / math.max(gap, 0.5)) ^ 2
		end
		if v.leader then
			local u = v.leader
			behind(v.gap, u.speed * math.max(0, u.h:Dot(v.h)))
		end
		-- the give-way line: a car coming in off a road waits for a clear stretch of ring
		local y = v.path.yieldS
		if y and v.s < y and v.s > y - 60 then
			local clear = true
			local m = v.path.mergeAt
			for _, u in ipairs(self.vehicles) do
				if u ~= v and u.prio == 2 and u.pos and not u.path.loop then -- (the inner lane's ring cars never cross it)
					local d = m - u.pos
					local dist = math.sqrt(d.X * d.X + d.Z * d.Z)
					local closing = (d.X * u.h.X + d.Z * u.h.Z) / math.max(dist, 0.01)
					if dist < 16 or (closing > 0.3 and dist / math.max(u.speed, 1) < YIELD_T) then
						clear = false
						break
					end
				end
			end
			if not clear then behind(y - v.s, 0) end
		end
		local acc = math.clamp(a * ACCEL, -BRAKE * 1.6, ACCEL)
		-- (a car held up for long, in a knot nothing else resolves, creeps on)
		v.held = if v.speed < 0.5 then v.held + dt else 0
		if v.held > 8 then acc = math.max(acc, 2) end
		v.accel = v.accel + (acc - v.accel) * math.min(1, dt * 6)
		v.speed = math.max(0, v.speed + acc * dt)

		-- steering: pure pursuit toward a point down the road, from the rear axle
		local Ld = math.max(7, v.base * 1.1 + v.speed * 0.35)
		local target = sample(v.path, if v.path.loop then v.s + Ld else math.min(v.s + Ld, v.path.total))
		local to = Vector3.new(target.X - v.rear.X, 0, target.Z - v.rear.Z)
		local want = 0
		if to.Magnitude > 0.5 then
			local tu = to.Unit
			-- (+ turns the heading from +X toward +Z: a right turn, as the rotation below does it)
			local sinA = v.h.X * tu.Z - v.h.Z * tu.X
			local cosA = v.h:Dot(tu)
			local alpha = math.atan2(sinA, cosA)
			want = math.clamp(math.atan(2 * v.base * math.sin(alpha) / to.Magnitude), -MAX_STEER, MAX_STEER)
		end
		local ds = math.clamp(want - v.steer, -STEER_RATE * dt, STEER_RATE * dt)
		v.steer += ds
		-- the bicycle: move the rear axle along the heading, turn the heading by the steer
		local dist = v.speed * dt
		local yawRate = v.speed / v.base * math.tan(v.steer)
		v.rear += v.h * dist
		local yaw = yawRate * dt
		local c, s = math.cos(yaw), math.sin(yaw)
		v.h = Vector3.new(v.h.X * c - v.h.Z * s, 0, v.h.X * s + v.h.Z * c).Unit
		v.s = project(v.path, v.s, v.rear + v.h * (v.base / 2), dist + 2)
		-- the road under it: wrap a through route from its far end to its start (out of sight, faded)
		if not v.path.loop and v.s >= v.path.total - 1 then
			v.path = self.paths.through[self.rng:NextInteger(0, 7)][self.rng:NextInteger(1, 7)]
			v.s = 0
			self:place(v)
		elseif v.path.loop and v.s >= v.path.total then
			v.s -= v.path.total
		end
		-- (safety: if it ever strays off its lane, put it back on it)
		local onRoad = sample(v.path, v.s)
		local centre = v.rear + v.h * (v.base / 2)
		if (Vector3.new(onRoad.X - centre.X, 0, onRoad.Z - centre.Z)).Magnitude > 6 then self:place(v) end

		-- fade in and out at the far ends of a through route
		if not v.path.loop then
			local FADE = 90
			local f = math.clamp(math.min(v.s, v.path.total - v.s) / FADE, 0, 1)
			f = f * f * (3 - 2 * f)
			v.hidden = f < 0.05
			if v.fadeShown == nil or math.abs(f - v.fadeShown) > 0.03 or (f == 1 and v.fadeShown ~= 1) or (f == 0 and v.fadeShown ~= 0) then
				v.fadeShown = f
				local isLamp = {}
				for _, l in ipairs(v.lamps or {}) do
					isLamp[l] = true
					l.Transparency = if self.night then 1 - f else 1
				end
				for _, part in ipairs(v.parts) do
					if not isLamp[part] then part.Transparency = 1 - f end
				end
			end
		end

		-- the body: on the road under its two axles, rocking on its springs
		local front = v.rear + v.h * v.base
		local yR = sample(v.path, v.s - v.base / 2).Y
		local yF = sample(v.path, v.s + v.base / 2).Y
		local lat = v.speed * yawRate -- sideways acceleration in the bend
		local pitchT = math.clamp(v.accel * 0.006, -0.06, 0.05) -- (braking dips the nose)
		local rollT = math.clamp(lat * 0.004, -0.06, 0.06)
		-- (a damped spring each, so a hard stop nods and settles)
		v.pitchV += ((pitchT - v.pitch) * 60 - v.pitchV * 9) * dt
		v.pitch += v.pitchV * dt
		v.rollV += ((rollT - v.roll) * 50 - v.rollV * 8) * dt
		v.roll += v.rollV * dt
		local mid = (v.rear + front) / 2
		local axle = Vector3.new(mid.X, (yR + yF) / 2, mid.Z)
		local slope = math.atan2(yF - yR, v.base)
		local bob = math.sin(t * 7 + v.wob) * 0.03 * SCALE * math.min(1, v.speed / 30)
		local ground = CFrame.lookAt(axle, axle + v.h) * CFrame.Angles(slope, 0, 0)
		-- the frame the offsets were built in: its origin back from the axles' middle
		local frame = ground * CFrame.new(0, 0, -(v.zF + v.zR) / 2)
		local body = frame * CFrame.new(0, bob, 0) * CFrame.Angles(v.pitch, 0, v.roll)
		v.spin -= dist
		for i, part in ipairs(v.parts) do
			table.insert(parts, part)
			local off = v.offsets[i]
			local wr = v.wheels[i]
			if wr then
				local r = if type(wr) == "number" then wr else (v.wheelR or 1.4 * SCALE)
				local turnW = if v.front[i] then CFrame.Angles(0, -v.steer, 0) else CFrame.new()
				table.insert(cfs, frame * CFrame.new(off.Position) * turnW * CFrame.Angles(v.spin / math.max(0.5, r), 0, 0) * off.Rotation)
			else
				table.insert(cfs, body * off)
			end
		end
	end
	if #parts > 0 then workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
end

function LobbyTraffic:destroy()
	if self.conn then self.conn:Disconnect() end
	self.folder:Destroy()
end

return LobbyTraffic
