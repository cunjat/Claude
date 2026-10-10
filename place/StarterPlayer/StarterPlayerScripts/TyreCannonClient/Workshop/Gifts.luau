--!strict
-- TYRE CANNON :: Workshop / Gifts
-- Both ends of a gift.
--   Sending: while you try on a part you don't own, GIFT on the rack's banner opens a
--   list of everyone in the server. Pick someone and it's bought and wrapped for them.
--   Opening: wrapped boxes wait on the bench beside the wheel (three at a time). Click
--   one on the FIT station: it shakes, bursts, and the part inside goes onto your wheel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Config = require(Modules.Config)
local UI = require(script.Parent.Parent.UI)
local VFX = require(script.Parent.Parent.VFX)
local Rack = require(script.Parent.Rack)
local T = UI.Theme

local Gifts = {}
Gifts.__index = Gifts

local SLOTS = { -4.6, -6.0, -3.3 }
local LOOKUP = { skin = Config.SkinsById, rim = Config.RimsById, trail = Config.TrailsById, rig = Config.RigSkinsById }

local function defFor(kind: string)
	for _, d in ipairs(Rack.KINDS) do
		if d.kind == kind then return d end
	end
	return nil
end

function Gifts.new(ws)
	local self = setmetatable({}, Gifts)
	self.ws = ws
	self.boxes = {}
	self.hover = nil
	self.opening = false
	self.conns = {}
	self.announced = {}

	self.highlight = Instance.new("Highlight")
	self.highlight.Name = "GiftHover"
	self.highlight.FillTransparency = 1
	self.highlight.OutlineColor = T.gold
	self.highlight.Enabled = false

	self:buildPicker()
	return self
end

