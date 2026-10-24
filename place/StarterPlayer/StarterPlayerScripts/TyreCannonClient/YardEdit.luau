--!strict
-- TYRE CANNON :: YardEdit
-- Making your yard yours. The camera rises over the yard; press on a machine or a piece of decor to
-- pick it up (it lifts and leans as you drag), drag it across the floor on the grid, let go to set
-- it down with a bounce and a puff of dust. R or TURN turns it: a machine a quarter, decor 45
-- degrees; while you carry decor the wheel angles it 15 degrees at a time. The footprint under
-- each thing is green where it can stand and red where it can't; let go somewhere it can't stand
-- and it slides back to where it was picked up. Whatever's selected stays outlined in gold (its
-- footprint too, its name over the buttons), so TURN and REMOVE always say what they'll act on.
-- The drawer of decor along the bottom hands you a piece on the end of the pointer: it follows the
-- mouse until you click to set it down (Q drops it back in the drawer); on a touch screen it lands
-- near the middle of the view instead. REMOVE or Delete takes the selected piece away. DONE saves (the server checks the same rules,
-- Game.yardCheck), RESET puts the machines back where they started, Q or the X leaves unsaved.
-- The cannon and its ramp move together as the launcher: the shot has to go out over the ramp.
-- The camera orbits the yard on springs: right-drag (two fingers on a phone) looks round, the wheel
-- (a pinch) zooms, WASD or the arrows pan, F puts it back; carrying something draws it gently over.
-- Its pitch stays high enough that nothing in the yard can come between it and the floor.
-- LOOK cycles the yard's looks (Game.YardLooks) and previews each on the floor; DONE keeps the one
-- showing if it's yours, and offers the Midnight Garage pass if it isn't. Prestige and pass decor
-- (the neon pack, NeonDecor) show what unlocks them.
-- The drawer has tabs (Game.DecorCats, then FLOOR and FENCE): a floor or fence card previews it on
-- the yard (PlotStage.preview) and DONE saves it with the layout. Whatever you carry is drawn to the
-- nearest free spot by the pointer (settle), so it never sits on top of something; on a touch screen
-- a fresh piece floats until you tap where it goes. A click picks the smallest thing under it, so
-- decor beside a big machine can always be grabbed.
--   YardEdit.new(gui, remotes, plot2) ; :open(plotModel, onClose) ; :isOpen()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local PackFX = require(script.Parent.PackFX)
local Sound = require(script.Parent.Sound)
local Models = require(script.Parent.Models)
local NeonDecor = require(script.Parent.NeonDecor)
local YardLook = require(script.Parent.YardLook)
local PlotStage = require(script.Parent.PlotStage)
local Config = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Config"))
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local C = Kit.C

local YardEdit = {}
YardEdit.__index = YardEdit

local FLOOR_Y = 2
local LIFT = 3.2
-- the overview: from behind the cannon on the plaza side, high, looking down the lane (plot space)
local CAM_AT = Vector3.new(-40, 88, 0)
local CAM_LOOK = Vector3.new(14, 0, 0)
local CAM_FOV = 52
-- the orbit's limits (plot space)
local PITCH_MIN, PITCH_MAX = math.rad(34), math.rad(78)
local DIST_MIN, DIST_MAX = 52, 150
local PLATE_IDLE = Color3.fromRGB(246, 242, 232)
local PLATE_GOOD = Color3.fromRGB(78, 204, 96)
local PLATE_BAD = Color3.fromRGB(236, 58, 66)
local PLATE_SEL = Color3.fromRGB(255, 200, 60)
local CARD_W, CARD_H = 104, 128
-- the magnet's search: grid steps within 10 studs, nearest first
local NEAR = {}
for dx = -5, 5 do
	for dz = -5, 5 do
		local d = dx * dx + dz * dz
		if d <= 25 then table.insert(NEAR, { dx, dz, d }) end
	end
end
table.sort(NEAR, function(a, b) return a[3] < b[3] end)

