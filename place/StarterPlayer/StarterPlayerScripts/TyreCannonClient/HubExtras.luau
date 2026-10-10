--!strict
-- TYRE CANNON :: HubExtras (v3)
-- What the hub adds around its edges to keep a server together:
--   the Heat notice    top centre, only in the last 30 seconds before a Heat starts: a card with a
--                      countdown and JOIN (this is the only thing that ever sits up there)
--   the Events panel   behind the Events tab: the Heat's clock, the server event that's on or the
--                      next one, and Server Luck
-- and the popups that go with them: the login calendar, the Heat's placings, a Server Luck shout,
-- and the Shop panel (Config.Store).
--   HubExtras.new(gui, remotes, hooks) · :setProfile(p) · :setVisible(on) · :openShop() · :openEvents()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Game = require(Modules.Game)
local Config = require(Modules.Config)
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local C = Kit.C

local HubExtras = {}
HubExtras.__index = HubExtras

local NOTICE_AT = 30        -- seconds before a Heat starts that the notice appears

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then return ("%d:%02d:%02d"):format(sec // 3600, (sec % 3600) // 60, sec % 60) end
	return ("%d:%02d"):format(sec // 60, sec % 60)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

function HubExtras.new(gui: ScreenGui, remotes: Instance, hooks: { [string]: any })
	local self = setmetatable({}, HubExtras)
	self.gui = gui
	self.R = remotes
	self.hooks = hooks or {}
	self.joined = false
	self.noticeOn = false

	-- the Heat notice: top centre, slid up out of sight until it's needed
	local root = UI.mk("Frame", {
		Name = "HubExtras", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -110), Size = UDim2.fromOffset(390, 64),
		BackgroundTransparency = 1, ZIndex = 20, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.root = root
	Kit.slice("panel_body", nil, root, 1, 0.4)
	self.noticeRing = Kit.slice("panel_ring", C.red, root, 2, 0.4)
	UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(34, 32), Size = UDim2.fromOffset(math.floor(62 * Kit.IconScale), math.floor(62 * Kit.IconScale)),
		BackgroundTransparency = 1, Image = Kit.Icon.event, ZIndex = 4, Parent = root,
	})
	self.noticeTitle = Kit.text("", 19, C.white, 2.5)
	self.noticeTitle.TextXAlignment = Enum.TextXAlignment.Left
	self.noticeTitle.Position = UDim2.fromOffset(68, 9)
	self.noticeTitle.Size = UDim2.fromOffset(200, 24)
	Kit.fit(self.noticeTitle, 19, 11)
	self.noticeTitle.ZIndex = 4
	self.noticeTitle.Parent = root
	self.noticeSub = Kit.text("", 13, C.muted, 1.5, Kit.Body)
	self.noticeSub.TextXAlignment = Enum.TextXAlignment.Left
	self.noticeSub.Position = UDim2.fromOffset(68, 35)
	self.noticeSub.Size = UDim2.fromOffset(200, 18)
	Kit.fit(self.noticeSub, 13, 9)
	self.noticeSub.ZIndex = 4
	self.noticeSub.Parent = root
	local join = Kit.button("Join", C.red, UDim2.fromOffset(92, 42), 18)
	join.root.AnchorPoint = Vector2.new(1, 0.5)
	join.root.Position = UDim2.new(1, -12, 0.5, 0)
	join.root.ZIndex = 6
	join.root.Parent = root
	join.onClick = function() self:joinHeat() end
	self.joinBtn = join
	-- close: hides it until the next Heat
	local x = Kit.close(30)
	x.root.AnchorPoint = Vector2.new(0.5, 0.5)
	x.root.Position = UDim2.new(1, 0, 0, 2)
	x.root.ZIndex = 8
	x.root.Parent = root
	x.onClick = function()
		self.dismissed = workspace:GetAttribute("HeatAt")
		self:showNotice(false)
	end

	self:buildEvents()

	local R = remotes :: any
	R.Reward.OnClientEvent:Connect(function(d) self:reward(d) end)
	local hr = remotes:WaitForChild("HeatResult", 10)
	if hr then (hr :: RemoteEvent).OnClientEvent:Connect(function(list) self:heatResult(list) end) end
	local hs = remotes:WaitForChild("HeatStart", 10)
	if hs then
		(hs :: RemoteEvent).OnClientEvent:Connect(function(d)
			self.joined = false
			if self.hooks.heatStart then self.hooks.heatStart(d) end
		end)
	end
	R.Announce.OnClientEvent:Connect(function(d)
		if type(d) == "table" and d.kind == "luck" then
			Kit.callout(gui, ("%s turned on SERVER LUCK!"):format(tostring(d.name)), C.green, UDim2.fromScale(0.5, 0.22), 40)
		end
	end)

	task.spawn(function()
		while root.Parent do
			self:tick()
			task.wait(0.25)
		end
	end)
	self:buildShop()
	return self
end

--==============================================================
-- the Events panel
--==============================================================
function HubExtras:buildEvents()
	local panel = UI.mk("Frame", { Name = "Events", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(620, 440),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = self.gui })
	UI.autoScale(panel, 1280, 760)
	local holder, face = Kit.card(UDim2.fromOffset(620, 430), C.cream)
	holder.Parent = panel
	Kit.header(face, "Events", C.red, 56)
	local close = Kit.close(52)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, 12, 0, -14)
	close.root.ZIndex = 40
	close.root.Parent = panel
	close.onClick = function() self:openEvents(false) end
	self.events = panel

	-- three rows: the Heat, the server event, Server Luck
	self.evRows = {}
	local function row(i: number, accent: Color3, icon: string)
		local f = UI.mk("Frame", { Position = UDim2.fromOffset(28, 58 + (i - 1) * 112), Size = UDim2.fromOffset(564, 100), BackgroundTransparency = 1, ZIndex = 5, Parent = face })
		Kit.slot(f, accent, 5)
		UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(52, 50), Size = UDim2.fromOffset(math.floor(88 * Kit.IconScale), math.floor(88 * Kit.IconScale)),
			BackgroundTransparency = 1, Image = icon, ZIndex = 7, Parent = f,
		})
		local title = Kit.text("", 24, C.white, 2.5)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Position = UDim2.fromOffset(108, 12)
		title.Size = UDim2.fromOffset(300, 30)
		Kit.fit(title, 24, 12)
		title.ZIndex = 7
		title.Parent = f
		local sub = Kit.text("", 15, C.muted, 1.5, Kit.Body)
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.TextYAlignment = Enum.TextYAlignment.Top
		sub.TextWrapped = true
		sub.Position = UDim2.fromOffset(108, 46)
		sub.Size = UDim2.fromOffset(300, 44)
		sub.ZIndex = 7
		sub.Parent = f
		local timer = Kit.text("", 26, C.gold, 2.5)
		timer.AnchorPoint = Vector2.new(1, 0.5)
		timer.TextXAlignment = Enum.TextXAlignment.Right
		timer.Position = UDim2.new(1, -18, 0.5, 0)
		timer.Size = UDim2.fromOffset(130, 36)
		timer.ZIndex = 7
		timer.Parent = f
		return { frame = f, title = title, sub = sub, timer = timer }
	end
	self.evRows.heat = row(1, C.red, Kit.Icon.event)
	self.evRows.event = row(2, C.orange, Kit.Icon.cannon)
	self.evRows.luck = row(3, C.green, Kit.Icon.crate)
