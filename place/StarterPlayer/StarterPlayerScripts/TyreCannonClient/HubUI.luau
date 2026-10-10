--!strict
-- TYRE CANNON :: HubUI
-- The yard's shell: the money chip, the frame every panel sits in, toasts,
-- the results sheet and the daily streak. Menu panels are modules under
-- Panels and register themselves here. Everything inside a panel is centred:
-- titles, tabs, grids and button rows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunServiceForReceipt = game:GetService("RunService")
local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Remotes = Root:WaitForChild("Remotes")
local Config = require(Modules.Config)
local Progress = require(Modules.Progress)
local UI = require(script.Parent.UI)
local T = UI.Theme

local HubUI = {}
HubUI.__index = HubUI

-- the receipt's paper width; declared up here because fitReceipt needs it too
local RECEIPT_W = 400
local Icons = require(script.Parent.Icons)

function HubUI.new(gui: ScreenGui)
	local self = setmetatable({}, HubUI)
	self.gui = gui
	self.profile = nil
	self.panels = {}
	self.onLaunch = nil
	self.onAction = nil

	local chip = UI.panel({
		Name = "Money", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(236, 72), BackgroundTransparency = 0.04, ZIndex = 3, Parent = gui,
	})
	UI.autoScale(chip)
	self.chip = chip
	-- a gold coin beside the number, the label over it, the metal as coloured coins below
	UI.mk("ImageLabel", {
		Name = "Coin", Position = UDim2.fromOffset(11, 12), Size = UDim2.fromOffset(32, 32), BackgroundTransparency = 1,
		Image = Icons.Coin.credits, ZIndex = 4, Parent = chip,
	})
	local eb = UI.text("CREDITS", 11, "monoBold", T.dim)
	eb.Position = UDim2.fromOffset(50, 7)
	eb.Size = UDim2.fromOffset(120, 14)
	eb.ZIndex = 4
	eb.Parent = chip
	self.tokensLabel = UI.text("", 11, "monoBold", T.gold)
	self.tokensLabel.AnchorPoint = Vector2.new(1, 0)
	self.tokensLabel.Position = UDim2.new(1, -14, 0, 7)
	self.tokensLabel.Size = UDim2.fromOffset(100, 14)
	self.tokensLabel.TextXAlignment = Enum.TextXAlignment.Right
	self.tokensLabel.ZIndex = 4
	self.tokensLabel.Parent = chip
	self.credits = UI.text("0", 28, "display", T.text)
	self.credits.Position = UDim2.fromOffset(49, 18)
	self.credits.Size = UDim2.fromOffset(176, 32)
	self.credits.ZIndex = 4
	self.credits.Parent = chip
	-- bronze, silver and gold as coins with their counts
	self.metals = UI.mk("Frame", {
		Name = "Metals", Position = UDim2.fromOffset(12, 49), Size = UDim2.fromOffset(212, 18), BackgroundTransparency = 1,
		ZIndex = 4, Parent = chip,
	}, { UI.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	self.metalCounts = {}
	for i, def in ipairs(Config.Metals) do
		local cell = UI.mk("Frame", {
			Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 4, Parent = self.metals,
		}, { UI.list(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
		UI.mk("ImageLabel", {
			Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = (Icons.Coin :: any)[def.id], LayoutOrder = 1, ZIndex = 5, Parent = cell,
		})
		local n = UI.text("0", 13, "monoBold", T.text)
		n.Size = UDim2.fromOffset(0, 16)
		n.AutomaticSize = Enum.AutomaticSize.X
		n.LayoutOrder = 2
		n.ZIndex = 5
		n.Parent = cell
		self.metalCounts[def.id] = n
	end
	UI.tooltip(self.credits, "Credits. Earned by distance, air time, quirks and pads on every run. Spent in the shop, the garage and on the workbench.")
	UI.tooltip(self.metals, "Bronze, silver and gold, picked up on the road. Deeper checkpoints drop the rarer ones. Metal buys boosters.")
	UI.tooltip(self.tokensLabel, "Prestige tokens. Only prestiging earns them, and they buy titles and permanent upgrades.")

	self.backdrop = UI.mk("TextButton", {
		Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.void, BackgroundTransparency = 0.38,
		BorderSizePixel = 0, Text = "", AutoButtonColor = false, Selectable = false, Visible = false, ZIndex = 8, Parent = gui,
	})
	UI.guardBackdrop(self.backdrop, function() self:closeAll() end)

	-- one strip, one message at a time, always in the same place
	self.toastHolder = UI.mk("Frame", {
		Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 118), Size = UDim2.fromOffset(620, 60),
		BackgroundTransparency = 1, ZIndex = 80, Parent = gui,
	})
	UI.autoScale(self.toastHolder)
	local strip = UI.mk("CanvasGroup", {
		Name = "Strip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(320, 46),
		BackgroundTransparency = 1, GroupTransparency = 1, Visible = false, ZIndex = 80, Parent = self.toastHolder,
	})
	UI.plate("slot", { Name = "Plate", Size = UDim2.fromScale(1, 1), ZIndex = 80, Parent = strip })
	local mark = UI.mk("Frame", {
		Name = "Mark", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(4, 22),
		BackgroundColor3 = T.good, BorderSizePixel = 0, ZIndex = 81, Parent = strip,
	})
	local msg = UI.text("", 18, "display", T.text)
	msg.Name = "Text"
	msg.AnchorPoint = Vector2.new(0.5, 0.5)
	msg.Position = UDim2.new(0.5, 4, 0.5, 0)
	msg.Size = UDim2.new(1, -44, 1, -8)
	msg.TextXAlignment = Enum.TextXAlignment.Center
	msg.TextTruncate = Enum.TextTruncate.AtEnd
	msg.ZIndex = 81
	msg.Parent = strip
	self.toastStrip, self.toastMark, self.toastText = strip, mark, msg
	self.toastQueue = {}

	local panels = script.Parent:FindFirstChild("Panels")
	if panels then
		for _, mod in ipairs(panels:GetChildren()) do
			if mod:IsA("ModuleScript") then
				local ok, err = pcall(function() (require(mod) :: any)(self) end)
				if not ok then warn("[TyreCannon] panel " .. mod.Name .. " failed: " .. tostring(err)) end
			end
		end
	end
	self:buildResults()
	self:buildDaily()
	return self
end

--==============================================================
-- building blocks
--==============================================================
function HubUI:modal(name: string, title: string, sub: string, w: number, h: number)
	local p = UI.panel({
		Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(w, h), Visible = false, ZIndex = 10, Parent = self.gui,
	})
	UI.autoScale(p, w + 80, h + 90)
	local t = UI.text(title, 32, "display", T.text)
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0, 16)
	t.Size = UDim2.new(1, -140, 0, 36)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.ZIndex = 11
	t.Parent = p
	local s = UI.text(sub, 15, "body", T.dim)
	s.Name = "Subtitle"
	s.AnchorPoint = Vector2.new(0.5, 0)
	s.Position = UDim2.new(0.5, 0, 0, 52)
	s.Size = UDim2.new(1, -140, 0, 20)
	s.TextXAlignment = Enum.TextXAlignment.Center
	s.ZIndex = 11
	s.Parent = p
	local close = UI.button("X", "ghost", 38, 38)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 16)
	close.TextSize = 18
	close.ZIndex = 12
	close.Parent = p
	close.Activated:Connect(function() self:closeAll() end)
	local body = UI.mk("Frame", {
		Name = "Body", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 88),
		Size = UDim2.fromOffset(w - 56, h - 108), BackgroundTransparency = 1, ZIndex = 11, Parent = p,
	})
	return { frame = p, body = body, sub = s, title = t, w = w - 56, h = h - 108 }
end

function HubUI:register(name: string, def)
	self.panels[name] = def
end

function HubUI:scroll(parent: Instance, pos: UDim2, size: UDim2, layout: Instance?): ScrollingFrame
	local sf = UI.mk("ScrollingFrame", {
		Position = pos, Size = size, BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, ScrollBarImageColor3 = T.lineHi, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 11, Parent = parent,
	})
	if layout then layout.Parent = sf end
	UI.pad(0, 6, 6, 4, 10).Parent = sf
	return sf
end

-- a centred row of tab buttons
function HubUI:tabs(parent: Instance, names: { string }, width: number, onPick: (string) -> ())
	local row = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, ZIndex = 11, Parent = parent,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	local buttons = {}
	local function set(active: string)
		for n, b in pairs(buttons) do UI.setButtonStyle(b, n == active and "primary" or "ghost") end
	end
	for i, n in ipairs(names) do
		local b = UI.button(string.upper(n), "ghost", width, 34)
		b.TextSize = 16
		b.LayoutOrder = i
		b.ZIndex = 12
		b.Parent = row
		b.Activated:Connect(function()
			set(n)
			onPick(n)
		end)
		buttons[n] = b
	end
	return row, set
end

function HubUI:card(parent: Instance, w: number, h: number, order: number, edge: Color3?): Frame
	local f = UI.mk("Frame", {
		Size = UDim2.fromOffset(w, h), BackgroundColor3 = T.raised, BackgroundTransparency = 0.25,
		BorderSizePixel = 0, LayoutOrder = order, ZIndex = 12, Parent = parent,
	})
	UI.stroke(edge or T.line, edge and 1.5 or 1).Parent = f
	return f
end

-- a centred heading followed by a container that grows with its contents
function HubUI:section(parent: Instance, title: string, order: number, layout: Instance?)
	local head = UI.text(title, 18, "display", T.text)
	head.Size = UDim2.new(1, 0, 0, 26)
	head.TextXAlignment = Enum.TextXAlignment.Center
	head.LayoutOrder = order * 10
	head.ZIndex = 12
	head.Parent = parent
	local box = UI.mk("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		LayoutOrder = order * 10 + 1, ZIndex = 12, Parent = parent,
	})
	if layout then layout.Parent = box end
	return head, box