-- (a card in the drawer's grid is placed by the grid: its face shakes, not the cell)
local function shakeCard(card: GuiObject)
	local face = card:FindFirstChild("Holder")
	Kit.shake(if face and face:IsA("GuiObject") then face else card, 5, 0.2)
end

local function tuned(name: string, default: any): any
	if RunService:IsStudio() then
		local v = workspace:GetAttribute(name)
		if v ~= nil then return v end
	end
	return default
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- a deep copy of a layout: the units' spots and the decor list
local function copy(layout: Game.YardLayout): Game.YardLayout
	local out = {}
	for _, u in ipairs(Game.Yard.Units) do
		local s = layout[u.id]
		if s then out[u.id] = { x = s.x, z = s.z, r = s.r } end
	end
	out.decor = {}
	for _, d in ipairs(layout.decor or {}) do table.insert(out.decor, { k = d.k, x = d.x, z = d.z, r = d.r, a = Game.decorAngle(d) }) end
	out.floor = layout.floor or "stage"
	out.fence = layout.fence or "stage"
	return out
end

-- decor is addressed as "d1", "d2"... (its place in the list), the same names yardCheck reports
local function decorIndex(id: string?): number?
	if id and string.sub(id, 1, 1) == "d" then return tonumber(string.sub(id, 2)) end
	return nil
end

local function flat(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Transparency = transparency
	p.Parent = parent
	return p
end

function YardEdit.new(gui: ScreenGui, remotes: Instance, plot2)
	local self = setmetatable({}, YardEdit)
	self.gui = gui
	self.R = remotes
	self.plot2 = plot2
	self.open_ = false
	-- what's been done in the editor this session (the yard tour in Tutorial watches it)
	self.stats = { added = 0, moved = 0, skins = 0, saved = 0 }

	-- v4 layout (2026-10-16): a bar along the top (the title, the yard's Style, LOOK / RESET / DONE),
	-- the catalogue down the right (a grid by kind: each piece's style points, its set, x2 if it's the
	-- week's theme), the sets down the left (how far into each; the theme marked), and a bar along the
	-- bottom for whatever's selected (TURN / REMOVE), a line of help when nothing is
	local root = UI.mk("Frame", { Name = "YardEdit", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 40, Parent = gui })
	self.root = root

	-- the top bar
	local top = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(860, 70), BackgroundTransparency = 1, Active = true, Parent = root })
	UI.autoScale(top, 1280, 760)
	Kit.slice("panel_body", nil, top, 1, 0.45)
	Kit.slice("panel_ring", C.teal, top, 2, 0.45)
	local title = Kit.text("EDIT YARD", 26, C.white, 2.5)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(20, 8)
	title.Size = UDim2.fromOffset(190, 30)
	title.ZIndex = 4
	title.Parent = top
	self.decorCount = Kit.text("", 14, C.gold, 1.5, Kit.Body)
	self.decorCount.TextXAlignment = Enum.TextXAlignment.Left
	self.decorCount.Position = UDim2.fromOffset(20, 40)
	self.decorCount.Size = UDim2.fromOffset(190, 18)
	self.decorCount.ZIndex = 4
	self.decorCount.Parent = top
	-- the Style meter: the score, the level, a bar to the next level, what it pays
	local styleTag = Kit.text("STYLE", 13, C.teal, 1.5)
	styleTag.TextXAlignment = Enum.TextXAlignment.Left
	styleTag.Position = UDim2.fromOffset(222, 9)
	styleTag.Size = UDim2.fromOffset(60, 16)
	styleTag.ZIndex = 4
	styleTag.Parent = top
	self.styleScore = Kit.text("0", 26, C.white, 2.5)
	self.styleScore.TextXAlignment = Enum.TextXAlignment.Left
	self.styleScore.Position = UDim2.fromOffset(276, 4)
	self.styleScore.Size = UDim2.fromOffset(90, 28)
	self.styleScore.ZIndex = 4
	self.styleScore.Parent = top
	self.styleLevel = Kit.text("", 13, C.gold, 1.5)
	self.styleLevel.TextXAlignment = Enum.TextXAlignment.Right
	self.styleLevel.Position = UDim2.fromOffset(380, 9)
	self.styleLevel.Size = UDim2.fromOffset(100, 16)
	self.styleLevel.ZIndex = 4
	self.styleLevel.Parent = top
	local strack, sfill = Kit.bar(258, 12, C.teal)
	strack.Position = UDim2.fromOffset(222, 34)
	strack.ZIndex = 4
	strack.Parent = top
	self.styleFill = sfill
	self.stylePays = Kit.text("", 12, C.muted, 1.5, Kit.Body)
	self.stylePays.TextXAlignment = Enum.TextXAlignment.Left
	self.stylePays.Position = UDim2.fromOffset(222, 49)
	self.stylePays.Size = UDim2.fromOffset(258, 15)
	Kit.fit(self.stylePays, 12, 8)
	self.stylePays.ZIndex = 4
	self.stylePays.Parent = top
	local function topButton(text: string, color: Color3, x: number, w: number, fn: () -> ())
		local b = Kit.button(text, color, UDim2.fromOffset(w, 48), 19)
		b.root.Position = UDim2.fromOffset(x, 11)
		b.root.ZIndex = 5
		b.root.Parent = top
		b.onClick = fn
		return b
	end
	self.lookBtn = topButton("Look", C.purple, 500, 104, function() self:nextLook() end)
	self.resetBtn = topButton("Reset", C.grey, 612, 104, function() self:reset() end)
	self.doneBtn = topButton("Done", C.green, 724, 120, function() self:done() end)
	local close = Kit.close(52)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, -24, 0, 24)
	close.root.Parent = root
	close.onClick = function() self:leave() end

	-- the catalogue, down the right
	local drawer = UI.mk("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.56, 0), Size = UDim2.fromOffset(352, 560), BackgroundTransparency = 1, Active = true, Parent = root })
	UI.autoScale(drawer, 1280, 760)
	Kit.slice("panel_body", nil, drawer, 1, 0.45)
	Kit.slice("panel_ring", C.teal, drawer, 2, 0.45)
	self.drawer = drawer
	self.tab = "tools"
	self.tabs = {}
	local tabList = {}
	for _, c in ipairs(Game.DecorCats) do table.insert(tabList, c) end
	table.insert(tabList, { id = "floor", name = "Floor" })
	table.insert(tabList, { id = "fence", name = "Fence" })
	for i, t in ipairs(tabList) do
		local tb = Kit.tab(t.name, UDim2.fromOffset(78, 28), t.id == self.tab)
		tb.root.Position = UDim2.fromOffset(12 + ((i - 1) % 4) * 82, 12 + math.floor((i - 1) / 4) * 32)
		tb.root.ZIndex = 4
		tb.root.Parent = drawer
		tb.onClick = function() self:showTab(t.id) end
		self.tabs[t.id] = tb
	end
	-- the week's theme
	self.themeLine = Kit.text("", 13, C.gold, 1.5, Kit.Body)
	self.themeLine.TextXAlignment = Enum.TextXAlignment.Left
	self.themeLine.Position = UDim2.fromOffset(16, 80)
	self.themeLine.Size = UDim2.fromOffset(320, 18)
	Kit.fit(self.themeLine, 13, 8)
	self.themeLine.ZIndex = 4
	self.themeLine.Parent = drawer
	self.shelf = UI.mk("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 102), Size = UDim2.new(1, -20, 1, -112), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 5, ScrollBarImageColor3 = C.line,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 3, Parent = drawer,
	})
	UI.mk("UIGridLayout", { CellSize = UDim2.fromOffset(CARD_W, CARD_H), CellPadding = UDim2.fromOffset(6, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.shelf })
	UI.mk("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8), Parent = self.shelf })
	self.cards = {}

	-- the sets, down the left
	local sets = UI.mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -18), Size = UDim2.fromOffset(270, 54 + #Game.DecorSets * 27), BackgroundTransparency = 1, Active = true, Parent = root })
	UI.autoScale(sets, 1280, 760)
	Kit.slice("panel_body", nil, sets, 1, 0.45)
	Kit.slice("panel_ring", C.gold, sets, 2, 0.45)
	local setsTitle = Kit.text("SETS", 17, C.white, 2)
	setsTitle.TextXAlignment = Enum.TextXAlignment.Left
	setsTitle.Position = UDim2.fromOffset(16, 10)
	setsTitle.Size = UDim2.fromOffset(120, 20)
	setsTitle.ZIndex = 4
	setsTitle.Parent = sets
	local setsNote = Kit.text(("Whole set +%d style"):format(Game.Style.SetBonus), 12, C.muted, 1.5, Kit.Body)
	setsNote.AnchorPoint = Vector2.new(1, 0)
	setsNote.TextXAlignment = Enum.TextXAlignment.Right
	setsNote.Position = UDim2.new(1, -16, 0, 13)
	setsNote.Size = UDim2.fromOffset(140, 16)
	setsNote.ZIndex = 4
	setsNote.Parent = sets
	self.setRows = {}
	for i, st in ipairs(Game.DecorSets) do
		local y = 38 + (i - 1) * 27
		local name = Kit.text(st.name, 14, C.text, 1.5, Kit.Body)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(16, y)
		name.Size = UDim2.fromOffset(130, 18)
		Kit.fit(name, 14, 9)
		name.ZIndex = 4
		name.Parent = sets
		local trackS, fillS = Kit.bar(70, 10, C.gold, "off")
		trackS.Position = UDim2.fromOffset(150, y + 4)
		trackS.ZIndex = 4
		trackS.Parent = sets
		local count = Kit.text("", 13, C.gold, 1.5, Kit.Body)
		count.AnchorPoint = Vector2.new(1, 0)
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.Position = UDim2.new(1, -14, 0, y)
		count.Size = UDim2.fromOffset(40, 18)
		count.ZIndex = 4
		count.Parent = sets
		self.setRows[st.id] = { name = name, fill = fillS, count = count, n = #st.pieces }
	end

	-- the bar along the bottom: what's selected and what to do with it, or how to start
	local bar = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, -60, 1, -18), Size = UDim2.fromOffset(560, 64), BackgroundTransparency = 1, Active = true, Parent = root })
	UI.autoScale(bar, 1280, 760)
	self.bar = bar
	local plate = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = bar })
	Kit.slice("panel_body", nil, plate, 1, 0.45)
	self.barRing = Kit.slice("panel_ring", PLATE_SEL, plate, 2, 0.45)
	self.selLabel = Kit.text("", 17, PLATE_SEL, 2)
	self.selLabel.TextXAlignment = Enum.TextXAlignment.Left
	self.selLabel.Position = UDim2.fromOffset(18, 0)
	self.selLabel.Size = UDim2.fromOffset(260, 64)
	Kit.fit(self.selLabel, 17, 10)
	self.selLabel.ZIndex = 5
	self.selLabel.Parent = bar
	local how = UserInputService.TouchEnabled and "Drag anything to move it.  Two fingers look round."
		or "Click anything to move it.  R turns.  Z undoes.  Right-drag looks round.  WASD pans.  F resets the view."
	self.hint = Kit.text(how, 15, C.white, 1.5, Kit.Body)
	self.hint.Position = UDim2.fromOffset(16, 0)
	self.hint.Size = UDim2.new(1, -32, 1, 0)
	Kit.fit(self.hint, 15, 9)
	self.hint.ZIndex = 5
	self.hint.Parent = bar
	local function barButton(text: string, color: Color3, x: number, fn: () -> ())
		local b = Kit.button(text, color, UDim2.fromOffset(124, 46), 19)
		b.root.Position = UDim2.fromOffset(x, 9)
		b.root.ZIndex = 6
		b.root.Parent = bar
		b.onClick = fn
		return b
	end
	self.turnBtn = barButton("Turn", C.blue, 290, function() self:turn() end)
	self.removeBtn = barButton("Remove", C.red, 422, function() self:remove() end)
	return self
end

function YardEdit:isOpen(): boolean
	return self.open_
end

--==============================================================
-- what's what
--==============================================================
-- the spot of a unit or a piece of decor (the table itself, so it can be moved in place)
function YardEdit:spot(id: string): any
	local i = decorIndex(id)
	if i then return (self.layout.decor :: any)[i] end
	return self.layout[id]
end

function YardEdit:boxes(id: string): { { number } }
	local i = decorIndex(id)
	if i then return { Game.decorBox((self.layout.decor :: any)[i]) } end
	local s = self.layout[id]
	return Game.yardBoxes(id, s.x, s.z, s.r)
end

function YardEdit:tier(): number
	return (self.plotModel and self.plotModel:GetAttribute("V2_Tier") :: number?) or 1
end

-- the floor this yard has at its stage
function YardEdit:floor()
	return Game.yardFloor(self:tier())
end

-- the drawn state and the footprint plate of every piece of decor, rebuilt after one's added or removed
function YardEdit:syncDecor()
	for id in pairs(self.shown) do
		if decorIndex(id) then self.shown[id] = nil end
	end
	for id, list in pairs(self.plates) do
		if decorIndex(id) then
			for _, p in ipairs(list) do p:Destroy() end
			self.plates[id] = nil
		end
	end
	for i, d in ipairs(self.layout.decor or {}) do
		local id = "d" .. i
		self.shown[id] = { x = d.x, z = d.z, r = d.r, a = Game.decorAngle(d), h = 0, vh = 0, lean = Vector2.zero, placed = true }
		self.plates[id] = { flat(self.folder, "Footprint_" .. id, Vector3.new(1, 0.12, 1), self.base, PLATE_IDLE, 0.7) }
	end
	self:drawDecor()
	self:refreshPlates()
	self:refreshDrawer()
end

-- the decor drawn where it's shown (lifted while held)
function YardEdit:drawDecor()
	local list, lifts = {}, {}
	for i, d in ipairs(self.layout.decor or {}) do
		local sh = self.shown["d" .. i]
		if sh then
			list[i] = { k = d.k, x = sh.x, z = sh.z, r = sh.r, a = sh.a }
			lifts[i] = CFrame.new(0, sh.h, 0) * CFrame.Angles(-sh.lean.Y, 0, sh.lean.X)
		else
			list[i] = d
		end
	end
	self.plot2:renderDecor(self.plotModel, list, lifts)
end

