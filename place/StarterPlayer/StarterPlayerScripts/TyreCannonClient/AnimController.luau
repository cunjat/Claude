--!strict
-- TYRE CANNON :: AnimController
-- One owner for the character's animations, so nothing ever fights over the
-- body. Roblox's default Animate script is removed on spawn and this drives
-- everything from the Humanoid's state:
--   ground   idle (the watch check now and then) / walk / run
--   air      jump (lift-off) -> jumpFall (coming down), or fall if you never jumped
--   landing  land, once, then back to the ground set
--   extras   victory, and the sad sit on a chair
-- Priorities keep layers apart: Idle < Movement < Action < Action2 < Action4.
-- Every switch fades the old track out, so two loops never play together.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))
local Prefs = require(script.Parent.Prefs)
local AnimIds = require(script.Parent.AnimIds)
local Assets = Root:WaitForChild("Assets")

local AnimController = {}
AnimController.__index = AnimController

local WALK_REF = 22			-- studs/s the walk looks right at (Movement's walk speed)
local RUN_REF = 38			-- and the run (Movement's sprint)
local LEAN_TURN = 0.075		-- radians of lean per radian a second of turning
local LEAN_MAX = 0.2
local PackFX = require(script.Parent.PackFX)
local FADE = 0.2
local P = Enum.AnimationPriority

local function load(animator: Animator, id: string?, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	if type(id) ~= "string" or id == "" then return nil end
	local a = Instance.new("Animation")
	a.AnimationId = id
	local ok, track = pcall(function() return animator:LoadAnimation(a) end)
	if not ok or not track then return nil end
	track.Priority = priority
	track.Looped = looped
	return track
end

function AnimController.new(player: Player, movement)
	local self = setmetatable({}, AnimController)
	self.player = player
	self.movement = movement
	self.tracks = {}
	self.loco = nil
	self.air = nil
	self.enabled = true
	self.sitting = nil
	player.CharacterAdded:Connect(function(char) self:bind(char) end)
	if player.Character then task.spawn(function() self:bind(player.Character) end) end
	self.stepConn = RunService.Heartbeat:Connect(function(dt) self:step(dt) end)
	return self
end

function AnimController:bind(char: Model)
	self:standUp(true)
	self.tracks = {}
	self.loco, self.air = nil, nil
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then return end
	-- (2026-10-23, the owner: "we'll just use base roblox animations for now") Config.UseRobloxAnimations
	-- keeps Roblox's own Animate script for walking, running, jumping and sitting; this only plays the
	-- extras (the victory dance, the sad sit)
	self.roblox = Config.UseRobloxAnimations == true
	local animate = char:FindFirstChild("Animate")
	if animate and not self.roblox then animate:Destroy() end
	local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5)
	if not animator then return end
	if not self.roblox then
		for _, t in ipairs((animator :: Animator):GetPlayingAnimationTracks()) do t:Stop(0) end
	end
	self.hum = hum
	self.char = char
	self.animator = animator
	self.dances = {}
	self.dance = nil
	self.root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- the joint the whole body hangs off (R6 RootJoint, R15 Root), for leaning into turns
	local joint = (self.root and self.root:FindFirstChild("RootJoint")) or char:FindFirstChild("Root", true)
	if joint and joint:IsA("Motor6D") then
		self.joint = joint
		self.jointC0 = joint.C0
	else
		self.joint, self.jointC0 = nil, nil
	end
	self.lean = Vector2.zero
	self.lastLook = nil
	self.lastSpeed = 0
	self.groundOn = false
	self.dustAt = 0

	-- AnimIds swaps in Roblox's R6 defaults for any upload this game isn't allowed to play
	self.nextIdle2 = os.clock() + math.random(8, 14)
	AnimIds.wait()
	if self.char ~= char then return end
	local A = AnimIds.get
	local an = animator :: Animator
	if self.roblox then
		self.tracks = {
			victory = load(an, A("victory"), P.Action2, false),
			sadSit = load(an, A("sadSit"), P.Action4, true),
		}
		return
	end
	self.tracks = {
		idle = load(an, A("idle"), P.Idle, true),
		idle2 = load(an, A("idle2"), P.Idle, false),
		walk = load(an, A("walk"), P.Movement, true),
		run = load(an, A("run"), P.Movement, true),
		jump = load(an, A("jump"), P.Action, false),
		jumpFall = load(an, A("jumpFall"), P.Action, true),
		fall = load(an, A("fall"), P.Action, true),
		land = load(an, A("land"), P.Action, false),
		victory = load(an, A("victory"), P.Action2, false),
		sadSit = load(an, A("sadSit"), P.Action4, true),
	}
	self.nextIdle2 = os.clock() + math.random(8, 14)
	self.jumped = false
	hum.StateChanged:Connect(function(_, new) self:onState(new) end)
end

function AnimController:setLoco(name: string?, speed: number?)
	local t = self.tracks
	if name == nil and self.groundOn then
		-- leaving the ground (or switched off): the blended idle, walk and run all fade out
		for _, k in ipairs({ "idle", "walk", "run" }) do
			if t[k] then t[k]:Stop(0.15) end
		end
		self.groundOn = false
		self.loco = nil
		return
	end
	if self.loco ~= name then
		if self.loco and t[self.loco] then t[self.loco]:Stop(FADE) end
		self.loco = name
		if name and t[name] then t[name]:Play(FADE) end
	end
	if name and t[name] and speed then t[name]:AdjustSpeed(speed) end
end

function AnimController:setAir(name: string?)
	local t = self.tracks
	if self.air == name then return end
	if self.air and t[self.air] then t[self.air]:Stop(0.12) end
	self.air = name
	if name and t[name] then t[name]:Play(0.1) end
end

function AnimController:onState(state: Enum.HumanoidStateType)
	if self.sitting or not self.enabled then return end
	local S = Enum.HumanoidStateType
	if state == S.Jumping then
		self.jumped = true
		self:setLoco(nil)
		self:setAir("jump")
	elseif state == S.Freefall then
		self:setLoco(nil)
		if not self.jumped then self:setAir("fall") end
	elseif state == S.Landed then
		self:setAir(nil)
		self.jumped = false
		local land = self.tracks.land
		if land then land:Play(0.05) end
		if (self.fallSpeed or 0) > 45 and self.root then
			pcall(function()
				PackFX.burst("dustRing", CFrame.new(self.root.Position - Vector3.new(0, 2.8, 0)), 3, Color3.fromRGB(214, 206, 190), 0.32)
			end)
		end
	elseif state == S.Running or state == S.RunningNoPhysics then
		self:setAir(nil)
		self.jumped = false
	end
end

function AnimController:step(_dt: number)
	local hum, root = self.hum, self.root
	if self.roblox then return end
	if not (hum and root and hum.Parent) or self.sitting or not self.enabled then return end
	-- (2026-10-24) sat on a bench: the idle/walk/run blend stops, so BenchPose's sitting pose is the
	-- only thing on the body (the idle's arms and legs showed through it)
	if hum.Sit then
		self:setLoco(nil)
		self:setAir(nil)
		self:leanTo(0, 0, _dt)
		return
	end
	local state = hum:GetState()
	local S = Enum.HumanoidStateType
	if state == S.Freefall or state == S.Jumping then
		self.fallSpeed = math.max(0, -root.AssemblyLinearVelocity.Y)
		if self.jumped and self.air == "jump" and root.AssemblyLinearVelocity.Y < -2 then
			self:setAir("jumpFall")
		end
		self:leanTo(0, 0, _dt)
		return
	end
	if self.victoryPlaying then
		local v = root.AssemblyLinearVelocity
		if Vector3.new(v.X, 0, v.Z).Magnitude > 2 and self.dance then
			self.dance:Stop(0.2)
			self.victoryPlaying = false
		else
			return
		end
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local t = self.tracks
	-- something else (a dance, the chair) stopped the ground set: start it again
	if self.groundOn and t.idle and not t.idle.IsPlaying then self.groundOn = false end
	if not self.groundOn then
		self.groundOn = true
		self.loco = "ground"
		if t.idle then t.idle:Play(0.2, 1) end
		if t.walk then t.walk:Play(0.2, 0.01) end
		if t.run then t.run:Play(0.2, 0.01) end
	end
	-- how much you're moving, and how far from a walk to a run
	local move = math.clamp((speed - 0.6) / 5, 0, 1)
	local runK = math.clamp((speed - WALK_REF * 0.9) / (RUN_REF * 0.95 - WALK_REF * 0.9), 0, 1)
	runK = runK * runK * (3 - 2 * runK)
	if t.idle then t.idle:AdjustWeight(math.max(0.01, 1 - move), 0.12) end
	if t.walk then
		t.walk:AdjustWeight(math.max(0.01, move * (1 - runK)), 0.12)
		t.walk:AdjustSpeed(math.clamp(speed / WALK_REF, 0.45, 1.5))
	end
	if t.run then
		t.run:AdjustWeight(math.max(0.01, move * runK), 0.12)
		t.run:AdjustSpeed(math.clamp(speed / RUN_REF, 0.6, 1.4))
	end
	if move < 0.05 and os.clock() > self.nextIdle2 then
		self.nextIdle2 = os.clock() + math.random(10, 18)
		local i2 = t.idle2
		if i2 then i2:Play(0.3) end
	end
	-- lean into turns, a touch forward when speeding up, back when braking
	local look = root.CFrame.LookVector
	local yawRate = 0
	if self.lastLook and _dt > 0 then
		local a = math.atan2(-look.X, -look.Z) - math.atan2(-self.lastLook.X, -self.lastLook.Z)
		if a > math.pi then a -= 2 * math.pi elseif a < -math.pi then a += 2 * math.pi end
		yawRate = a / _dt
	end
	self.lastLook = look
	local accel = if _dt > 0 then (speed - self.lastSpeed) / _dt else 0
	self.lastSpeed = speed
	local roll = math.clamp(yawRate * LEAN_TURN, -LEAN_MAX, LEAN_MAX) * move * (0.5 + 0.5 * runK)
	local pitch = math.clamp(accel * 0.004, -0.1, 0.12) + 0.05 * runK * move
	self:leanTo(pitch, roll, _dt)
	-- a puff of dust off the heels while sprinting
	if runK > 0.7 and speed > 30 and os.clock() > self.dustAt then
		self.dustAt = os.clock() + 0.3
		pcall(function()
			PackFX.burst("dustPuff", CFrame.new(root.Position - Vector3.new(0, 2.8, 0) - look * 1.2), 1, Color3.fromRGB(214, 206, 190), 0.28)
		end)
	end
end

-- eases the body's lean toward (pitch forward, roll into the turn)
function AnimController:leanTo(pitch: number, roll: number, dt: number)
	if not (self.joint and self.jointC0) then return end
	local k = math.min(1, dt * 8)
	self.lean = self.lean:Lerp(Vector2.new(pitch, roll), k)
	self.joint.C0 = CFrame.Angles(-self.lean.X, 0, self.lean.Y) * self.jointC0
end

function AnimController:setEnabled(on: boolean)
	self.enabled = on
	if not on then
		self:setLoco(nil)
		self:setAir(nil)
		if self.joint and self.jointC0 then self.joint.C0 = self.jointC0 end
		self.lean = Vector2.zero
	end
end

--==============================================================
-- victory
--==============================================================
-- plays the dance picked in Settings; walking away cuts it short
function AnimController:victory()
	if self.sitting or not self.animator then return end
	local d = Config.VictoryDancesById[Prefs.get("dance")] or Config.VictoryDances[1]
	local t = self.dances[d.id]
	if not t then
		local looped = d.seconds ~= nil or (d.loops or 1) > 1
		t = load(self.animator :: Animator, d.anim, P.Action2, looped)
		if not t then return end
		self.dances[d.id] = t
	end
	if self.dance and self.dance ~= t then self.dance:Stop(0.15) end
	self.dance = t
	self:setLoco(nil)
	self:setAir(nil)
	self.victoryPlaying = true
	local token = (self.danceToken or 0) + 1
	self.danceToken = token
	t:Play(0.2)
	t.Stopped:Once(function()
		if self.danceToken == token then self.victoryPlaying = false end
	end)
	-- looping emotes stop on their own after a few seconds or a few loops
	local seconds = d.seconds
	if not seconds and d.loops then
		local start = os.clock()
		while t.Length == 0 and os.clock() - start < 2 do task.wait(0.05) end
		seconds = t.Length * d.loops
	end
	if seconds then
		task.delay(seconds, function()
			if self.danceToken == token and t.IsPlaying then t:Stop(0.3) end
		end)
	end
end

--==============================================================
-- the sad sit: a plastic chair appears and you slump into it. Any move key
-- stands you back up and the chair goes away. Tweak SitHeight / SitBack on
-- Assets.Props.Chair until the seat and the animation line up.
--==============================================================
function AnimController:sadSit(chairCF: CFrame)
	local hum, root = self.hum, self.root
	local tpl = Assets.Props:FindFirstChild("Chair") :: BasePart?
	if not (hum and root and tpl) or self.sitting then return end
	local chair = tpl:Clone()
	chair.Anchored = true
	chair.CanCollide = false
	chair.CFrame = chairCF
	chair.Parent = workspace

	local seat = chairCF * (tpl:GetAttribute("SeatOffset") or Vector3.zero)
	local facing = chairCF:VectorToWorldSpace(tpl:GetAttribute("SeatFacing") or Vector3.new(0, 0, 1))
	facing = Vector3.new(facing.X, 0, facing.Z).Unit
	local height = tpl:GetAttribute("SitHeight") or 1.0
	local back = tpl:GetAttribute("SitBack") or 0
	local pos = seat + Vector3.new(0, height, 0) - facing * back

	self:setLoco(nil)
	self:setAir(nil)
	root.Anchored = true
	root.CFrame = CFrame.lookAt(pos, pos + facing)
	if self.movement then self.movement:setEnabled(false) end
	local t = self.tracks.sadSit
	if t then t:Play(0.25) end
	self.sitting = { chair = chair }

	task.delay(0.6, function()
		if not self.sitting then return end
		self.sitting.conn = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then return end
			local K = Enum.KeyCode
			local k = input.KeyCode
			if k == K.W or k == K.A or k == K.S or k == K.D or k == K.Space or k == K.Up or k == K.Down
				or k == K.Left or k == K.Right or k == K.ButtonA or k == K.Thumbstick1 then
				self:standUp(false)
			end
		end)
	end)
end

function AnimController:standUp(silent: boolean)
	local s = self.sitting
	if not s then return end
	self.sitting = nil
	if s.conn then s.conn:Disconnect() end
	if self.tracks.sadSit then self.tracks.sadSit:Stop(0.2) end
	if self.root then
		self.root.Anchored = false
		if not silent then self.root.CFrame = self.root.CFrame * CFrame.new(0, 0.5, -2.5) end
	end
	if self.movement then self.movement:setEnabled(true) end
	if s.chair then s.chair:Destroy() end
end

--==============================================================
-- NPCs: idle loop with the occasional watch check
--==============================================================
function AnimController.idleNPC(model: Model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local animator = hum and (hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum))
	if not animator then return end
	-- in its own thread: AnimIds may still be checking which uploads this game can play
	task.spawn(function()
		AnimIds.wait()
		if not model.Parent then return end
		local idle = load(animator :: Animator, AnimIds.get("idle"), P.Idle, true)
		local idle2 = load(animator :: Animator, AnimIds.get("idle2"), P.Idle, false)
		if idle then idle:Play(0.3) end
		if idle2 then
			task.wait(math.random() * 10)
			while model.Parent do
				task.wait(math.random(9, 16))
				if model.Parent then idle2:Play(0.3) end
			end
		end
	end)
end

return AnimController
