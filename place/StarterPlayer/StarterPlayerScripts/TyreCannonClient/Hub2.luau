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
local RunService = game:GetService("RunService")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Sound = require(script.Parent.Sound)
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
	UI.autoScale(money, 1280, 760, true)
	local ch, cl = Kit.chip(Kit.Icon.cash, nil, 210)
	ch.Parent = money
	-- (2026-10-16) the cash is the number that matters most: a touch bigger than the keys
	UI.mk("UIScale", { Scale = 1.12, Parent = ch })
	self.cashText = cl
	self.cashBox = ch
	local kh, kl = Kit.chip(Kit.Icon.key, nil, 150)
	kh.Position = UDim2.fromOffset(0, 62)
	kh.Parent = money
	self.keyText = kl
	self.keyBox = kh
	-- the login reward, while it's waiting to be claimed (closing its card doesn't lose it)
	local daily = Kit.button("Daily Reward", C.yellow, UDim2.fromOffset(150, 34), 15)
	daily.root.Position = UDim2.fromOffset(0, 116)
	daily.root.Visible = false
	daily.root.Parent = money
	daily.onClick = function() if actions.daily then actions.daily() end end
	self.dailyBtn = daily
	-- the level medal (Server/Career) hangs on its ribbon from the bars' right end, beside the keys: the level on its face,
	-- the XP to the next under it. It's a pendulum: it swings when you level up, nudges when you
	-- point at it, and jingles when you press it (which opens the Profile: level, prestige, titles).
	do
		-- the render (icons7 medal): the ribbon's top at 6% down the image, the disc's middle at 62%,
		-- the disc 49% of the image wide
		local Q = 114
		local TOP, MID = 0.0625, 0.623
		-- the swing turns about its middle, which is the ribbon's top: the hang point
		local swing = UI.mk("Frame", {
			Name = "LevelMedal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(182, 38),
			Size = UDim2.fromOffset(Q, 2 * Q * (1 - TOP)), BackgroundTransparency = 1, ZIndex = 0, Parent = money,
		})
		local medal = UI.mk("ImageLabel", {
			Name = "Medal", Position = UDim2.fromOffset(0, Q * (1 - TOP) - Q * TOP), Size = UDim2.fromOffset(Q, Q),
			BackgroundTransparency = 1, Image = Kit.Icon.medal, ZIndex = 0, Parent = swing,
		})
		local num = Kit.text("1", 24, C.white, 3)
		num.AnchorPoint = Vector2.new(0.5, 0.5)
		num.Position = UDim2.fromScale(0.5, MID)
		num.Size = UDim2.fromOffset(42, 26)
		Kit.fit(num, 24, 10)
		num.ZIndex = 2
		num.Parent = medal
		-- the XP to the next level: a slim bar under the disc
		local back = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.9), Size = UDim2.fromOffset(46, 6),
			BackgroundColor3 = Color3.fromRGB(20, 20, 24), BorderSizePixel = 0, ZIndex = 2, Parent = medal }, { UI.corner(3) })
		UI.mk("UIStroke", { Color = Color3.fromRGB(14, 12, 18), Thickness = 2, Parent = back })
		local fill = UI.mk("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.gold, BorderSizePixel = 0, ZIndex = 3, Parent = back }, { UI.corner(3) })
		-- the hit box rides on the disc
		local hit = UI.mk("TextButton", {
			Name = "LevelBadge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, MID), Size = UDim2.fromScale(0.56, 0.6),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 4, Parent = medal,
		})
		hit.MouseEnter:Connect(function() self:swingMedal(if math.random() < 0.5 then -40 else 40) end)
		hit.MouseButton1Down:Connect(function() Kit.pop(medal, 0.9, 0.15) end)
		hit.Activated:Connect(function()
			self:swingMedal(130, true)
			task.delay(0.12, function() if actions.profile then actions.profile() end end)
		end)
		self.level = { root = swing, slot = medal, num = num, fill = fill }
		self.medalSwing = { a = 0, v = 0, conn = nil :: RBXScriptConnection? }
	end
	money.Size = UDim2.fromOffset(240, 150)

	-- the side menu: where you go
	local side = UI.mk("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 30, 0.6, 0), Size = UDim2.fromOffset(220, 360), BackgroundTransparency = 1, Parent = root })
	UI.autoScale(side, 1280, 760, true)
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
		-- an even grid (the same gap across and down); a last tile on its own sits centred under the pair
		local col = if i == #items and i % 2 == 1 then 0.5 else (i - 1) % 2
		b.root.Position = UDim2.fromOffset(col * 110, ((i - 1) // 2) * 110)
		b.root.Parent = side
		b.onClick = function() if it[4] then it[4]() end end
		self.dock[string.upper(it[1])] = b
		Kit.appear(b.root, 0.05 * i, 14)
		-- alive while you stand there: a shine crosses the tile now and then (the icons hold still),
		-- and a red badge says when there's something to do in it
		local holder = b.root:FindFirstChild("Holder")
		local face = holder and holder:FindFirstChildWhichIsA("ImageLabel")
		if face then Kit.flow(face, "drift", 0.24, 5.5 + i * 0.9) end
		self.alerts = self.alerts or {}
		self.alerts[string.upper(it[1])] = Kit.alert(b.root, 25)
	end
	self.plotBadge = badge(self.dock.PLOT, C.green, "!")
	-- (2026-10-16, the phone pass) a phone on its side has width to spare and little height: the
	-- tiles go in one row along the bottom left there, clear of the counters; elsewhere the grid
	local function sideLayout()
		local phone = UI.isPhone()
		for i, it in ipairs(items) do
			local b = self.dock[string.upper(it[1])]
			if phone then
				b.root.Position = UDim2.fromOffset((i - 1) * 104, 0)
			else
				local col = if i == #items and i % 2 == 1 then 0.5 else (i - 1) % 2
				b.root.Position = UDim2.fromOffset(col * 110, ((i - 1) // 2) * 110)
			end
		end
		if phone then
			side.Size = UDim2.fromOffset(#items * 104, 100)
			side.AnchorPoint = Vector2.new(0, 1)
			side.Position = UDim2.new(0, 14, 1, -8)
		else
			side.Size = UDim2.fromOffset(220, 360)
			side.AnchorPoint = Vector2.new(0, 0.5)
			side.Position = UDim2.new(0, 30, 0.6, 0)
		end
	end
	sideLayout()
	-- (again once the tiles' entrance has played: it slides them to where they were made)
	task.delay(0.9, sideLayout)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(sideLayout)

	-- the corner: the Events tab, and under it the Workbench and Settings
	-- (2026-10-16) up toward the top and a size bigger
	local corner = UI.mk("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 14), Size = UDim2.fromOffset(204, 152), BackgroundTransparency = 1, Parent = root })
	UI.autoScale(corner, 1280, 760, true)
	self.corner = corner
	local events = Kit.tab("Events", UDim2.fromOffset(204, 42), false)
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
	local bench = Kit.tile(Kit.Icon.bench, "Workbench", C.orange, 94, "B")
	bench.root.AnchorPoint = Vector2.new(1, 0)
	bench.root.Position = UDim2.new(1, -108, 0, 54)
	bench.root.Parent = corner
	bench.onClick = function() if actions.bench then actions.bench() end end
	self.dock.WORKBENCH = bench
	local settings = Kit.tile(Kit.Icon.settings, "Settings", C.blue, 94)
	settings.root.AnchorPoint = Vector2.new(1, 0)
	settings.root.Position = UDim2.new(1, 0, 0, 54)
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
	local dock = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(360, 120), BackgroundTransparency = 1, Parent = root })
	UI.autoScale(dock, 1280, 760, true)
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
	-- the launch button breathes: it's always the next thing to do
	Kit.breathe(launch.root, 0.022, 2.6)
	self.stopBob = Kit.bob(launch.root, 3, 3)
	self.fromText = Kit.text("", 17, C.text, 2)
	self.fromText.AnchorPoint = Vector2.new(0.5, 0)
	self.fromText.Position = UDim2.new(0.5, 0, 0, 92)
	self.fromText.Size = UDim2.fromOffset(360, 22)
	self.fromText.Parent = dock
	self:setZone("backroad")

	-- the auto-cannon, beside Launch: your yard's cannon fires on its own every half minute while
	-- you're here (Game.AutoCannon); a bar runs down to the next shot, what each shot pays is on it,
	-- and it jumps when one goes. Press it to hear what it is.
	do
		local A = Game.AutoCannon
		local card = UI.mk("TextButton", {
			Name = "AutoCannon", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 218, 1, -24), Size = UDim2.fromOffset(236, 64),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = root,
		})
		UI.autoScale(card, 1280, 760)
		local body = UI.mk("Frame", { Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = card })
		Kit.slice("counter", nil, body, 1, 0.5)
		local icon = UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(30, 30), Size = UDim2.fromOffset(58, 58), BackgroundTransparency = 1,
			Image = Kit.Icon.cannon, ZIndex = 4, Parent = body,
		})
		local title = Kit.text("AUTO-CANNON", 14, C.white, 2)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Position = UDim2.fromOffset(62, 7)
		title.Size = UDim2.fromOffset(110, 17)
		Kit.fit(title, 14, 8)
		title.ZIndex = 4
		title.Parent = body
		local pay = Kit.text("", 15, C.gold, 2)
		pay.AnchorPoint = Vector2.new(1, 0)
		pay.TextXAlignment = Enum.TextXAlignment.Right
		pay.Position = UDim2.new(1, -12, 0, 6)
		pay.Size = UDim2.fromOffset(80, 18)
		Kit.fit(pay, 15, 8)
		pay.ZIndex = 4
		pay.Parent = body
		local track, fill = Kit.bar(150, 14, C.gold, "off")
		track.Position = UDim2.fromOffset(62, 28)
		track.ZIndex = 4
		track.Parent = body
		local left = Kit.text("", 12, C.white, 1.5, Kit.Body)
		left.AnchorPoint = Vector2.new(1, 0)
		left.TextXAlignment = Enum.TextXAlignment.Right
		left.Position = UDim2.new(1, -10, 0, 27)
		left.Size = UDim2.fromOffset(26, 16)
		left.ZIndex = 4
		left.Parent = body
		local note = Kit.text("", 11, C.muted, 1.5, Kit.Body)
		note.TextXAlignment = Enum.TextXAlignment.Left
		note.Position = UDim2.fromOffset(62, 45)
		note.Size = UDim2.fromOffset(166, 14)
		Kit.fit(note, 11, 7)
		note.ZIndex = 4
		note.Parent = body
		card.MouseEnter:Connect(function() Kit.tween(body, 0.14, { Position = UDim2.fromOffset(0, -3) }, Enum.EasingStyle.Back) end)
		card.MouseLeave:Connect(function() Kit.tween(body, 0.14, { Position = UDim2.fromOffset(0, 0) }) end)
		-- (2026-10-16) a small card that stays until you close it: what it pays, what raises it, and
		-- what it earned while you were away (the callout went before you could read it)
		card.Activated:Connect(function() self:autoInfo() end)
		self.auto = { card = card, body = body, icon = icon, pay = pay, fill = fill, left = left, note = note, on = false }
		RunService.RenderStepped:Connect(function()
			local au = self.auto
			if not au.on or not card.Visible or not root.Visible then return end
			local at = workspace:GetAttribute("AutoCannonAt")
			if typeof(at) ~= "number" then return end
			local rest = math.max(0, at - workspace:GetServerTimeNow())
			fill.Size = UDim2.fromScale(math.clamp(1 - rest / A.Every, 0, 1), 1)
			left.Text = ("%ds"):format(math.ceil(rest))
		end)
	end

	-- announcements and the offline card
	local V2 = remotes
	;(V2 :: any).Announce.OnClientEvent:Connect(function(d) self:announce(d) end)
	;(V2 :: any).Offline.OnClientEvent:Connect(function(d) self:offline(d) end)
	task.spawn(function()
		local afk = V2:WaitForChild("AfkReport", 30) :: RemoteEvent?
		if afk then afk.OnClientEvent:Connect(function(d) self:afkReport(d) end) end
	end)
	return self
end

-- the zone the next run starts in, shown under Launch
function Hub2:setZone(id: string)
	local z = Game.ZonesById[id]
	self.fromText.Text = z and ("From the <font color=\"#E2B86A\">%s</font>"):format(z.name) or ""
end

-- the auto-cannon's state from the profile: locked until your first run, then what a shot pays
function Hub2:setAuto(v)
	local au = self.auto
	if not au then return end
	local A = Game.AutoCannon
	local live = v and (v.runs or 0) > 0 and (v.rate or 0) > 0
	au.on = live
	if live then
		local share = (v.passes and v.passes.autolaunch) and A.PassShare or A.Share
		share = math.min(A.MaxShare, share * Game.styleBonus(v.style or 0) * (1 + 0.2 * Game.perkLv(v, "idle")))
		au.pay.Text = "+$" .. Game.short(math.floor(v.rate / 60 * A.Every * share))
		au.note.Text = "Fires on its own while you're here"
		au.icon.ImageTransparency = 0
	else
		au.pay.Text = ""
		au.left.Text = ""
		au.fill.Size = UDim2.fromScale(0, 1)
		au.note.Text = "Starts after your first run"
		au.icon.ImageTransparency = 0.5
	end
end

-- a shot just went: the card jumps, the cannon kicks, the pay rises off it
function Hub2:autoFired(cash: number)
	local au = self.auto
	if not au or not self.root.Visible then return end
	Kit.pop(au.body, 0.85, 0.3)
	au.icon.Rotation = -14
	Kit.tween(au.icon, 0.4, { Rotation = 0 }, Enum.EasingStyle.Back)
	local f = Kit.text("+$" .. Game.short(cash), 22, C.gold, 2.5)
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 0, 0)
	f.Size = UDim2.fromOffset(160, 26)
	f.ZIndex = 8
	f.Parent = au.card
	Kit.tween(f, 1.2, { Position = UDim2.new(0.5, 0, 0, -46), TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local st = f:FindFirstChildOfClass("UIStroke")
	if st then Kit.tween(st, 1.2, { Transparency = 1 }) end
	task.delay(1.25, function() f:Destroy() end)
end

function Hub2:setVisible(on: boolean)
	self.root.Visible = on
end

-- the hub's entrance after the loading screen: each piece slides in from the edge it sits on, one
-- after another, instead of the whole lot appearing at once
function Hub2:enter()
	local root = self.root
	root.Visible = true
	local pieces = {}
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible then table.insert(pieces, c) end
	end
	-- (left to right, top to bottom, so it ripples across)
	table.sort(pieces, function(a, b)
		return a.AbsolutePosition.X + a.AbsolutePosition.Y * 0.5 < b.AbsolutePosition.X + b.AbsolutePosition.Y * 0.5
	end)
	self.restAt = self.restAt or {}
	for i, c in ipairs(pieces) do
		local rest = self.restAt[c] or c.Position
		self.restAt[c] = rest
		local x, y = rest.X.Scale, rest.Y.Scale
		local from
		if x < 0.3 then
			from = rest + UDim2.fromOffset(-300, 0)
		elseif x > 0.7 then
			from = rest + UDim2.fromOffset(300, 0)
		elseif y > 0.5 then
			from = rest + UDim2.fromOffset(0, 220)
		else
			from = rest + UDim2.fromOffset(0, -220)
		end
		c.Position = from
		task.delay(0.05 + (i - 1) * 0.045, function()
			Kit.tween(c, 0.5, { Position = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end)
	end
end

-- the Events tab's red dot: something's on
function Hub2:setEventLive(on: boolean)
	self.eventDot.Visible = on
end

-- the red badges: what you could do right now in each place
-- the medal on its ribbon: a damped pendulum; `kick` is a push in degrees a second
function Hub2:swingMedal(kick: number, jingle: boolean?)
	local m = self.medalSwing
	if not m then return end
	m.v += kick
	if jingle then Sound.play("medal", { volume = 0.7, pitch = 0.95 + math.random() * 0.15, length = 1.2 }) end
	if m.conn then return end
	local swing = self.level.root
	m.conn = game:GetService("RunService").RenderStepped:Connect(function(dt)
		dt = math.min(dt, 1 / 30)
		-- stiff enough to swing about once a second, damped to settle in two or three
		m.v += (-58 * m.a - 2.4 * m.v) * dt
		m.a = math.clamp(m.a + m.v * dt, -55, 55)
		swing.Rotation = m.a
		if math.abs(m.a) < 0.05 and math.abs(m.v) < 0.5 then
			m.a, m.v = 0, 0
			swing.Rotation = 0
			m.conn:Disconnect()
			m.conn = nil
		end
	end)
end

function Hub2:refreshAlerts(p)
	local v = p.v2
	local A = self.alerts
	if not (A and v) then return end
	-- the Plot: a machine you can afford, or the stage-up is ready
	local plot = Game.canUpgradePlot(v, p.credits)
	if not plot then
		for _, m in ipairs(Game.Machines) do
			local lvl = v.mach[m.id] or 0
			if lvl < Game.maxLevel(m.id) and p.credits >= Game.machinePrice(m.id, lvl, v.tier, v) then
				plot = true
				break
			end
		end
	end
	-- Crates: one you can open, with cash or keys
	local crate = false
	for _, z in ipairs(Game.Zones) do
		if v.zones[z.id] and (p.credits >= Game.crateCash(z.id, v.tier, v) or v.keys >= Game.cratePrice(z.id)) then
			crate = true
			break
		end
	end
	-- Tyres: enough copies of something to fuse
	local fuse = false
	local counts = {}
	for _, t in ipairs(v.inv) do
		if not t.fav and (t.forge or 0) < 3 then
			local k = t.id .. ":" .. (t.forge or 0)
			counts[k] = (counts[k] or 0) + 1
			if counts[k] >= Game.fuseNeed(t.id) then fuse = true end
		end
	end
	local _ = plot
	if A.CRATES then A.CRATES(crate) end
	if A.TYRES then A.TYRES(fuse) end
end

function Hub2:setProfile(p)
	local prevCash, prevKeys = self.cash, self.keys
	self.profile = p
	if not p or not p.v2 then return end
	pcall(function() self:refreshAlerts(p) end)
	local v = p.v2
	pcall(function() self:setAuto(v) end)
	self.cash, self.keys = p.credits, v.keys
	if prevCash and prevCash ~= p.credits then
		Kit.countUp(self.cashText, prevCash, p.credits, 0.5, function(x) return "$" .. Game.short(x) end)
		if p.credits > prevCash then Kit.pop(self.cashBox, 0.8, 0.3) end
	else
		self.cashText.Text = "$" .. Game.short(p.credits)
	end
	self.keyText.Text = tostring(v.keys)
	if prevKeys and v.keys > prevKeys then Kit.pop(self.keyBox, 0.6, 0.3) end
	local ready = v.daily ~= nil and v.daily.last ~= Game.utcDay(math.floor(workspace:GetServerTimeNow()))
	if ready and not self.dailyBtn.root.Visible then Kit.pop(self.dailyBtn.root, 0.7, 0.3) end
	self.dailyBtn.root.Visible = ready
	-- the level badge
	local cr = v.career
	if cr and self.level then
		local L = self.level
		local band = Game.levelBand(cr.level)
		if self.shownLevel and cr.level > self.shownLevel then
			-- a level up: the medal swings hard, flashes up and jingles
			self:swingMedal(220, true)
			Kit.pop(L.slot, 0.6, 0.35)
		elseif self.shownXp and cr.xp > self.shownXp then
			self:swingMedal(35)
		end
		self.shownXp = cr.xp
		self.shownLevel = cr.level
		L.num.Text = tostring(cr.level)
		L.fill.BackgroundColor3 = band.color
		L.fill.Size = UDim2.fromScale(math.clamp(cr.xp / Game.xpToNext(cr.level), 0, 1), 1)
		-- (the medal keeps its gold; the rank shows in the XP bar's colour)
	end
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
			if m.gain > 0 and lvl < Game.maxLevel(m.id) and p.credits >= Game.machinePrice(m.id, lvl, v.tier, v) then
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

-- back from AFK: what the yard's auto-cannon did while you were away
function Hub2:afkReport(d)
	if type(d) ~= "table" or (d.shots or 0) <= 0 then return end
	if self.afkBox and self.afkBox.Parent then self.afkBox:Destroy() end
	local box = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(480, 264), BackgroundTransparency = 1, ZIndex = 70, Parent = self.gui })
	self.afkBox = box
	UI.autoScale(box, 1280, 760)
	Kit.dim(self.gui, box, true)
	local h, f = Kit.card(UDim2.fromScale(1, 1), C.cream, 20, 8)
	h.Parent = box
	Kit.header(f, "Welcome Back", C.accent, 50)
	local secs = d.seconds or 0
	local hrs, mins = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
	local away = if hrs > 0 then ("%dh %dm"):format(hrs, mins) else ("%d min"):format(math.max(1, mins))
	local sub = Kit.text(("You were away %s. Your yard's cannon kept firing."):format(away), 18, C.muted, 1.5, Kit.Body)
	sub.Position = UDim2.fromOffset(0, 50)
	sub.Size = UDim2.new(1, 0, 0, 22)
	sub.ZIndex = 4
	sub.Parent = f
	local icon = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -150, 0, 118), Size = UDim2.fromOffset(78, 78),
		BackgroundTransparency = 1, Image = Kit.Icon.cannon, ZIndex = 5, Parent = f,
	})
	local amt = Kit.text("+$0", 54, C.gold, 2.5)
	amt.Position = UDim2.fromOffset(60, 84)
	amt.Size = UDim2.new(1, -80, 0, 64)
	amt.ZIndex = 4
	amt.Parent = f
	local shots = Kit.text(("%d shots fired   ·   balance $%s"):format(d.shots, Game.short(d.balance or 0)), 17, C.white, 1.5, Kit.Body)
	shots.Position = UDim2.fromOffset(0, 154)
	shots.Size = UDim2.new(1, 0, 0, 22)
	shots.ZIndex = 4
	shots.Parent = f
	Kit.pop(box, 0.6, 0.35)
	icon.Rotation = -14
	Kit.tween(icon, 0.5, { Rotation = 0 }, Enum.EasingStyle.Back)
	Sound.play("medal", { volume = 0.5, pitch = 1.1, length = 1.2 })
	task.delay(0.3, function() Kit.countUp(amt, 0, d.cash or 0, 1.0, function(x) return "+$" .. Game.short(x) end) end)
	local ok = Kit.button("Nice", C.green, UDim2.fromOffset(220, 58), 25)
	ok.root.AnchorPoint = Vector2.new(0.5, 1)
	ok.root.Position = UDim2.new(0.5, 0, 1, -14)
	ok.root.ZIndex = 5
	ok.root.Parent = f
	ok.onClick = function()
		Kit.dim(self.gui, box, false)
		Kit.vanish(box, 0.18, function() box:Destroy() end)
	end
end

-- the Auto-cannon card: in the game it pays a share of your run earnings every shot; away, a much
-- smaller share (so being here pays). What raises both, and the last time away.
function Hub2:autoInfo()
	if self.autoBox then
		self.autoBox:Destroy()
		self.autoBox = nil
		return
	end
	-- (not over the tutorial's welcome choice: that screen is answered first)
	local sg = self.gui:FindFirstAncestorWhichIsA("ScreenGui") or self.gui
	if sg:FindFirstChild("TutorialChoice", true) then return end
	local A, O = Game.AutoCannon, Game.Offline
	local p = self.profile
	local v = p and p.v2
	local pass = v and v.passes and v.passes.autolaunch
	local share = if pass then A.PassShare else A.Share
	local style = Game.styleBonus(v and v.style or 0)
	local idle = 1 + 0.2 * Game.perkLv(v, "idle")
	local rate = v and v.rate or 0
	local shot = math.floor(rate / 60 * A.Every * share * style * idle)
	local box = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 330, 1, -112), Size = UDim2.fromOffset(400, 300), BackgroundTransparency = 1, ZIndex = 70, Parent = self.gui })
	UI.autoScale(box, 1280, 760, true)
	self.autoBox = box
	Kit.slice("panel_body", nil, box, 70, 0.4)
	Kit.slice("panel_ring", C.gold, box, 71, 0.4)
	local x = Kit.close(36)
	x.root.AnchorPoint = Vector2.new(1, 0)
	x.root.Position = UDim2.new(1, 8, 0, -8)
	x.root.ZIndex = 76
	x.root.Parent = box
	x.onClick = function() self:autoInfo() end
	local function line(text: string, y: number, size: number, color: Color3, bold: boolean?)
		local l = Kit.text(text, size, color, 1.5, if bold then nil else Kit.Body)
		l.RichText = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Position = UDim2.fromOffset(20, y)
		l.Size = UDim2.fromOffset(360, size + 6)
		Kit.fit(l, size, 9)
		l.ZIndex = 74
		l.Parent = box
		return l
	end
	line("AUTO-CANNON", 14, 22, C.gold, true)
	line(("Fires every <b>%ds</b> while you're here: each shot <b>$%s</b>"):format(A.Every, Game.short(shot)), 48, 16, C.white)
	line(("Pays <b>%d%%</b> of what your runs earn%s"):format(math.floor(share * 100 + 0.5), if pass then " (Auto Launch)" else ""), 74, 15, C.text)
	line("WHAT RAISES IT", 108, 15, C.gold, true)
	line(("Your runs: further runs earn more  ·  rate $%s/min"):format(Game.short(rate)), 132, 14, C.text)
	line(("Yard Style: +%d%%  (decor in Edit Yard)"):format(math.floor((style - 1) * 100 + 0.5)), 154, 14, C.text)
	line(("Idle Hands perk: +%d%%"):format(math.floor((idle - 1) * 100 + 0.5)), 176, 14, C.text)
	line(("Auto Launch pass: %d%% a shot"):format(math.floor(A.PassShare * 100 + 0.5)), 198, 14, if pass then C.green else C.muted)
	line("WHILE YOU'RE AWAY", 228, 15, C.gold, true)
	local away = self.lastOffline
	line(("Only <b>%d%%</b>, up to %dh: being here pays %d times more%s"):format(math.floor(O.Share * 100 + 0.5), O.CapHours, math.floor(share / O.Share + 0.5),
		if away and away.cash then ("  ·  last time $%s"):format(Game.short(away.cash)) else ""), 252, 14, C.text)
	Kit.pop(box, 0.85, 0.25)
end

function Hub2:offline(d)
	if type(d) ~= "table" then return end
	self.lastOffline = d
	local box = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(460, 260), BackgroundTransparency = 1, ZIndex = 70, Parent = self.gui })
	UI.autoScale(box, 1280, 760)
	Kit.dim(self.gui, box, true)
	local h, f = Kit.card(UDim2.fromScale(1, 1), C.cream, 20, 8)
	h.Parent = box
	Kit.header(f, "While You Were Away", C.accent, 50)
	local hrs = math.floor((d.seconds or 0) / 3600)
	local mins = math.floor(((d.seconds or 0) % 3600) / 60)
	local sub = Kit.text(("Your yard earned for %s (style %d)"):format(hrs > 0 and ("%dh %dm"):format(hrs, mins) or ("%d min"):format(mins), d.style or 0), 18, C.muted, 1.5, Kit.Body)
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