end

function HubExtras:openEvents(on: boolean?)
	local show = on
	if show == nil then show = not self.events.Visible end
	if show then
		Kit.dim(self.gui, self.events, true)
		Kit.open(self.events)
	else
		Kit.dim(self.gui, self.events, false)
		if self.events.Visible then Kit.close_(self.events) end
	end
end

function HubExtras:isEventsOpen(): boolean
	return self.events.Visible
end

function HubExtras:setVisible(on: boolean)
	if not on then
		self:showNotice(false)
		if self.shop then self.shop.Visible = false end
		if self.events then self.events.Visible = false end
	end
	self.hubVisible = on
end

function HubExtras:setProfile(p)
	self.profile = p
	local v = p and p.v2
	if not v then return end
	-- the calendar, once a session, once the title's gone
	if not self.dailyChecked and v.runs >= 0 then
		self.dailyChecked = true
		task.spawn(function()
			local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
			while pg:GetAttribute("IntroPlaying") do task.wait(0.3) end
			task.wait(1.2)
			-- never over a launch, a run or a menu: wait until you're standing in your yard
			while self.hooks.idle and not self.hooks.idle() do task.wait(0.5) end
			if v.daily.last ~= Game.utcDay(math.floor(now())) then self:showDaily(v) end
		end)
	end
