--!strict
-- TYRE CANNON :: Workshop
-- The workbench as a room of its own, one per player and client-side only.
-- Opening it rolls a garage shutter over the screen, swaps the yard for a dark
-- workshop far above the map, and puts your wheel on a balancer under a
-- single warm lamp.
--   FIT       tyres, rims, trails and pressure. Shop cards on top, your rack
--             below. Tap a card, or drag it onto the wheel.
--   STICKERS  stickers wrapped onto the rubber. They bend over the tread and
--             down the sidewall.
--   RETREAD   three toolboxes on the anvil, three hammer strikes, one better box.
-- Main hooks: Workshop.new(gui, hub), :open(plot), :close(), :setProfile(p),
-- .onEnter() once the shutter is down on the way in, .onExit() on the way out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Modules = Root:WaitForChild("Modules")
local Remotes = Root:WaitForChild("Remotes")
local Config = require(Modules.Config)
local WheelAssembly = require(Modules.WheelAssembly)
local DoorArt = require(Modules:WaitForChild("DoorArt"))
local UI = require(script.Parent.UI)
local Room = require(script.Room)
local Effects = require(script.Effects)
local Rack = require(script.Rack)
local Stickers = require(script.Stickers)
local Retread = require(script.Retread)
local Wall = require(script.Wall)
local Gifts = require(script.Gifts)
local Prefs = require(script.Parent.Prefs)
local T = UI.Theme

local Workshop = {}
Workshop.__index = Workshop

Workshop.WHEEL_DIAMETER = 5

-- the anvil (Retread) is off the bench in Alpha 0.2: no forging, no quench
local STATIONS = { "Fit", "Stickers", "Wall" }
local STATION_KEYS = {
	[Enum.KeyCode.One] = "Fit",
	[Enum.KeyCode.Two] = "Stickers",
	[Enum.KeyCode.Three] = "Wall",
}
local ROOM_ORIGIN = CFrame.new(-6000, 2400, 6000)
local LIGHT_KEYS = {
	"Ambient", "OutdoorAmbient", "Brightness", "EnvironmentDiffuseScale",
	"EnvironmentSpecularScale", "ExposureCompensation", "GlobalShadows",
}

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

