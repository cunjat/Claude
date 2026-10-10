--!strict
-- TYRE CANNON :: Hub2
-- The yard's always-on layer, kept to what you need (after Anime Expeditions' lobby HUD):
--   top left      cash and keys as counters with their icons (they count up when they change)
--   left side     the menu as square tiles: Plot, Tyres, Crates, Zones, Shop
--   top right     Events (a small tab), and under it the Workbench and Settings tiles
--   top centre    nothing until something needs you (HubExtras puts the Heat's 30 second notice here)
--   bottom        the Launch button (the one tap that plays), with the zone the run starts in
--   pop-ups       server announcements for big pulls, the while-you-were-away card
--   Hub2.new(gui, remotes, actions) -> hub ; hub:setProfile(p) ; hub:setVisible(on)
-- A badge on Plot says an upgrade is within reach.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local C = Kit.C

local Hub2 = {}
Hub2.__index = Hub2

-- a small round badge on a tile's corner (an upgrade you can afford, an event that's on)
local function badge(tile, color: Color3, text: string): Frame
	local b = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = color,
		Visible = false, ZIndex = 9, Parent = tile.root,
	}, { UI.corner(12) })
	UI.mk("UIStroke", { Color = C.ink, Thickness = 2.5, Parent = b })
	local t = Kit.text(text, 16, C.white, 1.5)
	t.Size = UDim2.fromScale(1, 1)
	t.ZIndex = 10
	t.Parent = b
	return b
end

