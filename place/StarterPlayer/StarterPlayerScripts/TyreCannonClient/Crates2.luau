--!strict
-- TYRE CANNON :: Crates2 (v3)
-- The crate screen, laid out like a summon banner:
--   left     a tab a crate (Backroad, Highway, Dunes): its picture, its name, what it costs; a crate
--            you haven't reached is veiled and says how far it is
--   centre   the banner: the crate big on a coloured stage with slow rays, the featured Legendary in
--            a bay (x3 in every crate) with the clock to the next banner, Test Drive (one free run a
--            banner), the pity bar, and four buttons: cash x1, cash x3, key x1 (luckier, counts to
--            the pity), key x3
--   right    the drop rates for that crate, cash and key side by side
-- Opening: one or three display bays behind roller shutters, opened one after another: the
-- shutter rattles (harder the rarer), rolls up, the bay floods with the rarity's colour and the
-- tyre drops in; its name, rarity and multiplier come up, and a mutation's badge if it rolled one.
-- Open Again (the same way, the same count) or Done.
--   Crates2.new(gui, remotes) -> crates ; crates:setProfile(p) ; crates:open()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Game = require(Modules.Game)
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local TyreLook = require(script.Parent.TyreLook)
local TyreShow = require(script.Parent.TyreShow)
local C = Kit.C

local Crates2 = {}
Crates2.__index = Crates2

-- a spinning tyre in a viewport
function Crates2.tyreViewport(parent: Instance, size: UDim2, tyreId: string?): (ViewportFrame, () -> ())
	local vp = UI.mk("ViewportFrame", { Size = size, BackgroundTransparency = 1, Ambient = Color3.fromRGB(170, 170, 180), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1), Parent = parent })
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local model = TyreLook.model(tyreId, 6, "Preview")
	model.Parent = world
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 2.2, 14), Vector3.zero)
	cam.Parent = vp
	vp.CurrentCamera = cam
	local a = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		a += dt
		if model.Parent then
			model:PivotTo(CFrame.Angles(0, math.rad(-30) + math.sin(a * 0.6) * 0.12, 0) * CFrame.Angles(0, 0, -a * 1.2))
		end
	end)
	return vp, function() conn:Disconnect() end
end

local RARITY_ORDER = {}
for i, r in ipairs(Game.Rarities) do RARITY_ORDER[r.id] = i end

local function pct(x: number): string
	local p = x * 100
	if p >= 1 then return ("%d%%"):format(math.floor(p + 0.5)) end
	if p >= 0.1 then return ("%.1f%%"):format(p) end
	return ("%.2f%%"):format(p)
end