--==============================================================
-- construction
--==============================================================
function Workshop.new(gui: ScreenGui, hub)
	local self = setmetatable({}, Workshop)
	self.gui = gui
	self.hub = hub
	self.profile = nil
	self.isOpen = false
	self.busy = false
	self.station = "Fit"
	self.room = nil
	self.wheel = nil
	self.preview = { skin = "stock", rim = "steel", trail = "none" }
	self.tryOn = nil
	self.pending = 0
	self.yaw = 0
	self.roll = 0
	self.spin = 0
	self.spinKick = 0
	self.spinHold = 0
	self.turning = false
	self.camGoal = nil
	self.camCF = nil
	self.camFov = 42
	self.conns = {}
	self.onEnter = nil
	self.onExit = nil

	local root = UI.mk("Frame", {
		Name = "Workshop", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20, Parent = gui,
	})
	self.root = root

	-- shading so the cards and tabs read over the room
	local low = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.5),
		BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 20, Parent = root,
	})
	UI.mk("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 0.12),
		}),
		Parent = low,
	})
	local high = UI.mk("Frame", {
		Size = UDim2.fromScale(1, 0.18), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 20, Parent = root,
	})
	UI.mk("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.35, 1), Parent = high })

	-- stations, centred along the top
	local top = UI.mk("Frame", {
		Name = "TopBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(720, 80),
		BackgroundTransparency = 1, ZIndex = 21, Parent = root,
	})
	UI.autoScale(top)
	local eyebrow = UI.text("WORKBENCH", 12, "monoBold", T.faint)
	eyebrow.AnchorPoint = Vector2.new(0.5, 0)
	eyebrow.Position = UDim2.fromScale(0.5, 0)
	eyebrow.Size = UDim2.new(1, 0, 0, 14)
	eyebrow.TextXAlignment = Enum.TextXAlignment.Center
	eyebrow.ZIndex = 22
	eyebrow.Parent = top
	local tabs = UI.mk("Frame", {
		Name = "Stations", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1, ZIndex = 21, Parent = top,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	self.tabButtons = {}
	for i, name in ipairs(STATIONS) do
		local b = UI.button(string.upper(name), "ghost", 124, 38)
		b.Name = "Tab_" .. name
		b.TextSize = 16
		b.LayoutOrder = i
		b.ZIndex = 22
		b.Parent = tabs
		b.Activated:Connect(function()
			if self.isOpen and not self.busy then self:setStation(name) end
		end)
		self.tabButtons[name] = b
	end
	local leave = UI.button("LEAVE", "ghost", 120, 38)
	leave.Name = "LeaveButton"
	leave.TextSize = 16
	leave.LayoutOrder = 10
	leave.ZIndex = 22
	leave.Parent = tabs
	leave.Activated:Connect(function() self:close() end)
	self.creditsLabel = UI.text("", 13, "monoBold", T.dim)
	self.creditsLabel.AnchorPoint = Vector2.new(0.5, 0)
	self.creditsLabel.Position = UDim2.new(0.5, 0, 0, 62)
	self.creditsLabel.Size = UDim2.new(1, 0, 0, 16)
	self.creditsLabel.TextXAlignment = Enum.TextXAlignment.Center
	self.creditsLabel.ZIndex = 22
	self.creditsLabel.Parent = top

	-- the roller shutter that hides every swap
	local shutter = UI.mk("Frame", {
		Name = "WorkshopShutter", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(52, 54, 58), BorderSizePixel = 0, Visible = false, ZIndex = 400, Parent = gui,
	})
	local SLATS = 14
	for i = 1, SLATS do
		local slat = UI.mk("Frame", {
			Position = UDim2.fromScale(0, (i - 1) / SLATS), Size = UDim2.new(1, 0, 1 / SLATS, 1),
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 401, Parent = shutter,
		})
		UI.mk("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 153, 158)),
				ColorSequenceKeypoint.new(0.14, Color3.fromRGB(116, 119, 124)),
				ColorSequenceKeypoint.new(0.82, Color3.fromRGB(76, 78, 83)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(32, 33, 36)),
			}),
			Parent = slat,
		})
	end
	-- the door's bottom edge
	local edge = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = Color3.fromRGB(34, 35, 38), BorderSizePixel = 0, ZIndex = 402, Parent = shutter,
	})
	UI.mk("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(120, 122, 126), BorderSizePixel = 0, ZIndex = 403, Parent = edge })
	-- a real roller-door image, once Config.Workshop.DoorImage is set; it fills the
	-- screen at any shape without stretching, and the drawn slats step aside for it
	local doorImage = (Config.Workshop and Config.Workshop.DoorImage) or ""
	if doorImage ~= "" then
		for _, c in ipairs(shutter:GetChildren()) do
			if c:IsA("Frame") and c.ZIndex == 401 then c.Visible = false end
		end
		UI.mk("ImageLabel", {
			Name = "DoorImage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = doorImage,
			ScaleType = Enum.ScaleType.Crop, ZIndex = 404, Parent = shutter,
		})
		-- a speck of the same picture stays on screen from the start, so it has already
		-- loaded by the first time the door comes down
		UI.mk("ImageLabel", {
			Name = "DoorImageWarm", Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1, Image = doorImage,
			ImageTransparency = 0.98, ZIndex = 1, Parent = gui,
		})
	end
	-- your stickers, slapped on the door
	self.doorStickers = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 405, Parent = shutter })
	local drop = UI.mk("Frame", {
		Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0, ZIndex = 400, Parent = shutter,
	})
	UI.mk("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.3, 1), Parent = drop })
	self.shutter = shutter

	-- sparks thrown off the door's bottom edge when it slams down or grinds off the floor
	self.sparkLayer = UI.mk("Frame", {
		Name = "DoorSparks", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 410, Parent = gui,
	})
	self.doorDust = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 90),
		BackgroundColor3 = Color3.fromRGB(140, 132, 122), BackgroundTransparency = 1, BorderSizePixel = 0,
		ZIndex = 411, Parent = self.sparkLayer,
	})
	UI.mk("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 0.2) }),
		Parent = self.doorDust,
	})
	self.sparks = {}
	self.doorShake = 0
	RunService.RenderStepped:Connect(function(dt) self:stepSparks(dt) end)

	self.fx = Effects.new(self)
	self.rack = Rack.new(self)
	self.stickers = Stickers.new(self)
	self.retread = Retread.new(self)
	self.wall = Wall.new(self)
	self.gifts = Gifts.new(self)
	return self
end

--==============================================================
-- open and close
--==============================================================
-- the classic bounce: lands at 1/2.75, 2/2.75 and 2.5/2.75 of the way through
-- the roller door recording (3.35 s): a rattle for its first half second, a quiet gap, the slam
-- at 0.66 s, and a tail that's gone by 1.6 s
local DOOR_SOUND = "rbxassetid://122316613819334"
local DOOR_SLAM_AT = 0.66
task.spawn(function()
	local s = Instance.new("Sound")
	s.SoundId = DOOR_SOUND
	pcall(function() game:GetService("ContentProvider"):PreloadAsync({ s }) end)
end)

local DOOR_HITS = { 1 / 2.75, 2 / 2.75, 2.5 / 2.75 }
local DOOR_HIT_POWER = { 1, 0.45, 0.18 }
local function bounceOut(k: number): number
	local n, d = 7.5625, 2.75
	if k < 1 / d then
		return n * k * k
	elseif k < 2 / d then
		k -= 1.5 / d
		return n * k * k + 0.75
	elseif k < 2.5 / d then
		k -= 2.25 / d
		return n * k * k + 0.9375
	end
	k -= 2.625 / d
	return n * k * k + 0.984375
end

-- Down: the door drops, slams onto the floor with a fan of sparks, and bounces twice
-- with smaller showers. Up: it grinds off the floor with a scrape of sparks and rolls away.
-- The door recording cut to the animation. Coming down, it starts just early enough that the
-- slam lands on the first bounce, then fades as the bounces settle. Going up, only the opening
-- rattle plays, a touch quicker, and fades out before the slam.
function Workshop:doorSound(down: boolean)
	local SoundService = game:GetService("SoundService")
	local s = Instance.new("Sound")
	s.SoundId = DOOR_SOUND
	s.SoundGroup = SoundService:FindFirstChild("Effects") :: SoundGroup?
	s.Volume = 0
	s.Parent = SoundService
	local volume, fadeAt, fadeFor
	if down then
		local firstHit = DOOR_HITS[1] * 0.62
		s.TimePosition = DOOR_SLAM_AT - firstHit
		volume, fadeAt, fadeFor = 0.8, 0.85, 0.35
	else
		s.PlaybackSpeed = 1.15
		s.TimePosition = 0
		volume, fadeAt, fadeFor = 0.5, 0.32, 0.22
	end
	local from = s.TimePosition
	s:Play()
	s.TimePosition = from
	TweenService:Create(s, TweenInfo.new(0.04), { Volume = volume }):Play()
	task.delay(fadeAt, function()
		if s.Parent then
			TweenService:Create(s, TweenInfo.new(fadeFor, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = 0 }):Play()
		end
	end)
	task.delay(fadeAt + fadeFor + 0.05, function() s:Destroy() end)
