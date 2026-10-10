--!strict
-- TYRE CANNON :: Tyres2
-- Your tyres, on a steel panel under an enamel sign.
--   left    MINE / INDEX tabs, how many you've got, EQUIP BEST; a grid of cards: each a dark steel
--           well with the tyre standing in it, its name, an enamel plate in its rarity's colour and
--           the well's edge in that colour too; badges for the launch tyre and spares, a count, the
--           fused level. INDEX shows every tyre in the patch, unfound ones as dark silhouettes.
--   right   the selected tyre on a turntable in its display bay, turning slowly; its name, rarity,
--           what it does, SET AS LAUNCH, ADD SPARE / REMOVE, FUSE (five fuse into Gold, Chrome,
--           Obsidian).
-- Motion: hovering a card lifts it, tips it a touch, runs a shine across it and brightens its edge;
-- the selected card keeps an amber line round it and its tyre turns slowly (only that one). The
-- grid fills in one card after another when it's drawn.
--   Tyres2.new(gui, remotes) -> tyres ; tyres:setProfile(p) ; tyres:open() / :close() / :isOpen()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local TyreShow = require(script.Parent.TyreShow)
local C = Kit.C

local Tyres2 = {}
Tyres2.__index = Tyres2

local FORGE_COL = { [0] = C.white, [1] = Color3.fromRGB(255, 204, 70), [2] = Color3.fromRGB(214, 224, 238), [3] = Color3.fromRGB(150, 130, 190) }
local CELL = Vector2.new(132, 178)
Tyres2.CELL = CELL
local UNFOUND = Color3.fromRGB(96, 96, 102)

