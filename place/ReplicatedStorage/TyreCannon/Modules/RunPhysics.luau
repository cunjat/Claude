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
--                  rolls on, middling scrubs speed, hard kicks it back up.

local RunPhysics = {}

export type State = {
	x: number, y: number, z: number,
	speed: number, pitch: number, yaw: number,
	grounded: boolean, bank: number,
	-- the tuck (RunPhysics.tuck): held, for how long, cooling, and whether the key was down last step
	tucking: boolean?, tuckT: number?, tuckCd: number?, tuckPrev: boolean?,
}

export type Input = {
	aimYaw: number,       -- radians, where the wheel points
	aimPitch: number,     -- air only: + flare, - dive (about -0.6..0.6)
	tuck: boolean,
	thrust: number,       -- studs/s^2 along the path this step (nitro and quirks)
}

-- everything the stats, quirks and skills change, folded into plain multipliers by the caller
export type Ctx = {
	radius: number,
	turn: number, gravity: number, drag: number, friction: number,
	glide: number, keep: number, restitution: number,
	maxSpeed: number, fatigue: number,
}

export type Landing = { impact: number, soft: boolean, bounced: boolean, tp: number }

export type Result = { tookOff: boolean, landing: Landing? }

export type Terrain = { heightAt: (number) -> number, slopeAt: (number) -> number }

-- The tuck is a crouch with a timing window: a press starts it, it works for TuckWindow seconds, then
-- the legs cramp and it's dead for TuckCool. Letting go early costs only TuckEarly. A press just as
-- the road drops away (flat or rising here, a steep fall within PerfectLook studs) is a PERFECT tuck:
-- it fires `perfect` once so the caller can give the kick. Returns whether the tuck is on this step
-- and an event ("tuck", "perfect", "cramp") on the step it happened.
function RunPhysics.tuck(st: State, pressed: boolean, T: Terrain, F: any, dt: number): (boolean, string?)
	local edge = pressed and not st.tuckPrev
	st.tuckPrev = pressed
	st.tuckCd = math.max(0, (st.tuckCd or 0) - dt)
	local ev: string? = nil
	if edge and st.tuckCd <= 0 then
		st.tucking, st.tuckT = true, 0
		ev = "tuck"
		if st.grounded then
			local here = T.slopeAt(st.x)
			local ahead = T.slopeAt(st.x + math.cos(st.yaw) * F.PerfectLook)
			if here > F.PerfectFlat and ahead < F.PerfectDrop then ev = "perfect" end
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
	return st.tucking == true, ev
end

function RunPhysics.step(st: State, inp: Input, c: Ctx, T: Terrain, F: any, dt: number): Result
	local R = c.radius
	local res: Result = { tookOff = false, landing = nil }
	local s = st.speed
	local g = F.Gravity * c.gravity

	-- steering: heavier the faster you go, a nudge in the air; bends on the ground scrub speed
	local turn = F.TurnRate * c.turn / (1 + s / F.TurnFall * 0.5)
	if inp.tuck then turn *= F.TuckTurn end
	if not st.grounded then turn *= F.AirTurn end
	local dyaw = math.clamp(inp.aimYaw - st.yaw, -turn * dt, turn * dt)
	st.yaw += dyaw
	if st.grounded then s *= 1 - math.min(0.5, math.abs(dyaw) * F.TurnCost) end
	st.bank += ((dyaw / dt) * 0.45 - st.bank) * math.min(1, dt * 6)

	local py = st.y
	if st.grounded then
		local tp0 = math.atan(T.slopeAt(st.x))
		local fric = (F.GroundFriction0 + s * F.GroundFriction1) * c.friction * c.fatigue * (inp.tuck and F.TuckRoll or 1)
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
	local drag = (F.Drag0 + s * F.Drag1) * s * c.drag * (inp.tuck and F.TuckDrag or 1)
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
	local land: Landing = { impact = impact, soft = impact < F.SoftImpact, bounced = false, tp = tp }
	res.landing = land
	if land.soft then
		st.grounded = true
		st.pitch = tp
		st.speed = vt
		return res
	end
	local sev = math.clamp((impact - F.SoftImpact) / 260, 0, 1)
	vt *= (1 - sev * (1 - F.HardKeep)) * math.min(1.06, c.keep ^ 0.4)
	if impact > F.HardImpact then
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
