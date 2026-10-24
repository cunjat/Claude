--!strict
-- TYRE CANNON :: LoadScene (the loading screen's scene; title idea B, 2026-10-15)
-- What you watch while the game loads: a tyre in slow motion over the Backroad, the camera chasing
-- it low from behind (swaying between the rear quarters), the run's own wind (WindFX) streaming past
-- and the zone's own light
-- (WorldView's ZoneLook). It's the real road, built in the world the way a run builds it, far out
-- along the road from the lobby. Every ten seconds or so (a little random) the tyre dissolves into
-- another tyre from the game, mid-flight, and its name and rarity fade across in the corner.
-- The loading bar and the logo stay on top (TyreLoading draws them). When loading is done the
-- tyre takes off down the road and is gone, and TyreLoading takes the camera home to the yard.
--   LoadScene.new(playerGui, startX?) -> scene ; scene:start() ; scene:prepare(cap) (blocks until it's all in)
--   (startX: somewhere else along the road, in studs: the zone pictures are shot from it, Studio only)
--   scene:intro() ; scene:exit() (blocks ~1.8 s) ; scene:destroy()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)
local TrackGen = require(Modules.TrackGen)
local Game = require(Modules.Game)
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local TyreLook = require(script.Parent.TyreLook)
local WorldView = require(script.Parent.WorldView)
local WindFX = require(script.Parent.WindFX)
local DayNight = require(script.Parent.DayNight)
local C = Kit.C

local LoadScene = {}
LoadScene.__index = LoadScene

local R = Config.Physics.TyreRadius
local D = R * 2
local START = 620                 -- where along the Backroad it starts
local SLOW = 26                   -- (the old slow-motion drift; unused)
local ALT = 17                    -- (the old glide height; unused)
-- (2026-10-22, the owner: the tyre "travelling through the air is also janky ... either come up with a
-- better idea or fix this one"; the fading "terrible and janky"; the wind trail "much tighter")
-- The slow-motion glide is gone: the floating tyre, the slow drift under a fast wind and a lazy spin
-- never agreed on a speed. Now it's a run: the tyre rolls down the real road at a run's pace, spinning
-- with the road, hopping now and then off a rise, the wind tight round it at the same speed, the camera
-- on a spring behind it (so the road's small bumps never shake the shot). A new tyre takes over in a
-- pit-stop pop (no see-through dissolve), and the exit carries the tyre's own speed up the kicker.
local RUN = 118                   -- studs a second down the road
local MAX_SPIN = 17               -- the drawn spin is capped (past it the spokes strobe backwards)
local INTRO = 1.5                 -- the entrance, rocketing in to slow motion
local WIND = 760                  -- the speed the wind is drawn at: two of its layers, scrolling briskly
local SWAP_MIN, SWAP_MAX = 8.5, 12.5
local DISSOLVE = 1.4
local FOV = 52
local EXIT = 2.6                  -- (2026-10-16) the exit: down to the road, up a kicker, launched
local HOUR = 13.5                 -- it's always early afternoon in the loading scene
-- (2026-10-16) the land a run builds only reaches a few chunks ahead and a little to the sides; from
-- the scene's low camera its edge showed as a flat cut with sky under it. A ground skirt in the
-- land's own colour runs out to the horizon under it, and a thicker haze swallows the join.
local SKIRT = 12000
local HAZE = { Density = 0.42, Offset = 0.18, Haze = 2.4, Glare = 0.2 }

local function smooth(k: number): number
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

-- the tyres worth showing off: everything but the Secrets, the rarer ones more often
local function pickTyre(last: string?): string
	local pool, total = {}, 0
	for _, t in ipairs(Game.Tyres) do
		if t.zone ~= "retired" and t.rarity ~= "Secret" and t.id ~= last and TyreLook.has(t.id) then
			local r = Game.RaritiesById[t.rarity]
			local w = 1 + ((r and (r :: any).order) or 1) * 0.6
			total += w
			table.insert(pool, { id = t.id, w = w })
		end
	end
	local x = math.random() * total
	for _, e in ipairs(pool) do
		x -= e.w
		if x <= 0 then return e.id end
	end
	return pool[1] and pool[1].id or Game.StarterTyre
end

-- every part of a model to a transparency (k: 0 shown, 1 gone), keeping each part's own
local function fadeModel(m: Model, k: number)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local base = d:GetAttribute("BaseT")
			if base == nil then
				base = d.Transparency
				d:SetAttribute("BaseT", base)
			end
			d.Transparency = (base :: number) + (1 - (base :: number)) * k
		elseif d:IsA("Decal") or d:IsA("Texture") then
			local base = d:GetAttribute("BaseT")
			if base == nil then
				base = d.Transparency
				d:SetAttribute("BaseT", base)
			end
			d.Transparency = (base :: number) + (1 - (base :: number)) * k
		end
	end
end

function LoadScene.new(playerGui: PlayerGui, startX: number?)
	local self = setmetatable({}, LoadScene)
	self.start0 = startX or START
	self.t = 0
	self.pathT = 0
	self.exitK = 0
	-- the yard's day and night steps aside: the scene is lit for early afternoon (before the road's
	-- own light, so that settles over it and is what it puts back)
	self:holdDay()
	self.track = TrackGen.get("road")
	self.track:setRun(self.track.cfg.seed or 1, 0, 0)
	-- (the rollers laid almost flat: seen slowly from low down, a run's hills read as blocks with
	-- cliffs for sides; the road just undulates here)
	self.track.hillScale = 0.02
	-- the road, as a run builds it (its land, props, light and haze), around where the tyre flies
	-- (the backdrop: the land, horizon and light, but no keys, pads or gates on the road)
	self.world = WorldView.new("road", nil, { backdrop = true })
	self.world:ensure(self.start0)
	local folder = Instance.new("Folder")
	folder.Name = "TyreCannonLoadScene"
	folder.Parent = workspace
	self.folder = folder
	self.wind = WindFX.new(folder, { tight = true })
	self.models = {}
	-- the tyre's name and rarity, bottom left (above the loading screen's own layers)
	local gui = UI.mk("ScreenGui", { Name = "LoadSceneTag", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6001, Parent = playerGui })
	self.gui = gui
	local tagOuter = UI.mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 28, 1, -22), Size = UDim2.fromOffset(320, 54), BackgroundTransparency = 1, Parent = gui })
	UI.autoScale(tagOuter, 1280, 760)
	local tagName = Kit.text("", 24, C.white, 2.5)
	tagName.TextXAlignment = Enum.TextXAlignment.Left
	tagName.Size = UDim2.new(1, 0, 0, 28)
	tagName.TextTransparency = 1
	tagName.Parent = tagOuter
	local tagRar = Kit.text("", 14, C.white, 1.5, Kit.Body)
	tagRar.TextXAlignment = Enum.TextXAlignment.Left
	tagRar.Position = UDim2.fromOffset(2, 30)
	tagRar.Size = UDim2.new(1, 0, 0, 18)
	tagRar.TextTransparency = 1
	tagRar.Parent = tagOuter
	self.tagName, self.tagRar = tagName, tagRar
	self:showTyre(pickTyre(nil), true)
	-- (the tag waits for the scene: the plate covers it until intro)
	self:tagAlpha(1, 0)
	return self