--==============================================================
-- the decor drawer
--==============================================================
-- a card per kind: the model turning in a little well, its name, a padlock until its stage
function YardEdit:buildDrawer()
	if self.drawerBuilt then return end
	self.drawerBuilt = true
	for i, kind in ipairs(Game.YardDecor) do
		local b = UI.mk("TextButton", {
			Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = i, ZIndex = 4, Parent = self.shelf,
		})
		local holder = UI.mk("Frame", { Name = "Holder", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4, Parent = b })
		Kit.slot(holder, Kit.NEUTRAL, 4)
		local vp = UI.mk("ViewportFrame", {
			Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(CARD_W - 12, CARD_W - 18), BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(150, 150, 156), LightColor = Color3.fromRGB(255, 244, 228), LightDirection = Vector3.new(-0.4, -1, -0.6), ZIndex = 6, Parent = holder,
		})
		local built = kind.build and NeonDecor.build(kind.id, NeonDecor.optsFor(self.plotModel))
		local tpl = not kind.build and Models.get(kind.path)
		if built then built.Parent = vp end
		if tpl or built then
			local m = built or Models.place(tpl, vp, CFrame.new(), 1)
			local cf, size = m:GetBoundingBox()
			local r = size.Magnitude / 2
			local cam = Instance.new("Camera")
			cam.FieldOfView = 30
			cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(-0.7, 0.55, -1).Unit * r * 3.6, cf.Position)
			cam.Parent = vp
			vp.CurrentCamera = cam
		end
		local name = Kit.text(kind.name, 13, C.white, 1.5)
		name.Position = UDim2.fromOffset(4, CARD_H - 30)
		name.Size = UDim2.fromOffset(CARD_W - 8, 16)
		Kit.fit(name, 13)
		name.ZIndex = 8
		name.Parent = holder
		local lockLabel = Kit.text(if kind.prestige then ("Prestige " .. kind.prestige) elseif kind.pass then "Midnight pass" else ("Stage " .. kind.tier), 11, C.gold, 1.5, Kit.Body)
		lockLabel.Position = UDim2.fromOffset(4, CARD_H - 15)
		lockLabel.Size = UDim2.fromOffset(CARD_W - 8, 12)
		lockLabel.ZIndex = 8
		lockLabel.Parent = holder
		-- (open: the set it belongs to, in its place)
		local set = Game.DecorSetOf[kind.id]
		local setLabel = Kit.text(if set then set.name else "", 11, C.teal, 1.5, Kit.Body)
		setLabel.Position = UDim2.fromOffset(4, CARD_H - 15)
		setLabel.Size = UDim2.fromOffset(CARD_W - 8, 12)
		Kit.fit(setLabel, 11, 7)
		setLabel.ZIndex = 8
		setLabel.Parent = holder
		-- its style points, and x2 while its set is the week's theme
		local pts = Kit.text("+" .. Game.decorStyle(kind), 13, C.gold, 1.5)
		pts.AnchorPoint = Vector2.new(1, 0)
		pts.TextXAlignment = Enum.TextXAlignment.Right
		pts.Position = UDim2.new(1, -8, 0, 6)
		pts.Size = UDim2.fromOffset(50, 16)
		pts.ZIndex = 8
		pts.Parent = holder
		local theme = Kit.text("x2", 13, C.yellow, 2)
		theme.TextXAlignment = Enum.TextXAlignment.Left
		theme.Position = UDim2.fromOffset(8, 6)
		theme.Size = UDim2.fromOffset(30, 16)
		theme.ZIndex = 8
		theme.Visible = false
		theme.Parent = holder
		local veil = UI.mk("Frame", {
			Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BackgroundColor3 = Color3.fromRGB(8, 8, 12), BackgroundTransparency = 0.35,
			BorderSizePixel = 0, ZIndex = 9, Visible = false, Parent = holder,
		}, { UI.corner(8) })
		UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1,
			Image = Kit.Icon.lock, ZIndex = 10, Parent = veil,
		})
		b.MouseEnter:Connect(function() Kit.tween(holder, 0.14, { Position = UDim2.fromOffset(0, -4) }, Enum.EasingStyle.Back) end)
		b.MouseLeave:Connect(function() Kit.tween(holder, 0.14, { Position = UDim2.fromOffset(0, 0) }) end)
		b.Activated:Connect(function() self:addDecor(kind.id, b) end)
		self.cards[kind.id] = { button = b, veil = veil, lockLabel = lockLabel, setLabel = setLabel, theme = theme, cat = (kind :: any).cat }
	end
	-- the floor and fence cards: a swatch of the ground, the fence's model; the stage's own first
	local order = #Game.YardDecor
	for _, which in ipairs({ "floor", "fence" }) do
		for _, opt in ipairs(if which == "floor" then Game.YardFloors else Game.YardFences) do
			order += 1
			local b = UI.mk("TextButton", {
				Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = order, ZIndex = 4, Visible = false, Parent = self.shelf,
			})
			local holder = UI.mk("Frame", { Name = "Holder", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4, Parent = b })
			local slot = Kit.slot(holder, Kit.NEUTRAL, 4)
			if opt.id == "stage" or opt.id == "none" then
				UI.mk("ImageLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 48), Size = UDim2.fromOffset(70, 70), BackgroundTransparency = 1,
					Image = Kit.Icon.plot, ImageTransparency = if opt.id == "none" then 0.6 else 0, ZIndex = 6, Parent = holder,
				})
			else
				local vp = UI.mk("ViewportFrame", {
					Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(CARD_W - 12, CARD_W - 18), BackgroundTransparency = 1,
					Ambient = Color3.fromRGB(150, 150, 156), LightColor = Color3.fromRGB(255, 244, 228), LightDirection = Vector3.new(-0.4, -1, -0.6), ZIndex = 6, Parent = holder,
				})
				local cam = Instance.new("Camera")
				cam.FieldOfView = 30
				if which == "floor" then
					local slab = Instance.new("Part")
					slab.Anchored = true
					slab.Size = Vector3.new(8, 1, 8)
					slab.Material = (Enum.Material :: any)[opt.mat]
					slab.MaterialVariant = opt.variant or ""
					slab.Color = opt.color
					slab.Parent = vp
					cam.CFrame = CFrame.lookAt(Vector3.new(-9, 12, -9), Vector3.zero)
				else
					local tpl = Models.get(opt.path)
					if tpl then
						local fm = Models.place(tpl, vp, CFrame.new(), 1)
						local cf, size = fm:GetBoundingBox()
						cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(-0.55, 0.35, -1).Unit * size.Magnitude * 1.7, cf.Position)
					end
				end
				cam.Parent = vp
				vp.CurrentCamera = cam
			end
			local name = Kit.text(opt.name, 13, C.white, 1.5)
			name.Position = UDim2.fromOffset(4, CARD_H - 30)
			name.Size = UDim2.fromOffset(CARD_W - 8, 16)
			Kit.fit(name, 13)
			name.ZIndex = 8
			name.Parent = holder
			local lockLabel = Kit.text("Stage " .. opt.tier, 11, C.gold, 1.5, Kit.Body)
			lockLabel.Position = UDim2.fromOffset(4, CARD_H - 15)
			lockLabel.Size = UDim2.fromOffset(CARD_W - 8, 12)
			lockLabel.ZIndex = 8
			lockLabel.Parent = holder
			local veil = UI.mk("Frame", {
				Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BackgroundColor3 = Color3.fromRGB(8, 8, 12), BackgroundTransparency = 0.35,
				BorderSizePixel = 0, ZIndex = 9, Visible = false, Parent = holder,
			}, { UI.corner(8) })
			UI.mk("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1,
				Image = Kit.Icon.lock, ZIndex = 10, Parent = veil,
			})
			b.MouseEnter:Connect(function() Kit.tween(holder, 0.14, { Position = UDim2.fromOffset(0, -4) }, Enum.EasingStyle.Back) end)
			b.MouseLeave:Connect(function() Kit.tween(holder, 0.14, { Position = UDim2.fromOffset(0, 0) }) end)
			b.Activated:Connect(function() self:pickSkin(which, opt.id, b) end)
			local edge = slot:FindFirstChild("Edge")
			self.cards[which .. ":" .. opt.id] = {
				button = b, veil = veil, lockLabel = lockLabel, cat = which, skin = which, opt = opt,
				stroke = edge and edge:FindFirstChild("Rarity") :: UIStroke?,
			}
		end
	end
end

-- the drawer shows one tab at a time
function YardEdit:showTab(id: string)
	self.tab = id
	for tid, tb in pairs(self.tabs) do tb.setColor(if tid == id then C.accent else C.grey) end
	self.shelf.CanvasPosition = Vector2.zero
	Sound.play("gateWhoosh", { volume = 0.15, pitch = 1.9 })
	self:refreshDrawer()
end

-- a floor or fence card: shown on the yard straight away, kept by DONE
function YardEdit:pickSkin(which: string, id: string, card: GuiObject?)
	if self.closing then return end
	local opt = (if which == "floor" then Game.YardFloorsById else Game.YardFencesById)[id]
	if not opt then return end
	if opt.tier > self:tier() then
		if card then shakeCard(card) end
		Kit.callout(self.gui, ("Unlocks at stage %d"):format(opt.tier), C.red, UDim2.fromScale(0.5, 0.2), 30)
		return
	end
	self:snapshot()
	self.layout[which] = id
	self.stats.skins += 1
	PlotStage.preview(self.plotModel, self.layout.floor or "stage", self.layout.fence or "stage")
	if card then Kit.pop(card, 0.9, 0.2) end
	Kit.callout(self.gui, opt.name, C.purple, UDim2.fromScale(0.5, 0.2), 30)
	Sound.play("land", { volume = 0.35, pitch = 1.3 })
	self:refreshDrawer()
end

-- the models a unit or a piece of decor is drawn with
function YardEdit:modelsOf(id: string?): { Instance }
	if not id then return {} end
	local i = decorIndex(id)
	if i then
		local y = self.plot2.yards[self.plotModel]
		local e = y and y.decor and y.decor[i]
		return if e and e.model then { e.model } else {}
	end
	return self.plot2:unitModels(self.plotModel, id)
