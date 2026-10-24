--!strict
-- TYRE CANNON :: PlotStage
-- A yard is built up as its owner climbs the tiers, and everyone in the server sees it:
--   free plot      bare dirt, a scrap-sheet fence, a To Let board
--   1 Dirt Lot     dirt, scrap fence, a tarp shack at the street with a tyre or two
--   2 Scrapyard    gravel, chain-link, a rusted shed, more stock out front
--   3 Workshop     concrete, chain-link, the garage bay with its shutter on the street, lamps
--   4 Depot        painted lane lines, green palisade, a gantry hoist and racks out front
--   5 Launch Cplx  hazard-marked lane, palisade, floodlight masts at the back corners
-- The building stands on the street side of the yard (the cannon fires out of the back), with a
-- gap beside it to walk in through. Its sign carries the owner's name.
-- Models: Assets/Stages (stages.py) and Assets/Lobby (garage.py); nothing shows until imported.
--   PlotStage.new() -> watches every plot

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local Models = require(script.Parent.Models)
local DayNight = require(script.Parent.DayNight)
local PackFX = require(script.Parent.PackFX)
local Sound = require(script.Parent.Sound)

local PlotStage = {}
PlotStage.__index = PlotStage

-- the plot's own frame: the floor runs x -34..74, z -39..39 on a dirt lot (it grows with the
-- stage, Game.yardFloor: the fence stands a stud outside the floor you can build on), its top 2
-- up; -x faces the street
local function floorFor(tier: number)
	local g = Game.yardFloor(math.max(1, tier))
	return { x0 = g.x0 - 1, x1 = g.x1 + 1, z0 = g.z0 - 1, z1 = g.z1 + 1, y = 2 }
end
local PANEL = 16
-- a building's frame: centred on z -14, its front on the street, its back against the floor edge
local BUILD_Z = -14
-- a building's frame has its front along +z; turning it -90 about y points that down -x (the
-- street). Imported pieces face -z with x mirrored, so they go in turned half round.
local FACE_STREET = CFrame.Angles(0, -math.pi / 2, 0)
local MODEL_FIX = CFrame.Angles(0, math.pi, 0)

local GROUND = {
	[0] = { mat = Enum.Material.Ground, variant = "TC_Dirt", color = Color3.fromRGB(255, 255, 255) },
	[1] = { mat = Enum.Material.Ground, variant = "TC_Dirt", color = Color3.fromRGB(255, 255, 255) },
	[2] = { mat = Enum.Material.Ground, variant = "TC_Gravel", color = Color3.fromRGB(255, 255, 255) },
	[3] = { mat = Enum.Material.Concrete, color = Color3.fromRGB(176, 172, 164) },
	[4] = { mat = Enum.Material.Concrete, color = Color3.fromRGB(170, 166, 158) },
	[5] = { mat = Enum.Material.Concrete, color = Color3.fromRGB(150, 148, 144) },
}
local FENCE = { [0] = "Stages/ScrapFence", [1] = "Stages/ScrapFence", [2] = "Lobby/ChainFence", [3] = "Lobby/ChainFence",
	[4] = "Stages/PalisadeFence", [5] = "Stages/PalisadeFence" }
