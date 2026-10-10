--!strict
-- TYRE CANNON :: Title
-- The title is the game: the Backroad itself in its late-afternoon light, a cannon at the head of
-- the road firing a tyre down it every few seconds (a different collectable each time), and the
-- camera cutting between a low hero angle on the cannon, a chase behind the tyre as it lands and
-- bounds away, and a high wide over the fields. The logo sits over it; PLAY (or Enter / A) dips to
-- black and you're stood in the lobby. It's built behind the loading door (TitleReady lifts the
-- door; DoorUp brings the logo in) and IntroPlaying stays set until you're in.
--   Title.run(gui)   blocks until PLAY

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Game = require(Modules:WaitForChild("Game"))
local TrackGen = require(Modules:WaitForChild("TrackGen"))
local WorldView = require(script.Parent.WorldView)
local Models = require(script.Parent.Models)
local TyreLook = require(script.Parent.TyreLook)
local MuzzleFX = require(script.Parent.MuzzleFX)
local PackFX = require(script.Parent.PackFX)
local DayNight = require(script.Parent.DayNight)
local Sound = require(script.Parent.Sound)
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local C = Kit.C

local Title = {}

local CANNON = "Cannons/Cannon3"
local CANNON_SCALE = 0.667
local CANNON_X = -38
local TYRE_D = 7.4
local GRAVITY = Vector3.new(0, -60, 0)
local LOGO = "rbxassetid://83949485296533" -- the 3D logo (art/blender/icon_studio.py: logo)
local LOGO_W, LOGO_ASPECT = 330, 685 / 572
-- the shots, in order, and how long each holds
local SHOTS = { { "hero", 3.4 }, { "chase", 3.0 }, { "wide", 3.8 } }

-- the title's light: late afternoon, the sun low and warm behind the cannon, a gold haze over the
-- fields. Set on the way in, handed back to the day-night cycle on PLAY. No sun rays.
local TITLE_LIGHT = {
	ClockTime = 17.3, Brightness = 2.6, ExposureCompensation = 0.05, GeographicLatitude = 28,
	Ambient = Color3.fromRGB(84, 72, 66), OutdoorAmbient = Color3.fromRGB(156, 132, 112),
}
local TITLE_AIR = { Density = 0.3, Offset = 0.12, Haze = 1.8, Glare = 0.35, Color = Color3.fromRGB(255, 208, 156), Decay = Color3.fromRGB(196, 132, 96) }

local function golden(on: boolean, saved: any): any
	local L = game:GetService("Lighting")
	if on then
		saved = { light = {}, air = {}, rays = nil, cc = nil }
		for k, v in pairs(TITLE_LIGHT) do
			saved.light[k] = (L :: any)[k]
			;(L :: any)[k] = v
		end
		local air = L:FindFirstChildOfClass("Atmosphere")
		if air then
			for k, v in pairs(TITLE_AIR) do
				saved.air[k] = (air :: any)[k]
				;(air :: any)[k] = v
			end
		end
		local rays = L:FindFirstChildOfClass("SunRaysEffect")
		if rays then
			saved.rays = rays.Enabled
			rays.Enabled = false
		end
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "TitleGrade"
		cc.Saturation = 0.14
		cc.Contrast = 0.08
		cc.TintColor = Color3.fromRGB(255, 244, 232)
		cc.Parent = L
		saved.cc = cc
		return saved
	end
	if not saved then return nil end
	for k, v in pairs(saved.light) do (L :: any)[k] = v end
	local air = L:FindFirstChildOfClass("Atmosphere")
	if air then
		for k, v in pairs(saved.air) do (air :: any)[k] = v end
	end
	local rays = L:FindFirstChildOfClass("SunRaysEffect")
	if rays and saved.rays ~= nil then rays.Enabled = saved.rays end
	if saved.cc then saved.cc:Destroy() end
	return nil
end

