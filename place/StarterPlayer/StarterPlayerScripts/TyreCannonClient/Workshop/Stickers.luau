--!strict
-- TYRE CANNON :: Workshop / Stickers
-- Stickers wrapped onto the rubber. Each one is a small mesh WheelAssembly
-- bends over the tread and down the sidewall, so a sticker on the shoulder
-- curves with it.
--   pick a sticker on the sheet, then click the rubber to stick it on
--   click a sticker on the tyre to select it, drag to slide it around
--   Q / E rotate, scroll or - / = resize, X or Delete peels it off
--   drag anywhere off the tyre to turn the wheel
-- Needs EditableMesh allowed in Game Settings > Security.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Config = require(Modules.Config)
local WheelAssembly = require(Modules.WheelAssembly)
local UI = require(script.Parent.Parent.UI)
local VFX = require(script.Parent.Parent.VFX)
local T = UI.Theme

local Stickers = {}
Stickers.__index = Stickers

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function copyList(list)
	local out = {}
	for _, s in ipairs(list or {}) do
		table.insert(out, { id = s.id, u = s.u or 0, v = s.v or 0, rot = s.rot or 0, scale = s.scale or 1, side = s.side or 1 })
	end
	return out
end

local function centred(parent: Instance, text: string, size: number, role: string, color: Color3, y: number, h: number): TextLabel
	local l = UI.text(text, size, role, color)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.Size = UDim2.new(1, 0, 0, h)
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.ZIndex = 24
	l.Parent = parent
	return l
end

