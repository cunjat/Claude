--!strict
-- TYRE CANNON :: YardEdit
-- Making your yard yours. The camera rises over the yard; press on a machine or a piece of decor to
-- pick it up (it lifts and leans as you drag), drag it across the floor on the grid, R or TURN turns
-- it a quarter, let go to set it down with a bounce and a puff of dust. The footprint under each
-- thing is green where it can stand and red where it can't; let go somewhere it can't stand and it
-- slides back to where it was picked up. The drawer of decor along the bottom adds a piece (the
-- game's own props, more unlocking with each yard stage, as many as the stage allows); REMOVE or
-- Delete takes the selected piece away. DONE saves (the server checks the same rules,
-- Game.yardCheck), RESET puts the machines back where they started, Q or the X leaves unsaved.
-- The cannon and its ramp move together as the launcher: the shot has to go out over the ramp.
-- The camera orbits the yard on springs: right-drag (two fingers on a phone) looks round, the wheel
-- (a pinch) zooms, WASD or the arrows pan, F puts it back; carrying something draws it gently over.
-- Its pitch stays high enough that nothing in the yard can come between it and the floor.
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
local CARD_W, CARD_H = 104, 126

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
	for _, d in ipairs(layout.decor or {}) do table.insert(out.decor, { k = d.k, x = d.x, z = d.z, r = d.r }) end
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

	-- the title and a line of help along the top
	local root = UI.mk("Frame", { Name = "YardEdit", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 40, Parent = gui })
	self.root = root
	local top = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(760, 64), BackgroundTransparency = 1, Parent = root })
	UI.autoScale(top, 1280, 760)
	local title = Kit.text("Edit Yard", 34, C.white, 2.5)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0)
	title.Size = UDim2.fromOffset(640, 38)
	title.Parent = top
	local how = UserInputService.TouchEnabled and "Drag to move.   Two fingers look round."
		or "Drag to move.   R turns.   Right-drag looks round.   Scroll zooms.   WASD pans.   F resets."
	self.hint = Kit.text(how, 17, C.white, 2, Kit.Body)
	self.hint.AnchorPoint = Vector2.new(0.5, 0)
	self.hint.Position = UDim2.new(0.5, 0, 0, 40)
	self.hint.Size = UDim2.fromOffset(760, 22)
	Kit.fit(self.hint, 17)
	self.hint.Parent = top

	-- along the bottom: the decor drawer, then the buttons
	local dock = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(760, 244), BackgroundTransparency = 1, Parent = root })
	UI.autoScale(dock, 1280, 760)
	local drawer = UI.mk("Frame", { Size = UDim2.fromOffset(760, 162), BackgroundTransparency = 1, Parent = dock })
	Kit.slice("panel_body", nil, drawer, 1, 0.45)
	Kit.slice("panel_ring", C.teal, drawer, 2, 0.45)
	local dt = Kit.text("DECOR", 16, C.white, 2)
	dt.Position = UDim2.fromOffset(16, 8)
	dt.Size = UDim2.fromOffset(120, 20)
	dt.TextXAlignment = Enum.TextXAlignment.Left
	dt.ZIndex = 4
	dt.Parent = drawer
	self.decorCount = Kit.text("", 15, C.gold, 2, Kit.Body)
	self.decorCount.AnchorPoint = Vector2.new(1, 0)
	self.decorCount.Position = UDim2.new(1, -16, 0, 9)
	self.decorCount.Size = UDim2.fromOffset(300, 20)
	self.decorCount.TextXAlignment = Enum.TextXAlignment.Right
	self.decorCount.ZIndex = 4
	self.decorCount.Parent = drawer
	self.shelf = UI.mk("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 32), Size = UDim2.new(1, -20, 0, CARD_H + 2), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 5, ScrollBarImageColor3 = C.line,
		AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ZIndex = 3, Parent = drawer,
	})
	UI.mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.shelf })
	UI.mk("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 2), Parent = self.shelf })
	self.cards = {}

	local bar = UI.mk("Frame", { Position = UDim2.fromOffset(0, 176), Size = UDim2.fromOffset(760, 64), BackgroundTransparency = 1, Parent = dock })
	local function button(text: string, color: Color3, x: number, w: number, fn: () -> ())
		local b = Kit.button(text, color, UDim2.fromOffset(w, 60), 24)
		b.root.Position = UDim2.fromOffset(x, 0)
		b.root.Parent = bar
		b.onClick = fn
		return b
	end
	button("Turn", C.blue, 0, 150, function() self:turn() end)
	self.removeBtn = button("Remove", C.red, 162, 150, function() self:remove() end)
	button("Reset", C.grey, 324, 150, function() self:reset() end)
	self.doneBtn = button("Done", C.green, 486, 274, function() self:done() end)
	local close = Kit.close(52)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, -24, 0, 24)
	close.root.Parent = root
	close.onClick = function() self:close(false) end
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
		self.shown[id] = { x = d.x, z = d.z, r = d.r, h = 0, vh = 0, lean = Vector2.zero, placed = true }
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
			list[i] = { k = d.k, x = sh.x, z = sh.z, r = sh.r }
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
		local tpl = Models.get(kind.path)
		if tpl then
			local m = Models.place(tpl, vp, CFrame.new(), 1)
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
		local lockLabel = Kit.text("Stage " .. kind.tier, 11, C.gold, 1.5, Kit.Body)
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
		b.Activated:Connect(function() self:addDecor(kind.id, b) end)
		self.cards[kind.id] = { button = b, veil = veil, lockLabel = lockLabel }
	end
