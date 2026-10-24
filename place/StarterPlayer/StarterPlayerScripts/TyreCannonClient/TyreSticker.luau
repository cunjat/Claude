--!strict
-- TYRE CANNON :: TyreSticker
-- Stickers on a tyre's sidewall: thin clear plates with the picture on them, laid on the rubber and
-- turning with the tyre. A sticker (the Design remote's format) is
--   { id, a, r, rot, size, mirror }
--     id     a sticker of the pack (WheelAssembly.stickers().byId)
--     a      degrees round the wheel from the top (0 = 12 o'clock, + is clockwise)
--     r      how far out from the hub, as a share of the wheel's radius (0.6 .. 1.0)
--     rot    degrees the picture itself is turned
--     size   0.3 .. 2.5 (1 is about a third of the wheel's radius across)
--     mirror also on the other side of the tyre
--   TyreSticker.apply(model, stickers)   replaces the stickers the model wears
--   TyreSticker.catalogue()              { { id, texture, size, pack } }, grouped by pack
--   TyreSticker.surface(model)           (radius, profile) : profile(r) is how far the sidewall
--                                        stands out from the wheel's middle at r studs from the hub
-- A sticker follows the sidewall: each one sits on the rubber where it is (not on the widest point
-- of the whole wheel), tilted with the sidewall's slope, and one that crosses the shoulder (where the
-- sidewall rolls over into the tread) is laid as two halves folded along its middle, so it bends
-- with the rubber instead of standing off it. Every plate is named "Sticker" and carries the
-- sticker's place in the list (StickerIndex) and its side (StickerSide, 1 or -1).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WheelAssembly = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("WheelAssembly"))

local TyreSticker = {}

local LIFT = 0.04      -- how far a plate stands off the rubber (just enough not to flicker)
local FOLD = 0.035     -- a sticker bends in two once its middle is this far off the straight line

function TyreSticker.catalogue()
	return WheelAssembly.stickers()
end

-- the wheel's own measurements in its pivot's frame: the outer radius and how far its sidewalls stand
-- out along the axle (every tyre is built with its axle along Z and the pivot at the wheel's centre)
local function measure(model: Model): (number, number)
	local pivot = model:GetPivot()
	local radius, zMax = 0, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Sticker" then
			local half = d.Size / 2
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local p = pivot:PointToObjectSpace(d.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)))
						-- how far out it reaches along the wheel's own axes: the distance to a box's corner would
						-- overshoot a round tyre by up to 40%
						radius = math.max(radius, math.abs(p.X), math.abs(p.Y))
						zMax = math.max(zMax, math.abs(p.Z))
					end
				end
			end
		end
	end
	return radius, zMax
end

-- the sidewall's shape, sampled once per kind of wheel: rays straight down the axle onto a copy of
-- it at a range of distances from the hub (several angles each, keeping the highest, so raised
-- lettering or lugs count). Kept as a share of the radius so any size of the same wheel shares it.
local SAMPLES = 16
local R_LO, R_HI = 0.45, 1.02
local profiles: { [string]: { number } } = {}

local function keyOf(model: Model): string
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") then
			local ok, id = pcall(function() return (d :: MeshPart).MeshId end)
			table.insert(parts, if ok then tostring(id) else d.Name)
		elseif d:IsA("BasePart") and d.Name ~= "Sticker" then
			table.insert(parts, d.ClassName .. d.Name)
		end
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

local function sample(model: Model, radius: number, zMax: number): { number }?
	local copy: Model? = nil
	local ok, res = pcall(function()
		copy = model:Clone()
		local copy = copy :: Model
		for _, c in ipairs(copy:GetChildren()) do
			if c.Name == "Sticker" then c:Destroy() end
		end
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = true
				d.Transparency = 1
			elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
				d:Destroy()
			end
		end
		local far = CFrame.new(0, 40000, 0)
		copy:PivotTo(far)
		copy.Parent = workspace
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { copy }
		local out = {}
		local depth = zMax + 4
		for i = 0, SAMPLES - 1 do
			local r = radius * (R_LO + (R_HI - R_LO) * i / (SAMPLES - 1))
			local best = nil
			for k = 0, 7 do
				local ang = (k + 0.5) * math.pi / 4
				local origin = far:PointToWorldSpace(Vector3.new(math.cos(ang) * r, math.sin(ang) * r, depth))
				local hit = workspace:Raycast(origin, far:VectorToWorldSpace(Vector3.new(0, 0, -depth)), params)
				if hit then
					local z = far:PointToObjectSpace(hit.Position).Z
					best = if best then math.max(best, z) else z
				end
			end
			out[i + 1] = if best then best / radius else -1
		end
		return out
	end)
	-- (gone whatever happened in there)
	if copy then (copy :: Model):Destroy() end
	if not ok or type(res) ~= "table" then return nil end
	return res
end

-- a round shoulder on a flat face: for a wheel whose rays only found a flat face (a box for its
-- collision shape), the sidewall is taken to roll over into the tread on a curve
local function shoulder(rs: number, w: number): number
	local c = math.min(w * 0.8, 0.24)    -- the shoulder's radius, as a share of the wheel's
	local s0 = 1 - c
	if rs <= s0 then return w end
	local u = math.clamp((rs - s0) / c, 0, 1)
	return w - c + c * math.sqrt(1 - u * u)
end

function TyreSticker.surface(model: Model): (number, (number) -> number)
	local radius, zMax = measure(model)
	if radius <= 0 then return 0, function() return 0 end end
	local key = keyOf(model)
	local prof = profiles[key]
	if not prof then
		local got = sample(model, radius, zMax)
		local w = zMax / radius
		prof = {}
		local lo, hi = math.huge, -math.huge
		if got then
			for i, v in ipairs(got) do
				if v >= 0 then
					lo, hi = math.min(lo, v), math.max(hi, v)
				end
				prof[i] = v
			end
		end
		-- nothing found, or a flat face everywhere: the face with a rounded shoulder
		local flat = not got or hi < lo or hi - lo < 0.01
		for i = 1, SAMPLES do
			local rs = R_LO + (R_HI - R_LO) * (i - 1) / (SAMPLES - 1)
			if flat then
				prof[i] = shoulder(rs, w)
			elseif (prof[i] or -1) < 0 then
				-- past the tread (or a hole): carry the last one in
				prof[i] = if i > 1 then prof[i - 1] else w
			end
		end
		profiles[key] = prof
	end
	local p = prof :: { number }
	return radius, function(r: number): number
		local t = (r / radius - R_LO) / (R_HI - R_LO) * (SAMPLES - 1)
		local i = math.clamp(math.floor(t), 0, SAMPLES - 2)
		local f = math.clamp(t - i, 0, 1)
		return (p[i + 1] + (p[i + 2] - p[i + 1]) * f) * radius
	end
end

-- one plate: centred on `c` (pivot space), its right and up along `right` and `up`, `w` by `h`
local function plate(model: Model, pivot: CFrame, c: Vector3, right: Vector3, up: Vector3, w: number, h: number, side: number, texture: string, half: number?, index: number)
	local p = Instance.new("Part")
	p.Name = "Sticker"
	p.Size = Vector3.new(w, h, 0.04)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = pivot * CFrame.fromMatrix(c, right, up)
	local face = if side > 0 then Enum.NormalId.Back else Enum.NormalId.Front
	if half then
		-- half of the picture: a texture one whole sticker tall, slid so this half shows (half 0 the
		-- top, half 1 the bottom; with two halves the slide is the same either way it's measured)
		local t = Instance.new("Texture")
		t.Texture = texture
		t.Face = face
		t.StudsPerTileU = w
		t.StudsPerTileV = h * 2
		t.OffsetStudsU = 0
		t.OffsetStudsV = half * h
		t.Parent = p
	else
		local d = Instance.new("Decal")
		d.Texture = texture
		d.Face = face
		d.Parent = p
	end
	p:SetAttribute("StickerIndex", index)
	p:SetAttribute("StickerSide", side)
	p.Parent = model
end

function TyreSticker.apply(model: Model, stickers: { any }?)
	for _, c in ipairs(model:GetChildren()) do
		if c.Name == "Sticker" then c:Destroy() end
	end
	if not stickers or #stickers == 0 then return end
	local cat = TyreSticker.catalogue()
	local pivot = model:GetPivot()
	local radius, prof = TyreSticker.surface(model)
	if radius <= 0 then return end
	for index, s in ipairs(stickers) do
		local entry = cat.byId[s.id]
		if entry then
			local k = (s.size or 1) * radius / 4
			local w, h = entry.size.X * k, entry.size.Y * k
			local a = math.rad(s.a or 0)
			local centre2 = CFrame.Angles(0, 0, -a) * Vector3.new(0, (s.r or 0.82) * radius, 0)
			for _, side in ipairs(if s.mirror then { 1, -1 } else { 1 }) do
				local orient = CFrame.Angles(0, 0, -a) * CFrame.Angles(0, 0, -math.rad((s.rot or 0) * side))
				local right, up = orient.RightVector, orient.UpVector
				-- the rubber under a line across the sticker at `p2`: the highest of its middle and ends,
				-- so no corner sinks into the sidewall
				local function on(p2: Vector3): Vector3
					local z = 0
					for e = -1, 1 do
						local q = p2 + right * (w / 2) * e
						z = math.max(z, prof(Vector3.new(q.X, q.Y, 0).Magnitude))
					end
					return Vector3.new(p2.X, p2.Y, side * (z + LIFT))
				end
				local top = on(centre2 + up * (h / 2))
				local mid = on(centre2)
				local bot = on(centre2 - up * (h / 2))
				local bend = math.abs(mid.Z - (top.Z + bot.Z) / 2)
				if bend < FOLD then
					-- flat enough: one plate, tilted from its bottom edge to its top edge
					local u = (top - bot).Unit
					plate(model, pivot, (top + bot) / 2, right, u, w, (top - bot).Magnitude, side, entry.texture, nil, index)
				else
					-- folded along its middle, each half on its own stretch of rubber
					local u1 = (top - mid).Unit
					plate(model, pivot, (top + mid) / 2, right, u1, w, (top - mid).Magnitude, side, entry.texture, 0, index)
					local u2 = (mid - bot).Unit
					plate(model, pivot, (mid + bot) / 2, right, u2, w, (mid - bot).Magnitude, side, entry.texture, 1, index)
				end
			end
		end
	end
end

return TyreSticker