--==============================================================
function Stickers.new(ws)
	local self = setmetatable({}, Stickers)
	self.ws = ws
	self.list = {}
	self.state = {}
	self.gen = 0
	self.selected = nil
	self.placing = nil
	self.active = false
	self.dirty = false
	self.saving = false
	self.saveAt = 0
	self.changeId = 0
	self.pressing = nil
	self.previewPart = nil
	self.previewBusy = false
	self.previewAt = 0
	self.lastRot = 0
	self.noMesh = false
	self.peelArmed = 0
	self.conns = {}
	self.sheetCards = {}

	local frame = UI.mk("Frame", {
		Name = "Stickers", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(1140, 200), BackgroundTransparency = 1, Visible = false, ZIndex = 22, Parent = ws.root,
	})
	UI.autoScale(frame, 1240, 780)
	self.frame = frame
	-- one tab per sheet, with the count on the tyre at the end of the row
	local tabs = UI.mk("Frame", {
		Name = "Sheets", Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, ZIndex = 22, Parent = frame,
	}, { UI.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	self.sheetTabs = {}
	for i, sh in ipairs(Config.StickerSheets) do
		local b = UI.button(string.upper(sh.name), "ghost", 104, 28)
		b.Name = "Sheet_" .. sh.id
		b.TextSize = 13
		b.LayoutOrder = i
		b.ZIndex = 23
		b.Parent = tabs
		b.Activated:Connect(function() self:showSheet(sh.id) end)
		self.sheetTabs[sh.id] = b
	end
	self.header = UI.text("", 13, "monoBold", T.dim)
	self.header.Name = "Count"
	self.header.AutomaticSize = Enum.AutomaticSize.X
	self.header.Size = UDim2.fromOffset(0, 28)
	self.header.LayoutOrder = 99
	self.header.ZIndex = 23
	self.header.Parent = tabs
	UI.pad(0, 14, 0, 0, 0).Parent = self.header
	self.sheetId = Config.StickerSheets[1] and Config.StickerSheets[1].id or ""
	self.hint = centred(frame, "", 14, "body", T.dim, 31, 18)

	local sheet = UI.mk("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 96), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = T.lineHi, ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ElasticBehavior = Enum.ElasticBehavior.Never,
		ZIndex = 22, Parent = frame,
	})
	local sheetLayout = UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	sheetLayout.Parent = sheet
	UI.centreScroll(sheet, sheetLayout)
	self.sheet = sheet

	local controls = UI.mk("Frame", {
		Position = UDim2.fromOffset(0, 156), Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, ZIndex = 22, Parent = frame,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	local function control(label: string, w: number, order: number, fn: () -> ()): TextButton
		local b = UI.button(label, "ghost", w, 36)
		b.TextSize = 14
		b.LayoutOrder = order
		b.ZIndex = 23
		b.Parent = controls
		b.Activated:Connect(fn)
		return b
	end
	self.controls = {
		control("ROTATE  Q", 108, 1, function() self:rotate(-15) end),
		control("ROTATE  E", 108, 2, function() self:rotate(15) end),
		control("SMALLER  -", 108, 3, function() self:resize(-0.1) end),
		control("BIGGER  =", 108, 4, function() self:resize(0.1) end),
		control("PEEL OFF  X", 116, 5, function() self:remove() end),
	}
	self.peelAll = control("PEEL ALL", 104, 6, function() self:peelAllPressed() end)
	self.turnButtons = {
		control("< TURN  A", 104, 7, function() self:turnBy(-math.pi / 4) end),
		control("TURN >  D", 104, 8, function() self:turnBy(math.pi / 4) end),
		control("FLIP", 76, 9, function() self:turnBy(math.pi) end),
	}

	local ghost = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(64, 64), BackgroundTransparency = 1,
		ImageTransparency = 0.2, ScaleType = Enum.ScaleType.Fit, Visible = false, ZIndex = 300, Parent = ws.root,
	})
	self.ghost = ghost
	return self
end

--==============================================================
-- meshes on the bench wheel
--==============================================================
function Stickers:folder(wheel: Model): Folder
	local f = wheel:FindFirstChild("Stickers")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Stickers"
		f.Parent = wheel
	end
	return f :: Folder
end

function Stickers:meshMissing()
	if self.noMesh then return end
	self.noMesh = true
	self.ws:toast("Stickers can't render: allow EditableMesh in Game Settings > Security.", T.bad)
	self:updateUI()
end

function Stickers:buildOne(i: number)
	local s = self.list[i]
	local wheel = self.ws.wheel
	if not s or not wheel then return end
	local st = self.state[i]
	if not st then
		st = {}
		self.state[i] = st
	end
	if st.mesh and st.mesh.Parent and WheelAssembly.updateSticker(wheel, st.mesh, s) then
		if self.selected == i then self:paintSelection() end
		return
	end
	if st.building then return end
	st.building = true
	local gen = self.gen
	task.spawn(function()
		local mp = WheelAssembly.buildSticker(wheel, s)
		st.building = false
		local idx = table.find(self.state, st)
		if gen ~= self.gen or not idx or not (wheel.Parent and self.ws.wheel == wheel) then
			if mp then mp:Destroy() end
			return
		end
		if not mp then
			self:meshMissing()
			return
		end
		if st.mesh then st.mesh:Destroy() end
		st.mesh = mp
		mp.Parent = self:folder(wheel)
		-- catch up with anything changed while it was being built
		local latest = self.list[idx]
		if latest then WheelAssembly.updateSticker(wheel, mp, latest) end
		if self.selected == idx then self:paintSelection() end
	end)
end

function Stickers:rebuildAll()
	self.gen += 1
	for _, st in pairs(self.state) do
		if st.mesh then st.mesh:Destroy() end
	end
	self.state = {}
	self:clearPreview()
	local wheel = self.ws.wheel
	if not wheel then return end
	local old = wheel:FindFirstChild("Stickers")
	if old then old:Destroy() end
	wheel:SetAttribute("StickerToken", "workshop" .. self.gen)
	for i = 1, #self.list do self:buildOne(i) end
	self:paintSelection()
end

-- called whenever the bench wheel is rebuilt
function Stickers:dress(force: boolean?)
	if not self.dirty and not self.saving then
		local fresh = copyList(self.ws.profile and self.ws.profile.stickers)
		if not force then
			local okA, a = pcall(function() return HttpService:JSONEncode(fresh) end)
			local okB, b = pcall(function() return HttpService:JSONEncode(self.list) end)
			local built = true
			for i = 1, #fresh do
				local st = self.state[i]
				if not (st and st.mesh and st.mesh.Parent) then built = false end
			end
			if okA and okB and a == b and built then
				self.selected = nil
				self:paintSelection()
				return
			end
		end
		self.list = fresh
	end
	self.selected = nil
	self:rebuildAll()
end

function Stickers:clearPreview(destroy: boolean?)
	self.previewFor = nil
	self.previewSpec = nil
	local pv = self.previewPart
	if pv then
		if destroy or not pv.Parent then
			pv:Destroy()
			self.previewPart = nil
		else
			pv.Transparency = 1
		end
	end
end

function Stickers:showPreview(hit)
	local wheel = self.ws.wheel
	local id = self.placing
	if not wheel or not id then return end
	local spec = { id = id, u = hit.u, v = hit.v, rot = self:uprightAt(hit), scale = 1 }
	self:fit(spec)
	self.previewSpec = spec
	local pv = self.previewPart
	if pv and pv.Parent and WheelAssembly.updateSticker(wheel, pv, spec) then
		pv.Transparency = 0.3
		return
	end
	if self.previewBusy then return end
	self.previewBusy = true
	local gen = self.gen
	task.spawn(function()
		local mp = WheelAssembly.buildSticker(wheel, spec)
		self.previewBusy = false
		if not mp then
			self:meshMissing()
			return
		end
		if gen ~= self.gen or not self.active or self.ws.wheel ~= wheel then
			mp:Destroy()
			return
		end
		if self.previewPart then self.previewPart:Destroy() end
		mp.Name = "StickerPreview"
		mp.Parent = self:folder(wheel)
		self.previewPart = mp
		local latest = self.previewSpec
		if latest then WheelAssembly.updateSticker(wheel, mp, latest) end
		mp.Transparency = (self.placing and latest) and 0.3 or 1
	end)
end

function Stickers:paintSelection()
	if self.highlight then self.highlight.Enabled = false end
	local wheel = self.ws.wheel
	local i = self.selected
	local s = i and self.list[i]
	local fr = self.framePart
	if not (s and wheel) then
		if fr then fr.Transparency = 1 end
		return
	end
	if fr and fr.Parent and WheelAssembly.updateStickerFrame(wheel, fr, s) then
		fr.Transparency = 0
		return
	end
	if self.frameBusy then return end
	self.frameBusy = true
	local gen = self.gen
	task.spawn(function()
		local mp = WheelAssembly.buildStickerFrame(wheel)
		self.frameBusy = false
		if not mp then return end
		if gen ~= self.gen or self.ws.wheel ~= wheel then
			mp:Destroy()
			return
		end
		if self.framePart then self.framePart:Destroy() end
		mp.Color = T.accent
		mp.Parent = self:folder(wheel)
		self.framePart = mp
		local cur = self.selected and self.list[self.selected]
		if cur and WheelAssembly.updateStickerFrame(wheel, mp, cur) then
			mp.Transparency = 0
		else
			mp.Transparency = 1
		end
	end)
end

--==============================================================
-- editing
--==============================================================
function Stickers:touch()
	self.dirty = true
	self.changeId += 1
	self.saveAt = os.clock() + 1.2
	self:updateUI()
end

function Stickers:save()
	self.saving = true
	local id = self.changeId
	local payload = copyList(self.list)
	task.spawn(function()
		local res = self.ws:call("SetStickers", payload)
		self.saving = false
		if res and res.ok then
			if self.changeId == id then
				self.dirty = false
			elseif not self.active then
				self:save()
			end
		else
			self.saveAt = os.clock() + 2
		end
	end)
end

function Stickers:setPlacing(id: string?)
	self.placing = id
	local e = id and WheelAssembly.stickers().byId[id]
	self.ghost.Image = e and e.texture or ""
	self.ghost.Visible = id ~= nil
	self:showZone(id ~= nil)
	UI.setCursor(id and "place" or nil)
	if not id then self:clearPreview() end
	if id then self:select(nil) end
	self:updateUI()
end

-- the rubber lights up while you're holding a sticker: that's where it can go
function Stickers:showZone(on: boolean)
	local z = self.zone
	if not z then
		z = Instance.new("Highlight")
		z.Name = "StickerZone"
		z.FillColor = T.accent
		z.FillTransparency = 0.82
		z.OutlineColor = T.accent
		z.OutlineTransparency = 0.35
		z.DepthMode = Enum.HighlightDepthMode.Occluded
		self.zone = z
	end
	local wheel = self.ws.wheel
	local carcass = wheel and wheel:FindFirstChild("Carcass")
	if on and carcass and self.ws.room then
		z.Adornee = carcass
		z.Parent = self.ws.room.folder
		z.Enabled = true
	else
		z.Enabled = false
	end
end

function Stickers:uprightAt(hit): number
	local wheel = self.ws.wheel
	if not wheel then return 0 end
	return math.floor(WheelAssembly.uprightRotation(wheel, hit.u, hit.v, workspace.CurrentCamera.CFrame.UpVector) + 0.5)
end

function Stickers:pick(hit): number?
	local wheel = self.ws.wheel
	if not wheel then return nil end
	local cat = WheelAssembly.stickers()
	local d = WheelAssembly.dims(wheel)
	local k = d.R / 3
	local span = d.W / 2 + (d.R - d.Ri)
	local best, bestD = nil, math.huge
	for i, s in ipairs(self.list) do
		local e = cat.byId[s.id]
		if e then
			local du = hit.u - s.u
			du -= 2 * math.floor((du + 1) / 2)
			local across = du * math.pi * d.R
			local along = (hit.v - s.v) * span
			local dist = math.sqrt(across * across + along * along)
			local reach = math.max(e.size.X, e.size.Y) * k * 0.75 * (s.scale or 1) * 0.6
			if dist < reach and dist < bestD then
				best, bestD = i, dist
			end
		end
	end
	return best
end

-- slides or shrinks a sticker so it stays on the rubber instead of folding over the lip
function Stickers:fit(s)
	local wheel = self.ws.wheel
	if wheel then WheelAssembly.fitSticker(wheel, s) end
end

function Stickers:place(id: string, hit)
	if #self.list >= Config.Stickers.MaxPerTyre then
		self.ws:toast(("A tyre takes %d stickers at most."):format(Config.Stickers.MaxPerTyre), T.bad)
		return
	end
	local spec = { id = id, u = hit.u, v = hit.v, rot = self:uprightAt(hit), scale = 1, side = hit.v < 0 and -1 or 1 }
	self:fit(spec)
	table.insert(self.list, spec)
	local i = #self.list
	local st = {}
	self.state[i] = st
	local wheel = self.ws.wheel
	local pv = self.previewPart
	if pv and pv.Parent and wheel and WheelAssembly.updateSticker(wheel, pv, spec) then
		pv.Name = "Sticker_" .. id
		pv.Transparency = 0.02
		st.mesh = pv
		self.previewPart = nil
	else
		self:clearPreview()
		self:buildOne(i)
	end
	self:setPlacing(nil)
	self:select(i)
	self:touch()
end

function Stickers:select(i: number?)
	self.selected = i
	self:paintSelection()
	self:updateUI()
end

function Stickers:rotate(deg: number)
	local i = self.selected
	local s = i and self.list[i]
	if not s then return end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then deg /= 3 end
	s.rot = ((s.rot or 0) + deg + 180) % 360 - 180
	self.lastRot = s.rot
	self:fit(s)
	self:buildOne(i :: number)
	self:touch()
end

function Stickers:resize(delta: number)
	local i = self.selected
	local s = i and self.list[i]
	if not s then return end
	local S = Config.Stickers
	s.scale = math.clamp(math.floor(((s.scale or 1) + delta) * 100 + 0.5) / 100, S.MinScale, S.MaxScale)
	self:fit(s)
	self:buildOne(i :: number)
	self:touch()
end

function Stickers:turnBy(delta: number)
	local ws = self.ws
	ws.yawGoal = (ws.yawGoal or ws.yaw) + delta
end

function Stickers:remove()
	local i = self.selected
	if not i or not self.list[i] then return end
	table.remove(self.list, i)
	local st = table.remove(self.state, i)
	if st and st.mesh then st.mesh:Destroy() end
	self.selected = nil
	self:paintSelection()
	self:touch()
end

function Stickers:peelAllPressed()
	if #self.list == 0 then return end
	if os.clock() > self.peelArmed then
		self.peelArmed = os.clock() + 3
		self:updateUI()
		return
	end
	self.peelArmed = 0
	self.list = {}
	self.selected = nil
	self:rebuildAll()
	self:touch()
end

--==============================================================
-- input
--==============================================================
function Stickers:bind()
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
	table.insert(self.conns, UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or not self.active or self.ws.busy then return end
		if UserInputService:GetFocusedTextBox() then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if self.placing then self:setPlacing(nil) end
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Q then
			self:rotate(-15)
			return
		elseif key == Enum.KeyCode.E then
			self:rotate(15)
			return
		elseif key == Enum.KeyCode.Minus or key == Enum.KeyCode.KeypadMinus then
			self:resize(-0.1)
			return
		elseif key == Enum.KeyCode.Equals or key == Enum.KeyCode.KeypadPlus then
			self:resize(0.1)
			return
		elseif key == Enum.KeyCode.X or key == Enum.KeyCode.Delete or key == Enum.KeyCode.Backspace then
			self:remove()
			return
		end
		if not isPress(input) then return end
		local mouse = UserInputService:GetMouseLocation()
		local hit = self.ws:hitWheel(mouse)
		if self.placing then
			if hit then self:place(self.placing, hit) end
			return
		end
		if hit then
			local idx = self:pick(hit)
			if idx then
				self:select(idx)
				self.pressing = { mode = "move", index = idx, start = mouse, moved = false }
				UI.setCursor("grabbing")
				return
			end
		end
		self.pressing = { mode = "turn", start = mouse, moved = false, empty = hit == nil }
		UI.setCursor("grabbing")
	end))
	table.insert(self.conns, UserInputService.InputChanged:Connect(function(input, gpe)
		if not self.active then return end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			if not gpe and self.selected then self:resize(input.Position.Z > 0 and 0.1 or -0.1) end
			return
		end
		if not isMove(input) then return end
		local pr = self.pressing
		if not pr then return end
		local mouse = UserInputService:GetMouseLocation()
		if (mouse - pr.start).Magnitude > 4 then pr.moved = true end
		if pr.mode == "turn" then
			self.ws.yawGoal = (self.ws.yawGoal or self.ws.yaw) + input.Delta.X * 0.012
			self.ws.roll -= input.Delta.Y * 0.012
		elseif pr.mode == "move" and pr.moved then
			local hit = self.ws:hitWheel(mouse)
			local s = self.list[pr.index]
			if hit and s then
				s.u, s.v = hit.u, hit.v
				s.side = hit.v < 0 and -1 or 1
				self:fit(s)
				self:buildOne(pr.index)
				self:touch()
			end
		end
	end))
	table.insert(self.conns, UserInputService.InputEnded:Connect(function(input)
		if not isPress(input) then return end
		local pr = self.pressing
		self.pressing = nil
		UI.setCursor(self.placing and "place" or nil)
		if pr and pr.mode == "turn" and not pr.moved and pr.empty then self:select(nil) end

	end))