end

function YardEdit:refreshDrawer()
	local tier = self:tier()
	local count, max = #(self.layout.decor or {}), Game.yardDecorMax(tier)
	self.decorCount.Text = ("%d / %d placed"):format(count, max)
	for _, kind in ipairs(Game.YardDecor) do
		local c = self.cards[kind.id]
		if c then
			local open = kind.tier <= tier
			c.veil.Visible = not open
			c.lockLabel.Visible = not open
		end
	end
	self.removeBtn.setEnabled(decorIndex(self.selected) ~= nil)
end

-- add a piece near the middle of the view, on the first free spot spiralling out from it
function YardEdit:addDecor(kindId: string, card: GuiObject?)
	if self.closing then return end
	local kind = Game.YardDecorById[kindId]
	local tier = self:tier()
	if not kind or kind.tier > tier then
		if card then Kit.shake(card, 5, 0.2) end
		Kit.callout(self.gui, ("Unlocks at stage %d"):format(kind and kind.tier or 0), C.red, UDim2.fromScale(0.5, 0.2), 30)
		return
	end
	local decor = self.layout.decor
	if #decor >= Game.yardDecorMax(tier) then
		if card then Kit.shake(card, 5, 0.2) end
		Kit.callout(self.gui, "No more room for decor at this stage", C.red, UDim2.fromScale(0.5, 0.2), 28)
		return
	end
	local G = Game.Yard.Grid
	local F = Game.Yard.Floor
	local cx = math.floor(self.view.target.X / G + 0.5) * G
	local cz = math.floor(self.view.target.Z / G + 0.5) * G
	local entry = { k = kindId, x = cx, z = cz, r = 0 }
	table.insert(decor, entry)
	local n = #decor
	local found = false
	for ring = 0, 30 do
		for dx = -ring, ring do
			for dz = -ring, ring do
				if math.max(math.abs(dx), math.abs(dz)) == ring and not found then
					entry.x = math.clamp(cx + dx * G * 2, F.x0, F.x1)
					entry.z = math.clamp(cz + dz * G * 2, F.z0, F.z1)
					local _, bad = Game.yardCheck(self.layout)
					if not bad["d" .. n] then found = true end
				end
			end
		end
		if found then break end
	end
	if not found then
		table.remove(decor, n)
		Kit.callout(self.gui, "No free floor for that", C.red, UDim2.fromScale(0.5, 0.2), 30)
		return
	end
	self:syncDecor()
	-- it drops in from above with a bounce, and it's the selected piece
	local id = "d" .. n
	local sh = self.shown[id]
	sh.h, sh.vh = LIFT * 2.5, 0
	self.landing = id
	self.selected = id
	if card then Kit.pop(card, 0.9, 0.2) end
	Sound.play("gateWhoosh", { volume = 0.3, pitch = 1.5 })
	self:refreshPlates()
	self:refreshDrawer()
