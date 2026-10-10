--!strict
-- TYRE CANNON :: Physical
-- Imported models come in as decoration: anchored, CanCollide off (so the run's world and the menus
-- never snag on them). Where you walk they have to be solid. This decides, for each part of a model,
-- what it does when something bumps into it:
--   * a building, a machine, a prop       solid, Box fidelity when big, Hull when small
--   * a tree                              its canopy stays soft; a slim trunk collider carries it
--                                         (a tree that has a Trunk mesh of its own uses that)
--   * foliage, ground cover, pickups      soft: you walk through them
--   * a thin or tiny thing                soft (nothing to bump into)
-- The same rules are baked into the asset templates once from Studio (tools/bake_physical.luau), because
-- fidelity can only be written from a plugin; at runtime the lobby is solidified the same way.

local Physical = {}

-- models that are never in the way, by name without its _1/_2 count
local SOFT_MODEL: { [string]: boolean } = {
	Bush = true, MustardPatch = true, Grass = true, Flower = true, Flowers = true, Rose = true, Weeds = true,
	Shrub = true, Beanstalk = true, Tumbleweed = true, Coin = true, Key = true, StickerPack = true, Stickers = true,
	Wind = true, WindLight = true, WindSmall = true, WindSharp = true, Textures = true,
}
-- parts of any model that are never in the way
local SOFT_PART: { [string]: boolean } = {
	Leaf = true, Leaves = true, Canopy = true, FlowerTop = true, FlowerMid = true, Stalk = true, Petal = true,
}
-- a tree built as one mesh: model name -> trunk width as a share of the canopy's narrower side
local TREES: { [string]: number } = {
	Safeda = 0.1, Birch = 0.08, Poplar = 0.12, Oak = 0.1, Tree = 0.1, Palm = 0.07, Khejri = 0.1,
	Pine = 0.1, Olbrek = 0.1, Tuscany = 0.1, Sequoia = 0.1,
}

local MIN_SIDE = 1.5      -- the longest side of a part has to be at least this to be worth bumping into
local BIG = 30            -- over this (the diagonal) a mesh gets a Box fidelity, under it a Hull

-- "Pine_3" -> "Pine", "Flower1" -> "Flower"
local function base(s: string): string
	return (s:gsub("[_%d]+$", ""))
end

local function modelNameOf(part: BasePart): string
	local m = part:FindFirstAncestorWhichIsA("Model")
	return base(m and m.Name or part.Name)
end

local function trunkFor(part: BasePart, share: number)
	if part:FindFirstChild("TrunkCollider") then return end
	local s = part.Size
	local w = math.max(2.4, math.min(s.X, s.Z) * share)
	local h = s.Y * 0.92
	local c = Instance.new("Part")
	c.Name = "TrunkCollider"
	c:SetAttribute("Collider", true)
	c.Size = Vector3.new(w, h, w)
	c.CFrame = part.CFrame * CFrame.new(0, -s.Y / 2 + h / 2, 0)
	c.Anchored = true
	c.Transparency = 1
	c.CanCollide = true
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	c.Parent = part
end

-- one part: solid, soft or given a trunk
function Physical.part(p: BasePart)
	if p:GetAttribute("Collider") then
		p.CanCollide = true      -- (a placed copy has had its collision cleared, this puts a trunk's back)
		return
	end
	if p:GetAttribute("Soft") or p.Transparency >= 0.95 then return end
	local model = modelNameOf(p)
	local name = base(p.Name)
	if SOFT_MODEL[model] or SOFT_PART[name] then
		p.CanCollide = false
		return
	end
	local tree = TREES[model]
	if tree and name ~= "Trunk" then
		p.CanCollide = false
		trunkFor(p, tree)
		return
	end
	local s = p.Size
	if math.max(s.X, s.Y, s.Z) < MIN_SIDE then
		p.CanCollide = false
		return
	end
	p.CanCollide = true
	if p:IsA("MeshPart") or p:IsA("PartOperation") then
		-- (fidelity can only be written from a plugin: in the game it's left as imported, and the
		-- place gets it baked in once from Studio, see tools/bake_physical.luau)
		pcall(function()
			(p :: any).CollisionFidelity = if s.Magnitude > BIG then Enum.CollisionFidelity.Box else Enum.CollisionFidelity.Hull
		end)
	end
end

-- a model (or part) and everything inside it
function Physical.solidify(root: Instance)
	if root:IsA("BasePart") then Physical.part(root) end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then Physical.part(d) end
	end
end

-- a folder of the world (the lobby): everything in it now, and whatever streams in later
function Physical.watch(root: Instance, skip: { [string]: boolean }?)
	local function consider(d: Instance)
		if d:IsA("BasePart") then
			if skip then
				local a: Instance? = d
				while a and a ~= root do
					if skip[a.Name] then return end
					a = a.Parent
				end
			end
			Physical.part(d)
		end
	end
	for _, d in ipairs(root:GetDescendants()) do consider(d) end
	root.DescendantAdded:Connect(consider)
end

return Physical