end

-- centred card text helper
function HubUI:line(parent: Instance, text: string, size: number, role: string, color: Color3, y: number, h: number?)
	local l = UI.text(text, size, role, color)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.Size = UDim2.new(1, -20, 0, h or (size + 6))
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextWrapped = true
	l.ZIndex = 13
	l.Parent = parent
	return l
end

function HubUI:clear(container: Instance)
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end

function HubUI:call(remoteName: string, ...: any)
	local r = Remotes:FindFirstChild(remoteName) :: RemoteFunction?
	if not r then return nil end
	local args = table.pack(...)
	local ok, res = pcall(function()
		return (r :: RemoteFunction):InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		self:toast("No answer from the server. Try again.", T.bad)
		return nil
	end
	if type(res) == "table" then
		if res.profile then self:setProfile(res.profile) end
		if res.ok == false and res.err then self:toast(res.err, T.bad) end
	end
	return res
end

--==============================================================
-- open / close
--==============================================================
-- Closing fades each open menu out; it counts as closed straight away. Returns whether
-- anything was open.
function HubUI:closeAll(): boolean
	local wasOpen = false
	for _, def in pairs(self.panels) do
		local rest = def.position or UDim2.fromScale(0.5, 0.5)
		if def.shown then
			def.shown = false
			wasOpen = true
			if def.onClose then def.onClose() end
			UI.fade(def.frame, false, { rest = rest })
		elseif def.frame.Visible and not UI.isFading(def.frame) then
			def.frame.Visible = false
		end
	end
	self.anyOpen = false
	-- switching straight to another menu keeps the backdrop up, so nothing flashes
	if not self.switching then
		self:fadeBackdrop(false)
		self:setBlur(false)
		if wasOpen and self.onOpenChanged then self.onOpenChanged(false) end
	end
	return wasOpen
end

-- the yard goes soft behind an open menu, so the panel is the only sharp thing on screen
function HubUI:setBlur(on: boolean)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local dof = cam:FindFirstChild("MenuBlur") :: DepthOfFieldEffect?
	if not dof then
		if not on then return end
		dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "MenuBlur"
		dof.FocusDistance = 0
		dof.InFocusRadius = 0
		dof.FarIntensity = 0
		dof.NearIntensity = 0
		dof.Parent = cam
	end
	local d = dof :: DepthOfFieldEffect
	self.blurToken = (self.blurToken or 0) + 1
	local token = self.blurToken
	UI.tween(d, on and 0.28 or 0.24, { FarIntensity = on and 0.6 or 0, NearIntensity = on and 0.6 or 0 })
	if not on then
		-- gone once it's faded: two depth-of-field effects on one camera render the world white
		task.delay(0.26, function()
			if self.blurToken == token and d.Parent then d:Destroy() end
		end)
	end
end

function HubUI:fadeBackdrop(on: boolean)
	local b = self.backdrop
	if self.backdropRest == nil then self.backdropRest = b.BackgroundTransparency end
	self.backdropToken = (self.backdropToken or 0) + 1
	local token = self.backdropToken
	if on then
		if not b.Visible then b.BackgroundTransparency = 1 end
		b.Visible = true
		UI.tween(b, 0.28, { BackgroundTransparency = self.backdropRest }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	elseif b.Visible then
		UI.tween(b, 0.24, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.24, function()
			if self.backdropToken ~= token then return end
			b.Visible = false
			b.BackgroundTransparency = self.backdropRest
		end)
	end
end

-- the receipt shrinks to sit under the top menu, so the printer never covers GARAGE
function HubUI:fitReceipt()
	local r = self.results
	if not (r and r.designH) then return end
	local sc = r.frame:FindFirstChildOfClass("UIScale")
	local layer = r.frame:FindFirstAncestorWhichIsA("LayerCollector")
	local cam = workspace.CurrentCamera
	if not (sc and layer and cam) then return end
	local screenH = (layer :: any).AbsoluteSize.Y
	-- never up under Roblox's own top-bar buttons
	local ceiling = 10
	if (layer :: any).IgnoreGuiInset then
		ceiling = game:GetService("GuiService"):GetGuiInset().Y + 10
	end
	local pg = layer.Parent
	local garage = pg and pg:FindFirstChild("GarageButton", true) :: GuiObject?
	local garageHidden = garage and garage.Parent and garage.Parent:GetAttribute("Hidden") == true
	if garage and garage.Visible and not garageHidden then
		ceiling = garage.AbsolutePosition.Y + garage.AbsoluteSize.Y + 30
	end
	local Prefs = require(script.Parent:WaitForChild("Prefs")) :: any
	local v = cam.ViewportSize
	local natural = math.clamp(math.min(v.X / (RECEIPT_W + 140), v.Y / (r.designH + 120)), 0.5, 1.15) * (Prefs.get("uiScale") or 1)
	-- the printer sits 12 above the frame, and the frame's foot 12 off the bottom
	local cap = (screenH - 12 - ceiling) / (r.designH + 12)
	local target = math.max(0.3, math.min(natural, cap))
	if math.abs(sc.Scale - target) > 0.002 then sc.Scale = target end
end

function HubUI:open(name: string)
	local def = self.panels[name]
	self.switching = def ~= nil
	local wasOpen = self:closeAll()
	self.switching = false
	if not def then return end
	if def.refresh then def.refresh() end
	self:fadeBackdrop(true)
	self:setBlur(true)
	if not wasOpen and self.onOpenChanged then self.onOpenChanged(true) end
	def.shown = true
	self.anyOpen = true
	-- switching: the old menu finishes fading out before this one fades in
	UI.fade(def.frame, true, { rest = def.position or UDim2.fromScale(0.5, 0.5), delay = wasOpen and 0.2 or 0 })
	if def.onOpen then def.onOpen() end
end

function HubUI:isOpen(name: string?): boolean
	if name then
		local def = self.panels[name]
		return def ~= nil and def.shown == true
	end
	return self.anyOpen == true
end

function HubUI:setHubVisible(v: boolean)
	self.chip.Visible = v
	if not v then self:closeAll() end
end

function HubUI:setProfile(profile)
	if not profile then return end
	self.profile = profile
	-- the credits roll up (or down) to the new number rather than jumping
	local target = math.floor(profile.credits or 0)
	local from = self.shownCredits or target
	self.creditToken = (self.creditToken or 0) + 1
	local token = self.creditToken
	if from == target then
		self.shownCredits = target
		self.credits.Text = UI.comma(target)
	else
		task.spawn(function()
			local t, dur = 0, math.clamp(math.abs(target - from) / 2500, 0.35, 0.9)
			while t < dur and self.creditToken == token do
				t += game:GetService("RunService").RenderStepped:Wait()
				local k = 1 - (1 - math.min(t / dur, 1)) ^ 3
				self.shownCredits = math.floor(from + (target - from) * k + 0.5)
				self.credits.Text = UI.comma(self.shownCredits)
			end
			if self.creditToken == token then
				self.shownCredits = target
				self.credits.Text = UI.comma(target)
			end
		end)
	end
	local m = profile.metals or {}
	for _, def in ipairs(Config.Metals) do
		local n = self.metalCounts and self.metalCounts[def.id]
		if n then n.Text = UI.comma(m[def.id] or 0) end
	end
	self.tokensLabel.Text = (profile.tokens or 0) > 0 and ("%d TOKEN%s"):format(profile.tokens, profile.tokens == 1 and "" or "S") or ""
	for _, def in pairs(self.panels) do
		if def.frame.Visible and def.refresh and not def.noAutoRefresh then
			def.refresh()
			-- keep a message that's showing in the subtitle through the refresh
			local sub = def.frame:FindFirstChild("Subtitle")
			if sub and sub:IsA("TextLabel") and sub:GetAttribute("FlashText") then
				sub:SetAttribute("FlashBase", sub.Text)
				sub.Text = sub:GetAttribute("FlashText")
				sub.TextColor3 = sub:GetAttribute("FlashColor") or T.text
			end
		end
	end
end

function HubUI:toast(text: string, color: Color3)
	-- with a menu open the message goes in that menu's subtitle, never on top of its cards
	for _, def in pairs(self.panels) do
		local sub = def.frame.Visible and def.frame:FindFirstChild("Subtitle")
		if sub and sub:IsA("TextLabel") then
			self:flashSubtitle(sub, text, color)
			return
		end
	end
	self:floatToast(text, color)
end

function HubUI:flashSubtitle(sub: TextLabel, text: string, color: Color3)
	local token = (sub:GetAttribute("FlashToken") or 0) + 1
	sub:SetAttribute("FlashToken", token)
	if sub:GetAttribute("FlashText") == nil then
		sub:SetAttribute("FlashBase", sub.Text)
		sub:SetAttribute("FlashBaseColor", sub.TextColor3)
	end
	sub:SetAttribute("FlashText", text)
	sub:SetAttribute("FlashColor", color)
	sub.Text = text
	sub.TextColor3 = color
	task.delay(1.8, function()
		if sub:GetAttribute("FlashToken") ~= token then return end
		sub.Text = sub:GetAttribute("FlashBase") or ""
		sub.TextColor3 = sub:GetAttribute("FlashBaseColor") or T.dim
		sub:SetAttribute("FlashText", nil)
		sub:SetAttribute("FlashColor", nil)
		sub:SetAttribute("FlashBase", nil)
		sub:SetAttribute("FlashBaseColor", nil)
	end)
end

-- Every message waits its turn in one strip under the top of the screen. The same
-- message twice in a row counts up instead of queueing again.
function HubUI:floatToast(text: string, color: Color3)
	local q = self.toastQueue
	local showing = self.toastShowing
	local last = q[#q] or showing
	if last and last.text == text then
		last.count += 1
		last.hold = math.max(last.hold, 1.2)
		if last == showing then self:paintToast(last) end
		return
	end
	if #q >= 4 then table.remove(q, 1) end
	table.insert(q, { text = text, color = color, count = 1, hold = 1.8 })
	if not self.toastRunning then
		self.toastRunning = true
		task.spawn(function() self:runToasts() end)
	end
end

function HubUI:paintToast(item)
	local label = self.toastText
	label.Text = item.count > 1 and ("%s  <font color=\"#AAA296\">x%d</font>"):format(item.text, item.count) or item.text
	label.TextColor3 = (item.color == T.bad) and T.text or item.color
	self.toastMark.BackgroundColor3 = item.color
	local w = math.clamp(label.TextBounds.X + 64, 240, 620)
	self.toastStrip.Size = UDim2.fromOffset(w, 46)
end

function HubUI:runToasts()
	local strip = self.toastStrip
	while #self.toastQueue > 0 do
		local item = table.remove(self.toastQueue, 1)
		self.toastShowing = item
		strip.Visible = true
		self:paintToast(item)
		task.wait()
		self:paintToast(item)
		strip.Position = UDim2.new(0.5, 0, 0, -10)
		UI.tween(strip, 0.16, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0) }, Enum.EasingStyle.Back)
		local shown = 0
		while shown < item.hold do
			local dt = task.wait(0.05)
			shown += dt
			-- a queue behind it shortens the wait
			if #self.toastQueue > 0 then item.hold = math.min(item.hold, 1.1) end
		end
		UI.tween(strip, 0.14, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0, -8) })
		task.wait(0.16)
	end
	self.toastShowing = nil
	strip.Visible = false
	self.toastRunning = false
