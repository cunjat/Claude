--!strict
-- TYRE CANNON :: TyreSticker
-- Stickers on a tyre's sidewall: thin clear plates with a decal on them, laid on the rubber face and
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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WheelAssembly = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("WheelAssembly"))

local TyreSticker = {}

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

function TyreSticker.apply(model: Model, stickers: { any }?)
	for _, c in ipairs(model:GetChildren()) do
		if c.Name == "Sticker" then c:Destroy() end
	end
	if not stickers or #stickers == 0 then return end
	local cat = TyreSticker.catalogue()
	local pivot = model:GetPivot()
	local radius, zMax = measure(model)
	if radius <= 0 then return end
	for _, s in ipairs(stickers) do
		local entry = cat.byId[s.id]
		if entry then
			local k = (s.size or 1) * radius / 4
			local w, h = entry.size.X * k, entry.size.Y * k
			for _, side in ipairs(if s.mirror then { 1, -1 } else { 1 }) do
				local p = Instance.new("Part")
				p.Name = "Sticker"
				p.Size = Vector3.new(w, h, 0.04)
				p.Transparency = 1
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.CFrame = pivot * CFrame.Angles(0, 0, -math.rad(s.a or 0)) * CFrame.new(0, (s.r or 0.82) * radius, side * (zMax + 0.03))
					* CFrame.Angles(0, 0, -math.rad((s.rot or 0) * side))
				local d = Instance.new("Decal")
				d.Texture = entry.texture
				d.Face = if side > 0 then Enum.NormalId.Back else Enum.NormalId.Front
				d.Parent = p
				p.Parent = model
			end
		end
	end
end

return TyreSticker
