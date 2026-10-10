--!strict
-- TYRE CANNON :: ZoneMap
-- Where the next run starts, as a route: one road across the screen with a stop for every zone.
--   each stop   its emblem standing on the road, a node in the zone's colour, its name, and how far
--               it is (a zone you haven't reached is greyed with a padlock and the distance)
--   below       the zone you've picked: what it is, what it pays, from how far, and a button that
--               says Start Here, Starting Here or Locked
-- No scene pictures: the zones' look is waiting on real art.
--   ZoneMap.new(gui, onPick(zoneId)) -> map ; map:setProfile(p) ; map:open() / :close() / :isOpen()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Game = require(Root:WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local C = Kit.C

local ZoneMap = {}
ZoneMap.__index = ZoneMap

-- each zone's look: its colour and its emblem (a studio render of its signature thing), and a line
local LOOK = {
	backroad = {
		color = Color3.fromRGB(150, 205, 60), emblem = "rbxassetid://83152526890742", pic = "rbxassetid://96177458923825",
		blurb = "Village lanes through the Punjab fields: mustard either side, poplars along the canal, a tube well thumping and a buffalo that will not move.",
	},
	highway = {
		color = Color3.fromRGB(255, 128, 40), emblem = "rbxassetid://139037651079434", pic = "rbxassetid://109289235049196",
		blurb = "The Grand Trunk Road into the sunset: painted goods trucks pulled in at the dhaba, and the pylons marching off to the haze.",
	},
	dunes = {
		color = Color3.fromRGB(176, 112, 240), emblem = "rbxassetid://136591911534456", pic = "rbxassetid://78657262671906",
		blurb = "The Thar at dusk: dunes over the tarmac, a khejri bent by the wind, a camel on the ridge and a chhatri standing alone.",
	},
}
ZoneMap.LOOK = LOOK

local LOCK = Kit.Icon.lock -- the padlock (icon studio)
local W = 960
local ROAD_Y = 188          -- the road's centre line, in the card's own space

function ZoneMap.new(gui: ScreenGui, onPick: (string) -> ())
	local self = setmetatable({}, ZoneMap)
	self.gui = gui
	self.onPick = onPick
	self.pick = "backroad"
	self.focus = "backroad"
	local root = UI.mk("Frame", {
		Name = "ZoneMap", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(W, 560),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.root = root
	local holder, face = Kit.card(UDim2.fromOffset(W, 540), C.cream)
	holder.Parent = root
	Kit.header(face, "Zones", C.teal, 56)
	local close = Kit.close(54)
	close.root.AnchorPoint = Vector2.new(0.5, 0.5)
	close.root.Position = UDim2.new(1, -8, 0, 8)
	close.root.ZIndex = 40
	close.root.Parent = root
	close.onClick = function() self:close() end
	self.face = face

	-- the road: a dark band with a dashed line down it, lit up to the stop you've reached
	local road = UI.mk("Frame", { Position = UDim2.fromOffset(40, ROAD_Y - 22), Size = UDim2.fromOffset(W - 80, 44), BackgroundColor3 = Color3.fromRGB(34, 35, 38), BorderSizePixel = 0, ZIndex = 5, Parent = face }, { UI.corner(10) })
	UI.mk("UIStroke", { Color = Kit.C.ink, Thickness = 3, Parent = road })
	road.ClipsDescendants = true
	local dashes = UI.mk("Frame", { Size = UDim2.new(1, 62, 1, 0), BackgroundTransparency = 1, ZIndex = 6, Parent = road })
	for k = 0, 30 do
		UI.mk("Frame", { Position = UDim2.fromOffset(14 + k * 31, 20), Size = UDim2.fromOffset(18, 4), BackgroundColor3 = Color3.fromRGB(110, 112, 118), BorderSizePixel = 0, ZIndex = 6, Parent = dashes })
	end
	self.dashes = dashes
	self.lit = UI.mk("Frame", { Position = UDim2.fromOffset(40, ROAD_Y - 22), Size = UDim2.fromOffset(0, 44), BackgroundColor3 = C.teal, BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 6, Parent = face }, { UI.corner(10) })
	self.roller = UI.mk("ImageLabel", {
		Name = "Roller", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(40, ROAD_Y), Size = UDim2.fromOffset(46, 46),
		BackgroundTransparency = 1, Image = Kit.Icon.tyre, ZIndex = 12, Parent = face,
	})

	-- the stops, spread along the road
	self.stops = {}
	local n = #Game.Zones
	for i, z in ipairs(Game.Zones) do
		local look = LOOK[z.id]
		local cx = 40 + (W - 80) * ((i - 0.5) / n)
		local b = UI.mk("TextButton", {
			Name = z.id, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(cx, 56), Size = UDim2.fromOffset(250, 220),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 8, Parent = face,
		})
		local inner = UI.mk("Frame", { Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 8, Parent = b })
		local card = UI.mk("Frame", {
			Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(125, 54), Size = UDim2.fromOffset(212, 104),
			BackgroundTransparency = 1, ZIndex = 8, Parent = inner,
		})
		Kit.slot(card, look.color, 8)
		local ring = UI.mk("ImageLabel", {
			Name = "Scene", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), BackgroundTransparency = 1,
			Image = look.pic or "", ScaleType = Enum.ScaleType.Crop, ImageTransparency = 0.45, ZIndex = 9, Parent = card,
		}, { UI.corner(10) })
		local emblem = UI.mk("ImageLabel", {
			Name = "Emblem", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(125, 138), Size = UDim2.fromOffset(120, 120),
			BackgroundTransparency = 1, Image = look.emblem, ScaleType = Enum.ScaleType.Fit, ZIndex = 10, Parent = inner,
		})
		-- the node on the road
		local node = UI.mk("Frame", {
			Name = "Node", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(125, ROAD_Y - 56), Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = look.color, ZIndex = 11, Parent = inner,
		}, { UI.corner(17) })
		UI.mk("UIStroke", { Color = Kit.C.ink, Thickness = 3, Parent = node })
		local num = Kit.text(tostring(i), 18, C.white, 2)
		num.Size = UDim2.fromScale(1, 1)
		num.ZIndex = 12
		num.Parent = node
		local name = Kit.text(string.upper(z.name), 26, C.white, 3)
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Position = UDim2.fromOffset(125, ROAD_Y - 56 + 70)
		name.Size = UDim2.fromOffset(240, 30)
		Kit.fit(name, 26, 14)
		name.ZIndex = 10
		name.Parent = inner
		local status = Kit.text("", 15, C.gold, 2, Kit.Body)
		status.AnchorPoint = Vector2.new(0.5, 0)
		status.Position = UDim2.fromOffset(125, ROAD_Y - 56 + 102)
		status.Size = UDim2.fromOffset(240, 20)
		status.ZIndex = 10
		status.Parent = inner
		local lock = UI.mk("ImageLabel", {
			Name = "Lock", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(125, 70), Size = UDim2.fromOffset(64, 64),
			BackgroundTransparency = 1, Image = LOCK, ZIndex = 13, Visible = false, Parent = inner,
		})
		local chip = Kit.plate(inner, "Starting", C.green, UDim2.fromOffset(75, 4), UDim2.fromOffset(100, 24), 13)
		chip.Visible = false
		b.MouseEnter:Connect(function()
			if self.focus ~= z.id then Kit.tween(inner, 0.14, { Position = UDim2.fromOffset(0, -6) }, Enum.EasingStyle.Back) end
		end)
		b.MouseLeave:Connect(function()
			Kit.tween(inner, 0.14, { Position = UDim2.fromOffset(0, self.focus == z.id and -10 or 0) })
		end)
		b.Activated:Connect(function()
			self.focus = z.id
			self:show(z.id)
			Kit.pop(emblem, 0.85, 0.25)
		end)
		self.stops[z.id] = { button = b, inner = inner, status = status, chip = chip, lock = lock, emblem = emblem, node = node, name = name, glow = ring, cx = cx }
	end

	-- the zone you've picked, under the road
	local card = UI.mk("Frame", { Position = UDim2.fromOffset(34, 322), Size = UDim2.fromOffset(W - 68, 196), BackgroundTransparency = 1, ZIndex = 5, Parent = face })
	Kit.slice("panel_body", nil, card, 5, 0.4)
	self.cardEdge = Kit.slice("panel_ring", C.teal, card, 6, 0.4)
	self.title = Kit.text("", 30, C.white, 3)
	self.title.TextXAlignment = Enum.TextXAlignment.Left
	self.title.Position = UDim2.fromOffset(24, 14)
	self.title.Size = UDim2.fromOffset(420, 36)
	Kit.fit(self.title, 30, 16)
	self.title.ZIndex = 8
	self.title.Parent = card
	self.blurb = Kit.text("", 17, C.text, 1.5, Kit.Body)
	self.blurb.Position = UDim2.fromOffset(24, 54)
	self.blurb.Size = UDim2.fromOffset(W - 68 - 330, 64)
	self.blurb.TextWrapped = true
	self.blurb.TextXAlignment = Enum.TextXAlignment.Left
	self.blurb.TextYAlignment = Enum.TextYAlignment.Top
	self.blurb.ZIndex = 8
	self.blurb.Parent = card
	self.facts = Kit.text("", 16, C.gold, 1.5, Kit.Body)
	self.facts.Position = UDim2.fromOffset(24, 138)
	self.facts.Size = UDim2.fromOffset(W - 68 - 330, 40)
	self.facts.TextWrapped = true
	self.facts.TextXAlignment = Enum.TextXAlignment.Left
	self.facts.TextYAlignment = Enum.TextYAlignment.Top
	self.facts.ZIndex = 8
	self.facts.Parent = card
	local go = Kit.button("Start Here", C.green, UDim2.fromOffset(270, 64), 25)
	go.root.AnchorPoint = Vector2.new(1, 0.5)
	go.root.Position = UDim2.new(1, -24, 0.5, 0)
	go.root.ZIndex = 9
	go.root.Parent = card
	go.onClick = function()
		local id = self.focus
		if self.profile and self.profile.v2 and self.profile.v2.zones[id] then
			self.pick = id
			self.onPick(id)
			self:refresh()
			Kit.callout(self.gui, "Starting in the " .. Game.ZonesById[id].name, C.green, UDim2.fromScale(0.5, 0.2), 34)
			task.delay(0.35, function() self:close() end)
		end
	end
	self.go = go
	return self
end

-- point the card at a zone and light its stop
function ZoneMap:show(id: string)
	local z = Game.ZonesById[id]
	local look = LOOK[id]
	local v = self.profile and self.profile.v2
	local open = v ~= nil and v.zones[id] == true
	for zid, s in pairs(self.stops) do
		local on = zid == id
		Kit.tween(s.inner, 0.16, { Position = UDim2.fromOffset(0, on and -10 or 0) }, Enum.EasingStyle.Back)
		Kit.tween(s.emblem, 0.16, { Size = if on then UDim2.fromOffset(140, 140) else UDim2.fromOffset(112, 112) }, Enum.EasingStyle.Back)
		Kit.tween(s.glow, 0.16, { ImageTransparency = if on then 0 else 0.5 })
	end
	self.title.Text = string.upper(z.name)
	self.cardEdge.ImageColor3 = look.color
	self.blurb.Text = look.blurb
	self.facts.Text = ("x%.2f cash a metre  ·  from %s  ·  %d key crate"):format(z.rate, Game.metres(z.start), z.keys)
	if not open then
		self.go.setText("Locked: reach " .. Game.metres(z.start))
		self.go.setEnabled(false)
	elseif id == self.pick then
		self.go.setText("Starting Here")
		self.go.setEnabled(false)
	else
		self.go.setText("Start Here")
		self.go.setEnabled(true)
	end
end

function ZoneMap:refresh()
	local v = self.profile and self.profile.v2
	local reachedStop = 0
	for i, z in ipairs(Game.Zones) do
		local s = self.stops[z.id]
		local open = v ~= nil and v.zones[z.id] == true
		if open then reachedStop = i end
		s.status.Text = open and ("from %s"):format(Game.metres(z.start)) or ("reach %s"):format(Game.metres(z.start))
		s.lock.Visible = not open
		s.emblem.ImageColor3 = if open then Color3.new(1, 1, 1) else Color3.fromRGB(96, 94, 104)
		s.node.BackgroundColor3 = if open then LOOK[z.id].color else Color3.fromRGB(80, 80, 88)
		s.chip.Visible = z.id == self.pick
	end
	-- the road is lit up to the furthest zone you've reached
	local reach = if reachedStop > 0 then self.stops[Game.Zones[reachedStop].id].cx else 40
	self.lit.Size = UDim2.fromOffset(math.max(0, reach - 40), 44)
	self.reachX = reach
	if self.root.Visible then self:show(self.focus) end
end

function ZoneMap:setProfile(p)
	self.profile = p
	-- a zone picked before can stay picked only while it's still open to you
	local v = p and p.v2
	if v and not v.zones[self.pick] then
		self.pick = "backroad"
		self.onPick("backroad")
	end
	self:refresh()
end

-- while the map is up: the dashes run, the tyre rolls out to your reach, the picked emblem bobs
function ZoneMap:animate()
	if self.anim then self.anim:Disconnect() end
	local t0 = os.clock()
	self.roller.Position = UDim2.fromOffset(40, ROAD_Y)
	self.anim = game:GetService("RunService").RenderStepped:Connect(function(dt)
		if not self.root.Visible then
			self.anim:Disconnect()
			self.anim = nil
			return
		end
		local t = os.clock() - t0
		self.dashes.Position = UDim2.fromOffset(-((t * 40) % 31), 0)
		local target = math.max(40, (self.reachX or 40) - 34)
		local x = self.roller.Position.X.Offset
		x += (target - x) * math.min(1, dt * 2.2)
		self.roller.Position = UDim2.fromOffset(x, ROAD_Y + math.abs(math.sin(t * 9)) * -2)
		self.roller.Rotation += dt * (math.abs(target - x) > 2 and 540 or 60)
		local s = self.stops[self.focus]
		if s then s.emblem.Position = UDim2.fromOffset(125, 138 + math.sin(t * 3) * 3) end
	end)
end

function ZoneMap:open()
	task.defer(function() self:animate() end)
	Kit.dim(self.gui, self, true)
	Kit.open(self.root)
	self.focus = self.pick
	self:refresh()
	self:show(self.pick)
	local list = {}
	for _, z in ipairs(Game.Zones) do table.insert(list, self.stops[z.id].button) end
	Kit.cascade(list, 0.06)
end

function ZoneMap:close()
	Kit.dim(self.gui, self, false)
	if self.root.Visible then Kit.close_(self.root) end
end

function ZoneMap:isOpen(): boolean
	return self.root.Visible
end

return ZoneMap
