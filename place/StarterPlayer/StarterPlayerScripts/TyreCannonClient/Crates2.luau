--!strict
-- TYRE CANNON :: Crates2 (v4, after the gacha research in docs/CRATE_RESEARCH.md)
-- The crate screen is the banner:
--   top      a tab a crate (Backroad, Highway, Dunes): its picture, its name, its price; one you
--            haven't reached is locked and says how far it is. Your keys on the right.
--   banner   the crate big on a stage lit in its zone's colour, its own tyres circling slowly behind
--            it, its name and the clock to the next banner; the featured Legendary on a big gold card
--            with Test Drive (one free run a banner)
--   bottom   the pity (always on: Legendary guaranteed in N, counted apart for cash and key crates),
--            pay with cash or keys, DROP RATES (every outcome and its chance, in a popup: shown
--            before you buy, as Roblox's paid-random-items rules ask), and two big buttons, OPEN 1
--            and OPEN 10 (one of the ten is always Rare or better), the price on each
-- The opening (full screen): the crate slams down and rattles harder and harder, glowing white;
-- it bursts in a flash and a shockwave, and only then does the light take the colour of the best
-- thing in it (the tell comes late, so the suspense holds); a Legendary or better gets a slow-
-- motion hold, a gold wash and its own banner first. One crate: its card flies in big. Ten: ten
-- face-down cards are dealt into a grid and flip over one after another, rarest last, a rare one
-- with a pause and a flash. SKIP turns them all at once; a tap hurries it. Then: OPEN AGAIN (the
-- same way), AUTO (keeps opening while you can pay), DONE.
--   Crates2.new(gui, remotes) -> crates ; crates:setProfile(p) ; crates:open() ; crates.stage

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Game = require(Modules.Game)
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local TyreLook = require(script.Parent.TyreLook)
local TyreShow = require(script.Parent.TyreShow)
local Sound = require(script.Parent.Sound)
local C = Kit.C

local Crates2 = {}
Crates2.__index = Crates2

local W, H = 1160, 660            -- the screen's card
local SW, SH = 1116, 470           -- the banner stage inside it
local CX, CY = 330, 200            -- the crate's middle on the stage

-- a spinning tyre in a viewport (for a tyre without a studio picture yet)
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

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	return ("%d:%02d:%02d"):format(sec // 3600, (sec % 3600) // 60, sec % 60)
end

-- each crate's look: its colour, its tab picture (plain) and its hero picture (with its light)
-- what a locked crate's contents are drawn in: a near-black silhouette
local SHADOW = Color3.fromRGB(16, 16, 22)

local ZONE_LOOK = {
	backroad = { color = Color3.fromRGB(150, 205, 60), icon = Kit.Icon.crate_backroad, big = (Kit.Icon :: any).crateBig_backroad },
	highway = { color = Color3.fromRGB(255, 128, 40), icon = Kit.Icon.crate_highway, big = (Kit.Icon :: any).crateBig_highway },
	dunes = { color = Color3.fromRGB(176, 112, 240), icon = Kit.Icon.crate_dunes, big = (Kit.Icon :: any).crateBig_dunes },
}

-- a tyre's picture in a box (its studio render, or a turning model when it has none yet)
local function tyrePic(parent: Instance, id: string, size: number, pos: UDim2, z: number): GuiObject
	local g = TyreShow.thumb(parent, id, true, UDim2.fromOffset(size, size), pos)
	g.ZIndex = z
	return g
end

local function text(t: string, size: number, color: Color3, stroke: number, parent: Instance, pos: UDim2, box: UDim2, z: number, anchor: Vector2?, font: Font?): TextLabel
	local l = Kit.text(t, size, color, stroke, font)
	l.AnchorPoint = anchor or Vector2.new(0, 0)
	l.Position = pos
	l.Size = box
	Kit.fit(l, size, 8)
	l.ZIndex = z
	l.Parent = parent
	return l
end

--==============================================================
-- the screen
--==============================================================
function Crates2.new(gui: ScreenGui, remotes: Instance)
	local self = setmetatable({}, Crates2)
	self.gui = gui
	self.R = remotes
	self.zone = "backroad"
	self.pay = "cash"
	self.auto = false
	local root = UI.mk("Frame", {
		Name = "Crates2", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(W, H),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.root = root
	local holder, face = Kit.card(UDim2.fromOffset(W, H - 16), C.cream, 22, 9)
	holder.Parent = root
	Kit.header(face, "Crates", C.purple, 56)
	local close = Kit.close(52)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, 12, 0, -14)
	close.root.ZIndex = 40
	close.root.Parent = root
	close.onClick = function() self:close() end
	-- your keys, top right
	local keyChip, keyText = Kit.chip(Kit.Icon.key, nil, 120)
	keyChip.AnchorPoint = Vector2.new(1, 0.5)
	keyChip.Position = UDim2.new(1, -66, 0, 8)
	keyChip.ZIndex = 9
	keyChip.Parent = face
	for _, d in ipairs(keyChip:GetDescendants()) do
		if d:IsA("GuiObject") then d.ZIndex = math.max(d.ZIndex, 9) end
	end
	self.keysText = keyText

	---------------------------------------------------------------
	-- the tabs: a strip of crates along the top
	---------------------------------------------------------------
	self.tabs = {}
	for i, z in ipairs(Game.Zones) do
		local look = ZONE_LOOK[z.id]
		local b = UI.mk("TextButton", {
			Name = z.id, Position = UDim2.fromOffset(22 + (i - 1) * 262, 56), Size = UDim2.fromOffset(250, 70),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 5, Parent = face,
		})
		local inner = UI.mk("Frame", { Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5, Parent = b })
		local frame = Kit.slice("tile", look.color, inner, 5, 0.3)
		local pic = UI.mk("ImageLabel", {
			Name = "Crate", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(40, 35), Size = UDim2.fromOffset(66, 66),
			BackgroundTransparency = 1, Image = look.icon, ZIndex = 8, Parent = inner,
		})
		local name = text(string.upper(z.name), 20, C.white, 2.5, inner, UDim2.fromOffset(78, 12), UDim2.fromOffset(160, 24), 9)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local status = text("", 14, C.gold, 2, inner, UDim2.fromOffset(78, 38), UDim2.fromOffset(160, 18), 9, nil, Kit.Body)
		status.TextXAlignment = Enum.TextXAlignment.Left
		local lock = UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(40, 35), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1,
			Image = Kit.Icon.lock, ZIndex = 10, Visible = false, Parent = inner,
		})
		b.MouseEnter:Connect(function()
			if self.zone ~= z.id then Kit.tween(inner, 0.14, { Position = UDim2.fromOffset(0, -4) }, Enum.EasingStyle.Back) end
		end)
		b.MouseLeave:Connect(function()
			Kit.tween(inner, 0.14, { Position = UDim2.fromOffset(0, if self.zone == z.id then -6 else 0) })
		end)
		b.Activated:Connect(function() self:selectZone(z.id) end)
		self.tabs[z.id] = { button = b, inner = inner, frame = frame, status = status, lock = lock, crate = pic, name = name }
	end

	---------------------------------------------------------------
	-- the banner
	---------------------------------------------------------------
	local banner = UI.mk("Frame", { Position = UDim2.fromOffset(22, 136), Size = UDim2.fromOffset(SW, SH + 16), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
	self.bannerRing = Kit.slice("panel_ring", C.purple, banner, 5, 0.4)
	local stage = UI.mk("Frame", {
		Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(SW - 16, SH), BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true,
		ZIndex = 5, Parent = banner,
	}, { UI.corner(10) })
	self.stageGrad = UI.mk("UIGradient", { Rotation = 90, Parent = stage })
	self.stageGlow = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CX, CY), Size = UDim2.fromOffset(560, 560), BackgroundTransparency = 1,
		Image = Kit.Art.radial, ImageTransparency = 0.25, ZIndex = 5, Parent = stage,
	})
	self.carousel = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6, Parent = stage })
	self.carouselItems = {}
	self.bannerTitle = text("", 36, C.white, 3, stage, UDim2.fromOffset(24, 14), UDim2.fromOffset(520, 42), 12)
	self.bannerTitle.TextXAlignment = Enum.TextXAlignment.Left
	self.bannerClock = text("", 15, C.white, 1.5, stage, UDim2.fromOffset(26, 56), UDim2.fromOffset(400, 18), 12, nil, Kit.Body)
	self.bannerClock.TextXAlignment = Enum.TextXAlignment.Left
	self.bigCrate = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CX, CY + 10), Size = UDim2.fromOffset(320, 320), BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit, ZIndex = 9, Parent = stage,
	})
	Kit.bob(self.bigCrate, 5, 1.8)
	-- (2026-10-24, the owner: "the fog shouldn't just be there, the actual crates and tyres should be
	-- darkened so you DON'T know what's in there until you've unlocked it") a crate you haven't
	-- reached: the stage as it is, but the crate, its tyres and its Legendary are black silhouettes
	-- (Crates2:shade), the names hidden; a padlock and how far it is under the crate
	local veil = UI.mk("Frame", { Name = "Locked", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Visible = false, ZIndex = 30, Parent = stage })
	local padlock = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CX, CY + 20), Size = UDim2.fromOffset(92, 92),
		BackgroundTransparency = 1, Image = Kit.Icon.lock, ZIndex = 33, Parent = veil,
	})
	self.lockQ = padlock
	self.lockText = text("", 22, C.white, 2.5, veil, UDim2.fromOffset(CX - 250, CY + 110), UDim2.fromOffset(500, 28), 33)
	self.lockVeil = veil
	game:GetService("RunService").RenderStepped:Connect(function()
		if not veil.Visible or not self.root.Visible then return end
		padlock.Rotation = math.sin(os.clock() * 1.3) * 5
	end)
	-- the featured Legendary: a big gold card, Test Drive under it
	local gold = Game.RaritiesById.Legendary.color
	local feat = UI.mk("Frame", { Position = UDim2.fromOffset(SW - 16 - 290, 50), Size = UDim2.fromOffset(250, 238), BackgroundTransparency = 1, ZIndex = 8, Parent = stage })
	Kit.slice("tile", gold, feat, 8, 0.4)
	UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.fromOffset(240, 240), BackgroundTransparency = 1,
		Image = Kit.Art.radial, ImageColor3 = gold, ImageTransparency = 0.4, ZIndex = 9, Parent = feat,
	})
	self.bannerBay = feat
	Kit.plate(stage, "Featured Legendary", gold, UDim2.fromOffset(SW - 16 - 275, 36), UDim2.fromOffset(220, 28), 12)
	self.featName = text("", 22, C.white, 2.5, feat, UDim2.new(0.5, 0, 1, -54), UDim2.fromOffset(230, 26), 12, Vector2.new(0.5, 0))
	self.featRate = text("", 14, gold, 2, feat, UDim2.new(0.5, 0, 1, -28), UDim2.fromOffset(230, 18), 12, Vector2.new(0.5, 0), Kit.Body)
	local test = Kit.button("Test Drive", C.yellow, UDim2.fromOffset(250, 40), 16)
	test.root.Position = UDim2.fromOffset(SW - 16 - 290, 296)
	test.root.ZIndex = 12
	test.root.Parent = stage
	test.onClick = function() self:testDrive() end
	self.testBtn = test

	---------------------------------------------------------------
	-- the bottom of the banner: the pity, how you pay, the rates, the two buttons
	---------------------------------------------------------------
	local by = SH - 96
	self.pityText = text("", 15, C.white, 2, stage, UDim2.fromOffset(24, by), UDim2.fromOffset(330, 20), 12, nil, Kit.Body)
	self.pityText.TextXAlignment = Enum.TextXAlignment.Left
	local ptrack, pfill = Kit.bar(330, 18, gold, "change")
	ptrack.Position = UDim2.fromOffset(24, by + 26)
	ptrack.ZIndex = 12
	ptrack.Parent = stage
	self.pityFill = pfill
	self.pitySub = text("", 12, C.white, 1.5, stage, UDim2.fromOffset(24, by + 50), UDim2.fromOffset(330, 16), 12, nil, Kit.Body)
	self.pitySub.TextXAlignment = Enum.TextXAlignment.Left
	self.pitySub.TextTransparency = 0.25
	local paySeg, setPay = Kit.segment({ { id = "cash", label = "Cash" }, { id = "keys", label = "Keys" } }, "cash", 104, 34, function(id)
		self.pay = id
		self:refreshPay()
	end)
	paySeg.Position = UDim2.fromOffset(380, by)
	paySeg.ZIndex = 12
	paySeg.Parent = stage
	self.setPay = setPay
	local rates = Kit.button("Drop Rates", C.grey, UDim2.fromOffset(216, 36), 16)
	rates.root.Position = UDim2.fromOffset(380, by + 42)
	rates.root.ZIndex = 12
	rates.root.Parent = stage
	rates.onClick = function() self:showRates() end
	local function openBtn(x: number, n: number, label: string)
		local b = Kit.button(label, C.green, UDim2.fromOffset(228, 78), 26)
		b.root.Position = UDim2.fromOffset(x, by - 2)
		b.root.ZIndex = 12
		b.root.Parent = stage
		b.onClick = function() self:openCrate(self.zone, self.pay, n) end
		local h = b.root:FindFirstChild("Holder") :: Frame
		b.label.Position = UDim2.new(0.5, 0, 0.5, -12)
		b.label.Size = UDim2.new(1, -28, 0, 30)
		local row = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 6), Size = UDim2.fromOffset(160, 24), BackgroundTransparency = 1, ZIndex = 5, Parent = h })
		UI.mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), Parent = row })
		local coin = UI.mk("ImageLabel", { Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Image = Kit.Icon.cash, ZIndex = 5, LayoutOrder = 1, Parent = row })
		local price = Kit.text("", 19, C.white, 2)
		price.AutomaticSize = Enum.AutomaticSize.X
		price.Size = UDim2.fromOffset(0, 24)
		price.ZIndex = 5
		price.LayoutOrder = 2
		price.Parent = row
		;(b :: any).setPrice = function(t: string, keys: boolean)
			price.Text = t
			coin.Image = if keys then Kit.Icon.key else Kit.Icon.cash
		end
		return b
	end
	local N = Game.Crate.Multi
	self.openBtns = { one = openBtn(SW - 16 - 476, 1, "Open 1"), many = openBtn(SW - 16 - 240, N, ("Open %d"):format(N)) }
	-- the big open's promise, a ribbon on its corner
	local ribbon = Kit.plate(self.openBtns.many.root, "Rare+ inside", C.purple, UDim2.new(0.5, -58, 0, -16), UDim2.fromOffset(116, 24), 14)
	ribbon.Rotation = -3

	-- the drop rates (a popup) and the opening (full screen)
	self.ratesBox = nil
	local overlay = UI.mk("Frame", { Name = "CrateStage", Size = UDim2.new(1, 0, 1, 120), Position = UDim2.fromOffset(0, -60), BackgroundColor3 = Color3.fromRGB(8, 8, 10), BackgroundTransparency = 1, Visible = false, ZIndex = 60, Parent = gui })
	self.stage = overlay

	task.spawn(function()
		while root.Parent do
			if root.Visible then self:tickBanner() end
			task.wait(1)
		end
	end)
	-- the carousel behind the crate
	task.spawn(function()
		local t = 0
		while root.Parent do
			local dt = RunService.RenderStepped:Wait()
			if root.Visible then
				t += dt
				local n = #self.carouselItems
				for i, d in ipairs(self.carouselItems) do
					local a = t * 0.2 + (i - 1) / math.max(n, 1) * math.pi * 2
					local depth = (math.sin(a) + 1) / 2
					d.img.Position = UDim2.fromOffset(CX + math.cos(a) * 230, CY + 40 + math.sin(a) * 60 - 34)
					local sz = 60 + depth * 40
					d.img.Size = UDim2.fromOffset(sz, sz)
					d.img.ImageTransparency = 0.7 - depth * 0.4
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
		Kit.tween(t.inner, 0.16, { Position = UDim2.fromOffset(0, on and -6 or 0) }, Enum.EasingStyle.Back)
		t.frame.ImageColor3 = if on then Kit.lift(ZONE_LOOK[zid].color, 0.18) else ZONE_LOOK[zid].color:Lerp(Color3.fromRGB(40, 40, 48), 0.45)
	end
	self.bannerRing.ImageColor3 = look.color
	self.stageGlow.ImageColor3 = look.color
	self.stageGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, look.color:Lerp(Color3.fromRGB(14, 14, 18), 0.45)),
		ColorSequenceKeypoint.new(0.65, look.color:Lerp(Color3.fromRGB(14, 14, 18), 0.82)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 14, 18)),
	})
	self.bigCrate.Image = look.big or look.icon
	if not instant then
		self.bigCrate.Size = UDim2.fromOffset(250, 250)
		Kit.tween(self.bigCrate, 0.4, { Size = UDim2.fromOffset(320, 320) }, Enum.EasingStyle.Back)
	end
	local z = Game.ZonesById[id]
	self.bannerTitle.Text = string.upper(z.name) .. " CRATE"
	-- (its own Legendary on the card: picked again for this crate)
	self.shownLegend = nil
	self:tickBanner()
	self:fillCarousel(id)
	if self.ratesBox and self.ratesBox.Parent then self:showRates() end
	if self.profile then self:setProfile(self.profile) end