function Tyres2.new(gui: ScreenGui, remotes: Instance)
	local self = setmetatable({}, Tyres2)
	self.gui = gui
	self.R = remotes
	self.tab = "owned"
	self.cells = {}
	local root = UI.mk("Frame", {
		Name = "Tyres2", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(960, 580),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.root = root
	local holder, face = Kit.card(UDim2.fromOffset(960, 570), C.cream)
	holder.Parent = root
	Kit.header(face, "Tyres", C.green, 60)
	local close = Kit.close(54)
	close.root.AnchorPoint = Vector2.new(0.5, 0.5)
	close.root.Position = UDim2.new(1, -8, 0, 8)
	close.root.ZIndex = 40
	close.root.Parent = root
	close.onClick = function() self:close() end

	-- the tabs and the count, EQUIP BEST at the right of the grid
	self.bMine = Kit.tab("Equip & Fuse", UDim2.fromOffset(170, 44), true)
	self.bMine.root.Position = UDim2.fromOffset(32, 44)
	self.bMine.root.ZIndex = 6
	self.bMine.root.Parent = face
	self.bMine.onClick = function() self.tab = "owned" self:render() end
	self.bIndex = Kit.tab("Index", UDim2.fromOffset(124, 44), false)
	self.bIndex.root.Position = UDim2.fromOffset(164, 44)
	self.bIndex.root.ZIndex = 6
	self.bIndex.root.Parent = face
	self.bIndex.onClick = function() self.tab = "index" self:render() end
	-- the Index moved to the Workbench: this screen is for equipping and fusing
	self.bIndex.root.Visible = false
	self.countText = Kit.text("", 17, C.muted, 1.5, Kit.Body)
	self.countText.Position = UDim2.fromOffset(214, 54)
	self.countText.Size = UDim2.fromOffset(150, 24)
	self.countText.TextXAlignment = Enum.TextXAlignment.Left
	self.countText.ZIndex = 6
	self.countText.Parent = face
	self.bBest = Kit.button("Equip Best", C.blue, UDim2.fromOffset(156, 44), 18)
	self.bBest.root.AnchorPoint = Vector2.new(1, 0)
	self.bBest.root.Position = UDim2.fromOffset(620, 44)
	self.bBest.root.ZIndex = 6
	self.bBest.root.Parent = face
	self.bBest.onClick = function() self:equip(nil, "best") end
	Kit.divider(face, UDim2.fromOffset(326, 100), UDim.new(0, 590), 5)

	self.list = UI.mk("ScrollingFrame", {
		Position = UDim2.fromOffset(26, 106), Size = UDim2.fromOffset(604, 440), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, ScrollBarImageColor3 = C.line, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		ZIndex = 5, Parent = face,
	})
	UI.mk("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.list })
	UI.mk("UIPadding", { PaddingTop = UDim.new(0, 20), PaddingLeft = UDim.new(0, 8), PaddingBottom = UDim.new(0, 40), Parent = self.list })

	-- the Index's own header: what it is, how far you are, what finishing a row pays
	local info = UI.mk("Frame", { Name = "IndexInfo", Position = UDim2.fromOffset(26, 106), Size = UDim2.fromOffset(596, 78), BackgroundTransparency = 1, Visible = false, ZIndex = 6, Parent = face })
	Kit.slot(info, Color3.fromRGB(110, 112, 124), 6)
	self.idxTitle = Kit.text("THE INDEX", 20, C.white, 2)
	self.idxTitle.TextXAlignment = Enum.TextXAlignment.Left
	self.idxTitle.Position = UDim2.fromOffset(18, 8)
	self.idxTitle.Size = UDim2.fromOffset(200, 24)
	self.idxTitle.ZIndex = 8
	self.idxTitle.Parent = info
	self.idxText = Kit.text("Every tyre in the game. A tyre is logged the first time you pull it and stays logged for good, even if you fuse it away. Every 5 logged pays a key and +5% cash.", 13, C.muted, 1.5, Kit.Body)
	self.idxText.TextXAlignment = Enum.TextXAlignment.Left
	self.idxText.TextYAlignment = Enum.TextYAlignment.Top
	self.idxText.TextWrapped = true
	self.idxText.Position = UDim2.fromOffset(18, 32)
	self.idxText.Size = UDim2.fromOffset(398, 40)
	self.idxText.ZIndex = 8
	self.idxText.Parent = info
	self.idxCount = Kit.text("", 28, C.gold, 2.5)
	self.idxCount.AnchorPoint = Vector2.new(1, 0)
	self.idxCount.Position = UDim2.new(1, -16, 0, 6)
	self.idxCount.Size = UDim2.fromOffset(150, 32)
	self.idxCount.TextXAlignment = Enum.TextXAlignment.Right
	self.idxCount.ZIndex = 8
	self.idxCount.Parent = info
	local itrack, ifill = Kit.bar(160, 16, C.green)
	itrack.AnchorPoint = Vector2.new(1, 0)
	itrack.Position = UDim2.new(1, -16, 0, 40)
	itrack.ZIndex = 8
	itrack.Parent = info
	self.idxFill = ifill
	self.idxNext = Kit.text("", 12, C.muted, 1.5, Kit.Body)
	self.idxNext.AnchorPoint = Vector2.new(1, 0)
	self.idxNext.Position = UDim2.new(1, -16, 0, 58)
	self.idxNext.Size = UDim2.fromOffset(170, 16)
	self.idxNext.TextXAlignment = Enum.TextXAlignment.Right
	self.idxNext.ZIndex = 8
	self.idxNext.Parent = info
	self.idxInfo = info
	-- the Index's order: by crate (grouped), by rarity, by strength, or what you've found first
	self.idxSort = "zone"
	local idxSeg = Kit.segment({
		{ id = "zone", label = "Crate" }, { id = "rarity", label = "Rarity" }, { id = "best", label = "Best" }, { id = "found", label = "Found" },
	}, self.idxSort, 96, 32, function(id)
		self.idxSort = id
		self:render()
	end)
	idxSeg.Position = UDim2.fromOffset(26, 192)
	idxSeg.ZIndex = 8
	idxSeg.Visible = false
	idxSeg.Parent = face
	self.idxSeg = idxSeg
	-- the rows run out under a fade into the panel rather than a hard cut
	UI.mk("Frame", {
		Name = "ListFade", Position = UDim2.fromOffset(26, 506), Size = UDim2.fromOffset(596, 40), BackgroundColor3 = Color3.fromRGB(15, 16, 18),
		BorderSizePixel = 0, ZIndex = 12, Parent = face,
	}, { UI.mk("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }) })

	-- the selected tyre: on its turntable, then what it is
	self.stand = TyreShow.stand(face, UDim2.fromOffset(290, 268))
	self.stand.root.Position = UDim2.fromOffset(646, 44)
	self.stand.root.ZIndex = 6
	self.dName = Kit.text("", 26, C.text, 2)
	self.dName.Position = UDim2.fromOffset(646, 318)
	self.dName.Size = UDim2.fromOffset(290, 30)
	self.dName.ZIndex = 7
	self.dName.Parent = face
	local plate, plateText = Kit.plate(face, "", C.grey, UDim2.fromOffset(721, 352), UDim2.fromOffset(140, 26), 7)
	self.dPlate, self.dPlateText = plate, plateText
	self.dInfo = Kit.text("", 16, C.gold, 1.5, Kit.Body)
	self.dInfo.Position = UDim2.fromOffset(654, 386)
	self.dInfo.Size = UDim2.fromOffset(276, 66)
	self.dInfo.TextWrapped = true
	self.dInfo.TextYAlignment = Enum.TextYAlignment.Top
	self.dInfo.ZIndex = 7
	self.dInfo.Parent = face
	local launch = Kit.button("Set As Launch", C.accent, UDim2.fromOffset(290, 48), 20)
	launch.root.Position = UDim2.fromOffset(646, 458)
	launch.root.ZIndex = 7
	launch.root.Parent = face
	launch.onClick = function() if self.sel then self:equip(self.sel.uid, "launch") end end
	local spare = Kit.button("Add Spare", C.grey, UDim2.fromOffset(141, 42), 16)
	spare.root.Position = UDim2.fromOffset(646, 512)
	spare.root.ZIndex = 7
	spare.root.Parent = face
	spare.onClick = function() if self.sel then self:equip(self.sel.uid, "spare") end end
	local forge = Kit.button("Fuse 0/5", C.purple, UDim2.fromOffset(141, 42), 16)
	forge.root.Position = UDim2.fromOffset(795, 512)
	forge.root.ZIndex = 7
	forge.root.Parent = face
	forge.onClick = function() if self.sel then self:forge(self.sel.id, self.sel.forge) end end
	self.bLaunch, self.bSpare, self.bForge = launch, spare, forge

	-- the selected card's tyre turns slowly
	self.turnYaw = TyreShow.THUMB_YAW
	self.turnConn = nil :: RBXScriptConnection?
	return self
end

function Tyres2:setProfile(p)
	self.profile = p
	if self.root.Visible then self:render() end
end

function Tyres2:open()
	Kit.dim(self.gui or self.root.Parent, self, true)
	Kit.open(self.root)
	self:render(true)
	if not self.turnConn then
		self.turnConn = RunService.RenderStepped:Connect(function(dt)
			local c = self.selCell
			if c and c.model then
				self.turnYaw += dt * 0.7
				TyreShow.pose(c.model, self.turnYaw)
			end
		end)
	end
end

function Tyres2:close()
	Kit.dim(self.gui or self.root.Parent, self, false)
	if self.root.Visible then Kit.close_(self.root) end
	if self.turnConn then
		self.turnConn:Disconnect()
		self.turnConn = nil
	end
end

function Tyres2:isOpen(): boolean
	return self.root.Visible
end

local function badge(parent: Instance, text: string, color: Color3)
	Kit.plate(parent, text, color, UDim2.fromOffset(6, -8), UDim2.fromOffset(70, 22), 12)
end

-- a card: the well, the tyre, the name, the rarity plate; hover and selection on its holder
function Tyres2:cell(order: number, tyreId: string, forge: number, count: number, badgeText: string?, known: boolean, onPick: () -> (), parent: Instance?)
	local t = Game.TyresById[tyreId]
	local rar = Game.RaritiesById[t.rarity]
	local col = if known then rar.color else UNFOUND
	local b = UI.mk("TextButton", { Size = UDim2.fromOffset(CELL.X, CELL.Y), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = order, ZIndex = 6, Parent = parent or self.list })
	local holder = UI.mk("Frame", { Name = "Holder", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6, Parent = b })
	local well = Kit.slot(holder, col, 6)
	local edge = well:FindFirstChild("EdgeArt") :: ImageLabel
	-- the selected line: white, just inside the rarity edge
	local sel = UI.mk("Frame", { Name = "Selected", Position = UDim2.fromOffset(7, 7), Size = UDim2.new(1, -14, 1, -14), BackgroundTransparency = 1, Visible = false, ZIndex = 9, Parent = holder }, { UI.corner(5) })
	UI.mk("UIStroke", { Color = C.white, Thickness = 3, Parent = sel })
	local thumb, model = TyreShow.thumb(holder, tyreId, known, UDim2.fromOffset(118, 104), UDim2.new(0.5, 0, 0, 8))
	if not known then
		-- not found yet: a coloured backlight behind the ghost of the tyre, and a fog over its foot
		UI.mk("ImageLabel", {
			Name = "Backlight", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(124, 112),
			BackgroundTransparency = 1, Image = Kit.Art.glow, ImageColor3 = rar.color, ImageTransparency = 0.3, ZIndex = 7, Parent = holder,
		})
		local fog = UI.mk("ImageLabel", {
			Name = "Fog", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(124, 100),
			BackgroundTransparency = 1, Image = Kit.Art.glow, ImageColor3 = Color3.fromRGB(205, 212, 228), ImageTransparency = 0.35, ZIndex = 9, Parent = holder,
		})
		UI.mk("UIGradient", {
			Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.55, 0.45), NumberSequenceKeypoint.new(1, 0.1) }), Parent = fog,
		})
		local _ = thumb
	end
	local name = Kit.text(if known then t.name else "???", 15, if known then C.text else C.muted, 1.5)
	name.Position = UDim2.fromOffset(4, 112)
	name.Size = UDim2.fromOffset(CELL.X - 8, 22)
	name.TextScaled = true
	name.ZIndex = 9
	name.Parent = holder
	UI.mk("UITextSizeConstraint", { MaxTextSize = 15, Parent = name })
	Kit.plate(holder, if known then rar.id else "Unfound", col, UDim2.fromOffset(10, 140), UDim2.fromOffset(CELL.X - 20, 26), 9)
	if count > 1 then
		local c = Kit.text("x" .. count, 16, C.text, 2)
		c.AnchorPoint = Vector2.new(1, 0)
		c.Position = UDim2.new(1, -9, 0, 8)
		c.Size = UDim2.fromOffset(40, 18)
		c.TextXAlignment = Enum.TextXAlignment.Right
		c.ZIndex = 10
		c.Parent = holder
	end
	if forge > 0 then
		local f = Kit.text(Game.Forge.Names[forge + 1], 13, FORGE_COL[forge], 1.5)
		f.Position = UDim2.fromOffset(10, 18)
		f.Size = UDim2.fromOffset(70, 16)
		f.TextXAlignment = Enum.TextXAlignment.Left
		f.ZIndex = 10
		f.Parent = holder
	end
	if badgeText then badge(holder, badgeText, if badgeText == "Launch" then C.green else C.blue) end
	-- the shine that runs across on hover: the buttons' own, over the well's own shape
	local sweep = Kit.shine(edge, 11)
	local base = col
	b.MouseEnter:Connect(function()
		Kit.tween(holder, 0.16, { Position = UDim2.fromOffset(0, -6) }, Enum.EasingStyle.Back)
		Kit.tween(edge, 0.12, { ImageColor3 = Kit.lift(base, 0.35) })
		sweep()
	end)
	b.MouseLeave:Connect(function()
		Kit.tween(holder, 0.16, { Position = UDim2.fromOffset(0, 0) })
		Kit.tween(edge, 0.16, { ImageColor3 = base })
	end)
	b.MouseButton1Down:Connect(function() Kit.tween(holder, 0.05, { Position = UDim2.fromOffset(0, 1) }) end)
	b.Activated:Connect(onPick)
	local cell = { button = b, holder = holder, sel = sel, model = model, id = tyreId, forge = forge }
	table.insert(self.cells, cell)
	return cell
end

function Tyres2:markSelected(cell)
	if self.selCell and self.selCell ~= cell then
		self.selCell.sel.Visible = false
		if self.selCell.model then TyreShow.pose(self.selCell.model, TyreShow.THUMB_YAW) end
	end
	self.selCell = cell
	if cell then
		cell.sel.Visible = true
		Kit.pop(cell.sel, 0.9, 0.2)
		self.turnYaw = TyreShow.THUMB_YAW
	end
end

-- a block of cards in a grid (auto-height), in the list
function Tyres2:grid(order: number): Frame
	local f = UI.mk("Frame", { Name = "Grid", Size = UDim2.fromOffset(584, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 5, Parent = self.list })
	UI.mk("UIGridLayout", { CellSize = UDim2.fromOffset(CELL.X, CELL.Y), CellPadding = UDim2.fromOffset(14, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
	return f
end

-- where a tyre comes from, for the Index
local SOURCES = {
	{ zone = "backroad", title = "BACKROAD CRATE", sub = "from the first road" },
	{ zone = "highway", title = "HIGHWAY CRATE", sub = "unlocks at " .. Game.metres(Game.ZonesById.highway.start) },
	{ zone = "dunes", title = "DUNES CRATE", sub = "unlocks at " .. Game.metres(Game.ZonesById.dunes.start) },
	{ zone = "mythic", title = "MYTHIC", sub = "any crate, 0.05%" },
	{ zone = "secret", title = "SECRET", sub = "any crate, 0.01%" },
}

function Tyres2:render(fresh: boolean?)
	local p = self.profile
	if not p or not p.v2 then return end
	local v = p.v2
	for _, c in ipairs(self.list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	self.cells = {}
	self.selCell = nil
	self.bMine.setColor(if self.tab == "owned" then C.green else C.grey)
	self.bIndex.setColor(if self.tab == "index" then C.green else C.grey)
	self.bBest.root.Visible = self.tab == "owned"
	self.idxInfo.Visible = self.tab == "index"
	self.idxSeg.Visible = self.tab == "index"
	self.list.Position = UDim2.fromOffset(26, self.tab == "index" and 232 or 106)
	self.list.Size = UDim2.fromOffset(604, self.tab == "index" and 314 or 440)
	if self.tab == "index" and self.idxSort ~= "zone" then
		-- one flat grid in the chosen order
		local all = {}
		local found = 0
		for _, src in ipairs(SOURCES) do
			for _, t in ipairs(Game.TyresByZone[src.zone] or {}) do
				if t.zone ~= "retired" then
					table.insert(all, t)
					if v.index[t.id] then found += 1 end
				end
			end
		end
		local function rank(t) return Game.RaritiesById[t.rarity].order end
		table.sort(all, function(a, b)
			if self.idxSort == "rarity" then
				if rank(a) ~= rank(b) then return rank(a) > rank(b) end
			elseif self.idxSort == "best" then
				local pa, pb = Game.tyrePoints(a.id, 0), Game.tyrePoints(b.id, 0)
				if pa ~= pb then return pa > pb end
			elseif self.idxSort == "found" then
				local fa, fb = v.index[a.id] == true, v.index[b.id] == true
				if fa ~= fb then return fa end
				if rank(a) ~= rank(b) then return rank(a) > rank(b) end
			end
			return a.num < b.num
		end)
		local grid = self:grid(1)
		for i, t in ipairs(all) do
			local known = v.index[t.id] == true
			local cell
			cell = self:cell(i, t.id, 0, 1, nil, known, function()
				self:select({ id = t.id, forge = 0, uid = nil, unfound = not known })
				self:markSelected(cell)
			end, grid)
		end
		self.countText.Text = ""
		self.idxCount.Text = ("%d / %d"):format(found, Game.TyreCount)
		self.idxFill.Size = UDim2.fromScale(math.clamp(found / Game.TyreCount, 0, 1), 1)
		local nextAt = (v.indexPaid + 1) * Game.IndexEvery
		self.idxNext.Text = found >= Game.TyreCount and "Complete" or ("next reward at %d"):format(nextAt)
		if all[1] and not self.sel then self:select({ id = all[1].id, forge = 0, uid = nil, unfound = v.index[all[1].id] ~= true }) end
	elseif self.tab == "index" then
		local found = 0
		local order = 0
		for _, src in ipairs(SOURCES) do
			local list = {}
			for _, t in ipairs(Game.TyresByZone[src.zone] or {}) do
				if t.zone ~= "retired" then table.insert(list, t) end
			end
			table.sort(list, function(a, b) return a.num < b.num end)
			local got = 0
			for _, t in ipairs(list) do if v.index[t.id] then got += 1 end end
			found += got
			order += 1
			local head = Kit.section(self.list, ("%s   ·   %d / %d"):format(src.title, got, #list), UDim2.new(), UDim2.fromOffset(584, 30), 5)
			head.LayoutOrder = order * 2
			local lbl = head:FindFirstChild("Label")
			if lbl then (lbl :: TextLabel).TextXAlignment = Enum.TextXAlignment.Left end
			local grid = self:grid(order * 2 + 1)
			for _, t in ipairs(list) do
				local known = v.index[t.id] == true
				local cell
				cell = self:cell(t.num, t.id, 0, 1, nil, known, function()
					self:select({ id = t.id, forge = 0, uid = nil, unfound = not known })
					self:markSelected(cell)
				end, grid)
			end
		end
		self.countText.Text = ""
		self.idxCount.Text = ("%d / %d"):format(found, Game.TyreCount)
		self.idxFill.Size = UDim2.fromScale(math.clamp(found / Game.TyreCount, 0, 1), 1)
		local nextAt = (v.indexPaid + 1) * Game.IndexEvery
		self.idxNext.Text = found >= Game.TyreCount and "Complete" or ("next reward at %d"):format(nextAt)
		-- the first card, so the right side is never empty
		if self.cells[1] and not self.sel then
			local t0 = nil
			for _, src in ipairs(SOURCES) do
				for _, t in ipairs(Game.TyresByZone[src.zone] or {}) do
					if t.zone ~= "retired" and not t0 then t0 = t end
				end
			end
			if t0 then self:select({ id = t0.id, forge = 0, uid = nil, unfound = v.index[t0.id] ~= true }) end
		end
	else
		-- what you own, grouped by tyre and fused level, best first
		local groups, order = {}, {}
		for _, t in ipairs(v.inv) do
			-- a mutated tyre is its own stack: it's worth more
			local key = t.id .. ":" .. t.forge .. ":" .. (t.mut or "")
			if not groups[key] then
				groups[key] = { id = t.id, forge = t.forge, mut = t.mut, uids = {} }
				table.insert(order, key)
			end
			table.insert(groups[key].uids, t.uid)
		end
		table.sort(order, function(a, b)
			local ga, gb = groups[a], groups[b]
			return Game.tyrePoints(ga.id, ga.forge, ga.mut) > Game.tyrePoints(gb.id, gb.forge, gb.mut)
		end)
		local slots = 1 + (v.mach.rack or 0) + (v.passes.spares2 and 2 or 0)
		self.countText.Text = ("%d tyre%s  ·  %d/%d spares"):format(#v.inv, #v.inv == 1 and "" or "s", #v.spares, slots)
		local cur = self.sel and (self.sel.id .. ":" .. (self.sel.forge or 0) .. ":" .. (self.sel.mut or ""))
		local first = nil
		local grid = self:grid(1)
		for i, key in ipairs(order) do
			local g = groups[key]
			local tag = nil
			for _, uid in ipairs(g.uids) do
				if uid == v.launch then tag = "Launch" end
			end
			if not tag then
				for _, uid in ipairs(g.uids) do
					if table.find(v.spares, uid) then tag = "Spare" end
				end
			end
			local cell
			cell = self:cell(i, g.id, g.forge, #g.uids, tag, true, function()
				self:select(self:pickIn(g))
				self:markSelected(cell)
			end, grid)
			if key == cur or (not cur and i == 1) then first = { cell = cell, g = g } end
		end
		-- empty wells fill out the rows (at least two), so a short collection doesn't leave the
		-- grid as bare plate
		local shown = #order
		local want = math.max(8, math.ceil(shown / 4) * 4)
		for i = shown + 1, want do
			local b = UI.mk("Frame", { Name = "Empty", Size = UDim2.fromOffset(CELL.X, CELL.Y), BackgroundTransparency = 1, LayoutOrder = 1000 + i, Parent = grid })
			local well = Kit.slot(b, Color3.fromRGB(46, 47, 52), 6)
			;(well:FindFirstChild("EdgeArt") :: ImageLabel).ImageTransparency = 0.5
		end
		if first then
			self:select(self:pickIn(first.g))
			self:markSelected(first.cell)
		end
	end
	if fresh then
		local list = {}
		for _, c in ipairs(self.cells) do table.insert(list, c.holder) end
		Kit.cascade(list, 0.02)
	end
end

-- the copy of a tyre to act on (one that isn't equipped, if there is one) and whether this tyre
-- and fused level is already your launch tyre
function Tyres2:pickIn(g)
	local v = self.profile.v2
	local pick, isLaunch = g.uids[1], false
	for _, uid in ipairs(g.uids) do
		if uid == v.launch then isLaunch = true end
	end
	for _, uid in ipairs(g.uids) do
		if uid ~= v.launch and not table.find(v.spares, uid) then pick = uid break end
	end
	return { id = g.id, forge = g.forge, mut = g.mut, uid = pick, count = #g.uids, isLaunch = isLaunch }
end

function Tyres2:select(s)
	self.sel = s
	local t = Game.TyresById[s.id]
	local rar = Game.RaritiesById[t.rarity]
	local shownKey = s.id .. (s.unfound and ":dark" or "")
	if self.shownId ~= shownKey then
		self.shownId = shownKey
		self.stand.set(s.id, not s.unfound)
		self.stand.setRarity(s.unfound and Color3.fromRGB(96, 96, 102) or rar.color, rar.color)
		Kit.pop(self.stand.root, 0.96, 0.25)
	end
	local forgeName = Game.Forge.Names[(s.forge or 0) + 1]
	local mut = s.mut and Game.MutationsById[s.mut]
	self.dName.Text = (mut and (mut.name .. " ") or "") .. (forgeName ~= "" and (forgeName .. " ") or "") .. t.name
	local plate = self.dPlate:FindFirstChildWhichIsA("ImageLabel")
	if plate then plate.ImageColor3 = rar.color end
	self.dPlateText.Text = string.upper(rar.id)
	-- its multiplier, its stats, its special and skill (Game.tyreLines); an unfound one says where it drops
	local lines = Game.tyreLines(t.id, s.forge, s.mut)
	if s.unfound then
		local where = ({ backroad = "Backroad crate", highway = "Highway crate", dunes = "Dunes crate", mythic = "Any crate (very rare)", secret = "Any crate (secret)" })[t.zone] or "a crate"
		table.insert(lines, 1, "NOT FOUND YET: " .. string.upper(where))
	end
	self.dInfo.Text = table.concat(lines, "\n")
	local can = s.uid ~= nil
	self.bLaunch.setText(if s.isLaunch then "Your Launch Tyre" else "Set As Launch")
	self.bLaunch.setEnabled(can and not s.isLaunch)
	local v = self.profile and self.profile.v2
	self.bSpare.setEnabled(can and not (v and s.uid == v.launch))
	local count = s.count or 0
	local need = Game.fuseNeed(s.id)
	self.bForge.setText(("Fuse %d/%d"):format(math.min(count, need), need))
	self.bForge.setEnabled(can and count >= need and (s.forge or 0) < 3)
	if v and s.uid then
		self.bSpare.setText(if table.find(v.spares, s.uid) then "Remove" else "Add Spare")
	end
end

function Tyres2:equip(uid: number?, slot: string)
	local ok, res = pcall(function() return (self.R :: any).Equip:InvokeServer(uid, slot) end)
	if ok and type(res) == "table" and res.ok then
		Kit.callout(self.gui, slot == "launch" and "LAUNCH TYRE SET" or (slot == "best" and "BEST EQUIPPED" or "SPARES UPDATED"), C.green, UDim2.fromScale(0.5, 0.15), 34)
	elseif ok and type(res) == "table" and res.err then
		Kit.callout(self.gui, string.upper(res.err), C.red, UDim2.fromScale(0.5, 0.15), 28)
	end
end

function Tyres2:forge(id: string, forge: number)
	local ok, res = pcall(function() return (self.R :: any).Forge:InvokeServer(id, forge) end)
	if ok and type(res) == "table" and res.ok then
		local name = Game.Forge.Names[res.made.forge + 1]
		Kit.callout(self.gui, string.upper(name .. " " .. Game.TyresById[id].name) .. "!", FORGE_COL[res.made.forge], UDim2.fromScale(0.5, 0.2), 44)
		self.sel = nil
	elseif ok and type(res) == "table" and res.err then
		Kit.callout(self.gui, string.upper(res.err), C.red, UDim2.fromScale(0.5, 0.15), 28)
	end
end

return Tyres2