end

function Workshop:shutterTo(down: boolean)
	local s = self.shutter
	s.Visible = true
	self:doorSound(down)
	local function place(y: number)
		local shake = self.doorShake * (Prefs.get("shake") or 1)
		local jolt = shake > 0.2 and math.floor(math.sin(os.clock() * 95) * shake + 0.5) or 0
		s.Position = UDim2.new(0, 0, y, jolt)
	end
	if down then
		-- never drop a door whose picture hasn't loaded yet
		local img = s:FindFirstChild("DoorImage") :: ImageLabel?
		if img and not img.IsLoaded then
			s.Position = UDim2.fromScale(0, 0)
			local waited = 0
			while not img.IsLoaded and waited < 1 do
				waited += RunService.RenderStepped:Wait()
			end
		end
		place(0)
		local dur, t, nextHit = 0.62, 0, 1
		while t < dur do
			t += RunService.RenderStepped:Wait()
			local k = math.min(t / dur, 1)
			while nextHit <= #DOOR_HITS and k >= DOOR_HITS[nextHit] do
				self:doorHit(DOOR_HIT_POWER[nextHit], false)
				nextHit += 1
			end
			place(bounceOut(k))
		end
		local settle = 0
		while self.doorShake > 0.2 and settle < 0.3 do
			settle += RunService.RenderStepped:Wait()
			place(1)
		end
		s.Position = UDim2.fromScale(0, 1)
	else
		place(1)
		self:doorHit(0.35, true)
		local dur, t = 0.5, 0
		while t < dur do
			t += RunService.RenderStepped:Wait()
			local k = math.min(t / dur, 1)
			place(1 - k * k)
		end
		s.Visible = false
		s.Position = UDim2.fromScale(0, 0)
	end
end

-- a burst of sparks along the bottom of the screen, where the door meets the floor
function Workshop:doorHit(power: number, scrape: boolean)
	local layer = self.sparkLayer
	if not layer then return end
	local size = layer.AbsoluteSize
	local count = math.floor((scrape and 18 or 50) * power + 4)
	for _ = 1, count do
		local p = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
			Size = UDim2.fromOffset(6, 2), ZIndex = 412, Parent = layer,
		})
		UI.mk("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 104, 24), Color3.fromRGB(255, 240, 190)),
			Parent = p,
		})
		local side = math.random() < 0.5 and -1 or 1
		table.insert(self.sparks, {
			ui = p,
			x = math.random() * size.X,
			y = size.Y - 3,
			vx = side * (scrape and (300 + math.random() * 700) or (80 + math.random() * 620)),
			vy = scrape and -(60 + math.random() * 220) or -(260 + math.random() * 720) * math.sqrt(power),
			life = (scrape and 0.2 or 0.3) + math.random() * 0.35,
			age = 0,
			floor = size.Y - 3,
		})
	end
	self.doorShake = math.max(self.doorShake, scrape and 2.5 or 10 * power)
	if self.doorDust and not scrape then
		self.doorDust.BackgroundTransparency = 1 - 0.5 * power
		UI.tween(self.doorDust, 0.55, { BackgroundTransparency = 1 })
	end
end

function Workshop:stepSparks(dt: number)
	self.doorShake = math.max(0, (self.doorShake or 0) - dt * 40)
	local list = self.sparks
	if not list or #list == 0 then return end
	for i = #list, 1, -1 do
		local sp = list[i]
		sp.age += dt
		if sp.age >= sp.life or not sp.ui.Parent then
			sp.ui:Destroy()
			table.remove(list, i)
		else
			sp.vy += 1900 * dt
			sp.vx *= 1 - math.min(1, 1.1 * dt)
			sp.x += sp.vx * dt
			sp.y += sp.vy * dt
			-- skip once off the floor
			if sp.y > sp.floor and sp.vy > 0 then
				sp.y = sp.floor
				sp.vy *= -0.3
			end
			local speed = math.sqrt(sp.vx * sp.vx + sp.vy * sp.vy)
			sp.ui.Position = UDim2.fromOffset(sp.x, sp.y)
			sp.ui.Rotation = math.deg(math.atan2(sp.vy, sp.vx))
			sp.ui.Size = UDim2.fromOffset(math.clamp(speed * 0.024, 3, 26), 2)
			sp.ui.BackgroundTransparency = (sp.age / sp.life) ^ 2
		end
	end
end

