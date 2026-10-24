--!strict
-- TrophyPillar: the lobby's centrepiece (the owner's pick on 2026-10-15, "chrome and crown").
-- A black-and-gold pillar on stepped plinths in the middle of the plaza, with a leaderboard on each of its four
-- sides. On top, a giant chrome tyre stands in a gold laurel wreath, wearing a crown, on a turntable that the
-- clients turn (StarterPlayerScripts.TrophySpin). The server builds it at boot so everyone sees the same boards.
-- It closes round the old statue plinth without touching it (nothing in Workspace is moved or deleted).
-- workspace:SetAttribute("TrophyPillar", false) before the server starts brings back the old RunBoards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage.TyreCannon.Modules.Game)

local TrophyPillar = {}

local CENTRE = Vector3.new(-6000, 2, 6000) -- the top of the plaza floor, in the middle
local BLACK = Color3.fromRGB(24, 24, 28)
local GOLD = Color3.fromRGB(240, 186, 52)
local CHROME = Color3.fromRGB(186, 192, 202)
local WHITE = Color3.fromRGB(244, 242, 236)
local FONT_HEAVY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)
local FONT_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

-- one board per side, clockwise from the spawn side (+Z)
TrophyPillar.BOARDS = {
	{ key = "distance", title = "LONGEST RUN", accent = Color3.fromRGB(250, 196, 40) },
	{ key = "week", title = "THIS WEEK", accent = Color3.fromRGB(160, 108, 240) },
	{ key = "credits", title = "RICHEST", accent = Color3.fromRGB(80, 196, 96) },
	{ key = "prestige", title = "TOP PRESTIGE", accent = Color3.fromRGB(240, 92, 158) },
}
local ROWS = 10
local MEDAL = { Color3.fromRGB(250, 196, 40), Color3.fromRGB(200, 206, 216), Color3.fromRGB(214, 138, 82) }

-- heights (studs above the plaza floor's top)
local STEPS = { { 46, 1.4 }, { 40, 1.4 }, { 34, 1.4 } }
local BASE_H, BAND_H, CORE_W, CORE_H, CAP_H = 3, 2.4, 26, 32, 2.4
local TYRE_SCALE = 4

function TrophyPillar.enabled(): boolean
	return workspace:GetAttribute("TrophyPillar") ~= false
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, refl: number?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then p.Shape = shape end
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = refl or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function gold(parent: Instance, name: string, size: Vector3, cf: CFrame, shape: Enum.PartType?): Part
	return part(parent, name, size, cf, GOLD, 0.12, shape)
end
local function black(parent: Instance, name: string, size: Vector3, cf: CFrame): Part
	return part(parent, name, size, cf, BLACK, 0.04)
end
local function at(y: number): CFrame
	return CFrame.new(CENTRE + Vector3.new(0, y, 0))
end

-- a square slab with a gold lip round its top edge
local function step(parent: Instance, w: number, y0: number, h: number)
	black(parent, "Step", Vector3.new(w, h, w), at(y0 + h / 2))
	for i = 0, 3 do
		gold(parent, "StepLip", Vector3.new(w + 0.2, 0.35, 0.7), at(y0 + h - 0.1) * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0, w / 2 - 0.3))
	end
end

-- a chequered-flag band: two rows of black and white squares painted on all four sides, gold rules at the edges
local function chequer(parent: Instance, w: number, y0: number, h: number)
	local band = black(parent, "Chequer", Vector3.new(w, h, w), at(y0 + h / 2))
	local cols = math.floor(w / (h / 2) + 0.5)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 20
		sg.LightInfluence = 1
		for r = 0, 1 do
			for c = 0, cols - 1 do
				if (r + c) % 2 == 0 then
					local f = Instance.new("Frame")
					f.BorderSizePixel = 0
					f.BackgroundColor3 = WHITE
					f.Position = UDim2.fromScale(c / cols, r / 2)
					f.Size = UDim2.fromScale(1 / cols, 1 / 2)
					f.Parent = sg
				end
			end
		end
		sg.Parent = band
	end
	gold(parent, "ChequerRule", Vector3.new(w + 0.4, 0.3, w + 0.4), at(y0 + 0.15))
	gold(parent, "ChequerRule", Vector3.new(w + 0.4, 0.3, w + 0.4), at(y0 + h - 0.15))