end

--==============================================================
-- results, printed like a truck-stop receipt
--==============================================================
local PAPER = Color3.fromRGB(238, 233, 221)
local INK = Color3.fromRGB(36, 33, 30)
local INK_FAINT = Color3.fromRGB(118, 110, 100)
local STAMP_RED = Color3.fromRGB(196, 32, 42)

function HubUI:buildResults()
	local frame = UI.mk("Frame", {
		Name = "Results", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(RECEIPT_W + 40, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 10, Parent = self.gui,
	})
	local receiptScale = UI.autoScale(frame, RECEIPT_W + 140, 820)
	-- whatever rescales the receipt, it still has to fit under the top menu
	receiptScale:GetPropertyChangedSignal("Scale"):Connect(function() self:fitReceipt() end)

	-- the paper, clipped so it can feed up out of the printer slot
	local window = UI.mk("Frame", {
		Name = "Window", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, RECEIPT_W + 24, 1, -64), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 11, Parent = frame,
	})
	local paper = UI.mk("Frame", {
		Name = "Paper", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(RECEIPT_W, 500), BackgroundColor3 = PAPER, BorderSizePixel = 0, ZIndex = 12, Parent = window,
	})
	UI.mk("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.85, Color3.fromRGB(246, 244, 240)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 208, 196)),
		}),
		Parent = paper,
	})
	-- the torn edge: a row of paper teeth hanging off the foot, in the paper's own colour
	UI.mk("ImageLabel", {
		Name = "Teeth", Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 10), BackgroundTransparency = 1,
		Image = Icons.Receipt.teeth, ImageColor3 = Color3.fromRGB(214, 208, 196), ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(32, 10), ZIndex = 12, Parent = paper,
	})
	local lines = UI.mk("Frame", {
		Name = "Lines", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, ZIndex = 13, Parent = paper,
	}, { UI.list(Enum.FillDirection.Vertical, 1, Enum.HorizontalAlignment.Center) })
	UI.pad(0, 24, 24, 22, 26).Parent = lines

	-- the printer the paper feeds out of: the paper's top edge tucks up under its lip
	local slot = UI.mk("ImageLabel", {
		Name = "Printer", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -12), Size = UDim2.fromOffset(RECEIPT_W + 44, 36),
		BackgroundTransparency = 1, Image = Icons.Receipt.printer, ScaleType = Enum.ScaleType.Stretch, ZIndex = 14, Parent = frame,
	})

	-- straight back out on the same road, or home
	local again = UI.button("RUN IT BACK", "primary", 212, 48)
	again.Name = "AgainButton"
	again.AnchorPoint = Vector2.new(0.5, 1)
	again.Position = UDim2.new(0.5, 110, 1, 0)
	again.ZIndex = 14
	again.Parent = frame
	local back = UI.button("BACK TO THE YARD", "ghost", 212, 48)
	back.Name = "BackButton"
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, -110, 1, 0)
	back.ZIndex = 14
	back.Parent = frame

	self.results = { frame = frame, window = window, paper = paper, lines = lines, back = back, again = again, slot = slot }
	self:register("Results", { frame = frame, noAutoRefresh = true, position = UDim2.new(0.5, 0, 1, -12) })