end

--==============================================================
-- station lifecycle
--==============================================================
function Stickers:buildSheet()
	if self.sheetBuilt then return end
	self.sheetBuilt = true
	local cat = WheelAssembly.stickers()
	for i, e in ipairs(cat.list) do
		local b = UI.mk("TextButton", {
			Size = UDim2.fromOffset(88, 88), BackgroundTransparency = 1, BorderSizePixel = 0,
			AutoButtonColor = false, Text = "", LayoutOrder = i, ZIndex = 23, Parent = self.sheet,
		})
		UI.plate("slot", { Name = "Plate", Size = UDim2.fromScale(1, 1), ZIndex = 23, Parent = b })
		local edge = UI.plate("cardTrim", {
			Name = "Trim", Size = UDim2.fromScale(1, 1), ImageColor3 = T.line, ImageTransparency = 0.45, ZIndex = 26, Parent = b,
		})
		UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(72, 72),
			BackgroundTransparency = 1, Image = e.texture, ScaleType = Enum.ScaleType.Fit, ZIndex = 24, Parent = b,
		})
		b.MouseEnter:Connect(function() if self.placing ~= e.id then edge.ImageColor3 = T.lineHi end end)
		b.MouseLeave:Connect(function() if self.placing ~= e.id then edge.ImageColor3 = T.line end end)
		b.Activated:Connect(function()
			if self.placing == e.id then self:setPlacing(nil) else self:setPlacing(e.id) end
		end)
		self.sheetCards[e.id] = edge
		self.sheetButtons = self.sheetButtons or {}
		self.sheetButtons[e.id] = b
		if Config.FoilStickers[e.id] then
			-- foil ones catch the light on the sheet too
			local shine = UI.mk("UIGradient", {
				Rotation = 30,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(0.5, 0.35),
					NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = UI.mk("Frame", {
					Name = "Foil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 250, 235), BorderSizePixel = 0,
					BackgroundTransparency = 0.2, ZIndex = 25, Parent = b,
				}),
			})
			self.foilShines = self.foilShines or {}
			table.insert(self.foilShines, shine)
			UI.tooltip(b, "Foil. Catches the light as the tyre turns.")
		end
	end
	self:showSheet(self.sheetId)
	if #cat.list == 0 then
		local l = UI.text("No stickers found in Assets.Props.StickerPack.", 14, "body", T.faint)
		l.Size = UDim2.fromOffset(400, 80)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.ZIndex = 23
		l.Parent = self.sheet
	end