end

-- a crate you haven't reached: its crate, its tyres and its Legendary as black silhouettes, the
-- Legendary unnamed (what's in it stays a secret until you get there)
function Crates2:shade()
	local dark = self.locked == true
	local col = if dark then SHADOW else Color3.new(1, 1, 1)
	self.bigCrate.ImageColor3 = col
	for _, d in ipairs(self.carouselItems) do d.img.ImageColor3 = col end
	local f = self.bannerBay and self.bannerBay:FindFirstChild("Featured")
	if f and f:IsA("ImageLabel") then
		f.ImageColor3 = col
	elseif f and f:IsA("ViewportFrame") then
		f.ImageColor3 = col
		f.Ambient = if dark then Color3.new(0, 0, 0) else Color3.fromRGB(170, 170, 180)
		f.LightColor = if dark then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
	end
	if dark then
		self.featName.Text = "???"
	elseif self.featName.Text == "???" then
		self.shownLegend = nil
		self:tickBanner()
	end
end

-- the crate's own tyres circling slowly behind it
function Crates2:fillCarousel(zoneId: string)
	for _, d in ipairs(self.carouselItems) do d.img:Destroy() end
	self.carouselItems = {}
	local i = 0
	for _, t in ipairs(Game.TyresByZone[zoneId] or {}) do
		if TyreShow.Icons[t.id] and i < 8 then
			i += 1
			local img = UI.mk("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Image = TyreShow.Icons[t.id], ScaleType = Enum.ScaleType.Fit,
				ImageTransparency = 1, ImageColor3 = if self.locked then SHADOW else Color3.new(1, 1, 1), ZIndex = 6, Parent = self.carousel,
			})
			table.insert(self.carouselItems, { img = img })
		end
	end