end

function HubUI:showResults(summary, payout, onAgain, onBack)
	local r = self.results
	local lines, paper = r.lines, r.paper
	self:clear(lines)
	for _, c in ipairs(paper:GetChildren()) do
		if c.Name == "Stamp" then c:Destroy() end
	end
	local order = 0
	local rows = {}
	local function add(o: GuiObject)
		order += 1
		o.LayoutOrder = order
		o.Parent = lines
		table.insert(rows, o)
		return o
	end
	local function centre(text: string, size: number, role: string, color: Color3, h: number?)
		local l = UI.text(text, size, role, color)
		l.Size = UDim2.new(1, 0, 0, h or (size + 8))
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.TextWrapped = true
		l.ZIndex = 14
		return add(l)
	end
	local function rule(char: string?)
		return centre(string.rep(char or "- ", 34), 12, "mono", INK_FAINT, 16)
	end
	-- label ........ value
	local function pair(label: string, value: string, color: Color3?, strong: boolean?, tip: string?)
		local row = UI.mk("Frame", { Size = UDim2.new(1, 0, 0, strong and 26 or 21), BackgroundTransparency = 1, ZIndex = 14 })
		local size = strong and 18 or 14
		local dots = UI.text(string.rep(".", 90), 12, "mono", Color3.fromRGB(176, 168, 156))
		dots.Size = UDim2.fromScale(1, 1)
		dots.TextXAlignment = Enum.TextXAlignment.Center
		dots.TextTruncate = Enum.TextTruncate.None
		dots.ClipsDescendants = true
		dots.ZIndex = 14
		dots.Parent = row
		local l = UI.text(label, size, strong and "monoBold" or "mono", color or INK)
		l.AutomaticSize = Enum.AutomaticSize.X
		l.Size = UDim2.fromScale(0, 1)
		l.BackgroundTransparency = 0
		l.BackgroundColor3 = PAPER
		l.BorderSizePixel = 0
		l.ZIndex = 15
		l.Parent = row
		UI.pad(0, 0, 6, 0, 0).Parent = l
		local v = UI.text(value, size, "monoBold", color or INK)
		v.AnchorPoint = Vector2.new(1, 0)
		v.Position = UDim2.fromScale(1, 0)
		v.AutomaticSize = Enum.AutomaticSize.X
		v.Size = UDim2.fromScale(0, 1)
		v.TextXAlignment = Enum.TextXAlignment.Right
		v.BackgroundTransparency = 0
		v.BackgroundColor3 = PAPER
		v.BorderSizePixel = 0
		v.ZIndex = 15
		v.Parent = row
		UI.pad(0, 6, 0, 0, 0).Parent = v
		if tip then UI.tooltip(row, tip) end
		return add(row)
	end
	local function gap(h: number)
		return add(UI.mk("Frame", { Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1 }))
	end

	local track = Config.TracksById[summary.trackId] or {}
	local reasons = { stopped = "ROLLED TO A STOP", bailed = "BAILED OUT", timeout = "OUT OF TIME", aborted = "CALLED OFF", overheat = "BLOWOUT" }
	local counts = payout.counts or {}
	local b = payout.breakdown or {}
	local topSpeed = math.floor((summary.maxSpeed or 0) + 0.5)

	do
		local logo = UI.mk("ImageLabel", {
			Name = "Logo", Size = UDim2.new(0, 160, 0, math.floor(160 / Config.Brand.LogoAspect)), BackgroundTransparency = 1,
			Image = Config.Brand.Logo200 or Config.Brand.Logo, ScaleType = Enum.ScaleType.Fit, ZIndex = 14,
		})
		add(logo)
	end
	centre("TRUCK STOP  ·  " .. string.upper(track.name or "THE ROAD"), 12, "monoBold", INK_FAINT, 16)
	centre(os.date("%d %b %Y   %H:%M"), 12, "mono", INK_FAINT, 16)
	rule()
	centre(UI.comma(math.floor(summary.metres or 0)) .. " M", 44, "display", INK, 48)
	centre(reasons[summary.reason] or "RUN OVER", 13, "monoBold", summary.reason == "overheat" and STAMP_RED or INK_FAINT, 18)
	rule()
	pair("TOP SPEED", UI.comma(topSpeed) .. " STUDS/S", nil, false, "The fastest the tyre went this run.")
	pair("CHECKPOINTS", ("%d / %d"):format(summary.tier or 0, #Config.Difficulty.Checkpoints), nil, false, "Gates crossed. Each one opens a quirk draft, and the road gets rougher past it.")
	pair("AIR TIME", ("%.1f S"):format(counts.airTime or summary.airTime or 0), nil, false, "Every second off the ground pays.")
	pair("LONGEST JUMP", ("%.1f S"):format(summary.longestAir or 0))
	pair("QUIRKS", tostring(counts.perks or summary.perks or 0), nil, false, "Quirk icons picked up on the road, plus draft picks.")
	pair("PADS", tostring(counts.pads or summary.pads or 0))
	pair("SMASHED", tostring(payout.smashes or summary.smashes or 0), nil, false, "Obstacles you went through fast enough to break.")
	pair("HITS", tostring(summary.hits or 0), (summary.hits or 0) > 0 and STAMP_RED or nil, false, "Obstacles you bounced off. Each one costs speed and resets your quirk chain.")
	pair("IN THE RED", ("%.1f S"):format(summary.redlineSeconds or 0), nil, false, "Time spent boosting past the redline. Stronger shove, but the tyre can blow.")
	rule()
	pair("DISTANCE", UI.comma(b.distance or 0) .. " CR")
	pair("AIR", UI.comma(b.air or 0) .. " CR")
	pair("QUIRKS", UI.comma(b.perks or 0) .. " CR")
	pair("PADS", UI.comma(b.pads or 0) .. " CR")
	if (b.bonus or 0) > 0 then pair("BONUSES", UI.comma(b.bonus) .. " CR") end
	pair("ROAD", ("x%.2f"):format(b.trackMult or 1), INK_FAINT, false, "Harder roads pay more for the same run.")
	pair("QUIRK CHAIN", ("x%.2f"):format(b.quirkMult or 1), INK_FAINT, false, "Your average multiplier from chaining quirks without getting hit.")
	pair("EVERYTHING ELSE", ("x%.2f"):format(b.extraMult or 1), INK_FAINT, false, "Toolboxes, token upgrades, spectators and boosters, together.")
	if payout.chai then pair("MASALA CHAI", "+25%", INK_FAINT) end
	local mg = payout.metals or {}
	for _, m in ipairs(Config.Metals) do
		if (mg[m.id] or 0) > 0 then
			-- the metal's coin printed beside its name
			local row = pair(string.upper(m.name), "+" .. mg[m.id])
			local label = row:FindFirstChildWhichIsA("TextLabel")
			for _, c in ipairs(row:GetChildren()) do
				if c:IsA("TextLabel") and c.AutomaticSize == Enum.AutomaticSize.X and c.TextXAlignment == Enum.TextXAlignment.Left then label = c end
			end
			if label then
				local pad = label:FindFirstChildOfClass("UIPadding")
				if pad then pad.PaddingLeft = UDim.new(0, 20) end
				UI.mk("ImageLabel", {
					AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(16, 16),
					BackgroundTransparency = 1, Image = (Icons.Coin :: any)[m.id], ZIndex = 16, Parent = label,
				})
			end
		end
	end
	for _, c in ipairs(payout.contracts or {}) do
		pair("CONTRACT", "DONE", INK)
		centre(c.text, 12, "mono", INK_FAINT, 16)
	end
	for _, tb in ipairs(payout.found or {}) do
		local rar = Config.ToolboxRaritiesById[tb.rarity]
		local kind = Config.ToolboxKindsById[tb.kind]
		if rar and kind then pair("FOUND", string.upper(rar.name .. " " .. kind.name), INK) end
	end
	rule("= ")
	pair("TOTAL", "+" .. UI.comma(payout.earned or 0) .. " CR", INK, true)
	gap(6)
	centre("THANK YOU FOR ROLLING WITH US", 11, "monoBold", INK_FAINT, 14)
	centre("* " .. string.upper(track.subtitle and "keep it rolling" or "see you on the road") .. " *", 11, "mono", INK_FAINT, 14)

	-- print it: the paper feeds up out of the slot a line at a time
	for _, row in ipairs(rows) do
		for _, d in ipairs(row:GetDescendants()) do
			if d:IsA("TextLabel") then d:SetAttribute("Ink", d.TextTransparency); d.TextTransparency = 1 end
		end
		if row:IsA("TextLabel") then row:SetAttribute("Ink", row.TextTransparency); row.TextTransparency = 1 end
	end
	r.back.Visible = false
	r.again.Visible = false
	local function drop()
		for _, key in ipairs({ "backConn", "againConn", "keyConn" }) do
			if r[key] then r[key]:Disconnect() end
			r[key] = nil
		end
	end
	drop()
	local function goBack()
		drop()
		self:closeAll()
		if onBack then onBack() end
	end
	local function goAgain()
		drop()
		self:closeAll()
		if onAgain then onAgain() end
	end
	r.backConn = r.back.Activated:Connect(goBack)
	r.againConn = r.again.Activated:Connect(goAgain)
	-- R runs it back from the keyboard once the receipt has printed
	r.keyConn = game:GetService("UserInputService").InputBegan:Connect(function(input, gpe)
		if gpe or not (r.again.Visible and r.frame.Visible and self:isOpen("Results")) then return end
		if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonY then goAgain() end
	end)
	self:open("Results")
	task.spawn(function()
		-- let the list lay itself out before measuring it
		RunServiceForReceipt.RenderStepped:Wait()
		RunServiceForReceipt.RenderStepped:Wait()
		local h = lines.AbsoluteSize.Y / math.max(0.01, (r.frame:FindFirstChildOfClass("UIScale") :: UIScale).Scale) + 8
		if h < 120 then
			-- still hidden behind a fade: fall back to adding the rows up
			h = 48
			for _, row in ipairs(rows) do h += row.Size.Y.Offset + 1 end
		end
		-- the whole receipt always fits: the frame grows to it and the screen scaling shrinks it
		r.frame.Size = UDim2.fromOffset(RECEIPT_W + 40, h + 26 + 72)
		r.designH = h + 26 + 72
		self:fitReceipt()
		paper.Size = UDim2.fromOffset(RECEIPT_W, h)
		paper.Position = UDim2.new(0.5, 0, 0, -h)
		UI.tween(paper, 0.2 + #rows * 0.028, { Position = UDim2.new(0.5, 0, 0, 14) }, Enum.EasingStyle.Linear)
		for i, row in ipairs(rows) do
			task.delay(0.05 + i * 0.028, function()
				local list = row:GetDescendants()
				table.insert(list, row)
				for _, d in ipairs(list) do
					if d:IsA("TextLabel") and d:GetAttribute("Ink") ~= nil then
						d.TextTransparency = d:GetAttribute("Ink")
					end
				end
			end)
		end
		task.delay(0.35 + #rows * 0.028, function()
			if not r.frame.Visible then return end
			r.back.Visible = true
			r.again.Visible = onAgain ~= nil
			if payout.best then
				self:stampReceipt(paper)
				local ok, Sound = pcall(require, script.Parent.Sound)
				if ok then Sound.play("cheer", { length = 3.2 }) end
			end
		end)
	end)
end

-- the rubber stamp for a new best, slammed across the distance
function HubUI:stampReceipt(paper: Frame)
	local stamp = UI.mk("CanvasGroup", {
		Name = "Stamp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -78, 0, 122),
		Size = UDim2.fromOffset(156, 56), BackgroundTransparency = 1, Rotation = -12, GroupTransparency = 0.12, ZIndex = 30, Parent = paper,
	})
	-- inset, so the border isn't cut off by the group's edges
	local box = UI.mk("Frame", {
		Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1, ZIndex = 30, Parent = stamp,
	})
	UI.mk("UICorner", { CornerRadius = UDim.new(0, 8), Parent = box })
	UI.mk("UIStroke", { Color = STAMP_RED, Thickness = 4, Parent = box })
	local t = UI.text("NEW BEST", 24, "display", STAMP_RED)
	t.Size = UDim2.new(1, 0, 0, 28)
	t.Position = UDim2.fromOffset(0, 8)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.ZIndex = 31
	t.Parent = stamp
	local s = UI.text("PERSONAL RECORD", 9, "monoBold", STAMP_RED)
	s.Size = UDim2.new(1, 0, 0, 12)
	s.Position = UDim2.fromOffset(0, 35)
	s.TextXAlignment = Enum.TextXAlignment.Center
	s.ZIndex = 31
	s.Parent = stamp
	-- uneven ink
	UI.mk("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.35, 0.3),
			NumberSequenceKeypoint.new(0.6, 0), NumberSequenceKeypoint.new(1, 0.35),
		}),
		Parent = stamp,
	})
	local sc = UI.mk("UIScale", { Scale = 2.2, Parent = stamp })
	stamp.GroupTransparency = 1
	UI.tween(stamp, 0.08, { GroupTransparency = 0.12 })
	UI.tween(sc, 0.12, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.12, function()
		local p = paper.Position
		paper.Position = p + UDim2.fromOffset(0, 4)
		UI.tween(paper, 0.16, { Position = p }, Enum.EasingStyle.Back)
	end)
