--!strict
-- TYRE CANNON :: Panels / Career
-- The long game in one place: prestige, titles, token upgrades, today's
-- contracts, the quirk codex and the boards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Config = require(Modules.Config)
local Progress = require(Modules.Progress)
local Remotes = Root:WaitForChild("Remotes")
local UI = require(script.Parent.Parent.UI)
local RunPhoto = require(script.Parent.Parent.RunPhoto)
local T = UI.Theme

local BOARD_COLORS = {
	robux = Color3.fromRGB(120, 220, 160),
	distance = Color3.fromRGB(255, 160, 60),
	richest = Color3.fromRGB(246, 196, 64),
	spectators = Color3.fromRGB(120, 200, 255),
}

local function boardValue(key: string, v: number): string
	if key == "distance" then return UI.comma(v * Config.Physics.StudsToMetres) .. " m" end
	if key == "robux" then return "R$ " .. UI.comma(v) end
	if key == "spectators" then return UI.comma(v) end
	return UI.comma(v) .. " cr"
end

local SUBS = {
	Prestige = "Start again from nothing. Keep what nobody can buy.",
	Titles = "Earn the right, then spend tokens. Harder titles burn brighter.",
	Tokens = "Tokens come from prestige. Nothing bought here is ever wiped.",
	Contracts = "Three jobs a day. They pay the moment a run finishes one.",
	Boards = "Longest attempt and Robux are global. Richest is whoever's in this server.",
	Photos = "The top of your biggest jump from each run. The last six are kept.",
}

