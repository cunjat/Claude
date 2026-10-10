--!strict
-- TYRE CANNON :: Models
-- The Blender models, once imported, live under ReplicatedStorage.TyreCannon.Assets:
--   Cannons/Cannon1 .. Cannon5        each with a Body and a Barrel mesh
--   Machines/FuelTank, CoolingTower, Compressor, SpareRack, LaunchRamp, Scoreboard, TyreTower
--   Run/Key, WoodKicker, SteelKicker, DirtKicker, HayBale, RoadBarrier, DesertRocks, PowderKeg,
--       CargoCrate, SaltMarker, Snowman, MoonRock
--   Scenery/<zone id>/<piece>        (backroad, highway, dunes, quarry, docks, saltflats, mountain, moon)
-- Code asks here first and keeps its stand-in when a model isn't there yet, so the game works at
-- every step of the import.
--   Models.get("Run/Key") -> template or nil          Models.list("Scenery/dunes") -> templates
--   Models.place(template, parent, at, scale) -> Model standing with its ground centre at `at`
--   Models.info(name) -> Blender bounds (+ kicker len/theta)   Models.radius(name, scale) -> footprint
--   Models.parts(model) -> its BaseParts

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local AssetInfo = require(Root:WaitForChild("Modules"):WaitForChild("AssetInfo"))
local Physical = require(script.Parent:WaitForChild("Physical"))

local Models = {}

type Info = { min: { number }, max: { number }, len: number?, theta: number? }

function Models.get(path: string): Instance?
	local node: Instance? = Root:FindFirstChild("Assets")
	for name in path:gmatch("[^/]+") do
		if not node then return nil end
		node = node:FindFirstChild(name)
	end
	return node
end

function Models.list(path: string): { Instance }
	local f = Models.get(path)
	return f and f:GetChildren() or {}
end

function Models.info(name: string): Info?
	return (AssetInfo :: any)[name]
end

-- how far the model reaches from its centre on the ground, after scaling
function Models.radius(name: string, scale: number?): number
	local i = Models.info(name)
	if not i then return 8 * (scale or 1) end
	local r = math.max(math.abs(i.min[1]), math.abs(i.max[1]), math.abs(i.min[2]), math.abs(i.max[2]))
	return r * (scale or 1)
end

function Models.parts(m: Instance): { BasePart }
	local out = {}
	if m:IsA("BasePart") then table.insert(out, m) end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(out, d) end
	end
	return out
end

-- A placed model's frame (its pivot): Blender x right, y back, z up comes out as x, z, -y, so a
-- piece built facing Blender -Y faces the model's +Z and a lane built along Blender +X runs +X.
local function toRoblox(x: number, y: number, z: number): Vector3
	return Vector3.new(x, z, -y)
end
Models.toRoblox = toRoblox

-- Studio's 3D importer brings Blender (x, y, z) in as (-x, z, y), and keeps the Blender origin as
-- the mesh's pivot (tilted to Blender's axes). modelFrame keeps that origin and sets the pivot to
-- the model frame above: the importer's frame turned half way round about the vertical.
local FACE = CFrame.Angles(0, math.pi, 0)

local function modelFrame(m: Model)
	local pp = m.PrimaryPart or Models.parts(m)[1]
	if not pp then return end
	m.PrimaryPart = pp
	local origin = (pp.CFrame * pp.PivotOffset).Position
	pp.PivotOffset = pp.CFrame:ToObjectSpace(CFrame.new(origin) * FACE)
end

local function fresh(template: Instance): Model
	local copy = template:Clone()
	local m: Model
	if copy:IsA("Model") then
		m = copy
	else
		m = Instance.new("Model")
		m.Name = template.Name
		copy.Parent = m
	end
	modelFrame(m)
	return m
end

-- a copy of a template whose pivot is its Blender origin in the model frame (for code that places
-- by bounding box)
function Models.copy(template: Instance): Model
	return fresh(template)
end

-- turns a model's pivot (and so how it'll be placed) by `by`, in its own frame
function Models.turn(m: Model, by: CFrame)
	local pp = m.PrimaryPart
	if pp then pp.PivotOffset = pp.PivotOffset * by else m.WorldPivot = m.WorldPivot * by end
end

-- `solid` makes it something you walk into (a yard's machines and decor); the run's world, the
-- title scene and the menu previews leave it off so nothing snags
function Models.place(template: Instance, parent: Instance, at: CFrame, scale: number?, solid: boolean?): Model
	local s = scale or 1
	local m = fresh(template)
	for _, p in ipairs(Models.parts(m)) do
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
	end
	if s ~= 1 then m:ScaleTo(m:GetScale() * s) end
	m:PivotTo(at)
	m.Parent = parent
	if solid then Physical.solidify(m) end
	return m
end

return Models