function Hub2.new(gui: ScreenGui, remotes: Instance, actions)
	local self = setmetatable({}, Hub2)
	self.gui = gui
	self.R = remotes
	self.actions = actions
	local root = UI.mk("Frame", { Name = "Hub2", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20, Parent = gui })
	self.root = root

	-- money
	local money = UI.mk("Frame", { Position = UDim2.fromOffset(52, 70), Size = UDim2.fromOffset(240, 110), BackgroundTransparency = 1, Parent = root })
	UI.autoScale(money, 1280, 760)
	local ch, cl = Kit.chip(Kit.Icon.cash, nil, 210)
	ch.Parent = money
	self.cashText = cl
	self.cashBox = ch
	local kh, kl = Kit.chip(Kit.Icon.key, nil, 150)
	kh.Position = UDim2.fromOffset(0, 58)
	kh.Parent = money
	self.keyText = kl
	self.keyBox = kh

	-- the side menu: where you go
	local side = UI.mk("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 30, 0.6, 0), Size = UDim2.fromOffset(220, 360), BackgroundTransparency = 1, Parent = root })
	UI.autoScale(side, 1280, 760)
	local items = {
		{ "Plot", Kit.Icon.plot, C.accent, actions.plot }, { "Tyres", Kit.Icon.tyre, C.green, actions.tyres },
		{ "Crates", Kit.Icon.crate, C.purple, actions.crates }, { "Zones", Kit.Icon.zones, C.teal, actions.zones },
		{ "Shop", Kit.Icon.shop, C.pink, actions.shop, false },
	}
	self.dock = {}
	self.side = side
	for i, it in ipairs(items) do
		local hk = if it[5] == false then nil else string.sub(it[1], 1, 1)
		local b = Kit.tile(it[2], it[1], it[3], 96, hk)
		b.root.Position = UDim2.fromOffset(((i - 1) % 2) * 110, ((i - 1) // 2) * 118)
		b.root.Parent = side
		b.onClick = function() if it[4] then it[4]() end end
		self.dock[string.upper(it[1])] = b
		Kit.appear(b.root, 0.05 * i, 14)
	end
	-- the Shop's icon is gone (it didn't look right): its name sits in the middle of the tile instead
	do
		local shopHolder = self.dock.SHOP.root:FindFirstChild("Holder")
		local shopIcon = shopHolder and shopHolder:FindFirstChild("Icon") :: ImageLabel?
		if shopIcon then shopIcon.Image = "" end
		local l = self.dock.SHOP.label
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, 0.5)
		l.Size = UDim2.new(1, -8, 0, 30)
		Kit.fit(l, 26)
	end
	self.plotBadge = badge(self.dock.PLOT, C.green, "!")

	-- the corner: the Events tab, and under it the Workbench and Settings
	local corner = UI.mk("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 66), Size = UDim2.fromOffset(176, 130), BackgroundTransparency = 1, Parent = root })
	UI.autoScale(corner, 1280, 760)
	self.corner = corner
	local events = Kit.tab("Events", UDim2.fromOffset(176, 36), false)
	events.root.Position = UDim2.fromOffset(0, 0)
	events.root.Parent = corner
	-- the flag rides on the tab's face (so it lifts with it on hover), on a pole at its left
	local evHolder = events.root:FindFirstChild("Holder") :: Frame
	local evIcon = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.2, 0.9), Position = UDim2.new(0, 14, 0.5, 14), Size = UDim2.fromOffset(math.floor(40 * Kit.IconScale), math.floor(40 * Kit.IconScale)),
		BackgroundTransparency = 1, Image = Kit.Icon.event, ZIndex = 8, Parent = evHolder,
	})
	evIcon.Name = "EventIcon"
	-- the label leaves room for the flag and carries the countdown
	events.label.Position = UDim2.new(0.5, 14, 0.5, -1)
	events.label.Size = UDim2.new(1, -56, 1, -12)
	self.eventsTab = events
	self.eventFlag = evIcon
	-- the flag waves: a few flaps on hover, one big flap on a click, and all the time while an event's on
	local waveUntil = 0
	events.root.MouseEnter:Connect(function() waveUntil = math.max(waveUntil, os.clock() + 0.9) end)
	events.onClick = function()
		waveUntil = math.max(waveUntil, os.clock() + 0.6)
		Kit.pop(evIcon, 1.5, 0.3)
		if actions.events then actions.events() end
	end
	game:GetService("RunService").RenderStepped:Connect(function()
		if not root.Visible then return end
		local t = os.clock()
		if self.eventOn or t < waveUntil then
			evIcon.Rotation = math.sin(t * 9) * 12
		elseif evIcon.Rotation ~= 0 then
			evIcon.Rotation *= 0.8
			if math.abs(evIcon.Rotation) < 0.3 then evIcon.Rotation = 0 end
		end
	end)
	-- what the tab says: the event that's on and how long it has left, or how long until the next
	task.spawn(function()
		while root.Parent do
			local now = workspace:GetServerTimeNow()
			local e = Game.eventAt(math.floor(now))
			local function mmss(s: number): string
				s = math.max(0, math.floor(s))
				return ("%d:%02d"):format(s // 60, s % 60)
			end
			local on = e.on ~= nil
			if on then
				events.setText(("%s  %s"):format(e.on.name, mmss(e.ends - now)))
			else
				events.setText(("Events  %s"):format(mmss(e.nextAt - now)))
			end
			if on ~= self.eventOn then
				self.eventOn = on
				events.setColor(on and e.on.color or C.grey)
				if on then Kit.pop(evHolder, 0.85, 0.3) end
			end
			task.wait(0.5)
		end
	end)
	self.eventDot = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = C.red,
		Visible = false, ZIndex = 9, Parent = events.root,
	}, { UI.corner(7) })
	UI.mk("UIStroke", { Color = C.ink, Thickness = 2, Parent = self.eventDot })
	local bench = Kit.tile(Kit.Icon.bench, "Workbench", C.orange, 80, "B")
	bench.root.AnchorPoint = Vector2.new(1, 0)
	bench.root.Position = UDim2.new(1, -92, 0, 46)
	bench.root.Parent = corner
	bench.onClick = function() if actions.bench then actions.bench() end end
	self.dock.WORKBENCH = bench
	local settings = Kit.tile(Kit.Icon.settings, "Settings", C.blue, 80)
	settings.root.AnchorPoint = Vector2.new(1, 0)
	settings.root.Position = UDim2.new(1, 0, 0, 46)
	settings.root.Parent = corner
	settings.onClick = function() if actions.settings then actions.settings() end end
	self.dock.SETTINGS = settings

	-- hotkeys: the letter on each tile's badge opens it (not while typing, not over a panel)
	local keys = {
		P = actions.plot, T = actions.tyres, C = actions.crates, Z = actions.zones, B = actions.bench,
	}
	local names = { P = "PLOT", T = "TYRES", C = "CRATES", Z = "ZONES", B = "WORKBENCH" }
	UserInputService.InputBegan:Connect(function(io, processed)
		if processed or not root.Visible or not side.Visible then return end
		local fn = keys[io.KeyCode.Name]
		if fn then
			local b = self.dock[names[io.KeyCode.Name]]
			if b then Kit.pop(b.root:FindFirstChild("Holder") :: Frame, 0.9, 0.2) end
			fn()
		end
	end)

	-- the launch
	local dock = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(360, 120), BackgroundTransparency = 1, Parent = root })
	UI.autoScale(dock, 1280, 760)
	local launch = Kit.button("Launch", C.accent, UDim2.fromOffset(320, 84), 42)
	launch.root.AnchorPoint = Vector2.new(0.5, 0)
	launch.root.Position = UDim2.new(0.5, 0, 0, 0)
	launch.root.Parent = dock
	launch.onClick = function() if actions.launch then actions.launch() end end
	-- Enter (or a gamepad's X) launches from the hub, when no panel is in the way
	UserInputService.InputBegan:Connect(function(io, processed)
		if processed or not root.Visible or not launch.root.Visible then return end
		if io.KeyCode == Enum.KeyCode.Return or io.KeyCode == Enum.KeyCode.ButtonX then
			if actions.launch then actions.launch() end
		end
	end)
	self.launchBtn = launch
	self.launchDock = dock
	self.stopBob = Kit.bob(launch.root, 3, 3)
	self.fromText = Kit.text("", 17, C.text, 2)
	self.fromText.AnchorPoint = Vector2.new(0.5, 0)
	self.fromText.Position = UDim2.new(0.5, 0, 0, 92)
	self.fromText.Size = UDim2.fromOffset(360, 22)
	self.fromText.Parent = dock
	self:setZone("backroad")

	-- announcements and the offline card
	local V2 = remotes
	;(V2 :: any).Announce.OnClientEvent:Connect(function(d) self:announce(d) end)
	;(V2 :: any).Offline.OnClientEvent:Connect(function(d) self:offline(d) end)
	return self
end

-- the zone the next run starts in, shown under Launch
function Hub2:setZone(id: string)
	local z = Game.ZonesById[id]
	self.fromText.Text = z and ("From the <font color=\"#E2B86A\">%s</font>"):format(z.name) or ""
end

function Hub2:setVisible(on: boolean)
	self.root.Visible = on
end

-- the Events tab's red dot: something's on
function Hub2:setEventLive(on: boolean)
	self.eventDot.Visible = on
end

function Hub2:setProfile(p)
	local prevCash, prevKeys = self.cash, self.keys
	self.profile = p
	if not p or not p.v2 then return end
	local v = p.v2
	self.cash, self.keys = p.credits, v.keys
	if prevCash and prevCash ~= p.credits then
		Kit.countUp(self.cashText, prevCash, p.credits, 0.5, function(x) return "$" .. Game.short(x) end)
		if p.credits > prevCash then Kit.pop(self.cashBox, 0.8, 0.3) end
	else
		self.cashText.Text = "$" .. Game.short(p.credits)
	end
	self.keyText.Text = tostring(v.keys)
	if prevKeys and v.keys > prevKeys then Kit.pop(self.keyBox, 0.6, 0.3) end
	-- the Crates tile shows the crate of the furthest zone you've unlocked
	do
		local best = "backroad"
		for _, z in ipairs(Game.Zones) do
			if v.zones and v.zones[z.id] then best = z.id end
		end
		local holder = self.dock.CRATES and self.dock.CRATES.root:FindFirstChild("Holder")
		local icon = holder and holder:FindFirstChild("Icon") :: ImageLabel?
		local img = (Kit.Icon :: any)["crate_" .. best] or Kit.Icon.crate
		if icon and icon.Image ~= img then
			icon.Image = img
			if self.crateZone then Kit.pop(icon, 0.6, 0.3) end
		end
		self.crateZone = best
	end
	-- the Plot's badge: some upgrade (or the overhaul) is within reach of your cash
	local can = Game.canUpgradePlot(v, p.credits)
	if not can then
		for _, m in ipairs(Game.Machines) do
			local lvl = v.mach[m.id] or 0
			if m.gain > 0 and lvl < Game.maxLevel(m.id) and p.credits >= Game.machinePrice(m.id, lvl, v.tier) then
				can = true
				break
			end
		end
	end
	if can and not self.plotBadge.Visible then Kit.pop(self.plotBadge, 0.3) end
	self.plotBadge.Visible = can
	-- a brand-new player: point at LAUNCH
	if not v.started and not self.nudged then
		self.nudged = true
		task.delay(1.5, function()
			if self.root.Visible then
				Kit.callout(self.gui, "Tap Launch!", C.yellow, UDim2.new(0.5, 0, 1, -220), 50)
			end
		end)
	end
end

function Hub2:announce(d)
	if type(d) ~= "table" then return end
	local t = Game.TyresById[d.tyre]
	local r = Game.RaritiesById[d.rarity]
	if not t or not r then return end
	local banner = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -120), Size = UDim2.fromOffset(640, 70), BackgroundTransparency = 1, ZIndex = 80, Parent = self.gui })
	UI.autoScale(banner, 1280, 760)
	local h, f = Kit.card(UDim2.fromScale(1, 1), C.cream, 16, 6)
	h.Parent = banner
	local fr = f:FindFirstChild("Frame")
	local edge = fr and fr:FindFirstChildOfClass("UIStroke")
	if edge then edge.Color = r.color end
	local who = d.userId == Players.LocalPlayer.UserId and "You" or tostring(d.name)
	local hex = r.color:ToHex()
	local l = Kit.text(("%s pulled a <font color=\"#%s\">%s %s</font>!"):format(who, hex, r.id, t.name), 26, C.white, 2)
	l.Size = UDim2.fromScale(1, 1)
	l.ZIndex = 3
	l.Parent = f
	Kit.tween(banner, 0.4, { Position = UDim2.new(0.5, 0, 0, 130) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(4, function()
		Kit.tween(banner, 0.3, { Position = UDim2.new(0.5, 0, 0, -120) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.35, function() banner:Destroy() end)
	end)
end

function Hub2:offline(d)
	if type(d) ~= "table" then return end
	local box = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(460, 260), BackgroundTransparency = 1, ZIndex = 70, Parent = self.gui })
	UI.autoScale(box, 1280, 760)
	Kit.dim(self.gui, box, true)
	local h, f = Kit.card(UDim2.fromScale(1, 1), C.cream, 20, 8)
	h.Parent = box
	Kit.header(f, "While You Were Away", C.accent, 50)
	local hrs = math.floor((d.seconds or 0) / 3600)
	local mins = math.floor(((d.seconds or 0) % 3600) / 60)
	local sub = Kit.text(("Your compressor ran for %s"):format(hrs > 0 and ("%dh %dm"):format(hrs, mins) or ("%d min"):format(mins)), 18, C.muted, 1.5, Kit.Body)
	sub.Position = UDim2.fromOffset(0, 50)
	sub.Size = UDim2.new(1, 0, 0, 22)
	sub.ZIndex = 4
	sub.Parent = f
	local amt = Kit.text("$0", 54, C.gold, 2.5)
	amt.Position = UDim2.fromOffset(0, 84)
	amt.Size = UDim2.new(1, 0, 0, 64)
	amt.ZIndex = 4
	amt.Parent = f
	Kit.pop(box, 0.6, 0.35)
	task.delay(0.3, function() Kit.countUp(amt, 0, d.cash or 0, 1.0, function(x) return "+$" .. Game.short(x) end) end)
	local ok = Kit.button("Collect", C.green, UDim2.fromOffset(220, 58), 25)
	ok.root.AnchorPoint = Vector2.new(0.5, 1)
	ok.root.Position = UDim2.new(0.5, 0, 1, -14)
	ok.root.ZIndex = 5
	ok.root.Parent = f
	ok.onClick = function()
		Kit.dim(self.gui, box, false)
		Kit.vanish(box, 0.18, function() box:Destroy() end)
	end
end

return Hub2
