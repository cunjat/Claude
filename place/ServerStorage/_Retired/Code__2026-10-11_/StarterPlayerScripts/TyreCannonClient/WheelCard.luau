--!strict
-- TYRE CANNON :: WheelCard
-- A spec card for anyone's wheel, opened from VIEW WHEEL on their yard sign. The
-- wheel turns slowly in a viewport: drag to spin it, scroll to get close to the
-- stickers. Beside it: tyre, rim, trail, stickers and pressure, each in its rarity
-- colour, laid out to be screenshotted. View only, nothing here changes anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Config = require(Modules.Config)
local WheelAssembly = require(Modules.WheelAssembly)
local UI = require(script.Parent.UI)
local T = UI.Theme

local WheelCard = {}
WheelCard.__index = WheelCard

local DIAMETER = 6

function WheelCard.new(gui: ScreenGui)
	local self = setmetatable({}, WheelCard)
	self.gui = gui
	self.yaw = -0.6
	self.spinVel = 0.35
	self.zoom = 1
	self.dragging = false

	local backdrop = UI.mk("TextButton", {
		Name = "WheelCardBackdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.void, BackgroundTransparency = 0.3,
		BorderSizePixel = 0, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 120, Parent = gui,
	})
	UI.guardBackdrop(backdrop, function() self:close() end)
	self.backdrop = backdrop

	local card = UI.panel({
		Name = "WheelCard", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(860, 520), Visible = false, ZIndex = 121, Parent = gui,
	})
	UI.autoScale(card, 960, 640)
	self.card = card

	local close = UI.button("X", "ghost", 38, 38)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 16)
	close.ZIndex = 124
	close.Parent = card
	close.Activated:Connect(function() self:close() end)

	-- the wheel, in a pressed slot on the left
	local well = UI.plate("slot", {
		Name = "Well", Position = UDim2.fromOffset(28, 28), Size = UDim2.fromOffset(440, 464), ZIndex = 122, Parent = card,
	})
	local vpf = UI.mk("ViewportFrame", {
		Name = "View", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), BackgroundColor3 = Color3.fromRGB(30, 28, 26),
		BackgroundTransparency = 0, Ambient = Color3.fromRGB(150, 146, 140), LightColor = Color3.fromRGB(255, 240, 222),
		LightDirection = Vector3.new(-0.5, -0.7, -1), ZIndex = 123, Parent = well,
	})
	UI.mk("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150)),
		Parent = vpf,
	})
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vpf
	vpf.CurrentCamera = cam
	self.vpf, self.cam = vpf, cam
	local hint = UI.text("DRAG TO SPIN  ·  SCROLL TO ZOOM", 11, "monoBold", T.faint)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -14)
	hint.Size = UDim2.new(1, 0, 0, 14)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.ZIndex = 124
	hint.Parent = well

	vpf.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self.dragging = true
			UI.setCursor("grabbing")
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			self.zoom = math.clamp(self.zoom - input.Position.Z * 0.12, 0.45, 1.3)
		end
	end)
	vpf.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			self.zoom = math.clamp(self.zoom - input.Position.Z * 0.12, 0.45, 1.3)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if self.dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			self.spinVel = input.Delta.X * 0.6
			self.yaw += input.Delta.X * 0.012
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if self.dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			self.dragging = false
			UI.setCursor(nil)
		end
	end)

	-- the spec sheet on the right
	local x = 500
	local function label(name: string, text: string, size: number, role: string, color: Color3, y: number, h: number): TextLabel
		local l = UI.text(text, size, role, color)
		l.Name = name
		l.Position = UDim2.fromOffset(x, y)
		l.Size = UDim2.fromOffset(330, h)
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.ZIndex = 123
		l.Parent = card
		return l
	end
	self.eyebrow = label("Eyebrow", "SPEC CARD", 12, "monoBold", T.accent, 34, 16)
	self.owner = label("Owner", "", 30, "display", T.text, 52, 34)
	self.rigName = label("Rig", "", 14, "monoBold", Color3.fromRGB(222, 178, 96), 88, 18)
	UI.plate("divider", { Position = UDim2.fromOffset(x, 116), Size = UDim2.fromOffset(330, 10), ZIndex = 123, Parent = card })
	self.rows = {}
	local names = { "TYRE", "RIM", "TRAIL", "STICKERS", "PRESSURE", "BEST" }
	for i, n in ipairs(names) do
		local y = 136 + (i - 1) * 50
		local k = label("Key" .. i, n, 11, "monoBold", T.faint, y, 14)
		local v = label("Value" .. i, "", 19, "display", T.text, y + 14, 24)
		local tier = UI.text("", 11, "monoBold", T.dim)
		tier.AnchorPoint = Vector2.new(1, 0)
		tier.Position = UDim2.fromOffset(x + 330, y)
		tier.Size = UDim2.fromOffset(120, 14)
		tier.TextXAlignment = Enum.TextXAlignment.Right
		tier.ZIndex = 123
		tier.Parent = card
		self.rows[n] = { key = k, value = v, tier = tier }
	end
	self.footer = label("Footer", "", 11, "monoBold", T.faint, 468, 14)

	RunService.RenderStepped:Connect(function(dt) self:step(dt) end)
	return self