end

-- each tyre in a crate and its chance, cash and keys (keys: Epic and up KeyLuck times); the
-- Secrets as one unnamed entry
function Crates2:odds(zoneId: string)
	local list, kTotal = {}, 0
	local secretCash, secretKw = 0, 0
	for _, e in ipairs(Game.crateOdds(zoneId)) do
		local t = Game.TyresById[e.id]
		if t then
			local kw = e.odds * (if RARITY_ORDER[t.rarity] >= RARITY_ORDER.Epic then Game.Crate.KeyLuck else 1)
			kTotal += kw
			if t.rarity ~= "Secret" then
				table.insert(list, { t = t, cash = e.odds, kw = kw, featured = e.featured })
			else
				secretCash += e.odds
				secretKw += kw
			end
		end
	end
	-- (2026-10-24) the server's rule (Loop roll): with keys the Epic-and-up share is KeyLuck times the
	-- cash share (at most 90%), Rare keeps its share and Common gives up the difference
	local sum, pe, pr = 0, 0, 0
	for _, e in ipairs(Game.crateOdds(zoneId)) do
		local t = Game.TyresById[e.id]
		if t then
			sum += e.odds
			if RARITY_ORDER[t.rarity] >= RARITY_ORDER.Epic then pe += e.odds elseif t.rarity ~= "Common" then pr += e.odds end
		end
	end
	sum = math.max(sum, 1e-9)
	pe, pr = pe / sum, pr / sum
	local we = math.min(0.9, pe * Game.Crate.KeyLuck)
	local wr = math.min(0.95 - we, pr)
	local wc = 1 - we - wr
	local pc = math.max(1e-9, 1 - pe - pr)
	local function keyShare(t, odds: number): number
		local o = odds / sum
		if RARITY_ORDER[t.rarity] >= RARITY_ORDER.Epic then return if pe > 0 then o * we / pe else o end
		if t.rarity ~= "Common" then return if pr > 0 then o * wr / pr else o end
		return o * wc / pc
	end
	local _ = kTotal
	for _, e in ipairs(list) do e.key = keyShare(e.t, e.cash) end
	secretKw = 0
	for _, e in ipairs(Game.crateOdds(zoneId)) do
		local t = Game.TyresById[e.id]
		if t and t.rarity == "Secret" then secretKw += keyShare(t, e.odds) end
	end
	kTotal = 1
	table.sort(list, function(a, b)
		local ra, rb = RARITY_ORDER[a.t.rarity], RARITY_ORDER[b.t.rarity]
		if ra ~= rb then return ra > rb end
		return a.t.num < b.t.num
	end)
	return list, secretCash, secretKw / math.max(kTotal, 1e-9)
