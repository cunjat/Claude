--!strict
-- TYRE CANNON :: ProfilePanel (v2, 2026-10-16)
-- Your profile, opened from the level badge under your cash. Made for a player, not a spreadsheet:
--   YOU       your face, your rank and level with the XP bar, the next levels as a road of rewards
--             (keys, and the next rank), and six tiles of what you've done: best run, runs, tyres
--             found, prestige, yard style, titles
--   JOBS      today's three jobs, the week's one and the stage's trial, each with its bar and what
--             it pays (the same jobs as the card in the yard, which tucks itself away)
--   TITLES    every title (Config.Titles) with how far you are; EQUIP wears one
--   PRESTIGE  where you stand, what the next prestige gives (cash, keys, a perk, its colour), what
--             it still needs, and the perks you've kept; the button (a second tap confirms)
--   ProfilePanel.new(gui, V2) ; :setProfile(p) ; :open(tab?) ; :close() ; :isOpen() ; :show(tab)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)
local Game = require(Modules.Game)
local Goals = require(Modules.Goals)
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local C = Kit.C

local ProfilePanel = {}
ProfilePanel.__index = ProfilePanel

local W, H = 920, 560
local TABS = { { "you", "You" }, { "jobs", "Jobs" }, { "titles", "Titles" }, { "prestige", "Prestige" } }

local function stroke(slot: Frame, color: Color3)
	local edge = slot:FindFirstChild("Edge")
	local s = edge and edge:FindFirstChild("Rarity")
	if s then (s :: UIStroke).Color = color end
end

local function label(parent: Instance, text: string, size: number, color: Color3, x: number, y: number, w: number, h: number, align: string?, body: boolean?): TextLabel
	local l = Kit.text(text, size, color, if body then 1.5 else 2, if body then Kit.Body else nil)
	l.TextXAlignment = if align == "right" then Enum.TextXAlignment.Right elseif align == "center" then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	Kit.fit(l, size, math.max(8, math.floor(size * 0.55)))
	l.ZIndex = 8
	l.Parent = parent
	return l
end