end

function LoadScene:holdDay()
	local dn = (DayNight :: any).current
	if dn then
		dn.active = false
		dn:apply(HOUR)
	end
end

function LoadScene:tagAlpha(a: number, time: number)
	for _, l in ipairs({ self.tagName, self.tagRar }) do
		TweenService:Create(l, TweenInfo.new(time), { TextTransparency = a }):Play()
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then TweenService:Create(st, TweenInfo.new(time), { Transparency = a }):Play() end
	end
end

function LoadScene:setTag(tyreId: string)
	local t = Game.TyresById[tyreId]
	local r = t and Game.RaritiesById[t.rarity]
	self.tagName.Text = string.upper(t and t.name or tyreId)
	self.tagRar.Text = string.upper(t and t.rarity or "")
	self.tagRar.TextColor3 = r and r.color or C.white
end

-- the next tyre takes the same place in the air, turning the same way; the one before dissolves
-- into it
function LoadScene:showTyre(tyreId: string, instant: boolean?)
	self.tyreId = tyreId
	self.nextSwap = self.t + SWAP_MIN + math.random() * (SWAP_MAX - SWAP_MIN)
	local m = TyreLook.model(tyreId, D, "LoadSceneTyre")
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = true
		end
	end
	local scale0 = m:GetScale()
	m.Parent = self.folder
	local old = self.models[#self.models]
	local entry = { model = m, scale0 = scale0, s = if instant then 1 else 0.05 }
	if not instant then m:ScaleTo(scale0 * 0.05) end
	table.insert(self.models, entry)
	if instant then
		self:setTag(tyreId)
		return
	end
	-- the pop (a pit stop): the old one shrinks away in a blink, a flash and a ring of sparks, and the
	-- new one punches in a touch too big and settles. Solid the whole way: nothing see-through
	local t0 = os.clock()
	local OUT, IN = 0.14, 0.34
	self:flash()
	task.spawn(function()
		while m.Parent do
			local k = os.clock() - t0
			if old and old.model.Parent then
				local q = math.clamp(k / OUT, 0, 1)
				old.s = math.max(0.02, 1 - q * q)
				pcall(function() old.model:ScaleTo(old.scale0 * old.s) end)
				if q >= 1 then old.model:Destroy() end
			end
			local u = math.clamp((k - OUT * 0.6) / IN, 0, 1)
			-- (back-out: past full size, then home)
			local c1, c3 = 1.9, 2.9
			entry.s = math.max(0.05, 1 + c3 * (u - 1) ^ 3 + c1 * (u - 1) ^ 2)
			pcall(function() m:ScaleTo(scale0 * entry.s) end)
			if u >= 1 then break end
			RunService.RenderStepped:Wait()
		end
		entry.s = 1
		pcall(function() m:ScaleTo(scale0) end)
		for i = #self.models, 1, -1 do
			if not self.models[i].model.Parent then table.remove(self.models, i) end
		end
	end)
	self:tagAlpha(1, 0.12)
	task.delay(0.22, function()
		if self.leaving then return end
		self:setTag(tyreId)
		self:tagAlpha(0, 0.3)
	end)
end

-- the swap's flash: a hot white burst at the tyre and a ring of sparks, gone in a quarter second
function LoadScene:flash()
	local at = self.lastPos or self:tyrePos()
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 236, 190)
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Size = Vector3.one * D * 0.6
	p.CFrame = CFrame.new(at)
	p.Parent = self.folder
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 210, 120))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, D * 0.12), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.25, 0.45)
	sparks.Speed = NumberRange.new(D * 6, D * 10)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 4
	sparks.Rate = 0
	sparks.Parent = p
	sparks:Emit(28)
	TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * D * 2.4, Transparency = 1 }):Play()
	task.delay(0.6, function() p:Destroy() end)