function Workshop:open(plot: Instance?): boolean
	if self.isOpen or self.busy then return false end
	self.plot = plot
	if not self.profile then
		self.hub:toast("Still loading your save.", T.bad)
		return false
	end
	self.busy = true
	self:dressDoor()
	task.spawn(function()
		self:shutterTo(true)
		if self.onEnter then pcall(self.onEnter) end
		local ok, err = pcall(function() self:enterRoom() end)
		if not ok then
			warn("[TyreCannon] workbench failed to open: " .. tostring(err))
			pcall(function() self:exitRoom() end)
			if self.onExit then pcall(self.onExit) end
			self.hub:toast("The workbench jammed. Try again.", T.bad)
		end
		if ok and self.room and not self.preparedDone then
			pcall(function() game:GetService("ContentProvider"):PreloadAsync(self.room.folder:GetDescendants()) end)
			self.preparedDone = true
		end
		-- lamps straight to full, then give the lighting a real moment to settle on the
		-- new room before the door lifts: at least 1.4 s and 45 rendered frames
		if ok and self.room then pcall(function() self.room:snap() end) end
		local litFrom, frames = os.clock(), 0
		while os.clock() - litFrom < 1.4 or frames < 45 do
			RunService.RenderStepped:Wait()
			frames += 1
			if os.clock() - litFrom > 4 then break end
		end
		self:shutterTo(false)
		self.busy = false
	end)
	return true
end

function Workshop:close()
	if not self.isOpen or self.busy then return end
	if self.retread.forging then
		self:toast("Finish the strikes first.", T.bad)
		return
	end
	self.busy = true
	self:dressDoor()
	task.spawn(function()
		self:shutterTo(true)
		pcall(function() self:exitRoom() end)
		if self.onExit then pcall(self.onExit) end
		task.wait(0.12)
		self:shutterTo(false)
		self.busy = false
	end)
end

function Workshop:enterRoom()
	if not self.room then self.room = Room.build(ROOM_ORIGIN) end
	self.room.folder.Parent = workspace
	self:overrideLighting(true)
	self.tryOn = nil
	self.pending = 0
	self:readProfile()
	self.yaw, self.roll, self.spin, self.spinKick, self.spinHold = 0, 0, 0, 0, 0
	if self.wheel and self.wheel.Parent then
		self:refreshWheel()
	else
		self:buildWheel()
	end
	self.room:swing(1)
	self.isOpen = true
	self.root.Visible = true
	-- the build tag sits where the tray is, so it hides while the workbench is open
	local tag = self.gui:FindFirstChild("BuildTag") :: GuiObject?
	if tag then tag.Visible = false end
	self.station = "Fit"
	self:setStation("Fit", true)
	do
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = self.camCF
		cam.FieldOfView = self.camFov
		cam.Focus = CFrame.new(self.camGoal.focus)
	end
	self:bindInput()
	self.gifts:enter()
	self:setProfile(self.profile)
	table.insert(self.conns, RunService.RenderStepped:Connect(function(dt) self:step(dt) end))
end

function Workshop:exitRoom()
	self.isOpen = false
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
	pcall(function() self.stickers:leave() end)
	pcall(function() self.retread:leave() end)
	pcall(function() self.wall:leave() end)
	pcall(function() self.gifts:leave() end)
	pcall(function() self.rack:cancelDrag() end)
	self.fx:clear()
	self.tryOn = nil
	self.turning = false
	self:highlightWheel(nil)
	-- the room and the wheel stay built, far above the map, so the next open is instant
	self:overrideLighting(false)
	self.root.Visible = false
	local tag = self.gui:FindFirstChild("BuildTag") :: GuiObject?
	if tag then tag.Visible = true end
	self.station = "Fit"
end

--==============================================================
-- lighting: black room, one lamp
--==============================================================
function Workshop:overrideLighting(on: boolean)
	if on then
		if self.saved then return end
		local saved = { props = {}, effects = {}, atmosphere = nil }
		for _, k in ipairs(LIGHT_KEYS) do saved.props[k] = (Lighting :: any)[k] end
		for _, e in ipairs(Lighting:GetChildren()) do
			if e:IsA("PostEffect") then
				saved.effects[e] = e.Enabled
				e.Enabled = false
			elseif e:IsA("Atmosphere") then
				saved.atmosphere = { inst = e, Density = e.Density, Haze = e.Haze, Glare = e.Glare }
				e.Density = 0
				e.Haze = 0
				e.Glare = 0
			end
		end
		self.saved = saved
		Lighting.Ambient = Color3.fromRGB(26, 23, 20)
		Lighting.OutdoorAmbient = Color3.fromRGB(10, 9, 8)
		Lighting.Brightness = 0
		Lighting.EnvironmentDiffuseScale = 0
		Lighting.EnvironmentSpecularScale = 0.25
		Lighting.ExposureCompensation = 0.35
		Lighting.GlobalShadows = true
		local cam = workspace.CurrentCamera
		self.dof = UI.mk("DepthOfFieldEffect", {
			Name = "WorkshopFocus", FarIntensity = 0.5, NearIntensity = 0.25, InFocusRadius = 5, FocusDistance = 16, Parent = cam,
		})
		self.post = {
			UI.mk("ColorCorrectionEffect", {
				Name = "WorkshopGrade", Contrast = 0.14, Saturation = -0.05, Brightness = 0.01,
				TintColor = Color3.fromRGB(255, 247, 238), Parent = cam,
			}),
			UI.mk("BloomEffect", { Name = "WorkshopBloom", Intensity = 0.5, Size = 28, Threshold = 1.4, Parent = cam }),
			self.dof,
		}
	else
		local saved = self.saved
		if not saved then return end
		self.saved = nil
		for k, v in pairs(saved.props) do (Lighting :: any)[k] = v end
		for e, enabled in pairs(saved.effects) do
			if e.Parent then e.Enabled = enabled end
		end
		local a = saved.atmosphere
		if a and a.inst.Parent then
			a.inst.Density = a.Density
			a.inst.Haze = a.Haze
			a.inst.Glare = a.Glare
		end
		for _, e in ipairs(self.post or {}) do e:Destroy() end
		self.post = nil
		self.dof = nil
	end