--==============================================================
-- sending
--==============================================================
function Gifts:buildPicker()
	local ws = self.ws
	local panel = UI.panel({
		Name = "GiftPicker", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -360),
		Size = UDim2.fromOffset(420, 120), Visible = false, ZIndex = 60, Parent = ws.root,
	})
	UI.autoScale(panel, 1240, 780)
	local title = UI.text("GIFT IT TO", 20, "display", T.text)
	title.Position = UDim2.fromOffset(0, 16)
	title.Size = UDim2.new(1, 0, 0, 24)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 61
	title.Parent = panel
	local sub = UI.text("", 13, "body", T.dim)
	sub.Position = UDim2.fromOffset(20, 42)
	sub.Size = UDim2.new(1, -40, 0, 18)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.ZIndex = 61
	sub.Parent = panel
	local close = UI.button("X", "ghost", 32, 32)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.ZIndex = 62
	close.Parent = panel
	close.Activated:Connect(function() panel.Visible = false end)
	local list = UI.mk("Frame", {
		Name = "List", Position = UDim2.fromOffset(24, 70), Size = UDim2.new(1, -48, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, ZIndex = 61, Parent = panel,
	}, { UI.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })
	self.picker, self.pickerSub, self.pickerList = panel, sub, list
end

function Gifts:canGift(item): boolean
	return item and not item.robux and not item.locked and (item.cost or 0) > 0
end

function Gifts:openPicker(def, item)
	local ws = self.ws
	local panel, list = self.picker, self.pickerList
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	self.pickerSub.Text = ("%s  ·  %s CR, wrapped and left on their bench"):format(string.upper(item.name), UI.comma(item.cost or 0))
	local others = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= Players.LocalPlayer then table.insert(others, pl) end
	end
	table.sort(others, function(a, b) return a.DisplayName:lower() < b.DisplayName:lower() end)
	if #others == 0 then
		local l = UI.text("Nobody else is in this server yet.", 15, "bodySemi", T.faint)
		l.Size = UDim2.new(1, 0, 0, 40)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.ZIndex = 62
		l.Parent = list
	end
	for i, pl in ipairs(others) do
		if i > 8 then break end
		local row = UI.mk("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 61, Parent = list })
		UI.plate("slot", { Size = UDim2.fromScale(1, 1), ZIndex = 61, Parent = row })
		local name = UI.text(pl.DisplayName, 16, "displayMed", T.text)
		name.Position = UDim2.fromOffset(14, 0)
		name.Size = UDim2.new(1, -140, 1, 0)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = 62
		name.Parent = row
		local send = UI.button("SEND", "primary", 100, 30)
		send.AnchorPoint = Vector2.new(1, 0.5)
		send.Position = UDim2.new(1, -6, 0.5, 0)
		send.TextSize = 14
		send.ZIndex = 62
		send.Parent = row
		send.Activated:Connect(function()
			if ws.pending > 0 then return end
			ws.pending += 1
			UI.setButtonStyle(send, "off")
			task.spawn(function()
				local res = ws:call("SendGift", pl.UserId, def.kind, item.id)
				ws.pending -= 1
				if res and res.ok then
					panel.Visible = false
					UI.stamp(ws.gui, "Gift sent", T.gold, ("%s  ·  TO %s"):format(string.upper(item.name), string.upper(pl.DisplayName)))
					ws:putBack()
				else
					UI.setButtonStyle(send, "primary")
				end
			end)
		end)
	end
	local rows = math.max(1, math.min(8, #others))
	panel.Size = UDim2.fromOffset(420, 96 + rows * 46)
	panel.Visible = true
end

--==============================================================
-- the boxes on your bench
--==============================================================
function Gifts:refresh()
	local ws = self.ws
	local room = ws.room
	local p = ws.profile
	if not (room and p) then return end
	local tpl = Root.Assets.Props:FindFirstChild("GiftBox") :: BasePart?
	local want = {}
	for i, g in ipairs(p.gifts or {}) do
		if i > #SLOTS then break end
		want[g.uid] = { gift = g, slot = i }
	end
	-- clear boxes that were opened or moved
	for uid, b in pairs(self.boxes) do
		if not want[uid] and not b.opening then
			b.part:Destroy()
			self.boxes[uid] = nil
		end
	end
	local top = room.origin.Y + room.benchTop
	for uid, w in pairs(want) do
		if not self.boxes[uid] and tpl then
			local part = tpl:Clone()
			part.Name = "Gift_" .. uid
			-- a shoebox-sized present, not a crate
			local k = 1.25 / part.Size.Y
			part.Size *= k
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			if mesh then mesh.Scale *= k end
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = true
			part.CastShadow = true
			local x = room.origin.X + SLOTS[w.slot]
			local base = CFrame.new(x, top + part.Size.Y / 2 + 0.02, room.origin.Z - 8.3) * CFrame.Angles(0, math.rad(-18 + w.slot * 21), 0)
			part.CFrame = base
			part.Parent = room.folder
			self.boxes[uid] = { part = part, base = base, gift = w.gift, t = math.random() * 5 }
		end
	end
	-- say so once per gift
	if ws.isOpen then
		for _, g in ipairs(p.gifts or {}) do
			if not self.announced[g.uid] then
				self.announced[g.uid] = true
				ws:toast(("A GIFT FROM %s IS ON THE BENCH. CLICK IT TO OPEN."):format(string.upper(g.from or "SOMEONE")), T.gold)
			end
		end
	end
end

function Gifts:boxAt(pos: Vector2)
	local list = {}
	for _, b in pairs(self.boxes) do
		if not b.opening then table.insert(list, b.part) end
	end
	if #list == 0 then return nil end
	local ray = self.ws:mouseRay(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	local r = workspace:Raycast(ray.Origin, ray.Direction * 80, params)
	if not r then return nil end
	for _, b in pairs(self.boxes) do
		if b.part == r.Instance then return b end
	end
	return nil
end

function Gifts:open(b)
	local ws = self.ws
	if self.opening or ws.busy or not b then return end
	local g = b.gift
	local lookup = LOOKUP[g.kind]
	local item = lookup and lookup[g.id]
	if not item then return end
	self.opening = true
	b.opening = true
	self.highlight.Enabled = false
	UI.setCursor(nil)
	task.spawn(function()
		local res = ws:call("OpenGift", g.uid)
		if not (res and res.ok) then
			b.opening = false
			self.opening = false
			return
		end
		-- it rattles harder and harder, then bursts
		local t = 0
		while t < 0.9 do
			t += task.wait()
			local k = t / 0.9
			local a = math.rad(14) * k * math.sin(t * (30 + 40 * k))
			b.part.CFrame = b.base * CFrame.new(0, 0.12 * k * math.abs(math.sin(t * 22)), 0) * CFrame.Angles(0, 0, a)
		end
		local tier = Config.CosmeticTier(item)
		local color = Config.TierColor(tier)
		VFX.emit("DraftPick", b.part.CFrame, { scale = 1.2, color = color })
		VFX.emit("PortalEnter", b.part.CFrame * CFrame.new(0, -0.8, 0), { scale = 0.6 })
		ws:shake(0.35)
		local size = b.part.Size
		local pop = 0
		while pop < 0.18 do
			pop += task.wait()
			local k = pop / 0.18
			b.part.Size = size * (1 + k * 0.5)
			b.part.LocalTransparencyModifier = k
		end
		b.part:Destroy()
		for uid, x in pairs(self.boxes) do
			if x == b then self.boxes[uid] = nil end
		end
		self.opening = false
		UI.stamp(ws.gui, item.name, color, ("FROM %s  ·  %s"):format(string.upper(g.from or "SOMEONE"), string.upper(tier)))
		-- the part inside goes straight onto the wheel
		local def = defFor(g.kind)
		if def and ws.isOpen then
			if ws.station ~= "Fit" then ws:setStation("Fit") end
			ws.rack.tab = def.key
			ws.rack.sig = ""
			task.wait(0.3)
			if ws.isOpen then ws:useItem(def, item) end
		else
			self:refresh()
		end
	end)
end

function Gifts:enter()
	local ws = self.ws
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
	if ws.room then self.highlight.Parent = ws.room.folder end
	self:refresh()
	table.insert(self.conns, UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or not ws.isOpen or ws.busy or ws.station ~= "Fit" then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local pos = input.UserInputType == Enum.UserInputType.Touch and Vector2.new(input.Position.X, input.Position.Y) or UserInputService:GetMouseLocation()
			local b = self:boxAt(pos)
			if b then
				ws.turning = false
				self:open(b)
			end
		end
	end))
end

function Gifts:leave()
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
	self.highlight.Enabled = false
	if self.hover then UI.setCursor(nil) end
	self.hover = nil
	self.picker.Visible = false
end

function Gifts:step(dt: number)
	local ws = self.ws
	-- the boxes wobble now and then, like something's in there
	for _, b in pairs(self.boxes) do
		if not b.opening then
			b.t += dt
			local w = (b.t % 4) < 0.5 and math.sin(b.t * 40) * math.rad(5) * (1 - ((b.t % 4) / 0.5)) or 0
			b.part.CFrame = b.base * CFrame.Angles(0, 0, w)
		end
	end
	if ws.station ~= "Fit" or self.opening then
		if self.hover then
			self.hover = nil
			self.highlight.Enabled = false
			UI.setCursor(nil)
		end
		return
	end
	local b = self:boxAt(UserInputService:GetMouseLocation())
	if b ~= self.hover then
		self.hover = b
		if b then
			self.highlight.Adornee = b.part
			self.highlight.Enabled = true
			UI.setCursor("point")
		else
			self.highlight.Enabled = false
			UI.setCursor(nil)
		end
	end
	if self.hover then UI.setCursor("point") end
end

return Gifts
