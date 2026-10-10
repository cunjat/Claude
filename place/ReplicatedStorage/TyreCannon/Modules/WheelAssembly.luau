--!strict
-- TYRE CANNON :: WheelAssembly
-- One wheel for every place it shows up: your yard, the run, the workshop and
-- anyone watching. The rubber is Assets.Wheel.Tyre; the hub is built here;
-- stickers are wrapped onto the rubber as small generated meshes.
--
-- Model space: the axle is local Z and the wheel rolls about Z. Root is an
-- unrotated invisible part and the PrimaryPart, so
--   model:PivotTo(cf * CFrame.Angles(0, 0, -roll))
-- rolls it without any extra maths.
--
-- Hub sockets are Attachments on Root: Hub_Center, Hub_Face_L, Hub_Face_R,
-- Spoke_<n>_<L|R>, Gear_<n>. A future hub part is a model in
-- Assets.Wheel.Hub plus a row in WheelAssembly.HubParts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))
local Assets = Root:WaitForChild("Assets")

local WheelAssembly = {}

-- measured off Assets.Wheel.Tyre at its native size
local NATIVE_DIAMETER = 6
local NATIVE_INNER = 2.47
local NATIVE_WIDTH = 1.57

-- future hub parts, e.g.
-- { id = "gears", model = "GearSmall", socket = "Gear", count = 6, radius = 0.6, spin = -2.5 }
WheelAssembly.HubParts = {}

local AXLE = CFrame.Angles(0, math.rad(90), 0)

