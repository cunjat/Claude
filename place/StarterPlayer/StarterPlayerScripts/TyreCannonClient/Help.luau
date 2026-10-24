--!strict
-- TYRE CANNON :: Help (2026-10-16)
-- Settings > Help: what everything does, in a few plain lines each, with the game's own numbers, and
-- a button that replays the tutorial from the first launch (not from the daily reward).
--   Help.new(gui) ; :open() ; :close() ; :isOpen() ; .onReplay (Main: Tutorial:replay)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local C = Kit.C

local Help = {}
Help.__index = Help

local W, H = 860, 540

local function pct(x: number): string
	return ("%d%%"):format(math.floor(x * 100 + 0.5))
end

local TOPICS = {
	{ "Launching", Kit.Icon.cannon, function()
		return "Press LAUNCH and shift in the gold zone as the gauge rises: three clean shifts give a PERFECT LAUNCH. "
			.. "The better the launch, the faster the tyre leaves the cannon."
	end },
	{ "Riding", Kit.Icon.tyre, function()
		return "Steer with the mouse (or drag on a phone). Hold SPACE for nitro. Tuck (Shift) over drops and bumps to keep speed, "
			.. "and as you land. In the air, W floats the nose up to glide, S dives to come down faster. Hills are speed: tuck down them."
	end },
	{ "Your yard", Kit.Icon.plot, function()
		return "Spend cash on the Cannon, Fuel Tank, Cooling Tower, Compressor and Spare Rack: each makes every run go further. "
			.. "Max the Cannon, Fuel Tank and Cooling and pass the stage's trial to move the yard up a stage: a new cannon and cash x"
			.. ("%g"):format(Game.Overhaul.Mult) .. " for good."
	end },
	{ "Stage trials", Kit.Icon.medal, function()
		return "Each stage asks for one challenge done on a run (land PERFECTs, stay in the air, go far...). "
			.. "Every run that falls short makes it a little easier, so it's never a wall."
	end },
	{ "Tyres & crates", Kit.Icon.crate, function()
		return "Crates hold tyres: better tyres multiply your cash. Open them with cash, or with keys for better odds. "
			.. "Each crate features its own Legendary. Your launch tyre counts in full; spares on the rack add "
			.. pct(Game.SpareCash) .. " of theirs."
	end },
	{ "Keys", Kit.Icon.key, function()
		return "Keys are rare: one sometimes waits out on the road (steer for it), every 5th level pays a few, "
			.. "finishing all three daily jobs pays some, and so does the weekly job and the daily reward."
	end },
	{ "Auto-cannon", Kit.Icon.cash, function()
		return ("While you're in the game your yard's cannon fires on its own every %d seconds, each shot paying %s of what your runs earn "
			.. "(%s with Auto Launch). Offline it keeps going at only %s, for up to %d hours: being here pays far more. "
			.. "Yard Style and the Idle Hands perk raise both."):format(Game.AutoCannon.Every, pct(Game.AutoCannon.Share), pct(Game.AutoCannon.PassShare),
			pct(Game.Offline.Share), Game.Offline.CapHours)
	end },
	{ "Jobs", Kit.Icon.key, function()
		return "Three jobs a day pay cash; do all three for keys. A weekly job pays more. Find them in your Profile (the medal under your cash)."
	end },
	{ "Yard style", Kit.Icon.plot, function()
		return "Edit Yard places decor. Every piece scores style points; a whole set and the week's theme score more. "
			.. "Style raises your auto-cannon and offline pay, and shows on your sign for others to like."
	end },
	{ "Prestige & perks", Kit.Icon.medal, function()
		return "At the top stage you can prestige: the yard starts again from nothing, but all cash is multiplied for good, you get keys, "
			.. "a new colour, and you keep one of three perks. Tyres, keys and decor stay."
	end },
}

function Help.new(gui: ScreenGui)
	local self = setmetatable({}, Help)
	self.gui = gui
	self.onReplay = nil :: (() -> ())?
	local root = UI.mk("Frame", { Name = "Help", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(W, H + 20),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui })
	UI.autoScale(root, 1280, 760)
	self.root = root
	local holder, face = Kit.card(UDim2.fromOffset(W, H), C.cream)
	holder.Parent = root
	Kit.header(face, "Help", C.blue, 56)
	local close = Kit.close(52)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, 12, 0, -14)
	close.root.ZIndex = 40
	close.root.Parent = root
	close.onClick = function() self:close() end
	-- the topics down the left
	self.tabs = {}
	for i, t in ipairs(TOPICS) do
		local b = Kit.tab(t[1], UDim2.fromOffset(220, 38), i == 1)
		b.root.Position = UDim2.fromOffset(24, 60 + (i - 1) * 42)
		b.root.ZIndex = 6
		b.root.Parent = face
		b.onClick = function() self:show(i) end
		self.tabs[i] = b
	end
	-- the page
	local page = UI.mk("Frame", { Position = UDim2.fromOffset(264, 60), Size = UDim2.fromOffset(W - 288, 380), BackgroundTransparency = 1, ZIndex = 5, Parent = face })
	Kit.slot(page, Color3.fromRGB(70, 70, 76), 5)
	self.icon = UI.mk("ImageLabel", { Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1, ZIndex = 7, Parent = page })
	self.title = Kit.text("", 30, C.white, 2.5)
	self.title.TextXAlignment = Enum.TextXAlignment.Left
	self.title.Position = UDim2.fromOffset(116, 36)
	self.title.Size = UDim2.fromOffset(W - 288 - 140, 36)
	Kit.fit(self.title, 30, 14)
	self.title.ZIndex = 7
	self.title.Parent = page
	self.body = Kit.text("", 19, C.text, 1.5, Kit.Body)
	self.body.TextXAlignment = Enum.TextXAlignment.Left
	self.body.TextYAlignment = Enum.TextYAlignment.Top
	self.body.TextWrapped = true
	self.body.Position = UDim2.fromOffset(22, 116)
	self.body.Size = UDim2.fromOffset(W - 288 - 44, 250)
	Kit.fit(self.body, 19, 11)
	self.body.ZIndex = 7
	self.body.Parent = page
	-- the replay
	local replay = Kit.button("Replay Tutorial", C.green, UDim2.fromOffset(260, 56), 21)
	replay.root.AnchorPoint = Vector2.new(1, 1)
	replay.root.Position = UDim2.new(1, -24, 1, -18)
	replay.root.ZIndex = 7
	replay.root.Parent = face
	replay.onClick = function()
		self:close()
		if self.onReplay then task.delay(0.3, self.onReplay :: () -> ()) end
	end
	local note = Kit.text("Starts from your first launch. You can skip it any time.", 15, C.muted, 1.5, Kit.Body)
	note.TextXAlignment = Enum.TextXAlignment.Right
	note.AnchorPoint = Vector2.new(1, 1)
	note.Position = UDim2.new(1, -300, 1, -34)
	note.Size = UDim2.fromOffset(400, 20)
	note.ZIndex = 7
	note.Parent = face
	self:show(1)
	return self
end

function Help:show(i: number)
	local t = TOPICS[i]
	for k, b in ipairs(self.tabs) do b.setColor(if k == i then C.accent else C.grey) end
	self.icon.Image = t[2] or ""
	self.title.Text = string.upper(t[1])
	self.body.Text = t[3]()
end

function Help:open()
	Kit.dim(self.gui, self.root, true)
	Kit.open(self.root)
end

function Help:close()
	Kit.dim(self.gui, self.root, false)
	if self.root.Visible then Kit.close_(self.root) end
end

function Help:isOpen(): boolean
	return self.root.Visible
end

return Help