-- the building, how deep it is, and where its sign board sits (building space: +z is its front)
local BUILDING = {
	[1] = { path = "Stages/TarpShack", depth = 11, sign = { at = Vector3.new(0, 7.2, 6.2), size = Vector2.new(6, 1.6) } },
	[2] = { path = "Stages/ScrapShed", depth = 17, sign = { at = Vector3.new(-2.5, 10.15, 8.5), size = Vector2.new(9.6, 1.3) } },
	[3] = { path = "Lobby/GarageBay", depth = 33, sign = { at = Vector3.new(0, 19.6, 15.7), size = Vector2.new(19.6, 2.4) } },
	[4] = { path = "Lobby/GarageBay", depth = 33, sign = { at = Vector3.new(0, 19.6, 15.7), size = Vector2.new(19.6, 2.4) } },
	[5] = { path = "Lobby/GarageBay", depth = 33, sign = { at = Vector3.new(0, 19.6, 15.7), size = Vector2.new(19.6, 2.4) } },
}
-- what stands in front of the building, in building space (x across its front, z out into the
-- street), by the tier it first appears at
local FRONT_PROPS = {
	{ tier = 1, path = "Lobby/TyreStack", x = 9, z = 3, r = 0 },
	{ tier = 1, path = "Lobby/OilDrum", x = -8, z = 2, r = 20 },
	{ tier = 2, path = "Lobby/TyreStack", x = 12, z = 4.5, r = 40 },
	{ tier = 2, path = "Lobby/TrolleyJack", x = 4, z = 4, r = 160 },
	{ tier = 2, path = "Lobby/OilDrum", x = -10.5, z = 3, r = 70 },
	{ tier = 3, path = "Lobby/TyreRack", x = -17, z = 3.5, r = 0 },
	{ tier = 3, path = "Lobby/AirPoint", x = 19.5, z = 3, r = 180 },
	{ tier = 4, path = "Lobby/GantryHoist", x = 30, z = 8, r = 90 },
	{ tier = 4, path = "Lobby/TyreRack", x = -17, z = 7.5, r = 0 },
}

local function place(path: string, parent: Instance, cf: CFrame): Model?
	local tpl = Models.get(path)
	if not tpl then return nil end
	-- solid: the yard is walked, so its building, fence and stock stop you
	local m = Models.place(tpl, parent, cf, 1, true)
	return m
end

local function signBoard(parent: Instance, cf: CFrame, size: Vector2, title: string, sub: string)
	local p = Instance.new("Part")
	p.Name = "NameBoard"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = Vector3.new(size.X, size.Y, 0.1)
	p.CFrame = cf
	p.Transparency = 1
	p.Parent = parent
	local sg = Instance.new("SurfaceGui")
	-- the part's back face looks out of the building
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 1
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
	t.RichText = true
	t.Text = ("%s<font size=\"28\" color=\"#8A4A1C\">  %s</font>"):format(title, sub)
	t.TextColor3 = Color3.fromRGB(40, 34, 30)
	t.TextScaled = true
	t.Parent = sg
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 70
	cap.Parent = t
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = t
end

local function lampLight(m: Model, parent: Instance, range: number, color: Color3)
	-- the light hangs off the far end of the arm, near the top of the model
	local cf, size = m:GetBoundingBox()
	local a = Instance.new("Attachment")
	local host = m:FindFirstChildWhichIsA("BasePart", true)
	if not host then return end
	-- imported with x mirrored, the arm's end is at the model's -x
	a.WorldCFrame = cf * CFrame.new(-(size.X / 2 - 0.8), size.Y / 2 - 1.4, 0)
	a.Parent = host
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = 1.4
	l.Color = color
	l.Shadows = false
	l.Parent = a
	local dn = (DayNight :: any).current
	if dn and dn.addLamp then dn:addLamp(l) end
	local _ = parent
end

-- the yard editor's preview of a floor or fence before it's saved ({ floor, fence } by plot)
PlotStage.previews = {} :: { [Instance]: { floor: string?, fence: string? } }

-- the owner's chosen floor and fence (Game.YardFloors / YardFences): the preview while editing, else
-- what the server published in the layout
local function skinOf(plot: Instance): (string, string)
	local pv = PlotStage.previews[plot]
	local saved = Game.yardDecode(plot:GetAttribute("V2_Layout") :: string?)
	return (pv and pv.floor) or saved.floor or "stage", (pv and pv.fence) or saved.fence or "stage"
end

-- shows a floor/fence on a plot without saving it (nil, nil goes back to the saved one)
function PlotStage.preview(plot: Instance, floor: string?, fence: string?)
	PlotStage.previews[plot] = if floor or fence then { floor = floor, fence = fence } else nil
	local cur = (PlotStage :: any).current
	if cur then cur:build(plot) end
end