function ProfilePanel.new(gui: ScreenGui, v2: Instance)
	local self = setmetatable({}, ProfilePanel)
	self.gui = gui
	self.R = v2
	local root = UI.mk("Frame", { Name = "Profile", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(W, H + 20),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui })
	UI.autoScale(root, 1280, 760)
	self.root = root
	local holder, face = Kit.card(UDim2.fromOffset(W, H), C.cream)
	holder.Parent = root
	Kit.header(face, "Profile", C.accent, 56)
	local close = Kit.close(52)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, 12, 0, -14)
	close.root.ZIndex = 40
	close.root.Parent = root
	close.onClick = function() self:close() end

	self.tabs = {}
	self.pages = {}
	for i, t in ipairs(TABS) do
		local id = t[1]
		local tb = Kit.tab(t[2], UDim2.fromOffset(206, 40), id == "you")
		tb.root.Position = UDim2.fromOffset(24 + (i - 1) * 218, 54)
		tb.root.ZIndex = 6
		tb.root.Parent = face
		tb.onClick = function() self:show(id) end
		self.tabs[id] = tb
		self.pages[id] = UI.mk("Frame", { Name = id, Position = UDim2.fromOffset(0, 106), Size = UDim2.new(1, 0, 1, -106), BackgroundTransparency = 1, Visible = id == "you", ZIndex = 4, Parent = face })
	end

	--==========================================================
	-- YOU
	--==========================================================
	local you = self.pages.you
	-- the hero card: face, name, rank, level, XP
	local hero = UI.mk("Frame", { Position = UDim2.fromOffset(24, 4), Size = UDim2.fromOffset(420, 196), BackgroundTransparency = 1, ZIndex = 5, Parent = you })
	self.heroSlot = Kit.slot(hero, C.gold, 5)
	local faceFrame = UI.mk("Frame", { Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(104, 104), BackgroundColor3 = C.well, ZIndex = 7, Parent = hero }, { UI.corner(52) })
	self.faceStroke = UI.mk("UIStroke", { Color = C.gold, Thickness = 4, Parent = faceFrame })
	self.headshot = UI.mk("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 8, Parent = faceFrame }, { UI.corner(52) })
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(Players.LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok then self.headshot.Image = img end
	end)
	-- the level coin on the face's corner
	local coin = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(110, 108), Size = UDim2.fromOffset(52, 52), BackgroundColor3 = C.ink, ZIndex = 9, Parent = hero }, { UI.corner(26) })
	self.coinStroke = UI.mk("UIStroke", { Color = C.gold, Thickness = 3, Parent = coin })
	self.coinLevel = Kit.text("1", 24, C.white, 2)
	self.coinLevel.Size = UDim2.fromScale(1, 1)
	Kit.fit(self.coinLevel, 24, 10)
	self.coinLevel.ZIndex = 10
	self.coinLevel.Parent = coin
	self.name = label(hero, string.upper(Players.LocalPlayer.DisplayName), 26, C.white, 140, 20, 266, 32)
	self.rank = label(hero, "ROOKIE", 18, C.gold, 140, 54, 266, 22)
	self.title = label(hero, "", 14, C.muted, 140, 80, 266, 18, nil, true)
	local track, fill = Kit.bar(388, 22, C.gold)
	track.Position = UDim2.fromOffset(16, 136)
	track.ZIndex = 7
	track.Parent = hero
	self.xpFill = fill
	self.xpText = label(hero, "", 14, C.white, 16, 162, 388, 18, "center", true)

	-- the road of the next levels' rewards
	local road = UI.mk("Frame", { Position = UDim2.fromOffset(24, 212), Size = UDim2.fromOffset(420, 220), BackgroundTransparency = 1, ZIndex = 5, Parent = you })
	Kit.slot(road, C.teal, 5)
	label(road, "COMING UP", 15, C.teal, 18, 12, 200, 18)
	label(road, "Every 5th level pays keys. Ranks change your badge.", 13, C.muted, 18, 32, 384, 16, nil, true)
	self.nextRank = label(road, "", 14, C.white, 18, 192, 384, 18, nil, true)
	local line = UI.mk("Frame", { Position = UDim2.fromOffset(42, 112), Size = UDim2.fromOffset(340, 6), BackgroundColor3 = C.bar, BorderSizePixel = 0, ZIndex = 6, Parent = road }, { UI.corner(3) })
	local _ = line
	self.nodes = {}
	for i = 1, 5 do
		local x = 42 + (i - 1) * 85
		local node = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, 115), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = C.well, ZIndex = 7, Parent = road }, { UI.corner(22) })
		local st = UI.mk("UIStroke", { Color = C.line, Thickness = 3, Parent = node })
		local lvl = Kit.text("", 18, C.white, 2)
		lvl.Size = UDim2.fromScale(1, 1)
		lvl.ZIndex = 8
		lvl.Parent = node
		local icon = UI.mk("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x - 10, 144), Size = UDim2.fromOffset(28, 28), BackgroundTransparency = 1, Image = Kit.Icon.key, ZIndex = 7, Parent = road })
		local reward = Kit.text("", 15, C.gold, 1.5)
		reward.TextXAlignment = Enum.TextXAlignment.Left
		reward.Position = UDim2.fromOffset(x + 4, 147)
		reward.Size = UDim2.fromOffset(40, 22)
		reward.ZIndex = 7
		reward.Parent = road
		local rank = Kit.text("", 12, C.white, 1.5)
		rank.Position = UDim2.fromOffset(x - 40, 176)
		rank.Size = UDim2.fromOffset(80, 30)
		rank.TextWrapped = true
		rank.ZIndex = 7
		rank.Parent = road
		local top = Kit.text("", 12, C.muted, 1.5, Kit.Body)
		top.Position = UDim2.fromOffset(x - 40, 70)
		top.Size = UDim2.fromOffset(80, 16)
		top.ZIndex = 7
		top.Parent = road
		self.nodes[i] = { node = node, stroke = st, lvl = lvl, icon = icon, reward = reward, rank = rank, top = top }
	end

	-- six tiles of what you've done
	local TILES = {
		{ "best", "BEST RUN", Kit.Icon.zones }, { "runs", "RUNS", Kit.Icon.cannon }, { "tyres", "TYRES FOUND", Kit.Icon.tyre },
		{ "prestige", "PRESTIGE", Kit.Icon.medal }, { "style", "YARD STYLE", Kit.Icon.plot }, { "titles", "TITLES", Kit.Icon.gold },
	}
	self.tiles = {}
	for i, t in ipairs(TILES) do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local tile = UI.mk("Frame", { Position = UDim2.fromOffset(462 + col * 216, 4 + row * 144), Size = UDim2.fromOffset(206, 136), BackgroundTransparency = 1, ZIndex = 5, Parent = you })
		Kit.slot(tile, Color3.fromRGB(70, 70, 76), 5)
		UI.mk("ImageLabel", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(58, 58), BackgroundTransparency = 1, Image = t[3], ZIndex = 7, Parent = tile })
		label(tile, t[2], 13, C.muted, 76, 20, 120, 16)
		local val = label(tile, "0", 30, C.white, 14, 74, 180, 36)
		local sub = label(tile, "", 12, C.gold, 14, 108, 180, 16, nil, true)
		self.tiles[t[1]] = { value = val, sub = sub }
	end

	--==========================================================
	-- JOBS
	--==========================================================
	local jobs = self.pages.jobs
	self.jobReset = label(jobs, "", 15, C.muted, 24, 4, 600, 20, nil, true)
	self.jobRows = {}
	for i = 1, 5 do
		local y = 30 + (i - 1) * 80
		local row = UI.mk("Frame", { Position = UDim2.fromOffset(24, y), Size = UDim2.fromOffset(872, 72), BackgroundTransparency = 1, ZIndex = 5, Parent = jobs })
		local slot = Kit.slot(row, Color3.fromRGB(70, 70, 76), 5)
		local tag = label(row, "", 12, C.yellow, 18, 8, 400, 16)
		local what = label(row, "", 20, C.white, 18, 26, 470, 26)
		local tr, fl = Kit.bar(300, 14, C.yellow, "off")
		tr.Position = UDim2.fromOffset(500, 18)
		tr.ZIndex = 7
		tr.Parent = row
		local prog = label(row, "", 13, C.white, 500, 36, 300, 18, nil, true)
		local pay = label(row, "", 18, C.gold, 806, 24, 34, 24, "right")
		local key = UI.mk("ImageLabel", { Position = UDim2.fromOffset(838, 20), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 1, Image = Kit.Icon.key, ZIndex = 8, Parent = row })
		self.jobRows[i] = { row = row, slot = slot, tag = tag, what = what, fill = fl, prog = prog, pay = pay, key = key }
	end

	--==========================================================
	-- TITLES
	--==========================================================
	local ti = self.pages.titles
	self.wearing = Kit.text("", 18, C.white, 2, Kit.Body)
	self.wearing.TextXAlignment = Enum.TextXAlignment.Left
	self.wearing.Position = UDim2.fromOffset(28, 4)
	self.wearing.Size = UDim2.fromOffset(600, 26)
	self.wearing.RichText = true
	self.wearing.ZIndex = 6
	self.wearing.Parent = ti
	local off = Kit.button("Take off", C.grey, UDim2.fromOffset(160, 34), 15)
	off.root.AnchorPoint = Vector2.new(1, 0)
	off.root.Position = UDim2.new(1, -24, 0, 0)
	off.root.ZIndex = 7
	off.root.Parent = ti
	off.onClick = function() self:equip("") end
	self.offBtn = off
	local list = UI.mk("ScrollingFrame", { Position = UDim2.fromOffset(20, 42), Size = UDim2.new(1, -40, 1, -58), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, ScrollingDirection = Enum.ScrollingDirection.Y, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 5, Parent = ti })
	UI.mk("UIGridLayout", { CellSize = UDim2.fromOffset(424, 76), CellPadding = UDim2.fromOffset(12, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	UI.mk("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 2), Parent = list })
	self.rows = {}
	for i, t in ipairs(Config.Titles) do
		local tier = Config.TitleTiers[t.tier]
		local row = UI.mk("Frame", { Name = t.id, LayoutOrder = i, BackgroundTransparency = 1, ZIndex = 6, Parent = list })
		local slot = Kit.slot(row, tier.colors[1], 6)
		local name = UI.titleLabel(t.id, 20)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(14, 8)
		name.Size = UDim2.fromOffset(260, 26)
		name.ZIndex = 9
		name.Parent = row
		local desc = Kit.text(t.desc or "", 14, C.muted, 1.5, Kit.Body)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Position = UDim2.fromOffset(14, 38)
		desc.Size = UDim2.fromOffset(262, 18)
		Kit.fit(desc, 14, 9)
		desc.ZIndex = 9
		desc.Parent = row
		local prog = Kit.text("", 13, C.gold, 1.5, Kit.Body)
		prog.TextXAlignment = Enum.TextXAlignment.Left
		prog.Position = UDim2.fromOffset(14, 55)
		prog.Size = UDim2.fromOffset(262, 16)
		prog.ZIndex = 9
		prog.Parent = row
		local b = Kit.button("Equip", C.green, UDim2.fromOffset(122, 40), 16)
		b.root.AnchorPoint = Vector2.new(1, 0.5)
		b.root.Position = UDim2.new(1, -12, 0.5, 0)
		b.root.ZIndex = 10
		b.root.Parent = row
		b.onClick = function() self:equip(t.id) end
		self.rows[t.id] = { row = row, slot = slot, prog = prog, btn = b, title = t }
	end

	--==========================================================
	-- PRESTIGE
	--==========================================================
	local pr = self.pages.prestige
	local medal = UI.mk("Frame", { Position = UDim2.fromOffset(24, 4), Size = UDim2.fromOffset(300, 300), BackgroundTransparency = 1, ZIndex = 5, Parent = pr })
	self.presSlot = Kit.slot(medal, C.accent, 5)
	UI.mk("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(130, 130), BackgroundTransparency = 1, Image = Kit.Icon.medal, ZIndex = 7, Parent = medal })
	self.presNow = label(medal, "", 34, C.white, 12, 152, 276, 42, "center")
	self.presBonus = label(medal, "", 16, C.gold, 12, 196, 276, 20, "center", true)
	self.presLook = label(medal, "", 14, C.muted, 12, 218, 276, 18, "center", true)
	self.perkLine = label(medal, "", 13, C.teal, 12, 246, 276, 40, "center", true)
	self.perkLine.TextWrapped = true
	-- what the next one gives
	label(pr, "NEXT PRESTIGE GIVES", 15, C.gold, 344, 6, 300, 18)
	self.gives = {}
	local GIVES = { { "cash", Kit.Icon.cash }, { "keys", Kit.Icon.key }, { "perk", Kit.Icon.medal }, { "look", Kit.Icon.plot } }
	for i, g in ipairs(GIVES) do
		local card = UI.mk("Frame", { Position = UDim2.fromOffset(344 + (i - 1) * 136, 30), Size = UDim2.fromOffset(128, 120), BackgroundTransparency = 1, ZIndex = 5, Parent = pr })
		Kit.slot(card, C.gold, 5)
		UI.mk("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(54, 54), BackgroundTransparency = 1, Image = g[2], ZIndex = 7, Parent = card })
		local big = label(card, "", 20, C.white, 6, 66, 116, 24, "center")
		local small = label(card, "", 12, C.muted, 6, 92, 116, 16, "center", true)
		self.gives[g[1]] = { big = big, small = small }
	end
	-- what it still needs
	label(pr, "STILL TO DO", 15, C.gold, 344, 162, 300, 18)
	self.needs = {}
	for i = 1, 4 do
		local y = 186 + (i - 1) * 32
		local box = UI.mk("Frame", { Position = UDim2.fromOffset(344, y + 3), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = C.well, ZIndex = 6, Parent = pr }, { UI.corner(6) })
		local st = UI.mk("UIStroke", { Color = C.line, Thickness = 2, Parent = box })
		local t = label(pr, "", 16, C.white, 376, y, 400, 28, nil, true)
		self.needs[i] = { box = box, stroke = st, text = t }
	end
	local btn = Kit.button("Prestige", C.accent, UDim2.fromOffset(536, 58), 22)
	btn.root.Position = UDim2.fromOffset(344, 324)
	btn.root.ZIndex = 7
	btn.root.Parent = pr
	btn.onClick = function() self:prestige() end
	self.presBtn = btn
	label(pr, "Prestige starts your yard again from nothing for good bonuses. Tyres, keys, decor and perks stay.", 13, C.muted, 24, 318, 300, 64, nil, true).TextWrapped = true
	return self
end

function ProfilePanel:show(id: string)
	for k, pg in pairs(self.pages) do
		pg.Visible = k == id
		self.tabs[k].setColor(if k == id then C.accent else C.grey)
	end
end

function ProfilePanel:setProfile(p)
	self.profile = p
	if not p or not p.v2 then return end
	local v = p.v2
	local cr = v.career or { level = 1, xp = 0, titles = {} }

	-- YOU
	local band = Game.levelBand(cr.level)
	stroke(self.heroSlot, band.color)
	self.faceStroke.Color = band.color
	self.coinStroke.Color = band.color
	self.coinLevel.Text = tostring(cr.level)
	self.rank.Text = ("%s  ·  LEVEL %d"):format(string.upper(band.name), cr.level)
	self.rank.TextColor3 = band.color
	local wearing = p.title ~= "" and Config.TitlesById[p.title]
	self.title.Text = if wearing then ("Wearing the title %s"):format(string.upper(wearing.name)) else "No title yet: earn one in Titles"
	local need = Game.xpToNext(cr.level)
	self.xpFill.Size = UDim2.fromScale(math.clamp(cr.xp / need, 0, 1), 1)
	self.xpText.Text = ("%s / %s XP to level %d"):format(Game.short(cr.xp), Game.short(need), cr.level + 1)
	for i, n in ipairs(self.nodes) do
		local l = cr.level + i
		n.lvl.Text = tostring(l)
		local lk = Game.levelKeys(l)
		n.reward.Text = if lk > 0 then "+" .. lk else ""
		n.icon.Visible = lk > 0
		local nb = Game.levelBand(l)
		local newRank = nb.from == l
		n.rank.Text = if newRank then string.upper(nb.name) else ""
		n.rank.TextColor3 = nb.color
		n.stroke.Color = if newRank then nb.color elseif Game.levelKeys(l) > 1 then C.gold else C.line
		n.top.Text = if i == 1 then "NEXT" else ""
	end
	local nextBand = nil
	for _, b in ipairs(Game.Levels.Bands) do
		if b.from > cr.level then nextBand = b break end
	end
	self.nextRank.Text = if nextBand then ('Next rank: <font color="#%s">%s</font> at level %d'):format(nextBand.color:ToHex(), string.upper(nextBand.name), nextBand.from) else "Top rank reached"
	self.nextRank.RichText = true
	local owned = 0
	for _, t in ipairs(Config.Titles) do
		local have = Game.titleProgress(p, t)
		if (if t.live then have >= 1 else (cr.titles and cr.titles[t.id] == true)) then owned += 1 end
	end
	local found = 0
	for _ in pairs(v.index or {}) do found += 1 end
	local T = self.tiles
	T.best.value.Text = if (v.bestEver or 0) > 0 then Game.metres(v.bestEver) else "No runs yet"
	T.best.sub.Text = "Your furthest launch"
	T.runs.value.Text = Game.short(v.runs or 0)
	T.runs.sub.Text = ("Stage %d: %s"):format(v.tier, Game.Tiers[v.tier].name)
	T.tyres.value.Text = ("%d / %d"):format(found, Game.TyreCount)
	T.tyres.sub.Text = ("Next bonus at %d found"):format((math.floor(found / Game.IndexEvery) + 1) * Game.IndexEvery)
	T.prestige.value.Text = if (p.prestige or 0) > 0 then ("P%d"):format(p.prestige) else "None yet"
	T.prestige.sub.Text = ("All cash x%s"):format(("%g"):format(Game.prestigeMult(p.prestige or 0)))
	T.style.value.Text = tostring(v.style or 0)
	T.style.sub.Text = ("Idle pay +%d%%"):format(math.floor((Game.styleBonus(v.style or 0) - 1) * 100 + 0.5))
	T.titles.value.Text = ("%d / %d"):format(owned, #Config.Titles)
	T.titles.sub.Text = if wearing then string.upper(wearing.name) else "None worn"

	-- JOBS
	local q = v.quests or {}
	local left = 86400 - os.time() % 86400
	self.jobReset.Text = ("New daily jobs in %dh %02dm.  Each pays %d minutes of your earnings; all three pay %d keys."):format(
		math.floor(left / 3600), math.floor(left % 3600 / 60), Goals.DailyReward.minutes, Goals.DailyBonus.keys)
	local entries = {}
	for _, g in ipairs(q.list or {}) do table.insert(entries, { g = g, tag = "TODAY", pay = Goals.DailyReward.minutes .. "m", icon = Kit.Icon.cash, color = C.yellow }) end
	if q.wk then table.insert(entries, { g = q.wk, tag = "THIS WEEK", pay = "+" .. Goals.WeeklyReward.keys, icon = Kit.Icon.key, color = C.purple }) end
	if v.trial and v.trial.k then
		table.insert(entries, { g = { k = v.trial.k, t = v.trial.t, h = v.trial.best, done = v.trial.done }, tag = "STAGE TRIAL  ·  UNLOCKS THE NEXT STAGE", pay = "", color = C.gold })
	end
	for i, r in ipairs(self.jobRows) do
		local e = entries[i]
		r.row.Visible = e ~= nil
		if e then
			local g = e.g
			stroke(r.slot, if g.done then C.green else e.color)
			r.tag.Text = e.tag .. (if g.done then "  ·  DONE" else "")
			r.tag.TextColor3 = if g.done then C.green else e.color
			r.what.Text = Goals.text(g)
			r.fill.Size = UDim2.fromScale(if g.done then 1 else math.clamp((g.h or 0) / math.max(g.t, 1e-6), 0, 1), 1)
			r.prog.Text = if g.done then "Done" else Goals.progressText(g, g.h)
			r.pay.Text = e.pay
			r.key.Visible = e.pay ~= ""
			if e.icon then r.key.Image = e.icon end
		end
	end

	-- TITLES
	self.wearing.Text = if wearing then ('Wearing: <font color="#ECC478">%s</font>'):format(string.upper(wearing.name)) else "Wearing: no title"
	self.offBtn.setEnabled(wearing ~= nil and wearing ~= false)
	local ownedT = 0
	for id, r in pairs(self.rows) do
		local t = r.title
		local have, goal = Game.titleProgress(p, t)
		local mine = if t.live then have >= 1 else (cr.titles and cr.titles[id] == true)
		if mine then ownedT += 1 end
		r.row.LayoutOrder = (if mine then 0 else 100) + (table.find(Config.Titles, t) or 0)
		if t.live then
			r.prog.Text = if mine then "YOURS WHILE YOU HOLD IT" else "LIVE: TAKE THE BOARD PLACE"
		else
			r.prog.Text = if mine then "UNLOCKED" else ("%s / %s"):format(Game.short(have), Game.short(goal))
		end
		r.prog.TextColor3 = if mine then C.green else C.gold
		if p.title == id then
			r.btn.setText("Equipped")
			r.btn.setColor(C.accent)
			r.btn.setEnabled(false)
		else
			r.btn.setText(if mine then "Equip" else "Locked")
			r.btn.setColor(if mine then C.green else C.grey)
			r.btn.setEnabled(mine == true)
		end
	end
	self.tabs.titles.setText(("Titles  %d/%d"):format(ownedT, #Config.Titles))

	-- PRESTIGE
	local level = p.prestige or 0
	local top = v.tier >= #Game.Tiers
	local maxed = Game.machinesMaxed(v)
	local cost = Game.prestigeCost(v)
	local afford = p.credits >= cost
	local capped = level >= Game.Prestige.Max
	local look = Game.prestigeLook(level)
	self.presNow.Text = if level > 0 then ("PRESTIGE %d"):format(level) else "NOT YET"
	self.presBonus.Text = ("All cash x%s for good"):format(("%g"):format(Game.prestigeMult(level)))
	self.presLook.Text = if look then ("Your colour: %s"):format(look.name) else "Your first prestige brings a colour"
	if look then stroke(self.presSlot, look.color) end
	local perks = {}
	for _, pk in ipairs(Game.Perks) do
		local lv = Game.perkLv(v, pk.id)
		if lv > 0 then table.insert(perks, ("%s %d"):format(pk.name, lv)) end
	end
	self.perkLine.Text = if #perks > 0 then "Perks: " .. table.concat(perks, ", ") else "Each prestige, you keep one of three perks"
	local nextLook = Game.prestigeLook(level + 1)
	self.gives.cash.big.Text = ("x%s"):format(("%g"):format(Game.prestigeMult(level + 1)))
	-- (2026-10-24) honest about the catch: prices climb with prestige too (Game.Prestige.PriceExp)
	self.gives.cash.small.Text = ("All cash, for good (prices x%s)"):format(("%.2f"):format(Game.prestigeMult(level + 1) ^ Game.Prestige.PriceExp):gsub("0+$", ""):gsub("%.$", ""))
	self.gives.keys.big.Text = ("+%d"):format(Game.Prestige.Keys + Game.Prestige.KeysPer * (level + 1))
	self.gives.keys.small.Text = "Keys"
	self.gives.perk.big.Text = "1 of 3"
	self.gives.perk.small.Text = "A perk to keep"
	self.gives.look.big.Text = if nextLook then nextLook.name else "-"
	self.gives.look.small.Text = if nextLook and nextLook ~= look then "A new colour" else "Your colour"
	local tr = v.trial
	local items = {
		{ top, ("Reach the Launch Complex (you're on stage %d of %d)"):format(v.tier, #Game.Tiers) },
		{ top and maxed, "Max the Cannon, Fuel Tank and Cooling there" },
		{ top and Game.trialDone(v), if top and tr and tr.k then "Pass its trial: " .. Goals.text({ k = tr.k, t = tr.t }) else "Pass the Launch Complex's trial" },
		{ afford, ("Have $%s"):format(Game.short(cost)) },
	}
	for i, n in ipairs(self.needs) do
		local ok, text = items[i][1], items[i][2]
		n.box.BackgroundColor3 = if ok then C.green else C.well
		n.stroke.Color = if ok then Color3.fromRGB(150, 230, 120) else C.line
		n.text.Text = text
		n.text.TextColor3 = if ok then C.muted else C.white
	end
	local ready = top and maxed and afford and Game.trialDone(v) and not capped
	if self.confirm then
		self.presBtn.setText("Tap again to prestige")
	else
		self.presBtn.setText(if capped then "Top Prestige" elseif ready then ("Prestige  $" .. Game.short(cost)) else "Not ready yet")
	end
	self.presBtn.setEnabled(ready)
end

function ProfilePanel:equip(id: string)
	local f = self.R:FindFirstChild("EquipTitle") :: RemoteFunction?
	if not f then return end
	local ok, res = pcall(function() return (f :: RemoteFunction):InvokeServer(id) end)
	if ok and type(res) == "table" and res.ok then
		local t = Config.TitlesById[id]
		Kit.callout(self.gui, if t then ("WEARING " .. string.upper(t.name)) else "TITLE OFF", C.accent, UDim2.fromScale(0.5, 0.2), 34)
	elseif ok and type(res) == "table" and res.err then
		Kit.callout(self.gui, string.upper(res.err), C.red, UDim2.fromScale(0.5, 0.2), 30)
	end
end

-- a second tap within 4 s confirms (it starts the yard again)
function ProfilePanel:prestige()
	if not self.confirm then
		self.confirm = true
		if self.profile then self:setProfile(self.profile) end
		task.delay(4, function()
			self.confirm = nil
			if self.profile then self:setProfile(self.profile) end
		end)
		return
	end
	self.confirm = nil
	local f = self.R:FindFirstChild("Prestige") :: RemoteFunction?
	if not f then return end
	local ok, res = pcall(function() return (f :: RemoteFunction):InvokeServer() end)
	if ok and type(res) == "table" and res.ok then
		self:close()
		Kit.callout(self.gui, "PRESTIGE " .. tostring(res.level) .. "!", C.accent, UDim2.fromScale(0.5, 0.35), 80)
		task.delay(0.5, function()
			Kit.callout(self.gui, ("ALL CASH x%s  ·  +%d KEYS"):format(("%g"):format(res.mult), res.keys), C.white, UDim2.fromScale(0.5, 0.45), 44)
		end)
	elseif ok and type(res) == "table" and res.err then
		Kit.callout(self.gui, string.upper(res.err), C.red, UDim2.fromScale(0.5, 0.18), 30)
	end
end

function ProfilePanel:open(tab: string?)
	if self.profile then self:setProfile(self.profile) end
	self:show(tab or "you")
	Kit.dim(self.gui, self.root, true)
	Kit.open(self.root)
end

function ProfilePanel:close()
	Kit.dim(self.gui, self.root, false)
	if self.root.Visible then Kit.close_(self.root) end
end

function ProfilePanel:isOpen(): boolean
	return self.root.Visible
end

return ProfilePanel
