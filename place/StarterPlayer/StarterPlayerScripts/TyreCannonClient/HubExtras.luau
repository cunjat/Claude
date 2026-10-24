--!strict
-- TYRE CANNON :: HubExtras (v3)
-- What the hub adds around its edges to keep a server together:
--   the Heat notice    top centre, only in the last 30 seconds before a Heat starts: a card with a
--                      countdown and JOIN (this is the only thing that ever sits up there)
--   the Events panel   behind the Events tab: the Heat's clock, the server event that's on or the
--                      next one, and Server Luck
-- and the popups that go with them: the login calendar, the Heat's placings, a Server Luck shout,
-- and the Shop panel (Config.Store). The shop leads with the neon stage (the Midnight Garage pass): a
-- banner with the yard turning slowly in a window, its three colourways to flick through, and the buy.
--   HubExtras.new(gui, remotes, hooks) · :setProfile(p) · :setVisible(on) · :openShop() · :openEvents()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Game = require(Modules.Game)
local Config = require(Modules.Config)
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Sound = require(script.Parent.Sound)
local Models = require(script.Parent.Models)
local NeonDecor = require(script.Parent.NeonDecor)
local YardLook = require(script.Parent.YardLook)
local RunService = game:GetService("RunService")
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
	-- (tucked in on the corner, not hanging off it)
	local x = Kit.close(28)
	x.root.AnchorPoint = Vector2.new(0.5, 0.5)
	x.root.Position = UDim2.new(1, -8, 0, 8)
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
		elseif type(d) == "table" and d.kind == "prestige" and d.userId ~= Players.LocalPlayer.UserId then
			Kit.callout(gui, ("%s reached PRESTIGE %d!"):format(tostring(d.name), tonumber(d.level) or 1), C.accent, UDim2.fromScale(0.5, 0.22), 40)
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
			-- a newcomer picks tutorial or skip first (the tutorial then makes this its first step)
			while self.hooks.holdDaily and self.hooks.holdDaily() do task.wait(0.3) end
			-- never over a launch, a run or a menu: wait until you're standing in your yard
			while self.hooks.idle and not self.hooks.idle() do task.wait(0.5) end
			local cur = (self.profile and self.profile.v2) or v
			if not self:isDailyOpen() and cur.daily.last ~= Game.utcDay(math.floor(now())) then self:showDaily(cur) end
			self.dailyDone = true
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
		-- (and not while something wants the player's attention: a newcomer's first launch, a popup)
		and not (self.hooks.quiet and self.hooks.quiet())
		-- (a race needs HeatMin players: don't offer one the server can't fill)
		and #Players:GetPlayers() >= (tonumber(workspace:GetAttribute("HeatMin")) or 2)
		and (self.dismissed == nil or self.dismissed ~= workspace:GetAttribute("HeatAt"))
	-- joined, but the window closed without enough racers: say so rather than go quiet
	if self.lastPhase == "join" and phase == "idle" and self.joined then
		Kit.callout(self.gui, "Not enough racers joined. Next heat soon.", C.red, UDim2.fromScale(0.5, 0.2), 30)
	end
	self.lastPhase = phase
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
-- (2026-10-16) rewards wait their turn: never over a run, the payout card or a crate opening
-- (rewardGate, from Main), one at a time. Unlocks (a title, a level, an Index milestone) get their
-- own banner; everything else the plain one.
function HubExtras:reward(d)
	if type(d) ~= "table" then return end
	self.rewardQueue = self.rewardQueue or {}
	table.insert(self.rewardQueue, d)
	if self.rewardPump then return end
	self.rewardPump = true
	task.spawn(function()
		while #self.rewardQueue > 0 do
			while self.rewardGate and not self.rewardGate() do task.wait(0.3) end
			local nextOne = table.remove(self.rewardQueue, 1)
			local stay = if nextOne.kind == "title" or nextOne.kind == "level" or nextOne.kind == "index" then self:unlockBanner(nextOne) else self:plainBanner(nextOne)
			task.wait(stay + 0.5)
		end
		self.rewardPump = false
	end)
end

function HubExtras:plainBanner(d): number
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
	return 3.6
end

