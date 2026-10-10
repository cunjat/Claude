--!strict
-- TYRE CANNON :: Workbench
-- Where you look after your tyres: the selected tyre on its stand, clean (no dust, no lamp haze).
--   left     the selected tyre on the bench, turning slowly, stickers and all; its name, rarity, what it
--            does, and a FAV pill (a favourite sorts first and is never used up by a Fuse)
--   Tyres    organize: sort by best, rarity, newest or name; show only favourites; pick one
--   Stickers dress the selected tyre: the bay grows and the tyre comes forward; pick a sticker from
--            the pack (or click one on the tyre) and the view closes in on the sidewall, face-on, the
--            sticker outlined; drag it round the wheel with the mouse (or a finger), scroll over it to
--            size it, or use the sliders (round, out, size, turn, both sides); up to
--            Config.Stickers.MaxPerTyre; Save keeps it (it goes on the tyre in your runs too), lets
--            the sticker go and leaves the tyre turning. Out of the close view, drag to turn the tyre
--   Workbench.new(gui, remotes) · :setProfile(p) · :open() · :close() · :isOpen()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Game = require(Modules.Game)
local Config = require(Modules.Config)
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local TyreShow = require(script.Parent.TyreShow)
local TyreSticker = require(script.Parent.TyreSticker)
local Tyres2 = require(script.Parent.Tyres2)
local C = Kit.C

local Workbench = {}
Workbench.__index = Workbench

local SORTS = {
	{ id = "best", label = "Best" },
	{ id = "rarity", label = "Rarity" },
	{ id = "newest", label = "Newest" },
	{ id = "name", label = "A-Z" },
}
local RANK = {}
for i, r in ipairs(Game.Rarities) do RANK[r.id] = i end
local MAX_STICKERS = Config.Stickers.MaxPerTyre

--==============================================================
-- dust in the lamplight: soft motes drifting up through the stage, twinkling, wrapping round
--==============================================================
local function dust(parent: Instance, count: number)
	local layer = UI.mk("Frame", { Name = "Dust", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 14, Parent = parent })
	local motes = {}
	for i = 1, count do
		local size = 3 + math.random() * 6
		local m = UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Image = Kit.Art.glow,
			ImageColor3 = Color3.fromRGB(255, 226, 170), ImageTransparency = 0.6, ZIndex = 14, Parent = layer,
		})
		table.insert(motes, {
			ui = m, x = math.random(), y = math.random(), vx = (math.random() - 0.5) * 0.02, vy = -(0.012 + math.random() * 0.03),
			phase = math.random() * 6.28, rate = 0.6 + math.random() * 1.6, base = 0.5 + math.random() * 0.35,
		})
	end
	local t = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		if not layer.Visible or not layer.Parent then return end
		t += dt
		for _, m in ipairs(motes) do
			m.x += (m.vx + math.sin(t * 0.7 + m.phase) * 0.012) * dt
			m.y += m.vy * dt
			if m.y < -0.05 then m.y, m.x = 1.05, math.random() end
			if m.x < -0.05 then m.x = 1.05 elseif m.x > 1.05 then m.x = -0.05 end
			m.ui.Position = UDim2.fromScale(m.x, m.y)
			m.ui.ImageTransparency = m.base + math.sin(t * m.rate + m.phase) * 0.22
		end
	end)
	layer.Destroying:Connect(function() conn:Disconnect() end)
	return layer
end