return function(hub)
	local m = hub:modal("Career", "CAREER", "", 1010, 680)
	local W = m.w
	local tab = "Prestige"
	local armedPrestige = false
	local boards: any = nil
	local boardsAt = 0
	local boardsGen = 0
	local refresh

	local _, setTab = hub:tabs(m.body, { "Prestige", "Titles", "Tokens", "Contracts", "Codex", "Boards", "Photos" }, 124, function(n)
		tab = n
		if n == "Boards" then boardsAt = 0 end
		refresh()
	end)
	local area = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 48), Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1, ZIndex = 11, Parent = m.body,
	})

	local function place(f: GuiObject, y: number)
		f.AnchorPoint = Vector2.new(0.5, 0)
		f.Position = UDim2.new(0.5, 0, 0, y)
	end

	local function centreLabel(l: GuiObject)
		if l:IsA("TextLabel") or l:IsA("TextButton") then
			l.TextXAlignment = Enum.TextXAlignment.Center
		end
	end

	--==========================================================
	local function prestige(p)
		local level = p.prestige or 0
		local atMax = level >= Config.Prestige.MaxLevel
		local cost = Config.PrestigeCost(level)
		local reward = Config.PrestigeReward(level + 1)
		local tokens = Config.Prestige.TokensFor(level + 1)

		local head = hub:card(area, W, 132, 1)
		place(head, 0)
		hub:line(head, "PRESTIGE " .. level, 44, "display", T.accent, 8, 48)
		hub:line(head, ("%d TOKEN%s IN THE BANK"):format(p.tokens or 0, (p.tokens or 0) == 1 and "" or "S"), 13, "monoBold", T.gold, 58, 16)
		local frac = atMax and 1 or math.clamp(p.credits / math.max(1, cost), 0, 1)
		local bg, fill = UI.bar(T.sunk, frac >= 1 and T.good or T.accent, 10)
		place(bg, 84)
		bg.Size = UDim2.fromOffset(W - 240, 10)
		bg.ZIndex = 13
		fill.ZIndex = 14
		fill.Size = UDim2.fromScale(frac, 1)
		bg.Parent = head
		hub:line(head, atMax and "Top of the ladder." or ("%s / %s credits"):format(UI.comma(p.credits), UI.comma(cost)),
			14, "monoBold", frac >= 1 and T.good or T.dim, 102, 20)

		local half = math.floor((W - 16) / 2)
		local function listCard(x: number, heading: string, color: Color3, items: { string }, order: number)
			local card = hub:card(area, half, 196, order)
			card.Position = UDim2.fromOffset(x, 146)
			hub:line(card, heading, 20, "display", color, 12, 24)
			for i, s in ipairs(items) do
				hub:line(card, s, 14, "body", T.dim, 44 + (i - 1) * 28, 24)
			end
		end
		listCard(0, "GONE", T.bad, {
			"Credits, garage upgrades and charms",
			"Anything bought with credits",
			"Toolboxes and personal records",
			"Road unlocks, unless you bought Standing Permit",
			Config.Prestige.KeepsCodex and "Nothing else" or "The quirk codex",
		}, 2)
		listCard(half + 16, "KEPT", T.good, {
			"Robux purchases, prestige rewards, token buys",
			"Titles, stats and lifetime board numbers",
			"Metal, boosters and your daily streak",
			"Prestige level and tokens",
		}, 3)

		local foot = hub:card(area, W, 164, 4)
		place(foot, 356)
		hub:line(foot, reward and ("NEXT: %s  +  %d TOKENS"):format(string.upper(reward.note), tokens) or ("NEXT: %d TOKENS"):format(tokens),
			20, "display", T.accent, 16, 26)
		hub:line(foot, "Granted on the spot and never taken back.", 14, "body", T.faint, 44, 20)
		local can = (not atMax) and p.credits >= cost
		local btn = UI.button(atMax and "MAXED" or (armedPrestige and "PRESS AGAIN TO CONFIRM" or "PRESTIGE"),
			can and (armedPrestige and "bad" or "primary") or "off", 340, 54)
		btn.AnchorPoint = Vector2.new(0.5, 1)
		btn.Position = UDim2.new(0.5, 0, 1, -18)
		btn.ZIndex = 13
		btn.Parent = foot
		btn.Activated:Connect(function()
			if not can then
				hub:toast(atMax and "Top of the ladder." or ("Need %s more credits."):format(UI.comma(cost - p.credits)), T.bad)
				return
			end
			if not armedPrestige then
				armedPrestige = true
				refresh()
				task.delay(4, function()
					if armedPrestige then
						armedPrestige = false
						if hub:isOpen("Career") then refresh() end
					end
				end)
				return
			end
			armedPrestige = false
			local res = hub:call("Prestige")
			if res and res.ok then
				hub:toast(("PRESTIGE %d  +%d TOKENS"):format(res.level, res.tokens or 0), T.accent)
				if res.reward then task.delay(0.6, function() hub:toast(string.upper(res.reward), T.good) end) end
			end
		end)
	end

	--==========================================================
	local function titles(p)
		local wearing = hub:card(area, W, 64, 1)
		place(wearing, 0)
		hub:line(wearing, ("WEARING  ·  %d TOKEN%s"):format(p.tokens or 0, (p.tokens or 0) == 1 and "" or "S"), 12, "monoBold", T.faint, 6, 14)
		if p.title ~= "" and p.title ~= nil then
			local cur = UI.titleLabel(p.title, 26)
			place(cur, 24)
			cur.Size = UDim2.new(1, -40, 0, 32)
			centreLabel(cur)
			cur.ZIndex = 13
			cur.Parent = wearing
		else
			hub:line(wearing, "Nothing yet", 20, "bodySemi", T.faint, 26, 28)
		end

		local cellW = math.floor((W - 36) / 3)
		local grid = hub:scroll(area, UDim2.fromOffset(0, 76), UDim2.new(1, 0, 1, -76), UI.grid(cellW, 140, 12))
		local order = {}
		for i, name in ipairs(Config.TitleTierOrder) do order[name] = i end
		local list = table.clone(Config.Titles)
		table.sort(list, function(a, b)
			if order[a.tier] ~= order[b.tier] then return order[a.tier] < order[b.tier] end
			return a.name < b.name
		end)
		for i, t in ipairs(list) do
			local st = Progress.titleState(p, t)
			local tier = Config.TitleTiers[t.tier]
			local card = hub:card(grid, 0, 0, i, st.equipped and T.accent or nil)
			if not st.unlocked and not st.owned then card.BackgroundTransparency = 0.55 end
			local lbl = UI.titleLabel(t.id, 22)
			place(lbl, 8)
			lbl.Size = UDim2.new(1, -24, 0, 26)
			centreLabel(lbl)
			lbl.ZIndex = 13
			lbl.Parent = card
			local chip = UI.chip(t.tier, tier.colors[1])
			place(chip, 38)
			chip.ZIndex = 13
			chip.Parent = card
			hub:line(card, Progress.titleHow(t), 13, "body", T.dim, 62, 18).TextTruncate = Enum.TextTruncate.AtEnd
			if not t.live and not st.owned then
				local bg, fill = UI.bar(T.sunk, st.unlocked and T.good or T.accent, 4)
				place(bg, 84)
				bg.Size = UDim2.new(1, -40, 0, 4)
				bg.ZIndex = 13
				fill.ZIndex = 14
				fill.Size = UDim2.fromScale(math.clamp(st.current / math.max(1, st.goal), 0, 1), 1)
				bg.Parent = card
			end
			local label, style, action
			if st.equipped then
				label, style, action = "TAKE OFF", "ghost", function() hub:call("EquipTitle", "") end
			elseif st.owned then
				label, style, action = "WEAR", "primary", function() hub:call("EquipTitle", t.id) end
			elseif t.live then
				label, style = "HOLD THE RANK", "off"
			elseif st.unlocked then
				label = ("BUY  %d TOKEN%s"):format(st.cost, st.cost == 1 and "" or "S")
				style = (p.tokens or 0) >= st.cost and "primary" or "off"
				action = function()
					local res = hub:call("BuyTitle", t.id)
					if res and res.ok then hub:toast(string.upper(t.name) .. " IS YOURS", T.good) end
				end
			else
				label, style = ("%s / %s"):format(UI.comma(math.min(st.current, st.goal)), UI.comma(st.goal)), "off"
			end
			local btn = UI.button(label, style, 170, 30)
			btn.AnchorPoint = Vector2.new(0.5, 1)
			btn.Position = UDim2.new(0.5, 0, 1, -10)
			btn.TextSize = 14
			btn.ZIndex = 13
			btn.Parent = card
			if action then btn.Activated:Connect(action) end
		end
	end

	--==========================================================
	local function tokenShop(p)
		local grid = hub:scroll(area, UDim2.new(), UDim2.fromScale(1, 1), UI.grid(math.floor((W - 36) / 3), 170, 12))
		for i, t in ipairs(Config.TokenShop) do
			local have = (p.tokenUpgrades or {})[t.id] or 0
			local maxed = have >= t.max
			local card = hub:card(grid, 0, 0, i, maxed and T.good or nil)
			hub:line(card, string.upper(t.name), 18, "display", T.text, 10, 22)
			local d = hub:line(card, t.desc, 13, "body", T.dim, 36, 50)
			d.TextYAlignment = Enum.TextYAlignment.Top
			hub:line(card, ("OWNED %d / %d"):format(have, t.max), 12, "monoBold", T.faint, 90, 16)
			local afford = (p.tokens or 0) >= t.cost and not maxed
			local b = UI.button(maxed and "MAXED" or ("%d TOKEN%s"):format(t.cost, t.cost == 1 and "" or "S"), afford and "primary" or "off", 200, 36)
			b.AnchorPoint = Vector2.new(0.5, 1)
			b.Position = UDim2.new(0.5, 0, 1, -12)
			b.TextSize = 15
			b.ZIndex = 13
			b.Parent = card
			b.Activated:Connect(function()
				local res = hub:call("BuyToken", t.id)
				if res and res.ok then hub:toast(string.upper(t.name), T.good) end
			end)
		end
	end

	--==========================================================
	local function contracts(p)
		local left = 86400 - (os.time() % 86400)
		local reset = UI.text(("NEW JOBS IN %dH %02dM"):format(math.floor(left / 3600), math.floor(left % 3600 / 60)), 13, "monoBold", T.faint)
		place(reset, 4)
		reset.Size = UDim2.new(1, 0, 0, 18)
		reset.TextXAlignment = Enum.TextXAlignment.Center
		reset.ZIndex = 12
		reset.Parent = area
		local list = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.new(1, 0, 0, 330),
			BackgroundTransparency = 1, ZIndex = 11, Parent = area,
		}, { UI.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center) })
		local jobs = (p.contracts and p.contracts.list) or {}
		for i, c in ipairs(jobs) do
			local row = hub:card(list, W - 160, 100, i, c.done and T.good or nil)
			local state = UI.chip(c.done and "done" or "open", c.done and T.good or T.dim)
			place(state, 10)
			state.ZIndex = 13
			state.Parent = row
			hub:line(row, Progress.contractText(c), 19, "bodySemi", c.done and T.dim or T.text, 36, 24)
			hub:line(row, UI.money(c.reward), 15, "monoBold", c.done and T.faint or T.accent, 66, 20)
		end
		if #jobs == 0 then
			local l = UI.text("No jobs today. Check back after the reset.", 16, "body", T.dim)
			l.Size = UDim2.new(1, 0, 0, 24)
			l.TextXAlignment = Enum.TextXAlignment.Center
			l.ZIndex = 12
			l.Parent = list
		end
		local claimable, index = Progress.dailyState(p)
		local daily = UI.button(claimable and ("DAILY STREAK  ·  DAY %d READY"):format(index) or "DAILY STREAK", claimable and "good" or "ghost", 340, 48)
		daily.AnchorPoint = Vector2.new(0.5, 1)
		daily.Position = UDim2.new(0.5, 0, 1, -8)
		daily.ZIndex = 12
		daily.Parent = area
		daily.Activated:Connect(function() hub:open("Daily") end)
	end

	--==========================================================
	local function codex(p)
		local found = 0
		for _, perk in ipairs(Config.Perks) do
			if p.codex[perk.id] then found += 1 end
		end
		m.sub.Text = ("%d of %d quirks found. The rare ones float higher and further out."):format(found, #Config.Perks)
		local grid = hub:scroll(area, UDim2.new(), UDim2.fromScale(1, 1), UI.grid(226, 128, 10))
		local sorted = table.clone(Config.Perks)
		table.sort(sorted, function(a, b)
			local ra, rb = Config.Rarity[a.rarity].order, Config.Rarity[b.rarity].order
			if ra ~= rb then return ra < rb end
			return a.name < b.name
		end)
		for i, perk in ipairs(sorted) do
			local info = Config.Rarity[perk.rarity]
			local known = p.codex[perk.id] == true
			local tile = hub:card(grid, 0, 0, i, known and info.color or nil)
			if not known then tile.BackgroundTransparency = 0.6 end
			hub:line(tile, known and string.upper(perk.name) or "???", 17, "display", known and info.color or T.faint, 8, 22)
			hub:line(tile, string.upper(perk.rarity), 11, "monoBold", T.faint, 30, 14)
			local d = hub:line(tile, known and perk.desc or "Not found yet.", 13, "body", known and T.dim or T.faint, 48, 50)
			d.TextYAlignment = Enum.TextYAlignment.Top
			if known then
				local bits = {}
				if (perk.duration or 0) > 0 then table.insert(bits, perk.duration .. "s") end
				if perk.instant and perk.instant.up then table.insert(bits, "+" .. perk.instant.up .. " lift") end
				if perk.instant and perk.instant.fwd then table.insert(bits, "+" .. perk.instant.fwd .. " push") end
				hub:line(tile, table.concat(bits, "  "), 11, "monoBold", info.color, 104, 14)
			end
		end
	end

	--==========================================================
	local function drawBoards()
		local cols = UI.mk("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 11, Parent = area,
		}, { UI.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center) })
		if type(boards) ~= "table" then
			local l = UI.text("Fetching the boards...", 16, "body", T.dim)
			l.Size = UDim2.new(1, 0, 0, 24)
			l.TextXAlignment = Enum.TextXAlignment.Center
			l.ZIndex = 12
			l.Parent = cols
			return
		end
		local count = math.max(1, #boards)
		local cw = math.floor((W - 12 * (count - 1)) / count)
		local h = m.h - 56
		for i, b in ipairs(boards) do
			local col = hub:card(cols, cw, h, i)
			local color = BOARD_COLORS[b.key] or T.text
			hub:line(col, b.title, 18, "display", color, 10, 24)
			local rows = UI.mk("Frame", {
				Position = UDim2.fromOffset(8, 42), Size = UDim2.new(1, -16, 1, -50), BackgroundTransparency = 1, ZIndex = 13, Parent = col,
			}, { UI.list(Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Center) })
			if #b.rows == 0 then
				local l = UI.text("Nobody yet.", 14, "body", T.faint)
				l.Size = UDim2.new(1, 0, 0, 24)
				l.TextXAlignment = Enum.TextXAlignment.Center
				l.ZIndex = 14
				l.Parent = rows
			end
			for r, row in ipairs(b.rows) do
				if r > 15 then break end
				local f = UI.mk("Frame", {
					Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = T.sunk, BackgroundTransparency = r <= 3 and 0.2 or 0.7,
					BorderSizePixel = 0, LayoutOrder = r, ZIndex = 14, Parent = rows,
				})
				UI.corner(2).Parent = f
				local rank = UI.text(tostring(r), 13, "monoBold", r <= 3 and color or T.faint)
				rank.Position = UDim2.fromOffset(6, 0)
				rank.Size = UDim2.fromOffset(22, 28)
				rank.ZIndex = 15
				rank.Parent = f
				local nm = UI.text(row.name, 14, "bodySemi", T.text)
				nm.Position = UDim2.fromOffset(28, 0)
				nm.Size = UDim2.new(0.55, -28, 0, 28)
				nm.TextTruncate = Enum.TextTruncate.AtEnd
				nm.ZIndex = 15
				nm.Parent = f
				local v = UI.text(boardValue(b.key, row.value), 12, "monoBold", color)
				v.AnchorPoint = Vector2.new(1, 0)
				v.Position = UDim2.new(1, -6, 0, 0)
				v.Size = UDim2.new(0.45, 0, 0, 28)
				v.TextXAlignment = Enum.TextXAlignment.Right
				v.ZIndex = 15
				v.Parent = f
			end
		end
	end

	local function boardTab()
		drawBoards()
		if os.clock() - boardsAt < 20 then return end
		boardsAt = os.clock()
		boardsGen += 1
		local gen = boardsGen
		task.spawn(function()
			local ok, res = pcall(function() return (Remotes :: any).Leaderboards:InvokeServer() end)
			if gen ~= boardsGen then return end
			if ok and type(res) == "table" then boards = res end
			if tab == "Boards" and hub:isOpen("Career") then
				hub:clear(area)
				drawBoards()
			end
		end)
	end

	--==========================================================
	-- photos: prints of the best moment from recent runs
	--==========================================================
	local function photos(p)
		local list = p.photos or {}
		if #list == 0 then
			local l = UI.text("Nothing yet. Every run keeps a still of its biggest jump.", 16, "body", T.dim)
			l.Size = UDim2.new(1, 0, 0, 60)
			l.TextXAlignment = Enum.TextXAlignment.Center
			l.ZIndex = 12
			l.Parent = area
			return
		end
		local grid = UI.mk("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 12, Parent = area,
		}, { UI.grid(300, 250, 12) })
		for i, ph in ipairs(list) do
			local print = UI.mk("Frame", { Size = UDim2.fromOffset(300, 250), BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 12, Parent = grid })
			UI.plate("slot", { Size = UDim2.fromScale(1, 1), ZIndex = 12, Parent = print })
			local vpf = UI.mk("ViewportFrame", {
				Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(280, 170), BackgroundTransparency = 0,
				ZIndex = 13, Parent = print,
			})
			local ok = pcall(function() RunPhoto.render(vpf, ph) end)
			if not ok then vpf.BackgroundColor3 = T.sunk end
			local top, bottom = RunPhoto.caption(ph)
			local a = UI.text(top, 14, "displayMed", T.text)
			a.Position = UDim2.fromOffset(14, 186)
			a.Size = UDim2.fromOffset(272, 18)
			a.TextTruncate = Enum.TextTruncate.AtEnd
			a.ZIndex = 13
			a.Parent = print
			local b = UI.text(bottom, 12, "monoBold", T.dim)
			b.Position = UDim2.fromOffset(14, 205)
			b.Size = UDim2.fromOffset(272, 16)
			b.ZIndex = 13
			b.Parent = print
			local when = UI.text(ph.at and ph.at > 0 and string.upper(os.date("%d %b  %H:%M", ph.at)) or "", 11, "mono", T.faint)
			when.Position = UDim2.fromOffset(14, 225)
			when.Size = UDim2.fromOffset(200, 14)
			when.ZIndex = 13
			when.Parent = print
			if ph.best then
				local pb = UI.chip("personal best", T.accent)
				pb.AnchorPoint = Vector2.new(1, 0)
				pb.Position = UDim2.new(1, -12, 0, 223)
				pb.ZIndex = 13
				pb.Parent = print
			end
		end
	end

	--==========================================================
	refresh = function()
		setTab(tab)
		m.sub.Text = SUBS[tab] or ""
		local p = hub.profile
		if not p then return end
		hub:clear(area)
		if tab == "Prestige" then prestige(p)
		elseif tab == "Titles" then titles(p)
		elseif tab == "Tokens" then tokenShop(p)
		elseif tab == "Contracts" then contracts(p)
		elseif tab == "Codex" then codex(p)
		elseif tab == "Photos" then photos(p)
		else boardTab() end
	end

	hub:register("Career", {
		frame = m.frame,
		refresh = refresh,
		onOpen = function() boardsAt = 0 end,
		onClose = function() armedPrestige = false end,
	})
	-- deep links from older code paths
	hub.careerTab = function(name: string)
		tab = name
	end
end
