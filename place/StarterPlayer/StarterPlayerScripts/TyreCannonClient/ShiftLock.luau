--!strict
-- TYRE CANNON :: ShiftLock
-- Our own shift lock, on Ctrl because Shift is sprint. While it's on the mouse is held at
-- the centre under the steel crosshair, the camera eases over your right shoulder and you
-- turn with it. A lock plate in the bottom right shows the state and snaps shut with it.
-- It stands aside whenever the camera isn't following you on foot: the workbench, a run,
-- spectating, a menu, the chair.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.UI)
local T = UI.Theme

local ShiftLock = {}
ShiftLock.__index = ShiftLock

local OFFSET = Vector3.new(1.75, 0, 0)
ShiftLock.Keys = { Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl }

local GameSettings = UserSettings():GetService("UserGameSettings")

function ShiftLock.new(gui: ScreenGui, blocked: (() -> boolean)?)
	local self = setmetatable({}, ShiftLock)
	self.player = Players.LocalPlayer
	self.on = false
	self.allowed = true
	self.active = false
	self.blend = 0
	self.blocked = blocked
	self.onChanged = nil

	local badge = UI.mk("Frame", {
		Name = "ShiftLock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(92, 34), BackgroundTransparency = 1, ZIndex = 3, Parent = gui,
	})
	UI.autoScale(badge)
	local plate = UI.plate("slot", { Name = "Plate", Size = UDim2.fromScale(1, 1), ImageTransparency = 0.25, ZIndex = 3, Parent = badge })
	local icon = UI.mk("ImageLabel", {
		Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1, Image = UI.Icons.unlock, ResampleMode = Enum.ResamplerMode.Pixelated, ZIndex = 4, Parent = badge,
	})
	local iconScale = UI.mk("UIScale", { Parent = icon })
	local key = UI.text("CTRL", 13, "monoBold", T.dim)
	key.AnchorPoint = Vector2.new(1, 0.5)
	key.Position = UDim2.new(1, -10, 0.5, 0)
	key.Size = UDim2.fromOffset(46, 16)
	key.TextXAlignment = Enum.TextXAlignment.Right
	key.ZIndex = 4
	key.Parent = badge
	self.badge, self.plate, self.icon, self.iconScale, self.keyLabel = badge, plate, icon, iconScale, key
	self:paint(false)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or UserInputService:GetFocusedTextBox() then return end
		if table.find(ShiftLock.Keys, input.KeyCode) then self:toggle() end
	end)
	UserInputService.LastInputTypeChanged:Connect(function() self:refreshBadge() end)
	RunService:BindToRenderStep("TyreShiftLock", Enum.RenderPriority.Camera.Value + 1, function(dt) self:step(dt) end)
	self:refreshBadge()
	return self
end

function ShiftLock:paint(snap: boolean)
	self.icon.Image = self.on and UI.Icons.lock or UI.Icons.unlock
	self.icon.ImageTransparency = self.on and 0 or 0.35
	self.keyLabel.TextColor3 = self.on and T.text or T.faint
	self.plate.ImageTransparency = self.on and 0.05 or 0.35
	if snap then
		self.iconScale.Scale = 1.45
		UI.tween(self.iconScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

function ShiftLock:toggle()
	self:set(not self.on)
end

function ShiftLock:set(on: boolean)
	if self.on == on then return end
	self.on = on
	self:paint(true)
	if self.onChanged then self.onChanged(on) end
end

-- the yard allows it; the workbench, runs and spectating don't
function ShiftLock:setAllowed(on: boolean)
	self.allowed = on
	self:refreshBadge()
end

function ShiftLock:refreshBadge()
	self.badge.Visible = self.allowed and UserInputService.MouseEnabled and UserInputService.KeyboardEnabled
end

function ShiftLock:step(dt: number)
	local cam = workspace.CurrentCamera
	local char = self.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local active = self.on and self.allowed and UserInputService.MouseEnabled
		and cam ~= nil and cam.CameraType == Enum.CameraType.Custom
		and hum ~= nil and root ~= nil and hum.Health > 0 and not hum.Sit and not root.Anchored
		and cam.CameraSubject == hum
		and not (self.blocked and self.blocked())
	if active then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		GameSettings.RotationType = Enum.RotationType.CameraRelative
	elseif self.active then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		GameSettings.RotationType = Enum.RotationType.MovementRelative
	end
	self.active = active
	self.blend += ((active and 1 or 0) - self.blend) * math.min(1, dt * 9)
	if self.blend < 0.001 then self.blend = 0 end
	if hum then
		local want = OFFSET * self.blend
		if (hum.CameraOffset - want).Magnitude > 0.0005 then hum.CameraOffset = want end
	end
end

return ShiftLock