end

-- whatever's selected stays outlined in gold; what's under the pointer gets a faint white line
function YardEdit:refreshSelection()
	if not self.folder then return end
	self.highlights = self.highlights or {}
	local want = {}
	for _, m in ipairs(self:modelsOf(self.selected)) do want[m] = "sel" end
	if self.hover and self.hover ~= self.selected then
		for _, m in ipairs(self:modelsOf(self.hover)) do want[m] = want[m] or "hover" end
	end
	for m, h in pairs(self.highlights) do
		if not want[m] or not m.Parent then
			h:Destroy()
			self.highlights[m] = nil
		end
	end
	for m, kind in pairs(want) do
		local h = self.highlights[m]
		if not h then
			h = Instance.new("Highlight")
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Adornee = m
			h.Parent = self.folder
			self.highlights[m] = h
		end
		if kind == "sel" then
			h.OutlineColor, h.OutlineTransparency = PLATE_SEL, 0
			h.FillColor, h.FillTransparency = PLATE_SEL, 0.82
		else
			h.OutlineColor, h.OutlineTransparency = Color3.new(1, 1, 1), 0.45
			h.FillTransparency = 1
		end
	end
	-- the name over the buttons, and the buttons that can act on it
	local name = nil
	local i = decorIndex(self.selected)
	if i then
		local d = (self.layout.decor :: any)[i]
		local kind = d and Game.YardDecorById[d.k]
		name = kind and kind.name
	elseif self.selected then
		local u = Game.YardUnits[self.selected]
		name = u and (u :: any).name or self.selected
	end
	self.selLabel.Text = if name then string.upper(name) else ""
	self.selLabel.Visible = name ~= nil
	self.hint.Visible = name == nil
	self.turnBtn.root.Visible = name ~= nil
	self.removeBtn.root.Visible = name ~= nil
	self.barRing.ImageColor3 = if name then PLATE_SEL else C.teal
	self.turnBtn.setEnabled(self.selected ~= nil)
end

