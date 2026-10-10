--!strict
-- TYRE CANNON :: TyreSkills
-- What the launch tyre brings to a run beyond its stats (Game.Tyres): its special (Epic and up),
-- built into how the run plays and shown with its own effects, and its skill (Legendary and up) on
-- one key (E, gamepad Y, the SKILL pad on a phone).
--   Ground Pound  slam from the air; the landing flattens what's near and throws you high
--   Spin Dash     hold to rev into a spin-ball, let go to blast forward through anything
--   Rebirth       once a run, rise from a blowout or a stop in a golden flash
--   Sandevistan   bullet time: everything slows, you steer like it hasn't, afterimages; no heat
--   Zero-G        three seconds of low gravity in a ring of stardust
--   Mini-Turbo    hold a turn on the ground to charge sparks blue, orange, purple; let go to shoot off
--   Mine          the next few things you hit break into blocks and drop coins
--   Inhale        swallow everything ahead, then float puffed up
-- RunSim reads the multipliers (gravity, drag, control, heat, timeScale, smashAll) and calls the hooks.
--   TyreSkills.new(sim, stats, gui) ; :input(on) ; :step(dt) ; :frame(dt) ; :landed(impact) -> vy?
--   :smashOverride(o) -> bool ; :smashed(o, pos) ; :rebirth(reason) -> bool ; :destroy()

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local VFX = require(script.Parent.VFX)
local PackFX = require(script.Parent.PackFX)
local Sound = require(script.Parent.Sound)
local Models = require(script.Parent.Models)

local TyreSkills = {}
TyreSkills.__index = TyreSkills

local GOLD = Color3.fromRGB(255, 196, 64)
local SPIN_BLUE = Color3.fromRGB(36, 92, 220)
local TURBO = { Color3.fromRGB(70, 150, 255), Color3.fromRGB(255, 150, 40), Color3.fromRGB(190, 90, 255) }
-- Sandevistan: how long it runs, how slow the world goes, and its afterimages
local SANDY_TIME = 3.2
local SANDY_WORLD = 0.18		-- the world's particle clock while it runs
local SANDY_GAP = 5.5			-- studs between afterimages
local SANDY_LIFE = 0.55
local SANDY_POOL = 18
local GLITCH = { Color3.fromRGB(0, 255, 196), Color3.fromRGB(255, 48, 196), Color3.fromRGB(240, 255, 250) }

local function part(parent: Instance, size: Vector3, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = mat
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

-- a plain emitter on an attachment, for the specials' trails
local function emitter(att: Attachment, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightEmission = 0
	e.LightInfluence = 1
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = att
	return e
end

local function seq(a: number, b: number): NumberSequence
	return NumberSequence.new(a, b)
end

function TyreSkills.new(sim, stats, gui: Instance?)
	local self = setmetatable({}, TyreSkills)
	self.sim = sim
	self.special = stats.special
	self.skillId = stats.skill
	self.skill = stats.skill and Game.Skills[stats.skill] or nil
	self.gravity, self.drag, self.control, self.heat, self.timeScale = 1, 1, 1, 1, 1
	self.smashAll = false
	self.cooldown = 0
	self.held = false
	self.charges = self.skill and self.skill.charges or nil
	self.fx = {}
	self.ghosts = {}
	self.ghostT = 0
	self.gui = gui
	self.fovAdd = 0

	-- an anchor under the hub for ground effects, one at the hub for air effects
	local folder = sim.folder
	local anchor = part(folder, Vector3.one, Color3.new(), Enum.Material.SmoothPlastic)
	anchor.Name = "SkillAnchor"
	anchor.Transparency = 1
	self.anchor = anchor
	local low = Instance.new("Attachment")
	low.Position = Vector3.new(0, -Game.TyreRadius * 0.9, 0)
	low.Parent = anchor
	local mid = Instance.new("Attachment")
	mid.Parent = anchor
	self.low, self.mid = low, mid

	local sp = self.special
	if sp == "chrome" or sp == "kart" then
		self.fx.sparks = emitter(low, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(255, 236, 190), Color3.fromRGB(255, 160, 60)),
			Size = seq(0.6, 0), Lifetime = NumberRange.new(0.15, 0.35), Speed = NumberRange.new(30, 60), SpreadAngle = Vector2.new(35, 35),
			Acceleration = Vector3.new(0, -60, 0), Rate = 90, EmissionDirection = Enum.NormalId.Back, Drag = 2,
		})
	elseif sp == "sandtrail" then
		self.fx.sand = emitter(low, {
			Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(GOLD, Color3.fromRGB(230, 170, 70)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) }),
			Transparency = seq(0.25, 1), Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(40, 40),
			Acceleration = Vector3.new(0, 3, 0), Rate = 40, EmissionDirection = Enum.NormalId.Back,
		})
	elseif sp == "floaty" then
		self.fx.stars = emitter(mid, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(230, 230, 255)),
			Size = seq(0.8, 0), Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180),
			Rate = 30,
		})
	elseif sp == "glazed" then
		self.fx.glaze = emitter(low, {
			Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(255, 130, 190)),
			Size = seq(0.9, 0.4), Transparency = seq(0.1, 0.7), Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(2, 6),
			Acceleration = Vector3.new(0, -50, 0), Rate = 24, SpreadAngle = Vector2.new(20, 20),
		})
	elseif sp == "jet" then
		self.fx.jet = PackFX.emitter("boost", mid)
	end
	if self.skillId == "miniturbo" then
		self.fx.turbo = emitter(low, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(TURBO[1]),
			Size = seq(1.1, 0), Lifetime = NumberRange.new(0.12, 0.3), Speed = NumberRange.new(20, 46), SpreadAngle = Vector2.new(50, 50),
			Acceleration = Vector3.new(0, -40, 0), Rate = 140, EmissionDirection = Enum.NormalId.Back,
		})
		self.turbo = 0
	end
	if gui and self.skill then self:buildCard(gui) end
	return self