-- an unlock: a gold sunburst turning behind its icon, NEW TITLE / LEVEL UP / INDEX on a tag, the
-- name big (a title in its own colours), what it pays under it; it pops in and shines once across
local UNLOCK = {
	title = { tag = "NEW TITLE", icon = "pass_vip", color = Color3.fromRGB(255, 196, 52) },
	level = { tag = "LEVEL UP", icon = "medal", color = Color3.fromRGB(255, 160, 40) },
	index = { tag = "INDEX MILESTONE", icon = "tyre", color = Color3.fromRGB(110, 200, 255) },
}
function HubExtras:unlockBanner(d): number
	local look = UNLOCK[d.kind]
	local W, H = 600, 128
	local holder = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, ZIndex = 80, Parent = self.gui })
	UI.autoScale(holder, 1280, 760)
	local box = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 80, Parent = holder })
	local pop = UI.mk("UIScale", { Scale = 0.4, Parent = box })
	Kit.slice("panel_body", nil, box, 80, 0.4)
	local ring = Kit.slice("panel_ring", look.color, box, 81, 0.4)
	Kit.flow(ring, "sheen", 0.6, 1.6)
	-- the burst and the icon breaking out of the left end
	local burst = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(70, H / 2), Size = UDim2.fromOffset(220, 220), BackgroundTransparency = 1,
		Image = Kit.Icon.burst_a, ImageColor3 = look.color, ImageTransparency = 0.25, ZIndex = 82, Parent = box,
	})
	UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(70, H / 2 - 4), Size = UDim2.fromOffset(112, 112), BackgroundTransparency = 1,
		Image = Kit.Icon[look.icon] or Kit.Icon.medal, ZIndex = 84, Parent = box,
	})
	if d.kind == "level" and d.level then
		local n = Kit.text(tostring(d.level), 26, C.white, 2.5)
		n.AnchorPoint = Vector2.new(0.5, 0.5)
		n.Position = UDim2.fromOffset(70, H / 2 + 14)
		n.Size = UDim2.fromOffset(60, 30)
		n.ZIndex = 85
		n.Parent = box
	end
	local tag = UI.mk("Frame", { Position = UDim2.fromOffset(140, 14), Size = UDim2.fromOffset(170, 24), BackgroundColor3 = look.color, ZIndex = 83, Parent = box }, { UI.corner(12) })
	UI.mk("UIStroke", { Color = C.ink, Thickness = 2, Parent = tag })
	local tt = Kit.text(look.tag, 14, C.ink, 0)
	tt.Size = UDim2.fromScale(1, 1)
	Kit.fit(tt, 14, 9)
	tt.ZIndex = 84
	tt.Parent = tag
	local name: TextLabel
	if d.kind == "title" and d.id then
		name = UI.titleLabel(d.id, 34)
	else
		name = Kit.text(string.upper(tostring(d.name or d.text or "")), 32, C.white, 2.5)
	end
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.fromOffset(140, 42)
	name.Size = UDim2.fromOffset(W - 160, 40)
	Kit.fit(name, 34, 14)
	name.ZIndex = 84
	name.Parent = box
	local pays = {}
	if d.sub then table.insert(pays, tostring(d.sub)) end
	if d.keys then table.insert(pays, ("+%d key%s"):format(d.keys, d.keys == 1 and "" or "s")) end
	if d.bonus then table.insert(pays, d.bonus) end
	local sub = Kit.text(table.concat(pays, "   ·   "), 16, C.gold, 1.5, Kit.Body)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Position = UDim2.fromOffset(140, 86)
	sub.Size = UDim2.fromOffset(W - 160, 22)
	Kit.fit(sub, 16, 10)
	sub.ZIndex = 84
	sub.Parent = box
	Sound.play("medal", { volume = 0.8, pitch = 1.0, length = 1.4 })
	Kit.tween(pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local conn = game:GetService("RunService").RenderStepped:Connect(function(dt) burst.Rotation += dt * 30 end)
	task.delay(4.2, function()
		Kit.tween(pop, 0.25, { Scale = 0.2 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.28, function()
			conn:Disconnect()
			holder:Destroy()
		end)
	end)
	return 4.5
end

-- the Heat's result: its own look. A chequered banner, a podium (1st tall in the middle, 2nd and
-- 3rd either side) with each racer's distance, your own place and what it paid, and the rest of the
-- field listed underneath. An X and a Continue button close it.
-- (2026-10-24) it waits for the reward gate like every other card: it used to land on top of a run
-- or a crate opening
function HubExtras:heatResult(list)
	if type(list) ~= "table" or #list == 0 then return end
	if self.rewardGate and not self.rewardGate() then
		task.spawn(function()
			local waited = 0
			while not self.rewardGate() and waited < 180 do waited += task.wait(0.3) end
			self:heatResultNow(list)
		end)
		return
	end
	self:heatResultNow(list)
end

function HubExtras:heatResultNow(list)
	local me = Players.LocalPlayer.UserId
	local W, H = 620, 470
	local box = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1.6, 0), Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, ZIndex = 80, Parent = self.gui })
	self.resultBox = box
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

