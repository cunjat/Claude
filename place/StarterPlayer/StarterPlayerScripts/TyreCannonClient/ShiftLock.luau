--!strict
-- TYRE CANNON :: ShiftLock
-- Our own shift lock, on Ctrl because Shift is sprint. While it's on the mouse is held at the
-- centre under the steel crosshair, the camera swings over your right shoulder on a spring (a
-- little overshoot, and it leans out the way you strafe), and you turn to face where it looks,
-- quickly but never in a snap. The badge in the bottom right is a key cap, the name and a light:
-- lit green and popping when it's on; click it to toggle. A word flashes by the crosshair.
-- It stands aside whenever the camera isn't following you on foot: the workbench, a run,
-- spectating, a menu, the chair.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local C = Kit.C

local ShiftLock = {}
ShiftLock.__index = ShiftLock

local SHOULDER = Vector3.new(1.85, 0.2, 0)
local LEAN = 0.35          -- how far the camera leans out the way you strafe
local TURN_RATE = 16       -- how fast you turn to face the camera (higher is snappier)
ShiftLock.Keys = { Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl }

local ON_COL = Color3.fromRGB(110, 230, 120)
local OFF_COL = Color3.fromRGB(70, 72, 80)

function ShiftLock.new(gui: ScreenGui, blocked: (() -> boolean)?)
	local self = setmetatable({}, ShiftLock)
	self.player = Players.LocalPlayer
	self.on = false
	self.allowed = true
	self.active = false
	self.blend = 0
	self.blendVel = 0
	self.lean = 0
	self.ownsRotate = false
	self.blocked = blocked
	self.onChanged = nil
	-- (the old lock turned the character with the camera setting; this one turns it itself)
	pcall(function()
		UserSettings():GetService("UserGameSettings").RotationType = Enum.RotationType.MovementRelative
	end)

	-- the badge: a key cap, SHIFT LOCK, and a light
	local badge = UI.mk("TextButton", {
		Name = "ShiftLock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.fromOffset(176, 42), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 3, Parent = gui,
	})
	UI.autoScale(badge, 1280, 760)
	local holder = UI.mk("Frame", { Name = "Holder", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = badge })
	local pill = Kit.slice("counter", nil, holder, 3, 0.45)
	pill.ImageTransparency = 0.1
	local cap = UI.mk("Frame", {
		Name = "Cap", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, -1), Size = UDim2.fromOffset(48, 28),
		BackgroundColor3 = Color3.fromRGB(46, 47, 52), ZIndex = 4, Parent = holder,
	}, { UI.corner(6) })
	local capStroke = UI.mk("UIStroke", { Color = C.ink, Thickness = 2, Parent = cap })
	-- the key's lit lower lip
	UI.mk("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 3, 1, -2), Size = UDim2.new(1, -6, 0, 3),
		BackgroundColor3 = Color3.fromRGB(24, 24, 28), BorderSizePixel = 0, ZIndex = 5, Parent = cap,
	}, { UI.corner(2) })
	local capText = Kit.text("CTRL", 13, C.white, 0, Kit.Body)
	capText.Size = UDim2.new(1, 0, 1, -3)
	capText.ZIndex = 6
	capText.Parent = cap
	local name = Kit.text("SHIFT LOCK", 14, C.muted, 1.5)
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.new(0, 64, 0.5, -1)
	name.Size = UDim2.fromOffset(84, 18)
	Kit.fit(name, 14, 9)
	name.ZIndex = 5
	name.Parent = holder
	local light = UI.mk("Frame", {
		Name = "Light", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, -1), Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = OFF_COL, ZIndex = 6, Parent = holder,
	}, { UI.corner(7) })
	UI.mk("UIStroke", { Color = C.ink, Thickness = 2, Parent = light })
	local glow = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1,
		Image = Kit.Art.glow, ImageColor3 = ON_COL, ImageTransparency = 1, ZIndex = 5, Parent = light,
	})
	badge.MouseEnter:Connect(function() Kit.tween(holder, 0.12, { Position = UDim2.fromOffset(0, -3) }, Enum.EasingStyle.Back) end)
	badge.MouseLeave:Connect(function() Kit.tween(holder, 0.12, { Position = UDim2.fromOffset(0, 0) }) end)
	badge.Activated:Connect(function() self:toggle() end)
	self.badge, self.holder, self.cap, self.capStroke, self.nameLabel, self.light, self.glow = badge, holder, cap, capStroke, name, light, glow

	-- the word by the crosshair
	local word = Kit.text("", 18, C.white, 2)
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.Position = UDim2.new(0.5, 0, 0.5, 46)
	word.Size = UDim2.fromOffset(240, 24)
	word.TextTransparency = 1
	word.ZIndex = 50
	word.Parent = gui
	self.word = word

	self:paint(false)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or UserInputService:GetFocusedTextBox() then return end
		if table.find(ShiftLock.Keys, input.KeyCode) then
			-- the key cap presses down with the key
			Kit.tween(self.cap, 0.05, { Position = UDim2.new(0, 8, 0.5, 1) })
			self:toggle()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if table.find(ShiftLock.Keys, input.KeyCode) then
			Kit.tween(self.cap, 0.18, { Position = UDim2.new(0, 8, 0.5, -1) }, Enum.EasingStyle.Back)
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(function() self:refreshBadge() end)
	RunService:BindToRenderStep("TyreShiftLock", Enum.RenderPriority.Camera.Value + 1, function(dt) self:step(dt) end)
	self:refreshBadge()
	return self