end

--==============================================================
-- the skill card on the HUD: name, key, cooldown
--==============================================================
function TyreSkills:buildCard(gui: Instance)
	local card = UI.mk("Frame", {
		Name = "SkillCard", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -118), Size = UDim2.fromOffset(230, 46),
		BackgroundColor3 = Color3.fromRGB(18, 18, 22), BackgroundTransparency = 0.25, ZIndex = 25, Parent = gui,
	}, { UI.corner(12) })
	UI.autoScale(card, 1280, 760)
	UI.stroke(Color3.fromRGB(255, 196, 64), 2, 0.2).Parent = card
	local key = UI.mk("TextLabel", {
		Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromRGB(255, 196, 64),
		Text = self.skill.key, TextColor3 = Color3.fromRGB(20, 18, 16), TextSize = 22, FontFace = UI.Fonts.display, ZIndex = 27, Parent = card,
	}, { UI.corner(8) })
	local name = UI.mk("TextLabel", {
		Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -56, 1, 0), BackgroundTransparency = 1,
		Text = string.upper(self.skill.name), TextColor3 = Color3.fromRGB(246, 242, 232), TextSize = 20, FontFace = UI.Fonts.display,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 27, Parent = card,
	})
	local fill = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 26, Parent = card,
	}, { UI.corner(12) })
	self.card, self.cardKey, self.cardName, self.cardFill = card, key, name, fill
end

function TyreSkills:updateCard()
	if not self.card then return end
	local cd = self.skill.cooldown or 0
	local frac = (cd > 0) and math.clamp(self.cooldown / cd, 0, 1) or 0
	if self.charges ~= nil then
		frac = self.charges > 0 and 0 or 1
		self.cardName.Text = string.upper(self.skill.name) .. (self.charges > 0 and "  READY" or "  USED")
	elseif self.skillId == "miniturbo" then
		local tier = self.turboTier or 0
		self.cardName.TextColor3 = tier > 0 and TURBO[tier] or Color3.fromRGB(246, 242, 232)
	end
	self.cardFill.Size = UDim2.fromScale(1, frac)
	self.cardKey.BackgroundColor3 = frac > 0 and Color3.fromRGB(90, 86, 80) or Color3.fromRGB(255, 196, 64)
end

local function flash(card: Frame?)
	if not card then return end
	local s = card:FindFirstChildOfClass("UIScale")
	if s then
		local base = s.Scale
		s.Scale = base * 1.12
		TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = base }):Play()
	end
end

--==============================================================
-- input
--==============================================================
function TyreSkills:ready(): boolean
	return self.skill ~= nil and self.cooldown <= 0 and not self.sim.blown and not self.sim.finished
end

function TyreSkills:input(on: boolean)
	if not self.skill then return end
	local was = self.held
	self.held = on
	local sim = self.sim
	local id = self.skillId
	if on and not was then
		if id == "groundpound" then
			local alt = sim.y - sim.track:heightAt(sim.x) - Game.TyreRadius
			if self:ready() and not sim.grounded and alt > 10 then
				self.pounding = true
				sim.vy = -420
				sim.vz *= 0.4
				Sound.play("gateWhoosh", { volume = 0.6, pitch = 0.7 })
				self:used()
			end
		elseif id == "spindash" then
			-- Drill Dash: a burst of speed through anything in the way
			if self:ready() then
				sim.vx += 150
				self.dashT = 1.1
				self.smashAll = true
				self:showBall(true)
				sim.shake = math.min(3, sim.shake + 1.2)
				Sound.play("gateWhoosh", { volume = 0.9, pitch = 1.4 })
				self:used()
			end
		elseif id == "wings" then
			-- the Scarab's wings: a few seconds of true glide, no sink, no stall
			if self:ready() then
				self.wingsT = 4.0
				self:wings()
				Sound.play("gateWhoosh", { volume = 0.8, pitch = 1.1 })
				self:used()
			end
		elseif id == "sandevistan" then
			if self:ready() then
				self:used()
				self:sandevistan(true)
			end
		elseif id == "zerog" then
			if self:ready() then
				self.zeroT = 3.0
				self:used()
				self:ring(true)
			end
		elseif id == "mine" then
			if self:ready() then
				self.mineHits = 3
				self.mineT = 8
				self:used()
				self:blocky(true)
			end
		elseif id == "inhale" then
			if self:ready() then
				self.inhaleT = 1.4
				self:used()
				Sound.play("gateWhoosh", { volume = 0.8, pitch = 1.3 })
			end
		end
	end
	self:updateCard()