end

-- one leaderboard: header bar in the board's colour, then ten rows (medal, avatar, name, value)
local function board(parent: Instance, def: any, rot: CFrame, y: number)
	local base = at(y) * rot
	local half = CORE_W / 2
	gold(parent, "BoardFrame", Vector3.new(20, 26, 0.6), base * CFrame.new(0, 0, half + 0.2))
	local p = part(parent, "Board_" .. def.key, Vector3.new(18.4, 24.4, 0.5), base * CFrame.new(0, 0, half + 0.55), Color3.fromRGB(18, 18, 22))
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Board"
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.Brightness = 1
	sg.MaxDistance = 400
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BorderSizePixel = 0
	head.BackgroundColor3 = def.accent
	head.Size = UDim2.new(1, 0, 0, 124)
	head.Parent = sg
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 1)
	title.FontFace = FONT_HEAVY
	title.Text = def.title
	title.TextSize = 80
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Parent = head
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(14, 13, 12)
	stroke.Parent = title
	for i = 1, ROWS do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.BorderSizePixel = 0
		row.BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(30, 30, 36) or Color3.fromRGB(22, 22, 27)
		row.Position = UDim2.new(0, 0, 0, 132 + (i - 1) * 84)
		row.Size = UDim2.new(1, 0, 0, 84)
		row.Parent = sg
		local rank = Instance.new("TextLabel")
		rank.Name = "Rank"
		rank.BackgroundColor3 = MEDAL[i] or Color3.fromRGB(56, 56, 64)
		rank.BorderSizePixel = 0
		rank.Position = UDim2.new(0, 14, 0.5, -28)
		rank.Size = UDim2.new(0, 56, 0, 56)
		rank.FontFace = FONT_HEAVY
		rank.Text = tostring(i)
		rank.TextSize = 38
		rank.TextColor3 = i <= 3 and Color3.fromRGB(24, 22, 20) or Color3.fromRGB(230, 228, 222)
		rank.Parent = row
		Instance.new("UICorner", rank).CornerRadius = UDim.new(0.5, 0)
		local face = Instance.new("ImageLabel")
		face.Name = "Avatar"
		face.BackgroundColor3 = Color3.fromRGB(48, 48, 56)
		face.BorderSizePixel = 0
		face.Position = UDim2.new(0, 84, 0.5, -32)
		face.Size = UDim2.new(0, 64, 0, 64)
		face.Visible = false
		face.Parent = row
		Instance.new("UICorner", face).CornerRadius = UDim.new(0.25, 0)
		local name = Instance.new("TextLabel")
		name.Name = "PlayerName"
		name.BackgroundTransparency = 1
		name.Position = UDim2.new(0, 162, 0, 0)
		name.Size = UDim2.new(1, -372, 1, 0)
		name.FontFace = FONT_BOLD
		name.TextSize = 40
		name.TextColor3 = Color3.fromRGB(240, 236, 228)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = i == 1 and "Be the first!" or ""
		name.Parent = row
		local value = Instance.new("TextLabel")
		value.Name = "Value"
		value.BackgroundTransparency = 1
		value.Position = UDim2.new(1, -206, 0, 0)
		value.Size = UDim2.new(0, 190, 1, 0)
		value.FontFace = FONT_HEAVY
		value.TextSize = 40
		value.TextColor3 = def.accent
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.Text = ""
		value.Parent = row
	end
	sg.Parent = p
end

-- a rounded gold leaf (an ellipsoid)
local function leaf(parent: Instance, size: Vector3, cf: CFrame)
	local p = gold(parent, "Leaf", size, cf)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- the laurel wreath: two arcs of gold leaves on a stem round the tyre, in the tyre's plane (local Y-Z)