end

--==============================================================
-- the drop rates: every outcome and its chance, the way you're paying
--==============================================================
function Crates2:showRates()
	if self.ratesBox then self.ratesBox:Destroy() end
	local keys = self.pay == "keys"
	local box = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(760, 540), BackgroundTransparency = 1, ZIndex = 50, Parent = self.root })
	self.ratesBox = box
	local blocker = UI.mk("TextButton", { Size = UDim2.new(2, 0, 2, 0), Position = UDim2.fromScale(-0.5, -0.5), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, ZIndex = 50, Parent = box })
	local holder, face = Kit.card(UDim2.fromOffset(760, 540), C.cream)
	holder.Parent = box
	for _, d in ipairs(holder:GetDescendants()) do if d:IsA("GuiObject") then d.ZIndex = math.max(d.ZIndex, 51) end end
	holder.ZIndex = 51
	Kit.header(face, "Drop Rates", C.purple, 56)
	local z = Game.ZonesById[self.zone]
	local sub = text(("%s Crate  ·  %s"):format(z.name, if keys then ("paying with keys: Epic and up x%d"):format(Game.Crate.KeyLuck) else "paying with cash"),
		15, if keys then Game.RaritiesById.Legendary.color else C.white, 1.5, face, UDim2.fromOffset(24, 50), UDim2.fromOffset(712, 18), 53, nil, Kit.Body)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	local grid = UI.mk("ScrollingFrame", {
		Position = UDim2.fromOffset(18, 78), Size = UDim2.fromOffset(724, 390), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 5, ScrollBarImageColor3 = C.line, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 53, Parent = face,
	})
	UI.mk("UIGridLayout", { CellSize = UDim2.fromOffset(110, 132), CellPadding = UDim2.fromOffset(9, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = grid })
	UI.mk("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = grid })
	local list, secretCash, secretKey = self:odds(self.zone)
	local function card(order: number, color: Color3, name: string, chance: number, id: string?, featured: boolean?)
		local cell = UI.mk("Frame", { BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 54, Parent = grid })
		Kit.slice("tile", color, cell, 54, 0.3)
		UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(100, 100), BackgroundTransparency = 1,
			Image = Kit.Art.radial, ImageColor3 = color, ImageTransparency = 0.5, ZIndex = 55, Parent = cell,
		})
		if id then
			-- (a crate you haven't reached shows its tyres as silhouettes, unnamed)
			TyreShow.thumb(cell, id, not self.locked, UDim2.fromOffset(74, 74), UDim2.new(0.5, 0, 0, 7)).ZIndex = 56
		else
			text("?", 46, color, 3, cell, UDim2.new(0.5, 0, 0, 44), UDim2.fromOffset(70, 60), 56, Vector2.new(0.5, 0.5))
		end
		if featured then text("★", 18, Game.RaritiesById.Legendary.color, 2, cell, UDim2.fromOffset(6, 4), UDim2.fromOffset(20, 20), 57) end
		local n = text(if self.locked and id then "???" else name, 13, C.white, 1.5, cell, UDim2.new(0.5, 0, 0, 82), UDim2.new(1, -8, 0, 18), 56, Vector2.new(0.5, 0))
		n.TextWrapped = false
		text(pct(chance), 17, color, 2, cell, UDim2.new(0.5, 0, 0, 102), UDim2.new(1, -8, 0, 22), 56, Vector2.new(0.5, 0))
	end
	if secretCash > 0 then card(0, Game.RaritiesById.Secret.color, "Secret", if keys then secretKey else secretCash) end
	for i, e in ipairs(list) do
		card(i, Game.RaritiesById[e.t.rarity].color, e.t.name, if keys then e.key else e.cash, e.t.id, e.featured)
	end
	local foot = text(("Open %d always holds one Rare or better.  Pity: a Legendary is guaranteed after %d key crates or %d cash crates without one.")
		:format(Game.Crate.Multi, Game.Crate.Pity, Game.Crate.CashPity), 13, C.white, 1.5, face, UDim2.fromOffset(24, 478), UDim2.fromOffset(600, 34), 53, nil, Kit.Body)
	foot.TextWrapped = true
	foot.TextXAlignment = Enum.TextXAlignment.Left
	foot.TextTransparency = 0.2
	local x = Kit.close(48)
	x.root.AnchorPoint = Vector2.new(1, 0)
	x.root.Position = UDim2.new(1, 10, 0, -12)
	x.root.ZIndex = 60
	x.root.Parent = box
	local function shut()
		if self.ratesBox == box then self.ratesBox = nil end
		Kit.vanish(box, 0.15, function() box:Destroy() end)
	end
	x.onClick = shut
	blocker.Activated:Connect(shut)
	Kit.pop(box, 0.85, 0.25)
end

-- the switch between cash and keys: the buttons' prices, the pity shown
function Crates2:refreshPay()
	if self.profile then self:setProfile(self.profile) end
	if self.ratesBox and self.ratesBox.Parent then self:showRates() end
end

function Crates2:tickBanner()
	local now = workspace:GetServerTimeNow()
	local ev = Game.eventAt(math.floor(now)).on
	local b = Game.banner(math.floor(now), self.zone)
	local leg = Game.TyresById[b.legendary]
	if b.legendary ~= self.shownLegend then
		-- (counted as shown only once it's drawn: a crate picked while the screen's shut draws it on opening)
		self.shownLegend = if self.root.Visible then b.legendary else nil
		if self.bannerStop then self.bannerStop() end
		self.bannerStop = nil
		local old = self.bannerBay:FindFirstChild("Featured")
		if old then old:Destroy() end
		if self.root.Visible then
			local vp: GuiObject, stop = nil, function() end
			if TyreShow.Icons[b.legendary] then
				vp = TyreShow.thumb(self.bannerBay, b.legendary, true, UDim2.fromOffset(160, 160), UDim2.new(0.5, 0, 0, 14))
			else
				local v
				v, stop = Crates2.tyreViewport(self.bannerBay, UDim2.fromOffset(176, 176), b.legendary)
				v.AnchorPoint = Vector2.new(0.5, 0)
				v.Position = UDim2.new(0.5, 0, 0, 16)
				vp = v
			end
			vp.Name = "Featured"
			vp.ZIndex = 10
			self.bannerStop = function()
				stop()
				vp:Destroy()
			end
		end
	end
	self.featName.Text = leg and leg.name or ""
	local rush = ev and ev.id == "rush"
	self.featRate.Text = if rush then "LEGENDARY RUSH x5" else ("RATE UP x%d"):format(Game.Crate.FeaturedMult)
	self:shade()
	self.bannerClock.Text = ("New banner in %s"):format(clock(b.ends - now))
	-- the Test Drive: one a banner
	local v = self.profile and self.profile.v2
	local span = Game.Crate.BannerHours * 3600
	local used = v and v.testDrive and math.floor(v.testDrive / span) == math.floor(now / span)
	if self.locked then
		-- (a locked crate's Legendary stays a secret: no driving it before you get there)
		self.testBtn.setText("Test Drive: locked")
		self.testBtn.setEnabled(false)
	elseif v and v.testArmed then
		self.testBtn.setText("Ready: next launch")
		self.testBtn.setEnabled(false)
	elseif used then
		self.testBtn.setText("Test Drive used")
		self.testBtn.setEnabled(false)
	else
		self.testBtn.setText("Test Drive: free")
		self.testBtn.setEnabled(true)
	end
end

-- a button you can afford breathes; one you can't sits still and grey
function Crates2:canBuy(b, on: boolean)
	b.setEnabled(on)
	local h = b.root:FindFirstChild("Holder") :: GuiObject
	if on then Kit.breathe(h, 0.025, 2.4) else Kit.still(h) end
end

function Crates2:affordable(zoneId: string, pay: string, n: number): boolean
	local p = self.profile
	local v = p and p.v2
	if not (p and v and v.zones[zoneId]) then return false end
	if pay == "keys" then return v.keys >= Game.cratePrice(zoneId) * n end
	return p.credits >= Game.crateCash(zoneId, v.tier, v) * n
end

function Crates2:setProfile(p)
	self.profile = p
	if not p or not p.v2 then return end
	local v = p.v2
	self.keysText.Text = tostring(v.keys)
	local N = Game.Crate.Multi
	for _, z in ipairs(Game.Zones) do
		local t = self.tabs[z.id]
		local unlocked = v.zones[z.id] == true
		t.lock.Visible = not unlocked
		t.crate.ImageTransparency = 0
		t.crate.ImageColor3 = if unlocked then Color3.new(1, 1, 1) else SHADOW
		t.status.Text = if unlocked then ("$%s a crate"):format(Game.short(Game.crateCash(z.id, v.tier, v))) else ("Reach %s"):format(Game.metres(z.start))
		t.status.TextColor3 = if unlocked then C.gold else C.muted
	end
	local z = self.zone
	local unlocked = v.zones[z] == true
	local b = self.openBtns
	local keys = self.pay == "keys"
	if keys then
		local k1 = Game.cratePrice(z)
		b.one.setPrice(tostring(k1), true)
		b.many.setPrice(tostring(k1 * N), true)
		b.one.setColor(C.purple)
		b.many.setColor(C.purple)
	else
		local c1 = Game.crateCash(z, v.tier, v)
		b.one.setPrice(Game.short(c1), false)
		b.many.setPrice(Game.short(c1 * N), false)
		b.one.setColor(C.green)
		b.many.setColor(C.green)
	end
	self:canBuy(b.one, self:affordable(z, self.pay, 1))
	self:canBuy(b.many, self:affordable(z, self.pay, N))
	-- the pity, whichever way you pay
	local count = if keys then (v.pity or 0) else (v.cashPity or 0)
	local cap = if keys then Game.Crate.Pity else Game.Crate.CashPity
	local left = math.max(1, cap - count)
	self.pityText.Text = ('LEGENDARY GUARANTEED IN <font color="#FFBE3C">%d</font>'):format(left)
	self.pityFill.Size = UDim2.fromScale(math.clamp(count / cap, 0, 1), 1)
	self.lockVeil.Visible = not unlocked
	self.locked = not unlocked
	self:shade()
	self.lockText.Text = ("LOCKED  ·  reach %s"):format(Game.metres(Game.ZonesById[z].start))
	self.pitySub.Text = if not unlocked then ("Reach %s to open this crate"):format(Game.metres(Game.ZonesById[z].start))
		elseif keys then ("Key crates: Epic and up x%d"):format(Game.Crate.KeyLuck) else "Counted for cash crates"
end

function Crates2:open()
	Kit.dim(self.gui or self.root.Parent, self, true)
	-- (2026-10-23) the tutorial says "your key opens a crate": open on Keys then, if a key crate is affordable
	if self.preferKeys then
		self.preferKeys = false
		if self.zone and self.setPay and self:affordable(self.zone, "keys", 1) then
			self.pay = "keys"
			self.setPay("keys")
			self:refreshPay()
		end
	end
	Kit.open(self.root)
	self.shownLegend = nil
	self:tickBanner()
end

function Crates2:close()
	Kit.dim(self.gui or self.root.Parent, self, false)
	if self.ratesBox then
		self.ratesBox:Destroy()
		self.ratesBox = nil
	end
	if self.root.Visible then Kit.close_(self.root) end
	if self.bannerStop then
		self.bannerStop()
		self.bannerStop = nil
	end
	self.shownLegend = nil
end

function Crates2:isOpen(): boolean
	return self.root.Visible
end

function Crates2:testDrive()
	local f = self.R:FindFirstChild("TestDrive") :: RemoteFunction?
	local ok, res = pcall(function() return f and f:InvokeServer(self.zone) end)
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
	local n = count or 1
	local ok, res = pcall(function() return (self.R :: any).OpenCrate:InvokeServer(zoneId, n, pay) end)
	if not (ok and type(res) == "table" and res.ok) then
		self.busy = false
		self.auto = false
		local which = if n > 1 then "many" else "one"
		if self.openBtns[which] then Kit.shake(self.openBtns[which].root, 6, 0.25) end
		if ok and type(res) == "table" and res.err then
			Kit.callout(self.gui, res.err, C.red, UDim2.fromScale(0.5, 0.15), 30)
		end
		return
	end
	if self.root.Visible then self:close() end
	self:reveal(zoneId, res.got, pay, n)
end

--==============================================================
-- the opening
--==============================================================
-- a card face-up: a tyre on its rarity's colours
local function frontOf(card: Frame, got, size: Vector2)
	local tyre = Game.TyresById[got.id]
	local rar = Game.RaritiesById[tyre.rarity]
	local front = UI.mk("Frame", { Name = "Front", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 72, Visible = false, Parent = card })
	Kit.slice("tile", rar.color, front, 72, size.X / 520)
	UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromScale(1.15, 0.95), BackgroundTransparency = 1,
		Image = Kit.Art.radial, ImageColor3 = rar.color, ImageTransparency = 0.35, ZIndex = 73, Parent = front,
	})
	tyrePic(front, got.id, math.floor(size.X * 0.72), UDim2.new(0.5, 0, 0.04, 0), 74)
	local s = size.X / 150
	text(string.upper(rar.id), math.floor(15 * s), rar.color, 2.5, front, UDim2.new(0.5, 0, 0.6, 0), UDim2.new(1, -8, 0, math.floor(18 * s)), 75, Vector2.new(0.5, 0))
	local nm = text(tyre.name, math.floor(14 * s), C.white, 2, front, UDim2.new(0.5, 0, 0.72, 0), UDim2.new(1, -8, 0, math.floor(17 * s)), 75, Vector2.new(0.5, 0))
	nm.TextWrapped = false
	text(("x%s CASH"):format(Game.multText(Game.tyreMult(tyre.id, 0, got.mut))), math.floor(13 * s), C.gold, 2, front, UDim2.new(0.5, 0, 0.84, 0), UDim2.new(1, -8, 0, math.floor(16 * s)), 75, Vector2.new(0.5, 0), Kit.Body)
	local mut = got.mut and Game.MutationsById[got.mut]
	if mut then
		local plate = Kit.plate(front, ("%s x%s"):format(mut.name, Game.multText(mut.mult)), mut.color, UDim2.new(0.5, -math.floor(52 * s), 0, -math.floor(10 * s)), UDim2.fromOffset(math.floor(104 * s), math.floor(22 * s)), 77)
		plate.Rotation = -4
	end
	if got.new then
		local tag = Kit.plate(front, "NEW", C.green, UDim2.new(1, -math.floor(46 * s), 0, math.floor(6 * s)), UDim2.fromOffset(math.floor(42 * s), math.floor(20 * s)), 77)
		tag.Rotation = 8
	end
	return front, rar, RARITY_ORDER[tyre.rarity]