local function newPart(parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
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
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

local function dimsOf(model: Model)
	return {
		R = model:GetAttribute("Radius") :: number,
		Ri = model:GetAttribute("InnerRadius") :: number,
		W = model:GetAttribute("Width") :: number,
	}
end
WheelAssembly.dims = dimsOf

--==============================================================
-- the shape of the rubber
-- s runs across the rubber: 0 is the middle of the tread, +/- smax is the
-- inner lip of each sidewall. theta is the angle round the axle.
--==============================================================
local function profile(d)
	local rs = math.min(d.W * 0.28, (d.R - d.Ri) * 0.45)
	local a = d.W / 2 - rs
	local b = rs * math.pi / 2
	local c = math.max(0, (d.R - rs) - d.Ri)
	return rs, a, b, c, a + b + c
end

function WheelAssembly.surface(d, theta: number, s: number): (Vector3, Vector3, number)
	local rs, a, b, _, smax = profile(d)
	local sgn = s < 0 and -1 or 1
	local t = math.clamp(math.abs(s), 0, smax)
	local r, z, nr, nz
	if t <= a then
		r, z, nr, nz = d.R, t, 1, 0
	elseif t <= a + b then
		local phi = (t - a) / rs
		r = (d.R - rs) + rs * math.cos(phi)
		z = (d.W / 2 - rs) + rs * math.sin(phi)
		nr, nz = math.cos(phi), math.sin(phi)
	else
		r = (d.R - rs) - (t - a - b)
		z = d.W / 2
		nr, nz = 0, 1
	end
	local ct, st = math.cos(theta), math.sin(theta)
	return Vector3.new(r * ct, r * st, sgn * z), Vector3.new(nr * ct, nr * st, sgn * nz), r
end

function WheelAssembly.toSurface(d, p: Vector3): (number, number)
	local rs, a, b, c, smax = profile(d)
	local theta = math.atan2(p.Y, p.X)
	local r = math.sqrt(p.X * p.X + p.Y * p.Y)
	local sgn = p.Z < 0 and -1 or 1
	local z = math.abs(p.Z)
	local s
	if z <= a and r >= d.R - rs then
		s = z
	elseif r >= d.R - rs then
		local phi = math.atan2(z - (d.W / 2 - rs), r - (d.R - rs))
		s = a + rs * math.clamp(phi, 0, math.pi / 2)
	else
		s = a + b + math.clamp((d.R - rs) - r, 0, c)
	end
	return theta / math.pi, sgn * s / smax
end

-- exact hit test against the rubber (tread and both sidewall rings)
function WheelAssembly.raycast(model: Model, originW: Vector3, dirW: Vector3)
	local root = model.PrimaryPart
	if not root then return nil end
	local d = dimsOf(model)
	local o = root.CFrame:PointToObjectSpace(originW)
	local v = root.CFrame:VectorToObjectSpace(dirW)
	local best = math.huge
	for _, zs in ipairs({ d.W / 2, -d.W / 2 }) do
		if math.abs(v.Z) > 1e-6 then
			local t = (zs - o.Z) / v.Z
			if t > 0 and t < best then
				local q = o + v * t
				local r = math.sqrt(q.X * q.X + q.Y * q.Y)
				if r >= d.Ri and r <= d.R then best = t end
			end
		end
	end
	local A = v.X * v.X + v.Y * v.Y
	if A > 1e-9 then
		local B = 2 * (o.X * v.X + o.Y * v.Y)
		local C = o.X * o.X + o.Y * o.Y - d.R * d.R
		local disc = B * B - 4 * A * C
		if disc >= 0 then
			local t = (-B - math.sqrt(disc)) / (2 * A)
			if t > 0 and t < best then
				local q = o + v * t
				if math.abs(q.Z) <= d.W / 2 then best = t end
			end
		end
	end
	if best == math.huge then return nil end
	local q = o + v * best
	local u, sv = WheelAssembly.toSurface(d, q)
	return { u = u, v = sv, point = root.CFrame:PointToWorldSpace(q), distance = best }
end

--==============================================================
-- stickers
--==============================================================
local catalogue = nil
function WheelAssembly.stickers()
	if catalogue then return catalogue end
	local cat = { list = {}, byId = {} }
	local pack = Assets:FindFirstChild("Props") and Assets.Props:FindFirstChild("StickerPack")
	if pack then
		for _, d in ipairs(pack:GetDescendants()) do
			if d:IsA("BasePart") then
				local decal = d:FindFirstChildOfClass("Decal")
				if decal then
					local e = { id = d.Name, texture = decal.Texture, size = Vector2.new(d.Size.X, d.Size.Z), pack = d.Parent and d.Parent.Name or "" }
					table.insert(cat.list, e)
					cat.byId[e.id] = e
				end
			end
		end
	end
	table.sort(cat.list, function(a, b) return a.id < b.id end)
	catalogue = cat
	return cat
end

-- the rotation, in degrees, that stands a sticker at (u, v) upright for
-- someone whose screen "up" is upWorld
function WheelAssembly.uprightRotation(model: Model, u: number, v: number, upWorld: Vector3): number
	local root = model.PrimaryPart
	if not root then return 0 end
	local d = dimsOf(model)
	local _, _, _, _, smax = profile(d)
	local theta, s = u * math.pi, v * smax
	local p0, _, r = WheelAssembly.surface(d, theta, s)
	local eps = 0.02
	local tx = WheelAssembly.surface(d, theta + eps / math.max(r, 0.05), s) - p0
	local ty = WheelAssembly.surface(d, theta, s + (s > smax - eps and -eps or eps)) - p0
	if s > smax - eps then ty = -ty end
	if tx.Magnitude < 1e-6 or ty.Magnitude < 1e-6 then return 0 end
	tx, ty = tx.Unit, ty.Unit
	local up = root.CFrame:VectorToObjectSpace(upWorld)
	local a, b = up:Dot(tx), up:Dot(ty)
	if math.abs(a) + math.abs(b) < 1e-4 then return 0 end
	return math.deg(math.atan2(-a, b))
end

-- every EditableMesh a sticker owns, so none outlive their MeshPart. Roblox
-- caps how much EditableMesh memory a client may hold; a leak shows up as
-- "reaching memory budget limits" and stickers silently stop building.
local liveMeshes: { [any]: { part: MeshPart, born: number } } = {}

local function trackMesh(mesh: any, mp: MeshPart)
	liveMeshes[mesh] = { part = mp, born = os.clock() }
	mp.Destroying:Connect(function()
		if liveMeshes[mesh] then
			liveMeshes[mesh] = nil
			pcall(function() mesh:Destroy() end)
		end
	end)
end

-- frees the mesh of any sticker part that left the game without being destroyed
local function sweepMeshes(hard: boolean?)
	local now = os.clock()
	local wait = hard and 0.5 or 3
	for mesh, info in pairs(liveMeshes) do
		if now - info.born > wait and not info.part:IsDescendantOf(game) then
			liveMeshes[mesh] = nil
			pcall(function() mesh:Destroy() end)
		end
	end
end

function WheelAssembly.liveStickerMeshes(): number
	local n = 0
	for _ in pairs(liveMeshes) do n += 1 end
	return n
end

local warnedMesh = false

-- builds one sticker as a mesh wrapped onto the rubber. Yields.
-- The real rubber sits a little inside the smooth wrap shape. Measured by raycast
-- against the carcass, in native tyre units, by fraction of the way from the
-- tread centre (0) to the inner lip (1). Tread values follow the tops of the tread
-- blocks, so a sticker bridges the grooves instead of sinking into the blocks.
local SURFACE_OFFSET = {
	{ 0.00, -0.013 }, { 0.45, -0.013 }, { 0.50, -0.020 }, { 0.56, -0.012 },
	{ 0.62, -0.004 }, { 0.68, -0.010 }, { 0.73, -0.030 }, { 1.00, -0.0324 },
}
local function surfaceOffset(frac: number): number
	frac = math.clamp(math.abs(frac), 0, 1)
	for i = 2, #SURFACE_OFFSET do
		local lo, hi = SURFACE_OFFSET[i - 1], SURFACE_OFFSET[i]
		if frac <= hi[1] then
			local t = (frac - lo[1]) / math.max(hi[1] - lo[1], 1e-6)
			return lo[2] + (hi[2] - lo[2]) * t
		end
	end
	return SURFACE_OFFSET[#SURFACE_OFFSET][2]
end

local function stickerBasis(d, entry, s, k: number)
	local rs, a, b, _, smax = profile(d)
	local scale = s.scale or 1
	local rot = math.rad(s.rot or 0)
	local w = entry.size.X * k * 0.75 * scale
	local h = entry.size.Y * k * 0.75 * scale
	-- The grid's straight edges cut inside the curve of the shoulder. On a big sticker
	-- that cut is deeper than the lift and the rubber pokes through, so the sticker is
	-- lifted over the shoulder by the sag (an edge can run corner to corner, hence 1.42).
	local cell = math.max(w, h) / Config.Stickers.Grid
	local sag = rs * (1 - math.cos(math.min(cell * 1.42 / (2 * rs), math.pi / 3)))
	return {
		smax = smax,
		w = w,
		h = h,
		cr = math.cos(rot),
		sr = math.sin(rot),
		theta0 = (s.u or 0) * math.pi,
		s0 = (s.v or 0) * smax,
		lift = Config.Stickers.Lift * k,
		k = k,
		cell = cell,
		sag = sag,
		shoulderIn = a,
		shoulderOut = a + b,
	}
end

-- sticker-local (x, y) to a point on the rubber, in the wheel's own space
local function stickerPoint(d, bs, x: number, y: number, extraLift: number): (Vector3, Vector3)
	local xr = x * bs.cr - y * bs.sr
	local yr = x * bs.sr + y * bs.cr
	local sv = math.clamp(bs.s0 + yr, -bs.smax, bs.smax)
	local _, _, rHere = WheelAssembly.surface(d, bs.theta0, sv)
	local pos, nrm = WheelAssembly.surface(d, bs.theta0 + xr / math.max(rHere, 0.05), sv)
	-- the full sag across the shoulder, easing to nothing a grid cell either side of it
	local t = math.abs(sv)
	local band = math.clamp(math.min(t - (bs.shoulderIn - bs.cell), (bs.shoulderOut + bs.cell) - t) / math.max(bs.cell, 1e-4), 0, 1)
	return pos + nrm * (surfaceOffset(sv / bs.smax) * bs.k + bs.lift + bs.sag * band + extraLift), nrm
end

-- Keeps a sticker on the rubber. Past the inner lip there's only rim, and a sticker
-- that reached over it folded up along the lip. One that gets there slides back
-- toward the tread, and one taller than the rubber is wide shrinks to fit.
-- Changes s in place and returns true if it had to.
function WheelAssembly.fitSticker(model: Model, s): boolean
	local entry = WheelAssembly.stickers().byId[s.id]
	if not (entry and model.PrimaryPart) then return false end
	local d = dimsOf(model)
	local k = d.R / (NATIVE_DIAMETER / 2)
	local _, _, _, _, smax = profile(d)
	local room = smax * 0.97
	local rot = math.rad(s.rot or 0)
	local function reach(scale: number): number
		local w = entry.size.X * k * 0.75 * scale
		local h = entry.size.Y * k * 0.75 * scale
		return math.abs(w / 2 * math.sin(rot)) + math.abs(h / 2 * math.cos(rot))
	end
	local changed = false
	local scale = s.scale or 1
	local ext = reach(scale)
	if ext > room then
		scale = math.max(Config.Stickers.MinScale, math.floor(scale * room / ext * 100) / 100)
		s.scale = scale
		ext = reach(scale)
		changed = true
	end
	local limit = math.max(0, room - ext)
	local s0 = (s.v or 0) * smax
	if math.abs(s0) > limit + 1e-6 then
		s.v = math.clamp(s0, -limit, limit) / smax
		changed = true
	end
	return changed
end

local function stickerGrid(d, entry, s, k: number)
	local bs = stickerBasis(d, entry, s, k)
	local G = Config.Stickers.Grid
	local pts, nrms = {}, {}
	for j = 0, G do
		for i = 0, G do
			local p, n = stickerPoint(d, bs, (i / G - 0.5) * bs.w, (j / G - 0.5) * bs.h, 0)
			pts[#pts + 1] = p
			nrms[#nrms + 1] = n
		end
	end
	return pts, nrms, G
end

-- Every sticker mesh is pinned to a box the size of the whole wheel by two
-- zero-area triangles, so its part never rescales: after the first build, moving,
-- turning, resizing or re-texturing a sticker just rewrites its vertices.
local stickerMesh: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any

local function pinBounds(mesh: any, d)
	local bx, bz = d.R + 1, d.W / 2 + 1
	for _, c in ipairs({ Vector3.new(-bx, -bx, -bz), Vector3.new(bx, bx, bz) }) do
		mesh:AddTriangle(mesh:AddVertex(c), mesh:AddVertex(c + Vector3.new(0.001, 0, 0)), mesh:AddVertex(c + Vector3.new(0, 0.001, 0)))
	end
end

local function meshPartFor(mesh: any): MeshPart
	local okOpts, made = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(mesh), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
		})
	end)
	return okOpts and made or AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
end

local function newEditableMesh(): any
	sweepMeshes()
	local mesh = AssetService:CreateEditableMesh()
	if not mesh then
		sweepMeshes(true)
		mesh = AssetService:CreateEditableMesh()
	end
	if not mesh then error("EditableMesh memory budget is full") end
	return mesh
end

-- foil stickers get a crinkled metal finish and a mirror sheen; the rest stay matte
function WheelAssembly.finishSticker(mp: MeshPart, id: string)
	local foil = Config.FoilStickers and Config.FoilStickers[id]
	mp.Material = foil and Enum.Material.Foil or Enum.Material.SmoothPlastic
	mp.Reflectance = foil and 0.32 or 0
end

-- builds one sticker as a mesh wrapped onto the rubber. Yields (once per sticker).
function WheelAssembly.buildSticker(model: Model, s): MeshPart?
	local entry = WheelAssembly.stickers().byId[s.id]
	local root = model.PrimaryPart
	if not entry or not root then return nil end
	local d = dimsOf(model)
	local k = d.R / (NATIVE_DIAMETER / 2)
	local pts, nrms, G = stickerGrid(d, entry, s, k)
	local ok, result = pcall(function()
		local mesh = newEditableMesh()
		local built, info = pcall(function()
			local vid, uid, nid = {}, {}, {}
			for n, p in ipairs(pts) do
				vid[n] = mesh:AddVertex(p)
				nid[n] = mesh:AddNormal(nrms[n])
			end
			for j = 0, G do
				for i = 0, G do
					uid[j * (G + 1) + i + 1] = mesh:AddUV(Vector2.new(i / G, 1 - j / G))
				end
			end
			local function tri(ia: number, ib: number, ic: number)
				local f = mesh:AddTriangle(vid[ia], vid[ib], vid[ic])
				mesh:SetFaceUVs(f, { uid[ia], uid[ib], uid[ic] })
				mesh:SetFaceNormals(f, { nid[ia], nid[ib], nid[ic] })
			end
			for j = 0, G - 1 do
				for i = 0, G - 1 do
					local p1 = j * (G + 1) + i + 1
					local p2 = p1 + 1
					local p3 = p1 + G + 1
					local p4 = p3 + 1
					-- both windings, so it shows whichever way the engine culls
					tri(p1, p2, p3)
					tri(p2, p4, p3)
					tri(p1, p3, p2)
					tri(p2, p3, p4)
				end
			end
			pinBounds(mesh, d)
			local mp = meshPartFor(mesh)
			mp.TextureContent = Content.fromUri(entry.texture)
			return { part = mp, vid = vid, nid = nid }
		end)
		if not built or not info then
			pcall(function() mesh:Destroy() end)
			error(info)
		end
		trackMesh(mesh, info.part)
		stickerMesh[info.part] = { mesh = mesh, vid = info.vid, nid = info.nid }
		return info.part
	end)
	if not ok or not result then
		if not warnedMesh then
			warnedMesh = true
			warn("[TyreCannon] sticker meshes unavailable here: " .. tostring(result))
		end
		return nil
	end
	local mp = result :: MeshPart
	mp.Name = "Sticker_" .. s.id
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.CastShadow = false
	-- a hair of transparency puts the sticker in the render pass that honours the image's alpha
	mp.Transparency = 0.02
	mp:SetAttribute("StickerId", s.id)
	WheelAssembly.finishSticker(mp, s.id)
	if not root.Parent then
		mp:Destroy()
		return nil
	end
	mp.CFrame = root.CFrame
	return mp
end

-- moves, turns, resizes or re-textures a built sticker in place: no rebuild, no wait
function WheelAssembly.updateSticker(model: Model, mp: MeshPart, s): boolean
	local data = stickerMesh[mp]
	local entry = WheelAssembly.stickers().byId[s.id]
	local root = model.PrimaryPart
	if not (data and data.vid and entry and root) then return false end
	local d = dimsOf(model)
	local k = d.R / (NATIVE_DIAMETER / 2)
	local pts, nrms = stickerGrid(d, entry, s, k)
	local ok = pcall(function()
		for n, p in ipairs(pts) do
			data.mesh:SetPosition(data.vid[n], p)
			data.mesh:SetNormal(data.nid[n], nrms[n])
		end
	end)
	if not ok then return false end
	if mp:GetAttribute("StickerId") ~= s.id then
		mp.TextureContent = Content.fromUri(entry.texture)
		mp:SetAttribute("StickerId", s.id)
		WheelAssembly.finishSticker(mp, s.id)
	end
	mp.CFrame = root.CFrame
	return true
end

-- a thin frame bent over the rubber around a sticker, to show which one is selected
local function framePerimeter(G: number): { Vector2 }
	local list = {}
	for i = 0, G - 1 do table.insert(list, Vector2.new(i / G - 0.5, -0.5)) end
	for j = 0, G - 1 do table.insert(list, Vector2.new(0.5, j / G - 0.5)) end
	for i = G, 1, -1 do table.insert(list, Vector2.new(i / G - 0.5, 0.5)) end
	for j = G, 1, -1 do table.insert(list, Vector2.new(-0.5, j / G - 0.5)) end
	return list
end

local function frameRing(d, entry, s, k: number)
	local bs = stickerBasis(d, entry, s, k)
	local e = 0.08 * k
	local inner, outer, nrms = {}, {}, {}
	for _, f in ipairs(framePerimeter(Config.Stickers.Grid)) do
		local pin, n = stickerPoint(d, bs, f.X * bs.w, f.Y * bs.h, 0.004 * k)
		local pout = stickerPoint(d, bs, f.X * (bs.w + 2 * e), f.Y * (bs.h + 2 * e), 0.004 * k)
		table.insert(inner, pin)
		table.insert(outer, pout)
		table.insert(nrms, n)
	end
	return inner, outer, nrms
end

function WheelAssembly.buildStickerFrame(model: Model): MeshPart?
	local root = model.PrimaryPart
	local entry = WheelAssembly.stickers().list[1]
	if not (root and entry) then return nil end
	local d = dimsOf(model)
	local k = d.R / (NATIVE_DIAMETER / 2)
	local inner, outer, nrms = frameRing(d, entry, { id = entry.id, u = 0, v = 0, rot = 0, scale = 1 }, k)
	local P = #inner
	local ok, result = pcall(function()
		local mesh = newEditableMesh()
		local built, info = pcall(function()
			local vi, vo, ni = {}, {}, {}
			for n = 1, P do
				vi[n] = mesh:AddVertex(inner[n])
				vo[n] = mesh:AddVertex(outer[n])
				ni[n] = mesh:AddNormal(nrms[n])
			end
			local function tri(p1: number, p2: number, p3: number, n1: number, n2: number, n3: number)
				local f = mesh:AddTriangle(p1, p2, p3)
				mesh:SetFaceNormals(f, { n1, n2, n3 })
			end
			for n = 1, P do
				local q = n % P + 1
				tri(vi[n], vo[n], vi[q], ni[n], ni[n], ni[q])
				tri(vi[q], vo[n], vo[q], ni[q], ni[n], ni[q])
				tri(vi[n], vi[q], vo[n], ni[n], ni[q], ni[n])
				tri(vi[q], vo[q], vo[n], ni[q], ni[q], ni[n])
			end
			pinBounds(mesh, d)
			return { part = meshPartFor(mesh), vi = vi, vo = vo, ni = ni }
		end)
		if not built or not info then
			pcall(function() mesh:Destroy() end)
			error(info)
		end
		trackMesh(mesh, info.part)
		stickerMesh[info.part] = { mesh = mesh, vi = info.vi, vo = info.vo, ni = info.ni }
		return info.part
	end)
	if not ok or not result then return nil end
	local mp = result :: MeshPart
	mp.Name = "StickerFrame"
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.CastShadow = false
	mp.Material = Enum.Material.SmoothPlastic
	mp.Transparency = 1
	mp.CFrame = root.CFrame
	return mp
end

function WheelAssembly.updateStickerFrame(model: Model, mp: MeshPart, s): boolean
	local data = stickerMesh[mp]
	local entry = WheelAssembly.stickers().byId[s.id]
	local root = model.PrimaryPart
	if not (data and data.vi and entry and root) then return false end
	local d = dimsOf(model)
	local k = d.R / (NATIVE_DIAMETER / 2)
	local inner, outer, nrms = frameRing(d, entry, s, k)
	local ok = pcall(function()
		for n = 1, #inner do
			data.mesh:SetPosition(data.vi[n], inner[n])
			data.mesh:SetPosition(data.vo[n], outer[n])
			data.mesh:SetNormal(data.ni[n], nrms[n])
		end
	end)
	if not ok then return false end
	mp.CFrame = root.CFrame
	return true
end

-- slides a built sticker round the tread without rebuilding it: the rubber is
-- the same shape all the way round, so a change of u is just a turn about the axle
function WheelAssembly.moveSticker(model: Model, mp: MeshPart, u: number): boolean
	local root = model.PrimaryPart
	local centre = mp:GetAttribute("BuiltCentre")
	local builtU = mp:GetAttribute("BuiltU")
	if not (root and typeof(centre) == "Vector3" and type(builtU) == "number") then return false end
	mp.CFrame = root.CFrame * CFrame.Angles(0, 0, (u - builtU) * math.pi) * CFrame.new(centre)
	return true
end

function WheelAssembly.setStickers(model: Model, list)
	local folder = model:FindFirstChild("Stickers")
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "Stickers"
	folder.Parent = model
	local token = {}
	model:SetAttribute("StickerToken", tostring(token))
	for _, s in ipairs(list or {}) do
		task.spawn(function()
			local mp = WheelAssembly.buildSticker(model, s)
			if not mp then return end
			if model:GetAttribute("StickerToken") ~= tostring(token) or not folder.Parent then
				mp:Destroy()
				return
			end
			mp.CFrame = model.PrimaryPart.CFrame * model.PrimaryPart.CFrame:ToObjectSpace(mp.CFrame)
			mp.Parent = folder
		end)
	end
end

--==============================================================
-- skin and hub
--==============================================================
function WheelAssembly.setSkin(model: Model, skinId: string?)
	local skin = Config.SkinsById[skinId or "stock"] or Config.SkinsById.stock
	local c = model:FindFirstChild("Carcass") :: BasePart?
	if c then
		c.Color = skin.tyre
		c.Material = skin.material
		c.Reflectance = skin.reflect or 0
	end
	model:SetAttribute("Skin", skin.id)
end

local function socket(root: BasePart, name: string, cf: CFrame)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = root.CFrame:ToObjectSpace(cf)
	a.Parent = root
	return a
end

function WheelAssembly.setRim(model: Model, rimId: string?, detail: string?)
	local rim = Config.RimsById[rimId or "steel"] or Config.RimsById.steel
	local root = model.PrimaryPart :: BasePart
	local d = dimsOf(model)
	local rootCF = root.CFrame
	local old = model:FindFirstChild("Hub")
	if old then old:Destroy() end
	for _, a in ipairs(root:GetChildren()) do
		if a:IsA("Attachment") then a:Destroy() end
	end

	local hub = Instance.new("Model")
	hub.Name = "Hub"
	hub.Parent = model
	local Ri, W = d.Ri, d.W
	local faceMat = rim.neon and Enum.Material.Neon or Enum.Material.Metal
	local low = detail == "low"

	-- An open rim: a ring of lip segments from the tyre's bead in to the face, the
	-- spokes (or a solid face) set back inside it, a dark back wall just behind them
	-- so the gaps read as depth, and a hub plate carrying the nuts and cap. (This used
	-- to be solid discs, which hid the spokes and buried the nuts.)
	local faceR = Ri * 0.86
	local dark = rim.barrel:Lerp(Color3.new(0, 0, 0), 0.62)
	local plateColor = rim.face:Lerp(Color3.new(0, 0, 0), 0.25)
	local plateLum = 0.299 * plateColor.R + 0.587 * plateColor.G + 0.114 * plateColor.B
	local nutColor = plateLum > 0.42 and Color3.fromRGB(38, 40, 44) or Color3.fromRGB(214, 218, 224)
	local spokeAsset = Assets.Wheel:FindFirstChild("Spoke") :: MeshPart?
	local segments = low and 10 or 18
	for _, side in ipairs({ -1, 1 }) do
		local tag = side < 0 and "L" or "R"
		local faceZ = W * ((rim.style == "dish") and 0.16 or 0.38)

		-- neon rims glow from their Neon lip only; no light of their own
		newPart(hub, "Barrel", Vector3.new(W * 0.04, Ri * 1.98, Ri * 1.98),
			rootCF * CFrame.new(0, 0, side * (faceZ - W * 0.09)) * AXLE, dark, Enum.Material.Metal, Enum.PartType.Cylinder)

		local rIn, rOut = Ri * 0.84, Ri * 0.995
		local zFront, zBack = W * 0.51, faceZ - W * 0.07
		local depth = zFront - zBack
		local segLen = 2 * rOut * math.tan(math.pi / segments) * 1.04
		for n = 1, segments do
			local ang = (n / segments) * math.pi * 2
			local seg = newPart(hub, "Lip", Vector3.new(segLen, rOut - rIn, depth),
				rootCF * CFrame.Angles(0, 0, ang) * CFrame.new(0, (rIn + rOut) / 2, side * (zBack + depth / 2)),
				rim.glow or rim.barrel, faceMat)
			seg.Reflectance = rim.reflect or 0
		end

		if rim.style == "solid" then
			newPart(hub, "Face", Vector3.new(W * 0.06, faceR * 2, faceR * 2),
				rootCF * CFrame.new(0, 0, side * faceZ) * AXLE, rim.face, Enum.Material.Metal, Enum.PartType.Cylinder).Reflectance = rim.reflect or 0
		else
			local count = rim.spokes or 6
			if rim.style == "mesh" then count *= 2 end
			if low then count = math.min(count, 5) end
			local thick = (rim.style == "mesh") and 0.08 or 0.16
			local len = faceR * 0.84
			for i = 1, count do
				local ang = (i / count) * math.pi * 2
				local cf = rootCF * CFrame.new(0, 0, side * faceZ) * CFrame.Angles(0, 0, ang) * CFrame.new(0, Ri * 0.16 + len / 2, 0)
				local spoke: BasePart
				if spokeAsset then
					local sp = spokeAsset:Clone()
					sp.Size = Vector3.new(Ri * thick, len, W * 0.12)
					sp.CFrame = cf
					sp.Anchored = true
					sp.CanCollide = false
					sp.CanQuery = false
					sp.CanTouch = false
					sp.CastShadow = false
					sp.Parent = hub
					spoke = sp
				else
					spoke = newPart(hub, "Spoke", Vector3.new(Ri * thick, len, W * 0.12), cf, rim.face, Enum.Material.Metal)
				end
				spoke.Name = "Spoke"
				spoke.Color = rim.face
				spoke.Material = Enum.Material.Metal
				spoke.Reflectance = rim.reflect or 0
				socket(root, ("Spoke_%d_%s"):format(i, tag), cf)
			end
		end

		-- the hub plate, nuts and cap sit on the face, however deep the face is
		local plateZ = faceZ + W * 0.06
		local nutZ = plateZ + W * 0.07
		newPart(hub, "Plate", Vector3.new(W * 0.08, Ri * 0.84, Ri * 0.84),
			rootCF * CFrame.new(0, 0, side * plateZ) * AXLE, plateColor, Enum.Material.Metal, Enum.PartType.Cylinder).Reflectance = rim.reflect or 0
		newPart(hub, "Cap", Vector3.new(W * 0.14, Ri * 0.4, Ri * 0.4),
			rootCF * CFrame.new(0, 0, side * nutZ) * AXLE, rim.face:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal, Enum.PartType.Cylinder)
		if not low then
			for n = 1, 5 do
				local ang = n / 5 * math.pi * 2
				newPart(hub, "Nut", Vector3.new(W * 0.14, Ri * 0.12, Ri * 0.12),
					rootCF * CFrame.Angles(0, 0, ang) * CFrame.new(Ri * 0.3, 0, side * nutZ) * AXLE,
					nutColor, Enum.Material.Metal, Enum.PartType.Cylinder)
			end
		end
		socket(root, "Hub_Face_" .. tag, rootCF * CFrame.new(0, 0, side * W * 0.5))
	end
	socket(root, "Hub_Center", rootCF)
	for n = 1, 6 do
		local ang = n / 6 * math.pi * 2
		socket(root, "Gear_" .. n, rootCF * CFrame.Angles(0, 0, ang) * CFrame.new(0, Ri * 0.6, W * 0.4))
	end

	-- future hub parts slot into the sockets above
	local hubAssets = Assets.Wheel:FindFirstChild("Hub")
	for _, def in ipairs(WheelAssembly.HubParts) do
		local tpl = hubAssets and hubAssets:FindFirstChild(def.model)
		if tpl then
			for n = 1, def.count or 1 do
				local att = root:FindFirstChild((def.socket or "Hub_Center") .. ((def.count or 1) > 1 and ("_" .. n) or ""))
				if att and att:IsA("Attachment") then
					local c = tpl:Clone()
					if c:IsA("Model") then c:PivotTo(att.WorldCFrame) elseif c:IsA("BasePart") then c.CFrame = att.WorldCFrame end
					c.Parent = hub
				end
			end
		end
	end
	model:SetAttribute("Rim", rim.id)
end

--==============================================================
-- build
--==============================================================
-- opts = { diameter, skin, rim, stickers, detail = "full" | "low", name }
function WheelAssembly.build(parent: Instance?, opts): Model
	opts = opts or {}
	local diameter = opts.diameter or 12
	local k = diameter / NATIVE_DIAMETER

	local model = Instance.new("Model")
	model.Name = opts.name or "Wheel"
	local root = newPart(model, "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	root.Transparency = 1
	model.PrimaryPart = root

	model:SetAttribute("Radius", diameter / 2)
	model:SetAttribute("InnerRadius", NATIVE_INNER * k)
	model:SetAttribute("Width", NATIVE_WIDTH * k)
	model:SetAttribute("Diameter", diameter)

	local tpl = Assets.Wheel:FindFirstChild("Tyre")
	local srcPart = tpl and (tpl:FindFirstChild("Carcass") or tpl:FindFirstChildWhichIsA("BasePart"))
	local carcass: BasePart
	if srcPart then
		carcass = (srcPart :: BasePart):Clone()
		carcass.Size = (srcPart :: BasePart).Size * k
	else
		carcass = newPart(nil, "Carcass", Vector3.new(NATIVE_WIDTH * k, diameter, diameter), CFrame.new(), Color3.fromRGB(26, 26, 28), Enum.Material.Pebble, Enum.PartType.Cylinder)
	end
	carcass.Name = "Carcass"
	carcass.CFrame = AXLE
	carcass.Anchored = true
	carcass.CanCollide = false
	carcass.CanQuery = false
	carcass.CanTouch = false
	carcass.CastShadow = true
	carcass.Parent = model

	WheelAssembly.setSkin(model, opts.skin)
	WheelAssembly.setRim(model, opts.rim, opts.detail)
	model.Parent = parent
	if opts.stickers and #opts.stickers > 0 and opts.detail ~= "low" then
		WheelAssembly.setStickers(model, opts.stickers)
	end
	return model
end

return WheelAssembly