local function laurels(parent: Instance, tc: Vector3, radius: number)
	local R = radius + 3.6
	for _, s in ipairs({ -1, 1 }) do
		for deg = 38, 150, 10 do
			local a = math.rad(deg)
			local radial = Vector3.new(0, -math.cos(a), s * math.sin(a))
			local tangent = Vector3.new(0, math.sin(a), s * math.cos(a))
			for _, side in ipairs({ -1, 1 }) do
				local b = math.rad(38) * side
				local dir = (tangent * math.cos(b) + radial * math.sin(b)).Unit
				local pos = tc + radial * (R + side * 1.5) + dir * 1.6
				leaf(parent, Vector3.new(1.1, 4.6, 2.2), CFrame.fromMatrix(pos, Vector3.xAxis, dir))
			end
		end
		for deg = 38, 150, 10 do
			local a0, a1 = math.rad(deg), math.rad(deg + 10)
			local p0 = tc + Vector3.new(0, -math.cos(a0), s * math.sin(a0)) * R
			local p1 = tc + Vector3.new(0, -math.cos(a1), s * math.sin(a1)) * R
			gold(parent, "Stem", Vector3.new(0.7, 0.7, (p1 - p0).Magnitude + 0.4), CFrame.lookAt((p0 + p1) / 2, p1))
		end
		-- the tip leaf at the top of each arc
		local a = math.rad(160)
		local tip = tc + Vector3.new(0, -math.cos(a), s * math.sin(a)) * R
		leaf(parent, Vector3.new(1.1, 4.4, 2.2), CFrame.fromMatrix(tip, Vector3.xAxis, Vector3.new(0, math.sin(a), s * math.cos(a)).Unit))
	end
end