end

-- which stickers belong to which sheet; anything unlisted goes on the last one
local sheetOf: { [string]: string }? = nil
local function sheetFor(id: string): string
	if not sheetOf then
		local map = {}
		for _, sh in ipairs(Config.StickerSheets) do
			for _, sid in ipairs(sh.ids) do map[sid] = sh.id end
		end
		sheetOf = map
	end
	local last = Config.StickerSheets[#Config.StickerSheets]
	return (sheetOf :: any)[id] or (last and last.id or "")
end

function Stickers:showSheet(id: string)
	self.sheetId = id
	for sid, b in pairs(self.sheetTabs or {}) do UI.setButtonStyle(b, sid == id and "primary" or "ghost") end
	for sid, b in pairs(self.sheetButtons or {}) do b.Visible = sheetFor(sid) == id end
	self.sheet.CanvasPosition = Vector2.zero
end

function Stickers:updateUI()
	local n, max = #self.list, Config.Stickers.MaxPerTyre
	self.header.Text = ("%d / %d ON THE TYRE"):format(n, max)
	if self.noMesh then
		self.hint.Text = "Stickers can't render here. Allow EditableMesh in Game Settings > Security."
		self.hint.TextColor3 = T.bad
	else
		self.hint.TextColor3 = T.dim
		if self.placing then
			self.hint.Text = "Click the rubber to stick it on. Right-click puts it back."
		elseif self.selected then
			self.hint.Text = "Drag to slide it.  Q / E rotate.  Scroll resizes.  X peels it off."
		else
			self.hint.Text = "Pick a sticker, then click the tyre.  A / D turns the tyre, W / S rolls it."
		end
	end
	for id, edge in pairs(self.sheetCards) do
		edge.ImageColor3 = id == self.placing and T.accent or T.line
		edge.ImageTransparency = id == self.placing and 0 or 0.45
	end
	local has = self.selected ~= nil
	for _, b in ipairs(self.controls) do UI.setButtonStyle(b, has and "ghost" or "off") end
	local armed = os.clock() < self.peelArmed
	self.peelAll.Text = armed and "PRESS AGAIN" or "PEEL ALL"
	UI.setButtonStyle(self.peelAll, n == 0 and "off" or (armed and "bad" or "ghost"))
end

function Stickers:enter()
	self.active = true
	self:buildSheet()
	self:bind()
	self.selected = nil
	self:paintSelection()
	self:updateUI()
end

function Stickers:leave()
	if not self.active then return end
	self.active = false
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
	self.placing = nil
	self.ghost.Visible = false
	UI.setCursor(nil)
	self:showZone(false)
	self:clearPreview()
	self.pressing = nil
	self.selected = nil
	self:paintSelection()
	if self.dirty and not self.saving then self:save() end
end

function Stickers:setVisible(v: boolean)
	self.frame.Visible = v
	if not v then self.ghost.Visible = false end
end

function Stickers:refresh()
	self:updateUI()
end

function Stickers:step(dt: number)
	if not self.active then return end
	if not UserInputService:GetFocusedTextBox() then
		local turn, roll = 0, 0
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then turn -= 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then turn += 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then roll += 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then roll -= 1 end
		if turn ~= 0 then self.ws.yawGoal = (self.ws.yawGoal or self.ws.yaw) + turn * dt * 2.4 end
		if roll ~= 0 then self.ws.roll += roll * dt * 2 end
	end
	if self.dirty and not self.saving and not self.pressing and os.clock() >= self.saveAt then self:save() end
	if self.foilShines then
		local o = ((os.clock() * 0.45) % 1.6) - 0.8
		for _, g in ipairs(self.foilShines) do g.Offset = Vector2.new(o, 0) end
	end
	if self.peelArmed > 0 and os.clock() > self.peelArmed then
		self.peelArmed = 0
		self:updateUI()
	end
	if self.placing then
		local mouse = UserInputService:GetMouseLocation()
		local hit = self.ws:hitWheel(mouse)
		self.ghost.Position = UDim2.fromOffset(mouse.X, mouse.Y)
		self.ghost.Visible = hit == nil or self.noMesh
		if hit and not self.noMesh then
			self.hoverHit = hit
			self:showPreview(hit)
		elseif self.previewPart or self.hoverHit then
			self.hoverHit = nil
			self:clearPreview()
		end
	end
end

return Stickers