end

function TyreSkills:used()
	self.cooldown = self.skill and self.skill.cooldown or 0
	flash(self.card)
	self.sim.onEvent({ kind = "skill", name = self.skill and self.skill.name or "" })
end

--==============================================================
-- physics, every sim step
--==============================================================
function TyreSkills:step(dt: number)
	local sim = self.sim
	self.cooldown = math.max(0, self.cooldown - dt)
	self.gravity, self.drag, self.control, self.heat = 1, 1, 1, 1
	self.noStall = false

	if self.wingsT then
		-- gliding: the sink all but gone, the nose never drops, the tyre turns a little better
		self.wingsT -= dt
		self.gravity = 0.18
		self.drag = 0.7
		self.control = 1.35
		self.noStall = true
		if self.wingsT <= 0 then
			self.wingsT = nil
			if self.wingSet then self.wingSet.t0 = os.clock() - 1.1 end
		end
	end
	if self.dashT then
		self.dashT -= dt
		self.drag = 0.4
		if self.dashT <= 0 then
			self.dashT = nil
			self.smashAll = false
			self:showBall(false)
		end
	end
	if self.sandy then
		-- the world crawls and you don't: you steer as if nothing had slowed
		self.sandy -= dt
		self.control = 2.6
		self.heat = 0
		self.drag = 0.75
		if self.sandy <= 0 then self:sandevistan(false) end
	end
	if self.zeroT then
		self.zeroT -= dt
		self.gravity = 0.3
		self.drag = 0.6
		if self.zeroT <= 0 then
			self.zeroT = nil
			self:ring(false)
		end
	end
	if self.mineT then
		self.mineT -= dt
		if self.mineT <= 0 or (self.mineHits or 0) <= 0 then
			self.mineT = nil
			self.mineHits = 0
			self:blocky(false)
		end
	end
	if self.inhaleT then
		self.inhaleT -= dt
		self:inhaleStep()
		if self.inhaleT <= 0 then
			self.inhaleT = nil
			self.puffT = 1.6
			self:puff(true)
		end
	end
	if self.puffT then
		self.puffT -= dt
		self.gravity = 0.45
		if self.puffT <= 0 then
			self.puffT = nil
			self:puff(false)
		end
	end

	-- Mini-Turbo: hold the skill on the ground to charge, let go to fire
	if self.skillId == "miniturbo" then
		if self.held and sim.vx > 60 and not sim.blown then
			self.turbo += dt
			local tier = self.turbo >= 1.8 and 3 or (self.turbo >= 1.2 and 2 or (self.turbo >= 0.6 and 1 or 0))
			if tier ~= (self.turboTier or 0) then
				self.turboTier = tier
				if tier > 0 then
					self.fx.turbo.Color = ColorSequence.new(TURBO[tier])
					Sound.play("tick", { volume = 0.5, pitch = 0.9 + tier * 0.2 })
				end
				self:updateCard()
			end
		elseif self.turbo > 0 then
			local tier = self.turboTier or 0
			if tier > 0 then
				sim.vx += ({ 70, 130, 200 })[tier]
				sim.shake = math.min(3, sim.shake + 0.4 * tier)
				PackFX.burst("boost", CFrame.new(sim.x - Game.TyreRadius, sim.y, sim.z) * CFrame.Angles(0, 0, math.rad(90)), 10 * tier, TURBO[tier], 1.2)
				Sound.play("gateWhoosh", { volume = 0.5 + 0.15 * tier, pitch = 1.2 })
				sim.onEvent({ kind = "skill", name = ({ "MINI-TURBO", "SUPER TURBO", "ULTRA TURBO" })[tier] })
			end
			self.turbo = 0
			self.turboTier = 0
			self:updateCard()
		end
	end
	if self.cooldown > 0 or self.charges ~= nil then self:updateCard() end
end