end

--==============================================================
-- the wheel on the balancer
--==============================================================
function Workshop:readProfile()
	local p = self.profile
	if not p then return end
	self.preview.skin = p.skin or "stock"
	self.preview.rim = p.rim or "steel"
	self.preview.trail = p.trail or "none"
end

function Workshop:wheelCF(): CFrame
	return self.room.wheelBase * CFrame.Angles(0, self.yaw, 0) * CFrame.Angles(0, 0, -self.roll)
end

function Workshop:buildWheel()
	if self.wheel then self.wheel:Destroy() end
	self.fx:clear()
	local wheel = WheelAssembly.build(self.room.folder, {
		diameter = Workshop.WHEEL_DIAMETER,
		skin = self.preview.skin,
		rim = self.preview.rim,
		name = "BenchWheel",
	})
	for _, d in ipairs(wheel:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Root" then d.CastShadow = true end
	end
	self.wheel = wheel
	wheel:PivotTo(self:wheelCF())
	self.fx:trail(self.preview.trail, false)
	self.stickers:dress(true)
end

-- brings a wheel that's already built up to date with the save, cheaply
function Workshop:refreshWheel()
	local wheel = self.wheel
	if not wheel then return end
	self.fx:clear()
	WheelAssembly.setSkin(wheel, self.preview.skin)
	if wheel:GetAttribute("Rim") ~= self.preview.rim then
		WheelAssembly.setRim(wheel, self.preview.rim)
		local hub = wheel:FindFirstChild("Hub")
		if hub then
			for _, d in ipairs(hub:GetDescendants()) do
				if d:IsA("BasePart") then d.CastShadow = true end
			end
		end
	end
	wheel:PivotTo(self:wheelCF())
	self.fx:trail(self.preview.trail, false)
	self.stickers:dress(false)
end

function Workshop:highlightWheel(color: Color3?)
	local h = self.highlight
	if not h then
		h = Instance.new("Highlight")
		h.Name = "WorkshopWheelHighlight"
		h.FillTransparency = 0.86
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		self.highlight = h
	end
	if color and self.wheel and self.room then
		h.Adornee = self.wheel
		h.OutlineColor = color
		h.FillColor = color
		h.Parent = self.room.folder
		h.Enabled = true
	else
		h.Enabled = false
	end
end

-- a camera move for a moment of drama. rate is how quickly it catches up (5 is the
-- station default); call with no eye to hand back to the station camera
-- a critically damped spring: eases in and out, and a new target picks up from wherever
-- the value is already heading
local function spring(x: Vector3, v: Vector3, target: Vector3, w: number, dt: number): (Vector3, Vector3)
	local d = x - target
	local e = math.exp(-w * dt)
	local j = v + d * w
	return target + (d + j * dt) * e, (v - j * (w * dt)) * e
end

-- where a tray sits when it's showing, remembered the first time it moves
local function trayRest(frame: GuiObject): UDim2
	local rest = frame:GetAttribute("RestPosition") :: UDim2?
	if not rest then
		rest = frame.Position
		frame:SetAttribute("RestPosition", rest)
	end
	return rest :: UDim2
end

-- keeps a camera position out of the room's props. A camera inside one is pushed out of
-- its nearest face; unless pushOnly, a prop between the camera and what it looks at
-- brings the camera in front of it. Props that hold the focus itself are ignored.
function Workshop:guardEye(eye: Vector3, focus: Vector3, pushOnly: boolean?): Vector3
	local solids = self.room and self.room.solids
	if not solids then return eye end
	local margin = Vector3.one * 0.7
	for _, s in ipairs(solids) do
		local h = s.half + margin
		local f = s.cf:PointToObjectSpace(focus)
		if not (math.abs(f.X) < h.X and math.abs(f.Y) < h.Y and math.abs(f.Z) < h.Z) then
			local p = s.cf:PointToObjectSpace(eye)
			local dx, dy, dz = h.X - math.abs(p.X), h.Y - math.abs(p.Y), h.Z - math.abs(p.Z)
			if dx > 0 and dy > 0 and dz > 0 then
				if dx <= dy and dx <= dz then
					p = Vector3.new((p.X >= 0 and 1 or -1) * h.X, p.Y, p.Z)
				elseif dz <= dy then
					p = Vector3.new(p.X, p.Y, (p.Z >= 0 and 1 or -1) * h.Z)
				else
					p = Vector3.new(p.X, (p.Y >= 0 and 1 or -1) * h.Y, p.Z)
				end
				eye = s.cf:PointToWorldSpace(p)
			elseif not pushOnly then
				local dir = p - f
				local t0, t1 = 0, 1
				local crosses = true
				for _, ax in ipairs({ "X", "Y", "Z" }) do
					local d = (dir :: any)[ax]
					local o = (f :: any)[ax]
					local lim = (h :: any)[ax]
					if math.abs(d) < 1e-6 then
						if math.abs(o) >= lim then crosses = false break end
					else
						local ta, tb = (-lim - o) / d, (lim - o) / d
						if ta > tb then ta, tb = tb, ta end
						t0, t1 = math.max(t0, ta), math.min(t1, tb)
						if t0 > t1 then crosses = false break end
					end
				end
				if crosses and t0 > 0 and t0 < 1 then
					eye = s.cf:PointToWorldSpace(f + dir * math.max(0, t0 - 0.02))
				end
			end
		end
	end
	return eye
end

function Workshop:shot(eye: Vector3?, look: Vector3?, fov: number?, rate: number?)
	local room = self.room
	if not room then return end
	if not (eye and look) then
		self.camGoal = room.stations[self.station]
		return
	end
	self.camGoal = { cf = CFrame.lookAt(eye, look), fov = fov or self.camFov, focus = look, look = look, rate = rate }
end

-- a jolt that dies away on its own; bigger numbers shake harder
function Workshop:shake(amount: number)
	self.shakeAmp = math.max(self.shakeAmp or 0, amount * (Prefs.get("shake") or 1))
end

function Workshop:mouseRay(pos: Vector2?): Ray
	local p = pos or UserInputService:GetMouseLocation()
	return workspace.CurrentCamera:ViewportPointToRay(p.X, p.Y)
end

function Workshop:hitWheel(pos: Vector2?)
	local wheel = self.wheel
	if not wheel or not wheel.PrimaryPart then return nil end
	local ray = self:mouseRay(pos)
	return WheelAssembly.raycast(wheel, ray.Origin, ray.Direction * 200)
end

function Workshop:overWheel(pos: Vector2): boolean
	local wheel = self.wheel
	if not wheel or not wheel.PrimaryPart then return false end
	if self:hitWheel(pos) then return true end
	local cam = workspace.CurrentCamera
	local c = wheel.PrimaryPart.Position
	local sp, onScreen = cam:WorldToViewportPoint(c)
	if not onScreen then return false end
	local edge = cam:WorldToViewportPoint(c + cam.CFrame.UpVector * (Workshop.WHEEL_DIAMETER / 2))
	local r = math.abs(edge.Y - sp.Y)
	return (Vector2.new(sp.X, sp.Y) - pos).Magnitude <= r * 1.2
end

--==============================================================
-- stations
--==============================================================
function Workshop:setStation(name: string, instant: boolean?)
	local old = self.station
	if old == "Retread" and name ~= "Retread" and self.retread.forging then
		self:toast("Finish the strikes first.", T.bad)
		return
	end
	if name ~= "Fit" and self.tryOn then self:putBack() end
	if old == "Stickers" and name ~= "Stickers" then
		self.stickers:leave()
		self.yawGoal = nil
		self.yaw = (self.yaw + math.pi) % (2 * math.pi) - math.pi
	end
	if old == "Retread" and name ~= "Retread" then self.retread:leave() end
	if old == "Wall" and name ~= "Wall" then self.wall:leave() end
	self.station = name
	for n, b in pairs(self.tabButtons) do
		UI.setButtonStyle(b, n == name and "primary" or "ghost")
	end
	local trays = { Fit = self.rack, Stickers = self.stickers, Retread = self.retread, Wall = self.wall }
	for n, t in pairs(trays) do
		if instant or old == name then
			t:setVisible(n == name)
		elseif n == name then
			-- the new tray fades up once the old one has gone, while the camera moves
			local rest = trayRest(t.frame)
			t:setVisible(true)
			UI.fade(t.frame, true, { rest = rest, delay = 0.22, dur = 0.34, offset = 40 })
		elseif n == old then
			UI.fade(t.frame, false, { rest = trayRest(t.frame), dur = 0.22, offset = 30 }, function()
				if self.station ~= n then t:setVisible(false) end
			end)
		else
			t:setVisible(false)
		end
	end
	local st = self.room.stations[name]
	self.camGoal = st
	if instant or not self.camCF then
		self.camCF = st.cf
		self.camFov = st.fov
		self.camEye = st.cf.Position
		self.camLook = st.look or (st.cf.Position + st.cf.LookVector * 12)
		self.camEyeV, self.camLookV = Vector3.zero, Vector3.zero
	end
	self.room:focus(name)
	if name == "Stickers" and (old ~= "Stickers" or instant) then self.stickers:enter() end
	if name == "Retread" and (old ~= "Retread" or instant) then self.retread:enter() end
	if name == "Wall" and (old ~= "Wall" or instant) then self.wall:enter() end
	if name == "Fit" then self.rack:refresh() end
end

function Workshop:bindInput()
	table.insert(self.conns, UserInputService.InputBegan:Connect(function(input, gpe)
		if not self.isOpen or self.busy then return end
		if input.KeyCode == Enum.KeyCode.ButtonB then
			self:close()
			return
		end
		if gpe or UserInputService:GetFocusedTextBox() then return end
		local st = STATION_KEYS[input.KeyCode]
		if st then
			self:setStation(st)
			return
		end
		if self.station == "Fit" and isPress(input) and not self.rack.drag then
			self.turning = true
		end
	end))
	table.insert(self.conns, UserInputService.InputChanged:Connect(function(input)
		if not self.turning then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			self.yaw = math.clamp(self.yaw + input.Delta.X * 0.012, -math.pi, math.pi)
		end
	end))
	table.insert(self.conns, UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then self.turning = false end
	end))