end

-- where the tyre is: drifting down the road in slow motion, a slow rise and settle
-- where the tyre is: drifting down the road in slow motion, a slow rise and settle. Its height
-- follows the ground smoothed out, so it glides over the hills instead of tracing them
function LoadScene:tyrePos(): Vector3
	local x = self.start0 + self.pathT * RUN
	return Vector3.new(x, (self.roadY or self.track:heightAt(x)) + R + (self.hopY or 0), 0)
end

-- the road actually built under x (the world's road keeps its hills; the scene's own copy of the
-- track is flattened), found by a ray, eased a touch so a seam between chunks never jolts it
function LoadScene:feelRoad(x: number, dt: number)
	self.rayParams = self.rayParams or RaycastParams.new()
	local rp = self.rayParams :: RaycastParams
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { self.folder }
	local guess = self.roadY or self.track:heightAt(x)
	local hit = workspace:Raycast(Vector3.new(x, guess + 120, 0), Vector3.new(0, -400, 0), rp)
	local y = if hit then hit.Position.Y else self.track:heightAt(x)
	self.roadY = if self.roadY then self.roadY + (y - self.roadY) * (1 - math.exp(-dt * 25)) else y
end

-- the camera: a chase shot from behind and a little to one side, low, so the tyre reads as rolling
-- away down the road (never side-on: from the side it looked like it hung across the road). It
-- sways slowly between the two rear quarters; the road runs ahead into the haze and the land's
-- edges stay out of the shot.
function LoadScene:chaseCF(base: Vector3, t: number): CFrame
	local yaw = 0.42 * math.sin(t * 0.13 + 0.6) + 0.12
	local dist = D * 4.6 + math.sin(t * 0.21) * D * 0.3
	local eye = base + Vector3.new(-math.cos(yaw) * dist, D * 0.35 + math.sin(t * 0.17) * D * 0.15, math.sin(yaw) * dist)
	return CFrame.lookAt(eye, base + Vector3.new(D * 3, D * 0.45, 0))