-- the crown on the tyre's top: a band of gold blocks, six points with ball tips, gems, a red velvet dome
local function crown(parent: Instance, base: Vector3)
	local K = 1.3
	local r = 4.6 * K
	part(parent, "Velvet", Vector3.new(8.4, 8.4, 8.4) * K, CFrame.new(base + Vector3.new(0, 1.2 * K, 0)), Color3.fromRGB(168, 28, 40), 0, Enum.PartType.Ball)
	gold(parent, "CrownTop", Vector3.new(1.8, 1.8, 1.8) * K, CFrame.new(base + Vector3.new(0, 5.9 * K, 0)), Enum.PartType.Ball)
	local gems = { Color3.fromRGB(214, 30, 48), Color3.fromRGB(40, 110, 230), Color3.fromRGB(40, 180, 90) }
	for k = 0, 11 do
		local ang = k * math.pi / 6
		local cf = CFrame.new(base) * CFrame.Angles(0, ang, 0)
		gold(parent, "CrownBand", Vector3.new(2.6, 2.6, 0.8) * K, cf * CFrame.new(0, 1.3 * K, r))
		if k % 2 == 0 then
			gold(parent, "CrownPoint", Vector3.new(1.9, 1.9, 0.8) * K, cf * CFrame.new(0, 3.1 * K, r) * CFrame.Angles(0, 0, math.pi / 4))
			gold(parent, "CrownTip", Vector3.new(1.1, 1.1, 1.1) * K, cf * CFrame.new(0, 4.6 * K, r), Enum.PartType.Ball)
		else
			part(parent, "Gem", Vector3.new(1.1, 1.1, 1.1) * K, cf * CFrame.new(0, 1.3 * K, r + 0.45 * K), gems[(k // 2) % 3 + 1], 0.2, Enum.PartType.Ball)
		end
	end
end

-- the turning top: turntable, gold chocks, the chrome tyre, laurels and crown
local function top(parent: Instance, y: number): Model
	local m = Instance.new("Model")
	m.Name = "Top"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local tt = part(m, "Turntable", Vector3.new(1.4, 22, 22), at(y + 0.7) * CFrame.Angles(0, 0, math.pi / 2), BLACK, 0.04, Enum.PartType.Cylinder)
	gold(m, "TurntableRim", Vector3.new(0.9, 23.2, 23.2), at(y + 0.45) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	m.PrimaryPart = tt
	local deck = y + 1.4
	-- the tyre, rolled on its tread with its axle along X
	local src = ReplicatedStorage.TyreCannon.Assets.Tyres:FindFirstChild("Tyre_monster")
	local tyre: BasePart
	if src and src:IsA("Model") and src.PrimaryPart then
		tyre = src.PrimaryPart:Clone()
		for _, c in ipairs(tyre:GetChildren()) do c:Destroy() end
		tyre.Size *= TYRE_SCALE
	else
		tyre = part(m, "Tyre", Vector3.new(12.8, 23.9, 23.9), CFrame.new(), CHROME, 0.6, Enum.PartType.Cylinder)
	end
	tyre.Name = "ChromeTyre"
	tyre.Anchored = true
	tyre.CanCollide = true
	tyre.Material = Enum.Material.SmoothPlastic
	tyre.Color = CHROME
	tyre.Reflectance = 0.6
	local radius = math.max(tyre.Size.X, tyre.Size.Y) / 2
	local tc = CENTRE + Vector3.new(0, deck + radius - 0.6, 0)
	if tyre:IsA("MeshPart") then
		tyre.CFrame = CFrame.new(tc) * CFrame.Angles(0, math.pi / 2, 0) -- the mesh's axle is its Z
	else
		tyre.CFrame = CFrame.new(tc)
	end
	tyre.Parent = m
	for _, s in ipairs({ -1, 1 }) do
		gold(m, "Chock", Vector3.new(tyre.Size.Z + 1, 2.6, 4), at(deck + 1.3) * CFrame.new(0, 0, s * radius * 0.6))
	end
	laurels(m, tc, radius)
	crown(m, tc + Vector3.new(0, radius - 0.3, 0))
	m.Parent = parent
	return m
end

function TrophyPillar.build(): Model?
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then return nil end
	local old = lobby:FindFirstChild("TrophyPillar")
	if old then return old :: Model end
	local m = Instance.new("Model")
	m.Name = "TrophyPillar"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local y = 0
	for _, s in ipairs(STEPS) do
		step(m, s[1], y, s[2])
		y += s[2]
	end
	gold(m, "Base", Vector3.new(30, BASE_H, 30), at(y + BASE_H / 2))
	y += BASE_H
	chequer(m, 28, y, BAND_H)
	y += BAND_H
	local coreY = y
	black(m, "Core", Vector3.new(CORE_W, CORE_H, CORE_W), at(y + CORE_H / 2))
	local h = CORE_W / 2
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			gold(m, "Column", Vector3.new(3.2, CORE_H, 3.2), at(y + CORE_H / 2) * CFrame.new(sx * h, 0, sz * h))
		end
	end
	for i, def in ipairs(TrophyPillar.BOARDS) do
		board(m, def, CFrame.Angles(0, (i - 1) * math.pi / 2, 0), coreY + CORE_H / 2)
	end
	y += CORE_H
	chequer(m, 28, y, BAND_H)
	y += BAND_H
	gold(m, "Cap", Vector3.new(30, CAP_H, 30), at(y + CAP_H / 2))
	y += CAP_H
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			gold(m, "Finial", Vector3.new(2.6, 2.6, 2.6), at(y + 1.1) * CFrame.new(sx * 13.6, 0, sz * 13.6), Enum.PartType.Ball)
		end
	end
	top(m, y)
	m.Parent = lobby
	return m
end

local function fmt(key: string, v: number, studsToMetres: number): string
	if key == "distance" then return Game.metres(v * studsToMetres) end
	if key == "week" then return Game.metres(v) end
	if key == "prestige" then return "P" .. math.floor(v) end
	return "$" .. Game.short(v)
end

-- fill the four boards from the server's board cache ({ [key] = { { name, value, userId } } })
function TrophyPillar.paint(cache: { [string]: any }, studsToMetres: number)
	local m = TrophyPillar.build()
	if not m then return end
	for _, def in ipairs(TrophyPillar.BOARDS) do
		local p = m:FindFirstChild("Board_" .. def.key)
		local sg = p and p:FindFirstChild("Board")
		if sg then
			local rows = cache[def.key] or {}
			for i = 1, ROWS do
				local row = sg:FindFirstChild("Row" .. i)
				local r = rows[i]
				if row then
					local face = row:FindFirstChild("Avatar") :: ImageLabel
					local name = row:FindFirstChild("PlayerName") :: TextLabel
					local value = row:FindFirstChild("Value") :: TextLabel
					if r then
						name.Text = r.name
						value.Text = fmt(def.key, r.value, studsToMetres)
						face.Image = r.userId and ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(r.userId) or ""
						face.Visible = r.userId ~= nil
					else
						name.Text = i == 1 and "Be the first!" or ""
						value.Text = ""
						face.Visible = false
					end
				end
			end
		end
	end
end

return TrophyPillar
