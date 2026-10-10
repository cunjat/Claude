--!strict
-- TYRE CANNON :: Movement
-- Walk and sprint speeds for the yard. Hold shift (or L2, or the RUN button on
-- touch) to sprint. Animations belong to AnimController; there's no camera bob.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent.UI)
local T = UI.Theme

local Movement = {}
Movement.__index = Movement

local WALK, SPRINT = 22, 38
local JUMP = 52
local FOV_BASE, FOV_SPRINT = 70, 78

function Movement.new(gui: ScreenGui)
	local self = setmetatable({}, Movement)
	self.player = Players.LocalPlayer
	self.sprinting = false
	self.enabled = true
	self.button = nil

	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local b = UI.button("RUN", "ghost", 92, 92)
		b.Name = "SprintButton"
		b.AnchorPoint = Vector2.new(1, 1)
		b.Position = UDim2.new(1, -28, 1, -140)
		b.ZIndex = 4
		b.Parent = gui
		UI.corner(46).Parent = b
		b.MouseButton1Down:Connect(function() self:setSprint(true) end)
		b.MouseButton1Up:Connect(function() self:setSprint(false) end)
		self.button = b
	end

	local function isSprintKey(k: Enum.KeyCode): boolean
		return k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.RightShift or k == Enum.KeyCode.ButtonL2
	end
	self.beganConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if not gpe and isSprintKey(input.KeyCode) then self:setSprint(true) end
	end)
	self.endedConn = UserInputService.InputEnded:Connect(function(input)
		if isSprintKey(input.KeyCode) then self:setSprint(false) end
	end)

	self.player.CharacterAdded:Connect(function()
		task.wait(0.3)
		self:apply()
	end)
	if self.player.Character then self:apply() end

	self.stepConn = RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		local hum = self:humanoid()
		if not (cam and hum) or cam.CameraType ~= Enum.CameraType.Custom then return end
		local moving = hum.MoveDirection.Magnitude > 0.1
		local want = (self.enabled and self.sprinting and moving) and FOV_SPRINT or FOV_BASE
		cam.FieldOfView += (want - cam.FieldOfView) * math.min(1, dt * 5)
	end)
	return self
end

function Movement:humanoid(): Humanoid?
	local char = self.player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

function Movement:apply()
	local hum = self:humanoid()
	if not hum then return end
	hum.UseJumpPower = true
	hum.JumpPower = self.enabled and JUMP or 0
	hum.WalkSpeed = self.enabled and (self.sprinting and SPRINT or WALK) or 0
end

function Movement:setSprint(on: boolean)
	if self.sprinting == on then return end
	self.sprinting = on
	local hum = self:humanoid()
	if not hum or not self.enabled then return end
	TweenService:Create(hum, TweenInfo.new(0.2), { WalkSpeed = on and SPRINT or WALK }):Play()
	if self.button then UI.setButtonStyle(self.button, on and "primary" or "ghost") end
end

function Movement:setEnabled(on: boolean)
	self.enabled = on
	if not on then self.sprinting = false end
	self:apply()
	if self.button then self.button.Visible = on end
end

function Movement:destroy()
	if self.beganConn then self.beganConn:Disconnect() end
	if self.endedConn then self.endedConn:Disconnect() end
	if self.stepConn then self.stepConn:Disconnect() end
	if self.button then self.button:Destroy() end
end

return Movement