end

function YardEdit:remove()
	local i = decorIndex(self.selected)
	if not i or self.closing then return end
	table.remove(self.layout.decor, i)
	self.selected = nil
	self.held = nil
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
	if not (base and y) then return end
	self.open_ = true
	self.plotModel = plot
	self.base = base
	self.onClose = onClose
	self.saved = self.plot2:layoutOf(plot)
	self.layout = copy(self.saved)
	-- what's drawn: each thing eases toward its spot on the grid, lifts while held, leans as it moves
	self.shown = {}
	for _, u in ipairs(Game.Yard.Units) do
		local s = self.layout[u.id]
		self.shown[u.id] = { x = s.x, z = s.z, r = s.r, h = 0, vh = 0, lean = Vector2.zero }
	end
	y.editing = true
	self.held = nil
	self.hover = nil
	self.selected = nil

	-- the floor's grid and a footprint plate under everything
	local folder = Instance.new("Folder")
	folder.Name = "YardEditor"
	folder.Parent = workspace
	self.folder = folder
	local F = Game.Yard.Floor
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
	self.pan = {}
	ContextActionService:BindActionAtPriority("TC_YardPan", function(_, st, io)
		self.pan[io.KeyCode] = st == Enum.UserInputState.Begin or st == Enum.UserInputState.Change
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right)
	ContextActionService:BindActionAtPriority("TC_YardLeave", function(_, st)
		if st == Enum.UserInputState.Begin then self:close(false) end
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)
	self.conns = {
		UserInputService.InputBegan:Connect(function(io, processed)
			if processed then return end
			if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
				self:press(Vector2.new(io.Position.X, io.Position.Y))
			elseif io.UserInputType == Enum.UserInputType.MouseButton2 then
				self.orbiting = true
			elseif io.KeyCode == Enum.KeyCode.F then
				self:resetView(false)
			end
		end),
		UserInputService.InputChanged:Connect(function(io, processed)
			if io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch then
				if self.orbiting and io.UserInputType == Enum.UserInputType.MouseMovement then
					self.view.yaw -= io.Delta.X * 0.006
					self.view.pitch = math.clamp(self.view.pitch + io.Delta.Y * 0.004, PITCH_MIN, PITCH_MAX)
				else
					self:drag(Vector2.new(io.Position.X, io.Position.Y))
				end
			elseif io.UserInputType == Enum.UserInputType.MouseWheel and not processed then
				self.view.dist = math.clamp(self.view.dist * (1 - io.Position.Z * 0.12), DIST_MIN, DIST_MAX)
			end
		end),
		UserInputService.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
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

function YardEdit:close(save: boolean)
	if not self.open_ or self.closing then return end
	if save then
		local ok, res = pcall(function() return (self.R :: any).Layout:InvokeServer(self.layout) end)
		if not (ok and type(res) == "table" and res.ok) then
			Kit.callout(self.gui, "Something's in the way", C.red, UDim2.fromScale(0.5, 0.2), 34)
			Kit.shake(self.doneBtn.root, 6, 0.25)
			return
		end
		Sound.play("land", { volume = 0.4, pitch = 1.4 })
	else
		-- unsaved: everything goes back where it was
		self.layout = copy(self.saved)
	end
	self.closing = true
	self.held = nil
	ContextActionService:UnbindAction("TC_YardTurn")
	ContextActionService:UnbindAction("TC_YardRemove")
	ContextActionService:UnbindAction("TC_YardLeave")
	ContextActionService:UnbindAction("TC_YardPan")
	self.orbiting = false
	for _, c in ipairs(self.conns or {}) do c:Disconnect() end
	self.conns = nil
	local plot = self.plotModel
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
	return self.base * CFrame.lookAt(v.target + dir * v.dist, v.target)
end

--==============================================================
-- picking up, dragging, setting down
--==============================================================
-- where a screen point lands on the yard's floor, in plot space
function YardEdit:floorAt(screen: Vector2): Vector3?
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(screen.X, screen.Y)
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
	local near, nearD = nil, 7
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

function YardEdit:press(screen: Vector2)
	if self.closing then return end
	local p = self:floorAt(screen)
	if not p then return end
	local id = self:unitAt(p)
	if not id then
		self.selected = nil
		self:refreshPlates()
		self:refreshDrawer()
		return
	end
	local s = self:spot(id)
	self.held = id
	self.selected = id
	self.grab = Vector3.new(s.x - p.X, 0, s.z - p.Z)
	self.pickedFrom = { x = s.x, z = s.z, r = s.r }
	self.shown[id].vh = 14
	Sound.play("gateWhoosh", { volume = 0.3, pitch = 1.6 })
	self:refreshPlates()
	self:refreshDrawer()
end

function YardEdit:drag(screen: Vector2)
	local p = self:floorAt(screen)
	if not p then return end
	if not self.held then
		self.hover = self:unitAt(p)
		self:refreshPlates()
		return
	end
	local G = Game.Yard.Grid
	local s = self:spot(self.held)
	local tx, tz = p.X + self.grab.X, p.Z + self.grab.Z
	local F = Game.Yard.Floor
	s.x = math.clamp(math.floor(tx / G + 0.5) * G, F.x0, F.x1)
	s.z = math.clamp(math.floor(tz / G + 0.5) * G, F.z0, F.z1)
	self:refreshPlates()
end

function YardEdit:release()
	local id = self.held
	if not id then return end
	self.held = nil
	local ok, bad = Game.yardCheck(self.layout)
	if not ok and bad[id] then
		-- it can't stand there: it slides back to where it came from
		local from = self.pickedFrom
		local s = self:spot(id)
		s.x, s.z, s.r = from.x, from.z, from.r
		Sound.play("gateWhoosh", { volume = 0.3, pitch = 0.8 })
	end
	self.landing = id
	self:refreshPlates()
end

function YardEdit:turn()
	local id = self.held or self.selected
	if not id or self.closing then return end
	local s = self:spot(id)
	if not s then return end
	s.r = (s.r + 1) % 4
	-- shown turns the short way round, never spinning back through three quarters
	local sh = self.shown[id]
	while sh.r - s.r > 2 do sh.r -= 4 end
	while s.r - sh.r > 2 do sh.r += 4 end
	if not self.held then
		local ok, bad = Game.yardCheck(self.layout)
		if not ok and bad[id] then
			s.r = (s.r + 3) % 4
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
	local _, bad = Game.yardCheck(self.layout)
	for id, list in pairs(self.plates) do
		local boxes = self:boxes(id)
		local col, tr = PLATE_IDLE, 0.72
		if id == self.held then
			col, tr = bad[id] and PLATE_BAD or PLATE_GOOD, 0.35
		elseif bad[id] then
			col, tr = PLATE_BAD, 0.45
		elseif id == self.selected or id == self.hover then
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
	local ok = Game.yardCheck(self.layout)
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
		-- carrying something draws the view a little toward it
		if self.held then
			local s = self:spot(self.held)
			v.target = v.target:Lerp(Vector3.new(s.x, 0, s.z), math.min(1, dt * 0.8))
		end
		local F = Game.Yard.Floor
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