-- the set round the cannon: the Backroad's own models (path, x, z, yaw, scale), seated on the ground
local DRESSING = {
	{ "Scenery/backroad/TubeWell", -64, 34, 200, 1 }, { "Scenery/backroad/Kup", -78, -30, 0, 1 }, { "Scenery/backroad/Kup", -66, -44, 40, 0.85 },
	{ "Scenery/backroad/Tractor", -20, -36, 120, 1 }, { "Scenery/backroad/Buffalo", -46, 42, 70, 1 }, { "Scenery/backroad/VillageHouse", -110, 52, 160, 1 },
	{ "Scenery/backroad/MustardPatch", 10, 30, 0, 1.6 }, { "Scenery/backroad/MustardPatch", 34, 38, 50, 1.6 }, { "Scenery/backroad/MustardPatch", 22, -34, 20, 1.6 },
	{ "Scenery/backroad/MustardPatch", 60, -40, 70, 1.6 }, { "Scenery/backroad/Fence", -40, 24, 0, 1 }, { "Scenery/backroad/Fence", -6, 24, 0, 1 },
	{ "Scenery/backroad/Goat", -30, 30, 300, 1 }, { "Scenery/backroad/KilnChimney", 180, 140, 0, 1 },
}
for i = 0, 11 do
	table.insert(DRESSING, { "Scenery/backroad/Poplar", -90 + i * 34, 64 + (i % 2) * 6, i * 37, 1 })
	table.insert(DRESSING, { "Scenery/backroad/Poplar", -70 + i * 40, -70 - (i % 2) * 8, i * 53, 1 })
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function ns(list: { { number } }): NumberSequence
	local k = {}
	for _, p in ipairs(list) do table.insert(k, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(k)
end

-- the placed cannon's muzzle and the way its bore points (AssetInfo), as LaunchShow2 finds them
local function aim(holder: Model, scale: number): (Vector3?, Vector3?)
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("Model") then
			local info = Models.info(child.Name) :: any
			if info and info.muzzle and info.elev then
				local pivot = child:GetPivot()
				local m = info.muzzle
				local muzzle = pivot * (Models.toRoblox(m[1], m[2], m[3]) * scale)
				local e = math.rad(info.elev)
				return muzzle, pivot:VectorToWorldSpace(Vector3.new(math.cos(e), math.sin(e), 0)).Unit
			end
		end
	end
	return nil, nil
end

function Title.run(gui: ScreenGui)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local cam = workspace.CurrentCamera
	local tpl = Models.get(CANNON)
	if not tpl then
		-- nothing to show yet: the loader does its old sweep instead
		playerGui:SetAttribute("TitleSkipped", true)
		return
	end
	local dn = (DayNight :: any).current
	if dn then dn:setActive(false) end

	-- the set: the real road, built from its start, and a cannon at its head
	local road = TrackGen.get("road")
	road:setRun(Random.new():NextInteger(1, 1e6), 0, 0)
	local world = WorldView.new("road")
	world:ensure(0)
	world:update(0, 0)
	-- the road's own zone look would hold the Backroad's midday light: the title has its own
	if world.look then
		world.look:destroy()
		world.look = nil
	end
	local lightSaved = golden(true, nil)
	local folder = Instance.new("Folder")
	folder.Name = "TitleSet"
	folder.Parent = workspace
	local gy = road:heightAt(0)
	-- dress the set
	for _, d in ipairs(DRESSING) do
		local tplD = Models.get(d[1])
		if tplD then
			local m = Instance.new("Model")
			m.Name = "Dressing"
			local placed = Models.place(tplD, m, CFrame.new(d[2], 0, d[3]) * CFrame.Angles(0, math.rad(d[4]), 0), d[5])
			local bcf, bsize = placed:GetBoundingBox()
			local floor = road:heightAt(math.max(d[2], 0))
			placed:PivotTo(placed:GetPivot() + Vector3.new(0, floor - (bcf.Position.Y - bsize.Y / 2) - 0.2, 0))
			m.Parent = folder
		end
	end
	local holder = Instance.new("Model")
	holder.Name = "TitleCannon"
	Models.place(tpl, holder, CFrame.new(CANNON_X, gy, 0), CANNON_SCALE)
	holder.Parent = folder
	local muzzle, dir = aim(holder, CANNON_SCALE)
	local cf, size = holder:GetBoundingBox()
	local mid, S = cf.Position, math.max(size.X, size.Y, size.Z)
	muzzle = muzzle or (mid + Vector3.new(S * 0.4, S * 0.3, 0))
	dir = dir or Vector3.new(0.9, 0.44, 0).Unit
	local barrel = {}
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:find("Barrel") then table.insert(barrel, { part = d, rest = d.CFrame }) end
	end
	local blast = MuzzleFX.new(muzzle :: Vector3, dir :: Vector3)
	-- the tyres' smoke trails, laid along their paths a puff at a time
	local trailPart, trailAtt = MuzzleFX.holder("TitleTrail", CFrame.new(muzzle :: Vector3))
	trailPart.Parent = folder
	local trail = MuzzleFX.emitter(trailAtt, PackFX.Sheet.plume, {
		EmissionDirection = Enum.NormalId.Front, Lifetime = NumberRange.new(0.9, 1.3), Speed = NumberRange.new(0, 2),
		Drag = 1, SpreadAngle = Vector2.new(180, 180), Size = ns({ { 0, 2.6 }, { 1, 8 } }),
		Transparency = ns({ { 0, 0.25 }, { 1, 1 } }), RotSpeed = NumberRange.new(-30, 30), Color = ColorSequence.new(MuzzleFX.Smoke),
	})
	-- every collectable with a model can be the one fired
	local ids = {}
	for _, t in ipairs(Game.Tyres) do
		if t.zone ~= "retired" and TyreLook.has(t.id) then table.insert(ids, t.id) end
	end

	local flying = {}
	local recoilT = math.huge
	local function fire()
		blast:fire(0.35)
		recoilT = 0
		Sound.play("land", { volume = 0.55, pitch = 0.75 })
		Sound.play("gateWhoosh", { volume = 0.4, pitch = 0.85 })
		local id = #ids > 0 and ids[math.random(1, #ids)] or nil
		local m = TyreLook.model(id, TYRE_D, "TitleTyre")
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		m.Parent = folder
		table.insert(flying, { model = m, pos = muzzle :: Vector3, vel = (dir :: Vector3) * 165, spin = 0, born = os.clock(), air = true })
	end

	-- the camera's shots
	local shot, shotT, shotIx = SHOTS[1][1], 0, 1
	local firedThisShot = false
	local chaseFrom: Vector3? = nil
	local function newest()
		return flying[#flying]
	end
	local function frame(): (Vector3, Vector3, number)
		if shot == "hero" then
			-- low behind the cannon's shoulder, looking down the road it fires along (the sun's behind)
			local drift = Vector3.new(shotT * 1.2, 0, 0)
			-- pulled back enough that the whole cannon sits in the left half, clear of the PLAY button
			return mid + Vector3.new(-S * 0.95, S * 0.02, -S * 1.05) + drift, mid + Vector3.new(S * 1.1, S * 0.32, S * 0.35), 56
		elseif shot == "chase" then
			local t = newest()
			if t then
				local at = t.pos
				local want = at + Vector3.new(-24, 7, -10)
				chaseFrom = chaseFrom and (chaseFrom :: Vector3):Lerp(want, 0.18) or want
				return chaseFrom :: Vector3, at + Vector3.new(28, -3, 0), 66
			end
		end
		-- establishing: high over the cannon's shoulder, the road running away between the fields
		local k = smooth(shotT / 3.8)
		local p = Vector3.new(CANNON_X - 70, gy + 44, -56):Lerp(Vector3.new(CANNON_X - 52, gy + 38, -44), k)
		return p, Vector3.new(CANNON_X + 320, gy - 10, 26), 52
	end

	-- the screen: vignette, logo, tagline, PLAY
	local ui = UI.mk("ScreenGui", { Name = "TitleUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
	for _, top in ipairs({ true, false }) do
		local v = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0, top and 0 or 1), Position = UDim2.fromScale(0, top and 0 or 1), Size = UDim2.fromScale(1, top and 0.3 or 0.34),
			BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 1, Parent = ui,
		})
		UI.mk("UIGradient", { Rotation = top and 90 or -90, Transparency = ns({ { 0, 0.45 }, { 1, 1 } }), Parent = v })
	end
	local logoH = math.floor(LOGO_W / LOGO_ASPECT)
	local logo = UI.mk("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(LOGO_W, logoH),
		BackgroundTransparency = 1, GroupTransparency = 1, ZIndex = 5, Parent = ui,
	})
	UI.mk("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = LOGO, ScaleType = Enum.ScaleType.Fit, ZIndex = 6, Parent = logo })
	local tag = Kit.text("Launch it   ·   Upgrade it   ·   Send it further", 18, C.text, 2, Kit.Body)
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 0, 34 + logoH + 8)
	tag.Size = UDim2.fromOffset(640, 22)
	tag.TextTransparency = 1
	tag.ZIndex = 5
	tag.Parent = ui
	local tagStroke = tag:FindFirstChildOfClass("UIStroke")
	if tagStroke then tagStroke.Transparency = 1 end
	local dock = UI.mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -54), Size = UDim2.fromOffset(320, 130), BackgroundTransparency = 1, Visible = false, ZIndex = 5, Parent = ui })
	UI.autoScale(dock, 1280, 760)
	local play = Kit.button("Play", C.accent, UDim2.fromOffset(300, 84), 44)
	play.root.AnchorPoint = Vector2.new(0.5, 0)
	play.root.Position = UDim2.fromScale(0.5, 0)
	play.root.Parent = dock
	local how = UserInputService.GamepadEnabled and "or press A" or (UserInputService.TouchEnabled and "" or "or press Enter")
	local hint = Kit.text(how, 16, C.white, 2, Kit.Body)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 102)
	hint.Size = UDim2.fromOffset(300, 20)
	hint.Parent = dock
	local cover = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 50, Parent = ui })

	-- run the set
	cam.CameraType = Enum.CameraType.Scriptable
	local camCF: CFrame? = nil
	local nextShot = os.clock() + 1.2
	local conn = RunService.RenderStepped:Connect(function(dt)
		cam.CameraType = Enum.CameraType.Scriptable
		shotT += dt
		-- Studio: hold one shot to look at it (workspace TitleShot = "hero" | "chase" | "wide")
		local hold = RunService:IsStudio() and workspace:GetAttribute("TitleShot")
		if hold and shot ~= hold then
			for i, sdef in ipairs(SHOTS) do
				if sdef[1] == hold then shotIx, shot, shotT, camCF, firedThisShot = i, hold, 0, nil, false end
			end
		end
		if hold and shotT >= SHOTS[shotIx][2] then
			shotT, firedThisShot = 0, false
		elseif shotT >= SHOTS[shotIx][2] then
			shotIx = (shotIx % #SHOTS) + 1
			shot, shotT = SHOTS[shotIx][1], 0
			firedThisShot = false
			chaseFrom = nil
			camCF = nil
		end
		-- the hero shot fires a beat in; the wide one fires too, so there's always a tyre in the air
		if not firedThisShot and ((shot == "hero" and shotT > 1.1) or (shot == "wide" and shotT > 1.4)) then
			firedThisShot = true
			fire()
		end
		if os.clock() > nextShot and #flying == 0 then
			nextShot = os.clock() + 3
			fire()
		end
		-- the barrel kicks and settles
		recoilT += dt
		local kick = if recoilT < 0.04 then 2 * recoilT / 0.04 else 2 * math.exp(-(recoilT - 0.04) * 5.5) * math.cos((recoilT - 0.04) * 9)
		for _, b in ipairs(barrel) do b.part.CFrame = b.rest - (dir :: Vector3) * (recoilT < 2 and kick or 0) end
		-- the tyres: out of the muzzle, down onto the road, bounding along it
		local focusX = 0
		for i = #flying, 1, -1 do
			local t = flying[i]
			local from = t.pos
			t.vel += GRAVITY * dt
			t.pos += t.vel * dt
			local g = road:heightAt(math.max(0, t.pos.X)) + TYRE_D / 2
			if t.pos.Y < g then
				t.pos = Vector3.new(t.pos.X, g, t.pos.Z)
				if t.vel.Y < -12 then
					PackFX.burst("dustRing", CFrame.new(t.pos.X, g - TYRE_D / 2 + 0.3, t.pos.Z), 10, road:cfgAt(t.pos.X).ground:Lerp(Color3.new(1, 1, 1), 0.3), 1.2)
				end
				t.vel = Vector3.new(t.vel.X * 0.94, math.max(0, -t.vel.Y * 0.42), t.vel.Z)
				t.air = false
			else
				t.air = true
			end
			if t.air then
				local n = math.min(10, math.ceil((t.pos - from).Magnitude / 1.8))
				for k = 1, n do
					trailAtt.WorldPosition = from:Lerp(t.pos, k / n)
					trail:Emit(1)
				end
			end
			t.spin -= t.vel.X / (TYRE_D / 2) * dt
			t.model:PivotTo(CFrame.new(t.pos) * CFrame.Angles(0, 0, t.spin))
			focusX = math.max(focusX, t.pos.X)
			if os.clock() - t.born > 7 then
				t.model:Destroy()
				table.remove(flying, i)
			end
		end
		world:ensure(math.max(0, focusX))
		world:update(dt, math.max(0, focusX))
		local pos, look, fov = frame()
		local want = CFrame.lookAt(pos, look)
		camCF = if camCF then (camCF :: CFrame):Lerp(want, math.min(1, dt * 8)) else want
		cam.CFrame = camCF :: CFrame
		cam.FieldOfView = fov
	end)
	playerGui:SetAttribute("TitleReady", true)

	-- once the door's up: the logo drops in, the tagline and PLAY follow
	local t0 = os.clock()
	while not playerGui:GetAttribute("DoorUp") and os.clock() - t0 < 20 do task.wait(0.05) end
	task.wait(0.35)
	local rest = logo.Position
	logo.Position = rest - UDim2.fromOffset(0, 60)
	logo.Rotation = -8
	TweenService:Create(logo, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	TweenService:Create(logo, TweenInfo.new(0.16), { GroupTransparency = 0 }):Play()
	TweenService:Create(logo, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = rest }):Play()
	task.wait(0.3)
	TweenService:Create(tag, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	if tagStroke then TweenService:Create(tagStroke, TweenInfo.new(0.3), { Transparency = 0 }):Play() end
	task.wait(0.2)
	Kit.appear(dock, 0, 30)
	local stopBob = Kit.bob(play.root, 4, 3)

	-- PLAY
	local go = false
	play.onClick = function() go = true end
	local keyConn = UserInputService.InputBegan:Connect(function(io, processed)
		if processed then return end
		if io.KeyCode == Enum.KeyCode.Return or io.KeyCode == Enum.KeyCode.Space or io.KeyCode == Enum.KeyCode.ButtonA then go = true end
	end)
	while not go do task.wait() end
	keyConn:Disconnect()
	stopBob()
	Sound.play("land", { volume = 0.5, pitch = 1.2 })

	-- a dip to black, the set comes down, and you're in the lobby
	TweenService:Create(cover, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 0 }):Play()
	task.wait(0.4)
	conn:Disconnect()
	for _, b in ipairs(barrel) do b.part.CFrame = b.rest end
	world:destroy()
	blast:destroy()
	folder:Destroy()
	golden(false, lightSaved)
	if dn then dn:setActive(true) end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		cam.CFrame = CFrame.lookAt(root.Position - root.CFrame.LookVector * 16 + Vector3.new(0, 7, 0), root.Position + Vector3.new(0, 2, 0))
	end
	cam.FieldOfView = 70
	cam.CameraType = Enum.CameraType.Custom
	if hum then cam.CameraSubject = hum end
	playerGui:SetAttribute("IntroPlaying", false)
	logo.Visible = false
	tag.Visible = false
	dock.Visible = false
	local fadeIn = TweenService:Create(cover, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	fadeIn:Play()
	fadeIn.Completed:Wait()
	ui:Destroy()
end

return Title