-- the landing: Ground Pound's shockwave, the Monster's heavy dust, Sandevistan's clean landing
function TyreSkills:landed(impact: number): number?
	local sim = self.sim
	local pos = Vector3.new(sim.x, sim.track:heightAt(sim.x), sim.z)
	if self.special == "monster" and impact > 120 then
		PackFX.burst("dustRing", CFrame.new(pos), 22, sim.track:cfgAt(sim.x).ground:Lerp(Color3.new(1, 1, 1), 0.3), 2.4)
	end
	if self.pounding then
		self.pounding = false
		local n = 0
		for key, node in pairs(sim.world.obstacleNodes) do
			local o = node.data
			if (Vector3.new(o.x, o.y, o.z) - pos).Magnitude < 55 and not sim.hitObstacles[key] then
				sim.hitObstacles[key] = true
				sim.world:shatter(key, Vector3.new(sim.vx, 60, 0))
				n += 1
			end
		end
		sim.smashes += n
		VFX.emit("CheckpointShock", CFrame.new(pos + Vector3.new(0, 1, 0)), { scale = 2.2 })
		VFX.emit("LandCrack", CFrame.new(pos + Vector3.new(0, 0.3, 0)), { scale = 3 })
		PackFX.burst("dustRing", CFrame.new(pos), 34, sim.track:cfgAt(sim.x).ground:Lerp(Color3.new(1, 1, 1), 0.3), 3.2)
		sim.shake = 3
		sim.vx += 90
		Sound.play("land", { volume = 1, pitch = 0.7 })
		if n > 0 then sim.onEvent({ kind = "smash", total = sim.smashes }) end
		return 52   -- the nose angle it throws you off at, in degrees
	end
	if self.sandy then
		return nil
	end
	return nil
end

-- obstacles: Spin Dash smashes everything; Mine turns the next few into blocks and coins
function TyreSkills:smashOverride(o): boolean
	if self.smashAll then return true end
	if (self.mineHits or 0) > 0 then
		self.mineHits -= 1
		self.mined = o
		return true
	end
	return false
end

function TyreSkills:smashed(o, pos: Vector3)
	local sim = self.sim
	if self.mined == o then
		self.mined = nil
		-- pixel blocks, and coins
		for _ = 1, 9 do
			local s = math.random(10, 26) / 10
			local b = part(sim.world.debris, Vector3.new(s, s, s), o.color:Lerp(Color3.new(0, 0, 0), math.random() * 0.25), Enum.Material.SmoothPlastic)
			b.CFrame = CFrame.new(pos + Vector3.new(math.random(-3, 3), math.random(0, 5), math.random(-3, 3)))
			b.Anchored = false
			b.CanCollide = true
			b.AssemblyLinearVelocity = Vector3.new(sim.vx * 0.5 + math.random(-40, 40), math.random(50, 110), math.random(-50, 50))
			Debris:AddItem(b, 2.2)
		end
		self.mineSwing = os.clock()
		sim.metals.bronze = (sim.metals.bronze or 0) + 3
		sim.onEvent({ kind = "metal", metal = "bronze", amount = 3 })
		Sound.play("tick", { volume = 0.8, pitch = 1.5 })
	end
	if self.special == "timber" then
		PackFX.burst("dustPuff", CFrame.new(pos), 14, Color3.fromRGB(176, 120, 64), 1.6)
	elseif self.special == "bore" or self.smashAll then
		VFX.emit("Sparks", CFrame.new(pos), { scale = 1.4 })
	end
end

-- (the old Rebirth is gone: the Scarab has real wings now. RunSim still asks, and gets no.)
function TyreSkills:rebirth(_reason: string): boolean
	return false
end

-- Inhale: everything in a cone ahead comes in
function TyreSkills:inhaleStep()
	local sim = self.sim
	local function inCone(x: number, y: number, z: number): boolean
		local dx, dy, dz = x - sim.x, y - sim.y, z - sim.z
		return dx > -5 and dx < 110 and math.abs(dz) < 20 + dx * 0.4 and math.abs(dy) < 30 + dx * 0.3
	end
	for key, node in pairs(sim.world.perkNodes) do
		local d = node.data
		if inCone(d.x, node.core.Position.Y, d.z) then
			sim.world:markCollected(key)
			sim:applyPerk(node.perk, "inhale")
		end
	end
	for key, node in pairs(sim.world.metalNodes) do
		local d = node.data
		if inCone(d.x, d.y, d.z) then
			sim.world:markMetalCollected(key)
			sim.metals[d.kind] = (sim.metals[d.kind] or 0) + d.amount
			sim.onEvent({ kind = "metal", metal = d.kind, amount = d.amount })
		end
	end
	for key, node in pairs(sim.world.keyNodes or {}) do
		local d = node.data
		if inCone(d.x, d.y, d.z) then
			sim.world:markKeyCollected(key)
			sim.keysGot += 1
			sim.onEvent({ kind = "key", total = sim.keysGot })
		end
	end
	for key, node in pairs(sim.world.obstacleNodes) do
		local o = node.data
		if not sim.hitObstacles[key] and inCone(o.x, o.y + o.h / 2, o.z) and o.x - sim.x < 70 then
			sim.hitObstacles[key] = true
			sim.world.obstacleNodes[key] = nil
			local m = node.model
			task.spawn(function()
				local t0 = os.clock()
				local scale0 = m:GetScale()
				while os.clock() - t0 < 0.3 and m.Parent do
					local k = (os.clock() - t0) / 0.3
					pcall(function()
						m:ScaleTo(scale0 * math.max(0.05, 1 - k))
						m:PivotTo(m:GetPivot():Lerp(CFrame.new(Vector3.new(sim.x, sim.y, sim.z)), k * 0.5))
					end)
					task.wait()
				end
				m:Destroy()
			end)
		end
	end