end

--==============================================================
-- the clocks
--==============================================================
-- the Heat notice slides down from the top only while a Heat is about to start
function HubExtras:showNotice(on: boolean)
	if on == self.noticeOn then return end
	self.noticeOn = on
	if on then
		Kit.tween(self.root, 0.4, { Position = UDim2.new(0.5, 0, 0, 58) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		Kit.tween(self.root, 0.3, { Position = UDim2.new(0.5, 0, 0, -110) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	end
end

function HubExtras:tick()
	local t = now()
	local e = Game.eventAt(math.floor(t))
	local phase = workspace:GetAttribute("HeatPhase") or "idle"
	local at = tonumber(workspace:GetAttribute("HeatAt")) or t
	local count = tonumber(workspace:GetAttribute("HeatCount")) or 0
	local left = at - t

	-- the notice: only in the last NOTICE_AT seconds before the race, and only in the yard
	local soon = phase == "join" and left > 0 and left <= NOTICE_AT and self.hubVisible ~= false and (self.hooks.idle == nil or self.hooks.idle())
		and (self.dismissed == nil or self.dismissed ~= workspace:GetAttribute("HeatAt"))
	if phase ~= "join" then self.joined = false end
	if soon then
		self.noticeTitle.Text = ("HEAT STARTS IN %s"):format(clock(left))
		self.noticeSub.Text = if self.joined then "You're in. Get ready." else ("%d joined"):format(count)
		self.joinBtn.setText(self.joined and "Joined" or "Join")
		self.joinBtn.setColor(self.joined and C.green or C.red)
		self.noticeRing.ImageColor3 = if self.joined then C.green else C.red
	end
	self:showNotice(soon)

	-- the Events panel
	local heat, ev, luck = self.evRows.heat, self.evRows.event, self.evRows.luck
	if phase == "join" then
		heat.title.Text = "HEAT OPEN"
		heat.sub.Text = ("%d joined. Join now and race the server."):format(count)
		heat.timer.Text = clock(left)
	elseif phase == "race" then
		heat.title.Text = "HEAT ON"
		heat.sub.Text = "Racing now. The next one opens soon."
		heat.timer.Text = ""
	else
		heat.title.Text = "NEXT HEAT"
		heat.sub.Text = "A server race, every few minutes. First, second and third are paid."
		-- (idle ends when the join window opens: the race itself starts a join window later)
		heat.timer.Text = clock(left + Game.Heats.Join)
	end
	if e.on then
		ev.title.Text = string.upper(e.on.name)
		ev.title.TextColor3 = e.on.color
		ev.sub.Text = e.on.text
		ev.timer.Text = clock(e.ends - t)
	else
		ev.title.Text = "NEXT: " .. string.upper(e.nextEvent.name)
		ev.title.TextColor3 = C.white
		ev.sub.Text = e.nextEvent.text
		ev.timer.Text = clock(e.nextAt - t)
	end
	local lu = tonumber(workspace:GetAttribute("ServerLuckUntil")) or 0
	if lu > t then
		luck.title.Text = "SERVER LUCK x2"
		luck.sub.Text = ("Thanks %s. Rarer tyres for everyone."):format(tostring(workspace:GetAttribute("ServerLuckBy") or ""))
		luck.timer.Text = clock(lu - t)
	else
		luck.title.Text = "SERVER LUCK"
		luck.sub.Text = "Someone buying it makes crates luckier for the whole server."
		luck.timer.Text = ""
	end
	-- the tab's red dot: an event is on, or the Heat is open
	if self.hooks.eventLive then self.hooks.eventLive(e.on ~= nil or phase == "join" or lu > t) end
end

function HubExtras:joinHeat()
	local f = self.R:FindFirstChild("HeatJoin") :: RemoteFunction?
	if not f then return end
	local ok, res = pcall(function() return f:InvokeServer() end)
	if ok and type(res) == "table" and res.ok then
		self.joined = res.joined == true
		Kit.pop(self.joinBtn.root, 0.8, 0.25)
	elseif ok and type(res) == "table" and res.err then
		Kit.callout(self.gui, res.err, C.red, UDim2.fromScale(0.5, 0.2), 30)
	end
end

-- a reward worth a banner (the Index paying out): it drops in from the top and goes again
function HubExtras:reward(d)
	if type(d) ~= "table" then return end
	local box = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -120), Size = UDim2.fromOffset(520, 78), BackgroundTransparency = 1, ZIndex = 80, Parent = self.gui })
	UI.autoScale(box, 1280, 760)
	Kit.slice("panel_body", nil, box, 80, 0.4)
	Kit.slice("panel_ring", C.yellow, box, 81, 0.4)
	local t = Kit.text(string.upper(tostring(d.text or "")), 20, C.white, 2)
	t.Position = UDim2.fromOffset(0, 10)
	t.Size = UDim2.new(1, 0, 0, 26)
	Kit.fit(t, 20, 12)
	t.ZIndex = 83
	t.Parent = box
	local pays = {}
	if d.keys then table.insert(pays, ("+%d KEY%s"):format(d.keys, d.keys == 1 and "" or "S")) end
	if d.bonus then table.insert(pays, d.bonus) end
	local r = Kit.text(table.concat(pays, "   "), 22, C.gold, 2)
	r.Position = UDim2.fromOffset(0, 40)
	r.Size = UDim2.new(1, 0, 0, 26)
	r.ZIndex = 83
	r.Parent = box
	Kit.tween(box, 0.4, { Position = UDim2.new(0.5, 0, 0, 96) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(3.2, function()
		Kit.tween(box, 0.3, { Position = UDim2.new(0.5, 0, 0, -120) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.35, function() box:Destroy() end)
	end)
end

-- the Heat's result: its own look. A chequered banner, a podium (1st tall in the middle, 2nd and
-- 3rd either side) with each racer's distance, your own place and what it paid, and the rest of the
-- field listed underneath. An X and a Continue button close it.
function HubExtras:heatResult(list)
	if type(list) ~= "table" or #list == 0 then return end
	local me = Players.LocalPlayer.UserId
	local W, H = 620, 470
	local box = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1.6, 0), Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, ZIndex = 80, Parent = self.gui })
	UI.autoScale(box, 1280, 760)
	Kit.slice("panel_body", nil, box, 80, 0.4)
	Kit.slice("panel_ring", C.red, box, 81, 0.4)
	-- the chequered banner across the top
	local flag = UI.mk("Frame", { Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(W - 28, 54), BackgroundColor3 = Color3.fromRGB(14, 14, 16), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 82, Parent = box }, { UI.corner(10) })
	local cell = 13
	for row = 0, 3 do
		for col = 0, math.ceil((W - 28) / cell) do
			if (row + col) % 2 == 0 then
				UI.mk("Frame", { Position = UDim2.fromOffset(col * cell, row * cell + 1), Size = UDim2.fromOffset(cell, cell), BackgroundColor3 = Color3.fromRGB(236, 236, 232), BorderSizePixel = 0, BackgroundTransparency = 0.82, ZIndex = 83, Parent = flag })
			end
		end
	end
	local title = Kit.text("HEAT RESULTS", 34, C.white, 3, Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic))
	title.Size = UDim2.fromScale(1, 1)
	title.ZIndex = 85
	title.Parent = flag
	-- the podium
	local medal = { Color3.fromRGB(255, 206, 72), Color3.fromRGB(206, 212, 224), Color3.fromRGB(218, 148, 92) }
	local order = { 2, 1, 3 }
	local heights = { [1] = 150, [2] = 112, [3] = 86 }
	for slot, place in ipairs(order) do
		local e = list[place]
		if e then
			local colW = 176
			local x = W / 2 + (slot - 2) * (colW + 6) - colW / 2
			local h = heights[place]
			local col = UI.mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(x, 322), Size = UDim2.fromOffset(colW, h), BackgroundColor3 = Color3.fromRGB(30, 30, 36), BorderSizePixel = 0, ZIndex = 82, Parent = box }, { UI.corner(8) })
			UI.stroke(medal[place], 3, 0).Parent = col
			local num = Kit.text(tostring(place), 54, medal[place], 3, Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic))
			num.Position = UDim2.fromOffset(0, 4)
			num.Size = UDim2.new(1, 0, 0, 58)
			num.ZIndex = 84
			num.Parent = col
			local nm = Kit.text(tostring(e.name), 18, e.userId == me and C.green or C.white, 2)
			nm.AnchorPoint = Vector2.new(0.5, 1)
			nm.Position = UDim2.new(0.5, 0, 1, -30)
			nm.Size = UDim2.new(1, -12, 0, 22)
			Kit.fit(nm, 18, 10)
			nm.ZIndex = 84
			nm.Parent = col
			local dm = Kit.text(Game.metres(e.metres or 0), 17, C.gold, 2, Kit.Body)
			dm.AnchorPoint = Vector2.new(0.5, 1)
			dm.Position = UDim2.new(0.5, 0, 1, -8)
			dm.Size = UDim2.new(1, -12, 0, 20)
			dm.ZIndex = 84
			dm.Parent = col
		end
	end
	-- the rest of the field, and you
	local mine
	for i, e in ipairs(list) do
		if e.userId == me then mine = { i = i, e = e } end
	end
	local y = 334
	for i = 4, math.min(#list, 6) do
		local e = list[i]
		local r = Kit.text(("%d.  %s   %s"):format(i, tostring(e.name), Game.metres(e.metres or 0)), 16, e.userId == me and C.green or C.muted, 1.5, Kit.Body)
		r.Position = UDim2.fromOffset(0, y)
		r.Size = UDim2.new(1, 0, 0, 20)
		r.ZIndex = 83
		r.Parent = box
		y += 20
	end
	local you = Kit.text(mine and (("YOU  ·  %s%s%s"):format(({ "1ST", "2ND", "3RD" })[mine.i] or (mine.i .. "TH"),
		(mine.e.bonus or 0) > 0 and ("   +$" .. Game.short(mine.e.bonus)) or "", (mine.e.keys or 0) > 0 and ("   +" .. mine.e.keys .. " KEY") or ""))
		or "You sat this one out", 22, mine and C.gold or C.muted, 2.5)
	you.Position = UDim2.fromOffset(0, H - 86)
	you.Size = UDim2.new(1, 0, 0, 28)
	you.ZIndex = 83
	you.Parent = box
	local ok = Kit.button("Continue", C.red, UDim2.fromOffset(240, 48), 22)
	ok.root.AnchorPoint = Vector2.new(0.5, 1)
	ok.root.Position = UDim2.new(0.5, 0, 1, -14)
	ok.root.ZIndex = 86
	ok.root.Parent = box
	local x = Kit.close(46)
	x.root.AnchorPoint = Vector2.new(0.5, 0.5)
	x.root.Position = UDim2.new(1, -2, 0, 4)
	x.root.ZIndex = 90
	x.root.Parent = box
	Kit.dim(self.gui, box, true)
	local function away()
		Kit.dim(self.gui, box, false)
		Kit.tween(box, 0.3, { Position = UDim2.new(0.5, 0, 1.6, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.35, function() box:Destroy() end)
	end
	ok.onClick = away
	x.onClick = away
	Kit.tween(box, 0.5, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(14, function() if box.Parent then away() end end)
end

-- the login calendar is up: nothing else (a launch, a panel) starts until it's claimed
function HubExtras:isDailyOpen(): boolean
	return self.dailyBox ~= nil and self.dailyBox.Parent ~= nil
end

-- the login calendar: seven days in a row of tiles, today's lit; Claim takes it
function HubExtras:showDaily(v)
	local today = Game.utcDay(math.floor(now()))
	local streak = (v.daily.last == today - 1) and (v.daily.streak + 1) or 1
	local day = ((streak - 1) % #Game.Daily) + 1
	local box = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(780, 330), BackgroundTransparency = 1, ZIndex = 70, Parent = self.gui })
	UI.autoScale(box, 1280, 760)
	self.dailyBox = box
	Kit.dim(self.gui, box, true)
	local holder, face = Kit.card(UDim2.fromOffset(780, 320), C.cream)
	holder.Parent = box
	Kit.header(face, "Daily Reward", C.yellow, 56)
	for i, g in ipairs(Game.Daily) do
		local tile = UI.mk("Frame", { Position = UDim2.fromOffset(24 + (i - 1) * 106, 60), Size = UDim2.fromOffset(96, 150), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
		local col = i < day and C.green or (i == day and C.yellow or Color3.fromRGB(70, 70, 76))
		Kit.slot(tile, col, 4)
		local dl = Kit.text("DAY " .. i, 14, i == day and C.yellow or C.muted, 1.5)
		dl.Position = UDim2.fromOffset(0, 8)
		dl.Size = UDim2.new(1, 0, 0, 16)
		dl.ZIndex = 6
		dl.Parent = tile
		UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(g.big and 72 or 58, g.big and 72 or 58),
			BackgroundTransparency = 1, Image = g.keys and (g.big and Kit.Icon.crate or Kit.Icon.key) or Kit.Icon.cash, ZIndex = 6, Parent = tile,
		})
		local what = Kit.text(g.keys and ("%d KEY%s"):format(g.keys, g.keys == 1 and "" or "S") or ("%d RUNS"):format(g.cashRuns), 14, C.white, 1.5)
		what.Position = UDim2.new(0, 0, 1, -26)
		what.Size = UDim2.new(1, 0, 0, 18)
		what.ZIndex = 6
		what.Parent = tile
		if i < day then
			local tick = Kit.text("DONE", 18, C.green, 2)
			tick.AnchorPoint = Vector2.new(0.5, 0.5)
			tick.Position = UDim2.fromScale(0.5, 0.48)
			tick.Size = UDim2.fromOffset(40, 40)
			tick.ZIndex = 7
			tick.Parent = tile
		elseif i == day then
			Kit.bob(tile, 3, 3)
		end
	end
	local sub = Kit.text(("Day %d of 7. Come back tomorrow for the next. Miss a day and it starts over."):format(day), 15, C.muted, 1.5, Kit.Body)
	sub.Position = UDim2.fromOffset(0, 222)
	sub.Size = UDim2.new(1, 0, 0, 20)
	sub.ZIndex = 5
	sub.Parent = face
	local claim = Kit.button("Claim", C.green, UDim2.fromOffset(240, 56), 24)
	claim.root.AnchorPoint = Vector2.new(0.5, 1)
	claim.root.Position = UDim2.new(0.5, 0, 1, -14)
	claim.root.ZIndex = 6
	claim.root.Parent = face
	Kit.pop(box, 0.6, 0.35)
	claim.onClick = function()
		local f = self.R:FindFirstChild("Daily") :: RemoteFunction?
		local ok, res = pcall(function() return f and f:InvokeServer() end)
		if ok and type(res) == "table" and res.ok then
			local r = res.reward or {}
			Kit.callout(self.gui, r.keys and ("+%d KEYS"):format(r.keys) or ("+$" .. Game.short(r.cash or 0)), C.yellow, UDim2.fromScale(0.5, 0.3), 56)
		end
		Kit.dim(self.gui, box, false)
		Kit.vanish(box, 0.18, function() box:Destroy() end)
	end
end

--==============================================================
-- the shop
--==============================================================
function HubExtras:buildShop()
	local gui = self.gui
	local shop = UI.mk("Frame", { Name = "Shop3", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(900, 560),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui })
	UI.autoScale(shop, 1280, 760)
	local holder, face = Kit.card(UDim2.fromOffset(900, 540), C.cream)
	holder.Parent = shop
	Kit.header(face, "Shop", C.green, 56)
	local close = Kit.close(52)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, 12, 0, -14)
	close.root.ZIndex = 40
	close.root.Parent = shop
	close.onClick = function() self:openShop(false) end
	Kit.section(face, "Passes: yours for good", UDim2.fromOffset(24, 50), UDim2.fromOffset(852, 30), 4)
	self.passBtns = {}
	local function item(def, x: number, y: number, w: number, isPass: boolean)
		local tile = UI.mk("Frame", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 180), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
		Kit.slot(tile, isPass and C.green or C.yellow, 4)
		UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(64, 64), BackgroundTransparency = 1,
			Image = Kit.Icon[def.icon] or Kit.Icon.cash, ZIndex = 6, Parent = tile,
		})
		local n = Kit.text(def.name, 16, C.white, 2)
		n.Position = UDim2.fromOffset(6, 74)
		n.Size = UDim2.new(1, -12, 0, 20)
		Kit.fit(n, 16, 10)
		n.ZIndex = 6
		n.Parent = tile
		local d = Kit.text(def.text or "", 11, C.muted, 1, Kit.Body)
		d.Position = UDim2.fromOffset(8, 96)
		d.Size = UDim2.new(1, -16, 0, 36)
		d.TextWrapped = true
		d.ZIndex = 6
		d.Parent = tile
		local soon = (isPass and def.passId or def.productId) == 0
		local b = Kit.button(soon and "Soon" or ("R$ " .. def.robux), isPass and C.green or C.yellow, UDim2.fromOffset(w - 20, 38), 16)
		b.root.Position = UDim2.fromOffset(10, 136)
		b.root.ZIndex = 7
		b.root.Parent = tile
		b.setEnabled(not soon)
		b.onClick = function()
			pcall(function()
				if isPass then
					MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, def.passId)
				else
					MarketplaceService:PromptProductPurchase(Players.LocalPlayer, def.productId)
				end
			end)
		end
		if isPass then self.passBtns[def.id] = { btn = b, soon = soon, robux = def.robux } end
	end
	for i, def in ipairs(Config.Store.Passes) do item(def, 24 + (i - 1) * 172, 88, 162, true) end
	Kit.section(face, "Keys and boosts", UDim2.fromOffset(24, 284), UDim2.fromOffset(852, 30), 4)
	for i, def in ipairs(Config.Store.Products) do item(def, 24 + (i - 1) * 214, 322, 204, false) end
	self.shop = shop
end

function HubExtras:openShop(on: boolean?)
	local show = on
	if show == nil then show = not self.shop.Visible end
	-- passes you own say so
	local v = self.profile and self.profile.v2
	for id, e in pairs(self.passBtns) do
		if v and v.passes[id] then
			e.btn.setText("Owned")
			e.btn.setEnabled(false)
		elseif not e.soon then
			e.btn.setText("R$ " .. e.robux)
			e.btn.setEnabled(true)
		end
	end
	if show then
		Kit.dim(self.gui, self.shop, true)
		Kit.open(self.shop)
	else
		Kit.dim(self.gui, self.shop, false)
		if self.shop.Visible then Kit.close_(self.shop) end
	end
end

function HubExtras:isShopOpen(): boolean
	return self.shop.Visible
end

return HubExtras
