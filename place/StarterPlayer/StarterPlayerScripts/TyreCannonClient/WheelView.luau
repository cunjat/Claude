--!strict
-- TYRE CANNON :: WheelView
-- VIEW WHEEL on a yard's sign: the owner's launch tyre turning in a bay (drag to spin it), its
-- name in its rarity's colour, its cash multiplier, its stats, its special and skill. View only.
--   WheelView.new(gui) -> view ; view:open(info) (a plot snapshot entry) ; view:close()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local TyreLook = require(script.Parent.TyreLook)
local C = Kit.C

local WheelView = {}
WheelView.__index = WheelView

function WheelView.new(gui: ScreenGui)
	local self = setmetatable({}, WheelView)
	self.gui = gui
	self.yaw = 0
	self.spin = 0.6
	local root = UI.mk("Frame", {
		Name = "WheelView", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(760, 440),
		BackgroundTransparency = 1, Visible = false, ZIndex = 90, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.root = root
	local holder, face = Kit.card(UDim2.fromScale(1, 1), C.cream, 20, 8)
	holder.Parent = root
	self.face = face
	self.header = Kit.header(face, "Wheel", C.green, 52)
	local close = Kit.close(48)
	close.root.AnchorPoint = Vector2.new(1, 0)
	close.root.Position = UDim2.new(1, 10, 0, -12)
	close.root.ZIndex = 95
	close.root.Parent = root
	close.onClick = function() self:close() end

	-- the bay on the left, the tyre turning in it
	local bay = UI.mk("Frame", { Position = UDim2.fromOffset(24, 50), Size = UDim2.fromOffset(340, 366), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
	self.slot = Kit.slot(bay, Kit.NEUTRAL, 4)
	local vp = UI.mk("ViewportFrame", {
		Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20), BackgroundTransparency = 1, Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1), ZIndex = 6, Parent = bay,
	})
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 1.6, 15), Vector3.zero)
	cam.Parent = vp
	vp.CurrentCamera = cam
	self.vp = vp
	local hint = Kit.text("Drag to spin", 13, C.muted, 1.5, Kit.Body)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -12)
	hint.Size = UDim2.new(1, 0, 0, 16)
	hint.ZIndex = 7
	hint.Parent = bay
	-- drag anywhere on the bay to turn it; let go and it carries on turning slowly
	local drag = UI.mk("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 8, Parent = bay })
	local dragging, lastX = false, 0
	drag.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			lastX = io.Position.X
		end
	end)
	UserInputService.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			local dx = io.Position.X - lastX
			lastX = io.Position.X
			self.yaw += dx * 0.012
			self.spin = dx * 0.6
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)

	-- the words on the right
	local function line(y: number, size: number, color: Color3, font: Font?): TextLabel
		local l = Kit.text("", size, color, 2, font)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Position = UDim2.fromOffset(388, y)
		l.Size = UDim2.fromOffset(348, size + 8)
		Kit.fit(l, size, 10)
		l.ZIndex = 5
		l.Parent = face
		return l
	end
	self.owner = line(54, 16, C.muted, Kit.Body)
	self.name = line(76, 34, C.white)
	self.rarity = line(118, 20, C.white)
	self.mult = line(150, 24, C.gold)
	self.stats = {}
	for i = 1, 5 do self.stats[i] = line(190 + (i - 1) * 30, 18, C.text, Kit.Body) end
	self.none = line(190, 18, C.muted, Kit.Body)

	RunService.RenderStepped:Connect(function(dt)
		if not root.Visible or not self.model then return end
		if not dragging then
			self.spin += (0.6 - self.spin) * math.min(1, dt * 2)
			self.yaw += self.spin * dt
		end
		self.model:PivotTo(CFrame.Angles(0, self.yaw, 0) * CFrame.Angles(0, math.rad(-30), 0))
	end)
	return self
end

function WheelView:open(info)
	if type(info) ~= "table" then return end
	local w = info.wheel
	local def = w and Game.TyresById[w.id]
	if self.model then self.model:Destroy() end
	self.model = nil
	local world = self.vp:FindFirstChildOfClass("WorldModel") or Instance.new("WorldModel")
	world.Parent = self.vp
	self.owner.Text = string.upper(tostring(info.name or "?")) .. "'S LAUNCH TYRE"
	for _, l in ipairs(self.stats) do l.Text = "" end
	if def then
		local r = Game.RaritiesById[def.rarity]
		local m = TyreLook.model(w.id, 6, "View", w.design)
		m.Parent = world
		self.model = m
		local stars = (w.forge or 0) > 0 and (" " .. string.rep("★", w.forge)) or ""
		local mut = w.mut and Game.MutationsById[w.mut]
		self.name.Text = def.name .. stars
		self.rarity.Text = string.upper(def.rarity) .. (mut and ("  ·  " .. string.upper(mut.name)) or "")
		self.rarity.TextColor3 = r.color
		self.mult.Text = ("x%s CASH"):format(Game.multText(Game.tyreMult(w.id, w.forge, w.mut)))
		local lines = Game.tyreLines(w.id, w.forge, w.mut)
		-- the first line is the cash multiplier, shown above already
		for i = 2, math.min(#lines, #self.stats + 1) do self.stats[i - 1].Text = lines[i] end
		self.none.Text = ""
		local art = self.slot:FindFirstChild("EdgeArt") :: ImageLabel?
		if art then art.ImageColor3 = r.color end
		local wash = self.slot:FindFirstChild("Wash") :: ImageLabel?
		if wash then wash.ImageColor3 = r.color end
	else
		self.name.Text = "No tyre yet"
		self.rarity.Text = ""
		self.mult.Text = ""
		self.none.Text = "They haven't picked a launch tyre."
	end
	Kit.dim(self.gui, self, true)
	Kit.open(self.root)
end

function WheelView:isOpen(): boolean
	return self.root.Visible
end

function WheelView:close()
	if not self.root.Visible then return end
	Kit.dim(self.gui, self, false)
	Kit.close_(self.root, function()
		if self.model then self.model:Destroy() end
		self.model = nil
	end)
end

return WheelView