function Workbench.new(gui: ScreenGui, remotes: Instance)
	local self = setmetatable({}, Workbench)
	self.gui = gui
	self.R = remotes
	self.tab = "tyres"
	self.sort = "best"
	self.favOnly = false
	self.packFilter = nil
	self.stickers = {} :: { any }
	self.selSticker = nil :: number?
	self.dirty = false
	local root = UI.mk("Frame", {
		Name = "Workbench", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(960, 580),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.root = root
	local holder, face = Kit.card(UDim2.fromOffset(960, 570), C.cream)
	holder.Parent = root
	Kit.header(face, "Workbench", C.orange, 60)
	local close = Kit.close(54)
	close.root.AnchorPoint = Vector2.new(0.5, 0.5)
	close.root.Position = UDim2.new(1, -8, 0, 8)
	close.root.ZIndex = 40
	close.root.Parent = root
	close.onClick = function() self:close() end
	self.face = face

	---------------------------------------------------------------
	-- the bench: the tyre under the lamp
	---------------------------------------------------------------
	self.stand = TyreShow.stand(face, UDim2.fromOffset(324, 300))
	self.stand.root.Position = UDim2.fromOffset(26, 50)
	self.stand.root.ZIndex = 6
	local _ = dust
	self:buildStickerPad()
	self.dName = Kit.text("", 26, C.text, 2)
	self.dName.Position = UDim2.fromOffset(26, 358)
	self.dName.Size = UDim2.fromOffset(324, 32)
	Kit.fit(self.dName, 26, 14)
	self.dName.ZIndex = 7
	self.dName.Parent = face
	local plate, plateText = Kit.plate(face, "", C.grey, UDim2.fromOffset(26, 394), UDim2.fromOffset(120, 26), 7)
	self.dPlate, self.dPlateText = plate, plateText
	local fav = Kit.button("Favourite", C.grey, UDim2.fromOffset(190, 34), 16)
	fav.root.Position = UDim2.fromOffset(160, 390)
	fav.root.ZIndex = 8
	fav.root.Parent = face
	fav.onClick = function() self:toggleFav() end
	self.favBtn = fav
	self.dInfo = Kit.text("", 15, C.gold, 1.5, Kit.Body)
	self.dInfo.Position = UDim2.fromOffset(32, 432)
	self.dInfo.Size = UDim2.fromOffset(314, 124)
	self.dInfo.TextWrapped = true
	self.dInfo.TextXAlignment = Enum.TextXAlignment.Left
	self.dInfo.TextYAlignment = Enum.TextYAlignment.Top
	self.dInfo.ZIndex = 7
	self.dInfo.Parent = face

	---------------------------------------------------------------
	-- tabs
	---------------------------------------------------------------
	self.tabBtns = {}
	for i, t in ipairs({ { "tyres", "Tyres" }, { "stickers", "Stickers" } }) do
		local b = Kit.tab(t[2], UDim2.fromOffset(150, 40), t[1] == self.tab)
		b.root.Position = UDim2.fromOffset(372 + (i - 1) * 158, 50)
		b.root.ZIndex = 8
		b.root.Parent = face
		b.onClick = function() self:setTab(t[1]) end
		self.tabBtns[t[1]] = b
	end
	self.pages = {}
	for _, name in ipairs({ "tyres", "stickers" }) do
		self.pages[name] = UI.mk("Frame", { Name = name, Position = UDim2.fromOffset(372, 100), Size = UDim2.fromOffset(564, 456), BackgroundTransparency = 1, Visible = name == self.tab, ZIndex = 6, Parent = face })
	end
	self:buildTyres(self.pages.tyres)
	self:buildStickers(self.pages.stickers)
	return self
end

--==============================================================
-- the Tyres page: sort, filter, a grid
--==============================================================
function Workbench:buildTyres(page: Frame)
	local seg, set = Kit.segment(SORTS, self.sort, 80, 36, function(id)
		self.sort = id
		self:renderGrid()
	end)
	seg.Position = UDim2.fromOffset(0, 0)
	seg.ZIndex = 8
	seg.Parent = page
	self.setSort = set
	-- two switches on their own rows, right-aligned, each label centred on its switch
	local function switchRow(y: number, text: string, onChange: (boolean) -> ())
		local l = Kit.text(text, 15, C.text, 2, Kit.Body)
		l.AnchorPoint = Vector2.new(1, 0.5)
		l.Position = UDim2.new(1, -96, 0, y + 20)
		l.Size = UDim2.fromOffset(150, 22)
		l.TextXAlignment = Enum.TextXAlignment.Right
		l.ZIndex = 8
		l.Parent = page
		local tog = Kit.toggle(false, onChange)
		tog.AnchorPoint = Vector2.new(1, 0)
		tog.Position = UDim2.new(1, 0, 0, y)
		tog.ZIndex = 8
		tog.Parent = page
	end
	switchRow(0, "Favourites only", function(v)
		self.favOnly = v
		self:renderGrid()
	end)
	switchRow(48, "All tyres", function(v)
		self.showAll = v
		self:renderGrid()
	end)
	self.count = Kit.text("", 14, C.muted, 1.5, Kit.Body)
	self.count.AnchorPoint = Vector2.new(0, 0.5)
	self.count.Position = UDim2.fromOffset(2, 68)
	self.count.Size = UDim2.fromOffset(300, 18)
	self.count.TextXAlignment = Enum.TextXAlignment.Left
	self.count.ZIndex = 8
	self.count.Parent = page
	self.grid = UI.mk("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 96), Size = UDim2.fromOffset(564, 360), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, ScrollBarImageColor3 = C.line, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 7, Parent = page,
	})
	UI.mk("UIGridLayout", { CellSize = UDim2.fromOffset(Tyres2.CELL.X, Tyres2.CELL.Y), CellPadding = UDim2.fromOffset(10, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.grid })
	UI.mk("UIPadding", { PaddingTop = UDim.new(0, 20), PaddingLeft = UDim.new(0, 8), PaddingBottom = UDim.new(0, 40), Parent = self.grid })
	-- the cards' thumbnails are made as they scroll into view (Tyres2:fillVisible)
	self.grid:GetPropertyChangedSignal("CanvasPosition"):Connect(function() self:fillThumbs() end)
end

function Workbench:fillThumbs()
	if self.gridShim then (Tyres2 :: any).fillVisible(self.gridShim) end
end

-- the tyres you own, sorted and filtered
function Workbench:owned(): { any }
	local v = self.profile and self.profile.v2
	local list = {}
	if not v then return list end
	for _, t in ipairs(v.inv) do
		if not self.favOnly or t.fav then table.insert(list, t) end
	end
	local function pts(t) return Game.tyrePoints(t.id, t.forge, t.mut) end
	table.sort(list, function(a, b)
		if (a.fav == true) ~= (b.fav == true) then return a.fav == true end
		if self.sort == "best" then
			local pa, pb = pts(a), pts(b)
			if pa ~= pb then return pa > pb end
		elseif self.sort == "rarity" then
			local ra, rb = RANK[Game.TyresById[a.id].rarity], RANK[Game.TyresById[b.id].rarity]
			if ra ~= rb then return ra > rb end
		elseif self.sort == "newest" then
			if a.uid ~= b.uid then return a.uid > b.uid end
		elseif self.sort == "name" then
			local na, nb = Game.TyresById[a.id].name, Game.TyresById[b.id].name
			if na ~= nb then return na < nb end
		end
		return a.uid < b.uid
	end)
	return list
end

function Workbench:renderGrid()
	local v = self.profile and self.profile.v2
	if not v then return end
	for _, c in ipairs(self.grid:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local list = self:owned()
	self.count.Text = ("%d tyre%s"):format(#list, #list == 1 and "" or "s")
	local dummy = { cells = {}, list = self.grid, root = self.root }
	self.gridShim = dummy
	self.cells = {}
	task.defer(function() self:fillThumbs() end)
	task.delay(0.1, function() self:fillThumbs() end)
	if self.showAll then
		-- the collection: every tyre in the game, the ones you've never pulled as dark shapes
		local all, found = {}, 0
		for _, t in ipairs(Game.Tyres) do
			if t.zone ~= "retired" then
				table.insert(all, t)
				if v.index[t.id] then found += 1 end
			end
		end
		table.sort(all, function(a, b)
			local fa, fb = v.index[a.id] == true, v.index[b.id] == true
			if fa ~= fb then return fa end
			if self.sort == "best" then
				local pa, pb = Game.tyrePoints(a.id, 0), Game.tyrePoints(b.id, 0)
				if pa ~= pb then return pa > pb end
			elseif self.sort == "rarity" then
				if RANK[a.rarity] ~= RANK[b.rarity] then return RANK[a.rarity] > RANK[b.rarity] end
			elseif self.sort == "name" then
				return a.name < b.name
			end
			return a.num < b.num
		end)
		local nextAt = ((v.indexPaid or 0) + 1) * Game.IndexEvery
		self.count.Text = ("%d / %d found  ·  next key at %d"):format(found, #all, nextAt)
		local byId = {}
		for _, t in ipairs(list) do
			if not byId[t.id] then byId[t.id] = t end
		end
		for i, t in ipairs(all) do
			local known = v.index[t.id] == true
			local mine = byId[t.id]
			local cell = Tyres2.cell(dummy :: any, i, t.id, 0, 1, nil, known, function()
				if mine then self:select(mine.uid) end
			end, self.grid)
			if mine then self.cells[mine.uid] = cell end
		end
		if self.sel and self.cells[self.sel] then self.cells[self.sel].sel.Visible = true end
		return
	end
	for i, t in ipairs(list) do
		local badge = if t.uid == v.launch then "Launch" elseif table.find(v.spares, t.uid) then "Spare" else nil
		local cell = Tyres2.cell(dummy :: any, i, t.id, t.forge, 1, badge, true, function() self:select(t.uid) end, self.grid)
		if t.fav then
			Kit.plate(cell.holder, "Fav", C.yellow, UDim2.new(1, -52, 0, 28), UDim2.fromOffset(44, 20), 13)
		end
		self.cells[t.uid] = cell
	end
	if self.sel and self.cells[self.sel] then self.cells[self.sel].sel.Visible = true end
end

--==============================================================
-- the Stickers page
--==============================================================
function Workbench:buildStickers(page: Frame)
	local cat = TyreSticker.catalogue()
	-- the pack
	local packs, seen = {}, {}
	for _, e in ipairs(cat.list) do
		if not seen[e.pack] then
			seen[e.pack] = true
			table.insert(packs, e.pack)
		end
	end
	table.sort(packs)
	self.packFilter = packs[1]
	local opts = {}
	for i, pk in ipairs(packs) do table.insert(opts, { id = pk, label = "Pack " .. i }) end
	local seg, set = Kit.segment(opts, self.packFilter or "", 84, 34, function(id)
		self.packFilter = id
		self:renderCatalogue()
	end)
	-- every pack in one list, a heading each (no tabs to hunt through)
	seg.Visible = false
	seg.Parent = page
	self.packs = packs
	self.catScroll = UI.mk("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(268, 456), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, ScrollBarImageColor3 = C.line, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 7, Parent = page,
	})
	UI.mk("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.catScroll })
	UI.mk("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 2), PaddingBottom = UDim.new(0, 16), Parent = self.catScroll })

	-- the stickers on this tyre, and the controls for the one picked
	local right = UI.mk("Frame", { Position = UDim2.fromOffset(282, 0), Size = UDim2.fromOffset(282, 456), BackgroundTransparency = 1, ZIndex = 7, Parent = page })
	local head = Kit.text("", 15, C.muted, 1.5, Kit.Body)
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.Position = UDim2.fromOffset(2, 2)
	head.Size = UDim2.fromOffset(280, 18)
	head.ZIndex = 8
	head.Parent = right
	self.stickHead = head
	self.chips = UI.mk("Frame", { Position = UDim2.fromOffset(0, 24), Size = UDim2.fromOffset(282, 104), BackgroundTransparency = 1, ZIndex = 7, Parent = right })
	UI.mk("UIGridLayout", { CellSize = UDim2.fromOffset(60, 48), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.chips })
	self.controls = UI.mk("Frame", { Position = UDim2.fromOffset(0, 136), Size = UDim2.fromOffset(282, 250), BackgroundTransparency = 1, ZIndex = 7, Parent = right })
	local function sliderRow(y: number, label: string, key: string, lo: number, hi: number, fmt: (number) -> string)
		local l = Kit.text(label, 15, C.text, 2, Kit.Body)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Position = UDim2.fromOffset(2, y)
		l.Size = UDim2.fromOffset(86, 34)
		l.ZIndex = 8
		l.Parent = self.controls
		local readout = Kit.text("", 14, C.gold, 1.5)
		readout.AnchorPoint = Vector2.new(1, 0)
		readout.TextXAlignment = Enum.TextXAlignment.Right
		readout.Position = UDim2.new(1, 0, 0, y)
		readout.Size = UDim2.fromOffset(52, 34)
		readout.ZIndex = 8
		readout.Parent = self.controls
		local s, show = Kit.slider(138, 0, function(t)
			local s0 = self.stickers[self.selSticker or 0]
			if not s0 then return end
			local val = lo + (hi - lo) * t
			s0[key] = val
			readout.Text = fmt(val)
			self:redress()
		end, C.orange)
		s.Position = UDim2.fromOffset(88, y)
		s.ZIndex = 8
		s.Parent = self.controls
		return function(val: number)
			show((val - lo) / (hi - lo))
			readout.Text = fmt(val)
		end
	end
	self.setA = sliderRow(0, "Round", "a", -180, 180, function(v) return ("%d°"):format(math.floor(v + 0.5)) end)
	self.setR = sliderRow(44, "Out", "r", 0.6, 1.0, function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end)
	self.setSize = sliderRow(88, "Size", "size", 0.3, 2.5, function(v) return ("%.1fx"):format(v) end)
	self.setRot = sliderRow(132, "Turn", "rot", -180, 180, function(v) return ("%d°"):format(math.floor(v + 0.5)) end)
	local bl = Kit.text("Both sides", 15, C.text, 2, Kit.Body)
	bl.TextXAlignment = Enum.TextXAlignment.Left
	bl.Position = UDim2.fromOffset(2, 180)
	bl.Size = UDim2.fromOffset(120, 40)
	bl.ZIndex = 8
	bl.Parent = self.controls
	self.mirrorTog, self.setMirror = Kit.toggle(false, function(v)
		local s0 = self.stickers[self.selSticker or 0]
		if s0 then
			s0.mirror = v
			self:redress()
		end
	end)
	self.mirrorTog.Position = UDim2.fromOffset(190, 180)
	self.mirrorTog.ZIndex = 8
	self.mirrorTog.Parent = self.controls
	local rm = Kit.button("Remove", C.red, UDim2.fromOffset(134, 38), 16)
	rm.root.Position = UDim2.fromOffset(0, 396)
	rm.root.ZIndex = 8
	rm.root.Parent = right
	rm.onClick = function()
		self:removeSticker()
		self:renderCatalogue()
	end
	local clear = Kit.button("Clear all", C.grey, UDim2.fromOffset(134, 38), 16)
	clear.root.Position = UDim2.fromOffset(148, 396)
	clear.root.ZIndex = 8
	clear.root.Parent = right
	clear.onClick = function()
		self.stickers = {}
		self.selSticker = nil
		self.dirty = true
		self:setEditing(false)
		self:redress()
		self:refreshStickerUI()
	end
	local save = Kit.button("Save", C.green, UDim2.fromOffset(282, 44), 20)
	save.root.Position = UDim2.fromOffset(0, 412)
	save.root.ZIndex = 8
	save.root.Parent = right
	save.onClick = function()
		-- saved: the sticker's let go and the tyre turns again, to be looked at all round
		self:saveDesign()
		self.selSticker = nil
		self:setEditing(false)
		self:refreshStickerUI()
	end
	self.saveBtn = save
	rm.root.Position = UDim2.fromOffset(0, 360)
	clear.root.Position = UDim2.fromOffset(148, 360)
	self.removeBtn = rm
	self.packSet = set
end

function Workbench:renderCatalogue()
	for _, c in ipairs(self.catScroll:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local cat = TyreSticker.catalogue()
	-- what's on the tyre now, so those cells can say so
	local used = {}
	for _, st in ipairs(self.stickers or {}) do used[st.id] = (used[st.id] or 0) + 1 end
	for pi, pk in ipairs(self.packs or {}) do
		local list = {}
		for _, e in ipairs(cat.list) do
			if e.pack == pk then table.insert(list, e) end
		end
		local head = Kit.section(self.catScroll, ("Pack %d   ·   %d stickers"):format(pi, #list), UDim2.new(), UDim2.fromOffset(258, 28), 8)
		head.LayoutOrder = pi * 2
		local lbl = head:FindFirstChild("Label")
		if lbl then (lbl :: TextLabel).TextXAlignment = Enum.TextXAlignment.Left end
		local grid = UI.mk("Frame", { Size = UDim2.fromOffset(258, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = pi * 2 + 1, ZIndex = 7, Parent = self.catScroll })
		UI.mk("UIGridLayout", { CellSize = UDim2.fromOffset(58, 58), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for n, e in ipairs(list) do
			local b = UI.mk("ImageButton", { Name = e.id, BackgroundTransparency = 1, Image = "", AutoButtonColor = false, LayoutOrder = n, ZIndex = 8, Parent = grid })
			Kit.slot(b, if used[e.id] then C.accent else Kit.NEUTRAL, 8)
			local art = UI.mk("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -14, 1, -14), BackgroundTransparency = 1,
				Image = e.texture, ScaleType = Enum.ScaleType.Fit, ZIndex = 10, Parent = b,
			})
			if used[e.id] then
				local c = Kit.text("x" .. used[e.id], 12, C.white, 2)
				c.AnchorPoint = Vector2.new(1, 1)
				c.Position = UDim2.new(1, -3, 1, -2)
				c.Size = UDim2.fromOffset(24, 14)
				c.ZIndex = 11
				c.Parent = b
			end
			-- hover pops the art, not the cell (the grid owns the cell's size)
			b.MouseEnter:Connect(function() Kit.tween(art, 0.1, { Size = UDim2.new(1, -6, 1, -6) }) end)
			b.MouseLeave:Connect(function() Kit.tween(art, 0.1, { Size = UDim2.new(1, -14, 1, -14) }) end)
			b.Activated:Connect(function()
				self:addSticker(e.id)
				self:renderCatalogue()
			end)
		end
	end
end

function Workbench:addSticker(id: string)
	if #self.stickers >= MAX_STICKERS then
		Kit.callout(self.gui, ("%d stickers is the most a tyre wears"):format(MAX_STICKERS), C.red, UDim2.fromScale(0.5, 0.16), 26)
		return
	end
	table.insert(self.stickers, { id = id, a = 0, r = 0.82, rot = 0, size = 1, mirror = false })
	self.selSticker = #self.stickers
	self.dirty = true
	self:setEditing(true)
	self:redress()
	self:refreshStickerUI()
end

function Workbench:removeSticker()
	local i = self.selSticker
	if not i or not self.stickers[i] then return end
	table.remove(self.stickers, i)
	self.selSticker = nil
	self.dirty = true
	self:setEditing(false)
	self:redress()
	self:refreshStickerUI()
end

-- put the stickers on the tyre on the bench
function Workbench:redress()
	local m = self.stand.model()
	if m then TyreSticker.apply(m, self.stickers) end
	self.dirty = true
	self:placeOutline()
end

--==============================================================
-- the sticker pad: over the bench. In the sticker view it outlines the picked sticker and lets you
-- grab any sticker and drag it round the wheel (scroll over the pad to size the picked one); out of
-- it, a drag across the bay turns the tyre. Where a sticker is on screen is found by projecting its
-- own plates through the bay's camera, and a drag is taken back through the camera onto the
-- sidewall, so the pointer and the sticker always agree.
--==============================================================
local STAND_POS, STAND_SIZE = UDim2.fromOffset(26, 50), UDim2.fromOffset(324, 300)
local BIG_POS, BIG_SIZE = UDim2.fromOffset(16, 50), UDim2.fromOffset(344, 506)

function Workbench:buildStickerPad()
	local root = self.stand.root
	local pad = UI.mk("TextButton", {
		Name = "StickerPad", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		Visible = true, ZIndex = (root.ZIndex or 6) + 8, Parent = root,
	})
	self.pad = pad
	-- the outline round the picked sticker, pulsing so it reads as the one you're moving
	local ring = UI.mk("Frame", {
		Name = "Outline", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false, ZIndex = pad.ZIndex + 1, Parent = pad,
	}, { UI.corner(4) })
	local stroke = UI.mk("UIStroke", { Color = C.orange, Thickness = 2, Transparency = 0, Parent = ring })
	local glow = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 10, 1, 10), BackgroundTransparency = 1,
		Image = Kit.Art.glow, ImageColor3 = C.orange, ImageTransparency = 0.75, ZIndex = pad.ZIndex, Parent = ring,
	})
	self.outline, self.outlineStroke, self.outlineGlow = ring, stroke, glow
	local hint = Kit.text("", 13, C.white, 2, Kit.Body)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -8)
	hint.Size = UDim2.new(1, -16, 0, 16)
	Kit.fit(hint, 13, 9)
	hint.ZIndex = pad.ZIndex + 2
	hint.Parent = pad
	self.padHint = hint
	RunService.RenderStepped:Connect(function()
		if not self.root.Visible then return end
		-- (kept on its sticker every frame: the camera glides in, the bay grows)
		self:placeOutline()
		if ring.Visible then
			local k = 0.5 + 0.5 * math.sin(os.clock() * 6)
			stroke.Transparency = 0.05 + 0.3 * k
			stroke.Thickness = if self.dragging then 3 else 2
			glow.ImageTransparency = 0.7 + 0.2 * k
		end
	end)
	local GuiService = game:GetService("GuiService")
	local UIS = game:GetService("UserInputService")
	-- a pointer position in the pad's own pixels from its centre (screen y down). The mouse is read
	-- where the screen has it, and a touch has the top bar added back, so both match the frames'
	-- AbsolutePosition (the interface ignores the top bar's inset)
	local function fromHub(io: InputObject): Vector2
		local p: Vector2
		if io.UserInputType == Enum.UserInputType.Touch then
			p = Vector2.new(io.Position.X, io.Position.Y) + GuiService:GetGuiInset()
		else
			p = UIS:GetMouseLocation()
		end
		if not self.gui.IgnoreGuiInset then p -= GuiService:GetGuiInset() end
		return p - (root.AbsolutePosition + root.AbsoluteSize / 2)
	end
	pad.InputBegan:Connect(function(io)
		if io.UserInputType ~= Enum.UserInputType.MouseButton1 and io.UserInputType ~= Enum.UserInputType.Touch then return end
		local d = fromHub(io)
		if self.tab == "stickers" then
			-- the sticker under the pointer (the smallest that holds it), picked and grabbed
			local best, bestArea = nil, math.huge
			for i in ipairs(self.stickers) do
				local box = self:stickerBox(i)
				if box and box.holds(d, 6) and box.w * box.h < bestArea then best, bestArea = i, box.w * box.h end
			end
			if best then
				local was = self.selSticker
				self.selSticker = best
				self:setEditing(true)
				local box = self:stickerBox(best)
				self.dragging = box ~= nil and self.stand.isEditing()
				self.grabOff = if box then box.c - d else Vector2.zero
				self.dragZ = box and box.z or 0
				if was ~= best then self:refreshStickerUI() end
				Kit.pop(ring, 1.08, 0.16)
				return
			end
		end
		-- anywhere else: turn the tyre by hand (out of the sticker view)
		if not self.stand.isEditing() then
			self.turningX = d.X
		end
	end)
	UIS.InputChanged:Connect(function(io)
		if io.UserInputType ~= Enum.UserInputType.MouseMovement and io.UserInputType ~= Enum.UserInputType.Touch then return end
		if self.turningX then
			local x = fromHub(io).X
			self.stand.spin(x - self.turningX)
			self.turningX = x
			return
		end
		if not self.dragging then return end
		local s0 = self.stickers[self.selSticker or 0]
		local m = self.stand.model()
		if not (s0 and m) then return end
		local p = self:unproject(fromHub(io) + (self.grabOff or Vector2.zero), self.dragZ or 0)
		if not p then return end
		local radius = TyreSticker.surface(m)
		s0.a = math.deg(math.atan2(p.X, p.Y))
		s0.r = math.clamp(Vector2.new(p.X, p.Y).Magnitude / math.max(radius, 0.1), 0.6, 1.0)
		self.setA(s0.a)
		self.setR(s0.r)
		self:redress()
	end)
	UIS.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			self.dragging = false
			self.turningX = nil
		end
	end)
	pad.MouseWheelForward:Connect(function() self:nudgeSize(0.1) end)
	pad.MouseWheelBackward:Connect(function() self:nudgeSize(-0.1) end)
	self:paintHint()
end

function Workbench:paintHint()
	local h = self.padHint
	if not h then return end
	h.Text = if self.tab == "stickers" and self.stand.isEditing() then "Drag a sticker to move it  ·  scroll to size it"
		elseif self.tab == "stickers" then "Click a sticker to edit it  ·  drag to turn the tyre"
		else "Drag to turn it"
end

-- a point in the bay's world to pixels from the bay's centre (screen y down)
function Workbench:project(p: Vector3): (Vector2, number)
	local cam = self.stand.camera()
	local size = self.stand.root.AbsoluteSize
	local q = cam.CFrame:PointToObjectSpace(p)
	local k = (size.Y / 2) / (math.max(0.05, -q.Z) * math.tan(math.rad(cam.FieldOfView / 2)))
	return Vector2.new(q.X * k, -q.Y * k), -q.Z
end

-- pixels from the bay's centre back through the camera onto the plane z = zp of the tyre's own frame
function Workbench:unproject(d: Vector2, zp: number): Vector3?
	local m = self.stand.model()
	if not m then return nil end
	local cam = self.stand.camera()
	local size = self.stand.root.AbsoluteSize
	local t = math.tan(math.rad(cam.FieldOfView / 2))
	local h2 = math.max(size.Y / 2, 1)
	local dir = cam.CFrame:VectorToWorldSpace(Vector3.new(d.X / h2 * t, -d.Y / h2 * t, -1))
	local pivot = m:GetPivot()
	local o = pivot:PointToObjectSpace(cam.CFrame.Position)
	local v = pivot:VectorToObjectSpace(dir)
	if math.abs(v.Z) < 1e-4 then return nil end
	local k = (zp - o.Z) / v.Z
	if k <= 0 then return nil end
	return o + v * k
end

-- where sticker i is on screen: its plates (this side) projected, boxed along the sticker's own
-- axes as it appears. -> { c, w, h, rot, z, holds(d, margin) }
function Workbench:stickerBox(i: number)
	local m = self.stand.model()
	if not m then return nil end
	local pts, ups, zs = {}, Vector2.zero, 0
	local n = 0
	local pivot = m:GetPivot()
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("BasePart") and c.Name == "Sticker" and c:GetAttribute("StickerIndex") == i and c:GetAttribute("StickerSide") == 1 then
			local hs = c.Size / 2
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					table.insert(pts, (self:project(c.CFrame:PointToWorldSpace(Vector3.new(hs.X * sx, hs.Y * sy, 0)))))
				end
			end
			local a = self:project(c.Position)
			local b = self:project(c.Position + c.CFrame.UpVector)
			ups += b - a
			zs += pivot:PointToObjectSpace(c.Position).Z
			n += 1
		end
	end
	if n == 0 then return nil end
	-- the sticker's up on screen, as a clockwise turn from straight up
	local rot = math.atan2(ups.X, -ups.Y)
	local R = Vector2.new(math.cos(rot), math.sin(rot))
	local Dn = Vector2.new(-math.sin(rot), math.cos(rot))
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(pts) do
		local x, y = p:Dot(R), p:Dot(Dn)
		x0, x1, y0, y1 = math.min(x0, x), math.max(x1, x), math.min(y0, y), math.max(y1, y)
	end
	local c = R * (x0 + x1) / 2 + Dn * (y0 + y1) / 2
	return {
		c = c, w = x1 - x0, h = y1 - y0, rot = math.deg(rot), z = zs / n,
		holds = function(d: Vector2, margin: number): boolean
			local x, y = d:Dot(R), d:Dot(Dn)
			return x >= x0 - margin and x <= x1 + margin and y >= y0 - margin and y <= y1 + margin
		end,
	}
end

function Workbench:nudgeSize(by: number)
	local s0 = self.stickers[self.selSticker or 0]
	if not s0 or not self.stand.isEditing() then return end
	s0.size = math.clamp((s0.size or 1) + by, 0.3, 2.5)
	self.setSize(s0.size)
	self:redress()
end

-- the outline over the picked sticker (only in the sticker view)
function Workbench:placeOutline()
	local ring = self.outline
	if not ring then return end
	local box = self.tab == "stickers" and self.stand.isEditing() and self.selSticker and self:stickerBox(self.selSticker) or nil
	if not box then
		ring.Visible = false
		return
	end
	ring.Visible = true
	ring.Position = UDim2.new(0.5, box.c.X, 0.5, box.c.Y)
	ring.Size = UDim2.fromOffset(box.w + 6, box.h + 6)
	ring.Rotation = box.rot
end

-- the bay grows to fill the left of the bench for the stickers (the tyre comes forward, the centre
-- of it all), and goes back for the tyres
function Workbench:layoutStand(big: boolean)
	if self.big == big then return end
	self.big = big
	for _, g in ipairs({ self.dName, self.dPlate, self.favBtn.root, self.dInfo } :: { GuiObject }) do g.Visible = not big end
	Kit.tween(self.stand.root, 0.4, { Position = if big then BIG_POS else STAND_POS, Size = if big then BIG_SIZE else STAND_SIZE }, Enum.EasingStyle.Back)
end

-- the sticker view (face-on, close) on or off; out of it the tyre turns and can be turned by hand
function Workbench:setEditing(on: boolean)
	local size = if self.big then BIG_SIZE else STAND_SIZE
	self.stand.setEdit(on, size.X.Offset / size.Y.Offset)
	if not on then self.dragging = false end
	self:placeOutline()
	self:paintHint()
end

-- the chips and sliders for the sticker picked
function Workbench:refreshStickerUI()
	for _, c in ipairs(self.chips:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	self.stickHead.Text = ("ON THIS TYRE   %d / %d"):format(#self.stickers, MAX_STICKERS)
	local cat = TyreSticker.catalogue()
	for i, s in ipairs(self.stickers) do
		local e = cat.byId[s.id]
		local b = UI.mk("TextButton", { BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = i, ZIndex = 8, Parent = self.chips })
		Kit.slot(b, if i == self.selSticker then C.orange else Kit.NEUTRAL, 8)
		if e then
			UI.mk("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -12, 1, -12), BackgroundTransparency = 1,
				Image = e.texture, ScaleType = Enum.ScaleType.Fit, ZIndex = 10, Parent = b,
			})
		end
		b.Activated:Connect(function()
			self.selSticker = i
			self:setEditing(true)
			self:refreshStickerUI()
		end)
	end
	local s = self.stickers[self.selSticker or 0]
	self.controls.Visible = s ~= nil
	self.removeBtn.root.Visible = s ~= nil
	self:placeOutline()
	if s then
		self.setA(s.a)
		self.setR(s.r)
		self.setSize(s.size)
		self.setRot(s.rot)
		self.setMirror(s.mirror == true)
	end
end

function Workbench:saveDesign()
	local v = self.profile and self.profile.v2
	local uid = self.sel
	if not (v and uid) then return end
	local design = { paint = {}, finish = {}, stickers = self.stickers, text = "" }
	local ok, res = pcall(function() return (self.R :: any).Design:InvokeServer(uid, design) end)
	if ok and type(res) == "table" and res.ok then
		self.dirty = false
		Kit.callout(self.gui, "SAVED", C.green, UDim2.fromScale(0.5, 0.16), 34)
	else
		Kit.callout(self.gui, "COULDN'T SAVE", C.red, UDim2.fromScale(0.5, 0.16), 28)
	end
end

--==============================================================
-- selection, favourites, tabs
--==============================================================
function Workbench:select(uid: number)
	local v = self.profile and self.profile.v2
	if not v then return end
	if self.dirty and self.sel and self.sel ~= uid then self:saveDesign() end
	local t
	for _, e in ipairs(v.inv) do
		if e.uid == uid then t = e end
	end
	if not t then return end
	if self.sel and self.cells and self.cells[self.sel] then self.cells[self.sel].sel.Visible = false end
	self.sel = uid
	if self.cells and self.cells[uid] then
		self.cells[uid].sel.Visible = true
		Kit.pop(self.cells[uid].sel, 0.9, 0.2)
	end
	local def = Game.TyresById[t.id]
	local rar = Game.RaritiesById[def.rarity]
	self.stand.set(t.id, true)
	self.stand.setRarity(rar.color, rar.color)
	Kit.pop(self.stand.root, 0.97, 0.22)
	local forgeName = Game.Forge.Names[(t.forge or 0) + 1]
	local mut = t.mut and Game.MutationsById[t.mut]
	self.dName.Text = (mut and (mut.name .. " ") or "") .. (forgeName ~= "" and (forgeName .. " ") or "") .. def.name
	local plate = self.dPlate:FindFirstChildWhichIsA("ImageLabel")
	if plate then plate.ImageColor3 = rar.color end
	self.dPlateText.Text = string.upper(rar.id)
	local info = Game.tyreLines(t.id, t.forge, t.mut)
	-- its special and skill, said in full
	for _, a in ipairs(Game.tyreAbilities(t.id)) do
		table.insert(info, ("<font color=\"#F4F0E8\">%s: %s</font>"):format(string.upper(a.name), a.text))
	end
	self.dInfo.Text = table.concat(info, "\n")
	self.dInfo.RichText = true
	self.favBtn.setText(if t.fav then "Favourite: on" else "Favourite")
	self.favBtn.setColor(if t.fav then C.yellow else C.grey)
	-- its stickers
	local design = v.designs and v.designs[tostring(uid)]
	self.stickers = {}
	for _, s in ipairs(design and design.stickers or {}) do table.insert(self.stickers, table.clone(s)) end
	self.selSticker = nil
	if self.tab == "stickers" then self:setEditing(false) end
	local m = self.stand.model()
	if m then TyreSticker.apply(m, self.stickers) end
	self.dirty = false
	self:refreshStickerUI()
end

function Workbench:toggleFav()
	local v = self.profile and self.profile.v2
	local uid = self.sel
	if not (v and uid) then return end
	local t
	for _, e in ipairs(v.inv) do
		if e.uid == uid then t = e end
	end
	if not t then return end
	local want = not t.fav
	local ok, res = pcall(function() return (self.R :: any).Fav:InvokeServer(uid, want) end)
	if ok and type(res) == "table" and res.ok then
		t.fav = want or nil
		self.favBtn.setText(if want then "Favourite: on" else "Favourite")
		self.favBtn.setColor(if want then C.yellow else C.grey)
		Kit.pop(self.favBtn.root, 0.9, 0.2)
		self:renderGrid()
	end
end

function Workbench:setTab(name: string)
	if self.tab == "stickers" and name ~= "stickers" and self.dirty then self:saveDesign() end
	self.tab = name
	for k, b in pairs(self.tabBtns) do b.setColor(if k == name then C.orange else C.grey) end
	for k, page in pairs(self.pages) do page.Visible = k == name end
	-- the stickers bring the tyre forward, big; a sticker picked closes in on the sidewall
	self:layoutStand(name == "stickers")
	self:setEditing(name == "stickers" and self.selSticker ~= nil)
	if name == "stickers" then
		self:renderCatalogue()
		self:refreshStickerUI()
	else
		self:renderGrid()
	end
end

function Workbench:setProfile(p)
	self.profile = p
	local v = p and p.v2
	if not v then return end
	if self.root.Visible then
		if self.tab == "tyres" then self:renderGrid() end
		-- a tyre that's gone (fused away): back to the launch tyre
		local have = false
		for _, e in ipairs(v.inv) do
			if e.uid == self.sel then have = true end
		end
		if not have then self:select(v.launch) end
	end
end

function Workbench:open()
	Kit.dim(self.gui, self, true)
	Kit.open(self.root)
	local v = self.profile and self.profile.v2
	self:setTab("tyres")
	if v then
		self:select(self.sel or v.launch)
		self:renderGrid()
	end
end

function Workbench:close()
	if self.dirty and self.sel then self:saveDesign() end
	Kit.dim(self.gui, self, false)
	if self.root.Visible then Kit.close_(self.root) end
end

function Workbench:isOpen(): boolean
	return self.root.Visible
end

return Workbench
