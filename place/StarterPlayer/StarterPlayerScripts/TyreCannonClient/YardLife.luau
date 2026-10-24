--!strict
-- TYRE CANNON :: YardLife
-- The machines on the yards near you, ticking over: the cooling tower's fan turns and a lazy wisp
-- of steam lifts off it, the compressor shudders and every few seconds lets off a pssht of air,
-- and now and then a thread of smoke curls out of a cannon's muzzle. Only yards within reach of
-- the camera, and nothing while you're away from the yard (runs, the workbench).
--   YardLife.new(plot2) ; :setPaused(on)

local RunService = game:GetService("RunService")
local Models = require(script.Parent.Models)
local PackFX = require(script.Parent.PackFX)
local MuzzleFX = require(script.Parent.MuzzleFX)

local STEAM_REACH = 140 -- studs from the camera
local YardLife = {}
YardLife.__index = YardLife

local REACH = 300
local FAN_SPEED = 7		-- radians a second

local function ns(list: { { number } }): NumberSequence
	local k = {}
	for _, p in ipairs(list) do table.insert(k, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(k)
end

-- the imported model inside a yard machine (Plot2 wraps it with its level plate)
local function inner(m: Model): Model?
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("Model") then return c end
	end
	return nil
end

function YardLife.new(plot2)
	local self = setmetatable({}, YardLife)
	self.plot2 = plot2
	self.paused = false
	self.state = {} :: { [Instance]: any }
	self.t = 0
	self.conn = RunService.RenderStepped:Connect(function(dt) self:step(dt) end)
	return self
end

function YardLife:setPaused(on: boolean)
	self.paused = on
	for _, st in pairs(self.state) do
		if st.steam then st.steam.Enabled = not on end
	end
end

-- what we keep per machine model, made the first time it's seen
function YardLife:stateFor(id: string, m: Model)
	local st = self.state[m]
	if st and st.model and st.model.Parent == m then return st end
	local model = inner(m)
	if not model then return nil end
	st = { model = model, id = id, next = os.clock() + math.random() * 6 }
	-- where the imported model sits inside the machine, so a shudder can be put on top of it
	st.rel = m:GetPivot():ToObjectSpace(model:GetPivot())
	-- what spins: the cooling fan, the turbo's compressor wheel. The racing radiator's fan and the
	-- turbo's wheel turn on their own axle (the model's Z, Blender's Y); the old tower's fan on Y
	local fan = (id == "cooling" and model:FindFirstChild("Fan", true)) or (id == "compressor" and model:FindFirstChild("Rotor", true)) or nil
	if fan and fan:IsA("BasePart") then
		st.fan = fan
		st.fanRel = model:GetPivot():ToObjectSpace(fan.CFrame)
		st.spinZ = model.Name == "Radiator" or model.Name == "Turbo"
		st.angle = math.random() * math.pi * 2
	end
	if id == "cooling" then
		-- steam drifting up off the top
		local top = Instance.new("Attachment")
		local _, size = model:GetBoundingBox()
		top.CFrame = CFrame.new(0, size.Y + 0.5, 0)
		top.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		local e = MuzzleFX.emitter(top, PackFX.Sheet.steam, {
			-- a thin wisp, not a cloud: big translucent puffs stacked up over the yards (and right
			-- into the yard editor's camera) were the lag
			EmissionDirection = Enum.NormalId.Top, Lifetime = NumberRange.new(1.4, 2), Speed = NumberRange.new(2.5, 4),
			Drag = 0.6, SpreadAngle = Vector2.new(10, 10), Size = ns({ { 0, 0.8 }, { 1, 3 } }),
			Transparency = ns({ { 0, 1 }, { 0.2, 0.8 }, { 1, 1 } }), RotSpeed = NumberRange.new(-12, 12),
			Color = ColorSequence.new(Color3.fromRGB(246, 246, 244)), Acceleration = Vector3.new(0.6, 1.5, 0.3),
		})
		e.Rate = 1.5
		e.Enabled = not self.paused
		st.steam = e
	end
	self.state[m] = st
	return st
end

function YardLife:step(dt: number)
	if self.paused then return end
	self.t += dt
	-- forget machines that have been rebuilt or taken away
	self.prune = (self.prune or 0) + dt
	if self.prune > 5 then
		self.prune = 0
		for m in pairs(self.state) do
			if not m.Parent then self.state[m] = nil end
		end
	end
	local cam = workspace.CurrentCamera.CFrame.Position
	local now = os.clock()
	for plot, y in pairs(self.plot2.yards) do
		local base = plot:GetAttribute("BaseCFrame") :: CFrame?
		-- steam only where it can be seen, and never while that yard is being edited
		local live = base ~= nil and not y.editing and (base.Position - cam).Magnitude <= STEAM_REACH
		for _, m in pairs(y.machines) do
			local st = self.state[m]
			if st and st.steam and st.steam.Enabled ~= live then st.steam.Enabled = live end
		end
		if y.editing then continue end
		if not base or (base.Position - cam).Magnitude > REACH then continue end
		for id, m in pairs(y.machines) do
			if not m.Parent then continue end
			local st = self:stateFor(id, m)
			if not st then continue end
			local model = st.model
			if st.fan then
				st.angle += dt * FAN_SPEED * (id == "compressor" and 2.5 or 1)
				if st.spinZ then
					st.fan.CFrame = model:GetPivot() * st.fanRel * CFrame.Angles(0, 0, st.angle)
				else
					st.fan.CFrame = model:GetPivot() * CFrame.Angles(0, st.angle, 0) * st.fanRel
				end
			end
			if id == "compressor" then
				-- a steady shudder, and every few seconds a kick with a burst of air
				local kick = 0
				if now >= st.next then
					st.next = now + 4 + math.random() * 4
					st.kickAt = now
					local _, size = model:GetBoundingBox()
					PackFX.burst("dustPuff", model:GetPivot() * CFrame.new(size.X * 0.45, size.Y * 0.4, 0) * CFrame.Angles(0, 0, math.rad(-80)), 5, Color3.fromRGB(236, 236, 232), 0.8)
				end
				if st.kickAt and now - st.kickAt < 0.35 then
					kick = (1 - (now - st.kickAt) / 0.35) * 0.12
				end
				local n = self.t * 38
				local amp = 0.025 + kick
				local jig = CFrame.new(math.noise(n, 1.7) * amp, math.abs(math.noise(n, 4.2)) * amp, math.noise(n, 9.1) * amp)
				-- (2026-10-24, the owner: it was "literally floating into the air linearly") jiggled about its
				-- yard spot, which stays put: the container's own pivot followed the machine, so each frame's
				-- upward jig was added to the last
				local anchor = y.at and y.at[id]
				if anchor then
					st.spotRel = st.spotRel or anchor:ToObjectSpace(model:GetPivot())
					model:PivotTo(anchor * st.spotRel * jig)
				end
			elseif id == "cannon" then
				-- a thread of smoke out of the muzzle now and then
				if now >= st.next then
					st.next = now + 7 + math.random() * 6
					local info = Models.info(model.Name) :: any
					if info and info.muzzle then
						local mz = info.muzzle
						local scale = model:GetScale()
						local p = model:GetPivot() * (Models.toRoblox(mz[1], mz[2], mz[3]) * scale)
						PackFX.burst("dustPuff", CFrame.new(p), 3, Color3.fromRGB(196, 194, 190), 0.6)
					end
				end
			end
		end
	end
end

return YardLife
