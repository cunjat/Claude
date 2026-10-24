--!strict
-- TYRE CANNON :: Tips (2026-10-16)
-- The newer systems explained the first time a player meets each one, once: a card slides up near
-- the bottom of the screen with the system's icon, a name and two short lines, and a GOT IT. It goes
-- on its own after a while too. One at a time; a tip asked for while another's up waits its turn.
-- What's been seen is saved in the `tips` pref (a list of ids), so it never shows twice. Every tip
-- shown is logged for the playtest (Track "tip:<id>").
--   Tips.new(gui, track) ; :want(id) -> boolean (asks for it; false when already seen) ; :seen(id)
--   :busy() -> boolean ; Tips.Defs[id] = { title, text, icon, color }

local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Prefs = require(script.Parent.Prefs)
local Sound = require(script.Parent.Sound)
local C = Kit.C

local Tips = {}
Tips.__index = Tips

local STAY = 14

Tips.Defs = {
	-- (top: comes down from the top instead, clear of what it's about)
	trial = { title = "Stage Trials", icon = "medal", color = C.gold, top = true,
		text = "Moving up a stage takes the cash and one challenge done on a run. Every run that falls short makes it a little easier." },
	jobs = { title = "Today's Jobs", icon = "key", color = C.yellow,
		text = "Three jobs a day pay you cash; finish all three for keys. Find them in your Profile: tap the medal under your cash." },
	perks = { title = "Perks", icon = "medal", color = C.teal,
		text = "Each prestige you keep one of three perks for good. They stack, so every climb gets a little stronger." },
	style = { title = "Yard Style", icon = "plot", color = C.teal,
		text = "Decor scores style points; a whole set and the week's theme score more. Style raises your auto-cannon and offline pay." },
	likes = { title = "Likes", icon = "gold", color = C.pink,
		text = "Like the yards you rate: once a day each, on their sign. Your own likes show on your sign, and they count for a weekly job." },
}

function Tips.new(gui: ScreenGui, track: ((string) -> ())?)
	local self = setmetatable({}, Tips)
	self.gui = gui
	self.track = track
	self.queue = {} :: { string }
	self.showing = nil :: string?
	return self
end

local function seenList(): { [string]: boolean }
	local set = {}
	for id in string.gmatch(tostring(Prefs.get("tips") or ""), "[%w_]+") do set[id] = true end
	return set
end

function Tips:seen(id: string): boolean
	return seenList()[id] == true
end

function Tips:busy(): boolean
	return self.showing ~= nil
end

-- asks for a tip; false when it's been seen (or is already waiting)
function Tips:want(id: string): boolean
	if not Tips.Defs[id] or self:seen(id) or self.showing == id or table.find(self.queue, id) then return false end
	table.insert(self.queue, id)
	if not self.showing then self:next() end
	return true
end

function Tips:mark(id: string)
	local set = seenList()
	if set[id] then return end
	local list = tostring(Prefs.get("tips") or "")
	Prefs.set("tips", if list == "" then id else list .. "," .. id)
end

function Tips:next()
	local id = table.remove(self.queue, 1)
	if not id then
		self.showing = nil
		return
	end
	if self:seen(id) then return self:next() end
	self.showing = id
	self:mark(id)
	if self.track then self.track("tip:" .. id) end
	local def = Tips.Defs[id]
	local card = UI.mk("Frame", {
		Name = "Tip", AnchorPoint = Vector2.new(0.5, if def.top then 0 else 1), Position = if def.top then UDim2.new(0.5, 0, 0, -200) else UDim2.new(0.5, 0, 1, 200), Size = UDim2.fromOffset(560, 116),
		BackgroundTransparency = 1, ZIndex = 120, Parent = self.gui,
	})
	UI.autoScale(card, 1280, 760, true)
	Kit.slice("panel_body", nil, card, 120, 0.4)
	Kit.slice("panel_ring", def.color, card, 121, 0.4)
	UI.mk("ImageLabel", { Position = UDim2.fromOffset(10, -14), Size = UDim2.fromOffset(96, 96), BackgroundTransparency = 1, Image = Kit.Icon[def.icon] or Kit.Icon.gold, ZIndex = 124, Parent = card })
	local new = Kit.text("NEW", 12, C.ink, 0)
	new.BackgroundTransparency = 0
	new.BackgroundColor3 = def.color
	new.Position = UDim2.fromOffset(116, 14)
	new.Size = UDim2.fromOffset(44, 18)
	new.ZIndex = 124
	UI.mk("UICorner", { CornerRadius = UDim.new(0, 9), Parent = new })
	new.Parent = card
	local title = Kit.text(string.upper(def.title), 22, C.white, 2)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(168, 10)
	title.Size = UDim2.fromOffset(250, 26)
	Kit.fit(title, 22, 12)
	title.ZIndex = 124
	title.Parent = card
	local body = Kit.text(def.text, 15, C.text, 1.5, Kit.Body)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Position = UDim2.fromOffset(116, 42)
	body.Size = UDim2.fromOffset(300, 64)
	Kit.fit(body, 15, 10)
	body.ZIndex = 124
	body.Parent = card
	local ok = Kit.button("Got it", def.color, UDim2.fromOffset(120, 44), 17)
	ok.root.AnchorPoint = Vector2.new(1, 0.5)
	ok.root.Position = UDim2.new(1, -16, 0.5, 0)
	ok.root.ZIndex = 125
	ok.root.Parent = card
	local gone = false
	local function leave()
		if gone then return end
		gone = true
		Kit.tween(card, 0.3, { Position = if def.top then UDim2.new(0.5, 0, 0, -200) else UDim2.new(0.5, 0, 1, 200) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.35, function()
			card:Destroy()
			self.showing = nil
			task.delay(1.2, function() if not self.showing then self:next() end end)
		end)
	end
	ok.onClick = leave
	Sound.play("medal", { volume = 0.4, pitch = 1.35, length = 0.6 })
	Kit.tween(card, 0.45, { Position = if def.top then UDim2.new(0, 0, 0, 30) + UDim2.fromScale(0.5, 0) else UDim2.new(0.5, 0, 1, -130) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(STAY, leave)
end

return Tips