-- each crate's look: its colour, its picture (a Blender render per crate) and a line about it
local ZONE_LOOK = {
	backroad = { color = Color3.fromRGB(150, 205, 60), icon = Kit.Icon.crate_backroad or Kit.Icon.crate, sub = "The everyday crate. Plain tyres, and a Legendary if you're lucky." },
	highway = { color = Color3.fromRGB(255, 128, 40), icon = Kit.Icon.crate_highway or Kit.Icon.crate, sub = "Every tyre in it pays x2 a Backroad one: even a Common beats a Backroad Rare." },
	dunes = { color = Color3.fromRGB(176, 112, 240), icon = Kit.Icon.crate_dunes or Kit.Icon.crate, sub = "Every tyre in it pays x4 a Backroad one: even a Common beats a Backroad Epic." },
}

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	return ("%d:%02d:%02d"):format(sec // 3600, (sec % 3600) // 60, sec % 60)
end

function Crates2.new(gui: ScreenGui, remotes: Instance)
	local self = setmetatable({}, Crates2)
	self.gui = gui
	self.R = remotes
	self.stops = {}
	self.count = 1
	self.zone = "backroad"
	local root = UI.mk("Frame", {
		Name = "Crates2", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(1000, 620),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.root = root
	local holder, face = Kit.card(UDim2.fromOffset(1000, 604), C.cream, 22, 9)
	holder.Parent = root
	Kit.header(face, "Crates", C.purple, 56)
	local close = Kit.close(52)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, 12, 0, -14)
	close.root.ZIndex = 40
	close.root.Parent = root
	close.onClick = function() self:close() end
	-- the top line, level with the title: the banner's clock, then your keys (a smaller counter,
	-- its middle on the panel's top edge like the title's)
	local keyChip, keyText = Kit.chip(Kit.Icon.key, nil, 112)
	keyChip.AnchorPoint = Vector2.new(1, 0.5)
	keyChip.Position = UDim2.new(1, -62, 0, 8)
	keyChip.ZIndex = 9
	keyChip.Parent = face
	UI.mk("UIScale", { Scale = 0.82, Parent = keyChip })
	for _, d in ipairs(keyChip:GetDescendants()) do
		if d:IsA("GuiObject") then d.ZIndex = math.max(d.ZIndex, 9) end
	end
	local keyIcon = keyChip:FindFirstChild("Icon") :: ImageLabel?
	if keyIcon then
		-- the key sits inside the counter's left end instead of hanging off it
		keyIcon.Position = UDim2.new(0, 22, 0.5, 0)
		keyIcon.Size = UDim2.fromOffset(40, 40)
	end
	self.keysText = keyText
	self.bannerClock = Kit.text("", 15, C.text, 2, Kit.Body)
	self.bannerClock.AnchorPoint = Vector2.new(1, 0.5)
	self.bannerClock.TextXAlignment = Enum.TextXAlignment.Right
	self.bannerClock.Position = UDim2.new(1, -170, 0, 8)
	self.bannerClock.Size = UDim2.fromOffset(440, 20)
	Kit.fit(self.bannerClock, 15, 10)
	self.bannerClock.ZIndex = 9
	self.bannerClock.Parent = face

	---------------------------------------------------------------
	-- the banner tabs down the left: one a crate, its picture, its name, what it costs
	---------------------------------------------------------------
	self.tabs = {}
	for i, z in ipairs(Game.Zones) do
		local look = ZONE_LOOK[z.id]
		local b = UI.mk("TextButton", {
			Name = z.id, Position = UDim2.fromOffset(22, 54 + (i - 1) * 180), Size = UDim2.fromOffset(212, 168),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 5, Parent = face,
		})
		local inner = UI.mk("Frame", { Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5, Parent = b })
		local frame = Kit.slice("tile", look.color, inner, 5, 0.42)
		UI.mk("ImageLabel", {
			Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(150, 130),
			BackgroundTransparency = 1, Image = Kit.Art.glow, ImageColor3 = look.color, ImageTransparency = 0.45, ZIndex = 6, Parent = inner,
		})
		local pic = UI.mk("ImageLabel", {
			Name = "Crate", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.37), Size = UDim2.fromOffset(96, 96),
			BackgroundTransparency = 1, Image = look.icon, ZIndex = 8, Parent = inner,
		})
		local name = Kit.text(string.upper(z.name), 20, C.white, 2.5)
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -30)
		name.Size = UDim2.fromOffset(190, 24)
		Kit.fit(name, 20, 11)
		name.ZIndex = 13
		name.Parent = inner
		local status = Kit.text("", 14, C.gold, 2, Kit.Body)
		status.AnchorPoint = Vector2.new(0.5, 1)
		status.Position = UDim2.new(0.5, 0, 1, -10)
		status.Size = UDim2.fromOffset(190, 18)
		-- (above the veil: on a locked crate this is what says how far it is)
		status.ZIndex = 13
		status.Parent = inner
		local veil = UI.mk("Frame", {
			Name = "Veil", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), BackgroundColor3 = Color3.fromRGB(8, 8, 12),
			BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 11, Visible = false, Parent = inner,
		}, { UI.corner(10) })
		UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1,
			Image = Kit.Icon.lock, ZIndex = 12, Parent = veil,
		})
		local sweep = Kit.shine(frame, 10)
		b.MouseEnter:Connect(function()
			if self.zone ~= z.id then Kit.tween(inner, 0.14, { Position = UDim2.fromOffset(5, 0) }, Enum.EasingStyle.Back) end
			sweep()
		end)
		b.MouseLeave:Connect(function()
			Kit.tween(inner, 0.14, { Position = UDim2.fromOffset(self.zone == z.id and 6 or 0, 0) })
		end)
		b.Activated:Connect(function() self:selectZone(z.id) end)
		self.tabs[z.id] = { button = b, inner = inner, frame = frame, status = status, veil = veil, crate = pic }
	end

	---------------------------------------------------------------
	-- the banner: the crate on a coloured stage with this crate's tyres drifting round it, its
	-- name, the featured tyre, and under it one switch (pay with cash or keys) and two buttons
	---------------------------------------------------------------
	local banner = UI.mk("Frame", { Position = UDim2.fromOffset(250, 54), Size = UDim2.fromOffset(500, 528), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
	self.bannerRing = Kit.slice("panel_ring", C.purple, banner, 6, 0.4)
	local stage = UI.mk("Frame", {
		Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), BackgroundColor3 = Color3.fromRGB(20, 20, 24), ClipsDescendants = true,
		ZIndex = 5, Parent = banner,
	}, { UI.corner(10) })
	self.stage2 = stage
	self.stageGlow = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(170, 206), Size = UDim2.fromScale(1.1, 1.0), BackgroundTransparency = 1,
		Image = Kit.Art.glow, ImageColor3 = C.purple, ImageTransparency = 0.35, ZIndex = 5, Parent = stage,
	})
	-- the crate's own tyres, faint, drifting slowly round behind it, each turning (fillDrift)
	self.drift = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5, Parent = stage })
	self.driftItems = {}
	self.bannerTitle = Kit.text("", 34, C.white, 3)
	self.bannerTitle.Position = UDim2.fromOffset(0, 14)
	self.bannerTitle.Size = UDim2.new(1, 0, 0, 40)
	Kit.fit(self.bannerTitle, 34, 18)
	self.bannerTitle.ZIndex = 8
	self.bannerTitle.Parent = stage
	self.bannerSub = Kit.text("", 15, C.muted, 1.5, Kit.Body)
	self.bannerSub.Position = UDim2.fromOffset(16, 54)
	self.bannerSub.Size = UDim2.new(1, -32, 0, 30)
	self.bannerSub.TextWrapped = true
	Kit.fit(self.bannerSub, 14, 11)
	self.bannerSub.ZIndex = 8
	self.bannerSub.Parent = stage
	self.bigCrate = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 170, 0, 206), Size = UDim2.fromOffset(210, 210), BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit, ZIndex = 9, Parent = stage,
	})
	self.stopBob = Kit.bob(self.bigCrate, 6, 1.6)
	-- the featured Legendary: a card on the right, its tag on top, its Test Drive along its foot
	local feat = UI.mk("Frame", { Position = UDim2.new(1, -164, 0, 104), Size = UDim2.fromOffset(148, 206), BackgroundTransparency = 1, ZIndex = 8, Parent = stage })
	Kit.slot(feat, Game.RaritiesById.Legendary.color, 8)
	self.bannerBay = feat
	self.featName = Kit.text("", 14, C.white, 2)
	self.featName.AnchorPoint = Vector2.new(0.5, 1)
	self.featName.Position = UDim2.new(0.5, 0, 1, -58)
	self.featName.Size = UDim2.fromOffset(138, 18)
	Kit.fit(self.featName, 14, 9)
	self.featName.ZIndex = 12
	self.featName.Parent = feat
	self.featRate = Kit.text("", 12, Game.RaritiesById.Legendary.color, 2, Kit.Body)
	self.featRate.AnchorPoint = Vector2.new(0.5, 1)
	self.featRate.Position = UDim2.new(0.5, 0, 1, -42)
	self.featRate.Size = UDim2.fromOffset(138, 14)
	self.featRate.ZIndex = 12
	self.featRate.Parent = feat
	Kit.plate(stage, "Featured", Game.RaritiesById.Legendary.color, UDim2.new(1, -154, 0, 84), UDim2.fromOffset(128, 26), 12)
	local test = Kit.button("Test Drive", C.yellow, UDim2.fromOffset(140, 30), 14)
	test.root.AnchorPoint = Vector2.new(0.5, 1)
	test.root.Position = UDim2.new(0.5, 0, 1, -8)
	test.root.ZIndex = 12
	test.root.Parent = feat
	test.onClick = function() self:testDrive() end
	self.testBtn = test
	-- pay with: cash (the everyday way) or keys (luckier, and counts toward the guaranteed Legendary)
	self.pay = "cash"
	local paySeg, setPay = Kit.segment({ { id = "cash", label = "Cash" }, { id = "keys", label = "Keys" } }, "cash", 120, 36, function(id)
		self.pay = id
		self:refreshPay()
	end)
	paySeg.AnchorPoint = Vector2.new(0.5, 0)
	paySeg.Position = UDim2.new(0.5, 0, 1, -146)
	paySeg.ZIndex = 9
	paySeg.Parent = stage
	self.setPay = setPay
	-- under the switch: the pity (keys) or what keys would bring (cash)
	self.pityText = Kit.text("", 13, C.white, 1.5, Kit.Body)
	self.pityText.AnchorPoint = Vector2.new(0.5, 1)
	self.pityText.Position = UDim2.new(0.5, 0, 1, -88)
	self.pityText.Size = UDim2.new(1, -28, 0, 16)
	Kit.fit(self.pityText, 13, 9)
	self.pityText.ZIndex = 9
	self.pityText.Parent = stage
	local ptrack, pfill = Kit.bar(460, 14, Game.RaritiesById.Legendary.color)
	ptrack.AnchorPoint = Vector2.new(0.5, 1)
	ptrack.Position = UDim2.new(0.5, 0, 1, -70)
	ptrack.ZIndex = 9
	ptrack.Parent = stage
	self.pityFill, self.pityTrack = pfill, ptrack
	-- two buttons: one crate, or three
	local function btn(x: number, n: number)
		local b = Kit.button("", C.green, UDim2.fromOffset(226, 52), 19)
		b.root.AnchorPoint = Vector2.new(0, 1)
		b.root.Position = UDim2.new(0, x, 1, -10)
		b.root.ZIndex = 9
		b.root.Parent = stage
		b.onClick = function() self:openCrate(self.zone, self.pay, n) end
		return b
	end
	self.openBtns = { one = btn(12, 1), three = btn(12 + 226 + 8, Game.Crate.MaxOpen) }

	---------------------------------------------------------------
	-- the right: what's inside, a row a tyre (rarest first): it turns in its well, its name, what it
	-- pays (x cash) and its chance the way you're paying; a tyre that would beat your launch tyre
	-- says UPGRADE, one you've found has a tick
	---------------------------------------------------------------
	local rates = UI.mk("Frame", { Position = UDim2.fromOffset(766, 54), Size = UDim2.fromOffset(212, 528), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
	Kit.slot(rates, Kit.NEUTRAL, 4)
	local it = Kit.text("WHAT'S INSIDE", 18, C.white, 2.5)
	it.Position = UDim2.fromOffset(0, 12)
	it.Size = UDim2.new(1, 0, 0, 24)
	it.ZIndex = 6
	it.Parent = rates
	self.compare = Kit.text("", 13, C.muted, 1.5, Kit.Body)
	self.compare.Position = UDim2.fromOffset(8, 38)
	self.compare.Size = UDim2.new(1, -16, 0, 32)
	self.compare.TextWrapped = true
	Kit.fit(self.compare, 13, 9)
	self.compare.ZIndex = 6
	self.compare.Parent = rates
	self.inside = UI.mk("ScrollingFrame", {
		Position = UDim2.fromOffset(6, 74), Size = UDim2.new(1, -12, 1, -122), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, ScrollBarImageColor3 = C.line, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 6, Parent = rates,
	})
	UI.mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.inside })
	UI.mk("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6), Parent = self.inside })
	self.insideRows = {}
	local mut = Kit.text("Any tyre can roll Gold x2, Chrome x3 or Rainbow x5.", 12, C.muted, 1, Kit.Body)
	mut.AnchorPoint = Vector2.new(0.5, 1)
	mut.Position = UDim2.new(0.5, 0, 1, -10)
	mut.Size = UDim2.new(1, -16, 0, 32)
	mut.TextWrapped = true
	mut.ZIndex = 6
	mut.Parent = rates

	-- the opening, full screen
	local overlay = UI.mk("Frame", { Name = "CrateStage", Size = UDim2.new(1, 0, 1, 120), Position = UDim2.fromOffset(0, -60), BackgroundColor3 = Color3.fromRGB(8, 8, 8), BackgroundTransparency = 1, Visible = false, ZIndex = 60, Parent = gui })
	self.stage = overlay
	self.tiles = self.openBtns
	task.spawn(function()
		while root.Parent do
			if root.Visible and self.shown then self:tickBanner() end
			task.wait(1)
		end
	end)
	-- the drifting tyres behind the crate, and the tyres turning in the rows
	task.spawn(function()
		local t = 0
		while root.Parent do
			local dt = RunService.RenderStepped:Wait()
			if root.Visible then
				t += dt
				for i, d in ipairs(self.driftItems) do
					local a = t * 0.12 + d.phase
					d.vp.Position = UDim2.fromOffset(170 + math.cos(a) * d.rx, 206 + math.sin(a) * d.ry)
					if d.model then TyreShow.pose(d.model, t * d.spin + d.phase) end
					local _ = i
				end
				for _, r in ipairs(self.insideRows) do
					if r.model then TyreShow.pose(r.model, TyreShow.THUMB_YAW + t * 0.8 + r.phase) end
				end
			end
		end
	end)
	self:selectZone("backroad", true)
	return self
end

-- point the banner at a crate
function Crates2:selectZone(id: string, instant: boolean?)
	local look = ZONE_LOOK[id]
	self.zone = id
	for zid, t in pairs(self.tabs) do
		local on = zid == id
		Kit.tween(t.inner, 0.16, { Position = UDim2.fromOffset(on and 6 or 0, 0) }, Enum.EasingStyle.Back)
		t.frame.ImageColor3 = if on then Kit.lift(ZONE_LOOK[zid].color, 0.12) else ZONE_LOOK[zid].color
	end
	self.bannerRing.ImageColor3 = look.color
	self.stageGlow.ImageColor3 = look.color
	self.bigCrate.Image = look.icon
	if not instant then
		self.bigCrate.Size = UDim2.fromOffset(170, 170)
		Kit.tween(self.bigCrate, 0.4, { Size = UDim2.fromOffset(210, 210) }, Enum.EasingStyle.Back)
	end
	local z = Game.ZonesById[id]
	self.bannerTitle.Text = string.upper(z.name) .. " CRATE"
	self.bannerSub.Text = look.sub
	self:fillInside(id)
	self:fillDrift(id)
	if self.profile then self:setProfile(self.profile) end
end

-- what's inside a crate: a row for every tyre it can give (not the Secrets), rarest first
function Crates2:fillInside(zoneId: string)
	local box = self.inside
	if not box then return end
	for _, c in ipairs(box:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	self.insideRows = {}
	-- each tyre's chance from a cash crate, and from a key crate (Epic and up KeyLuck times)
	local list, kTotal = {}, 0
	for _, e in ipairs(Game.crateOdds(zoneId, math.floor(workspace:GetServerTimeNow()))) do
		local t = Game.TyresById[e.id]
		if t then
			local kw = e.odds * (if RARITY_ORDER[t.rarity] >= RARITY_ORDER.Epic then Game.Crate.KeyLuck else 1)
			kTotal += kw
			if t.rarity ~= "Secret" then table.insert(list, { t = t, odds = e.odds, kw = kw, featured = e.featured }) end
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = RARITY_ORDER[a.t.rarity], RARITY_ORDER[b.t.rarity]
		if ra ~= rb then return ra > rb end
		return a.t.num < b.t.num
	end)
	for i, e in ipairs(list) do
		local r = Game.RaritiesById[e.t.rarity]
		local row = UI.mk("Frame", { Name = e.t.id, Size = UDim2.new(1, -6, 0, 58), BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 7, Parent = box })
		Kit.slot(row, r.color, 7)
		local vp, model = TyreShow.thumb(row, e.t.id, true, UDim2.fromOffset(46, 42), UDim2.new(0, 28, 0, 8))
		vp.ZIndex = 9
		local name = Kit.text(e.t.name, 13, C.white, 1.5)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(54, 6)
		name.Size = UDim2.fromOffset(86, 16)
		Kit.fit(name, 13, 8)
		name.ZIndex = 9
		name.Parent = row
		local rar = Kit.text(string.upper(r.id) .. (if e.featured then "  ★" else ""), 11, r.color, 1.5, Kit.Body)
		rar.TextXAlignment = Enum.TextXAlignment.Left
		rar.Position = UDim2.fromOffset(54, 24)
		rar.Size = UDim2.fromOffset(86, 14)
		Kit.fit(rar, 11, 7)
		rar.ZIndex = 9
		rar.Parent = row
		local mult = Kit.text("x" .. Game.multText(Game.tyreMult(e.t.id, 0, nil)), 14, C.gold, 1.5)
		mult.AnchorPoint = Vector2.new(1, 0)
		mult.TextXAlignment = Enum.TextXAlignment.Right
		mult.Position = UDim2.new(1, -8, 0, 5)
		mult.Size = UDim2.fromOffset(52, 18)
		mult.ZIndex = 9
		mult.Parent = row
		local chance = Kit.text("", 12, C.text, 1.5, Kit.Body)
		chance.AnchorPoint = Vector2.new(1, 0)
		chance.TextXAlignment = Enum.TextXAlignment.Right
		chance.Position = UDim2.new(1, -8, 0, 25)
		chance.Size = UDim2.fromOffset(52, 16)
		chance.ZIndex = 9
		chance.Parent = row
		local tag = Kit.text("", 10, C.green, 1.5, Kit.Body)
		tag.TextXAlignment = Enum.TextXAlignment.Left
		-- under the rarity, clear of the picture and the name
		tag.Position = UDim2.fromOffset(54, 40)
		tag.Size = UDim2.fromOffset(86, 12)
		Kit.fit(tag, 10, 7)
		tag.ZIndex = 10
		tag.Parent = row
		table.insert(self.insideRows, {
			id = e.t.id, row = row, model = model, chance = chance, tag = tag, cash = e.odds, key = e.kw / math.max(kTotal, 1e-9),
			mult = Game.tyreMult(e.t.id, 0, nil), phase = i * 0.7,
		})
	end
	self:refreshPay()
end

-- the crate's tyres drifting behind it: up to seven, faint, round an ellipse, each turning
function Crates2:fillDrift(zoneId: string)
	for _, c in ipairs(self.drift:GetChildren()) do c:Destroy() end
	self.driftItems = {}
	local ids = {}
	for _, t in ipairs(Game.TyresByZone[zoneId] or {}) do table.insert(ids, t.id) end
	for _, t in ipairs(Game.TyresByZone.mythic or {}) do table.insert(ids, t.id) end
	for i, id in ipairs(ids) do
		if i > 7 then break end
		local size = 74 + (i % 3) * 16
		local vp, model = TyreShow.thumb(self.drift, id, true, UDim2.fromOffset(size, size), UDim2.new())
		vp.AnchorPoint = Vector2.new(0.5, 0.5)
		vp.ImageTransparency = 0.72
		vp.ZIndex = 5
		table.insert(self.driftItems, {
			vp = vp, model = model, phase = (i - 1) / math.min(#ids, 7) * math.pi * 2, rx = 150 + (i % 2) * 40, ry = 120 + (i % 3) * 18,
			spin = 0.35 + (i % 3) * 0.15,
		})
	end
end

-- the switch between cash and keys: the buttons' prices, the chances in the rows, the pity line
function Crates2:refreshPay()
	local keys = self.pay == "keys"
	for _, r in ipairs(self.insideRows or {}) do
		r.chance.Text = pct(if keys then r.key else r.cash)
		r.chance.TextColor3 = if keys then C.gold else C.text
	end
	if self.pityTrack then self.pityTrack.Visible = keys end
	if self.profile then self:setProfile(self.profile) end
end

function Crates2:setCount(n: number)
	self.count = n
end

function Crates2:tickBanner()
	local now = workspace:GetServerTimeNow()
	local ev = Game.eventAt(math.floor(now)).on
	local b = Game.banner(math.floor(now))
	local leg = Game.TyresById[b.legendary]
	local myth = Game.TyresById[b.mythic]
	if b.legendary ~= self.shownLegend then
		self.shownLegend = b.legendary
		-- a new banner changes what's inside
		self:fillInside(self.zone)
		if self.bannerStop then self.bannerStop() end
		local old = self.bannerBay:FindFirstChild("Featured")
		if old then old:Destroy() end
		if self.root.Visible and self.shown then
			local vp, stop = Crates2.tyreViewport(self.bannerBay, UDim2.new(1, -16, 0, 118), b.legendary)
			vp.Name = "Featured"
			vp.Position = UDim2.fromOffset(8, 6)
			vp.ZIndex = 10
			self.bannerStop = function()
				stop()
				vp:Destroy()
			end
		end
	end
	self.featName.Text = leg and leg.name or ""
	local rush = ev and ev.id == "rush"
	self.featRate.Text = rush and "LEGENDARY RUSH x5" or ("RATE UP x%d"):format(Game.Crate.FeaturedMult)
	local nxt = Game.TyresById[b.nextLegendary]
	self.bannerClock.Text = ("New banner in %s  ·  next: %s%s"):format(clock(b.ends - now), nxt and nxt.name or "?",
		myth and ("  ·  Mythic: " .. myth.name) or "")
	-- the Test Drive: one a banner
	local v = self.profile and self.profile.v2
	local span = Game.Crate.BannerHours * 3600
	local used = v and v.testDrive and math.floor(v.testDrive / span) == math.floor(now / span)
	if v and v.testArmed then
		self.testBtn.setText("Armed")
		self.testBtn.setEnabled(false)
	elseif used then
		self.testBtn.setText("Used")
		self.testBtn.setEnabled(false)
	else
		self.testBtn.setText("Test Drive")
		self.testBtn.setEnabled(true)
	end
end

function Crates2:setProfile(p)
	self.profile = p
	if not p or not p.v2 then return end
	local v = p.v2
	self.keysText.Text = tostring(v.keys)
	local N = Game.Crate.MaxOpen
	for _, z in ipairs(Game.Zones) do
		local t = self.tabs[z.id]
		local unlocked = v.zones[z.id] == true
		t.veil.Visible = not unlocked
		t.status.Text = if unlocked then ("$%s a crate"):format(Game.short(Game.crateCash(z.id, v.tier))) else ("Reach %s"):format(Game.metres(z.start))
	end
	local z = self.zone
	local unlocked = v.zones[z] == true
	local b = self.openBtns
	local keys = self.pay == "keys"
	if keys then
		local k1 = Game.cratePrice(z)
		b.one.setText(("Open  ·  %d Key%s"):format(k1, k1 == 1 and "" or "s"))
		b.three.setText(("Open x%d  ·  %d Keys"):format(N, k1 * N))
		b.one.setColor(C.purple)
		b.three.setColor(C.purple)
		b.one.setEnabled(unlocked and v.keys >= k1)
		b.three.setEnabled(unlocked and v.keys >= k1 * N)
		local left = math.max(1, Game.Crate.Pity - v.pity)
		self.pityText.Text = ("Epic and up x%d  ·  Legendary guaranteed in %d key crate%s"):format(Game.Crate.KeyLuck, left, left == 1 and "" or "s")
		self.pityFill.Size = UDim2.fromScale(math.clamp(v.pity / Game.Crate.Pity, 0, 1), 1)
	else
		local c1 = Game.crateCash(z, v.tier)
		b.one.setText(("Open  ·  $%s"):format(Game.short(c1)))
		b.three.setText(("Open x%d  ·  $%s"):format(N, Game.short(c1 * N)))
		b.one.setColor(C.green)
		b.three.setColor(C.green)
		b.one.setEnabled(unlocked and p.credits >= c1)
		b.three.setEnabled(unlocked and p.credits >= c1 * N)
		self.pityText.Text = "Pay with keys for Epic and up twice as often"
	end
	if not unlocked then
		self.pityText.Text = ("Reach %s to open this crate"):format(Game.metres(Game.ZonesById[z].start))
	end
	-- the rows against your launch tyre: anything that pays more is an upgrade
	local mine = 1
	for _, t in ipairs(v.inv) do
		if t.uid == v.launch then mine = Game.tyreMult(t.id, t.forge, t.mut) end
	end
	local best = 0
	for _, r in ipairs(self.insideRows or {}) do
		best = math.max(best, r.mult)
		local found = v.index and v.index[r.id] == true
		if r.mult > mine then
			r.tag.Text = "▲ UPGRADE"
			r.tag.TextColor3 = C.green
		elseif found then
			r.tag.Text = "✓ FOUND"
			r.tag.TextColor3 = C.muted
		else
			r.tag.Text = ""
		end
	end
	self.compare.Text = ("Your launch tyre pays <font color=\"#ECC478\">x%s</font>. The best in here pays <font color=\"#56C248\">x%s</font>."):format(
		Game.multText(mine), Game.multText(best))
end

function Crates2:open()
	Kit.dim(self.gui or self.root.Parent, self, true)
	Kit.open(self.root)
	self.shown = true
	self.shownLegend = nil
	self:tickBanner()
end

function Crates2:close()
	Kit.dim(self.gui or self.root.Parent, self, false)
	self.shown = false
	if self.root.Visible then Kit.close_(self.root) end
	if self.bannerStop then
		self.bannerStop()
		self.bannerStop = nil
	end
	self.shownLegend = nil
	for _, stop in ipairs(self.stops) do stop() end
	self.stops = {}
end

function Crates2:isOpen(): boolean
	return self.root.Visible
end

function Crates2:testDrive()
	local f = self.R:FindFirstChild("TestDrive") :: RemoteFunction?
	local ok, res = pcall(function() return f and f:InvokeServer() end)
	if ok and type(res) == "table" and res.ok then
		local t = Game.TyresById[res.tyre]
		Kit.callout(self.gui, ("TEST DRIVE: %s on your next launch"):format(t and t.name or ""), C.yellow, UDim2.fromScale(0.5, 0.15), 34)
		self:tickBanner()
	elseif ok and type(res) == "table" and res.err then
		Kit.callout(self.gui, res.err, C.red, UDim2.fromScale(0.5, 0.15), 28)
	end
end

function Crates2:openCrate(zoneId: string, pay: string, count: number?)
	if self.busy then return end
	self.busy = true
	local n = count or self.count
	local ok, res = pcall(function() return (self.R :: any).OpenCrate:InvokeServer(zoneId, n, pay) end)
	if not (ok and type(res) == "table" and res.ok) then
		self.busy = false
		local which = if n > 1 then "three" else "one"
		if self.openBtns[which] then Kit.shake(self.openBtns[which].root, 6, 0.25) end
		if ok and type(res) == "table" and res.err then
			Kit.callout(self.gui, res.err, C.red, UDim2.fromScale(0.5, 0.15), 30)
		end
		return
	end
	self:close()
	self:reveal(zoneId, res.got, pay, n)
end

--==============================================================
-- the opening
--==============================================================
local SHUTTER = "rbxassetid://110040308815604"
local SPOT = "rbxassetid://119243950784301"

-- one bay: builds it shut, returns the function that plays its opening (blocking) and the stop
local function makeBay(stage: Frame, x: UDim2, got, pace: { k: number })
	local tyre = Game.TyresById[got.id]
	local rar = Game.RaritiesById[tyre.rarity]
	local rank = RARITY_ORDER[tyre.rarity]
	local special = rank >= RARITY_ORDER.Epic
	local mythic = rank >= RARITY_ORDER.Mythic
	local mut = got.mut and Game.MutationsById[got.mut]
	local holder = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = x, Size = UDim2.fromOffset(260, 260),
		BackgroundTransparency = 1, ZIndex = 62, Parent = stage,
	})
	local well = Kit.slot(holder, Kit.NEUTRAL, 62)
	local edgeArt = well:FindFirstChild("EdgeArt") :: ImageLabel
	local wash = well:FindFirstChild("Wash") :: ImageLabel
	wash.ImageTransparency = 1
	local bay = UI.mk("Frame", {
		Position = UDim2.fromOffset(9, 9), Size = UDim2.new(1, -18, 1, -18), BackgroundTransparency = 1, ClipsDescendants = true,
		ZIndex = 63, Parent = holder,
	}, { UI.corner(12) })
	local flood = UI.mk("ImageLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Kit.Art.glow, ImageColor3 = rar.color, ImageTransparency = 1,
		ZIndex = 63, Parent = bay,
	})
	UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromScale(0.85, 0.24), BackgroundTransparency = 1,
		Image = SPOT, ZIndex = 64, Parent = bay,
	})
	local vp, stop = Crates2.tyreViewport(bay, UDim2.fromOffset(230, 230), got.id)
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.3)
	vp.ImageTransparency = 1
	vp.ZIndex = 65
	local shutter = UI.mk("ImageLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = SHUTTER, ScaleType = Enum.ScaleType.Stretch, ZIndex = 66, Parent = bay,
	})
	local function slow(t: number) task.wait(t * pace.k) end
	-- every bay rattles from the start; each opens on its turn (`wait` in), the rare ones last
	local function play(wait: number)
		local rattle = wait + 0.5 + 0.12 * rank + (special and 0.35 or 0)
		local hard = 1 + 0.3 * rank
		local tt = 0
		local last = os.clock()
		local conn = RunService.RenderStepped:Connect(function()
			local now = os.clock()
			tt += (now - last) / pace.k
			last = now
			local t = tt
			local k = math.clamp(t / rattle, 0, 1) ^ 1.5
			local jump = math.abs(math.sin(t * (18 + 26 * k))) * (1.5 + 3.5 * k) * hard
			shutter.Position = UDim2.fromOffset(math.sin(t * 61) * 0.8 * k * hard, -jump)
			holder.Rotation = math.sin(t * (30 + 40 * k)) * 0.6 * k * (special and 1.6 or 1)
		end)
		while tt < rattle do RunService.RenderStepped:Wait() end
		conn:Disconnect()
		holder.Rotation = 0
		shutter.Position = UDim2.new()
		Kit.tween(shutter, 0.5, { Position = UDim2.fromScale(0, -1.02) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		slow(0.16)
		Kit.tween(edgeArt, 0.3, { ImageColor3 = rar.color })
		Kit.tween(wash, 0.3, { ImageTransparency = 0.25 })
		flood.ImageTransparency = 0.05
		Kit.tween(flood, 0.6, { ImageTransparency = 0.55 })
		if special then Kit.shake(stage, mythic and 14 or 8, 0.3) end
		if mythic then
			local flash = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rar.color, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 61, Parent = stage })
			Kit.tween(flash, 0.5, { BackgroundTransparency = 1 })
			task.delay(0.55, function() flash:Destroy() end)
		end
		Kit.pop(holder, 1.08, 0.3)
		Kit.tween(vp, 0.15, { ImageTransparency = 0 })
		Kit.tween(vp, 0.6, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
		slow(0.35)
		-- what it is, under the bay
		local function under(text: string, size: number, color: Color3, dy: number, font: Font?)
			local l = Kit.text(text, size, color, 2.5, font)
			l.AnchorPoint = Vector2.new(0.5, 0)
			l.Position = x + UDim2.fromOffset(0, 136 + dy)
			l.Size = UDim2.fromOffset(300, size + 6)
			Kit.fit(l, size, 10)
			l.ZIndex = 66
			l.Parent = stage
			Kit.appear(l, 0.04, 10)
		end
		under(string.upper(rar.id), 30, rar.color, 0)
		under(tyre.name, 22, C.white, 36)
		under(("x%s CASH"):format(Game.multText(Game.tyreMult(tyre.id, 0, got.mut))), 18, C.gold, 64, Kit.Body)
		if mut then
			local badge = Kit.plate(stage, mut.name .. "  x" .. Game.multText(mut.mult), mut.color, x + UDim2.fromOffset(40, -150), UDim2.fromOffset(130, 32), 68)
			badge.Rotation = 0
			Kit.pop(badge, 1.8, 0.22)
		end
	end
	return play, stop, holder, rank
end

function Crates2:reveal(zoneId: string, gots, pay: string, count: number)
	local pace = { k = workspace:GetAttribute("KitSlow") or 1 }
	local outer = self.stage
	outer:ClearAllChildren()
	outer.Visible = true
	outer.BackgroundTransparency = 1
	Kit.tween(outer, 0.25, { BackgroundTransparency = 0.12 })
	-- everything in one box that scales with the screen
	local stage = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1000, 640),
		BackgroundTransparency = 1, ZIndex = 61, Parent = outer,
	})
	UI.autoScale(stage, 1280, 760)
	-- a tap anywhere hurries the opening along
	local hurry = UI.mk("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 60, Parent = outer })
	hurry.Activated:Connect(function() pace.k = math.min(pace.k, 0.25) end)
	local zone = Game.ZonesById[zoneId]
	Kit.plate(stage, zone.name .. " Crate" .. (#gots > 1 and (" x" .. #gots) or ""), Kit.NEUTRAL, UDim2.new(0.5, -120, 0, 40), UDim2.fromOffset(240, 34), 67)
	local skip = Kit.text("Tap to hurry", 14, C.muted, 1.5, Kit.Body)
	skip.AnchorPoint = Vector2.new(0.5, 0)
	skip.Position = UDim2.new(0.5, 0, 0, 78)
	skip.Size = UDim2.fromOffset(200, 18)
	skip.ZIndex = 67
	skip.Parent = stage
	local stops = {}
	local bays = {}
	local n = #gots
	for i, got in ipairs(gots) do
		local dx = (i - (n + 1) / 2) * 300
		local play, stop, holder, rank = makeBay(stage, UDim2.new(0.5, dx, 0, 250), got, pace)
		table.insert(bays, { play = play, holder = holder, rank = rank, i = i })
		table.insert(stops, stop)
	end
	task.wait(0.3 * pace.k)
	-- the rarest opens last; the rest left to right
	local order = table.clone(bays)
	table.sort(order, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.i < b.i
	end)
	local left = #order
	for turn, b in ipairs(order) do
		task.spawn(function()
			b.play((turn - 1) * 0.45)
			left -= 1
		end)
	end
	while left > 0 do task.wait() end
	skip.Visible = false
	hurry:Destroy()
	-- the best pull of a multi-open gets the spotlight
	if n > 1 then
		local top = order[#order]
		Kit.pop(top.holder, 1.12, 0.35)
	end
	local again = Kit.button("Open Again", C.accent, UDim2.fromOffset(260, 58), 21)
	again.root.AnchorPoint = Vector2.new(1, 0)
	again.root.Position = UDim2.new(0.5, -10, 0, 530)
	again.root.ZIndex = 68
	again.root.Parent = stage
	local done = Kit.button("Done", C.green, UDim2.fromOffset(200, 58), 22)
	done.root.Position = UDim2.new(0.5, 10, 0, 530)
	done.root.ZIndex = 68
	done.root.Parent = stage
	Kit.appear(again.root, 0.2, 20)
	Kit.appear(done.root, 0.28, 20)
	local function finish()
		for _, stop in ipairs(stops) do stop() end
		Kit.tween(outer, 0.2, { BackgroundTransparency = 1 })
		stage.Visible = false
		task.delay(0.2, function()
			outer.Visible = false
			outer:ClearAllChildren()
			self.busy = false
		end)
	end
	done.onClick = finish
	again.onClick = function()
		finish()
		task.delay(0.3, function() self:openCrate(zoneId, pay, count) end)
	end
	local p = self.profile
	local v = p and p.v2
	local can = false
	if v and p then
		if pay == "keys" then can = v.keys >= Game.cratePrice(zoneId) * count
		else can = p.credits >= Game.crateCash(zoneId, v.tier) * count end
	end
	again.setEnabled(can)
end

return Crates2