end

local function setRow(row, value: string, tier: string?)
	row.value.Text = value
	if tier then
		local c = Config.TierColor(tier)
		row.tier.Text = string.upper(tier)
		row.tier.TextColor3 = c
		row.value.TextColor3 = T.text
	else
		row.tier.Text = ""
	end
end

-- info is a plot snapshot row: name, skin, rim, trail, stickers, pressure, best, rigName
function WheelCard:open(index: number, info)
	if type(info) ~= "table" then return end
	if self.model then self.model:Destroy() end
	local model = WheelAssembly.build(nil, {
		diameter = DIAMETER, skin = info.skin or "stock", rim = info.rim or "steel", stickers = info.stickers,
		name = "CardWheel",
	})
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Light") then d:Destroy() end
	end
	model.Parent = self.vpf
	self.model = model
	self.yaw = -0.6
	self.zoom = 1
	self.spinVel = 0.35

	self.owner.Text = string.upper(info.name or "?")
	local rig = type(info.rigName) == "string" and info.rigName or ""
	self.rigName.Text = rig ~= "" and ('"' .. string.upper(rig) .. '"') or ("YARD " .. index)
	local skin = Config.SkinsById[info.skin or "stock"] or Config.SkinsById.stock
	local rim = Config.RimsById[info.rim or "steel"] or Config.RimsById.steel
	local trail = Config.TrailsById[info.trail or "none"] or Config.TrailsById.none
	setRow(self.rows.TYRE, string.upper(skin.name), Config.CosmeticTier(skin))
	setRow(self.rows.RIM, string.upper(rim.name), Config.CosmeticTier(rim))
	if trail.id == "none" then
		setRow(self.rows.TRAIL, "NONE", nil)
	else
		setRow(self.rows.TRAIL, string.upper(trail.name), Config.CosmeticTier(trail))
	end
	local n = type(info.stickers) == "table" and #info.stickers or 0
	setRow(self.rows.STICKERS, ("%d OF %d"):format(n, Config.Stickers.MaxPerTyre), nil)
	local pressure = tonumber(info.pressure) or Config.Pressure.Default
	local psi = math.floor(20 + pressure * 0.4 + 0.5)
	setRow(self.rows.PRESSURE, ("%d PSI  ·  %s"):format(psi, pressure < 34 and "SOFT" or (pressure > 66 and "HARD" or "MEDIUM")), nil)
	setRow(self.rows.BEST, UI.comma(tonumber(info.best) or 0) .. " M", nil)
	self.footer.Text = ("TYRE CANNON  ·  YARD %d  ·  %s"):format(index, string.upper(os.date("%d %b %Y")))

	self.backdrop.Visible = true
	self.card.Visible = true
	self.card.Position = UDim2.new(0.5, 0, 0.5, 18)
	UI.tween(self.card, 0.22, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
end

function WheelCard:isOpen(): boolean
	return self.card.Visible
end

function WheelCard:close()
	self.backdrop.Visible = false
	self.card.Visible = false
	self.dragging = false
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
end

function WheelCard:step(dt: number)
	local model = self.model
	if not (model and self.card.Visible) then return end
	if not self.dragging then
		self.spinVel += (0.35 - self.spinVel) * math.min(1, dt * 1.5)
		self.yaw += self.spinVel * dt
	end
	model:PivotTo(CFrame.Angles(0, self.yaw, 0) * CFrame.Angles(0.12, 0, 0))
	local dist = 17 * self.zoom
	self.cam.CFrame = CFrame.lookAt(Vector3.new(0, 1.2 * self.zoom, dist), Vector3.zero)
end

return WheelCard
