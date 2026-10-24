--!strict
-- TYRE CANNON :: Feedback
-- What the playtest needs to hear, asked without getting in the way:
--   the form    from Settings (SEND FEEDBACK): what kind of note (a bug, an idea, something fun,
--               something boring), stars for how it's going, a few lines of text, SEND. It goes to
--               the server's Feedback store (Loop), never to other players.
--   the rating  after your third run of a session (and your tenth): a small card asks "How's it
--               going?" with five stars; one tap and it's gone. Ignored, it slides away on its own.
--   Feedback.new(gui, remotes) ; :open() ; :close() ; :isOpen() ; :askRating(context)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Sound = require(script.Parent.Sound)
local C = Kit.C
local _ = ReplicatedStorage

local Feedback = {}
Feedback.__index = Feedback

local KINDS = {
	{ id = "bug", name = "Bug", color = C.red },
	{ id = "idea", name = "Idea", color = C.blue },
	{ id = "fun", name = "Fun", color = C.green },
	{ id = "boring", name = "Boring", color = C.grey },
}

local function stars(parent: Instance, x: number, y: number, size: number, onPick: (number) -> (), z: number?)
	local row = { buttons = {}, value = 0 }
	for i = 1, 5 do
		local b = UI.mk("TextButton", {
			Position = UDim2.fromOffset(x + (i - 1) * (size + 6), y), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1,
			Text = "★", TextScaled = true, FontFace = Kit.Font, TextColor3 = C.line, AutoButtonColor = false, ZIndex = z or 8, Parent = parent,
		})
		b.Activated:Connect(function()
			row.value = i
			for k, o in ipairs(row.buttons) do o.TextColor3 = if k <= i then C.gold else C.line end
			Kit.pop(b, 1.4, 0.25)
			onPick(i)
		end)
		table.insert(row.buttons, b)
	end
	return row
end

function Feedback.new(gui: ScreenGui, remotes: Instance)
	local self = setmetatable({}, Feedback)
	self.gui = gui
	self.R = remotes
	self.kind = "idea"
	self.rating = 0

	local root = UI.mk("Frame", {
		Name = "Feedback", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 470),
		BackgroundTransparency = 1, Visible = false, ZIndex = 72, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.root = root
	local holder, face = Kit.card(UDim2.fromScale(1, 1), C.cream)
	holder.Parent = root
	Kit.header(face, "Feedback", C.green, 54)
	local close = Kit.close(48)
	close.root.AnchorPoint = Vector2.new(0.5, 0.5)
	close.root.Position = UDim2.new(1, -8, 0, 8)
	close.root.ZIndex = 80
	close.root.Parent = root
	close.onClick = function() self:close() end
	local sub = Kit.text("You're playtesting. Tell us what to fix and what to keep.", 16, C.muted, 1.5, Kit.Body)
	sub.Position = UDim2.fromOffset(0, 48)
	sub.Size = UDim2.new(1, 0, 0, 20)
	sub.ZIndex = 4
	sub.Parent = face
	-- the kind of note
	self.kindBtns = {}
	for i, k in ipairs(KINDS) do
		local b = Kit.tab(k.name, UDim2.fromOffset(130, 34), k.id == self.kind)
		b.root.Position = UDim2.fromOffset(28 + (i - 1) * 142, 80)
		b.root.ZIndex = 6
		b.root.Parent = face
		b.onClick = function()
			self.kind = k.id
			for id, o in pairs(self.kindBtns) do o.setColor(if id == k.id then C.accent else C.grey) end
		end
		self.kindBtns[k.id] = b
	end
	local howLabel = Kit.text("HOW'S IT GOING?", 14, C.gold, 1.5)
	howLabel.TextXAlignment = Enum.TextXAlignment.Left
	howLabel.Position = UDim2.fromOffset(30, 130)
	howLabel.Size = UDim2.fromOffset(200, 18)
	howLabel.ZIndex = 6
	howLabel.Parent = face
	self.stars = stars(face, 220, 122, 34, function(v) self.rating = v end)
	-- the text
	local well = UI.mk("Frame", { Position = UDim2.fromOffset(28, 170), Size = UDim2.fromOffset(564, 196), BackgroundTransparency = 1, ZIndex = 5, Parent = face })
	Kit.slot(well, Kit.NEUTRAL, 5)
	local box = UI.mk("TextBox", {
		Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 1, -24), BackgroundTransparency = 1, Text = "", ClearTextOnFocus = false,
		MultiLine = true, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		PlaceholderText = "What happened, or what would make it better?", PlaceholderColor3 = C.muted, TextColor3 = C.text,
		FontFace = Kit.Body, TextSize = 18, ZIndex = 7, Parent = well,
	})
	self.box = box
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > 600 then box.Text = string.sub(box.Text, 1, 600) end
	end)
	local send = Kit.button("Send", C.green, UDim2.fromOffset(220, 56), 24)
	send.root.AnchorPoint = Vector2.new(0.5, 1)
	send.root.Position = UDim2.new(0.5, 0, 1, -18)
	send.root.ZIndex = 7
	send.root.Parent = face
	send.onClick = function() self:send() end
	return self