function YardEdit:refreshDrawer()
	-- (the style first: the cards read the week's theme from it)
	self:refreshStyle()
	local tier = self:tier()
	local count, max = #(self.layout.decor or {}), Game.yardDecorMax(tier)
	self.decorCount.Text = ("%d / %d pieces"):format(count, max)
	for _, kind in ipairs(Game.YardDecor) do
		local c = self.cards[kind.id]
		if c then
			local open = kind.tier <= tier and self:owns(kind)
			c.veil.Visible = not open
			c.lockLabel.Visible = not open
			c.setLabel.Visible = open
			local set = Game.DecorSetOf[kind.id]
			c.theme.Visible = set ~= nil and set.id == self.themeId
		end
	end
	for _, c in pairs(self.cards) do
		c.button.Visible = c.cat == self.tab
		if c.skin then
			local open = c.opt.tier <= tier
			c.veil.Visible = not open
			c.lockLabel.Visible = not open
			local chosen = (self.layout[c.skin] or "stage") == c.opt.id
			if c.stroke then c.stroke.Color = if chosen then PLATE_SEL else Kit.NEUTRAL end
		end
	end
	self.removeBtn.setEnabled(decorIndex(self.selected) ~= nil)
	self:refreshSelection()
	self:refreshStyle()
end

-- the Style meter and the sets, worked out from the layout as it stands (Game.yardStyle)
function YardEdit:refreshStyle()
	if not self.layout then return end
	local prof = self.plot2 and self.plot2.profile
	local v = prof and prof.v2
	local Goals = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Goals")) :: any
	local week = Goals.utcWeek()
	local look = self.lookChoice and string.match(self.lookChoice, "^[%w_]+") or string.match(self.lookSaved or "stage", "^[%w_]+")
	local st = Game.yardStyle(self.layout, look, Game.perkLv(v, "showman"), week)
	local theme = Game.styleTheme(week)
	self.themeId = theme and theme.id
	local before = self.shownStyle
	self.shownStyle = st.score
	self.styleScore.Text = tostring(st.score)
	if before and st.score > before then Kit.pop(self.styleScore, 1.35, 0.3) end
	local lv = Game.styleLevel(st.score)
	self.styleLevel.Text = ("LEVEL %d"):format(lv)
	local into = (st.score % Game.Style.LevelEvery) / Game.Style.LevelEvery
	self.styleFill.Size = UDim2.fromScale(into, 1)
	self.stylePays.Text = ("Auto-cannon and offline pay +%d%%"):format(math.floor((Game.styleBonus(st.score) - 1) * 100 + 0.5))
	self.themeLine.Text = if theme then ("THIS WEEK: %s  ·  its pieces count x2, the whole set pays %d keys"):format(string.upper(theme.name), Game.Style.ThemeKeys) else ""
	for id, row in pairs(self.setRows) do
		local have = st.sets[id] or 0
		row.count.Text = ("%d/%d"):format(have, row.n)
		row.fill.Size = UDim2.fromScale(have / row.n, 1)
		local whole = have >= row.n
		row.name.TextColor3 = if whole then C.green elseif id == self.themeId then C.yellow else C.text
		row.name.Text = (if id == self.themeId then "★ " else "") .. Game.DecorSetsById[id].name
	end
	for _, c in pairs(self.cards) do
		if c.theme then c.theme.Visible = c.theme.Visible end
	end
end

-- add a piece near the middle of the view, on the first free spot spiralling out from it
function YardEdit:addDecor(kindId: string, card: GuiObject?)
	if self.closing then return end
	-- (a piece still on the pointer goes back in the drawer first)
	if self.carrying then self:cancelCarry() end
	local kind = Game.YardDecorById[kindId]
	local tier = self:tier()
	if kind and not self:owns(kind) then
		if card then shakeCard(card) end
		if kind.pass then
			Kit.callout(self.gui, "Part of the Midnight Garage pass", C.purple, UDim2.fromScale(0.5, 0.2), 30)
			self:offerPass()
		else
			Kit.callout(self.gui, ("Unlocks at Prestige %d"):format(kind.prestige or 0), C.red, UDim2.fromScale(0.5, 0.2), 30)
		end
		return
	end
	if not kind or kind.tier > tier then
		if card then shakeCard(card) end
		Kit.callout(self.gui, ("Unlocks at stage %d"):format(kind and kind.tier or 0), C.red, UDim2.fromScale(0.5, 0.2), 30)
		return
	end
	local decor = self.layout.decor
	if #decor >= Game.yardDecorMax(tier) then
		if card then shakeCard(card) end
		Kit.callout(self.gui, "No more room for decor at this stage", C.red, UDim2.fromScale(0.5, 0.2), 28)
		return
	end
	local G = Game.Yard.Grid
	local F = self:floor()
	local cx = math.floor(self.view.target.X / G + 0.5) * G
	local cz = math.floor(self.view.target.Z / G + 0.5) * G
	local entry = { k = kindId, x = cx, z = cz, r = 0 }
	self:snapshot()
	table.insert(decor, entry)
	local n = #decor
	local found = false
	for ring = 0, 30 do
		for dx = -ring, ring do
			for dz = -ring, ring do
				if math.max(math.abs(dx), math.abs(dz)) == ring and not found then
					entry.x = math.clamp(cx + dx * G * 2, F.x0, F.x1)
					entry.z = math.clamp(cz + dz * G * 2, F.z0, F.z1)
					local _, bad = Game.yardCheck(self.layout, self:tier())
					if not bad["d" .. n] then found = true end
				end
			end
		end
		if found then break end
	end
	if not found then
		table.remove(decor, n)
		self:dropSnapshot()
		Kit.callout(self.gui, "No free floor for that", C.red, UDim2.fromScale(0.5, 0.2), 30)
		return
	end
	self:syncDecor()
	self.stats.added += 1
	local id = "d" .. n
	local sh = self.shown[id]
	self.selected = id
	if card then Kit.pop(card, 0.9, 0.2) end
	Sound.play("gateWhoosh", { volume = 0.3, pitch = 1.5 })
	if UserInputService.MouseEnabled then
		-- with a mouse it comes up on the end of the pointer, held, until a click sets it down
		local m = UserInputService:GetMouseLocation() - game:GetService("GuiService"):GetGuiInset()
		local p = self:floorAt(m)
		if p then
			local s = (decor :: any)[n]
			self.settledFor = nil
			self:settle(id, p.X, p.Z)
			sh.x, sh.z = s.x, s.z
		end
		self.held = id
		self.carrying = id
		self.grab = Vector3.zero
		self.pickedFrom = nil
		sh.h, sh.vh = 0, 14
	else
		-- on a touch screen it floats near the middle of the view until you tap where it goes
		sh.h, sh.vh = LIFT * 2.5, 0
		self.held = id
		self.carrying = id
		self.grab = Vector3.zero
		self.pickedFrom = nil
		Kit.callout(self.gui, "Tap where it goes", C.white, UDim2.fromScale(0.5, 0.2), 28)
	end
	self:refreshPlates()
	self:refreshDrawer()
end

-- a piece fresh from the drawer goes back in it
--==============================================================
-- undo: a copy of the layout before each change, newest last (40 kept)
--==============================================================
function YardEdit:snapshot()
	if not self.undo then self.undo = {} end
	table.insert(self.undo, copy(self.layout))
	if #self.undo > 40 then table.remove(self.undo, 1) end
end

function YardEdit:dropSnapshot()
	if self.undo and #self.undo > 0 then table.remove(self.undo) end
end

function YardEdit:undoStep()
	if self.closing or self.saving then return end
	-- a piece in the hand goes back first (that's the undo, if it was all there was)
	if self.carrying then
		self:cancelCarry()
		self:dropSnapshot()
		return
	end
	if self.held then
		self:putBack()
		return
	end
	local prev = self.undo and table.remove(self.undo)
	if not prev then
		Kit.callout(self.gui, "Nothing to undo", C.muted, UDim2.fromScale(0.5, 0.2), 26)
		return
	end
	self.layout = prev
	self.selected = nil
	self.hover = nil
	self.settledFor = nil
	for _, u in ipairs(Game.Yard.Units) do self:shortWay(u.id) end
	PlotStage.preview(self.plotModel, self.layout.floor or "stage", self.layout.fence or "stage")
	self:syncDecor()
	self:refreshPlates()
	self:refreshDrawer()
	self:refreshSelection()
	Sound.play("gateWhoosh", { volume = 0.25, pitch = 1.1 })
end

-- what's lifted goes back where it was picked up (a second finger, or undo while holding)
function YardEdit:putBack()
	local id = self.held
	local from = self.pickedFrom
	self.held = nil
	if id and from then
		local s = self:spot(id)
		if s then
			s.x, s.z, s.r = from.x, from.z, from.r
			if decorIndex(id) then (s :: any).a = from.a end
			self:shortWay(id)
		end
	end
	self:dropSnapshot()
	self.landing = id
	self:refreshPlates()
end

-- a thing's shown turn brought round to the nearest equal of where it's going, so it never spins
-- the long way back
function YardEdit:shortWay(id: string)
	local sh = self.shown and self.shown[id]
	local s = self:spot(id)
	if not (sh and s) then return end
	if sh.r then
		while sh.r - s.r > 2 do sh.r -= 4 end
		while s.r - sh.r > 2 do sh.r += 4 end
	end
	if sh.a and (s :: any).a then
		local a = (s :: any).a
		while sh.a - a > 12 do sh.a -= 24 end
		while a - sh.a > 12 do sh.a += 24 end
	end
end

function YardEdit:cancelCarry()
	local id = self.carrying
	self.carrying = nil
	self.held = nil
	local i = decorIndex(id)
	if i then
		table.remove(self.layout.decor, i)
		self.selected = nil
		Sound.play("gateWhoosh", { volume = 0.3, pitch = 0.9 })
		self:syncDecor()
	end
end

-- does this yard's owner have what a decor kind or a look needs (prestige level, the pass)?
function YardEdit:owns(item: any): boolean
	local plot = self.plotModel
	local prestige = plot and (plot:GetAttribute("V2_Prestige") :: number?) or 0
	local passes = { midnight = plot ~= nil and plot:GetAttribute("V2_Midnight") == true }
	return Game.lookOpen(item, prestige, passes)
end

-- every look to cycle through: the stage's, the Hall of Prestige, each Midnight Garage colourway
local function lookChoices(): { string }
	local out = {}
	for _, l in ipairs(Game.YardLooks) do
		if l.ways then
			for _, w in ipairs(l.ways) do table.insert(out, l.id .. ":" .. w.id) end
		else
			table.insert(out, l.id)
		end
	end
	return out
end

-- the next look, previewed on the floor; DONE keeps it
function YardEdit:nextLook()
	if self.closing then return end
	local list = lookChoices()
	local now = self.lookChoice or self.lookSaved or "stage"
	local i = table.find(list, now) or table.find(list, (string.match(now, "^[%w_]+"))) or 0
	self.lookChoice = list[i % #list + 1]
	YardLook.apply(self.plotModel, self.layout, self.lookChoice)
	local id, way = string.match(self.lookChoice, "^([%w_]+):?(.*)$")
	local look = Game.YardLooksById[id]
	local name = look.name .. (if way ~= "" then " (" .. way .. ")" else "")
	if self:owns(look) then
		Kit.callout(self.gui, name, C.purple, UDim2.fromScale(0.5, 0.2), 30)
	elseif look.pass then
		Kit.callout(self.gui, name .. ": Midnight Garage pass, R$ " .. (Config.StorePassesById.midnight and Config.StorePassesById.midnight.robux or 699), C.purple, UDim2.fromScale(0.5, 0.2), 28)
	else
		Kit.callout(self.gui, name .. ": unlocks at Prestige " .. (look.prestige or 1), C.red, UDim2.fromScale(0.5, 0.2), 28)
	end
	Sound.play("gateWhoosh", { volume = 0.25, pitch = 1.2 })
	self:refreshStyle()
end

-- the Midnight Garage pass's purchase prompt (or a note while it isn't on sale yet)
function YardEdit:offerPass()
	local pass = Config.StorePassesById.midnight
	if pass and pass.passId ~= 0 then
		pcall(function() MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.passId) end)
	else
		Kit.callout(self.gui, "The Midnight Garage pass is coming soon", C.purple, UDim2.fromScale(0.5, 0.28), 26)
	end
end

function YardEdit:remove()
	local i = decorIndex(self.selected)
	if not i or self.closing then return end
	if not self.carrying then self:snapshot() end
	table.remove(self.layout.decor, i)
	self.selected = nil
	self.held = nil
	self.carrying = nil
	Sound.play("gateWhoosh", { volume = 0.3, pitch = 0.9 })
	self:syncDecor()
end

--==============================================================
-- open and close
--==============================================================
function YardEdit:open(plot: Instance, onClose: (() -> ())?)
	if self.open_ then return end
	local base = plot:GetAttribute("BaseCFrame") :: CFrame?
	local y = self.plot2.yards[plot]
	if not (base and y) then
		-- (not ready to edit: hand straight back, so the hub comes back rather than leaving you stuck)
		if onClose then task.defer(onClose) end
		return
	end
	self.open_ = true
	self.plotModel = plot
	self.base = base
	self.onClose = onClose
	-- the saved layout as this stage's rules have it (after a prestige the yard is stage 1 again:
	-- anything that no longer fits is put home or taken off, so the editor opens on a valid yard)
	local access = { prestige = (plot:GetAttribute("V2_Prestige") :: number?) or 0, passes = { midnight = plot:GetAttribute("V2_Midnight") == true } }
	self.saved = Game.yardFit(self.plot2:layoutOf(plot), self:tier(), access)
	self.undo = {}
	self.saving = false
	self.touch = nil
	self.lastPointer = nil
	self.lookSaved = (plot:GetAttribute("V2_Look") :: string?) or "stage"
	self.lookChoice = nil
	self.layout = copy(self.saved)
	-- what's drawn: each thing eases toward its spot on the grid, lifts while held, leans as it moves
	self.shown = {}
	for _, u in ipairs(Game.Yard.Units) do
		local s = self.layout[u.id]
		self.shown[u.id] = { x = s.x, z = s.z, r = s.r, h = 0, vh = 0, lean = Vector2.zero }
	end
	y.editing = true
	-- (PlotPaths hides this yard's path while it's rearranged)
	plot:SetAttribute("TC_Editing", true)
	self.held = nil
	self.hover = nil
	self.selected = nil

	-- the floor's grid and a footprint plate under everything
	local folder = Instance.new("Folder")
	folder.Name = "YardEditor"
	folder.Parent = workspace
	self.folder = folder
	local F = self:floor()
	local lineCol = Color3.fromRGB(28, 26, 34)
	for x = F.x0 + 1, F.x1 - 1, 4 do
		flat(folder, "Grid", Vector3.new(0.14, 0.04, F.z1 - F.z0), base * CFrame.new(x, FLOOR_Y + 0.03, (F.z0 + F.z1) / 2), lineCol, 0.82)
	end
	for z = F.z0 + 2, F.z1 - 2, 4 do
		flat(folder, "Grid", Vector3.new(F.x1 - F.x0, 0.04, 0.14), base * CFrame.new((F.x0 + F.x1) / 2, FLOOR_Y + 0.03, z), lineCol, 0.82)
	end
	self.plates = {}
	for _, u in ipairs(Game.Yard.Units) do
		local list = {}
		for i = 1, #u.boxes do
			list[i] = flat(folder, "Footprint_" .. u.id, Vector3.new(1, 0.12, 1), base, PLATE_IDLE, 0.7)
		end
		self.plates[u.id] = list
	end

	-- the camera rises from wherever it was to the overview
	local cam = workspace.CurrentCamera
	self.savedCam = cam.CFrame
	self.savedFov = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	self.camFrom = cam.CFrame
	self.camT = 0
	self:resetView(true)
	self:buildDrawer()
	self:syncDecor()
	-- the plot signs float over the yard: hidden while editing
	self.hiddenSigns = {}
	for _, g in ipairs(game.Players.LocalPlayer.PlayerGui:GetChildren()) do
		if g:IsA("BillboardGui") and g.Name:sub(1, 9) == "PlotSign_" and g.Enabled then
			g.Enabled = false
			table.insert(self.hiddenSigns, g)
		end
	end
	self.root.Visible = true
	Kit.appear(self.root, 0.1, 30)

	ContextActionService:BindActionAtPriority("TC_YardTurn", function(_, st)
		if st == Enum.UserInputState.Begin then self:turn() end
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority("TC_YardRemove", function(_, st)
		if st == Enum.UserInputState.Begin then self:remove() end
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.KeyCode.Delete, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonX)
	-- Z (or Ctrl+Z) steps back: a move, a turn, a piece added or taken off, a reset, a floor or fence
	ContextActionService:BindActionAtPriority("TC_YardUndo", function(_, st)
		if st == Enum.UserInputState.Begin then self:undoStep() end
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.KeyCode.Z)
	self.pan = {}
	ContextActionService:BindActionAtPriority("TC_YardPan", function(_, st, io)
		self.pan[io.KeyCode] = st == Enum.UserInputState.Begin or st == Enum.UserInputState.Change
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right)
	ContextActionService:BindActionAtPriority("TC_YardLeave", function(_, st)
		if st == Enum.UserInputState.Begin then
			-- with a fresh piece on the pointer, Q drops it back in the drawer; otherwise it leaves
			if self.carrying then self:cancelCarry() else self:leave() end
		end
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)
	self.conns = {
		UserInputService.InputBegan:Connect(function(io, processed)
			if processed then return end
			if io.UserInputType == Enum.UserInputType.Touch then
				-- one finger moves things; a second finger (a pinch or a twist) puts back what was lifted
				if self.touch then
					if self.held and not self.carrying then self:putBack() end
					return
				end
				self.touch = io
				self.lastPointer = Vector2.new(io.Position.X, io.Position.Y)
				self:press(self.lastPointer)
			elseif io.UserInputType == Enum.UserInputType.MouseButton1 then
				self.lastPointer = Vector2.new(io.Position.X, io.Position.Y)
				self:press(Vector2.new(io.Position.X, io.Position.Y))
			elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
				self.orbiting = true
			elseif io.KeyCode == Enum.KeyCode.F then
				self:resetView(false)
			end
		end),
		UserInputService.InputChanged:Connect(function(io, processed)
			if io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch then
				-- (only the finger that started it, never a drawer scroll or a second finger)
				if io.UserInputType == Enum.UserInputType.Touch and io ~= self.touch then return end
				self.lastPointer = Vector2.new(io.Position.X, io.Position.Y)
				if self.orbiting and io.UserInputType == Enum.UserInputType.MouseMovement then
					self.view.yaw -= io.Delta.X * 0.006
					self.view.pitch = math.clamp(self.view.pitch + io.Delta.Y * 0.004, PITCH_MIN, PITCH_MAX)
				else
					self:drag(Vector2.new(io.Position.X, io.Position.Y))
				end
			elseif io.UserInputType == Enum.UserInputType.MouseWheel and not processed then
				-- carrying decor, the wheel angles it; otherwise it zooms
				if self.held and decorIndex(self.held) then
					self:angle(if io.Position.Z > 0 then 1 else -1)
				else
					self.view.dist = math.clamp(self.view.dist * (1 - io.Position.Z * 0.12), DIST_MIN, DIST_MAX)
				end
			end
		end),
		UserInputService.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch then
				if io ~= self.touch then return end
				self.touch = nil
				self:release()
				-- (no pointer left over the yard: nothing stays hovered)
				if self.hover then
					self.hover = nil
					self:refreshPlates()
					self:refreshSelection()
				end
			elseif io.UserInputType == Enum.UserInputType.MouseButton1 then
				self:release()
			elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
				self.orbiting = false
			end
		end),
		-- two fingers: pinch zooms, twist looks round
		UserInputService.TouchPinch:Connect(function(_, scale, _, state)
			if state == Enum.UserInputState.Begin then self.pinchFrom = self.view.dist end
			if self.pinchFrom then self.view.dist = math.clamp(self.pinchFrom / math.max(scale, 0.2), DIST_MIN, DIST_MAX) end
			if state == Enum.UserInputState.End then self.pinchFrom = nil end
		end),
		UserInputService.TouchRotate:Connect(function(_, rotation, _, state)
			if state == Enum.UserInputState.Begin then self.twistFrom = self.view.yaw end
			if self.twistFrom then self.view.yaw = self.twistFrom - math.rad(rotation) end
			if state == Enum.UserInputState.End then self.twistFrom = nil end
		end),
		RunService.RenderStepped:Connect(function(dt) self:step(dt) end),
	}
