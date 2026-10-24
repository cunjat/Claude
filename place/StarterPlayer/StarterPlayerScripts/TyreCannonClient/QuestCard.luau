--!strict
-- TYRE CANNON :: QuestCard
-- Today's three jobs and the week's one (Goals, kept by the server), on a card on the right of the
-- yard once the tutorial's done: each row says what to do and how far along it is, ticks off with a
-- chime when it's done (the server pays it at once), and the foot of the card says when the next
-- day's jobs come. It doesn't sit there: after a little while (or its X) it tucks itself into a
-- small JOBS 1/3 tab on the right edge; the tab brings it back, and so does a job moving along.
-- The full list (with the stage trial) lives in the Profile's Jobs tab. It steps aside whenever a
-- screen is open over the yard.
--   QuestCard.new(gui) ; :setProfile(p) ; :show(on) ; .onOpenJobs

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Goals = require(Modules.Goals)
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Checklist = require(script.Parent.Checklist)
local C = Kit.C

local QuestCard = {}
QuestCard.__index = QuestCard

local STAY = 16   -- seconds the card stays open before it tucks away

function QuestCard.new(gui: ScreenGui)
	local self = setmetatable({}, QuestCard)
	self.gui = gui
	self.list = nil :: any
	self.key = nil :: string?
	self.want = false
	self.open = true
	self.left = STAY
	self.marks = {} :: { [string]: string }
	-- the tab it tucks into
	local pill = UI.mk("TextButton", {
		Name = "JobsTab", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.52, 0), Size = UDim2.fromOffset(150, 52),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 40, Parent = gui,
	})
	UI.autoScale(pill, 1280, 760, true)
	Kit.slice("panel_body", nil, pill, 40, 0.3)
	Kit.slice("panel_ring", C.yellow, pill, 41, 0.3)
	UI.mk("ImageLabel", { Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(32, 32), BackgroundTransparency = 1, Image = Kit.Icon.key, ZIndex = 43, Parent = pill })
	local pt = Kit.text("JOBS", 17, C.white, 2)
	pt.TextXAlignment = Enum.TextXAlignment.Left
	pt.Position = UDim2.fromOffset(50, 7)
	pt.Size = UDim2.fromOffset(88, 20)
	pt.ZIndex = 43
	pt.Parent = pill
	local pc = Kit.text("0/3", 15, C.gold, 1.5)
	pc.TextXAlignment = Enum.TextXAlignment.Left
	pc.Position = UDim2.fromOffset(50, 26)
	pc.Size = UDim2.fromOffset(88, 18)
	pc.ZIndex = 43
	pc.Parent = pill
	self.pill, self.pillCount = pill, pc
	pill.MouseEnter:Connect(function() Kit.tween(pill, 0.15, { Position = UDim2.new(1, -6, 0.52, 0) }) end)
	pill.MouseLeave:Connect(function() Kit.tween(pill, 0.15, { Position = UDim2.new(1, 0, 0.52, 0) }) end)
	pill.Activated:Connect(function() self:expand() end)

	local last = 0
	RunService.Heartbeat:Connect(function(dt)
		-- (it only counts down while it's on screen)
		if self.list and self.open and self.want then self.left -= dt end
		if not self.list or os.clock() - last < 1 then return end
		last = os.clock()
		local left = 86400 - os.time() % 86400
		self.list:setNote(("New jobs in %dh %02dm  ·  all jobs in Profile"):format(math.floor(left / 3600), math.floor(left % 3600 / 60)))
		if self.open and self.want and self.left <= 0 then self:tuck() end
	end)
	return self
end

function QuestCard:expand()
	self.open = true
	self.left = STAY
	self:show(self.want)
end

function QuestCard:tuck()
	self.open = false
	self:show(self.want)
end

function QuestCard:setProfile(p)
	local v = p and p.v2
	local q = v and v.quests
	if not (q and q.list and #q.list > 0) then return end
	local key = tostring(q.day) .. ":" .. tostring(q.week)
	if key ~= self.key then
		self.key = key
		if self.list then self.list:destroy() end
		local items = {}
		for i, g in ipairs(q.list) do
			table.insert(items, { id = "d" .. i, text = Goals.text(g) })
		end
		if q.wk then table.insert(items, { id = "wk", text = "Week: " .. Goals.text(q.wk) }) end
		self.list = Checklist.new(self.gui, {
			title = "Today's Jobs", color = C.yellow, items = items, side = "right", y = 0.52, values = true, w = 360,
			note = "New jobs soon", onClose = function() self:tuck() end,
		})
		self.shownOnce = false
		self.marks = {}
		self.open = true
		self.left = STAY
	end
	local L = self.list
	local moved = false
	local function row(id: string, g)
		if not g then return end
		local text = if g.done then "DONE" else Goals.progressText(g, g.h)
		if self.marks[id] and self.marks[id] ~= text then moved = true end
		self.marks[id] = text
		L:setValue(id, text)
		local r = L.rows[id]
		if g.done and r and not r.done then L:set(id, true, not self.shownOnce or not L.shown) end
	end
	for i, g in ipairs(q.list) do row("d" .. i, g) end
	row("wk", q.wk)
	local done, nextUp = 0, nil
	for i, g in ipairs(q.list) do
		if g.done then done += 1 elseif not nextUp then nextUp = "d" .. i end
	end
	self.pillCount.Text = ("%d/%d DONE"):format(done, #q.list)
	L:focus(nextUp)
	-- a job moving along brings the card out for a moment
	if moved and not self.open then
		self.open = true
		self.left = 6
	end
	self:show(self.want)
end

function QuestCard:show(on: boolean)
	self.want = on
	if not self.list then
		self.pill.Visible = false
		return
	end
	self.list:show(on and self.open)
	if on and self.open then self.shownOnce = true end
	local tab = on and not self.open
	if tab ~= self.pill.Visible then
		self.pill.Visible = tab
		if tab then
			self.pill.Position = UDim2.new(1, 160, 0.52, 0)
			Kit.tween(self.pill, 0.35, { Position = UDim2.new(1, 0, 0.52, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end
end

return QuestCard