end

function Feedback:isOpen(): boolean
	return self.root.Visible
end

function Feedback:open()
	Kit.dim(self.gui, self, true)
	Kit.open(self.root)
end

function Feedback:close()
	Kit.dim(self.gui, self, false)
	if self.root.Visible then Kit.close_(self.root) end
end

function Feedback:send()
	local text = self.box.Text
	if #text < 3 and self.rating == 0 then
		Kit.callout(self.gui, "Write a note or pick some stars first", C.red, UDim2.fromScale(0.5, 0.2), 28)
		return
	end
	local ok, res = pcall(function() return (self.R :: any).Feedback:InvokeServer(self.kind, text, self.rating) end)
	if ok and type(res) == "table" and res.ok then
		Sound.play("medal", { volume = 0.6, pitch = 1.2 })
		Kit.callout(self.gui, "THANKS! SENT.", C.green, UDim2.fromScale(0.5, 0.2), 36)
		self.box.Text = ""
		self:close()
	else
		Kit.callout(self.gui, string.upper(ok and type(res) == "table" and res.err or "Couldn't send that"), C.red, UDim2.fromScale(0.5, 0.2), 26)
	end
end

-- the one-tap rating card, bottom left; it leaves on its own after a while
function Feedback:askRating(context: string)
	if self.ratingCard then return end
	local card = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, 140), Size = UDim2.fromOffset(330, 110),
		BackgroundTransparency = 1, ZIndex = 70, Parent = self.gui,
	})
	UI.autoScale(card, 1280, 760)
	self.ratingCard = card
	Kit.slice("panel_body", nil, card, 70, 0.4)
	Kit.slice("panel_ring", C.gold, card, 71, 0.4)
	local q = Kit.text("HOW'S IT GOING?", 18, C.white, 2)
	q.Position = UDim2.fromOffset(0, 12)
	q.Size = UDim2.new(1, 0, 0, 22)
	q.ZIndex = 73
	q.Parent = card
	local function leave()
		if self.ratingCard ~= card then return end
		self.ratingCard = nil
		Kit.tween(card, 0.3, { Position = UDim2.new(0, 24, 1, 140) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.35, function() card:Destroy() end)
	end
	stars(card, 58, 44, 36, function(v)
		task.spawn(function() pcall(function() (self.R :: any).Feedback:InvokeServer("rating", context, v) end) end)
		Kit.callout(self.gui, "THANKS!", C.gold, UDim2.fromScale(0.5, 0.2), 30)
		task.delay(0.5, leave)
	end, 74)
	-- (2026-10-18: really bottom left now; top centre, it covered the run's distance on the results)
	Kit.tween(card, 0.45, { Position = UDim2.new(0, 24, 1, -24) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(14, leave)
end

return Feedback