-- (2026-10-24, the owner: the free yards still showed the white concrete and the old wooden posts and
-- rails) the place streams: a yard's Floor, FloorTrim and old Fence parts are the server's, and each
-- time one streams back in it comes back as the server has it. So the floor's look and the hidden old
-- fence are put on again whenever a part of the plot arrives, not just once when the stage is built.
function PlotStage:dress(plot: Instance)
	local d = self.dressing[plot]
	if not d then return end
	local floor = plot:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		floor.Material = d.floor.mat
		floor.MaterialVariant = d.floor.variant or ""
		floor.Color = d.floor.color
		floor.Size = d.floorSize
		floor.CFrame = d.floorCF
	end
	local trim = plot:FindFirstChild("FloorTrim")
	if trim and trim:IsA("BasePart") then
		-- (the place's own trim, as first seen, for when the yard is claimed)
		if not self.trimOrig[plot] then self.trimOrig[plot] = { mat = trim.Material, color = trim.Color } end
		local look = d.trim or self.trimOrig[plot]
		trim.Size = d.trimSize
		trim.CFrame = d.trimCF
		trim.Material = look.mat
		trim.MaterialVariant = ""
		trim.Color = look.color
	end
	-- the old wooden posts and rails: gone (the stage's own fence stands in their place)
	local oldFence = plot:FindFirstChild("Fence")
	if oldFence then
		for _, p in ipairs(oldFence:GetDescendants()) do
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = 1
				p.Transparency = 1
				-- (and out of the way: a grown yard reaches past where it stood)
				p.CanCollide = false
				p.CanQuery = false
			end
		end
	end
end

function PlotStage.new()
	local self = setmetatable({}, PlotStage)
	;(PlotStage :: any).current = self
	self.built = {} :: { [Instance]: string }
	self.dressing = {} :: { [Instance]: any }
	self.trimOrig = {} :: { [Instance]: any }
	self.expecting = {} :: { [Instance]: boolean }
	task.spawn(function()
		local lobby = workspace:WaitForChild("Lobby", 30)
		local plots = lobby and lobby:WaitForChild("Plots", 30)
		if not plots then return end
		for _, plot in ipairs(plots:GetChildren()) do self:watch(plot) end
		plots.ChildAdded:Connect(function(plot) self:watch(plot) end)
	end)
	return self
end

function PlotStage:watch(plot: Instance)
	local function refresh() self:build(plot) end
	plot:GetAttributeChangedSignal("V2_Tier"):Connect(refresh)
	plot:GetAttributeChangedSignal("V2_Owner"):Connect(refresh)
	plot:GetAttributeChangedSignal("V2_Layout"):Connect(refresh)
	-- (a streamed-in floor or fence part takes the yard's look again; once a frame, however many arrive)
	local queued = false
	plot.DescendantAdded:Connect(function(d)
		if queued or not d:IsA("BasePart") then return end
		if d.Name == "Floor" or d.Name == "FloorTrim" or d.Name == "Post" or d.Name == "Rail" then
			queued = true
			task.defer(function()
				queued = false
				self:dress(plot)
			end)
		end
	end)
	task.spawn(function()
		-- wait for the plot's frame and for the pieces to be in
		while not plot:GetAttribute("BaseCFrame") do task.wait(0.5) end
		local t0 = os.clock()
		while not Models.get("Stages/ScrapFence") and os.clock() - t0 < 20 do task.wait(1) end
		refresh()
	end)
end

--==============================================================
-- the stage-up scene: the old stage drops through the ground, the new one is built up out of it
--==============================================================
-- the next change to this plot's stage plays as a scene (StageUp sets this just before the purchase)
function PlotStage:expect(plot: Instance)
	self.expecting[plot] = true
end

function PlotStage:cancelExpect(plot: Instance)
	self.expecting[plot] = nil
end

local function pieces(folder: Instance): { Instance }
	local list = {}
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("Model") or (c:IsA("BasePart") and c.Name ~= "NameBoard") then table.insert(list, c) end
	end
	return list
end
local function pivotOf(i: Instance): CFrame
	return if i:IsA("Model") then i:GetPivot() else (i :: BasePart).CFrame
end
local function setPivot(i: Instance, cf: CFrame)
	if i:IsA("Model") then i:PivotTo(cf) else (i :: BasePart).CFrame = cf end
end
-- lowered `d` studs straight down in the world (a pivot may be turned any way, so no object-space moves)
local function lowered(cf: CFrame, d: number): CFrame
	return cf + Vector3.new(0, -d, 0)
end
local function heightOf(i: Instance): number
	if i:IsA("Model") then
		local _, size = i:GetBoundingBox()
		return size.Y
	end
	return (i :: BasePart).Size.Y
end

-- run `step(index, alpha)` for every piece, each starting `stagger` seconds after the last, each
-- taking `dur`; `done` runs when the last has finished
local function stagger(list: { Instance }, dur: number, gap: number, step: (number, number) -> (), done: (() -> ())?)
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		local all = true
		for i = 1, #list do
			local a = math.clamp((t - (i - 1) * gap) / dur, 0, 1)
			step(i, a)
			if a < 1 then all = false end
		end
		if all then
			conn:Disconnect()
			if done then done() end
		end
	end)
end

-- a piece that is moving must not shove anyone: its collision is switched off until it is still
local function hush(i: Instance): { BasePart }
	local held = {}
	local function one(d: Instance)
		if d:IsA("BasePart") and d.CanCollide then
			d.CanCollide = false
			table.insert(held, d)
		end
	end
	one(i)
	for _, d in ipairs(i:GetDescendants()) do one(d) end
	return held
end

function PlotStage:demolish(old: Instance)
	local list = pieces(old)
	for _, p in ipairs(list) do hush(p) end
	local at = {}
	for i, p in ipairs(list) do at[i] = pivotOf(p) end
	-- a shake first, then each piece sinks through the floor (the floor top is y 2 in the plot's frame)
	table.sort(list, function(a, b) return heightOf(a) > heightOf(b) end)
	for i, p in ipairs(list) do at[i] = pivotOf(p) end
	local thud = 0
	stagger(list, 0.55, 0.012, function(i, a)
		local p = list[i]
		if a <= 0 then return end
		local sink = (a * a) * (heightOf(p) + 6)
		local wob = math.sin(a * 40 + i) * (1 - a) * 0.4
		setPivot(p, lowered(at[i], sink) * CFrame.new(wob, 0, 0) * CFrame.Angles(0, 0, a * 0.12 * (i % 2 == 0 and 1 or -1)))
		if a >= 1 and p.Parent then
			p.Parent = nil
			if thud < 10 and i % 3 == 0 then
				thud += 1
				PackFX.burst("dustPuff", at[i] * CFrame.new(0, 1, 0), 5, Color3.fromRGB(150, 140, 125), 1.6)
			end
		end
	end, function() old:Destroy() end)
end

-- `rest` is where each piece belongs (build sinks them under the ground until their turn)
function PlotStage:rise(folder: Instance, rest: { [Instance]: CFrame }?)
	local list = pieces(folder)
	local base = {}
	for i, p in ipairs(list) do base[i] = if rest and rest[p] then rest[p] else pivotOf(p) end
	-- nearest the street first, then outward
	local order = {}
	for i = 1, #list do order[i] = i end
	table.sort(order, function(a, b) return base[a].Position.X < base[b].Position.X end)
	local sorted, sbase = {}, {}
	for k, i in ipairs(order) do
		sorted[k] = list[i]
		sbase[k] = base[i]
	end
	-- hold everything under the ground until its turn
	local held = {}
	for k, p in ipairs(sorted) do
		held[k] = hush(p)
		setPivot(p, lowered(sbase[k], heightOf(p) + 8))
	end
	local thuds = 0
	stagger(sorted, 0.7, 0.022, function(k, a)
		local p = sorted[k]
		if a <= 0 or not p.Parent then return end
		-- up out of the ground and over, settling with a little overshoot
		local e = 1 + 2.4 * (a - 1) ^ 3 + 1.4 * (a - 1) ^ 2
		setPivot(p, lowered(sbase[k], (1 - e) * (heightOf(p) + 8)))
		if a >= 1 and not p:GetAttribute("Landed") then
			p:SetAttribute("Landed", true)
			for _, part in ipairs(held[k]) do part.CanCollide = true end
			if (heightOf(p) > 6 or k % 4 == 0) and thuds < 22 then
				thuds += 1
				PackFX.burst("dustRing", sbase[k] * CFrame.new(0, 0.5, 0), 6, Color3.fromRGB(176, 166, 150), 1.2)
				if heightOf(p) > 6 then Sound.play("land", { volume = 0.5, pitch = 0.85 + math.random() * 0.3 }) end
			end
		end
	end)
end

function PlotStage:build(plot: Instance)
	local base = plot:GetAttribute("BaseCFrame") :: CFrame?
	if not base then return end
	local tier = (plot:GetAttribute("V2_Tier") :: number?) or 0
	local owner = plot:GetAttribute("V2_Owner") :: string?
	local skinFloor, skinFence = skinOf(plot)
	if tier < 1 then skinFloor, skinFence = "stage", "stage" end
	local key = tier .. "|" .. tostring(owner) .. "|" .. skinFloor .. "|" .. skinFence
	if self.built[plot] == key then return end
	self.built[plot] = key
	-- a stage-up (StageUp asked for it): the old stage drops away first, then the new one rises
	local scene = self.expecting[plot] == true
	self.expecting[plot] = nil
	local old = plot:FindFirstChild("Stage")
	if old then
		if scene then
			old.Name = "StageOld"
			self:demolish(old)
		else
			old:Destroy()
		end
	end
	local f = Instance.new("Folder")
	f.Name = "Stage"
	f.Parent = plot
	local FLOOR = floorFor(tier)

	-- the ground: the floor takes the tier's surface and size (client-side only; everyone's client
	-- builds every yard the same way)
	local floor = plot:FindFirstChild("Floor") :: BasePart?
	local g = GROUND[tier] or GROUND[0]
	local chosen = Game.YardFloorsById[skinFloor]
	if chosen and chosen.mat then
		g = { mat = (Enum.Material :: any)[chosen.mat], variant = chosen.variant, color = chosen.color }
	end
	-- (2026-10-24, the owner) a yard nobody has is plain sand, so it reads as free at a glance
	-- (2026-10-24, the owner, later: "change the base of said unclaimed plot to the sandstone we have in
	-- game") the park's sandstone pavers, edged in its kerb stone
	-- (and every yard, claimed or not, sits in the park's kerb stone rather than a grey concrete rim, so the
	-- yards meet the lawn the way the walks do)
	local trimLook = { mat = Enum.Material.Pavement, color = Color3.fromRGB(178, 152, 114) }
	if tier < 1 or not owner then
		g = { mat = Enum.Material.Pavement, color = Color3.fromRGB(214, 188, 146) }
	end
	local _ = floor
	self.dressing[plot] = {
		floor = g, trim = trimLook,
		floorSize = Vector3.new(FLOOR.x1 - FLOOR.x0, 2, FLOOR.z1 - FLOOR.z0),
		floorCF = base * CFrame.new((FLOOR.x0 + FLOOR.x1) / 2, 1, (FLOOR.z0 + FLOOR.z1) / 2),
		trimSize = Vector3.new(FLOOR.x1 - FLOOR.x0 + 4, 1.4, FLOOR.z1 - FLOOR.z0 + 4),
		trimCF = base * CFrame.new((FLOOR.x0 + FLOOR.x1) / 2, 0.5, (FLOOR.z0 + FLOOR.z1) / 2),
	}
	self:dress(plot)

	-- the fence: both sides, the back either side of the firing lane, the street side beside the gap
	local fence: string? = FENCE[tier] or FENCE[0]
	local fenceChoice = Game.YardFencesById[skinFence]
	if fenceChoice and fenceChoice.id == "none" then
		fence = nil
	elseif fenceChoice and fenceChoice.path then
		fence = fenceChoice.path
	end
	-- (2026-10-24, the owner: "fix the fences") a free yard is fenced too, in plain chain-link, so the row of
	-- yards stays neat; it had no fence at all, which left gaps in the row
	if tier < 1 or not owner then fence = if Models.get("Lobby/ChainFence") then "Lobby/ChainFence" else FENCE[0] end
	local function run(x0: number, z0: number, x1: number, z1: number)
		if not fence then return end
		local d = Vector3.new(x1 - x0, 0, z1 - z0)
		local len = d.Magnitude
		local n = math.max(1, math.ceil(len / PANEL - 0.05))
		local yaw = math.atan2(-d.Z, d.X)
		for i = 0, n - 1 do
			local t = (i + 0.5) / n
			local at = Vector3.new(x0, FLOOR.y, z0) + d * t
			place(fence :: string, f, base * CFrame.new(at) * CFrame.Angles(0, yaw, 0))
		end
	end
	run(FLOOR.x0, FLOOR.z1, FLOOR.x1, FLOOR.z1)
	run(FLOOR.x0, FLOOR.z0, FLOOR.x1, FLOOR.z0)
	run(FLOOR.x1, FLOOR.z0, FLOOR.x1, -13)
	run(FLOOR.x1, 13, FLOOR.x1, FLOOR.z1)
	run(FLOOR.x0, 24, FLOOR.x0, FLOOR.z1)

	-- lane markings as the yard is made proper
	local function paint(x0: number, z0: number, x1: number, z1: number, color: Color3)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = color
		p.Size = Vector3.new(math.abs(x1 - x0), 0.05, math.abs(z1 - z0))
		p.CFrame = base * CFrame.new((x0 + x1) / 2, FLOOR.y + 0.03, (z0 + z1) / 2)
		p.Parent = f
	end
	if tier >= 4 then
		for _, z in ipairs({ -13, 13 }) do paint(-24, z - 0.3, FLOOR.x1, z + 0.3, Color3.fromRGB(232, 188, 52)) end
	end
	if tier >= 5 then
		for k = 0, 7 do
			local z = -12 + k * 3.2
			paint(FLOOR.x1 - 6, z, FLOOR.x1 - 1, z + 1.6, (k % 2 == 0) and Color3.fromRGB(232, 188, 52) or Color3.fromRGB(28, 28, 30))
		end
	end

	-- the building on the street, and what stands in front of it
	local b = BUILDING[tier]
	if b then
		local bcf = base * CFrame.new(FLOOR.x0 - b.depth / 2 - 0.5, 0, BUILD_Z) * FACE_STREET
		local m = place(b.path, f, bcf * MODEL_FIX)
		if m then
			local s = b.sign
			signBoard(f, bcf * CFrame.new(s.at), s.size, string.upper(owner or "Yard"), Game.Tiers[tier].name)
			-- and on the wall that faces into the yard, where you stand: the same board turned round
			signBoard(f, bcf * CFrame.new(-s.at.X, s.at.Y, -b.depth / 2 - 0.15) * CFrame.Angles(0, math.pi, 0), s.size,
				string.upper(owner or "Yard"), Game.Tiers[tier].name)
		end
		local frontZ = b.depth / 2
		for _, pr in ipairs(FRONT_PROPS) do
			if tier >= pr.tier then
				place(pr.path, f, bcf * CFrame.new(pr.x, 0, frontZ + pr.z) * CFrame.Angles(0, math.rad(pr.r), 0) * MODEL_FIX)
			end
		end
		-- lamps either side of the frontage from the workshop up; floodlights at the back at the top
		if tier >= 3 then
			for _, x in ipairs({ -25, 25 }) do
				-- the arm (model -x) reaches out over the frontage toward the street (+z)
				local lamp = place("Lobby/SodiumLamp", f, bcf * CFrame.new(x, 0, frontZ + 1.5) * CFrame.Angles(0, math.rad(90), 0))
				if lamp then lampLight(lamp, f, 36, Color3.fromRGB(255, 196, 132)) end
			end
		end
		if tier >= 5 then
			for _, z in ipairs({ FLOOR.z0 + 3, FLOOR.z1 - 3 }) do
				-- heads (model -z) toward the yard (-x)
				local mast = place("Stages/FloodLight", f, base * CFrame.new(FLOOR.x1 - 3, FLOOR.y, z) * CFrame.Angles(0, math.pi / 2, 0))
				if mast then lampLight(mast, f, 60, Color3.fromRGB(255, 248, 236)) end
			end
		end
	end
	-- (a free plot has no To Let board: the claim pad says it all)
	if scene then
		-- (until its turn the new stage sits under the ground; rise puts each piece back where it was built)
		local rest: { [Instance]: CFrame } = {}
		for _, p in ipairs(pieces(f)) do
			rest[p] = pivotOf(p)
			setPivot(p, lowered(rest[p], heightOf(p) + 8))
		end
		task.delay(1.2, function()
			if f.Parent then self:rise(f, rest) end
		end)
	end
end

return PlotStage