end

--==============================================================
-- visuals
--==============================================================
-- the skills' Blender models (art/blender/skills3.py, skills3_more.py) are built in the tyres'
-- wheel frame: 8 studs across, pivot on the ground under the wheel centre. This stands one up at
-- the tyre's size with its pivot moved to the wheel centre, anchored and out of the way of physics.
local BALL_BUILT = 8
function TyreSkills:skillModel(path: string, scale: number?): Model?
	local tpl = Models.get(path)
	if not tpl then return nil end
	local s = (Game.TyreRadius * 2 / BALL_BUILT) * (scale or 1)
	local m = Models.place(tpl, nil :: any, CFrame.new(), s)
	Models.turn(m, CFrame.new(0, BALL_BUILT / 2 * s, 0))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	m.Parent = self.sim.folder
	return m
end

-- the Spin Dash ball: the Blender model once imported, a plain ball until then
function TyreSkills:showBall(on: boolean)
	local sim = self.sim
	if on and not self.ball then
		local r = Game.TyreRadius * 1.05
		local tpl = Models.get("Skills/SpinBall")
		local ball: Model
		local rings = {}
		if tpl then
			local s = r * 2 / BALL_BUILT
			ball = Models.place(tpl, nil :: any, CFrame.new(), s)
			Models.turn(ball, CFrame.new(0, BALL_BUILT / 2 * s, 0))
			for _, d in ipairs(ball:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
		else
			ball = Instance.new("Model")
			local core = part(ball, Vector3.new(r * 2, r * 2, r * 2), SPIN_BLUE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			core.Reflectance = 0.15
			ball.PrimaryPart = core
			for _ = 1, 3 do
				local ring = part(ball, Vector3.new(0.4, r * 2.12, r * 2.12), Color3.fromRGB(236, 244, 255), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
				ring.Transparency = 0.25
				table.insert(rings, ring)
			end
		end
		ball.Name = "SpinBall"
		ball.Parent = sim.folder
		-- revving on the spot throws dust out behind
		if not self.fx.revDust then self.fx.revDust = PackFX.emitter("dustPuff", self.low) end
		self.ball, self.ballRings = ball, rings
		for _, p in ipairs(sim.model:GetDescendants()) do
			if p:IsA("BasePart") then p.LocalTransparencyModifier = 1 end
		end
	elseif not on and self.ball then
		self.ball:Destroy()
		self.ball = nil
		if self.fx.revDust then self.fx.revDust.Enabled = false end
		for _, p in ipairs(sim.model:GetDescendants()) do
			if p:IsA("BasePart") then p.LocalTransparencyModifier = 0 end
		end
	end
end

--==============================================================
-- Sandevistan: the world drops to a crawl around you
--==============================================================
-- a glitch, the green grade, the world's particles and sounds slowed, afterimages from a pool
function TyreSkills:sandevistan(on: boolean)
	local sim = self.sim
	if on then
		if self.sandy then return end
		self.sandy = SANDY_TIME
		self.sandyMoved = 0
		self.sandyHue = 0
		self.fovAdd = -9
		self:glitch(0.32)
		Sound.play("gateWhoosh", { volume = 0.8, pitch = 0.45 })
		Sound.play("land", { volume = 0.5, pitch = 1.6 })
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "Sandevistan"
		cc.Parent = workspace.CurrentCamera
		TweenService:Create(cc, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Saturation = -0.55, Contrast = 0.22, Brightness = 0.02, TintColor = Color3.fromRGB(206, 255, 228),
		}):Play()
		self.sandyFx = cc
		-- every particle in the world runs slow, and anything new that appears does too
		local slowed = {}
		self.sandySlowed = slowed
		local function slow(d: Instance)
			if d:IsA("ParticleEmitter") and not slowed[d] then
				slowed[d] = d.TimeScale
				d.TimeScale = d.TimeScale * SANDY_WORLD
			end
		end
		for _, d in ipairs(workspace:GetDescendants()) do slow(d) end
		self.sandyConn = workspace.DescendantAdded:Connect(slow)
		-- and every sound drops
		local pitched = {}
		for _, g in ipairs(SoundService:GetDescendants()) do
			if g:IsA("SoundGroup") then
				local ps = Instance.new("PitchShiftSoundEffect")
				ps.Name = "Sandevistan"
				ps.Octave = 0.72
				ps.Parent = g
				table.insert(pitched, ps)
			end
		end
		self.sandyPitch = pitched
		-- the afterimage pool: plain see-through copies of the tyre, made once
		if not self.ghostPool then
			local pool = {}
			for i = 1, SANDY_POOL do
				local g = sim.model:Clone()
				g.Name = "Afterimage"
				local parts = {}
				for _, d in ipairs(g:GetDescendants()) do
					if d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("ParticleEmitter")
						or d:IsA("Attachment") or d:IsA("Light") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("BaseScript") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						d.CastShadow = false
						d.Material = Enum.Material.SmoothPlastic
						d.Reflectance = 0
						d.LocalTransparencyModifier = 0
						d.Transparency = 1
						table.insert(parts, d)
					end
				end
				g.Parent = sim.folder
				pool[i] = { model = g, parts = parts, born = -1 }
			end
			self.ghostPool = pool
			self.ghostNext = 1
		end
	else
		if not self.sandy then return end
		self.sandy = nil
		self.fovAdd = 0
		self:glitch(0.18)
		Sound.play("gateWhoosh", { volume = 0.5, pitch = 0.8 })
		if self.sandyConn then self.sandyConn:Disconnect() end
		self.sandyConn = nil
		for e, ts in pairs(self.sandySlowed or {}) do
			if e.Parent then e.TimeScale = ts end
		end
		self.sandySlowed = nil
		for _, ps in ipairs(self.sandyPitch or {}) do ps:Destroy() end
		self.sandyPitch = nil
		local cc = self.sandyFx
		self.sandyFx = nil
		if cc then
			TweenService:Create(cc, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
			Debris:AddItem(cc, 0.35)
		end
	end
end

-- a burst of torn scanlines across the screen, the moment time breaks
function TyreSkills:glitch(time: number)
	local parent = self.gui
	if not parent then return end
	local holder = Instance.new("Frame")
	holder.Name = "SandyGlitch"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 80
	holder.Parent = parent
	local wash = Instance.new("Frame")
	wash.Size = UDim2.fromScale(1, 1)
	wash.BorderSizePixel = 0
	wash.BackgroundColor3 = Color3.fromRGB(150, 255, 210)
	wash.BackgroundTransparency = 0.72
	wash.ZIndex = 80
	wash.Parent = holder
	TweenService:Create(wash, TweenInfo.new(time, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	local bars = {}
	for i = 1, 14 do
		local b = Instance.new("Frame")
		b.BorderSizePixel = 0
		b.BackgroundColor3 = GLITCH[(i % #GLITCH) + 1]
		b.BackgroundTransparency = 0.35
		b.ZIndex = 81
		b.Parent = holder
		table.insert(bars, b)
	end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t >= time then
			conn:Disconnect()
			holder:Destroy()
			return
		end
		-- the bars jump about every frame, thinning out as it settles
		local k = 1 - t / time
		for _, b in ipairs(bars) do
			b.Size = UDim2.new(math.random(30, 100) / 100, 0, 0, math.random(2, 16))
			b.Position = UDim2.new(math.random(-20, 40) / 100, 0, math.random(), 0)
			b.BackgroundTransparency = if math.random() < 0.8 then 1 - 0.65 * k else 1
		end
	end)
end

-- an afterimage left where the tyre is now, from the pool
function TyreSkills:afterimage()
	local pool = self.ghostPool
	if not pool then return end
	local g = pool[self.ghostNext]
	self.ghostNext = (self.ghostNext % #pool) + 1
	self.sandyHue = (self.sandyHue + 0.045) % 1
	-- green through cyan and blue to magenta, and back
	local h = 0.33 + 0.5 * (0.5 - 0.5 * math.cos(self.sandyHue * math.pi * 2))
	local colour = Color3.fromHSV(h, 0.78, 1)
	g.model:PivotTo(self.sim.model:GetPivot())
	g.born = os.clock()
	for _, p in ipairs(g.parts) do
		p.Color = colour
		p.Transparency = 0.3
	end
end

function TyreSkills:ring(on: boolean)
	if on and not self.zeroRing then
		-- two orbits with moonlets riding them, swirling round the tyre
		local model = self:skillModel("Skills/OrbitRing")
		if model then
			self.zeroRing = model
		else
			local r = Game.TyreRadius * 1.8
			local ring = part(self.sim.folder, Vector3.new(0.3, r * 2, r * 2), Color3.fromRGB(230, 232, 255), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			ring.Transparency = 0.35
			self.zeroRing = ring
		end
		self.zeroIn = os.clock()
		Sound.play("gateWhoosh", { volume = 0.5, pitch = 0.6 })
	elseif not on and self.zeroRing then
		self.zeroRing:Destroy()
		self.zeroRing = nil
	end
end

function TyreSkills:blocky(on: boolean)
	-- while Mine is armed a pixel pickaxe hovers over the tyre, and swings at whatever it breaks
	if on and not self.mineBox then
		local model = self:skillModel("Skills/VoxelPick", 0.9)
		if model then
			self.mineBox = model
		else
			local s = Game.TyreRadius * 2.3
			local box = part(self.sim.folder, Vector3.new(s, s, Game.TyreRadius), Color3.fromRGB(90, 200, 90), Enum.Material.SmoothPlastic)
			box.Transparency = 0.7
			self.mineBox = box
		end
		self.mineSwing = -1
		Sound.play("land", { volume = 0.4, pitch = 1.8 })
	elseif not on and self.mineBox then
		self.mineBox:Destroy()
		self.mineBox = nil
	end
end

-- Rebirth's wings: they open out of the tyre's back, beat once, fold and go
function TyreSkills:wings()
	if self.wingSet then self.wingSet.model:Destroy() end
	local model = self:skillModel("Skills/ScarabWings")
	if not model then return end
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "WingL" or d.Name == "WingR") then table.insert(parts, d) end
	end
	local pivot = model:GetPivot()
	local s = Game.TyreRadius * 2 / BALL_BUILT
	local wings = {}
	for _, w in ipairs(parts) do
		local rest = pivot:ToObjectSpace(w.CFrame)
		-- each wing hinges at its root, just behind the hub and a little above it
		local side = if rest.Position.Z > 0 then 1 else -1
		local hinge = Vector3.new(-2.6 * s, 1.2 * s, side * 1.6 * s)
		table.insert(wings, { part = w, rest = rest, hinge = hinge, side = side })
	end
	self.wingSet = { model = model, wings = wings, t0 = os.clock() }
end

function TyreSkills:puff(on: boolean)
	local sim = self.sim
	pcall(function() sim.model:ScaleTo(on and 1.35 or 1) end)
	if on then PackFX.burst("dustPuff", CFrame.new(sim.x, sim.y, sim.z), 12, Color3.fromRGB(255, 170, 210), 1.6) end
end

-- an afterimage: a see-through copy of the tyre left behind
function TyreSkills:ghost(color: Color3, life: number)
	local sim = self.sim
	local src = self.ball or sim.model
	local g = src:Clone()
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("ParticleEmitter") or d:IsA("Attachment") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = false
			d.Material = Enum.Material.ForceField
			d.Color = color
			d.LocalTransparencyModifier = 0
			d.Transparency = 0.1
			TweenService:Create(d, TweenInfo.new(life), { Transparency = 1 }):Play()
		end
	end
	g.Parent = sim.folder
	Debris:AddItem(g, life + 0.05)
end

function TyreSkills:frame(dt: number)
	local sim = self.sim
	local pos = Vector3.new(sim.x, sim.y, sim.z)
	self.anchor.CFrame = CFrame.new(pos)
	local fast = sim.vx > 520
	if self.fx.sparks then self.fx.sparks.Enabled = sim.grounded and (fast or (self.special == "kart" and math.abs(sim.steer or 0) > 0.6)) end
	if self.fx.sand then self.fx.sand.Enabled = sim.grounded and sim.vx > 80 end
	if self.fx.stars then self.fx.stars.Enabled = not sim.grounded end
	if self.fx.glaze then self.fx.glaze.Enabled = sim.vx > 60 end
	if self.fx.jet then self.fx.jet.Enabled = sim.usingBoost == true end
	if self.fx.turbo then self.fx.turbo.Enabled = (self.turboTier or 0) > 0 end
	if self.fx.revDust then
		local rev = self.revving and sim.grounded
		self.fx.revDust.Enabled = rev == true
		if rev then
			self.fx.revDust.Rate = 20 + 70 * (self.rev or 0)
			self.fx.revDust.Color = ColorSequence.new(sim.track:cfgAt(sim.x).ground:Lerp(Color3.new(1, 1, 1), 0.35))
		end
	end
	if self.ball then
		-- revving spins it up on the spot, faster as the charge builds
		if self.revving then self.ballSpin = (self.ballSpin or 0) + dt * (14 + 36 * (self.rev or 0)) end
		local roll = (sim.roll or 0) * 2 + (self.ballSpin or 0)
		self.ball:PivotTo(CFrame.new(pos) * CFrame.Angles(0, 0, -roll))
		for i, ring in ipairs(self.ballRings) do
			ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, -roll * (1 + i * 0.3)) * CFrame.Angles(0, math.rad(i * 60), 0)
		end
	end
	if self.zeroRing then
		local ring = self.zeroRing
		if ring:IsA("Model") then
			-- the orbits grow in and swirl
			local k = math.min(1, (os.clock() - (self.zeroIn or 0)) / 0.3)
			local grow = 1 - (1 - k) ^ 3
			ring:PivotTo(CFrame.new(pos) * CFrame.Angles(0, os.clock() * 1.8, 0) * CFrame.Angles(math.rad(8) * math.sin(os.clock() * 1.3), 0, 0))
			if math.abs(ring:GetScale() - grow * (Game.TyreRadius * 2 / BALL_BUILT)) > 0.01 then
				pcall(function() ring:ScaleTo(math.max(0.05, grow * (Game.TyreRadius * 2 / BALL_BUILT))) end)
			end
		else
			(ring :: BasePart).CFrame = CFrame.new(pos) * CFrame.Angles(0, os.clock() * 2, math.rad(90)) * CFrame.Angles(math.rad(70), 0, 0)
		end
	end
	if self.mineBox then
		local box = self.mineBox
		if box:IsA("Model") then
			-- over the tyre's shoulder, bobbing; a swing down when it breaks something
			local bob = math.sin(os.clock() * 3) * 0.4
			local since = os.clock() - (self.mineSwing or -1)
			local swing = if since >= 0 and since < 0.45 then math.sin(since / 0.45 * math.pi) * math.rad(-75) else 0
			box:PivotTo(CFrame.new(pos + Vector3.new(-1.5, Game.TyreRadius * 1.9 + bob, -Game.TyreRadius * 0.9)) * CFrame.Angles(swing, 0, math.rad(-10)))
		else
			(box :: BasePart).CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, -(sim.roll or 0))
		end
	end
	if self.wingSet then
		local ws = self.wingSet
		local t = os.clock() - ws.t0
		-- gliding: held open, flapping now and then
		if self.wingsT and self.wingsT > 0.2 then t = 0.62 + 0.1 * math.sin(os.clock() * 9) end
		-- open (0 - 0.35), one beat (0.5 - 0.85), fold (1.1 - 1.4), gone
		local open = if t < 0.35 then 1 - (1 - t / 0.35) ^ 3 elseif t < 1.1 then 1 else math.max(0, 1 - (t - 1.1) / 0.3)
		local beat = if t > 0.5 and t < 0.85 then math.sin((t - 0.5) / 0.35 * math.pi) * 0.35 else 0
		local fold = (1 - open) * math.rad(85) + beat
		local base = CFrame.new(pos)
		for _, w in ipairs(ws.wings) do
			local hinge = CFrame.new(w.hinge)
			local turn = hinge * CFrame.Angles(w.side * fold, 0, 0) * hinge:Inverse()
			w.part.CFrame = base * turn * w.rest
			w.part.Transparency = if t > 1.1 then math.clamp((t - 1.1) / 0.3, 0, 1) else 0
		end
		if t > 1.45 then
			ws.model:Destroy()
			self.wingSet = nil
		end
	end
	-- afterimages: Sandevistan lays one down every few studs travelled; the dash leaves blue copies
	if self.sandy then
		local last = self.sandyLast or pos
		self.sandyMoved += (pos - last).Magnitude
		self.sandyLast = pos
		if self.sandyMoved >= SANDY_GAP then
			self.sandyMoved = 0
			self:afterimage()
		end
	else
		self.sandyLast = nil
	end
	if self.ghostPool then
		local now = os.clock()
		for _, g in ipairs(self.ghostPool) do
			if g.born >= 0 then
				local k = (now - g.born) / SANDY_LIFE
				local tr = if k >= 1 then 1 else 0.3 + 0.7 * k * k
				if k >= 1 then g.born = -1 end
				for _, p in ipairs(g.parts) do p.Transparency = tr end
			end
		end
	end
	if self.dashT then
		self.ghostT -= dt
		if self.ghostT <= 0 then
			self.ghostT = 0.04
			self:ghost(Color3.fromRGB(120, 180, 255), 0.25)
		end
	end
	if self.inhaleT then
		if not self.inhaleFx then
			self.inhaleFx = emitter(self.mid, {
				Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(255, 220, 240)),
				Size = seq(3, 0.5), Transparency = seq(0.6, 1), Lifetime = NumberRange.new(0.35, 0.5), Speed = NumberRange.new(-120, -90),
				SpreadAngle = Vector2.new(25, 25), Rate = 120, EmissionDirection = Enum.NormalId.Front,
			})
			self.inhaleFx.Enabled = true
		end
	elseif self.inhaleFx then
		self.inhaleFx:Destroy()
		self.inhaleFx = nil
	end
end

function TyreSkills:destroy()
	self:showBall(false)
	self:sandevistan(false)
	if self.sandyFx then self.sandyFx:Destroy() end
	for _, g in ipairs(self.ghostPool or {}) do g.model:Destroy() end
	self.ghostPool = nil
	self:ring(false)
	self:blocky(false)
	if self.wingSet then self.wingSet.model:Destroy() end
	self.wingSet = nil
	if self.card then self.card:Destroy() end
	if self.anchor then self.anchor:Destroy() end
end

return TyreSkills