end

--==============================================================
-- daily streak
--==============================================================
function HubUI:buildDaily()
	local m = self:modal("Daily", "DAILY", "Every day you show up pays. Miss a day and it starts over.", 740, 340)
	local function refresh()
		local p = self.profile
		if not p then return end
		self:clear(m.body)
		local claimable, index = Progress.dailyState(p)
		local row = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(1, 0, 0, 150),
			BackgroundTransparency = 1, ZIndex = 12, Parent = m.body,
		}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
		local cw = math.floor((m.w - 56) / 7)
		for i, reward in ipairs(Config.Daily) do
			local current = i == index
			local past = (i < index) or (not claimable and i == index)
			local c = self:card(row, cw, 150, i, current and T.accent or nil)
			self:line(c, "DAY " .. i, 13, "monoBold", current and T.accent or T.faint, 8, 16)
			self:line(c, (UI.money(reward):gsub("  ", "\n")), 13, "monoBold", T.text, 32, 80)
			if past then
				self:line(c, "TAKEN", 12, "monoBold", T.good, 122, 16)
				c.BackgroundTransparency = 0.6
			end
		end
		local btn = UI.button(claimable and ("CLAIM DAY " .. index) or "BACK TOMORROW", claimable and "primary" or "off", 280, 48)
		btn.AnchorPoint = Vector2.new(0.5, 1)
		btn.Position = UDim2.new(0.5, 0, 1, 0)
		btn.ZIndex = 12
		btn.Parent = m.body
		btn.Activated:Connect(function()
			if not claimable then return end
			local res = self:call("ClaimDaily")
			if res and res.ok then
				self:toast("DAY " .. res.day .. " CLAIMED", T.good)
				refresh()
			end
		end)
	end
	self:register("Daily", { frame = m.frame, refresh = refresh })
end

function HubUI:showDailyIfReady()
	if self.profile and Progress.dailyState(self.profile) and not self:isOpen() then
		self:open("Daily")
	end
end

return HubUI
