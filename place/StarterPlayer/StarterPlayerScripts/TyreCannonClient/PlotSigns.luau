--!strict
-- TYRE CANNON :: PlotSigns
-- A nameplate hanging in the air over every plot: the owner's head, their name,
-- what they are doing, and a green SPECTATE tab under it while they are on a
-- run. The old board bolted to the front of the plot meant walking over to read
-- it; this one is readable and clickable from anywhere in the yard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Config"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local T = UI.Theme

local PlotSigns = {}
PlotSigns.__index = PlotSigns

local STATUS = {
	base      = { text = "IN BASE",       color = Color3.fromRGB(120, 235, 150) },
	launching = { text = "LAUNCHING",     color = Color3.fromRGB(255, 176, 60) },
	attempt   = { text = "IN AN ATTEMPT", color = Color3.fromRGB(90, 200, 255) },
	afk       = { text = "AFK",           color = Color3.fromRGB(140, 134, 126) },
}

local BRASS = Color3.fromRGB(222, 178, 96)
local AMBER = Color3.fromRGB(255, 196, 70)
local FLIP_CHARS = "0123456789"

-- A split-flap row: each cell rattles through a few characters before it lands,
-- one after another from the left, like a station board.
local function flipBoard(parent: Instance, x: number, y: number, cells: number)
	local board = { cells = {} }
	for i = 1, cells do
		local cell = UI.mk("Frame", {
			Position = UDim2.fromOffset(x + (i - 1) * 15, y), Size = UDim2.fromOffset(13, 18),
			BackgroundColor3 = Color3.fromRGB(12, 13, 16), BorderSizePixel = 0, ClipsDescendants = true, Parent = parent,
		})
		UI.corner(2).Parent = cell
		local label = UI.text("", 13, "monoBold", AMBER)
		label.Size = UDim2.fromScale(1, 1)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.ZIndex = 2
		label.Parent = cell
		local flap = UI.mk("Frame", {
			Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
			BorderSizePixel = 0, ZIndex = 3, Parent = cell,
		})
		UI.mk("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 4, Parent = cell,
		})
		table.insert(board.cells, { label = label, flap = flap, ch = "", token = 0 })
	end
	function board.setVisible(on: boolean)
		for _, c in ipairs(board.cells) do
			if c.label.Parent then (c.label.Parent :: Frame).Visible = on end
		end
	end
	function board.set(text: string, animate: boolean)
		local padded = text
		if #padded > cells then padded = padded:sub(-cells) end
		padded = string.rep(" ", cells - #padded) .. padded
		for i, c in ipairs(board.cells) do
			local ch = padded:sub(i, i)
			if c.ch ~= ch then
				c.ch = ch
				c.token += 1
				local token = c.token
				if not animate then
					c.label.Text = ch
				else
					task.delay((i - 1) * 0.06, function()
						for n = 1, 3 do
							if c.token ~= token then return end
							local r = math.random(1, #FLIP_CHARS)
							c.label.Text = FLIP_CHARS:sub(r, r)
							c.flap.BackgroundTransparency = 0.45
							task.wait(0.045)
							c.flap.BackgroundTransparency = 1
							task.wait(0.02)
						end
						if c.token == token then c.label.Text = ch end
					end)
				end
			end
		end
	end
	return board
end

local thumbCache: { [number]: string } = {}

local function thumbnailFor(userId: number): string?
	if thumbCache[userId] then return thumbCache[userId] end
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(userId,
			Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and url then
		thumbCache[userId] = url
		return url
	end
	return nil
end

--==============================================================
function PlotSigns.new(onSpectate)
	local self = setmetatable({}, PlotSigns)
	self.boards = {}
	self.onSpectate = onSpectate
	self.myUserId = Players.LocalPlayer.UserId

	local plots = PlotSigns.waitForPlots(8, 30)
	if not plots then return self end

	for _, plot in ipairs(plots:GetChildren()) do
		local index = plot:GetAttribute("Index")
		local anchor = plot:FindFirstChild("NameAnchor")
		if index and anchor then
			self.boards[index] = self:buildBoard(anchor)
			if self.boards[index] then self.boards[index].index = index end
		end
	end

	self:apply({})

	-- Billboard buttons don't always get clicks, so a click on the screen also checks
	-- for a sign tab under the pointer. A short debounce keeps one press from firing twice.
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	self.lastPress = 0
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not pg then return end
		local pos = input.UserInputType == Enum.UserInputType.Touch and Vector2.new(input.Position.X, input.Position.Y)
			or (UserInputService:GetMouseLocation() - Vector2.new(0, GuiService:GetGuiInset().Y))
		local ok, hits = pcall(function() return pg:GetGuiObjectsAtPosition(pos.X, pos.Y) end)
		if not ok then return end
		for _, o in ipairs(hits) do
			for _, b in pairs(self.boards) do
				if b.viewTab and o == b.viewTab and b.viewTab.Visible then
					self:pressView(b)
					return
				elseif b.tab and o == b.tab and b.tab.Visible then
					self:pressSpectate(b)
					return
				end
			end
		end
	end)
	return self
end

function PlotSigns:pressView(node)
	if os.clock() - (self.lastPress or 0) < 0.3 then return end
	self.lastPress = os.clock()
	if self.onView and node.info then self.onView(node.index, node.info) end
end

function PlotSigns:pressSpectate(node)
	if os.clock() - (self.lastPress or 0) < 0.3 then return end
	self.lastPress = os.clock()
	if self.onSpectate and node.userId then self.onSpectate(node.userId, node.displayName) end
end

-- WaitForChild on a folder returns the moment the FOLDER arrives, not when its
-- contents have. Wait for the expected number of plots, each with its Index
-- and sign board actually present, before touching any of them.
function PlotSigns.waitForPlots(expected: number, timeout: number)
	local lobby = workspace:WaitForChild("Lobby", timeout)
	if not lobby then return nil end
	local plots = lobby:WaitForChild("Plots", timeout)
	if not plots then return nil end

	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local ready = 0
		for _, plot in ipairs(plots:GetChildren()) do
			if plot:GetAttribute("Index") and plot:FindFirstChild("NameAnchor")
				and plot:FindFirstChild("ClaimPad") then
				ready += 1
			end
		end
		if ready >= expected then return plots end
		task.wait(0.1)
	end
	return plots
end

--==============================================================
function PlotSigns:buildBoard(anchor: BasePart)
	-- The plate itself is baked into the place, not built here. A BillboardGui
	-- created at runtime is at the mercy of whenever the client gets round to
	-- it; one that ships with the plot is simply there. All this does is find
	-- the pieces and wire the tab up.
	local gui = anchor:WaitForChild("PlotSign", 10)
	if not gui then return nil end
	local plate = gui:WaitForChild("Plate", 10)
	if not plate then return nil end

	local head = plate:WaitForChild("Head", 5)
	local pill = plate:WaitForChild("Pill", 5)
	-- a billboard only takes clicks from inside PlayerGui, so the sign moves there and
	-- stays pinned to its anchor; SPECTATE and VIEW WHEEL work from anywhere in the yard
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		gui.Adornee = anchor
		gui.ResetOnSpawn = false
		gui.Name = "PlotSign_" .. anchor.Parent.Name
		gui.Parent = playerGui
	end
	local node = {
		anchor = anchor,
		gui = gui,
		bg = plate,
		stroke = plate:FindFirstChild("Edge"),
		head = head and head:FindFirstChild("Portrait"),
		placeholder = head and head:FindFirstChild("Placeholder"),
		name = plate:FindFirstChild("Title"),
		sub = plate:FindFirstChild("Sub"),
		pill = pill,
		dot = pill and pill:FindFirstChild("Dot"),
		statusText = pill and pill:FindFirstChild("Status"),
		pres = plate:FindFirstChild("Pres"),
		tab = gui:FindFirstChild("SpectateTab"),
	}

	-- new type on the baked plate, and a title line that sits over @username
	local F = UI.Fonts
	if node.name then node.name.FontFace = F.display end
	if node.sub then node.sub.FontFace = F.mono end
	if node.statusText then node.statusText.FontFace = F.monoBold end
	if node.pres then node.pres.FontFace = F.monoBold end
	if node.placeholder then node.placeholder.FontFace = F.display end
	if node.tab and node.tab:IsA("TextButton") then node.tab.FontFace = F.display end
	if node.sub then
		local t = UI.titleLabel(nil, node.sub.TextSize)
		t.Name = "TitleLine"
		t.Position = node.sub.Position
		t.Size = node.sub.Size
		t.AnchorPoint = node.sub.AnchorPoint
		t.TextXAlignment = node.sub.TextXAlignment
		t.ZIndex = node.sub.ZIndex + 1
		t.Parent = node.sub.Parent
		node.titleLine = t
	end

	if node.tab then
		node.tab.MouseButton1Click:Connect(function() self:pressSpectate(node) end)
	end

	-- dressed in the kit (the menus' own panel and ring, the ring in the status colour), only
	-- shown near enough to matter: name, best, status, and SPECTATE while they're on a run
	gui.MaxDistance = 230
	gui.Size = UDim2.fromOffset(240, 132)
	plate.BackgroundTransparency = 1
	plate.Position = UDim2.fromOffset(0, 18)
	plate.Size = UDim2.fromOffset(240, 82)
	if node.stroke and node.stroke:IsA("UIStroke") then node.stroke.Enabled = false end
	for _, d in ipairs(plate:GetChildren()) do
		if d:IsA("UICorner") or d:IsA("UIGradient") then d:Destroy() end
	end
	local z = (plate.ZIndex or 1)
	node.body = Kit.slice("panel_body", nil, plate, z, 0.32)
	node.ring = Kit.slice("panel_ring", Kit.C.accent, plate, z + 1, 0.32)
	for _, d in ipairs(plate:GetDescendants()) do
		if d:IsA("GuiObject") and d ~= node.ring and d ~= node.body and d.ZIndex <= z + 1 then d.ZIndex = z + 2 end
	end
	if node.name then
		node.name.TextColor3 = Kit.C.text
		node.name.FontFace = Kit.Font
	end
	if node.sub then
		node.sub.TextColor3 = Kit.C.muted
		node.sub.FontFace = Kit.Body
	end
	if node.statusText then node.statusText.FontFace = Kit.Body end
	-- the rig's name over the plate, the best distance in gold under the name
	local rig = Kit.text("", 13, Kit.C.gold, 2)
	rig.Name = "RigName"
	rig.Size = UDim2.fromOffset(240, 18)
	rig.Parent = gui
	node.rig = rig
	local best = Kit.text("", 15, Kit.C.gold, 2)
	best.Name = "Best"
	best.AnchorPoint = Vector2.new(0, 1)
	best.TextXAlignment = Enum.TextXAlignment.Left
	best.Position = UDim2.new(0, 62, 1, -9)
	best.Size = UDim2.fromOffset(170, 18)
	best.ZIndex = z + 3
	best.Parent = plate
	node.best = best
	-- the old tab goes; a kit button takes its place
	if node.tab then node.tab:Destroy() end
	local spec = Kit.button("Spectate", Kit.C.green, UDim2.fromOffset(150, 30), 15)
	spec.root.AnchorPoint = Vector2.new(0.5, 0)
	spec.root.Position = UDim2.new(0.5, 0, 0, 102)
	spec.root.Visible = false
	spec.root.Parent = gui
	spec.onClick = function() self:pressSpectate(node) end
	node.tab = spec.root
	return node
end

function PlotSigns:apply(snapshot)
	snapshot = snapshot or {}
	for index, b in pairs(self.boards) do
		local info = snapshot[index]
		if info and info ~= false and type(info) == "table" then
			local st = STATUS[info.status] or STATUS.base
			local sameOwner = b.userId == info.userId
			b.info = info
			if b.rig then
				local name = type(info.rigName) == "string" and info.rigName or ""
				b.rig.Text = name ~= "" and ('"' .. string.upper(name) .. '"') or ""
			end
			if b.best then
				local best = tonumber(info.best) or 0
				b.best.Text = best > 0 and ("BEST  " .. UI.comma(best) .. " M") or ""
				if sameOwner and b.bestShown and b.bestShown ~= best then Kit.pop(b.best, 1.3, 0.25) end
				b.bestShown = best
			end
			-- a new title rattles in like the board does
			if b.titleLine and sameOwner and b.lastTitle ~= nil and b.lastTitle ~= (info.title or "") then
				task.spawn(function()
					local label = b.titleLine
					for _ = 1, 5 do
						label.TextTransparency = 0.6
						task.wait(0.04)
						label.TextTransparency = 0
						task.wait(0.03)
					end
				end)
			end
			b.lastTitle = info.title or ""
			b.displayName = info.name
			b.name.Text = string.upper(info.name)
			b.name.TextColor3 = Color3.fromRGB(236, 240, 248)
			b.sub.Text = "@" .. (info.user or "?")
			local titleId = (type(info.title) == "string" and info.title ~= "") and info.title or nil
			if b.titleLine then
				UI.applyTitle(b.titleLine, titleId)
				b.sub.Visible = titleId == nil
			end
			b.pill.Visible = true
			b.statusText.Text = st.text
			b.statusText.TextColor3 = st.color
			b.dot.BackgroundColor3 = st.color
			if b.ring then b.ring.ImageColor3 = st.color end

			local lvl = info.prestige or 0
			b.pres.Visible = lvl > 0
			b.pres.Text = "P" .. lvl

			-- the tab only exists while there is something to watch, and never
			-- over your own plot
			b.tab.Visible = (info.status == "attempt") and info.userId ~= self.myUserId

			if b.userId ~= info.userId then
				b.userId = info.userId
				b.head.Image = ""
				b.placeholder.Visible = true
				task.spawn(function()
					local url = thumbnailFor(info.userId)
					if url and b.userId == info.userId then
						b.head.Image = url
						b.placeholder.Visible = false
					end
				end)
			end
		else
			b.info = nil
			b.bestShown = nil
			b.honkCount = nil
			b.lastTitle = nil
			if b.rig then b.rig.Text = "" end
			if b.best then b.best.Text = "" end
			b.userId = nil
			b.displayName = nil
			b.head.Image = ""
			b.placeholder.Visible = true
			b.name.Text = "PLOT " .. index
			b.name.TextColor3 = Color3.fromRGB(150, 156, 170)
			b.sub.Text = "free yard · press E on the pad"
			b.sub.Visible = true
			if b.titleLine then UI.applyTitle(b.titleLine, nil) end
			b.pill.Visible = false
			b.pres.Visible = false
			b.tab.Visible = false
			if b.ring then b.ring.ImageColor3 = Color3.fromRGB(110, 116, 130) end
		end
	end
end

-- (honks are gone; kept so older callers don't break)
function PlotSigns:honked(_index: number, _count: number) end

-- hidden while you are mid-run, so the sky is not full of other people's UI
function PlotSigns:setVisible(v: boolean)
	for _, b in pairs(self.boards) do
		b.gui.Enabled = v
	end
end

return PlotSigns
