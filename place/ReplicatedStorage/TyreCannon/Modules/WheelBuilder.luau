--!strict
-- TYRE CANNON :: WheelBuilder
-- One wheel, built properly: a carcass with bulged sidewalls, a staggered
-- tread pattern, and a rim that is its own assembly so it can be swapped as a
-- separate cosmetic.
--
-- The model is built around the origin with the axle on local Z and the
-- rolling direction on local X. Move it with model:PivotTo(cf * roll) -- one
-- engine-side call instead of a Lua loop over thirty parts every frame.

local Config = require(script.Parent.Config)

local WheelBuilder = {}

local TREAD_BLOCKS = 16

local function mk(parent, name, size, cf, color, mat, reflect)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if reflect then p.Reflectance = reflect end
	p.Parent = parent
	return p
end

local function cyl(parent, name, size, cf, color, mat, reflect)
	local p = mk(parent, name, size, cf, color, mat, reflect)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- a cylinder's own axis is its local X, so spin it onto the wheel's Z
local AXLE = CFrame.Angles(0, math.rad(90), 0)

--==============================================================
-- build(parent, radius, width, skinId, rimId) -> Model
--==============================================================
function WheelBuilder.build(parent: Instance, radius: number, width: number,
	skinId: string?, rimId: string?)

	local skin = Config.SkinsById[skinId or "stock"] or Config.SkinsById.stock
	local rim = Config.RimsById[rimId or "steel"] or Config.RimsById.steel

	local m = Instance.new("Model")
	m.Name = "Wheel"

	local R, W = radius, width
	local rubber = skin.tyre
	local rubberMat = skin.material
	local sidewallColor = rubber:Lerp(Color3.new(0, 0, 0), 0.35)

	-- W is the full tyre width. A real tyre is roughly a third as wide as it
	-- is tall, and its rim sits PROUD of the sidewall rather than buried in it,
	-- which is the only way the rim reads at all on solid primitives.
	local half = W * 0.5

	---------------------------------------------------------------
	-- carcass and sidewalls
	---------------------------------------------------------------
	local carcass = cyl(m, "Carcass", Vector3.new(W * 0.90, R * 2, R * 2), AXLE,
		rubber, rubberMat, skin.reflect)
	m.PrimaryPart = carcass

	for _, s in ipairs({ -1, 1 }) do
		cyl(m, "Sidewall", Vector3.new(W * 0.08, R * 1.90, R * 1.90),
			CFrame.new(0, 0, s * half * 0.94) * AXLE, sidewallColor, rubberMat, skin.reflect)
	end

	---------------------------------------------------------------
	-- tread: chunky blocks with real gaps, alternating across the centre line
	---------------------------------------------------------------
	local treadColor = rubber:Lerp(Color3.new(1, 1, 1), 0.10)
	for i = 1, TREAD_BLOCKS do
		local a = (i / TREAD_BLOCKS) * math.pi * 2
		local side = (i % 2 == 0) and 1 or -1
		mk(m, "Tread",
			-- x radial, y tangential, z across the tread
			Vector3.new(R * 0.09, R * 0.26, W * 0.42),
			CFrame.Angles(0, 0, a) * CFrame.new(R * 0.975, 0, side * W * 0.22)
				* CFrame.Angles(math.rad(side * 14), 0, 0),
			treadColor, rubberMat, skin.reflect)
	end

	---------------------------------------------------------------
	-- rim, standing proud of each sidewall
	---------------------------------------------------------------
	local barrelR = R * (rim.style == "dish" and 0.64 or 0.58)
	local faceR = R * (rim.style == "dish" and 0.50 or 0.55)
	local rimMat = rim.neon and Enum.Material.Neon or Enum.Material.Metal
	local spokeCount = rim.spokes or 6
	if rim.style == "mesh" then spokeCount = spokeCount * 2 end
	local thin = (rim.style == "mesh") and 0.045 or 0.12

	cyl(m, "RimBarrel", Vector3.new(W * 1.02, barrelR * 2, barrelR * 2), AXLE,
		rim.barrel, rimMat, rim.reflect)

	for _, s in ipairs({ -1, 1 }) do
		local zLip  = s * (half + W * 0.03)
		local zFace = s * (half + W * 0.08)
		local zHub  = s * (half + W * 0.13)

		-- the outer lip: on a neon rim this is the ring that glows
		local lip = cyl(m, "RimLip", Vector3.new(W * 0.06, barrelR * 2.12, barrelR * 2.12),
			CFrame.new(0, 0, zLip) * AXLE, rim.glow or rim.barrel, rimMat, rim.reflect)
		if rim.glow then
			local lt = Instance.new("PointLight")
			lt.Color = rim.glow; lt.Range = R * 3.2; lt.Brightness = 1.8
			lt.Parent = lip
		end

		if rim.style == "solid" then
			cyl(m, "RimFace", Vector3.new(W * 0.07, faceR * 2, faceR * 2),
				CFrame.new(0, 0, zFace) * AXLE, rim.face, Enum.Material.Metal, rim.reflect)
		else
			for i = 1, spokeCount do
				local a = (i / spokeCount) * math.pi * 2
				mk(m, "Spoke",
					Vector3.new(faceR * 0.94, R * thin, W * 0.07),
					CFrame.Angles(0, 0, a) * CFrame.new(faceR * 0.50, 0, zFace),
					rim.face, Enum.Material.Metal, rim.reflect)
			end
		end

		cyl(m, "Hub", Vector3.new(W * 0.10, R * 0.28, R * 0.28),
			CFrame.new(0, 0, zHub) * AXLE,
			rim.face:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal, rim.reflect)
	end

	-- wheel nuts on the outward face only
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		cyl(m, "Nut", Vector3.new(W * 0.05, R * 0.07, R * 0.07),
			CFrame.Angles(0, 0, a) * CFrame.new(R * 0.17, 0, half + W * 0.17) * AXLE,
			Color3.fromRGB(96, 100, 106), Enum.Material.Metal)
	end

	-- An UNROTATED root at the hub, and it is the PrimaryPart.
	-- A model with a PrimaryPart pivots about that part and ignores WorldPivot,
	-- so while the carcass was the primary every PivotTo cancelled out the
	-- 90-degree AXLE turn baked into it: the axle came to lie along the
	-- direction of travel and the tyre tumbled end over end instead of rolling.
	-- The root has no rotation of its own, so PivotTo now means what it reads
	-- like, and it doubles as the mounting point for dust and trails.
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = CFrame.new()
	root.Parent = m
	m.PrimaryPart = root

	m:SetAttribute("Radius", R)
	m:SetAttribute("Width", W)
	m.Parent = parent
	return m
end

--==============================================================
-- recolour an existing wheel in place, for cosmetic previews
--==============================================================
function WheelBuilder.restyle(model: Model, skinId: string?, rimId: string?)
	local parent = model.Parent
	local pivot = model:GetPivot()
	local radius = model:GetAttribute("Radius") or 6
	local width = model:GetAttribute("Width") or 5
	model:Destroy()
	local fresh = WheelBuilder.build(parent, radius, width, skinId, rimId)
	fresh:SetAttribute("Radius", radius)
	fresh:SetAttribute("Width", width)
	fresh:PivotTo(pivot)
	return fresh
end

return WheelBuilder
