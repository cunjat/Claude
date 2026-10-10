--!strict
-- TYRE CANNON :: TouchControls
-- The flight on a phone. Put a thumb down on the left of the screen and drag: that's your stick,
-- wherever it lands (up climbs, down dives, sideways steers). The right thumb has BOOST (nitro),
-- TUCK (hold to dive faster) and SKILL, and BAIL is tucked up top where you won't hit it.

local UserInputService = game:GetService("UserInputService")
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local T = UI.Theme
local C = Kit.C

local TouchControls = {}
TouchControls.__index = TouchControls

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

local STICK = 95 -- pixels of drag for a full deflection

function TouchControls.new(gui: ScreenGui)
	local self = setmetatable({}, TouchControls)
	self.sim = nil
	self.forced = false

	local root = UI.mk("Frame", {
		Name = "TouchControls", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Visible = false, ZIndex = 20, Parent = gui,
	})
	self.root = root

	-- the stick: any touch that starts on the left side and not on a button
	local zone = UI.mk("Frame", {
		Name = "AimZone", Size = UDim2.fromScale(0.6, 1), BackgroundTransparency = 1, Active = true, ZIndex = 19, Parent = root,
	})
	local base = UI.mk("ImageLabel", {
		Name = "StickBase", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(150, 150), BackgroundTransparency = 1,
		Image = Kit.Art.glow, ImageColor3 = Color3.new(1, 1, 1), ImageTransparency = 0.7, Visible = false, ZIndex = 21, Parent = root,
	})
	local knob = UI.mk("Frame", {
		Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(58, 58), BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35, BorderSizePixel = 0, Visible = false, ZIndex = 22, Parent = root,
	}, { UI.corner(29) })
	UI.stroke(Color3.new(0, 0, 0), 2, 0.4).Parent = knob
	local hint = UI.mk("TextLabel", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 28, 1, -40), Size = UDim2.fromOffset(300, 36), BackgroundTransparency = 1,
		Text = "DRAG TO AIM", FontFace = UI.Fonts.display, TextSize = 22, TextColor3 = T.text, TextTransparency = 0.35,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21, Parent = root,
	})
	UI.stroke(Color3.new(0, 0, 0), 1.5, 0.4).Parent = hint
	self.hint = hint

	local aimTouch: InputObject? = nil
	local startPos = Vector2.zero
	zone.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or aimTouch then return end
		aimTouch = input
		startPos = Vector2.new(input.Position.X, input.Position.Y)
		base.Position = UDim2.fromOffset(startPos.X, startPos.Y)
		knob.Position = base.Position
		base.Visible, knob.Visible = true, true
		hint.Visible = false
	end)
	UserInputService.TouchMoved:Connect(function(input)
		if input ~= aimTouch or not self.sim then return end
		local d = (Vector2.new(input.Position.X, input.Position.Y) - startPos)
		local v = Vector2.new(math.clamp(d.X / STICK, -1, 1), math.clamp(-d.Y / STICK, -1, 1))
		;(self.sim :: any):setTouchAim(v)
		knob.Position = UDim2.fromOffset(startPos.X + v.X * 60, startPos.Y - v.Y * 60)
	end)
	UserInputService.TouchEnded:Connect(function(input)
		if input ~= aimTouch then return end
		aimTouch = nil
		base.Visible, knob.Visible = false, false
		if self.sim then (self.sim :: any):setTouchAim(Vector2.zero) end
	end)

	local right = UI.mk("Frame", {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -30),
		Size = UDim2.fromOffset(300, 260), BackgroundTransparency = 1, Parent = root,
	})
	UI.autoScale(right, 900, 500)

	local function pad(parent: Instance, text: string, size: Vector2, pos: UDim2, anchor: Vector2, textSize: number, tint: Color3)
		local b = UI.mk("TextButton", {
			AnchorPoint = anchor, Position = pos, Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundColor3 = tint, BackgroundTransparency = 0.35, BorderSizePixel = 0,
			AutoButtonColor = false, Text = text, FontFace = UI.Fonts.display, TextSize = textSize,
			TextColor3 = T.text, TextTransparency = 0.05, ZIndex = 23, Parent = parent,
		})
		UI.corner(math.floor(math.min(size.X, size.Y) / 2)).Parent = b
		UI.stroke(Color3.new(0, 0, 0), 2.5, 0.2).Parent = b
		return b
	end

	local function hold(b: TextButton, tint: Color3, onChange: (boolean) -> ())
		b.InputBegan:Connect(function(input)
			if not isPress(input) then return end
			onChange(true)
			b.BackgroundColor3 = C.yellow
			b.TextColor3 = Color3.fromRGB(30, 22, 8)
		end)
		b.InputEnded:Connect(function(input)
			if not isPress(input) then return end
			onChange(false)
			b.BackgroundColor3 = tint
			b.TextColor3 = T.text
		end)
	end

	local boost = pad(right, "BOOST", Vector2.new(140, 140), UDim2.new(1, 0, 1, 0), Vector2.new(1, 1), 26, C.blue)
	hold(boost, C.blue, function(on) if self.sim then (self.sim :: any):setTouch("boost", on) end end)
	local tuck = pad(right, "TUCK", Vector2.new(96, 96), UDim2.new(1, -156, 1, 0), Vector2.new(1, 1), 20, C.grey)
	hold(tuck, C.grey, function(on) if self.sim then (self.sim :: any):setTouch("tuck", on) end end)
	-- the launch tyre's skill (Legendary and up); hidden when the tyre has none
	local skill = pad(right, "SKILL", Vector2.new(104, 104), UDim2.new(1, -12, 1, -154), Vector2.new(1, 1), 20, C.orange)
	skill.Name = "Skill"
	hold(skill, C.orange, function(on) if self.sim then (self.sim :: any):setTouch("skill", on) end end)
	self.skillPad = skill

	local bail = pad(root, "BAIL", Vector2.new(76, 34), UDim2.new(1, -18, 0, 168), Vector2.new(1, 0), 15, C.grey)
	bail.BackgroundTransparency = 0.6
	bail.Activated:Connect(function()
		if self.sim then (self.sim :: any):bail() end
	end)
	-- first person and chase
	local view = pad(root, "VIEW", Vector2.new(76, 34), UDim2.new(1, -18, 0, 210), Vector2.new(1, 0), 15, C.grey)
	view.BackgroundTransparency = 0.6
	view.Activated:Connect(function()
		if self.sim then (self.sim :: any):toggleView() end
	end)

	return self
end

function TouchControls:shouldShow(): boolean
	return self.forced or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

function TouchControls:bind(sim)
	self.sim = sim
	self.root.Visible = self:shouldShow()
	self.hint.Visible = true
	local skill = sim and sim.skills and sim.skills.skill
	self.skillPad.Visible = skill ~= nil
	if skill then self.skillPad.Text = string.upper(skill.name) end
end

function TouchControls:unbind()
	self.sim = nil
	self.root.Visible = false
end

function TouchControls:setForced(on: boolean)
	self.forced = on
	if self.sim then self.root.Visible = self:shouldShow() end
end

return TouchControls
