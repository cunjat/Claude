--!strict
-- TYRE CANNON :: ShiftLock
-- Our own shift lock, on Ctrl because Shift is sprint. While it's on the mouse is held at the
-- centre under the steel crosshair, the camera glides over your right shoulder on a spring (it
-- settles without a wobble, leans out the way you strafe and stops short of walls), and you turn to face where it looks,
-- quickly but never in a snap. The badge in the bottom right is a hub tile (the padlock, CTRL on
-- it), lit green when it's on; click it to toggle. A word flashes by the crosshair.
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

local SHOULDER = Vector3.new(1.7, 0.45, 0)   -- over the right shoulder, a touch high
local LEAN = 0.3           -- how far the camera leans out the way you strafe
local TURN_RATE = 18       -- how fast you turn to face the camera (eased; higher is snappier)
ShiftLock.Keys = { Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl }

local ON_COL = Color3.fromRGB(110, 230, 120)
local OFF_COL = Color3.fromRGB(110, 112, 122)

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

	-- the badge: one of the hub's own tiles (the padlock, CTRL on it), grey when off, lit green when
	-- on; it lifts on hover and toggles on a click like the others
	local wrap = UI.mk("Frame", {
		Name = "ShiftLock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20), Size = UDim2.fromOffset(74, 74),
		BackgroundTransparency = 1, ZIndex = 3, Parent = gui,
	})
	UI.autoScale(wrap, 1280, 760)
	local tile = Kit.tile(Kit.Icon.lock, "Ctrl", C.grey, 74)
	tile.root.Parent = wrap
	tile.onClick = function() self:toggle() end
	self.badge, self.tile = wrap, tile
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
		-- (2026-10-18: not while it's switched off, e.g. in a run, where Ctrl tucks; it used to flip shift
		-- lock in the background and flash SHIFT LOCK ON by the crosshair)
		if gpe or UserInputService:GetFocusedTextBox() or not self.allowed then return end
		if table.find(ShiftLock.Keys, input.KeyCode) then self:toggle() end
	end)
	UserInputService.LastInputTypeChanged:Connect(function() self:refreshBadge() end)
	RunService:BindToRenderStep("TyreShiftLock", Enum.RenderPriority.Camera.Value + 1, function(dt) self:step(dt) end)
	self:refreshBadge()
	return self
end

function ShiftLock:paint(animate: boolean)
	local on = self.on
	self.tile.setColor(if on then ON_COL else OFF_COL)
	local holder = self.tile.root:FindFirstChild("Holder")
	local icon = holder and holder:FindFirstChild("Icon") :: ImageLabel?
	if icon then icon.ImageTransparency = if on then 0 else 0.35 end
	if animate then
		if holder then Kit.pop(holder :: Frame, if on then 0.78 else 0.9, 0.28) end
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

	-- the shoulder swing: a critically damped spring, so it glides over and settles without a wobble
	local target = active and 1 or 0
	local k = 120
	self.blendVel += ((target - self.blend) * k - self.blendVel * 2 * math.sqrt(k)) * dt
	self.blend = math.clamp(self.blend + self.blendVel * dt, 0, 1.05)
	if target == 0 and self.blend < 0.002 and math.abs(self.blendVel) < 0.01 then
		self.blend, self.blendVel = 0, 0
	end

	if active and hum and root and cam then
		-- face where the camera looks: eased, the same at any frame rate
		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			local want = math.atan2(-flat.X, -flat.Z)
			local _, yaw, _ = root.CFrame:ToEulerAnglesYXZ()
			local d = (want - yaw + math.pi) % (2 * math.pi) - math.pi
			local turned = yaw + d * (1 - math.exp(-dt * TURN_RATE))
			root.CFrame = CFrame.new(root.Position) * CFrame.fromEulerAnglesYXZ(0, turned, 0)
		end
		-- lean out the way you strafe
		local move = hum.MoveDirection
		local side = if move.Magnitude > 0.1 then cam.CFrame.RightVector:Dot(move) else 0
		self.lean += (side * LEAN - self.lean) * (1 - math.exp(-dt * 5))
	else
		self.lean += (0 - self.lean) * (1 - math.exp(-dt * 5))
	end

	-- the offset rides in camera space (the humanoid's offset turns with the body, so it swung
	-- about whenever you turned faster than the character); nothing left on the humanoid
	if hum and hum.CameraOffset.Magnitude > 0 and self.blend > 0 then hum.CameraOffset = Vector3.zero end
	if cam and self.blend > 0.001 and cam.CameraType == Enum.CameraType.Custom then
		local cf = cam.CFrame
		-- zoomed right in: the shoulder folds away so first person stays centred
		local dist = (cf.Position - cam.Focus.Position).Magnitude
		local near = math.clamp((dist - 1) / 4, 0, 1)
		local off = cf:VectorToWorldSpace((SHOULDER + Vector3.new(self.lean, 0, 0)) * self.blend * near)
		local len = off.Magnitude
		if len > 0.01 then
			-- never through a wall: stop short of whatever is beside you
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char :: Instance }
			params.RespectCanCollide = true
			local hit = workspace:Raycast(cf.Position, off.Unit * (len + 0.4), params)
			if hit then off = off.Unit * math.max(0, hit.Distance - 0.4) end
			cam.CFrame = cf + off
		end
	end
end

return ShiftLock