end

function Workshop:step(dt: number)
	local room = self.room
	if not room then return end
	local target = 0
	if self.station == "Fit" and self.spinHold <= 0 then
		target = (self.fx:hasTrail() and self.rack.tab == "Trails") and 2.6 or 0.7
	end
	if self.spinKick > 0 then
		target = math.max(target, self.spinKick)
		self.spinKick = math.max(0, self.spinKick - dt * 3)
	end
	self.spin += (target - self.spin) * (1 - math.exp(-dt * 2.5))
	self.roll += self.spin * dt
	if self.station == "Fit" and not self.turning then
		self.yaw += (0 - self.yaw) * (1 - math.exp(-dt * 1.2))
	elseif self.station == "Stickers" and self.yawGoal then
		self.yaw += (self.yawGoal - self.yaw) * (1 - math.exp(-dt * 7))
	end
	local wheel = self.wheel
	if wheel and wheel.PrimaryPart then
		wheel:PivotTo(self:wheelCF())
		self.fx:step(dt)
	end

	local goal = self.camGoal
	if goal then
		local cam = workspace.CurrentCamera
		local rate = goal.rate or 5
		local a = 1 - math.exp(-dt * rate)
		local look = goal.look or (goal.cf.Position + goal.cf.LookVector * 12)
		local focus = goal.focus or look
		local eye = self:guardEye(goal.cf.Position, focus)
		if not self.camEye then
			self.camEye, self.camLook = eye, look
			self.camEyeV, self.camLookV = Vector3.zero, Vector3.zero
		end
		-- the eye and the aim each ride a spring, the aim a little ahead, so every move
		-- eases out and in and a new shot carries on from the current motion
		local w = rate * 1.15
		self.camEye, self.camEyeV = spring(self.camEye, self.camEyeV, eye, w, dt)
		self.camLook, self.camLookV = spring(self.camLook, self.camLookV, look, w * 1.25, dt)
		self.camEye = self:guardEye(self.camEye, focus, true)
		self.camCF = CFrame.lookAt(self.camEye, self.camLook)
		self.camFov += (goal.fov - self.camFov) * a
		cam.CameraType = Enum.CameraType.Scriptable
		local shake = CFrame.new()
		local amp = self.shakeAmp or 0
		if amp > 0.002 then
			self.shakeAmp = amp * math.exp(-dt * 8)
			local now = os.clock()
			shake = CFrame.Angles(math.noise(now * 21, 1.3) * 0.05 * amp, math.noise(now * 19, 7.1) * 0.05 * amp, math.noise(now * 17, 3.7) * 0.03 * amp)
		end
		cam.CFrame = self.camCF * shake
		cam.Focus = CFrame.new(goal.focus)
		cam.FieldOfView = self.camFov
		if self.dof then self.dof.FocusDistance = (self.camCF.Position - goal.focus).Magnitude end
	end

	room:step(dt)
	self.rack:step(dt)
	self.gifts:step(dt)
	if self.station == "Stickers" then
		self.stickers:step(dt)
	elseif self.station == "Retread" then
		self.retread:step(dt)
	elseif self.station == "Wall" then
		self.wall:step(dt)
	end