-- the Heat's results are up (the hub steps aside for them like a panel)
function HubExtras:isResultOpen(): boolean
	return self.resultBox ~= nil and self.resultBox.Parent ~= nil
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
		local what = Kit.text(g.keys and ("%d KEY%s"):format(g.keys, g.keys == 1 and "" or "S") or ("%d RUNS' CASH"):format(g.cashRuns), 14, C.white, 1.5) -- (2026-10-18: "3 RUNS" read as a task)
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
	self.dailyClaim = claim.root    -- (the tutorial points at it)
	Kit.pop(box, 0.6, 0.35)
	-- the X: close it without claiming (the DAILY button under your keys brings it back)
	local x = Kit.close(48)
	x.root.AnchorPoint = Vector2.new(0.5, 0.5)
	x.root.Position = UDim2.new(1, -8, 0, 8)
	x.root.ZIndex = 80
	x.root.Parent = box
	x.onClick = function()
		Kit.dim(self.gui, box, false)
		Kit.vanish(box, 0.18, function() box:Destroy() end)
	end
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
-- each pass in its own colour, with a tag on the ones worth pointing at, and a living sheen on
-- the buttons of the big ones (2026-10-16: the shop's job is to make each thing look worth having)
local PASS_LOOK = {
	cash2 = { color = Color3.fromRGB(70, 196, 84), tag = "MOST POPULAR" },
	autolaunch = { color = Color3.fromRGB(255, 128, 40) },
	spares2 = { color = Color3.fromRGB(64, 150, 255) },
	lucky = { color = Color3.fromRGB(40, 200, 140), shine = true },
	vip = { color = Color3.fromRGB(255, 196, 52), tag = "BEST VALUE", shine = true },
	keys40 = { color = C.yellow, tag = "BEST DEAL" },
	serverluck = { color = Color3.fromRGB(40, 200, 140), tag = "EVERYONE" },
	starter = { color = C.purple, tag = "ONCE ONLY", shine = true },
}

function HubExtras:buildShop()
	local gui = self.gui
	local shop = UI.mk("Frame", { Name = "Shop3", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53), Size = UDim2.fromOffset(900, 700),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui })
	UI.autoScale(shop, 1280, 760)
	local holder, face = Kit.card(UDim2.fromOffset(900, 680), C.cream)
	holder.Parent = shop
	Kit.header(face, "Shop", C.green, 56)
	local close = Kit.close(52)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, 12, 0, -14)
	close.root.ZIndex = 40
	close.root.Parent = shop
	close.onClick = function() self:openShop(false) end
	self.passBtns = {}
	self.onceBtns = {}
	self.shopIcons = {}
	self:buildNeonBanner(face)
	Kit.section(face, "Passes: yours for good", UDim2.fromOffset(24, 214), UDim2.fromOffset(852, 28), 4)
	local function item(def, x: number, y: number, w: number, h: number, isPass: boolean)
		local look = PASS_LOOK[def.id] or { color = if isPass then C.green else C.yellow }
		local tile = UI.mk("Frame", { Name = def.id, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
		Kit.slot(tile, look.color, 4)
		-- (the products' row is shorter: a smaller picture, the name clear of the button, no blurb)
		local iconSize = if isPass then 92 else 58
		local icon = UI.mk("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -12), Size = UDim2.fromOffset(iconSize, iconSize), BackgroundTransparency = 1,
			Image = Kit.Icon[def.icon] or Kit.Icon.cash, ZIndex = 7, Parent = tile,
		})
		-- (the icon rocks a little while the shop's open)
		table.insert(self.shopIcons, { icon = icon, phase = x * 0.013 + y * 0.007 })
		if look.tag then
			local tag = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(math.min(w - 16, 118), 22),
				BackgroundColor3 = look.color, ZIndex = 9, Parent = tile }, { UI.corner(11) })
			UI.mk("UIStroke", { Color = C.ink, Thickness = 2, Parent = tag })
			local tt = Kit.text(look.tag, 12, C.white, 1.5)
			tt.Size = UDim2.fromScale(1, 1)
			Kit.fit(tt, 12, 8)
			tt.ZIndex = 10
			tt.Parent = tag
			icon.Position = UDim2.new(0.5, 0, 0, 4)
		end
		local top = if isPass then iconSize - 8 else iconSize - 12
		local n = Kit.text(def.name, 17, C.white, 2)
		n.Position = UDim2.fromOffset(6, top)
		n.Size = UDim2.new(1, -12, 0, 20)
		Kit.fit(n, 17, 10)
		n.ZIndex = 6
		n.Parent = tile
		local d = Kit.text(def.text or "", 12, C.muted, 1, Kit.Body)
		d.Position = UDim2.fromOffset(8, top + 21)
		d.Size = UDim2.new(1, -16, 0, math.max(14, h - top - 21 - 50))
		d.TextWrapped = true
		d.TextYAlignment = Enum.TextYAlignment.Top
		d.ZIndex = 6
		d.Visible = isPass
		d.Parent = tile
		local soon = (isPass and def.passId or def.productId) == 0
		local b = Kit.button(soon and "Soon" or ("R$ " .. def.robux), look.color, UDim2.fromOffset(w - 20, if isPass then 38 else 34), 16)
		b.root.AnchorPoint = Vector2.new(0, 1)
		b.root.Position = UDim2.new(0, 10, 1, -8)
		b.root.ZIndex = 7
		b.root.Parent = tile
		b.setEnabled(not soon)
		if look.shine then
			local bf = b.root:FindFirstChild("Face", true)
			if bf then Kit.flow(bf :: GuiObject, "sheen", 0.35, 2.4) end
		end
		local function blocked(): boolean
			return def.paidRandom == true and Players.LocalPlayer:GetAttribute("PaidRandomItemsRestricted") ~= false
		end
		if def.paidRandom and not soon then
			local function policy()
				b.setText(if blocked() then "Unavailable" else "R$ " .. def.robux)
				b.setEnabled(not blocked())
			end
			policy()
			Players.LocalPlayer:GetAttributeChangedSignal("PaidRandomItemsRestricted"):Connect(policy)
		end
		b.onClick = function()
			if soon or blocked() then return end
			pcall(function()
				if isPass then
					MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, def.passId)
				else
					MarketplaceService:PromptProductPurchase(Players.LocalPlayer, def.productId)
				end
			end)
		end
		if isPass then self.passBtns[def.id] = { btn = b, soon = soon, robux = def.robux } end
		if def.once then self.onceBtns[def.id] = { btn = b, soon = soon, robux = def.robux } end
	end
	-- the passes share the row, however many there are (the neon stage has its banner)
	local row = {}
	for _, def in ipairs(Config.Store.Passes) do
		if def.id ~= "midnight" then table.insert(row, def) end
	end
	local passW = math.floor((852 - (#row - 1) * 10) / #row)
	for i, def in ipairs(row) do item(def, 24 + (i - 1) * (passW + 10), 262, passW, 174, true) end
	Kit.section(face, "Keys and boosts", UDim2.fromOffset(24, 444), UDim2.fromOffset(852, 28), 4)
	local prodW = math.floor((852 - (#Config.Store.Products - 1) * 10) / #Config.Store.Products)
	for i, def in ipairs(Config.Store.Products) do item(def, 24 + (i - 1) * (prodW + 10), 490, prodW, 124, false) end
	-- Roblox Premium: what members get here, and the way to join
	local prem = UI.mk("Frame", { Name = "Premium", Position = UDim2.fromOffset(24, 622), Size = UDim2.fromOffset(852, 48), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
	Kit.slot(prem, Color3.fromRGB(255, 96, 176), 4)
	UI.mk("ImageLabel", { Position = UDim2.fromOffset(8, -8), Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1, Image = Kit.Icon.premium or Kit.Icon.gold, ZIndex = 7, Parent = prem })
	local pt = Kit.text(('<font color="#FF8AC8">ROBLOX PREMIUM</font>   +%d%% cash on everything, and a free key every day you play'):format(math.floor((Game.Premium.Cash - 1) * 100 + 0.5)), 15, C.white, 1.5, Kit.Body)
	pt.TextXAlignment = Enum.TextXAlignment.Left
	pt.Position = UDim2.fromOffset(76, 0)
	pt.Size = UDim2.fromOffset(580, 48)
	Kit.fit(pt, 15, 9)
	pt.ZIndex = 6
	pt.Parent = prem
	local pb = Kit.button("Get Premium", Color3.fromRGB(255, 96, 176), UDim2.fromOffset(170, 36), 15)
	pb.root.AnchorPoint = Vector2.new(1, 0.5)
	pb.root.Position = UDim2.new(1, -10, 0.5, 0)
	pb.root.ZIndex = 7
	pb.root.Parent = prem
	local function premState()
		local member = Players.LocalPlayer.MembershipType == Enum.MembershipType.Premium
		pb.setText(if member then "Active" else "Get Premium")
		pb.setEnabled(not member)
	end
	premState()
	Players.PlayerMembershipChanged:Connect(function(pl) if pl == Players.LocalPlayer then premState() end end)
	pb.onClick = function()
		if Players.LocalPlayer.MembershipType == Enum.MembershipType.Premium then return end
		pcall(function() MarketplaceService:PromptPremiumPurchase(Players.LocalPlayer) end)
	end
	RunService.RenderStepped:Connect(function()
		if not shop.Visible then return end
		local t = os.clock()
		for _, e in ipairs(self.shopIcons) do
			e.icon.Rotation = math.sin(t * 1.6 + e.phase) * 3
		end
	end)
	self.shop = shop
end

-- the neon stage: the Midnight Garage yard in a window, turning, in whichever colourway is picked
function HubExtras:buildNeonBanner(face: Frame)
	local def = Config.StorePassesById.midnight
	if not def then return end
	local band = UI.mk("Frame", { Name = "NeonStage", Position = UDim2.fromOffset(24, 60), Size = UDim2.fromOffset(852, 146), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
	local slot = Kit.slot(band, C.purple, 4)
	local vp = UI.mk("ViewportFrame", {
		Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(310, 130), BackgroundColor3 = Color3.fromRGB(12, 10, 26), BackgroundTransparency = 0,
		Ambient = Color3.fromRGB(150, 146, 170), LightColor = Color3.fromRGB(255, 244, 228), LightDirection = Vector3.new(-0.4, -1, -0.5), ZIndex = 6, Parent = band,
	}, { UI.corner(10) })
	local cam = Instance.new("Camera")
	cam.FieldOfView = 34
	cam.Parent = vp
	vp.CurrentCamera = cam
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local layout = Game.yardLayout(nil)
	local F = Game.yardFloor(1)
	local function build(wayId: string)
		world:ClearAllChildren()
		local floor = Instance.new("Part")
		floor.Anchored = true
		floor.Size = Vector3.new(F.x1 - F.x0 + 4, 2, F.z1 - F.z0 + 4)
		floor.CFrame = CFrame.new((F.x0 + F.x1) / 2, 1, (F.z0 + F.z1) / 2)
		floor.Color = Color3.fromRGB(40, 38, 48)
		floor.Material = Enum.Material.Concrete
		floor.Parent = world
		local f = Instance.new("Folder")
		f.Parent = world
		YardLook.build(f, CFrame.new(), 1, layout, "midnight:" .. wayId, 0)
		-- the cannon on its spot, and the pass's neon pieces round the yard
		local way = Game.yardWay(wayId)
		local tpl = Models.get("Cannons/Cannon3") or Models.get("Cannons/Cannon1")
		if tpl then Models.place(tpl, world, CFrame.new(Game.yardSpot(layout, "cannon").Position), 1) end
		for _, pc in ipairs({ { "neonsign", -24, 22, 0.6 }, { "neonstack", 36, -30, 0 }, { "checkerflag", 64, 30, -1.2 }, { "neonlamp", 6, 32, 3.1 }, { "neoncones", 46, 4, 1.57 } }) do
			local m = NeonDecor.build(pc[1], { a = way.a, b = way.b })
			if m then
				m:PivotTo(CFrame.new(pc[2], 2, pc[3]) * CFrame.Angles(0, pc[4], 0))
				m.Parent = world
			end
		end
	end
	build("Midnight")
	-- it turns slowly while the shop's open
	local t0 = os.clock()
	local centre = Vector3.new((F.x0 + F.x1) / 2, 0, 0)
	RunService.RenderStepped:Connect(function()
		if not (self.shop and self.shop.Visible) then return end
		local a = (os.clock() - t0) * 0.18 + 2.3
		cam.CFrame = CFrame.lookAt(centre + Vector3.new(math.cos(a) * 118, 86, math.sin(a) * 118), centre + Vector3.new(0, 4, 0))
	end)
	cam.CFrame = CFrame.lookAt(centre + Vector3.new(math.cos(2.3) * 118, 86, math.sin(2.3) * 118), centre + Vector3.new(0, 4, 0))

	local title = Kit.text("NEON STAGE", 30, C.white, 2.5)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(336, 8)
	title.Size = UDim2.fromOffset(300, 34)
	title.ZIndex = 6
	title.Parent = band
	local sub = Kit.text(def.name .. " plot look", 16, C.purple, 1.5, Kit.Body)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Position = UDim2.fromOffset(338, 40)
	sub.Size = UDim2.fromOffset(300, 20)
	sub.ZIndex = 6
	sub.Parent = band
	local d = Kit.text("Night floor and grid, a double neon edge, a bump lane, tyre towers, and 8 neon decor pieces. Switch it on in Edit Yard with LOOK.", 13, C.muted, 1, Kit.Body)
	d.TextWrapped = true
	d.TextXAlignment = Enum.TextXAlignment.Left
	d.TextYAlignment = Enum.TextYAlignment.Top
	d.Position = UDim2.fromOffset(338, 62)
	d.Size = UDim2.fromOffset(310, 40)
	d.ZIndex = 6
	d.Parent = band
	-- the colourways: each a chip in its two tube colours
	local ways = Game.YardLooksById.midnight.ways
	for i, w in ipairs(ways) do
		local chip = UI.mk("TextButton", {
			Position = UDim2.fromOffset(338 + (i - 1) * 98, 106), Size = UDim2.fromOffset(90, 30), BackgroundColor3 = w.floor, AutoButtonColor = false,
			Text = "", ZIndex = 6, Parent = band,
		}, { UI.corner(8) })
		local stroke = UI.mk("UIStroke", { Color = w.a, Thickness = if i == 1 then 3 else 1.5, Parent = chip })
		UI.mk("Frame", { Position = UDim2.fromOffset(6, 22), Size = UDim2.new(1, -12, 0, 3), BackgroundColor3 = w.b, BorderSizePixel = 0, ZIndex = 7, Parent = chip })
		local l = Kit.text(w.id, 13, w.a, 1.5, Kit.Body)
		l.Size = UDim2.new(1, 0, 0, 22)
		l.ZIndex = 7
		l.Parent = chip
		chip.Activated:Connect(function()
			build(w.id)
			for _, other in ipairs(band:GetChildren()) do
				local s = other:IsA("TextButton") and other:FindFirstChildOfClass("UIStroke")
				if s then s.Thickness = 1.5 end
			end
			stroke.Thickness = 3
			Kit.pop(chip, 0.9, 0.2)
		end)
	end
	local soon = def.passId == 0
	local b = Kit.button(soon and "Soon" or ("R$ " .. def.robux), C.purple, UDim2.fromOffset(170, 56), 22)
	b.root.AnchorPoint = Vector2.new(1, 0.5)
	b.root.Position = UDim2.new(1, -16, 0.5, 0)
	b.root.ZIndex = 7
	b.root.Parent = band
	b.setEnabled(not soon)
	b.onClick = function()
		if soon then return end
		pcall(function() MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, def.passId) end)
	end
	local price = Kit.text(("R$ %d"):format(def.robux), 14, C.gold, 1.5, Kit.Body)
	price.AnchorPoint = Vector2.new(1, 0)
	price.Position = UDim2.new(1, -16, 0.5, 32)
	price.Size = UDim2.fromOffset(170, 18)
	price.Visible = soon
	price.ZIndex = 7
	price.Parent = band
	self.passBtns.midnight = { btn = b, soon = soon, robux = def.robux }
	local _ = slot
end

function HubExtras:openShop(on: boolean?)
	local show = on
	if show == nil then show = not self.shop.Visible end
	-- passes you own say so (and a once-only pack you've had)
	local v = self.profile and self.profile.v2
	for id, e in pairs(self.onceBtns or {}) do
		if v and v.passes[id] then
			e.btn.setText("Owned")
			e.btn.setEnabled(false)
		end
	end
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