end

function LoadScene:frame(dt: number)
	self.t += dt
	-- (anything that turns the yard's clock back on while the scene's up is turned off again)
	local dn = (DayNight :: any).current
	if dn and dn.active then self:holdDay() end
	-- the lobby's desert backdrop is built round the plaza, miles off; from out here its sand skirt
	-- hangs in the sky like a ceiling, so it steps aside while the scene's up (it's built while the
	-- scene plays, so this checks every frame)
	local vista = workspace:FindFirstChild("LobbyVista")
	if vista then
		vista.Parent = nil
		self.vista = vista
	end
	if not self.leaving then self.pathT += dt end
	local t = self.t
	if not self.leaving and t >= self.nextSwap then self:showTyre(pickTyre(self.tyreId)) end
	-- a hop now and then, off a rise in the road (a quick arc and a little squash on landing)
	self.nextHop = self.nextHop or (t + 3 + math.random() * 3)
	if not self.leaving and t >= self.nextHop and not self.hopT0 then self.hopT0 = t end
	if self.hopT0 then
		local u = (t - self.hopT0) / 0.62
		if u >= 1 then
			self.hopT0, self.hopY = nil, 0
			self.nextHop = t + 3.5 + math.random() * 4
		else
			self.hopY = D * 1.1 * 4 * u * (1 - u)
		end
	end
	if not self.leaving then self:feelRoad(self.start0 + self.pathT * RUN, dt) end
	local base = self:tyrePos()
	local pos = base
	-- the intro: the tyre comes rocketing in over the camera's shoulder and settles into the chase
	-- as it reaches its place (the logo lands as it arrives)
	local introK = 1
	if self.introT0 then
		introK = math.clamp((t - self.introT0) / INTRO, 0, 1)
		local e = 1 - (1 - introK) ^ 3
		pos = base + Vector3.new(-160, 22, -10) * (1 - e)
	end
	-- the camera on a spring: it follows where the chase shot wants to be, never snapping to it
	local want = self:chaseCF(Vector3.new(base.X, (self.roadY or self.track:heightAt(base.X)) + R, 0), t)
	local kf = 1 - math.exp(-dt * 7)
	self.camEye = if self.camEye then self.camEye:Lerp(want.Position, kf) + Vector3.new(RUN * dt, 0, 0) * (1 - kf) else want.Position
	-- (the spring lags the climbs: never let the eye sink into the road under it)
	local eyeNow = self.camEye :: Vector3
	local floor = self.track:heightAt(eyeNow.X) + D * 0.8
	self.rayParams = self.rayParams or RaycastParams.new()
	local rp = self.rayParams :: RaycastParams
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { self.folder }
	local hit = workspace:Raycast(eyeNow + Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), rp)
	if hit then floor = math.max(floor, hit.Position.Y + D * 0.8) end
	if eyeNow.Y < floor then self.camEye = Vector3.new(eyeNow.X, floor, eyeNow.Z) end
	local wantLook = want.Position + want.LookVector * 60
	self.camLook = if self.camLook then self.camLook:Lerp(wantLook, kf) + Vector3.new(RUN * dt, 0, 0) * (1 - kf) else wantLook
	local cf = CFrame.lookAt(self.camEye :: Vector3, self.camLook :: Vector3)
	local spinRate = math.min(MAX_SPIN, RUN / R) + (1 - introK) ^ 2 * 20
	local fov = FOV
	if self.leaving and self.exitPath then
		-- (2026-10-16) the exit: the tyre comes down out of its glide onto the road, speeds up, runs
		-- up the kicker that's risen ahead of it and launches into a high arc; the camera follows it
		-- up. One smooth path: accelerating along the ground, the ramp's straight slope, then a
		-- ballistic arc leaving the lip at the speed it had
		local e = self.exitPath
		local k = self.exitK
		-- (2026-10-22) it keeps the speed it had and speeds up: along the road, up the kicker's
		-- straight slope, then a ballistic arc off the lip at the speed it got there
		local tau = k * EXIT
		local A = 70
		local lipT = (-RUN + math.sqrt(RUN * RUN + 2 * A * (e.r0 + e.L - e.x0))) / A
		local x, y
		if tau <= lipT then
			x = e.x0 + RUN * tau + 0.5 * A * tau * tau
			if x < e.r0 then
				y = self.track:heightAt(x) + R
			else
				y = e.g + R + e.H * (x - e.r0) / e.L
			end
		else
			local u = tau - lipT
			local vx = RUN + A * lipT
			local vy = vx * e.H / e.L * 0.55 + 10
			x = e.r0 + e.L + vx * u
			y = e.g + R + e.H + vy * u - 0.5 * 46 * u * u
		end
		pos = Vector3.new(x, y, 0)
		local held = self.exitCF :: CFrame
		-- (the camera hangs back and tilts up to follow the arc: the tyre stays in the shot)
		local eye = held.Position + Vector3.new((x - e.x0) * 0.5, math.max(0, y - e.y0) * 0.5, 0)
		local look = (held.Position + held.LookVector * 100):Lerp(pos + Vector3.new(0, 2, 0), smooth(k / 0.3))
		cf = CFrame.lookAt(eye, look)
		spinRate = 1.5 + smooth(k) * 30
		fov = FOV + smooth(k) * 10
	end
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = cf
	cam.FieldOfView = fov
	self.spin = (self.spin or 0) + dt * spinRate
	self.lastPos = pos
	for _, e in ipairs(self.models) do
		if e.model.Parent then
			-- rolling forward down the road (+X) with its axle across it (Z), the way a run's tyre
			-- does, with only the faintest wobble
			e.model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.sin(t * 0.37) * 0.035, 0)
				* CFrame.Angles(math.sin(t * 0.8) * 0.03, 0, 0) * CFrame.Angles(0, 0, -self.spin))
		end
	end
	-- the run's own wind round the tyre, a little brisker on the way out
	self.wind:update(pos, 0, WIND + self.exitK * 600 + (1 - introK) * 900)
	-- (the land is kept built round the tyre itself: on the exit it's far down the road)
	self.world:ensure(pos.X, 1)
	pcall(function() self.world:update(dt, pos.X) end)
	self:horizon(base)
end

-- the ground skirt under the land and the haze over the join (see SKIRT)
function LoadScene:horizon(base: Vector3)
	if not self.skirt then
		-- the land's own colour, from the ground off the side of the road
		local color = Color3.fromRGB(122, 112, 62)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { self.folder }
		local hit = workspace:Raycast(Vector3.new(base.X + 60, base.Y + 400, 140), Vector3.new(0, -900, 0), params)
		if hit and hit.Instance:IsA("BasePart") and hit.Instance.Name ~= "Terrain" then color = (hit.Instance :: BasePart).Color end
		local p = Instance.new("Part")
		p.Name = "HorizonSkirt"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Grass
		p.Color = color
		p.Size = Vector3.new(SKIRT, 1, SKIRT)
		p.Parent = self.folder
		self.skirt = p
	end
	-- it follows along the road, a little under the land so it never shows through it
	local g = self.groundY or self.track:heightAt(base.X)
	self.skirt.CFrame = CFrame.new(base.X + SKIRT * 0.3, g - 6, 0)
	local atm = game:GetService("Lighting"):FindFirstChildOfClass("Atmosphere")
	if atm then
		if not self.atmWas then
			self.atmWas = { Density = atm.Density, Offset = atm.Offset, Haze = atm.Haze, Glare = atm.Glare }
		end
		for k, v in pairs(HAZE) do (atm :: any)[k] = v end
	end
end

-- the tyre's entrance (the loading screen calls it as the scene comes up)
function LoadScene:intro()
	self.introT0 = self.t
	self:tagAlpha(0, 0.8)
end

function LoadScene:start()
	if self.conn then return end
	self.conn = RunService.RenderStepped:Connect(function(dt) self:frame(math.min(dt, 0.1)) end)
end

-- everything the scene shows has arrived and been drawn once (the plate stays over it until then,
-- so nothing pops in: the land, the props, the tyre, the wind). Blocks, up to `cap` seconds.
function LoadScene:prepare(cap: number?)
	local t0 = os.clock()
	local list = {}
	for _, root in ipairs({ self.world and self.world.root, self.folder } :: { Instance? }) do
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("MeshPart") or d:IsA("SpecialMesh") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance")
					or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
					table.insert(list, d)
				end
			end
		end
	end
	for i = 1, #list, 24 do
		pcall(function() ContentProvider:PreloadAsync(table.move(list, i, math.min(i + 23, #list), 1, {})) end)
		if os.clock() - t0 > (cap or 8) then break end
	end
	-- a few frames drawn behind the plate, so the first one seen isn't the first one made
	for _ = 1, 8 do RunService.RenderStepped:Wait() end
end

-- the tyre's away down the road (blocks while it goes)
function LoadScene:exit()
	if self.leaving then return end
	self.leaving = true
	self.exitCF = workspace.CurrentCamera.CFrame
	self:tagAlpha(1, 0.3)
	-- the kicker: up out of the road ahead of the tyre
	local tp = self:tyrePos()
	-- (far enough ahead that it rises out of the road before the tyre gets there, at the run's pace)
	local e = { x0 = tp.X, y0 = tp.Y, r0 = tp.X + RUN * 0.75 + 30, L = 64, H = 18 }
	e.g = self.track:heightAt(e.r0)
	self.exitPath = e
	self:buildRamp(e)
	local t0 = os.clock()
	while os.clock() - t0 < EXIT do
		self.exitK = (os.clock() - t0) / EXIT
		RunService.RenderStepped:Wait()
	end
	self.exitK = 1
end

-- a wooden kicker on the road: a sloped plank deck on posts, side boards, a hazard-striped lip; it
-- rises out of the ground (so it can't have been seen sliding along)
function LoadScene:buildRamp(e)
	local m = Instance.new("Model")
	m.Name = "ExitRamp"
	local slope = math.atan(e.H / e.L)
	local deckLen = math.sqrt(e.L * e.L + e.H * e.H)
	local wood = Color3.fromRGB(150, 104, 62)
	local function piece(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = size
		p.Color = color
		p.Material = mat
		p.CFrame = cf
		p.Parent = m
		return p
	end
	local deckCF = CFrame.new(e.r0 + e.L / 2, e.g + e.H / 2, 0) * CFrame.Angles(0, 0, slope)
	piece(Vector3.new(deckLen, 1.2, 22), deckCF, wood, Enum.Material.WoodPlanks)
	for _, z in ipairs({ -11.4, 11.4 }) do
		piece(Vector3.new(deckLen, 2.2, 0.8), deckCF * CFrame.new(0, 0.9, z), wood:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Wood)
	end
	-- the lip: yellow and black
	for i = 0, 5 do
		piece(Vector3.new(1.2, 1.3, 22 / 6), CFrame.new(e.r0 + e.L - 0.4, e.g + e.H + 0.1, -11 + 22 / 12 + i * 22 / 6) * CFrame.Angles(0, 0, slope),
			if i % 2 == 0 then Color3.fromRGB(250, 196, 40) else Color3.fromRGB(24, 24, 28), Enum.Material.SmoothPlastic)
	end
	-- the posts under it
	for k = 1, 4 do
		local x = e.r0 + e.L * k / 4.4
		local h = e.H * (x - e.r0) / e.L
		for _, z in ipairs({ -9, 9 }) do
			piece(Vector3.new(1.2, h, 1.2), CFrame.new(x, e.g + h / 2, z), wood:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Wood)
		end
	end
	m.Parent = self.folder
	-- up out of the ground
	local final = m:GetPivot()
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < 0.45 and m.Parent do
			local k = math.clamp((os.clock() - t0) / 0.45, 0, 1)
			local back = 1 + 2.2 * (k - 1) ^ 3 + 1.2 * (k - 1) ^ 2
			m:PivotTo(final * CFrame.new(0, -(e.H + 3) * (1 - back), 0))
			RunService.RenderStepped:Wait()
		end
		if m.Parent then m:PivotTo(final) end
	end)
	m:PivotTo(final * CFrame.new(0, -(e.H + 3), 0))
end

function LoadScene:destroy()
	if self.conn then self.conn:Disconnect() end
	self.conn = nil
	if self.wind then self.wind:destroy() end
	if self.world then pcall(function() self.world:destroy() end) end
	self.world = nil
	if self.folder then self.folder:Destroy() end
	if self.gui then self.gui:Destroy() end
	-- the lobby's backdrop and haze come back
	if self.vista and self.vista.Parent == nil then self.vista.Parent = workspace end
	local atm = game:GetService("Lighting"):FindFirstChildOfClass("Atmosphere")
	if atm and self.atmWas then
		for k, v in pairs(self.atmWas) do (atm :: any)[k] = v end
	end
	-- the yard's day and night carries on
	local dn = (DayNight :: any).current
	if dn then dn:setActive(true) end
end

return LoadScene