end

function ShiftLock:paint(animate: boolean)
	local on = self.on
	Kit.tween(self.light, 0.15, { BackgroundColor3 = if on then ON_COL else OFF_COL })
	Kit.tween(self.glow, 0.2, { ImageTransparency = if on then 0.25 else 1 })
	self.nameLabel.TextColor3 = if on then C.white else C.muted
	self.cap.BackgroundColor3 = if on then Color3.fromRGB(64, 120, 70) else Color3.fromRGB(46, 47, 52)
	if animate then
		Kit.pop(self.holder, if on then 0.8 else 0.9, 0.28)
		Kit.pop(self.light, 1.8, 0.3)
		if self.active or on then
			local w = self.word
			w.Text = if on then "SHIFT LOCK ON" else "SHIFT LOCK OFF"
			w.TextColor3 = if on then ON_COL else C.muted
			w.TextTransparency = 0
			local st = w:FindFirstChildOfClass("UIStroke")
			if st then st.Transparency = 0.1 end
			Kit.pop(w, 0.7, 0.2)
			task.delay(0.6, function()
				if w.Text == (if on then "SHIFT LOCK ON" else "SHIFT LOCK OFF") then
					Kit.tween(w, 0.35, { TextTransparency = 1 })
					if st then Kit.tween(st, 0.35, { Transparency = 1 }) end
				end
			end)
		end
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
		-- we turn the character ourselves (smoothly), so the humanoid stops turning it
		if hum and hum.AutoRotate then
			hum.AutoRotate = false
			self.ownsRotate = true
		end
	elseif self.active then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	if not active and self.ownsRotate then
		self.ownsRotate = false
		-- hand turning back, unless something else (a run, a menu) has the character
		if hum and self.allowed then hum.AutoRotate = true end
	end
	self.active = active

	-- the shoulder swing: a spring with a little overshoot
	local target = active and 1 or 0
	self.blendVel += ((target - self.blend) * 220 - self.blendVel * 22) * dt
	self.blend += self.blendVel * dt
	if target == 0 and self.blend < 0.002 and math.abs(self.blendVel) < 0.01 then
		self.blend, self.blendVel = 0, 0
	end

	if active and hum and root and cam then
		-- face where the camera looks, quickly but not in a snap
		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			local want = math.atan2(-flat.X, -flat.Z)
			local _, yaw, _ = root.CFrame:ToEulerAnglesYXZ()
			local d = (want - yaw + math.pi) % (2 * math.pi) - math.pi
			local turned = yaw + d * math.min(1, dt * TURN_RATE)
			root.CFrame = CFrame.new(root.Position) * CFrame.fromEulerAnglesYXZ(0, turned, 0)
		end
		-- lean out the way you strafe
		local move = hum.MoveDirection
		local side = if move.Magnitude > 0.1 then cam.CFrame.RightVector:Dot(move) else 0
		self.lean += (side * LEAN - self.lean) * math.min(1, dt * 6)
	else
		self.lean += (0 - self.lean) * math.min(1, dt * 6)
	end

	if hum then
		local want = SHOULDER * self.blend + Vector3.new(self.lean, 0, 0)
		if (hum.CameraOffset - want).Magnitude > 0.0005 then hum.CameraOffset = want end
	end
end

return ShiftLock