end

-- a card face-down: the crate's colours, a tyre's shadow, a question mark
local function backOf(card: Frame, zoneColor: Color3, size: Vector2)
	local back = UI.mk("Frame", { Name = "Back", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 72, Parent = card })
	Kit.slice("tile", zoneColor:Lerp(Color3.fromRGB(60, 60, 70), 0.35), back, 72, size.X / 520)
	UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.62, 0.5), BackgroundTransparency = 1,
		Image = Kit.Icon.tyre, ImageColor3 = Color3.fromRGB(70, 70, 82), ZIndex = 73, Parent = back,
	})
	text("?", math.floor(size.X * 0.32), Color3.fromRGB(220, 220, 230), 3, back, UDim2.fromScale(0.5, 0.45), UDim2.fromScale(0.6, 0.5), 74, Vector2.new(0.5, 0.5))
	return back
end

-- turn a card over: it narrows to nothing, shows its face, and springs back out
local function flip(card: Frame, back: Frame, front: Frame, fast: boolean)
	local t = if fast then 0.04 else 0.09
	local w = card:GetAttribute("W") :: number
	local h = card.Size.Y.Offset
	local half = Kit.tween(card, t, { Size = UDim2.fromOffset(0, h) })
	half.Completed:Wait()
	back.Visible = false
	front.Visible = true
	Kit.tween(card, t, { Size = UDim2.fromOffset(w, h) }, Enum.EasingStyle.Back)
	task.wait(t)
