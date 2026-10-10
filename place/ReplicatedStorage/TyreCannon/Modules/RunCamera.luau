--!strict
-- TYRE CANNON :: RunCamera
-- The run's camera, as numbers only (no Roblox types) so tools/camera_test can fly it headless.
-- RunSim turns what it returns into a CFrame.
--
-- Chase: behind the tyre along its heading, as far back as its speed and its height above the road
-- ask (the higher you are the more it pulls back and widens), up over whatever the road does between
-- the camera and the tyre, looking ahead along the heading at the road itself, so a downhill tips the
-- view down onto the slope and a crest shows what's past it. Everything eases; nothing cuts.
-- First person: the tyre's own eyes, looking where it's going.

local RunCamera = {}

export type Terrain = { heightAt: (number) -> number }

export type State = {
	yaw: number, pitch: number,
	dist: number, dv: number,      -- distance behind (a spring, dv its velocity: landings thump it)
	eyeY: number, lookY: number,
	fov: number, roll: number,
	started: boolean,
}

export type In = {
	x: number, y: number, z: number,
	yaw: number, pitch: number, speed: number,
	grounded: boolean, alt: number, bank: number, boosting: boolean,
	first: boolean, radius: number,
}

export type Out = {
	ex: number, ey: number, ez: number,
	lx: number, ly: number, lz: number,
	fov: number, roll: number,
}

function RunCamera.new(): State
	return { yaw = 0, pitch = 0, dist = 26, dv = 0, eyeY = 0, lookY = 0, fov = 66, roll = 0, started = false }
end

-- a landing, a gate: the camera is shoved this much and springs back
function RunCamera.thump(cs: State, amount: number)
	cs.dv -= amount
end

local function ease(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function angleDiff(a: number, b: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return d
end

function RunCamera.step(cs: State, i: In, T: Terrain, C: any, dt: number): Out
	local speedT = math.clamp(i.speed / C.SpeedRef, 0, 1.3)
	if not cs.started then
		cs.started = true
		cs.yaw, cs.pitch = i.yaw, i.pitch
		cs.dist = C.Dist0
		cs.eyeY = i.y + C.Height0
		cs.lookY = i.y
		cs.fov = C.Fov0
	end

	-- where it's heading: slower to follow in the air so a flight doesn't whip the view
	cs.yaw += angleDiff(cs.yaw, i.yaw) * ease(i.grounded and C.YawFollow or C.YawFollowAir, dt)
	cs.pitch += (i.pitch * C.PitchShare - cs.pitch) * ease(C.PitchFollow, dt)
	local cy, sy = math.cos(cs.yaw), math.sin(cs.yaw)

	-- how far back: speed and height both pull it out, and a spring so a change breathes
	local want = C.Dist0 + C.DistSpeed * speedT + math.min(i.alt * C.DistAlt, C.DistAltMax) + (i.grounded and 0 or C.DistAir)
	local acc = (want - cs.dist) * C.DistStiff - cs.dv * C.DistDamp
	cs.dv += acc * dt
	cs.dist += cs.dv * dt

	local fov = math.min(C.FovMax, C.Fov0 + C.FovSpeed * speedT + math.min(i.alt * C.FovAlt, C.FovAltMax) + (i.boosting and C.FovBoost or 0))
	cs.fov += (fov - cs.fov) * ease(C.FovFollow, dt)
	cs.roll += (-i.bank * C.Roll - cs.roll) * ease(C.RollFollow, dt)

	if i.first then
		local fp = math.cos(cs.pitch)
		local ex = i.x + cy * i.radius * 0.25
		local ez = i.z + sy * i.radius * 0.25
		local ey = i.y + i.radius * 0.5
		return {
			ex = ex, ey = ey, ez = ez,
			lx = ex + cy * fp * 100, ly = ey + math.sin(cs.pitch) * 100, lz = ez + sy * fp * 100,
			fov = cs.fov + C.FirstFov, roll = cs.roll,
		}
	end

	-- behind along the heading, and a little to the right of it (the angled view)
	local ex = i.x - cy * cs.dist - sy * C.Side
	local ez = i.z - sy * cs.dist + cy * C.Side
	-- the road between the camera and the tyre: the eye has to be high enough that the line from it
	-- to the tyre clears every crest on the way (a tyre dropping away over a crest needs the camera
	-- up over it, not behind it)
	local wantEye = i.y + C.Height0 + cs.dist * C.HeightPer
	for k = 1, 8 do
		local f = k / 9
		local sx = ex + (i.x - ex) * f
		-- (road right at the tyre's feet, a lip it's just come off, is under it, not in front of it)
		if i.x - sx > C.LosIgnore then
			local h = T.heightAt(sx) + C.Clear
			-- eye height at which the sight line to the tyre passes at least h at fraction f
			local need = (h - i.y * f) / (1 - f)
			if need > wantEye then wantEye = math.min(need, i.y + C.RiseMax) end
		end
	end
	-- up quickly (never let the road in front of the lens), down slowly
	local k = wantEye > cs.eyeY and C.EyeUp or C.EyeDown
	cs.eyeY += (wantEye - cs.eyeY) * ease(k, dt)
	-- the road itself under the camera is a hard floor
	cs.eyeY = math.max(cs.eyeY, T.heightAt(ex) + C.Floor)

	-- what it looks at: ahead along the heading, blending the tyre's height with the road's there
	local ahead = C.Look0 + C.LookSpeed * speedT
	local lx = i.x + cy * ahead
	local lz = i.z + sy * ahead
	local roadAhead = T.heightAt(lx) + i.radius
	local blend = i.grounded and C.LookRoad or C.LookRoadAir
	local pathY = i.y + math.sin(i.pitch) * ahead * C.LookPath
	local wantLook = (pathY + (roadAhead - pathY) * blend) + cs.dist * C.LookLift
	cs.lookY += (wantLook - cs.lookY) * ease(C.LookFollow, dt)

	return { ex = ex, ey = cs.eyeY, ez = ez, lx = lx, ly = cs.lookY, lz = lz, fov = cs.fov, roll = cs.roll }
end

return RunCamera
