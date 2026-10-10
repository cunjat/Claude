--!strict
-- TYRE CANNON :: RunPhysics
-- The rolling run, with no Roblox in it so it can be tested headless (tools/run_test.luau).
--
-- The tyre is a point with a heading (yaw) and a path angle (pitch) and one speed.
--   ON THE GROUND  it follows the terrain. Gravity along the slope is the engine: downhill adds
--                  speed, uphill takes it away, friction always takes some. If the road falls away
--                  faster than a free fall would (a crest, a kicker's lip) it leaves the ground.
--   IN THE AIR     a plain ballistic arc, plus drag. Nose up (flare) floats longer for more drag,
--                  nose down (dive) falls faster.
--   LANDING        the velocity splits along the slope and into it. What's along it is kept, so a
--                  landing that matches the slope loses nothing; what's into it is the impact: soft
--                  rolls on, middling scrubs speed, hard kicks it back up. Braced (tucked as it touches
--                  down, or a skill's slam) it takes far more before it scrubs or kicks: a landing you
--                  time is never a crash.

local RunPhysics = {}

export type State = {
	x: number, y: number, z: number,
	speed: number, pitch: number, yaw: number,
	grounded: boolean, bank: number,
	-- the tuck (RunPhysics.tuck): held, for how long, cooling, and whether the key was down last step
	tucking: boolean?, tuckT: number?, tuckCd: number?, tuckPrev: boolean?,
	tuckAmt: number?, tuckBuf: number?, perfectT: number?, perfectUsed: boolean?,
}

export type Input = {
	aimYaw: number,       -- radians, where the wheel points
	aimPitch: number,     -- air only: + flare, - dive (about -0.6..0.6)
	tuck: boolean,
	tuckAmt: number?,     -- how far into the tuck (eased); the key alone if missing
	thrust: number,       -- studs/s^2 along the path this step (nitro and quirks)
	brace: boolean?,      -- braced for the landing (tucked as it touches down)
	slam: boolean?,       -- a skill's slam (Meteor): it comes down keeping all its speed
}

-- everything the stats, quirks and skills change, folded into plain multipliers by the caller
export type Ctx = {
	radius: number,
	turn: number, gravity: number, drag: number, friction: number,
	glide: number, keep: number, restitution: number,
	maxSpeed: number, fatigue: number,
}

export type Landing = { impact: number, soft: boolean, bounced: boolean, tp: number, braced: boolean }

export type Result = { tookOff: boolean, landing: Landing? }

export type Terrain = { heightAt: (number) -> number, slopeAt: (number) -> number }

-- The tuck is a crouch with a timing window: a press starts it, it works for TuckWindow seconds, then
-- the legs cramp and it's dead for TuckCool. Letting go early costs only TuckEarly. It eases in and
-- out (st.tuckAmt, 0..1) rather than snapping, and a press made a moment before the tuck is ready
-- again is kept and starts it as soon as it is (TuckBuffer).
-- A press just as the road drops away is a PERFECT tuck (RunPhysics.perfectAhead): it fires `perfect`
-- once so the caller can give the kick. The same test drives the HUD's cue, and it stays good for
-- PerfectGrace seconds after it stops being true, so a press on the cue never misses on a frame.
-- Returns whether the tuck is on this step and an event ("tuck", "perfect", "cramp").

-- whether the road ahead drops away enough for a PERFECT tuck: flat or rising here, and a steep fall
-- coming within PerfectTime seconds at this speed (several looks, so a short dip between them or a
-- fast tyre never slips past)
function RunPhysics.perfectAhead(st: State, T: Terrain, F: any, scale: number?): boolean
	if not st.grounded then return false end
	if T.slopeAt(st.x) <= F.PerfectFlat then return false end
	local reach = math.max(F.PerfectLook * 0.5, st.speed * (F.PerfectTime or 0.9)) * (scale or 1)
	local c = math.cos(st.yaw)
	for i = 1, 6 do
		if T.slopeAt(st.x + c * reach * i / 6) < F.PerfectDrop then return true end
	end
	return false
end

function RunPhysics.tuck(st: State, pressed: boolean, T: Terrain, F: any, dt: number): (boolean, string?)
	local edge = pressed and not st.tuckPrev
	st.tuckPrev = pressed
	st.tuckCd = math.max(0, (st.tuckCd or 0) - dt)
	-- the perfect test, with its grace. One PERFECT a drop: once taken, the chance stays shut until
	-- the road has stopped dropping away (and the grace has run out)
	if RunPhysics.perfectAhead(st, T, F) then
		if not st.perfectUsed then st.perfectT = F.PerfectGrace or 0.18 end
	else
		st.perfectT = math.max(0, (st.perfectT or 0) - dt)
		if st.perfectT <= 0 then st.perfectUsed = false end
	end
	-- a press during the cooldown is held for a moment
	if edge then st.tuckBuf = F.TuckBuffer or 0.2 end
	st.tuckBuf = math.max(0, (st.tuckBuf or 0) - dt)
	local ev: string? = nil
	if not st.tucking and pressed and (st.tuckBuf or 0) > 0 and st.tuckCd <= 0 then
		st.tucking, st.tuckT, st.tuckBuf = true, 0, 0
		ev = "tuck"
		if (st.perfectT or 0) > 0 then
			ev = "perfect"
			st.perfectT = 0
			st.perfectUsed = true
		end
	end
	if st.tucking then
		if not pressed then
			st.tucking = false
			st.tuckCd = F.TuckEarly
		else
			st.tuckT = (st.tuckT or 0) + dt
			if st.tuckT >= F.TuckWindow then
				st.tucking = false
				st.tuckCd = F.TuckCool
				ev = ev or "cramp"
			end
		end
	end
	-- eased in and out: the drag, roll and turn it changes follow this, not the key
	local want = if st.tucking then 1 else 0
	local rate = if want > (st.tuckAmt or 0) then 9 else 6
	st.tuckAmt = (st.tuckAmt or 0) + (want - (st.tuckAmt or 0)) * math.min(1, dt * rate)
	return st.tucking == true, ev
end

function RunPhysics.step(st: State, inp: Input, c: Ctx, T: Terrain, F: any, dt: number): Result
	local R = c.radius
	local res: Result = { tookOff = false, landing = nil }
	local s = st.speed
	local g = F.Gravity * c.gravity

	-- steering: heavier the faster you go, a nudge in the air; bends on the ground scrub speed
	local turn = F.TurnRate * c.turn / (1 + s / F.TurnFall * 0.5)
	local tk = inp.tuckAmt or (if inp.tuck then 1 else 0)
	turn *= 1 + (F.TuckTurn - 1) * tk
	if not st.grounded then turn *= F.AirTurn end
	local dyaw = math.clamp(inp.aimYaw - st.yaw, -turn * dt, turn * dt)
	st.yaw += dyaw
	if st.grounded then s *= 1 - math.min(0.5, math.abs(dyaw) * F.TurnCost) end
	st.bank += ((dyaw / dt) * 0.45 - st.bank) * math.min(1, dt * 6)

	local py = st.y
	if st.grounded then
		local tp0 = math.atan(T.slopeAt(st.x))
		local fric = (F.GroundFriction0 + s * F.GroundFriction1) * c.friction * c.fatigue * (1 + (F.TuckRoll - 1) * tk)
		local sn = math.sin(tp0)
		-- the arcade rule the hills run on: down a slope gravity pulls harder than it holds back up one
		local pull = g * sn * (sn < 0 and F.HillDown or F.HillUp)
		s = math.clamp(s + (-pull - fric + inp.thrust) * dt, 0, c.maxSpeed)
		local hs = s * math.cos(tp0)
		st.x += math.cos(st.yaw) * hs * dt
		st.z += math.sin(st.yaw) * hs * dt
		local gNew = T.heightAt(st.x) + R
		local vy0 = s * math.sin(tp0)
		local yBall = py + vy0 * dt - 0.5 * g * dt * dt
		if s > F.TakeoffMin and gNew < yBall - 0.35 then
			-- the ground fell away faster than the tyre drops: off the lip
			st.grounded = false
			st.pitch = tp0
			st.y = yBall
			res.tookOff = true
		else
			st.y = gNew
			st.pitch = math.atan(T.slopeAt(st.x))
		end
		st.speed = s
		return res
	end

	local flare = math.clamp(inp.aimPitch / 0.5, 0, 1)
	local dive = math.clamp(-inp.aimPitch / 0.5, 0, 1)
	local hs, vy = math.cos(st.pitch) * s, math.sin(st.pitch) * s
	local drag = (F.Drag0 + s * F.Drag1) * s * c.drag * (1 + (F.TuckDrag - 1) * tk)
	drag *= (1 + F.FlareDrag * flare) * c.fatigue
	local s2 = math.clamp(s + (inp.thrust - drag) * dt, 0, c.maxSpeed)
	local k = s2 / math.max(s, 1)
	hs *= k
	vy *= k
	vy -= g * (1 - F.FlareLift * flare + F.DiveGrav * dive) * dt / math.sqrt(c.glide)
	st.x += math.cos(st.yaw) * hs * dt
	st.z += math.sin(st.yaw) * hs * dt
	st.y += vy * dt
	st.speed = math.sqrt(hs * hs + vy * vy)
	st.pitch = math.atan2(vy, math.max(hs, 1e-3))

	local gy = T.heightAt(st.x) + R
	if st.y > gy then return res end

	-- landing
	st.y = gy
	local tp = math.atan(T.slopeAt(st.x))
	local vt = math.max(hs * math.cos(tp) + vy * math.sin(tp), 0)
	local vn = -hs * math.sin(tp) + vy * math.cos(tp)
	local impact = math.max(0, -vn)
	local braced = inp.brace == true
	local softAt = if inp.slam then math.huge else F.SoftImpact * (if braced then (F.BraceSoft or 1) else 1)
	local hardAt = F.HardImpact * (if braced then (F.BraceHard or 1) else 1)
	local land: Landing = { impact = impact, soft = impact < softAt, bounced = false, tp = tp, braced = braced }
	res.landing = land
	if land.soft then
		st.grounded = true
		st.pitch = tp
		st.speed = vt
		return res
	end
	local sev = math.clamp((impact - softAt) / 260, 0, 1)
	vt *= (1 - sev * (1 - F.HardKeep)) * math.min(1.06, c.keep ^ 0.4)
	if impact > hardAt then
		local up = impact * c.restitution * c.glide ^ 0.3
		local nhs = vt * math.cos(tp) - up * math.sin(tp)
		local nvy = vt * math.sin(tp) + up * math.cos(tp)
		st.speed = math.sqrt(nhs * nhs + nvy * nvy)
		st.pitch = math.atan2(nvy, math.max(nhs, 1))
		land.bounced = true
	else
		st.grounded = true
		st.pitch = tp
		st.speed = vt
	end
	return res
end

return RunPhysics
