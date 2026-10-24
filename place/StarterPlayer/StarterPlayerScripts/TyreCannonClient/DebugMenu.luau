--!strict
-- TYRE CANNON :: DebugMenu
-- Open with ` (backquote). Server commands need the password; the server checks it, never the client.
-- In the kit's own style (like Settings): a card, a row of tabs, a grid of buttons, a status line.
--   Player   cash, keys, the yard's stage and machines, zones, tyres, every menu one click away
--   Run      launch, the bots (none / ok / good), speed and nitro, end the run
--   Game     the stats overlay, popups, animations, hide the UI
--   Log      every client and server error and warning, newest first
--   Playtest the playtest log (Server/Analytics): today and the last week, the tutorial funnel,
--            what got opened and done, who played how long, and the feedback notes

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Remotes = Root:WaitForChild("Remotes")
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))
local Game = require(Root:WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local C = Kit.C

local DebugMenu = {}
DebugMenu.__index = DebugMenu

local MAX_LOG = 120
local TABS = { "Player", "Run", "Game", "Log", "Playtest" }

function DebugMenu.new(gui: ScreenGui, ctx)
	local self = setmetatable({}, DebugMenu)
	self.ctx = ctx
	self.gui = gui
	-- (in Studio it's always a dev at the keys: the menu opens unlocked, and the server agrees)
	self.unlocked = RunService:IsStudio()
	-- (a dev on the server's DEVS list is let in without the password: ask once)
	task.spawn(function()
		-- (a few tries: the server answers only once the save's loaded)
		for _ = 1, 6 do
			local ok, res = pcall(function() return Remotes.Debug:InvokeServer("whoami") end)
			if ok and type(res) == "table" and res.ok then
				self.unlocked = true
				if self.panel.Visible then self:render() end
				return
			elseif ok and type(res) == "table" and res.err == "Locked." then
				return
			end
			task.wait(5)
		end
	end)
	self.log = {}
	self.errors = 0
	self.tab = "Player"

	local root = UI.mk("Frame", {
		Name = "Debug", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), Size = UDim2.fromOffset(640, 600),
		BackgroundTransparency = 1, Visible = false, ZIndex = 150, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.panel = root
	local holder, face = Kit.card(UDim2.fromOffset(640, 590), C.cream)
	holder.Parent = root
	Kit.header(face, "Debug", C.red, 56)
	local ver = Kit.text(Config.VersionLabel, 13, C.muted, 1.5, Kit.Body)
	ver.AnchorPoint = Vector2.new(1, 0)
	ver.Position = UDim2.new(1, -86, 0, 14)
	ver.Size = UDim2.fromOffset(160, 18)
	ver.TextXAlignment = Enum.TextXAlignment.Right
	ver.ZIndex = 8
	ver.Parent = face
	local close = Kit.close(48)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, 12, 0, -12)
	close.root.ZIndex = 160
	close.root.Parent = root
	close.onClick = function() self:toggle(false) end

	self.status = Kit.text("", 14, C.gold, 1.5, Kit.Body)
	self.status.AnchorPoint = Vector2.new(0, 1)
	self.status.Position = UDim2.new(0, 26, 1, -12)
	self.status.Size = UDim2.new(1, -52, 0, 20)
	self.status.TextXAlignment = Enum.TextXAlignment.Left
	self.status.TextTruncate = Enum.TextTruncate.AtEnd
	self.status.ZIndex = 8
	self.status.Parent = face

	-- locked view: a password
	local lock = UI.mk("Frame", { Position = UDim2.fromOffset(26, 80), Size = UDim2.fromOffset(588, 70), BackgroundTransparency = 1, ZIndex = 6, Parent = face })
	self.lock = lock
	local boxWrap = UI.mk("Frame", { Size = UDim2.fromOffset(390, 54), BackgroundTransparency = 1, ZIndex = 6, Parent = lock })
	Kit.slot(boxWrap, C.line, 6)
	local box = UI.mk("TextBox", {
		Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = "",
		PlaceholderText = "password", PlaceholderColor3 = C.muted, TextColor3 = C.text, FontFace = Kit.Body, TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 9, Parent = boxWrap,
	})
	local unlock = Kit.button("Unlock", C.green, UDim2.fromOffset(180, 54), 22)
	unlock.root.Position = UDim2.fromOffset(408, 0)
	unlock.root.ZIndex = 8
	unlock.root.Parent = lock
	local function tryUnlock()
		local ok, res = pcall(function() return Remotes.Debug:InvokeServer("auth", box.Text) end)
		if ok and type(res) == "table" and res.ok then
			self.unlocked = true
			box.Text = ""
			self:render()
			self:say("unlocked")
		else
			self:say((ok and type(res) == "table" and res.err) or "no answer")
		end
	end
	unlock.onClick = tryUnlock
	box.FocusLost:Connect(function(enter) if enter then tryUnlock() end end)

	-- unlocked view: tabs, then the grid
	local body = UI.mk("Frame", { Position = UDim2.fromOffset(26, 66), Size = UDim2.fromOffset(588, 470), BackgroundTransparency = 1, Visible = false, ZIndex = 6, Parent = face })
	self.body = body
	self.tabButtons = {}
	for i, name in ipairs(TABS) do
		local b = Kit.tab(name, UDim2.fromOffset(110, 40), name == self.tab)
		b.root.Position = UDim2.fromOffset((i - 1) * 119, 0)
		b.root.ZIndex = 8
		b.root.Parent = body
		b.onClick = function()
			self.tab = name
			self:render()
		end
		self.tabButtons[name] = b
	end
	self.content = UI.mk("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 54), Size = UDim2.fromOffset(588, 416), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, ScrollBarImageColor3 = C.line, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 6, Parent = body,
	})
	UI.mk("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 6), PaddingBottom = UDim.new(0, 16), Parent = self.content })

	-- stats overlay
	self.overlay = Kit.text("", 14, C.gold, 2, Kit.Body)
	self.overlay.AnchorPoint = Vector2.new(0, 1)
	self.overlay.Position = UDim2.new(0, 10, 1, -8)
	self.overlay.Size = UDim2.fromOffset(720, 18)
	self.overlay.TextXAlignment = Enum.TextXAlignment.Left
	self.overlay.Visible = false
	self.overlay.ZIndex = 150
	self.overlay.Parent = gui

	-- log capture
	LogService.MessageOut:Connect(function(msg, kind)
		if kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning then
			self:addLog("client", msg, kind.Name)
		end
	end)
	Remotes.DebugLog.OnClientEvent:Connect(function(src, msg, kind)
		self:addLog(tostring(src), tostring(msg), tostring(kind))
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.Backquote then self:toggle() end
	end)

	local frames, acc = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		frames += 1
		acc += dt
		if acc < 0.5 or not self.overlay.Visible then return end
		local fps = frames / acc
		frames, acc = 0, 0
		local world = workspace:FindFirstChild("TyreCannonWorld")
		local parts = world and #world:GetDescendants() or 0
		local ping = math.floor(Players.LocalPlayer:GetNetworkPing() * 1000)
		self.overlay.Text = ("FPS %d   PING %dms   WORLD %d   MEM %dMB   STATE %s"):format(
			math.floor(fps + 0.5), ping, parts, math.floor(Stats:GetTotalMemoryUsageMb()), tostring(ctx.getState and ctx.getState() or "?"))
	end)

	return self
end

function DebugMenu:say(text: string)
	self.status.Text = text
end

function DebugMenu:addLog(src: string, msg: string, kind: string)
	table.insert(self.log, 1, { src = src, msg = msg, kind = kind, t = os.date("%H:%M:%S") })
	while #self.log > MAX_LOG do table.remove(self.log) end
	if kind == "MessageError" then self.errors += 1 end
	if self.tabButtons.Log then self.tabButtons.Log.setText(self.errors > 0 and ("Log " .. self.errors) or "Log") end
	if self.panel.Visible and self.tab == "Log" then self:render() end
end

function DebugMenu:toggle(force: boolean?)
	local v = if force == nil then not self.panel.Visible else force
	if v == self.panel.Visible then return end
	if v then
		self.panel.Visible = true
		Kit.open(self.panel)
		self:render()
	else
		Kit.close_(self.panel)
	end
end

function DebugMenu:server(cmd: string, a: any?, b: any?)
	local ok, res = pcall(function() return Remotes.Debug:InvokeServer(cmd, a, b) end)
	if not ok or type(res) ~= "table" then
		self:say("no answer")
		return nil
	end
	if res.profile and self.ctx.hub then self.ctx.hub:setProfile(res.profile) end
	if res.ok then
		self:say(type(res.msg) == "string" and res.msg or "done")
	else
		self:say("failed: " .. tostring(res.err))
	end
	return res
end

-- the Playtest tab: asks the server for the log, then lays it out as lines of text
function DebugMenu:renderPlaytest(c: ScrollingFrame)
	UI.mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = c })
	local order = 0
	local function line(text: string, color: Color3?, size: number?)
		order += 1
		local l = Kit.text(text, size or 14, color or C.text, 1.5, Kit.Body)
		l.RichText = true
		l.Size = UDim2.new(1, -16, 0, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.LayoutOrder = order
		l.ZIndex = 8
		l.Parent = c
		return l
	end
	local function head(text: string)
		local l = line(string.upper(text), C.gold, 16)
		l.FontFace = Kit.Font
	end
	local refresh = Kit.button("Refresh", C.blue, UDim2.fromOffset(140, 34), 15)
	refresh.root.ZIndex = 8
	refresh.root.LayoutOrder = 0
	refresh.root.Parent = c
	refresh.onClick = function() self:render() end
	local status = line("Loading the playtest log...", C.muted)
	task.spawn(function()
		local res = self:server("playtest")
		if not (res and res.ok and type(res.msg) == "table") then
			status.Text = "Couldn't load the log."
			return
		end
		if self.tab ~= "Playtest" or not status.Parent then return end
		local d = res.msg
		status.Text = if d.saved then "Saved across every server (written once a minute)." else "This server only (the store can't be reached here, e.g. in Studio)."
		local function n(t, k) return tonumber(t[k]) or 0 end
		-- (players' own words go into rich text: keep their < > & from being read as markup)
		local function esc(s: any): string
			return (string.gsub(string.gsub(string.gsub(tostring(s), "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
		end
		local function pct(a: number, b: number): string
			return if b > 0 then ("%d%%"):format(math.floor(a / b * 100 + 0.5)) else "-"
		end
		local today = (d.days[1] and d.days[1].c) or {}
		local runs = n(today, "ev:RunMetres")
		head("Today")
		line(("Players <b>%d</b> (new %d)   Sessions %d, avg <b>%.1f min</b>   Runs <b>%d</b>, avg %s"):format(
			n(today, "joins"), n(today, "newPlayers"), n(today, "sessions"), n(today, "minutes") / math.max(1, n(today, "sessions")),
			runs, if runs > 0 then Game.metres(n(today, "metres") / runs) else "-"))
		line(("Crates opened %d   Jobs done %d"):format(n(today, "ev:CratesOpened"), n(today, "ev:QuestDone")))
		line(("Stage ups %d   Prestiges %d   Trials %d   Level ups %d   Titles %d   Perks %d   Likes %d   Tutorial skips %d"):format(
			n(today, "ev:StageUp"), n(today, "ev:Prestige"), n(today, "ev:TrialDone"), n(today, "ev:LevelUp"), n(today, "ev:TitleUnlocked"),
			n(today, "ev:PerkPicked"), n(today, "ev:YardLike"), n(today, "ev:TutorialSkipped")))
		line(("Feedback %d   Ratings %d, avg <b>%s</b> stars"):format(n(today, "ev:Feedback"), n(today, "rated"),
			if n(today, "rated") > 0 then ("%.1f"):format(n(today, "stars") / n(today, "rated")) else "-"))
		head("Tutorial funnel (today, of new players)")
		local base = math.max(n(today, "newPlayers"), n(today, "tut:Joined"))
		for _, step in ipairs(d.steps or {}) do
			local k = n(today, "tut:" .. step)
			line(("%-14s %4d   %s"):format(step, k, pct(k, base)), if base > 0 and k / base < 0.5 then C.red else C.text)
		end
		local function group(title: string, prefix: string)
			local rows = {}
			for k, v in pairs(today) do
				if string.sub(k, 1, #prefix) == prefix then table.insert(rows, { k = string.sub(k, #prefix + 1), v = tonumber(v) or 0 }) end
			end
			if #rows == 0 then return end
			table.sort(rows, function(a, b) return a.v > b.v end)
			head(title)
			local parts = {}
			for _, r in ipairs(rows) do table.insert(parts, ("%s %s"):format(r.k, Game.short(r.v))) end
			line(table.concat(parts, "   "))
		end
		group("Screens opened", "open:")
		group("Tips seen", "tip:")
		group("Cash and keys in", "in:")
		group("Cash and keys out", "out:")
		if #d.days > 1 then
			head("The last week")
			for _, day in ipairs(d.days) do
				local t = day.c
				local s = n(t, "sessions")
				line(("%s   players %d (new %d)   avg %.1f min   runs %d   ratings %s"):format(
					os.date("!%a %d %b", day.day * 86400), n(t, "joins"), n(t, "newPlayers"), n(t, "minutes") / math.max(1, s), n(t, "ev:RunMetres"),
					if n(t, "rated") > 0 then ("%.1f"):format(n(t, "stars") / n(t, "rated")) else "-"))
			end
		end
		local function who(r): string
			return ("<b>%s</b>  %.1f min  runs %s  best %s  stage %s  P%s  lv %s  tutorial %s%s"):format(
				esc(r.n), tonumber(r.m) or 0, tostring(r.runs or "-"), if r.best then Game.metres(r.best) else "-",
				tostring(r.stage or "-"), tostring(r.pres or 0), tostring(r.lvl or "-"),
				tostring(d.steps and d.steps[tonumber(r.tut) or 0] or r.tut or "-"), if r.tutDone then " (done)" else "")
		end
		head(("Playing now (%d)"):format(#(d.now or {})))
		for _, r in ipairs(d.now or {}) do line(who(r)) end
		head("Recent sessions")
		for i, r in ipairs(d.sessions or {}) do
			if i > 30 then break end
			line(os.date("!%d %b %H:%M  ", tonumber(r.t) or 0) .. who(r), C.text, 13)
		end
		head("Feedback notes")
		for i, e in ipairs(d.notes or {}) do
			if i > 30 then break end
			local stars = if (tonumber(e.rating) or 0) > 0 then string.rep("*", e.rating) .. "  " else ""
			line(("<b>%s</b> [%s] %s%s  <font color=\"#8A8478\">stage %s, %s runs, %s</font>"):format(
				esc(e.name), esc(string.upper(tostring(e.kind))), stars, esc(e.text or ""), tostring(e.tier), tostring(e.runs), tostring(e.ver)), C.text, 13)
		end
	end)
end

function DebugMenu:render()
	self.lock.Visible = not self.unlocked
	self.body.Visible = self.unlocked
	if not self.unlocked then return end
	for name, b in pairs(self.tabButtons) do b.setColor(if name == self.tab then C.accent else C.grey) end

	local c = self.content
	for _, ch in ipairs(c:GetChildren()) do
		if not ch:IsA("UIPadding") then ch:Destroy() end
	end
	local ctx = self.ctx

	if self.tab == "Playtest" then
		self:renderPlaytest(c)
		return
	end

	if self.tab == "Log" then
		UI.mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = c })
		local clear = Kit.button("Clear", C.grey, UDim2.fromOffset(140, 36), 16)
		clear.root.ZIndex = 8
		clear.root.Parent = c
		clear.onClick = function()
			self.log = {}
			self.errors = 0
			self.tabButtons.Log.setText("Log")
			self:render()
		end
		for i, e in ipairs(self.log) do
			local l = Kit.text(("%s  %s  %s"):format(e.t, string.upper(e.src), e.msg), 13, if e.kind == "MessageError" then C.red else C.gold, 1.5, Kit.Body)
			l.Size = UDim2.new(1, -16, 0, 0)
			l.AutomaticSize = Enum.AutomaticSize.Y
			l.TextWrapped = true
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.TextYAlignment = Enum.TextYAlignment.Top
			l.LayoutOrder = i + 1
			l.ZIndex = 8
			l.Parent = c
		end
		if #self.log == 0 then
			local l = Kit.text("No errors or warnings. Good.", 16, C.muted, 1.5, Kit.Body)
			l.Size = UDim2.new(1, 0, 0, 28)
			l.LayoutOrder = 2
			l.ZIndex = 8
			l.Parent = c
		end
		return
	end

	UI.mk("UIGridLayout", { CellSize = UDim2.fromOffset(176, 44), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = c })
	local order = 0
	local function add(label: string, fn: () -> (), color: Color3?)
		order += 1
		local b = Kit.button(label, color or C.grey, UDim2.fromOffset(176, 44), 15)
		b.root.LayoutOrder = order
		b.root.ZIndex = 8
		b.root.Parent = c
		b.onClick = function()
			local ok, err = pcall(fn)
			if not ok then self:say("error: " .. tostring(err)) end
		end
	end
	-- start the next group on a fresh row of the grid
	local function gap()
		while order % 3 ~= 0 do
			order += 1
			UI.mk("Frame", { BackgroundTransparency = 1, LayoutOrder = order, Parent = c })
		end
	end

	if self.tab == "Player" then
		add("+10K cash", function() self:server("give", "credits", 10000) end, C.green)
		add("+1M cash", function() self:server("give", "credits", 1000000) end, C.green)
		add("+1B cash", function() self:server("give", "credits", 1000000000) end, C.green)
		add("+5 keys", function() self:server("keys", 5) end, C.yellow)
		add("+100 keys", function() self:server("keys", 100) end, C.yellow)
		add("No cash", function() self:server("give", "credits", -1e15) end, C.red)
		gap()
		for t = 1, 5 do
			add("Stage " .. t, function() self:server("setTier", t) end, C.blue)
		end
		add("Max machines", function() self:server("maxMachines") end, C.accent)
		add("Machines to 0", function() self:server("resetMachines") end)
		add("Plot upgrade cash", function() self:server("overhaulReady") end)
		for _, id in ipairs({ "cannon", "fuel", "cooling", "compressor", "rack" }) do
			add(id .. " +1", function() self:server("machine", id, 1) end)
			add(id .. " -1", function() self:server("machine", id, -1) end)
		end
		gap()
		-- the yard's looks: the neon stage (Midnight Garage pass) and the Hall of Prestige
		add("Neon pass on/off", function() self:server("midnightPass") end, C.purple)
		add("Look: stage", function() self:server("setLook", "stage") end)
		add("Look: prestige", function() self:server("setLook", "prestige") end, C.gold)
		for _, w in ipairs({ "Midnight", "Sunset", "Toxic" }) do
			add("Neon: " .. w, function() self:server("setLook", "midnight", w) end, C.purple)
		end
		add("Prestige +1", function() self:server("prestige", 1) end, C.gold)
		add("Prestige -1", function() self:server("prestige", -1) end)
		add("Open shop", function()
			self:toggle(false)
			workspace:SetAttribute("DebugPanel", "")
			task.wait()
			workspace:SetAttribute("DebugPanel", "shop")
		end, C.green)
		gap()
		add("All zones", function() self:server("allZones") end, C.teal)
		add("One of every tyre", function() self:server("allTyres") end, C.purple)
		for _, r in ipairs({ "Rare", "Epic", "Legendary", "Mythic", "Secret" }) do
			add("+1 " .. r, function() self:server("tyreOf", r) end, C.purple)
		end
		gap()
		for _, m in ipairs({ "plot", "tyres", "crates", "zones", "bench", "events", "settings", "yard" }) do
			add("Open " .. m, function()
				self:toggle(false)
				workspace:SetAttribute("DebugPanel", "")
				task.wait()
				workspace:SetAttribute("DebugPanel", m)
			end, C.orange)
		end
		gap()
		add("Save now", function() self:server("save") end, C.green)
		add("Wipe loop", function() self:server("wipeLoop") end, C.red)
		add("Print profile", function()
			local res = self:server("profile")
			if res and res.msg then print(game:GetService("HttpService"):JSONEncode(res.msg.v2 or {})) end
		end)
	elseif self.tab == "Run" then
		add("Launch (auto)", function()
			self:toggle(false)
			ctx.startRun(0, true)
		end, C.accent)
		for _, mode in ipairs({ "none", "ok", "good" }) do
			add("Bot: " .. mode, function()
				workspace:SetAttribute("DebugBot", mode)
				self:say("the next run is flown by the '" .. mode .. "' bot")
			end, C.blue)
		end
		add("Bot off", function()
			workspace:SetAttribute("DebugBot", nil)
			self:say("you fly the next run")
		end)
		add("Pace log", function()
			local on = not workspace:GetAttribute("PaceLog")
			workspace:SetAttribute("PaceLog", on or nil)
			self:say("pace log " .. (on and "on (workspace.PaceResult after a run)" or "off"))
		end)
		for _, k in ipairs({ 1, 2, 3 }) do
			add(("Start at %d m"):format(k * 1000), function()
				self:toggle(false)
				ctx.startRun(k * 1000 / Config.Physics.StudsToMetres, true)
			end, C.teal)
		end
		gap()
		add("Fill nitro", function()
			local sim = ctx.getSim()
			if sim then sim.nitro = sim.nitroMax else self:say("not on a run") end
		end, C.blue)
		add("Speed +100", function()
			local sim = ctx.getSim()
			if sim then sim.speed += 100 else self:say("not on a run") end
		end, C.green)
		add("Stop dead", function()
			local sim = ctx.getSim()
			if sim then sim.speed = 0 else self:say("not on a run") end
		end)
		add("End run", function()
			local sim = ctx.getSim()
			if sim then sim:bail() end
		end, C.red)
		add("Touch pads", function()
			local on = not (ctx.touch and ctx.touch.forced)
			if ctx.touch then ctx.touch:setForced(on) end
			self:say("touch controls forced " .. (on and "on" or "off"))
		end)
	else
		add("Stats overlay", function() self.overlay.Visible = not self.overlay.Visible end, C.blue)
		add("Daily popup", function()
			if ctx.showDaily then ctx.showDaily() else self:say("not wired") end
		end)
		add("Victory anim", function()
			self:toggle(false)
			if ctx.reactToRun then ctx.reactToRun({ reason = "stopped", hits = 0 }, { best = true }) end
		end)
		add("Sad sit anim", function()
			self:toggle(false)
			if ctx.reactToRun then ctx.reactToRun({ reason = "overheat", hits = 1 }, {}) end
		end)
		add("Play tutorial", function()
			self:toggle(false)
			if ctx.playTutorial then ctx.playTutorial() end
		end)
		add("Toast", function() if ctx.hub then ctx.hub:toast("THIS IS A TOAST", UI.Theme.good) end end)
		add("Hide UI", function()
			if ctx.setHubMode then ctx.setHubMode(false) end
			task.delay(4, function() if ctx.setHubMode then ctx.setHubMode(true) end end)
			self:say("UI hidden for 4 seconds")
		end)
		add("Respawn", function()
			local hum = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.Health = 0 end
		end, C.red)
	end
end

return DebugMenu
