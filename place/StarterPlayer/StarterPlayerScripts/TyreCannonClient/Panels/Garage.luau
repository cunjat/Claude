--!strict
-- TYRE CANNON :: Panels / Garage
-- Everything you take into a run: upgrades, which road, and what's armed.
-- The run itself starts from the lever.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Config"))
local UI = require(script.Parent.Parent.UI)
local T = UI.Theme

local function fmtStat(u, level: number): string
	local v = Config.StatAt(u.id, level)
	if u.percent then
		local pct = v * 100
		if math.abs(pct) < 25 then return ("%.1f%%"):format(pct) end
		return ("%d%%"):format(math.round(pct))
	end
	if math.abs(v - math.floor(v)) < 0.001 then return ("%d%s"):format(v, u.unit) end
	return ("%.1f%s"):format(v, u.unit)
end

local SUBS = {
	Upgrades = "Credits in, speed out. The rig fires you. The tyre is you.",
	Roads = "Pick a road. Rougher ground pays more. Pull the lever in your yard to go.",
	Loadout = "What burns on your next launch.",
}

return function(hub)
	local m = hub:modal("Garage", "GARAGE", "", 980, 680)
	local tab = "Upgrades"
	local refresh
	local _, setTab = hub:tabs(m.body, { "Upgrades", "Roads", "Loadout" }, 150, function(n)
		tab = n
		refresh()
	end)
	local area = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 48), Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1, ZIndex = 11, Parent = m.body,
	})
	local toolSlot = 1

	local function upgrades(p)
		local colW = math.floor((m.w - 20) / 2)
		for c, tree in ipairs({ "Rig", "Tyre" }) do
			local col = hub:scroll(area, UDim2.new(c == 1 and 0 or 0.5, c == 1 and 0 or 10, 0, 30), UDim2.new(0.5, -10, 1, -30),
				UI.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center))
			local head = UI.text(tree == "Rig" and "THE RIG" or "THE TYRE", 18, "display", T.text)
			head.Position = UDim2.new(c == 1 and 0 or 0.5, c == 1 and 0 or 10, 0, 0)
			head.Size = UDim2.new(0.5, -10, 0, 26)
			head.TextXAlignment = Enum.TextXAlignment.Center
			head.ZIndex = 12
			head.Parent = area
			local ups = {}
			for _, u in ipairs(Config.Upgrades) do
				if u.tree == tree then table.insert(ups, u) end
			end
			table.sort(ups, function(a, b) return a.order < b.order end)
			for i, u in ipairs(ups) do
				local level = p.upgrades[u.id] or 0
				local maxed = level >= u.maxLevel
				local cost = Config.UpgradeCost(u.id, level)
				local row = hub:card(col, colW - 24, 92, i, maxed and T.accentDeep or nil)
				hub:line(row, string.upper(u.name), 17, "display", T.text, 8, 22)
				hub:line(row, u.desc, 13, "body", T.dim, 30, 18).TextTruncate = Enum.TextTruncate.AtEnd
				local pipW = math.max(6, math.floor(160 / u.maxLevel) - 3)
				local pips = UI.mk("Frame", {
					AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(u.maxLevel * (pipW + 3), 6),
					BackgroundTransparency = 1, ZIndex = 13, Parent = row,
				}, { UI.list(Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Center) })
				for k = 1, u.maxLevel do
					local pip = UI.mk("Frame", {
						Size = UDim2.fromOffset(pipW, 6), BackgroundColor3 = (k <= level) and T.accent or T.sunk,
						BorderSizePixel = 0, LayoutOrder = k, ZIndex = 13, Parent = pips,
					})
					UI.corner(1).Parent = pip
				end
				local stat = hub:line(row, maxed and (fmtStat(u, level) .. "  MAXED")
					or ("%s  →  %s"):format(fmtStat(u, level), fmtStat(u, level + 1)), 13, "monoBold", maxed and T.good or T.dim, 64, 18)
				stat.Size = UDim2.new(1, -150, 0, 18)
				stat.AnchorPoint = Vector2.new(0, 0)
				stat.Position = UDim2.fromOffset(12, 66)
				stat.TextXAlignment = Enum.TextXAlignment.Left
				if not maxed then
					local buy = UI.button(UI.comma(cost) .. " CR", p.credits >= cost and "primary" or "off", 126, 30)
					buy.AnchorPoint = Vector2.new(1, 1)
					buy.Position = UDim2.new(1, -10, 1, -8)
					buy.TextSize = 14
					buy.ZIndex = 13
					buy.Parent = row
					buy.Activated:Connect(function()
						local res = hub:call("BuyUpgrade", u.id)
						if res and res.ok then hub:toast(("%s  LV %d"):format(string.upper(u.name), res.level), T.good) end
					end)
				end
			end
		end
	end

	local function roads(p)
		local row = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.new(1, 0, 0, 240),
			BackgroundTransparency = 1, ZIndex = 11, Parent = area,
		}, { UI.list(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center) })
		local cw = math.floor((m.w - 14 * (#Config.Tracks - 1)) / #Config.Tracks) - 6
		for i, t in ipairs(Config.Tracks) do
			local unlocked = p.tracks[t.id] == true
			local selected = p.selected == t.id
			local rec = p.records[t.id]
			local card = hub:card(row, cw, 240, i, selected and T.accent or nil)
			card.ClipsDescendants = true
			local band = UI.mk("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = t.ground, BorderSizePixel = 0, ZIndex = 12, Parent = card })
			UI.mk("UIGradient", { Color = ColorSequence.new(t.ground, t.deepGround or t.ground), Parent = band })
			UI.mk("Frame", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = t.accent, BorderSizePixel = 0, ZIndex = 13, Parent = card })
			local mult = UI.chip(("x%.2f credits"):format(t.creditMult), T.text)
			mult.AnchorPoint = Vector2.new(0.5, 0)
			mult.Position = UDim2.new(0.5, 0, 0, 16)
			mult.ZIndex = 14
			mult.Parent = card
			hub:line(card, string.upper(t.name), 21, "display", T.text, 62, 26)
			hub:line(card, t.subtitle, 13, "body", T.dim, 90, 52)
			hub:line(card, (rec and rec.dist > 0) and ("BEST %s m"):format(UI.comma(rec.dist * Config.Physics.StudsToMetres)) or "NO RECORD YET", 12, "monoBold", T.faint, 146, 16)
			local btn
			if selected then
				btn = UI.button("SELECTED", "off", cw - 28, 44)
			elseif unlocked then
				btn = UI.button("PICK THIS ROAD", "primary", cw - 28, 44)
				btn.Activated:Connect(function() hub:call("SelectTrack", t.id) end)
			else
				btn = UI.button(("OPEN IT  %s CR"):format(UI.comma(t.cost)), p.credits >= t.cost and "good" or "off", cw - 28, 44)
				btn.Activated:Connect(function()
					local res = hub:call("SelectTrack", t.id)
					if res and res.ok then hub:toast(string.upper(t.name) .. " IS OPEN", T.good) end
				end)
			end
			btn.TextSize = 17
			btn.AnchorPoint = Vector2.new(0.5, 1)
			btn.Position = UDim2.new(0.5, 0, 1, -14)
			btn.ZIndex = 13
			btn.Parent = card
		end
		local note = UI.text("The lever next to your rig starts the run.", 16, "bodySemi", T.dim)
		note.AnchorPoint = Vector2.new(0.5, 0)
		note.Position = UDim2.new(0.5, 0, 0, 270)
		note.Size = UDim2.new(1, 0, 0, 22)
		note.TextXAlignment = Enum.TextXAlignment.Center
		note.ZIndex = 12
		note.Parent = area
	end

	local function loadout(p)
		local sf = hub:scroll(area, UDim2.new(), UDim2.fromScale(1, 1), UI.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center))

		-- charms
		local armed = {}
		for _, id in ipairs(p.loadout or {}) do armed[id] = true end
		local _, charmBox = hub:section(sf, ("CHARMS  ·  %d / 2 ARMED"):format(#(p.loadout or {})), 1, UI.grid(210, 118, 10))
		for i, c in ipairs(Config.Charms) do
			local owned = p.charms[c.id] or 0
			local card = hub:card(charmBox, 0, 0, i, armed[c.id] and c.fx or nil)
			if owned <= 0 and not armed[c.id] then card.BackgroundTransparency = 0.6 end
			hub:line(card, string.upper(c.name), 15, "display", c.fx, 8, 20)
			hub:line(card, ("CARRYING %d"):format(owned), 12, "monoBold", T.faint, 30, 16)
			hub:line(card, c.desc, 12, "body", T.dim, 46, 30)
			local arm = UI.button(armed[c.id] and "ARMED" or (owned > 0 and "ARM" or "BUY IN SHOP"), armed[c.id] and c.fx or (owned > 0 and "ghost" or "off"), 180, 28)
			arm.AnchorPoint = Vector2.new(0.5, 1)
			arm.Position = UDim2.new(0.5, 0, 1, -8)
			arm.TextSize = 13
			arm.ZIndex = 13
			arm.Parent = card
			arm.Activated:Connect(function()
				if owned <= 0 and not armed[c.id] then
					hub:toast("Buy one in the Shop first.", T.bad)
					return
				end
				local list = {}
				for _, id in ipairs(p.loadout or {}) do
					if id ~= c.id then table.insert(list, id) end
				end
				if not armed[c.id] then
					if #list >= 2 then table.remove(list, 1) end
					table.insert(list, c.id)
				end
				hub:call("SetLoadout", list)
			end)
		end

		-- boosters
		local _, boostBox = hub:section(sf, "BOOSTERS", 2, UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center))
		local any = false
		for i, b in ipairs(Config.Boosters) do
			local left = (p.boosters and p.boosters[b.id]) or 0
			if left > 0 then
				any = true
				local chip = UI.chip(("%s  %s"):format(b.name, b.kind == "timed" and UI.clock(left) or ("x" .. left)), b.color)
				chip.LayoutOrder = i
				chip.ZIndex = 13
				chip.Parent = boostBox
			end
		end
		if not any then
			local l = UI.text("Nothing running. Boosters are in the Shop.", 14, "body", T.faint)
			l.Size = UDim2.new(1, 0, 0, 20)
			l.TextXAlignment = Enum.TextXAlignment.Center
			l.ZIndex = 13
			l.Parent = boostBox
		end

		-- toolboxes
		local boxes = p.toolboxes or {}
		local equipped = p.equipped or {}
		local byUid = {}
		for _, tb in ipairs(boxes) do byUid[tb.uid] = tb end
		local _, slotBox = hub:section(sf, "TOOLBOXES", 3, UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center))
		for slot = 1, Config.Toolbox.Slots do
			local uid = equipped[slot] or equipped[tostring(slot)]
			local tb = uid and byUid[uid]
			local kind = tb and Config.ToolboxKindsById[tb.kind]
			local rar = tb and Config.ToolboxRaritiesById[tb.rarity]
			local chosen = toolSlot == slot
			local b = UI.mk("TextButton", {
				Size = UDim2.fromOffset(250, 80), BackgroundColor3 = T.sunk, BorderSizePixel = 0,
				AutoButtonColor = false, Text = "", LayoutOrder = slot, ZIndex = 13, Parent = slotBox,
			})
			UI.corner(4).Parent = b
			UI.stroke(chosen and T.accent or (rar and rar.color or T.line), chosen and 2 or 1).Parent = b
			hub:line(b, "SLOT " .. slot, 11, "monoBold", chosen and T.accent or T.faint, 8, 14)
			hub:line(b, tb and ("%s %s"):format(string.upper(rar.name), string.upper(kind.name)) or "EMPTY", 16, "display", tb and rar.color or T.faint, 24, 20)
			hub:line(b, tb and ("+%d%% %s"):format(math.floor(rar.bonus * (tb.q or 1) * 100 + 0.5), kind.label) or "pick this slot, then a box", 12, "body", T.dim, 48, 16)
			b.Activated:Connect(function()
				toolSlot = slot
				refresh()
			end)
			if tb then
				local clear = UI.button("X", "ghost", 24, 24)
				clear.AnchorPoint = Vector2.new(1, 0)
				clear.Position = UDim2.new(1, -6, 0, 6)
				clear.TextSize = 12
				clear.ZIndex = 14
				clear.Parent = b
				clear.Activated:Connect(function() hub:call("EquipToolbox", slot, nil) end)
			end
		end
		local _, drawer = hub:section(sf, #boxes > 0 and "FOUND ON THE ROAD" or "NOTHING FOUND YET", 4, UI.grid(210, 96, 10))
		local inUse = {}
		for _, u in pairs(equipped) do inUse[u] = true end
		local sorted = table.clone(boxes)
		table.sort(sorted, function(a, b)
			local ra = Config.ToolboxRaritiesById[a.rarity].bonus * (a.q or 1)
			local rb = Config.ToolboxRaritiesById[b.rarity].bonus * (b.q or 1)
			if ra ~= rb then return ra > rb end
			return a.uid < b.uid
		end)
		for i, tb in ipairs(sorted) do
			local kind = Config.ToolboxKindsById[tb.kind]
			local rar = Config.ToolboxRaritiesById[tb.rarity]
			local card = hub:card(drawer, 0, 0, i, rar.color)
			hub:line(card, string.upper(kind.name), 15, "display", rar.color, 8, 20)
			hub:line(card, ("+%d%% %s  ·  Q%.2f"):format(math.floor(rar.bonus * (tb.q or 1) * 100 + 0.5), kind.label, tb.q or 1), 12, "monoBold", T.dim, 30, 16)
			local fit = UI.button(inUse[tb.uid] and "FITTED" or ("FIT TO SLOT " .. toolSlot), inUse[tb.uid] and "off" or rar.color, 180, 28)
			fit.AnchorPoint = Vector2.new(0.5, 1)
			fit.Position = UDim2.new(0.5, 0, 1, -8)
			fit.TextSize = 13
			fit.ZIndex = 13
			fit.Parent = card
			fit.Activated:Connect(function() hub:call("EquipToolbox", toolSlot, tb.uid) end)
		end
	end

	refresh = function()
		setTab(tab)
		m.sub.Text = SUBS[tab] or ""
		local p = hub.profile
		if not p then return end
		hub:clear(area)
		if tab == "Upgrades" then upgrades(p)
		elseif tab == "Roads" then roads(p)
		else loadout(p) end
	end

	hub:register("Garage", { frame = m.frame, refresh = refresh })
end
