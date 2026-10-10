--!strict
-- TYRE CANNON :: SkillZones
-- Stretches of road set out for the launch tyre's skill (TrackGen:skillZones), so the skill is part
-- of the road rather than a button pressed anywhere:
--   air    Scarab Wings, Zero-G, Inhale: an updraft. With the skill running inside it you climb
--   smash  Meteor, Drill Dash, Mine: a scatter of extra smashables (TrackGen); each one smashed
--          while the skill is running is a second link (the chain's cash multiplier climbs faster)
--   speed  Sandevistan, Mini-Turbo: a line of boost pads (TrackGen); the skill doubles their kick
-- Each zone has a glowing arch at each end, a coloured band down the road between them and a sign
-- at the entry. Inside, the skill comes back three times as fast; used (or running) inside, it's a
-- link, a refill of nitro and a SKILL ZONE stamp. A call comes up as one gets near.
--   SkillZones.kindOf(skillId) -> kind?
--   SkillZones.new(sim, skillId) -> SkillZones? ; :step(dt) ; :frame(dt) ; :smashed() -> bool ; :destroy()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Game = require(Modules:WaitForChild("Game"))
local Config = require(Modules:WaitForChild("Config"))

local SkillZones = {}
SkillZones.__index = SkillZones

local KIND = {
	wings = "air", zerog = "air", inhale = "air",
	groundpound = "smash", spindash = "smash", mine = "smash",
	sandevistan = "speed", miniturbo = "speed",
}
local COLOR = {
	air = Color3.fromRGB(255, 205, 70),
	smash = Color3.fromRGB(255, 110, 60),
	speed = Color3.fromRGB(90, 210, 255),
}
local HINT = {
	air = "UPDRAFT · USE IT TO CLIMB",
	smash = "SMASH THROUGH · EVERY HIT LINKS TWICE",
	speed = "PADS · DOUBLE KICK",
}
local BUILD_AHEAD = 1100
local UPDRAFT = 0.4     -- the updraft, as a share of gravity, pushing up while the skill runs

function SkillZones.kindOf(skillId: string?): string?
	return skillId and KIND[skillId] or nil
end

function SkillZones.new(sim, skillId: string?)
	local kind = SkillZones.kindOf(skillId)
	if not kind or not sim.track.isRoad then return nil end
	local self = setmetatable({}, SkillZones)
	self.sim = sim
	self.kind = kind
	self.color = COLOR[kind]
	self.name = (skillId and Game.Skills[skillId] and Game.Skills[skillId].name or "SKILL"):upper()
	self.built = {}       -- zone index -> Folder
	self.paid = {}        -- zone index -> true once its bonus is given
	self.called = {}      -- zone index -> true once its "ahead" call is made
	self.inside = nil
	local f = Instance.new("Folder")
	f.Name = "SkillZones"
	f.Parent = sim.folder
	self.folder = f
	return self
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, alpha: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.Neon
	p.Transparency = alpha or 0
	p.Parent = parent
	return p
end

function SkillZones:build(zone)
	local track = self.sim.track
	local f = Instance.new("Folder")
	f.Name = "Zone" .. zone.i
	local col = self.color
	local half = Config.Physics.CorridorHalfWidth
	local w = half * 0.8
	-- an arch at each end
	for _, x in ipairs({ zone.x0, zone.x1 }) do
		local y = track:heightAt(x)
		for side = -1, 1, 2 do
			part(f, Vector3.new(3, 46, 3), CFrame.new(x, y + 23, side * w), col, Enum.Material.Neon, 0.1)
		end
		part(f, Vector3.new(3, 3, w * 2 + 3), CFrame.new(x, y + 46, 0), col, Enum.Material.Neon, 0.1)
	end
	-- the band down the road between them, slab by slab
	local SEG = 10
	local x = zone.x0
	while x < zone.x1 do
		local x2 = math.min(zone.x1, x + SEG)
		local a = Vector3.new(x, track:heightAt(x) + 0.6, 0)
		local b = Vector3.new(x2, track:heightAt(x2) + 0.6, 0)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		part(f, Vector3.new(len + 0.4, 0.2, w * 2), CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0), col, Enum.Material.Neon, 0.78)
		x = x2
	end
	-- an updraft: golden motes rising the length of the zone
	if self.kind == "air" then
		-- (a run of short emitters along the ground, so the motes rise off the road all the way)
		for k = 0, 5 do
		local mid = zone.x0 + (k + 0.5) * (zone.x1 - zone.x0) / 6
		local base = part(f, Vector3.new((zone.x1 - zone.x0) / 6, 1, w * 2), CFrame.new(mid, track:heightAt(mid) + 2, 0), col, Enum.Material.Neon, 1)
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(col)
		pe.LightEmission = 1
		pe.Rate = 15
		pe.Lifetime = NumberRange.new(2.5, 4)
		pe.Speed = NumberRange.new(40, 70)
		pe.EmissionDirection = Enum.NormalId.Top
		pe.SpreadAngle = Vector2.new(8, 8)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0.4) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		pe.Parent = base
		end
	end
	-- the sign at the entry
	local y0 = track:heightAt(zone.x0)
	local anchor = part(f, Vector3.new(1, 1, 1), CFrame.new(zone.x0, y0 + 58, 0), col, Enum.Material.Neon, 1)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(70, 16)    -- (in studs: it shrinks with distance like the arch it's on)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 1400
	bb.Parent = anchor
	local function label(text: string, y: number, h: number, c: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0, y)
		l.Size = UDim2.fromScale(1, h)
		l.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
		l.Text = text
		l.TextScaled = true
		l.TextColor3 = c
		l.TextStrokeTransparency = 0.2
		l.Parent = bb
	end
	label("SKILL ZONE · " .. self.name, 0, 0.58, col)
	label(HINT[self.kind], 0.6, 0.38, Color3.new(1, 1, 1))
	f.Parent = self.folder
	self.built[zone.i] = { folder = f, zone = zone }
end

-- every sim step: the zone you're in changes the skill's cooldown and the air
function SkillZones:step(dt: number)
	local sim = self.sim
	local sk = sim.skills
	local here = nil
	for _, zone in ipairs(sim.track:skillZones(sim.x, sim.x + 1)) do
		if sim.x >= zone.x0 and sim.x < zone.x1 then here = zone end
	end
	self.inside = here
	if not here or not sk then return end
	-- the skill comes back three times as fast in here
	sk.cooldown = math.max(0, sk.cooldown - dt * 2)
	local running = sk:isActive()
	if running and not self.paid[here.i] then
		self.paid[here.i] = true
		sim.perfects += 1
		sim:link()
		sim.nitro = math.min(sim.nitroMax, sim.nitro + 25)
		sim.onEvent({ kind = "skillzone", what = "bonus", name = self.name, chain = sim.chain, combo = sim.combo })
	end
	-- the updraft lifts a tyre whose skill is running (in the air)
	if self.kind == "air" and running and not sim.grounded then
		sk.gravity = -UPDRAFT
	end
end

-- a smash in a smash zone while the skill runs pays again
function SkillZones:smashed(): boolean
	local sk = self.sim.skills
	if self.kind == "smash" and self.inside and sk and sk:isActive() then
		-- a second link for it: the chain (and the cash multiplier it carries) climbs twice as fast
		self.sim:link()
		return true
	end
	return false
end

-- a pad in a speed zone while the skill runs kicks twice as hard
function SkillZones:padMult(): number
	local sk = self.sim.skills
	if self.kind == "speed" and self.inside and sk and sk:isActive() then return 2 end
	return 1
end

-- every frame: build the zones coming up, clear the ones behind, call the next one
function SkillZones:frame(_dt: number)
	local sim = self.sim
	local x = sim.x
	for _, zone in ipairs(sim.track:skillZones(x - 300, x + BUILD_AHEAD)) do
		if not self.built[zone.i] and zone.x1 > x then self:build(zone) end
		if not self.called[zone.i] and zone.x0 > x and zone.x0 - x < math.max(260, sim.speed * 2.2) then
			self.called[zone.i] = true
			local sk = sim.skills
			sim.onEvent({ kind = "skillzone", what = "ahead", name = self.name, ready = sk and sk:ready() or false })
		end
	end
	for i, b in pairs(self.built) do
		if b.zone.x1 < x - 250 then
			b.folder:Destroy()
			self.built[i] = nil
		end
	end
end

function SkillZones:destroy()
	if self.folder then self.folder:Destroy() end
	self.built = {}
end

return SkillZones