end

-- (2026-10-24) Q and the X used to throw away every unsaved change without a word: with changes,
-- the first press warns and a second within 3 s discards them
function YardEdit:leave()
	if self.saving then return end
	local HttpService = game:GetService("HttpService")
	local okA, a = pcall(HttpService.JSONEncode, HttpService, self.layout)
	local okB, b = pcall(HttpService.JSONEncode, HttpService, self.saved)
	local dirty = not (okA and okB and a == b)
	if dirty and not (self.discardAt and os.clock() - self.discardAt < 3) then
		self.discardAt = os.clock()
		Kit.callout(self.gui, "Unsaved changes: press again to discard", C.yellow, UDim2.fromScale(0.5, 0.2), 30)
		return
	end
	self.discardAt = nil
	self:close(false)
end

function YardEdit:close(save: boolean)
	-- (one save at a time: DONE twice, or Q during the round trip, waits for it)
	if not self.open_ or self.closing or self.saving then return end
	if save then
		self.saving = true
		local ok, res = pcall(function() return (self.R :: any).Layout:InvokeServer(self.layout) end)
		self.saving = false
		if ok and type(res) == "table" and res.ok and type(res.layout) == "string" then
			-- what the server kept is what's drawn
			self.layout = Game.yardDecode(res.layout)
		end
		if not (ok and type(res) == "table" and res.ok) then
			Kit.callout(self.gui, "Something's in the way", C.red, UDim2.fromScale(0.5, 0.2), 34)
			Kit.shake(self.doneBtn.root, 6, 0.25)
			return
		end
		Sound.play("land", { volume = 0.4, pitch = 1.4 })
		self.stats.saved += 1
		local choice = self.lookChoice
		if choice and choice ~= self.lookSaved then
			local id, way = string.match(choice, "^([%w_]+):?(.*)$")
			local look = Game.YardLooksById[id]
			if look and self:owns(look) then
				pcall(function() return (self.R :: any).Look:InvokeServer(id, way) end)
			elseif look and look.pass then
				self:offerPass()
			end
		end
	else
		-- unsaved: everything goes back where it was
		self.layout = copy(self.saved)
	end
	self.closing = true
	self.held = nil
	self.carrying = nil
	for _, h in pairs(self.highlights or {}) do h:Destroy() end
	self.highlights = {}
	ContextActionService:UnbindAction("TC_YardTurn")
	ContextActionService:UnbindAction("TC_YardRemove")
	ContextActionService:UnbindAction("TC_YardLeave")
	ContextActionService:UnbindAction("TC_YardPan")
	ContextActionService:UnbindAction("TC_YardUndo")
	self.orbiting = false
	for _, c in ipairs(self.conns or {}) do c:Disconnect() end
	self.conns = nil
	local plot = self.plotModel
	self.settledFor, self.settledAt = nil, nil
	PlotStage.preview(plot, nil, nil)
	for _, u in ipairs(Game.Yard.Units) do self.plot2:placeUnit(plot, self.layout, u.id) end
	self.plot2:renderDecor(plot, self.layout.decor or {})
	Kit.vanish(self.root, 0.18)
	-- the camera comes back down to where it was before handing back to the player
	local cam = workspace.CurrentCamera
	local from, fromFov = cam.CFrame, cam.FieldOfView
	local to, toFov = self.savedCam :: CFrame, self.savedFov :: number
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = smooth((os.clock() - t0) / 0.6)
		cam.CFrame = from:Lerp(to, k)
		cam.FieldOfView = fromFov + (toFov - fromFov) * k
		if k >= 1 then
			conn:Disconnect()
			cam.CameraType = Enum.CameraType.Custom
			if self.folder then self.folder:Destroy() end
			self.folder = nil
			local y = self.plot2.yards[plot]
			if y then y.editing = false end
			plot:SetAttribute("TC_Editing", nil)
			-- the floor shows the look that's saved, round the layout that's saved
			YardLook.apply(plot, self.plot2:layoutOf(plot))
			self.lookChoice = nil
			self.open_ = false
			self.closing = false
			for _, g in ipairs(self.hiddenSigns or {}) do
				if g.Parent then g.Enabled = true end
			end
			self.hiddenSigns = nil
			if self.onClose then self.onClose() end
		end
	end)
end

function YardEdit:done()
	self:close(true)
end

-- the machines back where they started (the decor stays)
function YardEdit:reset()
	self:snapshot()
	local start = Game.yardLayout(nil)
	for _, u in ipairs(Game.Yard.Units) do
		local s = start[u.id]
		self.layout[u.id] = { x = s.x, z = s.z, r = s.r }
	end
	self.held = nil
	Sound.play("gateWhoosh", { volume = 0.35, pitch = 1.3 })
	self:refreshPlates()
end

--==============================================================
-- the camera
--==============================================================
-- the view the camera orbits back to: the old fixed overview, as a target, yaw, pitch and distance
function YardEdit:resetView(instant: boolean)
	local at, look = tuned("YardCam", CAM_AT) :: Vector3, tuned("YardLook", CAM_LOOK) :: Vector3
	local off = at - look
	local flatLen = Vector2.new(off.X, off.Z).Magnitude
	local v = {
		target = look, yaw = math.atan2(off.Z, off.X), pitch = math.clamp(math.atan2(off.Y, flatLen), PITCH_MIN, PITCH_MAX),
		dist = math.clamp(off.Magnitude, DIST_MIN, DIST_MAX),
	}
	self.view = v
	if instant or not self.shownView then
		self.shownView = { target = v.target, yaw = v.yaw, pitch = v.pitch, dist = v.dist }
	end