end

--==============================================================
-- parts: fit, try on, buy, put back
--==============================================================
function Workshop:ownsItem(def, item): boolean
	local p = self.profile
	if not p then return false end
	if item.id == def.default then return true end
	return (p[def.cat] and p[def.cat][item.id] == true)
		or (p.permanent and p.permanent[def.cat] and p.permanent[def.cat][item.id] == true)
		or false
end

function Workshop:applyPreview(def, id: string, animate: boolean)
	self.preview[def.field] = id
	if not self.wheel then return end
	if def.kind == "skin" then
		self.fx:skin(id, animate)
	elseif def.kind == "rim" then
		self.fx:rim(id, animate)
	elseif def.kind == "trail" then
		self.fx:trail(id, animate)
	end
end

function Workshop:useItem(def, item)
	local p = self.profile
	if not p or not self.wheel or self.busy then return end
	local t = self.tryOn
	if t and t.item == item then
		self.fx:admire()
		return
	end
	if t then self:putBack(true) end
	if (p[def.field] or def.default) == item.id then
		self.fx:admire()
		self.rack:refresh()
		return
	end
	if self:ownsItem(def, item) then
		self.pending += 1
		self:applyPreview(def, item.id, true)
		task.spawn(function()
			local res = self:call("EquipCosmetic", def.kind, item.id)
			self.pending -= 1
			if res and res.ok then
				self.room:celebrate(Config.CosmeticTier(item))
				self:toast("FITTED  " .. string.upper(item.name), T.good)
			elseif self.profile then
				self:applyPreview(def, self.profile[def.field] or def.default, false)
			end
			self.rack:refresh()
		end)
	else
		self.tryOn = { def = def, item = item }
		self:applyPreview(def, item.id, true)
	end
	self.rack:refresh()
end