end

function Crates2:finishReveal()
	local outer = self.stage
	if self.revealConn then self.revealConn:Disconnect() end
	self.revealConn = nil
	Kit.tween(outer, 0.2, { BackgroundTransparency = 1 })
	for _, c in ipairs(outer:GetChildren()) do
		if c:IsA("GuiObject") then c.Visible = false end
	end
	task.delay(0.2, function()
		outer.Visible = false
		outer:ClearAllChildren()
		self.busy = false
	end)
end

function Crates2:reveal(zoneId: string, gots, pay: string, count: number)
	local look = ZONE_LOOK[zoneId]
	local zone = Game.ZonesById[zoneId]
	local outer = self.stage
	outer:ClearAllChildren()
	outer.Visible = true
	outer.BackgroundTransparency = 1
	Kit.tween(outer, 0.25, { BackgroundTransparency = 0.08 })
	local pace = { fast = false }
	local stage = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1280, 760), BackgroundTransparency = 1, ZIndex = 61, Parent = outer,
	})
	UI.autoScale(stage, 1280, 760)
	-- the zone's light behind everything; it takes the best thing's colour at the burst
	local glow = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(900, 900), BackgroundTransparency = 1,
		Image = Kit.Art.radial, ImageColor3 = look.color, ImageTransparency = 0.55, ZIndex = 61, Parent = stage,
	})
	local hurry = UI.mk("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 61, Parent = outer })
	hurry.Activated:Connect(function() pace.fast = true end)
	local skip = Kit.button("Skip", C.grey, UDim2.fromOffset(120, 42), 18)
	skip.root.AnchorPoint = Vector2.new(1, 0)
	skip.root.Position = UDim2.new(1, -30, 0, 30)
	skip.root.ZIndex = 90
	skip.root.Parent = stage
	skip.onClick = function() pace.fast = true end
	Kit.plate(stage, zone.name .. " Crate" .. (if #gots > 1 then (" x" .. #gots) else ""), Kit.NEUTRAL, UDim2.new(0.5, -130, 0, 34), UDim2.fromOffset(260, 36), 80)
	local function wait(t: number) if not pace.fast then task.wait(t) else task.wait(math.min(t, 0.03)) end end

	-- the best thing in it decides the burst (nobody knows it until then)
	local best, bestRank = gots[1], 0
	for _, g in ipairs(gots) do
		local r = RARITY_ORDER[Game.TyresById[g.id].rarity]
		if r > bestRank then best, bestRank = g, r end
	end
	local bestRar = Game.RaritiesById[Game.TyresById[best.id].rarity]
	local legendaryUp = bestRank >= RARITY_ORDER.Legendary
	local epicUp = bestRank >= RARITY_ORDER.Epic

	-- 1 the crate slams down
	local crate = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, -0.3), Size = UDim2.fromOffset(380, 380), BackgroundTransparency = 1,
		Image = look.big or look.icon, ScaleType = Enum.ScaleType.Fit, ZIndex = 66, Parent = stage,
	})
	local heat = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 300), BackgroundTransparency = 1,
		Image = Kit.Art.radial, ImageColor3 = Color3.new(1, 1, 1), ImageTransparency = 1, ZIndex = 65, Parent = stage,
	})
	local fall = Kit.tween(crate, if pace.fast then 0.1 else 0.42, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	fall.Completed:Wait()
	Sound.play("land", { volume = 0.8, pitch = 0.8 })
	Kit.shake(stage, 10, 0.25)
	Kit.pop(crate, 0.82, 0.3)
	wait(0.35)

	-- 2 it rattles, harder and harder, a white light swelling behind it
	local rattle = if #gots > 1 then 1.5 else 1.15
	local t0 = os.clock()
	while true do
		local t = os.clock() - t0
		if t >= rattle or pace.fast then break end
		local k = (t / rattle) ^ 1.6
		crate.Rotation = math.sin(t * (24 + 40 * k)) * (2 + 9 * k)
		crate.Position = UDim2.new(0.5, math.sin(t * 57) * 6 * k, 0.5, -math.abs(math.sin(t * (14 + 20 * k))) * 14 * k)
		heat.ImageTransparency = 1 - 0.85 * k
		heat.Size = UDim2.fromOffset(300 + 260 * k, 300 + 260 * k)
		RunService.RenderStepped:Wait()
	end
	crate.Rotation = 0

	-- 3 the burst: a flash, a ring, and the light of the best thing inside
	local flash = UI.mk("Frame", { Size = UDim2.new(2, 0, 2, 0), Position = UDim2.fromScale(-0.5, -0.5), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.05, BorderSizePixel = 0, ZIndex = 89, Parent = stage })
	Kit.tween(flash, 0.5, { BackgroundTransparency = 1 })
	Kit.tween(crate, 0.25, { Size = UDim2.fromOffset(560, 560), ImageTransparency = 1 })
	heat.ImageTransparency = 1
	local ring = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(120, 120), BackgroundTransparency = 1,
		Image = Kit.Art.radial, ImageColor3 = bestRar.color, ImageTransparency = 0.1, ZIndex = 64, Parent = stage,
	})
	Kit.tween(ring, 0.7, { Size = UDim2.fromOffset(1400, 1400), ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Kit.tween(glow, 0.5, { ImageColor3 = bestRar.color, ImageTransparency = if epicUp then 0.2 else 0.45 })
	-- the sunburst in the best thing's colour (art/ui/burst.py): broad tapered rays one way, fine ones
	-- the other, both soft and fading out from the middle; it breathes a little as it turns
	local function burst(img: string, size: number, z: number, alpha: number)
		local b = UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(size * 0.6, size * 0.6), BackgroundTransparency = 1,
			Image = img, ImageColor3 = bestRar.color, ImageTransparency = 1, ZIndex = z, Parent = stage,
		})
		Kit.tween(b, 0.6, { ImageTransparency = alpha, Size = UDim2.fromOffset(size, size) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		return b
	end
	local broad = burst(Kit.Icon.burst_a, 1500, 62, if epicUp then 0.05 else 0.5)
	local fine = burst(Kit.Icon.burst_b, 1300, 62, if epicUp then 0.25 else 0.68)
	-- the twinkles: four-point stars popping in and out around the cards
	local twinkles = {}
	local rng = Random.new()
	local nextTwinkle = 0
	self.revealConn = RunService.RenderStepped:Connect(function(dt)
		local spin = if legendaryUp then 16 else 7
		broad.Rotation += dt * spin
		fine.Rotation -= dt * spin * 0.6
		local breathe = 1 + math.sin(os.clock() * 2.2) * 0.04
		broad.Size = UDim2.fromOffset(1500 * breathe, 1500 * breathe)
		if os.clock() > nextTwinkle and #twinkles < (if epicUp then 14 else 8) then
			nextTwinkle = os.clock() + rng:NextNumber(0.06, 0.18)
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(240, 480)
			local s = rng:NextNumber(20, if legendaryUp then 64 else 44)
			local tw = UI.mk("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(a) * r * 1.3, 0.48, math.sin(a) * r * 0.8), Size = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1, Image = Kit.Icon.sparkle, ImageColor3 = bestRar.color:Lerp(Color3.new(1, 1, 1), 0.6), Rotation = rng:NextNumber(-20, 20), ZIndex = 63, Parent = stage,
			})
			table.insert(twinkles, tw)
			local life = rng:NextNumber(0.5, 0.9)
			Kit.tween(tw, life * 0.4, { Size = UDim2.fromOffset(s, s) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			task.delay(life * 0.5, function()
				if tw.Parent then Kit.tween(tw, life * 0.5, { Size = UDim2.fromOffset(0, 0), Rotation = tw.Rotation + 45 }) end
			end)
			task.delay(life + 0.05, function()
				local i = table.find(twinkles, tw)
				if i then table.remove(twinkles, i) end
				tw:Destroy()
			end)
		end
	end)
	Sound.play("land", { volume = 1, pitch = if legendaryUp then 0.6 else 1.0 })
	Kit.shake(stage, if legendaryUp then 22 elseif epicUp then 14 else 8, 0.35)
	wait(0.25)
	-- a Legendary or better: a hold, a gold wash, its own banner first
	if legendaryUp and not pace.fast then
		local wash = UI.mk("Frame", { Size = UDim2.new(2, 0, 2, 0), Position = UDim2.fromScale(-0.5, -0.5), BackgroundColor3 = bestRar.color, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 63, Parent = stage })
		Kit.tween(wash, 1.2, { BackgroundTransparency = 1 })
		local word = text(string.upper(bestRar.id) .. "!", 96, bestRar.color, 3, stage, UDim2.fromScale(0.5, 0.45), UDim2.fromOffset(900, 110), 88, Vector2.new(0.5, 0.5))
		Kit.pop(word, 2.2, 0.35)
		Sound.play("cheer", { length = 2.5 })
		Sound.play("medal", { volume = 0.9, pitch = 1.1, length = 1.4 })
		task.wait(1.1)
		Kit.tween(word, 0.25, { TextTransparency = 1, Position = UDim2.fromScale(0.5, 0.3) })
		local st = word:FindFirstChildOfClass("UIStroke")
		if st then Kit.tween(st, 0.25, { Transparency = 1 }) end
		task.wait(0.2)
	end

	-- 4 the cards
	local n = #gots
	if n == 1 then
		local size = Vector2.new(280, 360)
		local card = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(size.X, size.Y), BackgroundTransparency = 1, ZIndex = 72, Parent = stage })
		card:SetAttribute("W", size.X)
		local front, rar = frontOf(card, gots[1], size)
		front.Visible = true
		card.Rotation = -30
		Kit.pop(card, 0.2, 0.45)
		Kit.tween(card, 0.45, { Rotation = 0 }, Enum.EasingStyle.Back)
		Sound.play("gateWhoosh", { volume = 0.5, pitch = 1.4 })
		if RARITY_ORDER[rar.id] >= RARITY_ORDER.Rare then Sound.play("medal", { volume = 0.6, pitch = 1.2, length = 1 }) end
		wait(0.5)
	else
		-- dealt face-down into a grid of five by two
		local size = Vector2.new(180, 234)
		local cols = 5
		local entries = {}
		for i, got in ipairs(gots) do
			local col, row = (i - 1) % cols, (i - 1) // cols
			local target = UDim2.new(0.5, (col - (cols - 1) / 2) * 200, 0.46, (row - 0.5) * 254)
			local card = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size.X, size.Y), BackgroundTransparency = 1, ZIndex = 72, Parent = stage })
			card:SetAttribute("W", size.X)
			local back = backOf(card, look.color, size)
			local front, rar, rank = frontOf(card, got, size)
			card.Rotation = math.random(-25, 25)
			Kit.tween(card, if pace.fast then 0.05 else 0.3, { Position = target, Rotation = 0 }, Enum.EasingStyle.Back)
			table.insert(entries, { card = card, back = back, front = front, rar = rar, rank = rank, i = i })
			if not pace.fast then
				Sound.play("gateWhoosh", { volume = 0.25, pitch = 1.6 + i * 0.03 })
				task.wait(0.06)
			end
		end
		wait(0.45)
		-- turned over rarest last; a rare one waits a beat and flashes
		local order = table.clone(entries)
		table.sort(order, function(a, b)
			if a.rank ~= b.rank then return a.rank < b.rank end
			return a.i < b.i
		end)
		for _, e in ipairs(order) do
			local rare = e.rank >= RARITY_ORDER.Epic
			if rare and not pace.fast then
				Kit.shake(e.card, 6, 0.35)
				task.wait(0.35)
			end
			flip(e.card, e.back, e.front, pace.fast)
			if e.rank >= RARITY_ORDER.Rare and not pace.fast then
				local f = UI.mk("ImageLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = e.card.Position, Size = UDim2.fromOffset(160, 160), BackgroundTransparency = 1,
					Image = Kit.Art.radial, ImageColor3 = e.rar.color, ImageTransparency = 0.05, ZIndex = 71, Parent = stage,
				})
				Kit.tween(f, 0.6, { Size = UDim2.fromOffset(420, 420), ImageTransparency = 1 })
				task.delay(0.65, function() f:Destroy() end)
				Sound.play("medal", { volume = 0.35 + 0.1 * e.rank, pitch = 0.9 + 0.08 * e.rank, length = 0.8 })
				Kit.pop(e.card, 1.18, 0.3)
			end
			if not pace.fast then task.wait(if rare then 0.25 else 0.1) end
		end
	end
	skip.root.Visible = false
	hurry:Destroy()

	-- 5 what now: again, auto, done
	local again = Kit.button("Open Again", C.accent, UDim2.fromOffset(250, 60), 22)
	again.root.AnchorPoint = Vector2.new(1, 0)
	again.root.Position = UDim2.new(0.5, -90, 0, 660)
	again.root.ZIndex = 85
	again.root.Parent = stage
	local auto = Kit.button(if self.auto then "Auto: on" else "Auto: off", if self.auto then C.yellow else C.grey, UDim2.fromOffset(160, 60), 20)
	auto.root.AnchorPoint = Vector2.new(0.5, 0)
	auto.root.Position = UDim2.new(0.5, 0, 0, 660)
	auto.root.ZIndex = 85
	auto.root.Parent = stage
	local done = Kit.button("Done", C.green, UDim2.fromOffset(220, 60), 22)
	done.root.Position = UDim2.new(0.5, 90, 0, 660)
	done.root.ZIndex = 85
	done.root.Parent = stage
	Kit.appear(again.root, 0.05, 20)
	Kit.appear(auto.root, 0.1, 20)
	Kit.appear(done.root, 0.15, 20)
	local can = self:affordable(zoneId, pay, count)
	again.setEnabled(can)
	local closing = false
	local function nextOne()
		self:finishReveal()
		task.delay(0.3, function() self:openCrate(zoneId, pay, count) end)
	end
	done.onClick = function()
		closing = true
		self.auto = false
		self:finishReveal()
	end
	again.onClick = function()
		if closing then return end
		closing = true
		nextOne()
	end
	auto.onClick = function()
		self.auto = not self.auto
		auto.setText(if self.auto then "Auto: on" else "Auto: off")
		auto.setColor(if self.auto then C.yellow else C.grey)
		if self.auto and can and not closing then
			closing = true
			task.delay(0.4, nextOne)
		end
	end
	-- auto: on to the next one after a moment, while you can pay
	if self.auto then
		if can then
			task.delay(1.4, function()
				if self.auto and not closing and outer.Visible then
					closing = true
					nextOne()
				end
			end)
		else
			self.auto = false
			auto.setText("Auto: off")
			auto.setColor(C.grey)
			Kit.callout(self.gui, "Auto stopped: not enough to open another", C.red, UDim2.fromScale(0.5, 0.12), 24)
		end
	end
end

return Crates2