end

function YardEdit:viewCFrame(v): CFrame
	local dir = Vector3.new(math.cos(v.yaw) * math.cos(v.pitch), math.sin(v.pitch), math.sin(v.yaw) * math.cos(v.pitch))
	-- (the camera slides right, so the yard sits in the open space left of the catalogue)
	return self.base * CFrame.lookAt(v.target + dir * v.dist, v.target) * CFrame.new(v.dist * 0.16, 0, 0)
end

--==============================================================
-- picking up, dragging, setting down
--==============================================================
-- where a screen point lands on the yard's floor, in plot space. Input positions leave out the
-- top bar, so the ray is cast with ScreenPointToRay (ViewportPointToRay aims a top bar too high,
-- and a click would land on whatever stands behind the pointer)
function YardEdit:floorAt(screen: Vector2): Vector3?
	local cam = workspace.CurrentCamera
	local ray = cam:ScreenPointToRay(screen.X, screen.Y)
	local o = self.base:PointToObjectSpace(ray.Origin)
	local d = self.base:VectorToObjectSpace(ray.Direction)
	if math.abs(d.Y) < 1e-4 then return nil end
	local t = (FLOOR_Y - o.Y) / d.Y
	if t < 0 then return nil end
	return o + d * t
end

-- the thing whose footprint is under a floor point: decor first (it's smaller), then the machines
function YardEdit:unitAt(p: Vector3): string?
	-- everything whose footprint is under the pointer (small things get a wider margin), and the
	-- smallest wins: the cannon's big box never swallows the barrel or crate sitting by it.
	-- Nothing under it: the nearest thing within a few studs.
	local best, bestArea = nil, math.huge
	-- (a near miss still finds it, a finger more generously; a click well clear of everything is bare floor)
	local near, nearD = nil, if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then 6 else 2.5
	local function try(id: string, box: { number })
		local w, d = box[3] - box[1], box[4] - box[2]
		local area = w * d
		local m = if area < 150 then 3 elseif area < 500 then 2 else 0.5
		if p.X >= box[1] - m and p.X <= box[3] + m and p.Z >= box[2] - m and p.Z <= box[4] + m then
			if area < bestArea then best, bestArea = id, area end
		end
		local cx, cz = (box[1] + box[3]) / 2, (box[2] + box[4]) / 2
		local dist = math.max(0, math.abs(p.X - cx) - w / 2) + math.max(0, math.abs(p.Z - cz) - d / 2)
		if dist < nearD then near, nearD = id, dist end
	end
	local decor = self.layout.decor or {}
	for i = #decor, 1, -1 do try("d" .. i, Game.decorBox(decor[i])) end
	for _, u in ipairs(Game.Yard.Units) do
		local s = self.layout[u.id]
		for _, box in ipairs(Game.yardBoxes(u.id, s.x, s.z, s.r)) do try(u.id, box) end
	end
	return best or near
end

-- the machine or piece of decor drawn under the pointer: the click ray against each one's own
-- box (the nearest it meets), so a tall machine is picked where you see it, not by the floor
-- behind it. Nothing met: whatever's footprint is under the floor point.
function YardEdit:pickAt(screen: Vector2, p: Vector3?): string?
	local cam = workspace.CurrentCamera
	local ray = cam:ScreenPointToRay(screen.X, screen.Y)
	local best: string? = nil
	local hits = {}
	local function test(id: string, m: Instance?)
		if not (m and m:IsA("Model") and m.Parent) then return end
		local cf, size = m:GetBoundingBox()
		local o = cf:PointToObjectSpace(ray.Origin)
		local d = cf:VectorToObjectSpace(ray.Direction)
		local h = size / 2
		local t0, t1 = -math.huge, math.huge
		for _, ax in ipairs({ "X", "Y", "Z" }) do
			local oa, da, ha = (o :: any)[ax], (d :: any)[ax], (h :: any)[ax]
			if math.abs(da) < 1e-6 then
				if oa < -ha or oa > ha then return end
			else
				local a, b = (-ha - oa) / da, (ha - oa) / da
				if a > b then a, b = b, a end
				t0, t1 = math.max(t0, a), math.min(t1, b)
				if t0 > t1 then return end
			end
		end
		local t = if t0 >= 0 then t0 else t1
		if t >= 0 then table.insert(hits, { id = id, t0 = math.max(t0, 0), t1 = t1, vol = size.X * size.Y * size.Z }) end
	end
	local y = self.plot2.yards[self.plotModel]
	if y then
		for _, u in ipairs(Game.Yard.Units) do
			for _, m in ipairs(self.plot2:unitModels(self.plotModel, u.id)) do test(u.id, m) end
		end
		for i, e in pairs(y.decor or {}) do
			if e and e.model then test("d" .. i, e.model) end
		end
	end
	-- the nearest box the ray meets, unless a smaller one starts inside it (decor standing by or in
	-- front of a machine's bounding box isn't lost in it; a piece hidden behind a tall one is)
	table.sort(hits, function(a, b) return a.t0 < b.t0 end)
	local first = hits[1]
	if first then
		best = first.id
		local vol = first.vol
		for i = 2, #hits do
			local h = hits[i]
			if h.t0 <= first.t1 and h.vol < vol then best, vol = h.id, h.vol end
		end
	end
	if best then return best end
	return p and self:unitAt(p) or nil
end

function YardEdit:press(screen: Vector2)
	if self.closing or self.saving then return end
	local p = self:floorAt(screen)
	if not p then return end
	-- a fresh piece on the pointer: this click sets it down (if it can stand there)
	if self.carrying then
		local id = self.carrying
		self:settle(id, p.X, p.Z)
		local ok, bad = Game.yardCheck(self.layout, self:tier())
		if not ok and bad[id] then
			Kit.callout(self.gui, "It can't go there", C.red, UDim2.fromScale(0.5, 0.2), 28)
			Sound.play("gateWhoosh", { volume = 0.25, pitch = 0.7 })
			return
		end
		self.carrying = nil
		self.held = nil
		self.landing = id
		self:refreshPlates()
		self:refreshSelection()
		return
	end
	local id = self:pickAt(screen, p)
	if not id then
		-- a click on bare floor clears the selection
		self.selected = nil
		self:refreshPlates()
		self:refreshDrawer()
		return
	end
	local s = self:spot(id)
	self:snapshot()
	self.held = id
	self.selected = id
	self.settledFor = nil
	self.grab = Vector3.new(s.x - p.X, 0, s.z - p.Z)
	self.pickedFrom = { x = s.x, z = s.z, r = s.r, a = s.a }
	self.shown[id].vh = 14
	Sound.play("gateWhoosh", { volume = 0.3, pitch = 1.6 })
	self:refreshPlates()
	self:refreshDrawer()
end

function YardEdit:drag(screen: Vector2)
	local p = self:floorAt(screen)
	if not p then return end
	if not self.held then
		local was = self.hover
		self.hover = self:pickAt(screen, p)
		if self.hover ~= was then
			self:refreshPlates()
			self:refreshSelection()
		end
		return
	end
	self:settle(self.held, p.X + self.grab.X, p.Z + self.grab.Z)
	self:refreshPlates()
end

-- puts a carried thing on the grid at (tx, tz), or, when something's there, on the nearest free
-- spot within 10 studs (it's drawn there like a magnet); nowhere free: at (tx, tz), shown red
function YardEdit:settle(id: string, tx: number, tz: number): boolean
	local G = Game.Yard.Grid
	local F = self:floor()
	local s = self:spot(id)
	if not s then return false end
	-- its middle kept where its whole footprint stays on the floor (a big machine reaches the edge
	-- without going red), as it's turned now
	local lx0, lx1, lz0, lz1 = F.x0, F.x1, F.z0, F.z1
	do
		local minX, maxX, minZ, maxZ = 0, 0, 0, 0
		for _, b in ipairs(self:boxes(id)) do
			minX, maxX = math.min(minX, b[1] - s.x), math.max(maxX, b[3] - s.x)
			minZ, maxZ = math.min(minZ, b[2] - s.z), math.max(maxZ, b[4] - s.z)
		end
		if F.x0 - minX <= F.x1 - maxX then lx0, lx1 = math.ceil((F.x0 - minX) / G) * G, math.floor((F.x1 - maxX) / G) * G end
		if F.z0 - minZ <= F.z1 - maxZ then lz0, lz1 = math.ceil((F.z0 - minZ) / G) * G, math.floor((F.z1 - maxZ) / G) * G end
		if lx0 > lx1 then lx0, lx1 = F.x0, F.x1 end
		if lz0 > lz1 then lz0, lz1 = F.z0, F.z1 end
	end
	local bx = math.clamp(math.floor(tx / G + 0.5) * G, lx0, lx1)
	local bz = math.clamp(math.floor(tz / G + 0.5) * G, lz0, lz1)
	-- (the same target as last time: already settled)
	local key = bx .. "," .. bz
	if self.settledFor == id and self.settledAt == key then return true end
	self.settledFor, self.settledAt = id, key
	local tier = self:tier()
	for _, o in ipairs(NEAR) do
		s.x = math.clamp(bx + o[1] * G, lx0, lx1)
		s.z = math.clamp(bz + o[2] * G, lz0, lz1)
		local _, bad = Game.yardCheck(self.layout, tier)
		if not bad[id] then return true end
	end
	s.x, s.z = bx, bz
	return false
end

function YardEdit:release()
	local id = self.held
	-- (a fresh piece on the pointer isn't let go of: a click sets it down)
	if not id or self.carrying then return end
	self.held = nil
	local ok, bad = Game.yardCheck(self.layout, self:tier())
	local from = self.pickedFrom
	if not ok and bad[id] and from then
		-- it can't stand there: it slides back to where it came from (turning back the short way)
		local s = self:spot(id)
		s.x, s.z, s.r = from.x, from.z, from.r
		if decorIndex(id) then (s :: any).a = from.a end
		self:shortWay(id)
		self:dropSnapshot()
		Sound.play("gateWhoosh", { volume = 0.3, pitch = 0.8 })
	elseif from then
		local s = self:spot(id)
		if s and (s.x ~= from.x or s.z ~= from.z) then
			self.stats.moved += 1
		elseif s and s.r == from.r and (s :: any).a == from.a then
			self:dropSnapshot()   -- (picked up and put down where it was: nothing to undo)
		end
	end
	self.landing = id
	self:refreshPlates()
end

-- decor: an angle step (15 degrees) one way or the other
function YardEdit:angle(dir: number)
	local id = self.held or self.selected
	if not decorIndex(id) or self.closing then return end
	local s = self:spot(id :: string)
	local before = Game.decorAngle(s)
	if not self.held then self:snapshot() end
	self.settledFor = nil
	s.a = (before + dir) % 24
	s.r = s.a // 6
	local sh = self.shown[id :: string]
	local shBefore = sh.a
	-- shown turns the short way round
	while (sh.a or before) - s.a > 12 do sh.a = (sh.a or before) - 24 end
	while s.a - (sh.a or before) > 12 do sh.a = (sh.a or before) + 24 end
	if not self.held then
		local ok, bad = Game.yardCheck(self.layout, self:tier())
		if not ok and bad[id :: string] then
			s.a = before
			s.r = before // 6
			sh.a = shBefore
			self:dropSnapshot()
			Kit.callout(self.gui, "No room to turn", C.red, UDim2.fromScale(0.5, 0.2), 30)
		end
	end
	Sound.play("gateWhoosh", { volume = 0.15, pitch = 2 })
	self:refreshPlates()
end

function YardEdit:turn()
	local id = self.held or self.selected
	if not id or self.closing then return end
	-- decor turns 45 degrees at a time
	if decorIndex(id) then
		self:angle(3)
		return
	end
	local s = self:spot(id)
	if not s then return end
	if not self.held then self:snapshot() end
	self.settledFor = nil
	s.r = (s.r + 1) % 4
	-- shown turns the short way round, never spinning back through three quarters
	local sh = self.shown[id]
	local shBefore = sh.r
	while sh.r - s.r > 2 do sh.r -= 4 end
	while s.r - sh.r > 2 do sh.r += 4 end
	if not self.held then
		local ok, bad = Game.yardCheck(self.layout, self:tier())
		if not ok and bad[id] then
			s.r = (s.r + 3) % 4
			sh.r = shBefore
			self:dropSnapshot()
			Kit.callout(self.gui, "No room to turn", C.red, UDim2.fromScale(0.5, 0.2), 30)
		end
	end
	Sound.play("gateWhoosh", { volume = 0.25, pitch = 1.8 })
	self:refreshPlates()
end

--==============================================================
-- drawing
--==============================================================
function YardEdit:refreshPlates()
	local _, bad = Game.yardCheck(self.layout, self:tier())
	for id, list in pairs(self.plates) do
		local boxes = self:boxes(id)
		local col, tr = PLATE_IDLE, 0.72
		if id == self.held then
			col, tr = bad[id] and PLATE_BAD or PLATE_GOOD, 0.35
		elseif bad[id] then
			col, tr = PLATE_BAD, 0.45
		elseif id == self.selected then
			col, tr = PLATE_SEL, 0.3
		elseif id == self.hover then
			tr = 0.45
		end
		for i, plate in ipairs(list) do
			local b = boxes[i]
			if b then
				plate.Size = Vector3.new(b[3] - b[1], 0.12, b[4] - b[2])
				plate.CFrame = self.base * CFrame.new((b[1] + b[3]) / 2, FLOOR_Y + 0.07, (b[2] + b[4]) / 2)
				plate.Color = col
				plate.Transparency = tr
			end
		end
	end
	local ok = Game.yardCheck(self.layout, self:tier())
	self.doneBtn.setEnabled(ok)
end

function YardEdit:step(dt: number)
	local cam = workspace.CurrentCamera
	if not self.closing then
		local v, sv = self.view, self.shownView
		-- pan with the keys, along the ground relative to where the camera faces
		local fwd = Vector3.new(-math.cos(v.yaw), 0, -math.sin(v.yaw))
		local right = Vector3.new(-fwd.Z, 0, fwd.X)
		local P = self.pan or {}
		local K = Enum.KeyCode
		local mv = Vector3.zero
		if P[K.W] or P[K.Up] then mv += fwd end
		if P[K.S] or P[K.Down] then mv -= fwd end
		if P[K.D] or P[K.Right] then mv += right end
		if P[K.A] or P[K.Left] then mv -= right end
		if mv.Magnitude > 0 then v.target += mv.Unit * dt * (30 + v.dist * 0.4) end
		-- carrying something draws the view a little toward it, and the piece stays under the pointer
		-- while the view moves (not only when the mouse does)
		if self.held then
			local s = self:spot(self.held)
			v.target = v.target:Lerp(Vector3.new(s.x, 0, s.z), math.min(1, dt * 0.8))
			if self.lastPointer then self:drag(self.lastPointer) end
		end
		local F = self:floor()
		v.target = Vector3.new(math.clamp(v.target.X, F.x0 - 10, F.x1 + 10), 0, math.clamp(v.target.Z, F.z0 - 10, F.z1 + 10))
		-- the shown view follows on springs: no cuts, no whips
		local k = 1 - math.exp(-dt * 9)
		sv.target = sv.target:Lerp(v.target, k)
		sv.yaw += (v.yaw - sv.yaw) * k
		sv.pitch += (v.pitch - sv.pitch) * k
		sv.dist += (v.dist - sv.dist) * k
		local to = self:viewCFrame(sv)
		-- the rise into it from wherever the camera was
		self.camT = math.min(1, self.camT + dt / 0.7)
		cam.CFrame = if self.camT < 1 then (self.camFrom :: CFrame):Lerp(to, smooth(self.camT)) else to
		cam.FieldOfView = self.savedFov + (tuned("YardFov", CAM_FOV) - self.savedFov) * smooth(self.camT)
	end
	local plot = self.plotModel
	local decorMoved = false
	for id, sh in pairs(self.shown) do
		local s = self:spot(id)
		if s then
			local k = math.min(1, dt * 16)
			local px, pz = sh.x, sh.z
			sh.x += (s.x - sh.x) * k
			sh.z += (s.z - sh.z) * k
			sh.r += (s.r - sh.r) * math.min(1, dt * 12)
			local wantA = if decorIndex(id) then Game.decorAngle(s) else nil
			if wantA and sh.a then sh.a += (wantA - sh.a) * math.min(1, dt * 12) end
			-- lift on a spring: up while held, down with a bounce when let go
			local target = (id == self.held) and LIFT or 0
			sh.vh += ((target - sh.h) * 160 - sh.vh * 14) * dt
			sh.h += sh.vh * dt
			if target == 0 and sh.h < 0 then
				if sh.vh < -6 and self.landing == id then
					self.landing = nil
					self:landed(id)
				end
				sh.h = 0
				sh.vh = -sh.vh * 0.3
			end
			-- lean into the way it's moving
			local vel = Vector2.new(sh.x - px, sh.z - pz) / math.max(dt, 1e-3)
			local want = Vector2.new(math.clamp(vel.X * 0.004, -0.12, 0.12), math.clamp(vel.Y * 0.004, -0.12, 0.12))
			sh.lean = sh.lean:Lerp(want, math.min(1, dt * 10))
			local moving = sh.h > 0.01 or math.abs(sh.x - s.x) > 0.01 or math.abs(sh.z - s.z) > 0.01 or math.abs(sh.r - s.r) > 0.001
				or (wantA ~= nil and sh.a ~= nil and math.abs(sh.a - wantA) > 0.001)
			if decorIndex(id) then
				if moving then decorMoved = true end
			elseif moving or not sh.placed then
				sh.placed = true
				local lift = CFrame.new(0, sh.h, 0) * CFrame.Angles(-sh.lean.Y, 0, sh.lean.X)
				self.plot2:placeUnit(plot, { [id] = { x = sh.x, z = sh.z, r = sh.r } }, id, lift)
			end
		end
	end
	if decorMoved then self:drawDecor() end
end

-- set down: a thump and a ring of dust round its feet
function YardEdit:landed(id: string)
	for _, b in ipairs(self:boxes(id)) do
		local c = self.base * CFrame.new((b[1] + b[3]) / 2, FLOOR_Y + 0.4, (b[2] + b[4]) / 2)
		PackFX.burst("dustRing", c, 10, nil, 0.8 + math.max(b[3] - b[1], b[4] - b[2]) * 0.02)
	end
	Sound.play("land", { volume = 0.45, pitch = 1.1 })
end

return YardEdit