function Workshop:buyTryOn()
	local t = self.tryOn
	local p = self.profile
	if not t or not p or self.pending > 0 then return end
	local def, item = t.def, t.item
	if self:ownsItem(def, item) then
		self.tryOn = nil
		self.pending += 1
		task.spawn(function()
			local res = self:call("EquipCosmetic", def.kind, item.id)
			self.pending -= 1
			if res and res.ok then self.room:celebrate(Config.CosmeticTier(item)) end
			self.rack:refresh()
		end)
		return
	end
	if item.robux then
		if (item.devProductId or 0) == 0 then
			self:toast("Not on sale yet.", T.bad)
		else
			(Remotes :: any).BuyRobux:FireServer(def.kind, item.id)
		end
		return
	end
	if item.locked then
		self:toast("Earned, not bought.", T.bad)
		return
	end
	if p.credits < (item.cost or 0) then
		self:toast(("Need %s more credits."):format(UI.comma(item.cost - p.credits)), T.bad)
		return
	end
	self.pending += 1
	task.spawn(function()
		local res = self:call("BuyItem", def.kind, item.id)
		self.pending -= 1
		if res and res.ok then
			if self.tryOn and self.tryOn.item == item then self.tryOn = nil end
			self.room:celebrate(Config.CosmeticTier(item), true)
			self.fx:admire()
			local tier = Config.CosmeticTier(item)
			UI.stamp(self.gui, item.name, Config.TierColor(tier), string.upper(tier) .. "  ·  BOUGHT AND FITTED")
		end
		self.rack:refresh()
	end)
end

function Workshop:putBack(quiet: boolean?)
	local t = self.tryOn
	if not t then return end
	self.tryOn = nil
	local p = self.profile
	self:applyPreview(t.def, (p and p[t.def.field]) or t.def.default, false)
	if not quiet then self.rack:refresh() end
end

--==============================================================
-- profile and plumbing
--==============================================================
function Workshop:setProfile(p)
	if not p then return end
	self.profile = p
	local bits = { UI.comma(p.credits or 0) .. " CR" }
	for _, m in ipairs(Config.Metals) do
		table.insert(bits, ("%s %s"):format(UI.comma((p.metals or {})[m.id] or 0), string.upper(m.name:sub(1, 2))))
	end
	if (p.tokens or 0) > 0 then table.insert(bits, ("%d TOKEN%s"):format(p.tokens, p.tokens == 1 and "" or "S")) end
	self.creditsLabel.Text = table.concat(bits, "   ·   ")
	if not self.isOpen then return end

	local t = self.tryOn
	if t and p[t.def.field] == t.item.id then
		-- a Robux purchase landed while it was on the wheel
		self.tryOn = nil
		self.room:celebrate(Config.CosmeticTier(t.item), true)
	end
	if not self.tryOn and self.pending == 0 then
		for _, def in ipairs(Rack.KINDS) do
			local want = p[def.field] or def.default
			if self.preview[def.field] ~= want then self:applyPreview(def, want, false) end
		end
	end
	self.rack:refresh()
	self.stickers:refresh()
	self.retread:refresh()
	self.wall:refresh()
	self.gifts:refresh()
end

function Workshop:call(name: string, ...: any)
	local res = self.hub:call(name, ...)
	if type(res) == "table" and res.profile then self.profile = res.profile end
	return res
end

function Workshop:toast(text: string, color: Color3?)
	self.hub:toast(text, color or T.text)
end

--==============================================================
-- the door, and warming everything up before the first open
--==============================================================
-- everything the door wears, from the save: paint, stencil, stickers
function Workshop:doorOptions(): { [string]: any }
	local p = self.profile
	local prefs = p and p.prefs or {}
	return {
		paint = prefs.doorPaint, stencil = prefs.doorStencil, name = prefs.rigName,
		number = self.plot and self.plot:GetAttribute("Index") or 0,
		stickers = p and p.stickers or {}, catalogue = WheelAssembly.stickers(),
		seed = game:GetService("Players").LocalPlayer.UserId % 100000 + 7,
	}
end

function Workshop:dressDoor()
	local layer = self.doorStickers
	if not layer then return end
	local opts = self:doorOptions()
	opts.image = false
	opts.zIndex = 405
	DoorArt.paint(layer, opts)
	local img = self.shutter:FindFirstChild("DoorImage") :: ImageLabel?
	local paint = Config.DoorPaintsById[opts.paint or "steel"] or Config.DoorPaints[1]
	if img then img.ImageColor3 = paint.tint end
end

-- builds the room, the wheel and its stickers, the sticker sheet and the
-- first row of cards while nobody's looking, so the first open is instant
function Workshop:prepare()
	if self.prepared then return end
	self.prepared = true
	if not self.room then self.room = Room.build(ROOM_ORIGIN) end
	local ids = {}
	for _, e in ipairs(WheelAssembly.stickers().list) do table.insert(ids, e.texture) end
	local door = Config.Workshop and Config.Workshop.DoorImage
	if door and door ~= "" then table.insert(ids, door) end
	task.spawn(function()
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(ids) end)
	end)
	self.stickers:buildSheet()
	self.rack:prebuild()
	pcall(function()
		self.wall:build()
		self.wall:refresh()
	end)
	if self.isOpen or self.busy then return end
	self.room.folder.Parent = workspace
	self:readProfile()
	if not self.wheel then self:buildWheel() end
	-- load every mesh and texture in the room now, not behind the shutter later
	local list = self.room.folder:GetDescendants()
	pcall(function() game:GetService("ContentProvider"):PreloadAsync(list) end)
	self.preparedDone = true
end

return Workshop
