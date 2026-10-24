--!strict
-- TYRE CANNON :: LobbyPark
-- The lawn as a city park (owner, 2026-10-17: "make the grass area kind of like a park ... ponds ...
-- people walking around ... some have a phone out recording the launch ... fish jump out of the water
-- ... kids playing around"). After Delhi's Lodhi Garden. Gap k is the lawn between lines of fire k and
-- k+1 (centred at (k + 0.5) * 45 degrees):
--   0 the big pond under an arched footbridge: koi (some jump), ducks, benches
--   1, 5  the banyans: picnicking families, kids flying kites
--   2 the playground: swings, slide, see-saw, merry-go-round, a parent on a bench
--   3 the fountain: marigold beds, benches, a chai stall
--   4 the lily pond: koi, ducks, benches
--   6 gully cricket          7 a hedged flower garden, kids playing tag
-- A sandstone footpath rings the lawn with park lamps (lit at night) and bins; people stroll it both
-- ways. Spectators stand at the lawn's edge beside every line of fire, phones out, and when that
-- yard fires (Remotes.V2.Launched / AutoFire) they raise them and follow the shot into the sky.
-- The models are the Blender park pack (art/blender/park.py, people.py) under Assets/Park.
-- Everything moving goes through one BulkMoveTo from step(t); far groups update less often.
--   LobbyPark.new(folder, level) -> park (yields) ; park:clear(p, margin) ; park:step(t) ; park:destroy()

-- (2026-10-17, the owner: "make all of it solid ... the walking animations are not natural ... various
-- casual hairstyles ... speech bubbles of npc conversation ... a few conversations about an actual
-- player in the game") Props are solid (trees by a trunk collider, the banyan's chabutra a platform
-- you can stand on; water, grass and flowers stay soft), people block you too, the walk is a proper
-- cycle (stride matched to speed, hips riding over the planted foot, counter-swing, twist and lean),
-- hair is a weighted mix of casual styles, and the park talks: groups hold conversations in bubble
-- chat (some about the real players in the server: their best, their prestige, the server record),
-- greet you by name when you walk up, answer when you chat to them (E), and the spectators call out
-- whoever just launched.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Models = require(script.Parent:WaitForChild("Models"))
local Physical = require(script.Parent:WaitForChild("Physical"))

local LobbyPark = {}
LobbyPark.__index = LobbyPark

-- (2026-10-22, the owner: "we'll get rid of the npcs entirely, we need something else to make it feel
-- more lively, npcs probably isnt the best method") No people: every set piece that had them runs
-- without (each already did when Park/Person was missing), and the cricket, which is only its players,
-- is left out. The park's life is HubLife's now: swaying trees, birds, butterflies, kites.
local PEOPLE = false

local CENTRE = Vector3.new(-6000, 0, 6000)
-- (2026-10-18, the owner: the lobby ~40% smaller. The yards end 280 studs out and the canal now sits
-- at 384, so the park lives in the band between. Its layout below is still written in the old design
-- radii (the lawn 410-605) and gp() maps them into the band: R for distance out, X for along the ring,
-- so the pieces keep their places relative to each other.)
-- (2026-10-21, the owner: a stage-5 yard ran over the park's footpath. Yards reach 316 studs out at stage 5
-- (Game.YardGrowth: x1 104, z 60, the fence and palisade past that), so every ring is pushed out to clear it.)
local REMAP = { { 404, 328 }, { 452, 338 }, { 470, 344 }, { 500, 356 }, { 530, 371 }, { 560, 383 }, { 605, 398 } }
local function R(r: number): number
	for i = 1, #REMAP - 1 do
		local a, b = REMAP[i], REMAP[i + 1]
		if r <= b[1] or i == #REMAP - 1 then
			if r < a[1] and i == 1 then return a[2] + (r - a[1]) * (b[2] - a[2]) / (b[1] - a[1]) end
			return a[2] + (r - a[1]) * (b[2] - a[2]) / (b[1] - a[1])
		end
	end
	return r
end
-- the world radius back to the design one
local function Rinv(w: number): number
	for i = 1, #REMAP - 1 do
		local a, b = REMAP[i], REMAP[i + 1]
		if w <= b[2] or i == #REMAP - 1 then return a[1] + (w - a[2]) * (b[1] - a[1]) / (b[2] - a[2]) end
	end
	return w
end
local XS = 0.65
local function X(x: number): number return x * XS end
local PATH_R = R(452) -- the footpath ring, in world studs
local PATH_W = 7
local CANAL_IN = 0.66 * 640 - 24     -- the lawn's outer edge: the canal's inner bank (LobbyVista CANAL_R - 24)
local WATER_Y = 0.7                      -- the ponds' water (park.py pond water_z)
local SANDSTONE = Color3.fromRGB(214, 188, 146)
local KERB = Color3.fromRGB(178, 152, 114)
local WATER = Color3.fromRGB(62, 140, 158)
local SKINS = { Color3.fromRGB(201, 143, 85), Color3.fromRGB(141, 90, 59), Color3.fromRGB(176, 118, 74), Color3.fromRGB(224, 172, 120), Color3.fromRGB(110, 70, 46) }
local SHIRTS = { Color3.fromRGB(216, 64, 46), Color3.fromRGB(42, 111, 214), Color3.fromRGB(242, 194, 48), Color3.fromRGB(244, 241, 232),
	Color3.fromRGB(63, 174, 106), Color3.fromRGB(217, 79, 154), Color3.fromRGB(255, 138, 30), Color3.fromRGB(31, 181, 176), Color3.fromRGB(120, 86, 200) }
local PANTS = { Color3.fromRGB(52, 64, 90), Color3.fromRGB(40, 44, 52), Color3.fromRGB(107, 74, 42), Color3.fromRGB(150, 140, 120), Color3.fromRGB(31, 42, 68) }
local HAIRS = { Color3.fromRGB(26, 22, 20), Color3.fromRGB(42, 34, 28), Color3.fromRGB(70, 50, 36), Color3.fromRGB(150, 150, 150) }
local BRIGHT = { Color3.fromRGB(255, 138, 30), Color3.fromRGB(216, 64, 46), Color3.fromRGB(42, 111, 214), Color3.fromRGB(242, 194, 48), Color3.fromRGB(217, 79, 154) }
-- hairstyles (art/blender/hair.py) and how often each turns up; a style missing from the template is
-- skipped. Head coverings are kept rare.
local ADULT_HAIR = { HairCrop = 12, HairSidePart = 12, HairSpiky = 6, HairCurly = 9, HairAfro = 6, HairPonytail = 10, HairBob = 9,
	HairLongStraight = 8, HairQuiff = 8, HairBuzz = 6, HairBun = 6, Cap = 6, Beanie = 4, Turban = 2, HairShort = 3 }
local KID_HAIR = { HairCrop = 10, HairSpiky = 8, HairCurly = 8, HairPonytail = 8, HairPigtails = 8, HairBob = 6, HairSidePart = 6, Cap = 5, HairShort = 3 }
local ALL_HAIR = { HairLong = true }
for name in pairs(ADULT_HAIR) do ALL_HAIR[name] = true end
for name in pairs(KID_HAIR) do ALL_HAIR[name] = true end
local HAT = { Turban = true, Cap = true, Beanie = true }
local BODY_SOLID = { Torso = true, Head = true, LegL = true, LegR = true }

-- park chatter: lists of { speaker (1-3), line }. In a line {p} is another player in the server, {best}
-- their best, {prestige} their prestige; {top} and {topbest} the server's best; {me} and {mybest} you.
-- A conversation whose tokens can't be filled is skipped.
local TALK = {
	{ { 1, "Chai's extra sweet today." }, { 2, "Just how I like it." } },
	{ { 1, "Did you see that tyre fly?" }, { 2, "Right over the canal!" }, { 3, "I want one of those cannons." } },
	{ { 1, "The mustard's out on the fields." }, { 2, "Smells like home." } },
	{ { 1, "My cousin says the Dunes start at 12 km." }, { 2, "Who rolls a tyre twelve kilometres?" }, { 1, "Everyone here, apparently." } },
	{ { 1, "Someone pulled a Glazed Donut tyre." }, { 2, "A doughnut? As a tyre?" }, { 1, "The secret ones are weird." } },
	{ { 1, "Monsoon's coming, they say." }, { 2, "Double coins when it rains!" } },
	{ { 1, "Gol gappe after this?" }, { 2, "Only if you're paying." } },
	{ { 1, "The ducks have names, you know." }, { 2, "Go on then." }, { 1, "That one's Pappu." } },
	{ { 1, "Tuck before the speed bumps." }, { 2, "Or they eat a third of your speed." } },
	{ { 1, "Shift in the gold and it really goes." }, { 2, "I always shift too early." } },
	{ { 1, "Golden Hour soon." }, { 2, "Every key counts twice!" } },
	{ { 1, "I saw a koi jump earlier." }, { 2, "In the big pond?" }, { 1, "Right by the bridge." } },
}
local TALK_PLAYER = {
	{ { 1, "Is that {p} over there?" }, { 2, "Their best is {best}!" }, { 1, "No way." } },
	{ { 1, "{top} has the best here today." }, { 2, "{topbest}. Someone should beat that." } },
	{ { 1, "{p} is prestige {prestige}." }, { 2, "Respect." } },
	{ { 1, "{p} keeps launching." }, { 2, "{best} so far!" }, { 3, "I'm going to watch their next one." } },
	{ { 1, "Have you seen {p}'s yard?" }, { 2, "Not yet. Is it good?" }, { 1, "Go and look!" } },
}
local GREET = {
	{ { 1, "Oh hi, {me}!" }, { 2, "Hey {me}, nice yard." } },
	{ { 1, "It's {me}!" }, { 2, "{mybest}! Not bad, {me}." } },
	{ { 1, "Hello {me}! Lovely day for a launch." } },
}
local REPLIES = {
	"Hi {me}! Have you seen the koi jump?",
	"Tuck over the speed bumps, {me}. Trust me.",
	"Shift in the gold, {me}. That's the trick.",
	"The Highway's 4 km out. Have you made it yet?",
	"{mybest} is your best? Go beat it!",
	"Try the chai over by the fountain.",
	"Nitro on SPACE, {me}. Save it for the end.",
	"Keys make the rare tyres twice as likely.",
}
local CHEERS = { "{p} is launching!", "Here goes {p}!", "Look at {p}'s go!", "{p} sent it!", "Go on, {p}!" }
local WHOA = { "Whoa!", "Look at it go!", "So high!", "Over the canal!", "That's a big one!" }
-- when you come back from a run with a new best, the park noticed
local NEWBEST = {
	{ { 1, "{me}! New best: {mybest}!" }, { 2, "We all watched it!" } },
	{ { 1, "Was that you, {me}? {mybest}!" }, { 2, "Incredible." }, { 3, "Teach me!" } },
	{ { 1, "{mybest}! Nice one, {me}." } },
}
-- level -> how many strollers and spectators, and whether the busier set pieces run
local COUNTS = {
	{ walkers = 5, specs = 1, busy = false },
	{ walkers = 18, specs = 1, busy = true },
	{ walkers = 26, specs = 2, busy = true },
}
-- where the figure's limbs turn (art/blender/people.py JOINTS, Blender xyz)
local JOINT = {
	-- (2026-10-18: R6 proportions, art/blender/people_hd.py: shoulders at the torso's top corners, hips under it)
	ArmL = Vector3.new(-1.5, 0, 3.75), ArmR = Vector3.new(1.5, 0, 3.75),
	LegL = Vector3.new(-0.5, 0, 2.0), LegR = Vector3.new(0.5, 0, 2.0), Head = Vector3.new(0, 0, 4.0),
}
local HIP, ARM_LEN = 2.0, 1.75

local function toModel(v: Vector3, s: number): Vector3
	return Vector3.new(v.X, v.Z, -v.Y) * s
end

local function newPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

-- gap k's frame: a point r out from the plaza, x along the ring; `face` "out" (the default), "in",
-- "side" (along the ring) or a world direction
local function gp(k: number, r: number, x: number?, y: number?): (Vector3, Vector3, Vector3)
	local a = (k + 0.5) * math.pi / 4
	local out = Vector3.new(math.cos(a), 0, math.sin(a))
	local side = Vector3.new(-out.Z, 0, out.X)
	return CENTRE + out * R(r) + side * X(x or 0) + Vector3.new(0, y or 0, 0), out, side
end
local function gcf(k: number, r: number, x: number?, face: any?, y: number?): CFrame
	local p, out, side = gp(k, r, x, y)
	local dir = if face == "in" then -out elseif face == "side" then side elseif typeof(face) == "Vector3" then face else out
	return CFrame.lookAt(p, p + dir)
end
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

--==============================================================
-- people
--==============================================================
local function pick<T>(rng: Random, t: { T }): T
	return t[rng:NextInteger(1, #t)]
end

local function weighted(rng: Random, weights: { [string]: number }, have: { [string]: boolean }): string?
	local total = 0
	for name, w in pairs(weights) do if have[name] then total += w end end
	if total <= 0 then return nil end
	local x = rng:NextNumber(0, total)
	for name, w in pairs(weights) do
		if have[name] then
			x -= w
			if x <= 0 then return name end
		end
	end
	return nil
end

-- a figure with a look of its own: opts { scale, hair, phone, shirt }
function LobbyPark:person(opts: any): any
	if not PEOPLE then return nil end
	local tpl = Models.get("Park/Person")
	if not tpl then return nil end
	local rng = self.rng
	local s = opts.scale or 1
	local m = Models.place(tpl, self.peopleFolder, CFrame.new(), s)
	local have = {}
	for _, p in ipairs(m:GetChildren()) do have[p.Name] = true end
	local hair = opts.hair or weighted(rng, if s < 0.9 then KID_HAIR else ADULT_HAIR, have) or "HairShort"
	local skin = pick(rng, SKINS)
	local shirt = opts.shirt or pick(rng, SHIRTS)
	local pants = pick(rng, PANTS)
	local hairCol = if HAT[hair] then pick(rng, BRIGHT) else pick(rng, HAIRS)
	local parts, rest = {}, {}
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") then
			local keep = true
			if ALL_HAIR[p.Name] and p.Name ~= hair then keep = false end
			if p.Name == "Phone" and not opts.phone then keep = false end
			if p.Name == "RefHead" then keep = false end
			if not keep then
				p:Destroy()
			else
				p.CastShadow = false
				-- standing people block you (the small bits, face, hair, shoes, phone, don't need to); people
				-- on the move never do, since an anchored part teleported into you shoves or flings you
				p.CanCollide = not opts.moving and BODY_SOLID[p.Name] == true
				local tint = if p.Name == "Head" or p.Name == "ArmL" or p.Name == "ArmR" then skin
					elseif p.Name == "Torso" or p.Name == "SleeveL" or p.Name == "SleeveR" then shirt
					elseif p.Name == "LegL" or p.Name == "LegR" then pants
					elseif p.Name == hair then hairCol
					else nil
				if tint then
					-- (2026-10-18) the R6 parts are textured: their near-white detail is tinted through the
					-- SurfaceAppearance; untextured parts (the hairstyles) take the colour straight
					local sa = p:FindFirstChildOfClass("SurfaceAppearance")
					if sa then
						sa.AlphaMode = Enum.AlphaMode.TintMask
						sa.Color = tint
					else
						p.Color = tint
						p.Material = Enum.Material.SmoothPlastic
					end
				end
				parts[p.Name] = p
				rest[p.Name] = p.CFrame
			end
		end
	end
	local j = {}
	for name, v in pairs(JOINT) do j[name] = toModel(v, s) end
	return { model = m, s = s, parts = parts, rest = rest, j = j, hair = hair }
end

-- a held thing (a bat) rides the right hand
function LobbyPark:hold(person: any, name: string): BasePart?
	local tpl = Models.get("Park/" .. name)
	if not tpl then return nil end
	local m = Models.place(tpl, self.peopleFolder, CFrame.new(), person.s)
	local part = m:FindFirstChildWhichIsA("BasePart")
	if part then
		part.CastShadow = false
		person.held = part
		person.heldRest = part.CFrame
	end
	return part
end

-- a pose: { armL, armR (forward swing, radians), armLYaw, armRYaw (inward), legL, legR, headPitch,
-- headYaw, bob, lean (forward), twist, roll (the upper body, about the hips), phone = CFrame (relative
-- to the body), hand = CFrame (the held thing, in the hand) }
local I = CFrame.identity
-- one part of a figure, turned by `rot` about its joint `j`
local function put(p: any, parts: { BasePart }, cfs: { CFrame }, from: CFrame, name: string, j: Vector3, rot: CFrame)
	local part = p.parts[name]
	if not part then return end
	table.insert(parts, part)
	table.insert(cfs, from * CFrame.new(j) * rot * CFrame.new(-j) * p.rest[name])
end
local function pose(p: any, root: CFrame, a: any, parts: { BasePart }, cfs: { CFrame })
	local base = root * CFrame.new(0, a.bob or 0, 0)
	local hip = HIP * p.s
	local upper = if a.lean or a.twist or a.roll
		then base * CFrame.new(0, hip, 0) * CFrame.Angles(-(a.lean or 0), a.twist or 0, a.roll or 0) * CFrame.new(0, -hip, 0)
		else base
	put(p, parts, cfs, upper, "Torso", Vector3.zero, I)
	local head = CFrame.Angles(0, a.headYaw or 0, 0) * CFrame.Angles(a.headPitch or 0, 0, 0)
	put(p, parts, cfs, upper, "Head", p.j.Head, head)
	put(p, parts, cfs, upper, "Face", p.j.Head, head)
	put(p, parts, cfs, upper, p.hair, p.j.Head, head)
	local armL = CFrame.Angles(0, -(a.armLYaw or 0), 0) * CFrame.Angles(a.armL or 0, 0, 0)
	local armR = CFrame.Angles(0, a.armRYaw or 0, 0) * CFrame.Angles(a.armR or 0, 0, 0)
	put(p, parts, cfs, upper, "ArmL", p.j.ArmL, armL)
	put(p, parts, cfs, upper, "ArmR", p.j.ArmR, armR)
	put(p, parts, cfs, upper, "SleeveL", p.j.ArmL, armL)
	put(p, parts, cfs, upper, "SleeveR", p.j.ArmR, armR)
	local legL, legR = CFrame.Angles(a.legL or 0, 0, 0), CFrame.Angles(a.legR or 0, 0, 0)
	put(p, parts, cfs, base, "LegL", p.j.LegL, legL)
	put(p, parts, cfs, base, "ShoeL", p.j.LegL, legL)
	put(p, parts, cfs, base, "LegR", p.j.LegR, legR)
	put(p, parts, cfs, base, "ShoeR", p.j.LegR, legR)
	if p.parts.Phone then
		table.insert(parts, p.parts.Phone)
		table.insert(cfs, upper * (a.phone or CFrame.new(0.4 * p.s, 2.9 * p.s, -0.9 * p.s) * CFrame.Angles(-0.6, 0, 0)) * p.rest.Phone.Rotation)
	end
	if p.held then
		local hand = upper * CFrame.new(p.j.ArmR) * armR * CFrame.new(0, -ARM_LEN * p.s, -0.2 * p.s)
		table.insert(parts, p.held)
		table.insert(cfs, hand * (a.hand or I) * p.heldRest)
	end
end

-- a one-part model (a fish, a duck, a kite) and its rest frame: Models' pivot turns imported parts
-- half round, so anything aimed with lookAt is multiplied by this to face the right way
function LobbyPark:single(name: string, scale: number): (BasePart?, CFrame)
	local tpl = Models.get("Park/" .. name)
	if not tpl then return nil, I end
	local m = Models.place(tpl, self.peopleFolder, CFrame.new(), scale)
	local part = m:FindFirstChildWhichIsA("BasePart")
	if not part then return nil, I end
	part.CastShadow = false
	return part, part.CFrame
end

-- a walk (or run) cycle at phase ph: the legs swing amp either side, the hips ride over the planted
-- foot (highest as the legs pass, lowest at full stride, so the feet stay on the ground), the arms
-- counter-swing a little wide of the body, the shoulders twist against the hips, the body rolls onto
-- the standing leg and leans into the stride, and the head steadies against the twist
local LEG = 1.9
local function walkPose(ph: number, amp: number, s: number, lean: number?): any
	local sw = math.sin(ph)
	local leg = sw * amp
	return {
		legL = leg, legR = -leg, armL = -leg * 0.85, armR = leg * 0.85, armLYaw = -0.07, armRYaw = -0.07,
		bob = (math.cos(leg) - 1) * LEG * s, twist = leg * 0.22, roll = math.cos(ph) * 0.03, lean = lean or 0.05,
		headYaw = -leg * 0.15,
	}
end
-- how fast a cycle turns for a ground speed, so the feet don't skate (a cycle is two steps)
local function strideRate(speed: number, amp: number, s: number): number
	return speed * 2 * math.pi / (4 * LEG * s * math.sin(amp))
end
local SIT = { legL = 1.5, legR = 1.5, armL = 0.35, armR = 0.35 }
-- the root for someone sitting with their hips at height `seat`
local function sitRoot(cf: CFrame, s: number, seat: number): CFrame
	return cf * CFrame.new(0, seat - HIP * s + 0.1, 0)
end

--==============================================================
function LobbyPark.new(folder: Instance, level: number)
	local self = setmetatable({}, LobbyPark)
	self.level = level
	self.counts = COUNTS[level] or COUNTS[2]
	self.rng = Random.new(20261018)
	self.folder = Instance.new("Folder")
	self.folder.Name = "Park"
	self.folder.Parent = folder
	self.peopleFolder = Instance.new("Folder")
	self.peopleFolder.Name = "People"
	self.peopleFolder.Parent = self.folder
	self.zones = {} :: { any }
	self.actors = {} :: { any }
	self.fx = {} :: { any }
	self.lamps = {} :: { any }
	self.shots = {} :: { [number]: number }
	self.talkers = {} :: { any }
	self.leads = {} :: { [number]: any } -- a yard's first spectator, who calls out its launches
	self.flyers = {} :: { [number]: { any } } -- kite flyers by gap (for kite fights)
	self.lastShot = nil :: any -- the latest launch: where from, which way, when
	self.newBest = -1e9 -- when you last came back with a new best
	self.lastWhoa = -1e9
	self.conns = {} :: { RBXScriptConnection }
	self.frame = 0
	self.spurs = {} :: { any } -- { a, b }: the paved spurs' centre lines
	self.treeSpots = {} :: { Vector3 }
	self.pondSpots = {} :: { any } -- { p, r }
	self.wear = {} :: { any } -- { p, r }: where people gather and the grass wears (LobbyDetail draws it)
	self.parts = table.create(1600) :: { BasePart }
	self.cfs = table.create(1600) :: { CFrame }
	if not Models.get("Park/Person") then return self end -- the park pack isn't imported yet
	-- everything that zones its spot comes before the trees, so no tree grows out of anyone
	local steps = { self.paths, self.ponds, self.playground, self.fountain, self.yardFountains, self.banyans, self.cricket, self.garden, self.spectators, self.critters, self.trees, self.groups, self.walkers }
	for _, step in ipairs(steps) do
		local ok, err = pcall(step, self)
		if not ok then warn("[TyreCannon] LobbyPark:", err) end
		task.wait()
	end
	task.spawn(self.listen, self)
	return self
end

-- is `p` clear of everything the park built (so LobbyDetail's grass and flowers keep off it)?
-- is `p` on (or within `margin` of) the footpath ring or one of its paved spurs?
function LobbyPark:onPath(p: Vector3, margin: number?): boolean
	if Models.get("Park/Person") and math.abs((flat(p) - CENTRE).Magnitude - PATH_R) < PATH_W / 2 + 1 + (margin or 0) then
		return true
	end
	for _, s in ipairs(self.spurs) do
		-- (distance from the spur's centre line)
		local ab, ap = flat(s.b - s.a), flat(p - s.a)
		local u = math.clamp(ap:Dot(ab) / ab:Dot(ab), 0, 1)
		if (ap - ab * u).Magnitude < PATH_W / 2 + 1 + (margin or 0) then return true end
	end
	return false
end

function LobbyPark:clear(p: Vector3, margin: number?): boolean
	if self:onPath(p, margin) then return false end
	for _, z in ipairs(self.zones) do
		if (flat(p) - flat(z.p)).Magnitude < z.r + (margin or 0) then return false end
	end
	return true
end

function LobbyPark:zone(p: Vector3, r: number)
	table.insert(self.zones, { p = p, r = r })
end

function LobbyPark:put(name: string, cf: CFrame, scale: number?, zone: number?): Model?
	-- (2026-10-24, the owner: "switch all the old flower pots with the tyre pot from the centre")
	if name == "FlowerBed" and Models.get("Roadside/RoadPlanter") then
		name, scale = "Roadside/RoadPlanter", (scale or 1) * 1.05
	end
	local path = if string.find(name, "/") then name else "Park/" .. name
	local tpl = Models.get(path)
	if not tpl then return nil end
	local m = Models.place(tpl, self.folder, cf, scale or 1)
	for _, part in ipairs(Models.parts(m)) do part.CastShadow = false end
	self:solid(m, name, scale or 1)
	if zone then self:zone(cf.Position, zone) end
	-- (LobbyDetail clusters shrubs at tree bases and rocks at pond rims)
	-- (not the banyan, whose platform covers its base, nor the ashokas lining the paved spurs)
	if string.find(name, "Tree") and not string.find(name, "Banyan") and not string.find(name, "Ashoka") then table.insert(self.treeSpots, cf.Position) end
	return m
end

-- make a placed piece solid: props by Physical's rules (their collision shapes are baked into the
-- templates in Studio); a tree by a slim trunk collider so its canopy stays walk-under; the banyan's
-- chabutra a platform you can climb onto; water and lamp glass soft
function LobbyPark:solid(m: Model, name: string, scale: number)
	if string.find(name, "Tree") then
		for _, part in ipairs(Models.parts(m)) do part.CanCollide = false end
		local base = m:GetPivot().Position
		local _, size = m:GetBoundingBox()
		local w = math.clamp(math.min(size.X, size.Z) * 0.09, 1.4, 3.6)
		local h = size.Y * 0.5
		local trunk = newPart(m, Vector3.new(w, h, w), CFrame.new(base + Vector3.new(0, h / 2, 0)), Color3.new(), nil, Enum.PartType.Cylinder)
		trunk.CFrame = trunk.CFrame * CFrame.Angles(0, 0, math.pi / 2)
		trunk.Size = Vector3.new(h, w, w)
		trunk.Name = "TrunkCollider"
		trunk.Transparency = 1
		trunk.CanCollide = true
		if string.find(name, "Banyan") then
			local d = 18.8 * scale
			local plat = newPart(m, Vector3.new(2.6 * scale, d, d), CFrame.new(base + Vector3.new(0, 1.3 * scale, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.new(), nil, Enum.PartType.Cylinder)
			plat.Name = "ChabutraCollider"
			plat.Transparency = 1
			plat.CanCollide = true
		end
		return
	end
	Physical.solidify(m)
	for _, part in ipairs(Models.parts(m)) do
		if part.Name == "Water" or part.Name == "Glow" then part.CanCollide = false end
	end
end

--==============================================================
-- talk: speech bubbles over the park's people
--==============================================================
local function fmtMetres(m: number): string
	local s = tostring(math.floor(m))
	s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if s:sub(1, 1) == "," then s = s:sub(2) end
	return s .. " m"
end

local function bestOf(plr: Player): number
	local ls = plr:FindFirstChild("leaderstats")
	local b = ls and ls:FindFirstChild("Best")
	return if b and b:IsA("IntValue") then b.Value else 0
end

-- the facts a line can use: another player (one with a best, if any), the server's best, you
local function talkContext(rng: Random): any
	local me = Players.LocalPlayer
	-- no best yet means no "{mybest}" lines (nobody says "0 m! Not bad"), and {top} is never you
	local ctx: any = { me = me.DisplayName, mybest = if bestOf(me) > 0 then fmtMetres(bestOf(me)) else nil }
	local others, top, topBest = {}, nil, 0
	for _, plr in ipairs(Players:GetPlayers()) do
		local b = bestOf(plr)
		if plr ~= me and b > 0 then table.insert(others, plr) end
		if plr ~= me and b > topBest then top, topBest = plr, b end
	end
	if #others > 0 then
		local p = others[rng:NextInteger(1, #others)]
		ctx.p, ctx.best = p.DisplayName, fmtMetres(bestOf(p))
		local pr = p:GetAttribute("Prestige")
		if typeof(pr) == "number" and pr > 0 then ctx.prestige = tostring(pr) end
	end
	if top then ctx.top, ctx.topbest = top.DisplayName, fmtMetres(topBest) end
	return ctx
end

local function fill(line: string, ctx: any): string?
	local missing = false
	local out = line:gsub("{(%w+)}", function(key)
		local v = ctx[key]
		if v == nil then missing = true; return "" end
		return v
	end)
	return if missing then nil else out
end

function LobbyPark:say(who: any, text: string?)
	if not (who and text) then return end
	local head = who.parts.Head
	local cam = workspace.CurrentCamera
	-- only people you can actually see speak (the launch yards stay the loudest thing on screen)
	if head and cam and (head.Position - cam.CFrame.Position).Magnitude < 170 then
		pcall(function() TextChatService:DisplayBubble(head, text) end)
	end
end

-- a group that talks among itself: its people, where it stands, its queue of lines
function LobbyPark:talker(members: { any }, centre: Vector3): any
	local g = { members = members, centre = centre, queue = {}, next = 0, speaker = 0, speakUntil = 0, greeted = -1e9, faceUntil = 0 }
	g.next = workspace:GetServerTimeNow() + self.rng:NextNumber(2, 12)
	table.insert(self.talkers, g)
	return g
end

-- start a conversation: player talk sometimes, if there's anyone to talk about
function LobbyPark:converse(g: any, list: { any }?)
	local ctx = talkContext(self.rng)
	for _ = 1, 6 do
		local pool = list or (if self.rng:NextNumber() < 0.35 then TALK_PLAYER else TALK)
		local convo = pool[self.rng:NextInteger(1, #pool)]
		local lines = {}
		for _, l in ipairs(convo) do
			local text = fill(l[2], ctx)
			if not text then lines = nil; break end
			table.insert(lines, { l[1], text })
		end
		if lines then g.queue = lines; return end
	end
end

function LobbyPark:chatter(t: number)
	local me = Players.LocalPlayer
	local char = me.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	for _, g in ipairs(self.talkers) do
		if camPos and (g.centre - camPos).Magnitude < 170 then
			-- walk up to a group and it says hello (once in a while)
			if hrp and (flat(hrp.Position) - flat(g.centre)).Magnitude < 18 and t - g.greeted > 120 then
				g.greeted = t
				-- (a new best since this group last saw you: that's what they want to talk about)
				local fresh = t - self.newBest < 300 and g.toldBest ~= self.newBest
				if fresh then g.toldBest = self.newBest end
				self:converse(g, if fresh then NEWBEST else GREET)
				g.faceUntil = t + 5
				g.next = t
			end
			if t >= g.next then
				if #g.queue == 0 then self:converse(g) end
				local line = table.remove(g.queue, 1)
				if line then
					local idx = ((line[1] - 1) % #g.members) + 1
					self:say(g.members[idx], line[2])
					g.speaker, g.speakUntil = idx, t + 2.8
				end
				g.next = t + (if #g.queue > 0 then self.rng:NextNumber(2.6, 3.4) else self.rng:NextNumber(12, 22))
			end
		end
	end
end

-- chat to someone in a group (E): they turn to you and answer
function LobbyPark:prompt(g: any, who: any)
	local torso = who.parts.Torso
	if not torso then return end
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Chat"
	pp.ObjectText = "Park visitor"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.Parent = torso
	pp.Triggered:Connect(function()
		local t = workspace:GetServerTimeNow()
		local ctx = talkContext(self.rng)
		local text = fill(REPLIES[self.rng:NextInteger(1, #REPLIES)], ctx)
		local idx = table.find(g.members, who) or 1
		g.queue = { { idx, text or "Hello!" } }
		g.faceUntil = t + 5
		g.next = t
	end)
end

-- an animated thing; `centre` decides how often it moves (an actor that travels keeps it up to date)
function LobbyPark:actor(centre: Vector3, update: (number, { BasePart }, { CFrame }) -> ()): any
	local a = { centre = centre, update = update, phase = #self.actors % 6 }
	table.insert(self.actors, a)
	return a
end

--==============================================================
-- the footpath, lamps and bins
--==============================================================
function LobbyPark:paths()
	local f = Instance.new("Folder")
	f.Name = "Paths"
	f.Parent = self.folder
	-- spurs: in from the plaza in every gap (a path leading in invites you in), and out to the set
	-- pieces: gap -> { x along the ring, how far out }. The ring's kerb opens where each one joins.
	-- (2026-10-21: each spur stops at the set piece's edge: the bridge's foot, the sand's kerb, the pond's
	-- rim; the fountain's plaza meets the path itself, so gap 3 keeps only the kerb's opening)
	-- (2026-10-24, the owner: "useless road connector to the lake, remove it") the pond's stub (gap 4) and the
	-- garden's T (gap 7) are gone, and so is the walk on past the big pond's bridge
	local OUT = { [0] = { 0, 469 }, [2] = { 0, 468 }, [3] = { 0, 462 } }
	local mouths = {} -- { angle, side } where the kerb is left open
	for k = 0, 7 do
		table.insert(mouths, { (k + 0.5) * math.pi / 4, -1 })
		if OUT[k] then table.insert(mouths, { (k + 0.5) * math.pi / 4 + X(OUT[k][1]) / PATH_R, 1 }) end
	end
	local function open(a: number, side: number): boolean
		for _, m in ipairs(mouths) do
			local d = math.abs((a - m[1] + math.pi) % (2 * math.pi) - math.pi)
			if m[2] == side and d < math.rad(2) then return true end
		end
		return false
	end
	-- (2026-10-24, the owner: "fix the path all the way around, specifically the border of it") the old
	-- ring was 180 slabs, each 0.6 too long, so every joint was a flickering overlap and the kerbs
	-- stepped out at each one in a saw-tooth. Now 360 slabs cut to the chord at the ring's outer edge,
	-- every other one a hair higher (an overlap never shimmers), and each kerb is its own ring of
	-- pieces cut to its own radius, with the cut-outs for the walks rounded off by a post either side
	local n = 360
	local step = math.pi * 2 / n
	local function chord(r: number): number return 2 * r * math.sin(step / 2) end
	for i = 0, n - 1 do
		local a = (i + 0.5) * step
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = CENTRE + out * PATH_R
		local face = CFrame.lookAt(p, CENTRE) -- -Z toward the plaza, X along the ring
		local lift = if i % 2 == 0 then 0 else 0.004
		newPart(f, Vector3.new(chord(PATH_R + PATH_W / 2) + 0.04, 0.2, PATH_W), face + Vector3.new(0, 0.1 + lift, 0), SANDSTONE, Enum.Material.Pavement)
		for _, side in ipairs({ -1, 1 }) do
			if not open(a, side) then
				local rk = PATH_R + side * (PATH_W / 2 + 0.3) -- (+1 the outer kerb)
				local q = CENTRE + out * rk
				local kf = CFrame.lookAt(q, CENTRE)
				newPart(f, Vector3.new(chord(rk + 0.3) + 0.03, 0.34, 0.6), kf + Vector3.new(0, 0.17 + lift, 0), KERB, Enum.Material.Pavement)
				-- where the kerb stops for a walk, a rounded post ends it cleanly
				if open(a + step, side) or open(a - step, side) then
					local post = newPart(f, Vector3.new(0.34, 0.6, 0.6), CFrame.new(q + Vector3.new(0, 0.17, 0)) * CFrame.Angles(0, 0, math.pi / 2), KERB, Enum.Material.Pavement, Enum.PartType.Cylinder)
					post.Name = "KerbEnd"
				end
			end
		end
		if i % 60 == 0 then task.wait() end
	end
	local function spur(k: number, x: number, r0: number, r1: number)
		local p0, p1 = gp(k, r0, x), gp(k, r1, x)
		table.insert(self.spurs, { a = p0, b = p1 })
		local mid, len = (p0 + p1) / 2, (p1 - p0).Magnitude
		local cf = CFrame.lookAt(mid, p1)
		newPart(f, Vector3.new(PATH_W - 2, 0.2, len), cf + Vector3.new(0, 0.1, 0), SANDSTONE, Enum.Material.Pavement)
		for _, side in ipairs({ -1, 1 }) do
			newPart(f, Vector3.new(0.5, 0.3, len), cf * CFrame.new(side * ((PATH_W - 2) / 2 + 0.25), 0.15, 0), KERB, Enum.Material.Pavement)
		end
	end
	for k = 0, 7 do
		-- (the inward spur would be a few studs long now the path runs beside the yards: it's gone)
		if OUT[k] and R(OUT[k][2]) > PATH_R + PATH_W / 2 + 0.5 then spur(k, OUT[k][1], Rinv(PATH_R + PATH_W / 2), OUT[k][2]) end
	end
	-- (over the big pond's bridge and on to a bench looking back at the water)
	-- (spur(0, 0, 532, 563), on past the bridge, removed 2026-10-24)
	-- lamps in pairs either side of every gap's spurs (none stand in a line of fire), a bin by one
	for j = 0, 15 do
		local k = j // 2
		local a = math.rad((k + 0.5) * 45 + (if j % 2 == 0 then -5.625 else 5.625))
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = CENTRE + out * (PATH_R + PATH_W / 2 + 2.2)
		local lamp = self:put("ParkLamp", CFrame.lookAt(p, p - out), 1)
		local glow = lamp and lamp:FindFirstChild("Glow") :: BasePart?
		if glow then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 206, 140)
			light.Range = 20
			light.Brightness = 1.3
			light.Shadows = false
			light.Enabled = false
			light.Parent = glow
			table.insert(self.lamps, { part = glow, light = light })
		end
		if j % 2 == 0 then
			local side = Vector3.new(-out.Z, 0, out.X)
			self:put("Bin", CFrame.lookAt(p + side * 3, p + side * 3 - out), 1)
		end
	end
	self:nightCheck(true)
end

function LobbyPark:nightCheck(force: boolean?)
	local c = Lighting.ClockTime
	local night = c >= 17.5 or c < 6.3 -- (2026-10-23: on at the fixed 17.7 evening)
	if night == self.night and not force then return end
	self.night = night
	for _, l in ipairs(self.lamps) do
		l.part.Material = if night then Enum.Material.Neon else Enum.Material.SmoothPlastic
		l.part.Color = if night then Color3.fromRGB(255, 214, 150) else Color3.fromRGB(236, 224, 190)
		l.light.Enabled = night
	end
end

--==============================================================
-- ponds: koi swimming and jumping, ducks paddling
--==============================================================
local function tintWater(m: Model?, color: Color3, transparency: number)
	if not m then return end
	local w = m:FindFirstChild("Water") :: BasePart?
	if w then
		w.Color = color
		w.Transparency = transparency
		w.Material = Enum.Material.SmoothPlastic
		w.Reflectance = 0.05
	end
end

function LobbyPark:pond(kind: string, cf: CFrame, R1: number, R2: number, fish: number, ducks: number, bridge: boolean?, sc: number?)
	-- (sc draws the pond bigger than it was built, so it holds its own on the wide lawn; the koi and
	-- ducks keep their size)
	local k = sc or 1
	R1, R2 = R1 * k, R2 * k
	local waterY = WATER_Y * k
	local m = self:put(kind, cf, k)
	tintWater(m, WATER, 0.3)
	if bridge then self:put("Bridge", cf, k) end
	self:zone(cf.Position, math.max(R1, R2) * 1.2)
	table.insert(self.pondSpots, { p = cf.Position, cf = cf, r1 = R1 * 1.15, r2 = R2 * 1.15 })
	local rng = self.rng
	local kinds = { "FishKoi", "FishGold", "FishInk" }
	-- swimmers: each on its own ellipse under the surface
	local swimmers = {}
	for i = 1, fish do
		local part, rest = self:single(kinds[(i % 3) + 1], 1.3)
		if part then
			table.insert(swimmers, { part = part, rest = rest, f = rng:NextNumber(0.25, 0.62), w = rng:NextNumber(0.22, 0.42) * (if i % 2 == 0 then 1 else -1), a0 = rng:NextNumber(0, 6.28) })
		end
	end
	local duckList = {}
	for i = 1, ducks do
		local part, rest = self:single("Duck", 1.6)
		if part then
			local mother = { part = part, rest = rest, f = rng:NextNumber(0.55, 0.75), w = rng:NextNumber(0.06, 0.1), a0 = rng:NextNumber(0, 6.28), lag = 0 }
			table.insert(duckList, mother)
			-- the first duck has ducklings paddling along behind her
			if i == 1 then
				for j = 1, 3 do
					local dp, dr = self:single("Duck", 0.75)
					if dp then
						table.insert(duckList, { part = dp, rest = dr, f = mother.f, w = mother.w, a0 = mother.a0, lag = j * 0.07 / mother.f, small = true })
					end
				end
			end
		end
	end
	-- the jumper: one fish that leaps every few seconds
	local jumper, jumperRest = self:single("FishKoi", 1.5)
	local jump = { t0 = -1e9, next = 0, from = Vector3.zero, dir = Vector3.xAxis, splashed = 2 }
	local function onPond(f: number, a: number, y: number): Vector3
		return (cf * CFrame.new(math.cos(a) * R1 * f, y, math.sin(a) * R2 * f)).Position
	end
	local gather = 0 -- 0..1: how drawn the koi are to you
	local reach = math.max(R1, R2) * 1.15 + 4
	self:actor(cf.Position, function(t, parts, cfs)
		-- stand at the edge or on the bridge and the koi come to you, hoping for food
		local ch = Players.LocalPlayer.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		local you: Vector3? = nil
		if hrp then
			local rel = cf:PointToObjectSpace(hrp.Position)
			local e = (rel.X / (R1 * 1.1)) ^ 2 + (rel.Z / (R2 * 1.1)) ^ 2
			if e < 1.25 and (flat(hrp.Position) - flat(cf.Position)).Magnitude < reach then
				-- (the nearest point inside the water)
				local s = if e > 0.55 then math.sqrt(0.55 / e) else 1
				you = (cf * CFrame.new(rel.X * s, waterY - 0.42, rel.Z * s)).Position
			end
		end
		gather = math.clamp(gather + (if you then 0.02 else -0.01), 0, 1)
		for n, sw in ipairs(swimmers) do
			local a = sw.a0 + t * sw.w
			local p = onPond(sw.f, a, waterY - 0.42)
			local ahead = onPond(sw.f, a + 0.05 * math.sign(sw.w), waterY - 0.42)
			if you and gather > 0 then
				-- circling your feet, a tight jostling ring
				local ra = n / #swimmers * math.pi * 2 + t * 0.8
				local spot = you + Vector3.new(math.cos(ra) * 2.4, 0, math.sin(ra) * 2.4)
				local g = gather * gather * (3 - 2 * gather)
				p = p:Lerp(spot, g)
				ahead = ahead:Lerp(spot + Vector3.new(-math.sin(ra), 0, math.cos(ra)), g)
			end
			table.insert(parts, sw.part)
			table.insert(cfs, CFrame.lookAt(p, ahead) * CFrame.Angles(0, math.sin(t * 6 + sw.a0) * 0.15, 0) * sw.rest)
		end
		for _, d in ipairs(duckList) do
			local a = d.a0 + t * d.w - (d.lag or 0)
			local bobY = waterY - (if d.small then 0.14 else 0.28)
			local p = onPond(d.f, a, bobY + math.sin(t * 2.4 + d.a0 + (d.lag or 0) * 9) * 0.05)
			local ahead = onPond(d.f, a + 0.05, bobY)
			table.insert(parts, d.part)
			table.insert(cfs, CFrame.lookAt(p, Vector3.new(ahead.X, p.Y, ahead.Z)) * CFrame.Angles(0, 0, math.sin(t * 1.7 + d.a0) * 0.06) * d.rest)
		end
		if jumper then
			if t > jump.next then
				local a = rng:NextNumber(0, 6.28)
				jump.from = onPond(0.4, a, waterY - 0.4)
				local d = flat(onPond(0.1, a + rng:NextNumber(-0.8, 0.8), 0) - jump.from)
				if you and gather > 0.6 then
					-- (with you watching, it leaps right in front of you, more often)
					jump.from = you + Vector3.new(rng:NextNumber(-3, 3), 0.02, rng:NextNumber(-3, 3))
					d = flat(cf.Position - jump.from)
				end
				jump.dir = if d.Magnitude > 0.1 then d.Unit else Vector3.xAxis
				jump.t0 = t
				jump.next = t + (if you then rng:NextNumber(2.5, 5) else rng:NextNumber(4, 9))
				jump.splashed = 0
			end
			local u = (t - jump.t0) / 1.0
			local p: Vector3, look: Vector3
			if u >= 0 and u <= 1 then
				local h, len = 3.6, 6
				p = jump.from + jump.dir * len * u + Vector3.new(0, 4 * h * u * (1 - u), 0)
				look = jump.dir * len + Vector3.new(0, 4 * h * (1 - 2 * u), 0)
				if jump.splashed == 0 then jump.splashed = 1; self:splash(jump.from + Vector3.new(0, 0.42, 0), t) end
			else
				p, look = jump.from - Vector3.new(0, 30, 0), jump.dir
				if jump.splashed == 1 and u > 1 then jump.splashed = 2; self:splash(jump.from + jump.dir * 6 + Vector3.new(0, 0.42, 0), t) end
			end
			table.insert(parts, jumper)
			table.insert(cfs, CFrame.lookAt(p, p + look) * jumperRest)
		end
	end)
end

-- a splash: a ring spreading on the water and a few drops thrown up
function LobbyPark:splash(at: Vector3, t: number)
	local ring = newPart(self.folder, Vector3.new(0.12, 1.2, 1.2), CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(226, 244, 248), nil, Enum.PartType.Cylinder)
	ring.Transparency = 0.15
	table.insert(self.fx, { part = ring, t0 = t, kind = "ring", at = at })
	for i = 1, 6 do
		local drop = newPart(self.folder, Vector3.one * 0.32, CFrame.new(at), Color3.fromRGB(200, 232, 240), nil, Enum.PartType.Ball)
		local a = i / 6 * math.pi * 2 + self.rng:NextNumber(-0.3, 0.3)
		table.insert(self.fx, { part = drop, t0 = t, kind = "drop", at = at, v = Vector3.new(math.cos(a) * self.rng:NextNumber(2.5, 5), self.rng:NextNumber(9, 14), math.sin(a) * self.rng:NextNumber(2.5, 5)) })
	end
end

-- a paved pad for a bench or a stall to stand on (park seats sit on a slab, not loose on the grass)
function LobbyPark:pad(cf: CFrame, w: number, d: number)
	local p = newPart(self.folder, Vector3.new(w, 0.2, d), cf + Vector3.new(0, 0.1, 0), SANDSTONE, Enum.Material.Pavement)
	p.Name = "Pad"
	self:zone(cf.Position, math.max(w, d) / 2 + 1)
	table.insert(self.wear, { p = cf.Position, r = math.max(w, d) * 0.7 })
	return p
end

function LobbyPark:bench(cf: CFrame, sitters: number)
	-- (2026-10-23: the new, bigger bench you can sit on: BenchKit)
	self:pad(cf * CFrame.new(0, 0, 0.4), 10.5, 4.8)
	local BenchKit = require(script.Parent:WaitForChild("BenchKit"))
	if BenchKit.place(self.folder, cf, 1) then self:zone(cf.Position, 5.5) else self:put("Bench", cf, 1, 4) end
	for i = 1, sitters do
		local p = self:person({ phone = self.rng:NextNumber() < 0.4 })
		if p then
			local x = if sitters == 1 then 0 else (i - 1.5) * 2.6
			local root = sitRoot(cf * CFrame.new(x, 0, 0.25), p.s, 1.72)
			local looking = self.rng:NextNumber(0, 6.28)
			self:actor(cf.Position, function(t, parts, cfs)
				local a = table.clone(SIT)
				a.headYaw = math.sin(t * 0.3 + looking) * 0.5
				if p.parts.Phone then
					a.armL, a.armR, a.armLYaw, a.armRYaw = 0.9, 0.9, 0.3, 0.3
					a.headPitch = -0.45
					a.headYaw = 0
					a.phone = CFrame.new(0, 2.75 * p.s, -1.35 * p.s) * CFrame.Angles(-0.9, 0, 0)
				end
				pose(p, root, a, parts, cfs)
			end)
		end
	end
end

function LobbyPark:ponds()
	-- (the set pieces sit close in, where they read from the plaza; benches face the water)
	-- (2026-10-21: the ring's compression left set pieces on the footpath: the big pond is a size down and
	-- a touch further out, so its rim clears the path's kerb)
	local big = gcf(0, 511, 0)
	self:pond("PondBig", big, 26, 17, if self.counts.busy then 7 else 3, 4, true, 0.85)
	for _, x in ipairs({ -66, 66 }) do
		self:bench(gcf(0, 478, x, (gp(0, 511, 0) - gp(0, 478, x)).Unit), if x < 0 then 2 else 1)
	end
	-- past the bridge, a bench at the end of the path looking back over the pond
	self:bench(gcf(0, 566, 0, "in"), 1)
	self:put("FlowerBed", gcf(0, 572, -58), 1.2, 6)
	self:put("FlowerBed", gcf(0, 572, 58), 1.2, 6)
	local small = gcf(4, 515, -30)
	self:pond("PondSmall", small, 15, 11, if self.counts.busy then 4 else 2, 2, false, 1.0)
	self:bench(gcf(4, 492, -64, (gp(4, 515, -30) - gp(4, 492, -64)).Unit), 1)
	self:bench(gcf(4, 497, 6, (gp(4, 515, -30) - gp(4, 497, 6)).Unit), 2)
	self:put("FlowerBed", gcf(4, 520, 46), 1, 5)
	-- (2026-10-23) gap 6 lost its gully cricket with the people: a second lily pond, benches facing it
	local third = gcf(6, 512, 10)
	self:pond("PondSmall", third, 15, 11, if self.counts.busy then 4 else 2, 2, false, 1.1)
	self:bench(gcf(6, 490, -40, (gp(6, 512, 10) - gp(6, 490, -40)).Unit), 1)
	self:bench(gcf(6, 490, 52, (gp(6, 512, 10) - gp(6, 490, 52)).Unit), 1)
	self:put("FlowerBed", gcf(6, 530, -46), 1, 5)
	self:put("FlowerBed", gcf(6, 530, 62), 1, 5)
end

--==============================================================
-- the playground
--==============================================================
function LobbyPark:playground()
	local k = 2
	local S = 1.05 -- the equipment drawn a size up (and the kids with it) so it reads across the lawn
	local KID = 0.72
	local pad = gp(k, 517, 0) -- (517: the sand's kerb clear of the footpath's, 2026-10-21)
	-- the sand, with a kerb ring where it meets the grass
	local edge = newPart(self.folder, Vector3.new(0.24, 42.5, 42.5), CFrame.new(pad + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.pi / 2), KERB, Enum.Material.Pavement, Enum.PartType.Cylinder)
	edge.Name = "SandKerb"
	local mulch = newPart(self.folder, Vector3.new(0.3, 40, 40), CFrame.new(pad + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(196, 158, 112), Enum.Material.Sand, Enum.PartType.Cylinder)
	mulch.Name = "Mulch"
	self:zone(pad, 22)
	local busy = self.counts.busy
	-- swings: two kids, out of step (the frame a size bigger again: a real top bar is well over head height)
	local SF = 1.35
	local frame = gcf(k, 494, -15)
	self:put("SwingFrame", frame, SF)
	local seatTpl = Models.get("Park/SwingSeat")
	for i, x in ipairs({ -1.9 * SF, 1.9 * SF }) do
		local seat = seatTpl and (Models.place(seatTpl, self.peopleFolder, frame, SF):FindFirstChildWhichIsA("BasePart") :: BasePart)
		local kid = self:person({ scale = KID, moving = true })
		local seatLocal = seat and frame:Inverse() * seat.CFrame -- the seat as it hangs from the frame's middle
		local phase = i * 1.7
		local top = frame * CFrame.new(x, 3.5 * SF, 0)
		self:actor(frame.Position, function(t, parts, cfs)
			local ang = math.sin(t * 1.8 + phase) * 0.6
			-- the ground under this seat's hook, swung about the top bar
			local swing = top * CFrame.Angles(ang, 0, 0) * CFrame.new(0, -3.5 * SF, 0)
			if seat and seatLocal then
				table.insert(parts, seat)
				table.insert(cfs, swing * seatLocal)
			end
			if kid then
				local a = table.clone(SIT)
				a.armL, a.armR, a.armLYaw, a.armRYaw = 2.75, 2.75, 0.3, 0.3
				a.legL, a.legR = 1.2 - ang * 0.6, 1.2 - ang * 0.6
				pose(kid, sitRoot(swing, kid.s, 0.92 * SF), a, parts, cfs)
			end
		end)
	end
	-- the slide: up the ladder, down the chute, round the back again
	local slideCf = gcf(k, 490, 10)
	self:put("Slide", slideCf, S)
	local slider = self:person({ scale = KID, moving = true })
	if slider then
		local s = slider.s
		local L = function(v: Vector3): Vector3 return (slideCf * CFrame.new(toModel(v, S))).Position end
		local foot, top, chuteTop, chuteEnd = L(Vector3.new(0, -4.9, 0)), L(Vector3.new(0, -2.8, 4.1)), L(Vector3.new(0, -2.0, 4.0)), L(Vector3.new(0, 4.2, 0.55))
		local round = { L(Vector3.new(0, 4.8, 0)), L(Vector3.new(3.2, 2.0, 0)), L(Vector3.new(3.2, -3.5, 0)), foot }
		local fwd = slideCf.LookVector
		self:actor(slideCf.Position, function(t, parts, cfs)
			local u = (t % 9)
			if u < 2.2 then -- climbing
				local q = u / 2.2
				local p = foot:Lerp(top, q)
				local a = { armL = 2.4 + math.sin(u * 8) * 0.4, armR = 2.4 - math.sin(u * 8) * 0.4, legL = math.max(0, math.sin(u * 8)) * 0.9, legR = math.max(0, -math.sin(u * 8)) * 0.9 }
				pose(slider, CFrame.lookAt(p, p + fwd), a, parts, cfs)
			elseif u < 3.4 then -- sliding, arms up
				local q = (u - 2.2) / 1.2
				local p = chuteTop:Lerp(chuteEnd, q * q * (3 - 2 * q))
				local a = table.clone(SIT)
				a.armL, a.armR, a.headPitch = 2.9, 2.9, 0.2
				pose(slider, sitRoot(CFrame.lookAt(p, p + fwd), s, 0.15), a, parts, cfs)
			else -- running back round
				local q = (u - 3.4) / 5.6 * 3
				local seg = math.min(3, math.floor(q) + 1)
				local p0 = if seg == 1 then chuteEnd else round[seg]
				local p1 = round[seg + 1] or foot
				local w = q - (seg - 1)
				local p = p0:Lerp(p1, math.clamp(w, 0, 1))
				local dir = flat(p1 - p0)
				pose(slider, CFrame.lookAt(p, p + (if dir.Magnitude > 0.1 then dir.Unit else fwd)), walkPose(t * strideRate(6, 0.75, s), 0.75, s, 0.14), parts, cfs)
			end
		end)
	end
	-- the see-saw
	local ss = gcf(k, 514, 14, "side")
	self:put("SeeSawBase", ss, S)
	local plankTpl = Models.get("Park/SeeSawPlank")
	local plank = plankTpl and (Models.place(plankTpl, self.peopleFolder, ss, S):FindFirstChildWhichIsA("BasePart") :: BasePart)
	local plankRest = plank and ss:Inverse() * plank.CFrame
	local riders = { self:person({ scale = KID, moving = true }), self:person({ scale = KID, moving = true }) }
	self:actor(ss.Position, function(t, parts, cfs)
		local ang = math.sin(t * 1.6) * 0.28
		local tilt = ss * CFrame.new(0, 1.25 * S, 0) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, -1.25 * S, 0)
		if plank and plankRest then
			table.insert(parts, plank)
			table.insert(cfs, tilt * plankRest)
		end
		for i, kid in ipairs(riders) do
			if kid then
				local z = if i == 1 then 3.5 * S else -3.5 * S
				local seatCf = tilt * CFrame.new(0, 0, z) * (if i == 1 then I else CFrame.Angles(0, math.pi, 0))
				local a = table.clone(SIT)
				a.armL, a.armR = 1.0, 1.0
				a.headPitch = (if i == 1 then ang else -ang) * 0.5
				pose(kid, sitRoot(seatCf, kid.s, 1.5 * S), a, parts, cfs)
			end
		end
	end)
	-- the merry-go-round, three kids riding
	if busy then
		local mg = gcf(k, 518, -8)
		self:put("MerryBase", mg, S)
		local topTpl = Models.get("Park/MerryTop")
		local top = topTpl and (Models.place(topTpl, self.peopleFolder, mg, S):FindFirstChildWhichIsA("BasePart") :: BasePart)
		-- (2026-10-23, the owner: the merry-go-round clipped into the ground) the turning top sat 0.26 into
		-- its base: it rides on the base's top now
		if top then
			local base = self.folder:FindFirstChild("MerryBase")
			local _, bs = if base then (base :: Model):GetBoundingBox() else CFrame.new(), Vector3.new(0, 0.95 * S, 0)
			local lift = (mg.Position.Y + bs.Y + 0.03) - (top.Position.Y - top.Size.Y / 2)
			if lift > 0 then top.CFrame += Vector3.new(0, lift, 0) end
		end
		local topRest = top and mg:Inverse() * top.CFrame
		local ridersM = { self:person({ scale = KID, moving = true }), self:person({ scale = KID, moving = true }), self:person({ scale = KID, moving = true }) }
		self:actor(mg.Position, function(t, parts, cfs)
			local spin = mg * CFrame.Angles(0, (t * 1.1) % (2 * math.pi), 0) -- wrapped: CFrame angles are 32-bit
			if top and topRest then
				table.insert(parts, top)
				table.insert(cfs, spin * topRest)
			end
			for i, kid in ipairs(ridersM) do
				if kid then
					local seatCf = spin * CFrame.Angles(0, i / 3 * math.pi * 2, 0) * CFrame.new(0, 0, -1.9 * S) * CFrame.Angles(0, math.pi / 2, 0)
					local a = table.clone(SIT)
					a.armL, a.armR, a.headYaw = 1.3, 0.4, math.sin(t + i) * 0.4
					pose(kid, sitRoot(seatCf, kid.s, 0.86 * S), a, parts, cfs)
				end
			end
		end)
	end
	-- parents' benches at the sand's edge, facing the kids, and shade trees behind the far side
	self:bench(gcf(k, 514, -56, (gp(k, 514, 0) - gp(k, 514, -56)).Unit), 1)
	self:bench(gcf(k, 514, 56, (gp(k, 514, 0) - gp(k, 514, 56)).Unit), 1)
	self:put("Nature/TreeNeem", gcf(k, 565, -40), 1.1, 9)
	self:put("Nature/TreeNeem", gcf(k, 565, 42), 1.0, 9)
end

--==============================================================
-- the fountain and the chai stall
--==============================================================
-- (the cart faces the path; customers stand on the path's verge, the vendor behind)
function LobbyPark:stallFrame(): CFrame
	return gcf(3, Rinv(PATH_R + PATH_W / 2 + 7), 64, "in")
end

-- a fountain's spray: fine white water rising from its top bowl and falling back
local function spray(m: Model?, at: Vector3, rate: number, speed: number)
	if not m then return end
	local att = Instance.new("Attachment")
	att.Parent = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
	att.WorldPosition = at
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(214, 238, 246))
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.8) })
	e.Lifetime = NumberRange.new(0.9, 1.3)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.8, speed)
	e.SpreadAngle = Vector2.new(14, 14)
	e.Acceleration = Vector3.new(0, -28, 0)
	e.Parent = att
end

-- (2026-10-23, the owner: "don't just spam fountains ... come up with an idea ... two on either side with
-- benches") every yard gets its own viewing bay out on the lawn across its line of fire, where you'd
-- sit and watch that yard's launches: a paved bay with a bench either side facing the yard, a pair of
-- marigold beds behind, and a centrepiece of its own from the roadside life the game is made of. Only
-- the two yards on opposite sides of the hub (1 and 5) have a fountain.
local BAYS = {
	[0] = { "Roadside/RoadTyrePyramid", 1.0 },   -- tyres stacked into a planter
	[1] = { "Park/Fountain", 1.1, true },
	[2] = { "Roadside/RoadTyreSwing", 1.0 },     -- a tyre swing on its frame
	[3] = { "Roadside/RoadMatka", 1.05 },        -- clay water pots on their stand
	[4] = { "Roadside/RoadCharpai", 1.15 },      -- a charpai in the shade
	[5] = { "Park/Fountain", 1.1, true },
	[6] = { "Roadside/RoadToran", 0.95 },        -- a festival arch
	[7] = { "Roadside/RoadChaiCart", 1.0 },      -- the chai cart
}
function LobbyPark:yardFountains()
	local BenchKit = require(script.Parent:WaitForChild("BenchKit"))
	local r = (PATH_R + PATH_W / 2 + CANAL_IN) / 2
	for k = 0, 7 do
		local a = k * math.pi / 4
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local side = Vector3.new(-out.Z, 0, out.X)
		local p = CENTRE + out * r
		-- (looking out: the pieces' fronts and the benches' seats face back toward the yard)
		local cf = CFrame.lookAt(p, p + out)
		local bay = newPart(self.folder, Vector3.new(36, 0.2, 14), cf + Vector3.new(0, 0.1, 0), SANDSTONE, Enum.Material.Pavement)
		bay.Name = "ViewingBay"
		local kerb = newPart(self.folder, Vector3.new(36.8, 0.3, 14.8), cf + Vector3.new(0, 0.05, 0), KERB, Enum.Material.Pavement)
		kerb.Name = "ViewingBayKerb"
		self:zone(p, 19)
		table.insert(self.wear, { p = p, r = 16 })
		local spec = BAYS[k]
		if spec[3] then
			local disc = newPart(self.folder, Vector3.new(0.24, 16, 16), CFrame.new(p + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2), KERB, Enum.Material.Pavement, Enum.PartType.Cylinder)
			disc.Name = "FountainPlaza"
			local m = self:put("Fountain", cf, spec[2])
			-- (2026-10-24, the owner: the paving clipped through its base) stood on top of the plaza
			if m then
				local box, size = m:GetBoundingBox()
				m:PivotTo(m:GetPivot() + Vector3.new(0, p.Y + 0.26 - (box.Position.Y - size.Y / 2), 0))
			end
			tintWater(m, Color3.fromRGB(86, 166, 182), 0.25)
			spray(m, p + Vector3.new(0, 5.7 * spec[2], 0), 40, 13)
		else
			self:put(spec[1], cf, spec[2])
		end
		for _, s in ipairs({ -1, 1 }) do
			BenchKit.place(self.folder, cf + side * (s * 12.5), 1)
			self:put("FlowerBed", cf * CFrame.new(s * 7.5, 0, -4.6), 0.75)
		end
	end
end

function LobbyPark:fountain()
	local k = 3
	local cf = gcf(k, 502, 0)
	-- (2026-10-23: the hub's two fountains are in the yards' viewing bays now, and the chai cart has its
	-- own bay: this spot is a rose garden, beds round a sundial-like planter with benches)
	do
		self:pad(cf, 22, 22)
		self:put("Roadside/RoadPlanter", cf, 1.2, 6)
		-- (2026-10-24, the owner: "remove the extra flower pots in these areas") the five beds round it are gone
		self:bench(gcf(k, 502, -36, "side"), 0)
		self:bench(gcf(k, 502, 36, (gp(k, 502, 0) - gp(k, 502, 36)).Unit), 0)
		return
	end
	-- on a round paved plaza at the end of the spur, as a Mughal fountain sits on its axis
	local plaza = newPart(self.folder, Vector3.new(0.2, 28, 28), CFrame.new(cf.Position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), SANDSTONE, Enum.Material.Pavement, Enum.PartType.Cylinder)
	plaza.Name = "FountainPlaza"
	local FS = 1.2
	local m = self:put("Fountain", cf, FS, 17)
	if m then
		local box, size = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() + Vector3.new(0, cf.Position.Y + 0.22 - (box.Position.Y - size.Y / 2), 0))
	end
	tintWater(m, Color3.fromRGB(86, 166, 182), 0.25)
	if m then
		local att = Instance.new("Attachment")
		att.Parent = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
		att.WorldPosition = cf.Position + Vector3.new(0, 5.7 * FS, 0)
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(214, 238, 246))
		e.LightEmission = 0
		e.LightInfluence = 1
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 2) })
		e.Lifetime = NumberRange.new(0.9, 1.3)
		e.Rate = 34
		e.Speed = NumberRange.new(11, 14)
		e.SpreadAngle = Vector2.new(14, 14)
		e.Acceleration = Vector3.new(0, -28, 0)
		e.Parent = att
	end
	-- beds on the diagonals, so nothing blocks the axis (the near pair drawn in off the footpath, 2026-10-21)
	for _, o in ipairs({ { -15, -15 }, { 15, -15 }, { -17, 4 }, { 17, 4 } }) do
		self:put("FlowerBed", cf * CFrame.new(o[1], 0, o[2]), 1, 5)
	end
	self:bench(gcf(k, 502, -36, "side"), 2)
	self:bench(gcf(k, 502, 36, (gp(k, 502, 0) - gp(k, 502, 36)).Unit), 1)
	-- a chai stall beside the footpath, where people walk past: the vendor behind it, two customers
	local stall = self:stallFrame()
	self:pad(stall, 11, 15)
	local cart = self:put("Roadside/RoadChaiCart", stall, 1.6, 8)
	if cart then
		local vendor = self:person({ hair = "Turban" })
		local custs = { self:person({}), self:person({}) }
		local vroot = stall * CFrame.new(0, 0, 6)
		local nextCall = 0
		self:actor(stall.Position, function(t, parts, cfs)
			if vendor and t > nextCall then
				nextCall = t + self.rng:NextNumber(12, 20)
				self:say(vendor, pick(self.rng, { "Garam chai! Garam chai!", "Chai, ten rupees!", "Fresh chai, extra adrak!" }))
			end
			if vendor then
				pose(vendor, vroot * CFrame.Angles(0, 0, 0), { armL = 0.7 + math.sin(t * 3) * 0.3, armR = 0.9, armLYaw = 0.3, armRYaw = 0.2, headYaw = math.sin(t * 0.5) * 0.3 }, parts, cfs)
			end
			for i, c in ipairs(custs) do
				if c then
					local spot = stall * CFrame.new((i - 1.5) * 4, 0, -5) * CFrame.Angles(0, math.pi, 0)
					pose(c, spot, { armR = 1.1 + math.sin(t * 0.8 + i) * 0.15, armRYaw = 0.4, headPitch = -0.1, headYaw = math.sin(t * 0.4 + i) * 0.3 }, parts, cfs)
				end
			end
		end)
	end
end

--==============================================================
-- the banyans: picnics and kites
--==============================================================
function LobbyPark:kiteFlyer(k: number, r: number, x: number, scale: number, kiteName: string)
	local who = self:person({ scale = scale })
	local kite, kiteRest = self:single(kiteName, 2.8) -- big enough to read up at 50 studs
	if not (who and kite) then return end
	local p, out, side = gp(k, r, x)
	self:zone(p, 4)
	local root = CFrame.lookAt(p, p + out)
	local hand = Instance.new("Attachment")
	hand.Parent = who.parts.ArmR
	hand.Position = Vector3.new(0, -0.9 * who.s, 0)
	local tail = Instance.new("Attachment")
	tail.Parent = kite
	local beam = Instance.new("Beam")
	beam.Attachment0 = hand
	beam.Attachment1 = tail
	beam.Color = ColorSequence.new(Color3.fromRGB(244, 241, 232))
	beam.Width0, beam.Width1 = 0.07, 0.05
	beam.FaceCamera = true
	beam.Segments = 12
	beam.CurveSize0 = -8
	beam.Transparency = NumberSequence.new(0.1)
	beam.Parent = kite
	local seed = self.rng:NextNumber(0, 6.28)
	-- kite fights (Punjab's basant): now and then a kite's string is cut; it drifts off and down, its
	-- flyer groans, the other flyer in the gap shouts "Bo kata!", and a new kite goes up
	local me = { who = who, cutAt = -1e9, nextCut = workspace:GetServerTimeNow() + self.rng:NextNumber(30, 70), from = Vector3.zero }
	self.flyers[k] = self.flyers[k] or {}
	table.insert(self.flyers[k], me)
	local CUT, RISE = 9, 3
	self:actor(p, function(t, parts, cfs)
		local tug = math.sin(t * 1.3 + seed)
		local fly = p + out * 34 + side * math.sin(t * 0.37 + seed) * 6 + Vector3.new(0, 48 + math.sin(t * 0.6 + seed) * 4, 0)
		if t > me.nextCut and t - me.cutAt > CUT + RISE then
			me.cutAt, me.from = t, fly
			me.nextCut = t + self.rng:NextNumber(45, 90)
			beam.Enabled = false
			self:say(who, pick(self.rng, { "Arre! My patang!", "Noooo!", "Not again!" }))
			for _, other in ipairs(self.flyers[k]) do
				if other ~= me then
					task.delay(0.5, function() self:say(other.who, "Bo kata!") end)
					break
				end
			end
		end
		local since = t - me.cutAt
		local kp, roll = fly, math.sin(t * 2.1 + seed) * 0.35
		local a = { armR = 2.3 + tug * 0.2, armRYaw = 0.1, armL = 0.5, headPitch = 0.55 }
		if since < CUT then
			-- adrift: carried away downwind, spinning, sinking
			local q = since / CUT
			kp = me.from + out * (q * 70) + side * (math.sin(q * 6) * 8) + Vector3.new(0, -q * q * 46, 0)
			roll = since * 2.5
			a = { armR = 0.4, armL = 0.3, headPitch = 0.35, headYaw = math.sin(t * 3) * 0.2 }
		elseif since < CUT + RISE then
			-- a new kite climbing back up
			local q = (since - CUT) / RISE
			kp = p + out * (6 + 28 * q) + Vector3.new(0, 6 + (fly.Y - p.Y - 6) * q, 0)
			beam.Enabled = true
			a.armR = 2.0 + math.sin(t * 8) * 0.4
		end
		pose(who, root, a, parts, cfs)
		table.insert(parts, kite)
		table.insert(cfs, CFrame.lookAt(kp, p + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, roll) * kiteRest)
	end)
end

function LobbyPark:picnic(cf: CFrame, people: number)
	self:put("Picnic", cf, 1, 6)
	table.insert(self.wear, { p = cf.Position, r = 7 })
	local spots = { { -2.2, -3.0, 0 }, { 2.4, -2.8, 0 }, { -3.6, 0.8, -math.pi / 2 }, { 0.4, 3.0, math.pi } }
	for i = 1, math.min(people, #spots) do
		local sp = spots[i]
		local who = self:person({ scale = if i == 4 then 0.62 else 1 })
		if who then
			local root = sitRoot(cf * CFrame.new(sp[1], 0, sp[2]) * CFrame.Angles(0, sp[3], 0), who.s, 0.15)
			local seed = i * 1.3
			self:actor(cf.Position, function(t, parts, cfs)
				local a = table.clone(SIT)
				a.armR = 0.6 + math.max(0, math.sin(t * 0.9 + seed)) * 1.1 -- eating, chatting
				a.headYaw = math.sin(t * 0.35 + seed) * 0.6
				pose(who, root, a, parts, cfs)
			end)
		end
	end
end

function LobbyPark:banyans()
	for _, k in ipairs({ 1, 5 }) do
		local x = if k == 1 then 64 else -64
		-- the banyan the biggest tree in the park, and the family picnicking in its shade
		self:put("Nature/TreeBanyan", gcf(k, 545, x), 1.2, 20)
		self:picnic(gcf(k, 540, x - math.sign(x) * 21, "side"), 4)
		if self.counts.busy then self:picnic(gcf(k, 572, -x * 0.1, "in"), 3) end
		self:kiteFlyer(k, 588, -x * 1.2, 0.62, if k == 1 then "KiteA" else "KiteB")
		self:kiteFlyer(k, 578, x * 0.2, 1, if k == 1 then "KiteC" else "KiteA")
	end
end

--==============================================================
-- gully cricket
--==============================================================
function LobbyPark:cricket()
	local k = 6
	if not self.counts.busy or not PEOPLE then return end
	local function at(r: number, x: number?): Vector3 return (gp(k, r, x)) end
	local strip = gcf(k, 522, 0)
	newPart(self.folder, Vector3.new(5, 0.12, 28), strip + Vector3.new(0, 0.06, 0), Color3.fromRGB(178, 150, 104), Enum.Material.Ground)
	self:zone(strip.Position, 16)
	table.insert(self.wear, { p = strip.Position, r = 16 })
	self:put("Wicket", gcf(k, 500, 0, "out"), 1)
	self:put("Wicket", gcf(k, 544, 0, "in"), 1)
	local batter = self:person({ scale = 0.66, hair = "Cap", moving = true })
	local bowler = self:person({ scale = 0.66, moving = true })
	local fielder = self:person({ scale = 0.66, moving = true })
	local keeper = self:person({ scale = 0.66, moving = true })
	if batter then self:hold(batter, "Bat") end
	local ball = newPart(self.peopleFolder, Vector3.one * 0.6, CFrame.new(), Color3.fromRGB(200, 40, 34), nil, Enum.PartType.Ball)
	local out = (at(600) - at(500)).Unit
	local fieldSpot = at(522, 20)
	local lastCatch = -1
	self:actor(strip.Position, function(t, parts, cfs)
		local u = t % 6
		-- the bowler: run in, bowl, walk back
		if bowler then
			local r = if u < 1.4 then 566 - u / 1.4 * 20 elseif u < 2.0 then 546 else 546 + (u - 2.0) / 4.0 * 20
			local p = at(r, 1.2)
			local facing = if u < 2.0 then -out else out
			local a = if u < 1.4 then walkPose(t * strideRate(14, 0.8, bowler.s), 0.8, bowler.s, 0.2)
				elseif u < 2.0 then { armR = math.pi * (u - 1.4) / 0.6 * 2, armL = 0.6, lean = 0.15 }
				else walkPose(t * strideRate(5, 0.45, bowler.s), 0.45, bowler.s)
			pose(bowler, CFrame.lookAt(p, p + facing), a, parts, cfs)
		end
		-- the batter: stance, then the swing
		if batter then
			local sw = math.clamp((u - 1.85) / 0.3, 0, 1)
			local a = { armR = -0.5 + sw * 2.4, armL = -0.3 + sw * 2.0, armRYaw = 0.5, armLYaw = 0.5, legL = 0.2, legR = -0.15, headYaw = 0.3 }
			a.hand = CFrame.Angles(-0.6 + sw * 0.4, 0, 0)
			local p = at(502, -0.6)
			pose(batter, CFrame.lookAt(p, p + out) * CFrame.Angles(0, -0.5, 0), a, parts, cfs)
		end
		if keeper then
			local p = at(496, 0)
			pose(keeper, CFrame.lookAt(p, p + out) * CFrame.new(0, -0.5, 0), { legL = 0.5, legR = 0.5, armL = 1.1, armR = 1.1, armLYaw = 0.4, armRYaw = 0.4 }, parts, cfs)
		end
		-- the fielder takes the catch
		if fielder then
			local reach = if u > 2.9 and u < 3.9 then 2.8 else 0.4
			local over = math.floor(t / 6)
			if u > 3.3 and over ~= lastCatch then
				lastCatch = over
				self:say(fielder, pick(self.rng, { "Howzat!", "Caught it!", "Out!", "Easy catch!" }))
			end
			pose(fielder, CFrame.lookAt(fieldSpot, at(502)), { armL = reach, armR = reach, legL = 0.1, legR = -0.1, headPitch = if u > 2.2 and u < 3.6 then 0.5 else 0 }, parts, cfs)
		end
		-- the ball: bowled with a bounce, struck up to the fielder, thrown back
		local bp: Vector3
		if u < 1.9 and u >= 1.4 then
			local q = (u - 1.4) / 0.5
			local a0, b0 = at(545, 1.2) + Vector3.new(0, 3.2, 0), at(502, -0.3) + Vector3.new(0, 1.4, 0)
			local bounce = 0.7
			bp = if q < bounce then a0:Lerp(at(510, 0), q / bounce) + Vector3.new(0, -3.2 * (q / bounce) ^ 2 + 0.3, 0)
				else at(510, 0):Lerp(b0, (q - bounce) / (1 - bounce)) + Vector3.new(0, math.sin((q - bounce) / (1 - bounce) * math.pi) * 1.2 + 0.3, 0)
		elseif u >= 1.9 and u < 3.3 then
			local q = (u - 1.9) / 1.4
			bp = (at(502, -0.3) + Vector3.new(0, 1.6, 0)):Lerp(fieldSpot + Vector3.new(0, 3.6, 0), q) + Vector3.new(0, math.sin(q * math.pi) * 14, 0)
		elseif u >= 3.3 and u < 4.6 then
			local q = (u - 3.3) / 1.3
			bp = (fieldSpot + Vector3.new(0, 3.4, 0)):Lerp(at(548, 1.2) + Vector3.new(0, 3, 0), q) + Vector3.new(0, math.sin(q * math.pi) * 5, 0)
		else
			bp = at(548 + math.min(18, (u - 4.6) * 14), 1.4) + Vector3.new(0, 2.6, 0)
		end
		table.insert(parts, ball)
		table.insert(cfs, CFrame.new(bp))
	end)
end

--==============================================================
-- the flower garden and kids playing tag
--==============================================================
function LobbyPark:garden()
	local k = 7
	local c = gcf(k, 515, 0)
	-- the spur ends in a little paved square between the benches
	-- (its paved square at the end of the spur went with the spur, 2026-10-24)
	for _, o in ipairs({ { -24, 10 }, { 24, 10 }, { 0, -16 } }) do
		self:put("FlowerBed", c * CFrame.new(o[1], 0, o[2]), 1, 5)
	end
	for _, h in ipairs({ { 0, 32, 0 }, { -40, 0, math.pi / 2 }, { 40, 0, math.pi / 2 } }) do
		for j = -1, 1 do
			local along = if h[3] == 0 then CFrame.new(h[1] + j * 8.2, 0, -h[2]) else CFrame.new(h[1], 0, -h[2] + j * 8.2)
			-- (2026-10-24: the leaf-carded hedge, trees3.hedge, once imported; the pack's blob till then)
			self:put(if Models.get("Nature/Hedge") then "Nature/Hedge" else "Hedge", c * along * CFrame.Angles(0, h[3], 0), 1, 5)
		end
	end
	-- (facing into the garden, not out at the plaza)
	self:bench(c * CFrame.new(-14, 0, 18), 2)
	self:bench(c * CFrame.new(14, 0, 18), 1)
	-- tag: three kids chasing round an open stretch of lawn
	local tagAt = gp(k, 548, -84)
	self:zone(tagAt, 18)
	local kids = { self:person({ scale = 0.6, moving = true }), self:person({ scale = 0.6, moving = true }), self:person({ scale = 0.6, moving = true }) }
	if self.counts.busy then table.insert(kids, self:person({ scale = 0.6, moving = true })) end
	local nextShout = 0
	self:actor(tagAt, function(t, parts, cfs)
		for i, kid in ipairs(kids) do
			if kid then
				local w = 0.55 + i * 0.04
				local a = t * w + i * 1.6
				local rx, rz = 13 + math.sin(t * 0.3 + i) * 3, 9
				local p = tagAt + Vector3.new(math.cos(a) * rx, 0, math.sin(a) * rz)
				local ahead = tagAt + Vector3.new(math.cos(a + 0.1) * rx, 0, math.sin(a + 0.1) * rz)
				local speed = w * (rx + rz) / 2
				pose(kid, CFrame.lookAt(p, ahead), walkPose(t * strideRate(speed, 0.75, kid.s) + i, 0.75, kid.s, 0.14), parts, cfs)
			end
		end
		if t > nextShout then
			nextShout = t + self.rng:NextNumber(7, 13)
			self:say(kids[self.rng:NextInteger(1, #kids)], pick(self.rng, { "You're it!", "Can't catch me!", "Not fair!", "Got you!" }))
		end
	end)
	self:kiteFlyer(k, 590, 70, 0.62, "KiteC")
end

--==============================================================
-- trees: the lobby trees dotted round the park, off everything else
--==============================================================
function LobbyPark:trees()
	local kinds = { "TreeNeem", "TreeMango2", "TreeApple", "TreeNeem", "TreeMango2", "TreeApple", "TreeAshoka" }
	local rng = self.rng
	local function plant(p: Vector3, scale: number)
		if self:clear(p, 6) then
			self:put("Nature/" .. kinds[rng:NextInteger(1, #kinds)], CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), scale, 9)
		end
	end
	for k = 0, 7 do
		-- a belt along the canal, so the lawn is framed in green: clumps of two to four with open
		-- stretches between (an even row reads as an orchard), and a few nearer the path
		local x = -125 + rng:NextNumber(0, 20)
		while x < 125 do
			local n = rng:NextInteger(2, 4)
			for i = 1, n do
				local xi = x + (i - 1) * rng:NextNumber(10, 14)
				if xi < 128 then plant(gp(k, rng:NextNumber(576, 600), xi), rng:NextNumber(0.9, 1.7)) end
			end
			x += (n - 1) * 12 + rng:NextNumber(30, 50)
		end
		for _, x0 in ipairs({ -108, -86, 86, 108 }) do
			plant(gp(k, 484 + rng:NextNumber(-6, 14), x0 + rng:NextNumber(-4, 4)), rng:NextNumber(1.0, 1.3))
		end
		-- (the ashoka avenue lined the inward spurs; with the smaller lobby those are gone, 2026-10-18)
		task.wait()
	end
end

--==============================================================
-- people standing about in twos and threes, chatting
--==============================================================
function LobbyPark:groups()
	local rng = self.rng
	for k = 0, 7 do
		for g = 1, (if self.counts.busy then 2 else 1) do
			local centre: Vector3? = nil
			for _ = 1, 12 do
				local half = (500 * math.pi / 8 - 60) * 0.85
				local p = gp(k, rng:NextNumber(470, 585), rng:NextNumber(-half, half))
				if self:clear(p, 6) then centre = p; break end
			end
			if centre then
				self:zone(centre, 4)
				local c: Vector3 = centre
				local n = rng:NextInteger(2, 3)
				local members, spots = {}, {}
				for i = 1, n do
					local who = self:person({ scale = if rng:NextNumber() < 0.2 then 0.66 else 1, phone = rng:NextNumber() < 0.12 })
					if who then
						local a = i / n * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
						table.insert(members, who)
						table.insert(spots, c + Vector3.new(math.cos(a), 0, math.sin(a)) * 2.7)
					end
				end
				if #members > 0 then
					local g = self:talker(members, c)
					self:prompt(g, members[1])
					for i, who in ipairs(members) do
						local p = spots[i]
						local root = CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z))
						local seed = rng:NextNumber(0, 6.28)
						self:actor(c, function(t, parts, cfs)
							local talking = g.speaker == i and t < g.speakUntil
							local a: any = { armR = 0.15, armL = 0.12, headPitch = if who.s < 0.9 then 0.25 else 0,
								bob = math.sin(t * 1.1 + seed) * 0.025, roll = math.sin(t * 0.25 + seed) * 0.03 }
							local facing = root
							if t < g.faceUntil then
								-- turned to you while they greet or answer you
								local ch = Players.LocalPlayer.Character
								local hrp = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
								if hrp then
									local d = flat(hrp.Position - p)
									if d.Magnitude > 0.5 then facing = CFrame.lookAt(p, p + d.Unit) end
								end
							end
							local skyYaw, skyPitch = self:skyLook(p, facing, t)
							if skyYaw then
								-- a shot in the air: everyone follows it, and the first one points
								a.headYaw, a.headPitch = skyYaw, skyPitch
								if i == 1 then a.armR, a.armRYaw = 2.3, -skyYaw * 0.4 end
							elseif t < g.faceUntil then
								-- (facing you, set above)
							elseif g.speaker > 0 and g.speaker ~= i and t < g.speakUntil then
								-- listening: look at whoever's talking
								local to = flat(spots[g.speaker] - p)
								local _, yaw = root:ToObjectSpace(CFrame.lookAt(p, p + to.Unit)):ToEulerAnglesYXZ()
								a.headYaw = math.clamp(yaw, -0.9, 0.9)
							else
								a.headYaw = math.sin(t * 0.3 + seed) * 0.3
							end
							if talking then
								-- a hand going as they talk
								a.armR = 0.7 + math.abs(math.sin(t * 4.2 + seed)) * 0.6
								a.armRYaw = 0.3
								a.headPitch = (a.headPitch or 0) + math.sin(t * 6) * 0.04
							elseif who.parts.Phone then
								a.armR, a.armRYaw, a.headPitch = 1.0, 0.35, -0.35
							end
							pose(who, facing, a, parts, cfs)
						end)
					end
				end
			end
		end
		task.wait()
	end
end

--==============================================================
-- strollers on the footpath
--==============================================================
function LobbyPark:walkers()
	local rng = self.rng
	local n = self.counts.walkers
	local i = 0
	while i < n do
		local dir = if rng:NextNumber() < 0.5 then 1 else -1
		local jogger = rng:NextNumber() < 0.2 -- a morning jogger, out on their own
		local speed = if jogger then rng:NextNumber(8, 9.5) else rng:NextNumber(3.4, 4.6)
		local a0 = rng:NextNumber(0, math.pi * 2)
		local group = if jogger then 1 elseif rng:NextNumber() < 0.3 then 2 else 1
		for g = 1, group do
			local kid = group == 2 and g == 2 and rng:NextNumber() < 0.5
			local who = self:person({ scale = if kid then 0.62 else 1, phone = not jogger and not kid and g == 1 and rng:NextNumber() < 0.3, moving = true })
			if who then
				-- lanes stay inside the kerbs (half-width 3.5): pairs walk side by side 1.7 apart
				local lane = dir * (if jogger then 2.2 elseif g == 2 then 2.6 else 0.9)
				local behind = (g - 1) * 0.3
				local s = who.s
				local amp = if jogger then 0.72 elseif kid then 0.5 else 0.42
				local stride = strideRate(speed, amp, s)
				local lean = if jogger then 0.16 else 0.05
				local seed = rng:NextNumber(0, 6.28)
				local act
				act = self:actor(CENTRE + Vector3.new(math.cos(a0), 0, math.sin(a0)) * PATH_R, function(t, parts, cfs)
					local ang = a0 + dir * (t * speed / PATH_R) - dir * behind / PATH_R
					local r = PATH_R + lane
					local p = CENTRE + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
					act.centre = p
					local tangent = Vector3.new(-math.sin(ang), 0, math.cos(ang)) * dir
					local a = walkPose(t * stride + seed, amp, s, lean)
					if jogger then a.armL, a.armR = 0.55 + a.armL * 0.8, 0.55 + a.armR * 0.8 end -- arms carried higher
					if who.parts.Phone then
						a.armR, a.armRYaw, a.headPitch = 1.2, 0.35, -0.4
						a.phone = CFrame.new(0.15 * s, 3.2 * s, -1.2 * s) * CFrame.Angles(-0.8, 0, 0)
					end
					pose(who, CFrame.lookAt(p, p + tangent), a, parts, cfs)
				end)
			end
			i += 1
		end
	end
end

--==============================================================
-- spectators filming the launches
--==============================================================
function LobbyPark:spectators()
	local rng = self.rng
	for k = 0, 7 do
		local a = k * math.pi / 4
		local line = Vector3.new(math.cos(a), 0, math.sin(a))
		local side = Vector3.new(-line.Z, 0, line.X)
		local cannon = CENTRE + line * 270
		for j = 1, self.counts.specs + (if k % 2 == 0 then 1 else 0) do
			local sgn = if (j + k) % 2 == 0 then 1 else -1
			local p = CENTRE + line * R(rng:NextNumber(398, 410)) + side * sgn * rng:NextNumber(52, 66)
			local who = self:person({ phone = true, scale = if rng:NextNumber() < 0.25 then 0.66 else 1 })
			if who then
				self:zone(p, 4)
				local s = who.s
				local plot = k + 1
				if not self.leads[plot] then self.leads[plot] = who end
				local idle = rng:NextNumber(0, 6.28)
				self:actor(p, function(t, parts, cfs)
					local since = t - (self.shots[plot] or -1e9)
					local target: Vector3
					local filming: boolean
					if since >= 0 and since < 4.5 then
						-- follow the shot: out along the line and up, then falling away
						local d = 40 + since * 150
						target = CENTRE + line * (270 + d) + Vector3.new(0, 30 + since * 70 - since * since * 9, 0)
						filming = true
					else
						target = cannon + Vector3.new(0, 10, 0)
						filming = math.sin(t * 0.12 + idle) > 0.6
					end
					local flatDir = flat(target - p)
					local face = if flatDir.Magnitude > 0.1 then flatDir.Unit else line
					local pitch = math.atan2(target.Y - (p.Y + 4.6 * s), flatDir.Magnitude)
					local a: any
					if filming then
						local up = math.clamp(pitch, -0.2, 1.2)
						a = { armL = 1.45 + up * 0.8, armR = 1.45 + up * 0.8, armLYaw = 0.45, armRYaw = 0.45, headPitch = up * 0.7 }
						a.phone = CFrame.new(0, (3.95 + up * 0.9) * s, -(1.55 - up * 0.3) * s) * CFrame.Angles(up, 0, 0)
					else
						a = { armR = 0.9, armRYaw = 0.35, armL = 0.1, headPitch = -0.35 + math.sin(t * 0.5 + idle) * 0.1 }
						a.phone = CFrame.new(0.2 * s, 2.95 * s, -1.15 * s) * CFrame.Angles(-0.7, 0, 0)
					end
					a.bob = math.sin(t * 1.3 + idle) * 0.03
					pose(who, CFrame.lookAt(p, p + face), a, parts, cfs)
				end)
			end
		end
	end
end

--==============================================================
-- critters (art/blender/critters.py): pigeons that scatter when you walk up, a dog by the chai stall
--==============================================================
-- (2026-10-24) the rock pigeon from hub props (TC_HubProps: slate grey, green neck sheen, black wing
-- bars, pink legs). Filed as Park/Pigeon with the RockPigeon attribute; until it's filed, it's built
-- from the import itself (Pigeon__Body / __WingL / __WingR), so the new bird shows either way
local rockPigeon: Model? = nil
local function pigeonTemplate(): Instance?
	local filed = Models.get("Park/Pigeon")
	if filed and filed:GetAttribute("RockPigeon") then return filed end
	if rockPigeon then return rockPigeon end
	local props = workspace:FindFirstChild("TC_HubProps")
	local body = props and props:FindFirstChild("Pigeon__Body")
	if body and body:IsA("BasePart") then
		local m = Instance.new("Model")
		m.Name = "Pigeon"
		for _, n in ipairs({ "Body", "WingL", "WingR" }) do
			local src = (props :: Instance):FindFirstChild("Pigeon__" .. n)
			if src then
				local c = src:Clone()
				c.Name = n
				c.Parent = m
			end
		end
		m:SetAttribute("RockPigeon", true)
		rockPigeon = m
		return m
	end
	return filed
end

-- a jointed critter: its parts with their rest frames (placed at the origin) and its hinge points
function LobbyPark:critter(name: string, scale: number): any
	local tpl = if name == "Pigeon" then pigeonTemplate() else Models.get("Park/" .. name)
	if not tpl then return nil end
	local rock = tpl:GetAttribute("RockPigeon") == true
	local m = Models.place(tpl, self.peopleFolder, CFrame.new(), scale)
	if rock then
		-- (stood on its feet: the bottom of the bird on the ground, its middle over the spot)
		local cf, size = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() + Vector3.new(-cf.Position.X, size.Y / 2 - cf.Position.Y, -cf.Position.Z))
	end
	local c = { parts = {}, rest = {}, s = scale }
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") then
			p.CastShadow = false
			p.CanCollide = false
			-- (2026-10-24, the owner: "darken all the birds")
			if name == "Pigeon" and not rock then
				-- (the 2026-10-24 textured pigeon takes its shade through its SurfaceAppearance, a touch darker)
				local sa = p:FindFirstChildOfClass("SurfaceAppearance")
				if sa then sa.Color = Color3.fromRGB(205, 205, 210) else p.Color = p.Color:Lerp(Color3.new(0, 0, 0), 0.4) end
			end
			c.parts[p.Name] = p
			c.rest[p.Name] = p.CFrame
		end
	end
	return c
end

function LobbyPark:flock(centre: Vector3, n: number, spread: number)
	local rng = self.rng
	local birds = {}
	-- somewhere to land (well away from whoever scared them, so they don't go straight back up)
	local function spot(avoid: Vector3?): Vector3
		for _ = 1, 12 do
			local a, r = rng:NextNumber(0, 6.28), rng:NextNumber(2, spread)
			local p = centre + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local far = not avoid or (flat(p) - flat(avoid)).Magnitude > 16
			if far and (self:clear(p, 0) or math.abs((flat(p) - CENTRE).Magnitude - PATH_R) < PATH_W) then return p end
		end
		return centre
	end
	for i = 1, n do
		-- (2026-10-24) hub pack 6's pigeon is bigger at the same scale: 1.15 keeps it pigeon-sized
		local b = self:critter("Pigeon", 1.15)
		if not b then return end
		b.pos, b.heading = spot(), rng:NextNumber(0, 6.28)
		b.state, b.calm, b.seed = "ground", 0, rng:NextNumber(0, 6.28)
		table.insert(birds, b)
	end
	-- each wing hinges at its own top inner edge, and lifts away from the body on its own side
	local function hinge(b, name: string): (Vector3, number)
		local w, body = b.rest[name], b.rest.Body
		local side = if w.Position.X < body.Position.X then -1 else 1
		local sz = b.parts[name].Size
		return w.Position + Vector3.new(-side * sz.X / 2, sz.Y / 2, 0), side
	end
	self:actor(centre, function(t, parts, cfs)
		local ch = Players.LocalPlayer.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		local scare = false
		if hrp then
			for _, b in ipairs(birds) do
				if b.state == "ground" and t > b.calm and (flat(hrp.Position) - flat(b.pos)).Magnitude < 10 then scare = true; break end
			end
		end
		for _, b in ipairs(birds) do
			if scare and b.state == "ground" then
				-- the whole flock goes up together, each to its own landing spot
				b.state, b.t0, b.from, b.to = "fly", t + rng:NextNumber(0, 0.3), b.pos, spot(hrp and hrp.Position)
				b.dur = rng:NextNumber(2.4, 3.4)
			end
			local root: CFrame
			local flap = 0
			if b.state == "fly" then
				local u = math.clamp((t - b.t0) / b.dur, 0, 1)
				local p = b.from:Lerp(b.to, u) + Vector3.new(0, math.sin(u * math.pi) * 14 + u * (1 - u) * 6, 0)
				local d = flat(b.to - b.from)
				if d.Magnitude > 0.1 then b.heading = math.atan2(-d.X, -d.Z) end
				root = CFrame.new(p) * CFrame.Angles(0, b.heading, 0) * CFrame.Angles(-0.25 * (1 - u), 0, 0)
				flap = math.sin(t * 28 + b.seed) * 1.1
				if u >= 1 then b.state, b.pos, b.calm = "ground", b.to, t + 3 end
			else
				-- pecking about: quick dips of the head, the odd little hop and turn
				local peck = math.max(0, math.sin(t * 5 + b.seed)) ^ 6 * 0.5
				local hop = math.max(0, math.sin(t * 0.9 + b.seed * 2))
				if hop > 0.995 then
					b.heading += rng:NextNumber(-1, 1)
					b.pos += Vector3.new(-math.sin(b.heading), 0, -math.cos(b.heading)) * 0.25
				end
				root = CFrame.new(b.pos) * CFrame.Angles(0, b.heading, 0) * CFrame.Angles(-peck, 0, 0)
			end
			table.insert(parts, b.parts.Body)
			table.insert(cfs, root * b.rest.Body)
			for _, wn in ipairs({ "WingL", "WingR" }) do
				if b.parts[wn] then
					local j, side = hinge(b, wn)
					table.insert(parts, b.parts[wn])
					table.insert(cfs, root * CFrame.new(j) * CFrame.Angles(0, 0, side * flap) * CFrame.new(-j) * b.rest[wn])
				end
			end
		end
	end)
end

function LobbyPark:critters()
	if not pigeonTemplate() then return end
	-- the hub's centre: a flock pecking about on the plaza's rangoli ring round the trophy pillar
	-- (clear of the benches and planters at 40 studs, across from the spawn)
	local PLAZA_TOP = 2
	local function plaza(deg: number, r: number): Vector3
		local a = math.rad(deg)
		return Vector3.new(CENTRE.X + math.cos(a) * r, PLAZA_TOP, CENTRE.Z + math.sin(a) * r)
	end
	self:flock(plaza(-45, 28), if self.counts.busy then 7 else 5, 6)
	if self.counts.busy then self:flock(plaza(200, 27), 5, 5) end
	if self.counts.busy then
		self:flock(gp(3, 500, -26), 8, 12) -- by the fountain's benches
		self:flock(gp(0, 470, 30), 6, 10)  -- on the path by the big pond
		self:flock(gp(5, 505, -20), 5, 9)  -- by the banyan's picnic
	else
		self:flock(gp(3, 500, -26), 5, 10)
	end
	-- a street dog asleep beside the chai stall, its tail thumping (faster when you come close)
	local stall = self:stallFrame()
	local dog = self:critter("Dog", 2)
	if dog then
		-- in the cart's shade beside its wheel, as street dogs sleep, clear of the customers
		local cf = stall * CFrame.new(-6.5, 0, 2.5) * CFrame.Angles(0, 1.4, 0)
		-- (2026-10-24) hub pack 6's dog: the tail wags from its own root (the end nearest the body), and it
		-- casts a shadow so it lies on the grass instead of floating over it
		local jT = toModel(Vector3.new(-0.25, -1.4, 0.55), 2)
		if dog.parts.Tail and dog.parts.Body then
			local tr, br = dog.rest.Tail.Position, dog.rest.Body.Position
			local d = Vector3.new(br.X - tr.X, 0, br.Z - tr.Z)
			if d.Magnitude > 0.01 then
				local t = dog.parts.Tail.Size
				jT = tr + d.Unit * 0.45 * math.max(t.X, t.Z)
			end
		end
		for _, p in pairs(dog.parts) do p.CastShadow = true end
		self:zone(cf.Position, 4)
		self:actor(cf.Position, function(t, parts, cfs)
			local ch = Players.LocalPlayer.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
			local near = hrp and (flat(hrp.Position) - flat(cf.Position)).Magnitude < 12
			local wag = if near then math.sin(t * 16) * 0.6 else math.sin(t * 2.2) * 0.25
			local breathe = CFrame.new(0, math.sin(t * 1.4) * 0.04, 0)
			table.insert(parts, dog.parts.Body)
			table.insert(cfs, cf * breathe * dog.rest.Body)
			if dog.parts.Tail then
				table.insert(parts, dog.parts.Tail)
				table.insert(cfs, cf * CFrame.new(jT) * CFrame.Angles(0, wag, 0) * CFrame.new(-jT) * dog.rest.Tail)
			end
		end)
	end
end

-- every shot anyone fires (a run's launch or a yard's auto-cannon) turns that yard's spectators
function LobbyPark:listen()
	local root = ReplicatedStorage:FindFirstChild("TyreCannon")
	local remotes = root and root:FindFirstChild("Remotes")
	if not remotes then return end
	-- (the launch remotes live in Remotes.V2, as LaunchArcs uses them; plot i stands at (i - 1) * 45 degrees)
	local v2 = remotes:WaitForChild("V2", 20) or remotes
	local launched = v2:WaitForChild("Launched", 20)
	local auto = v2:WaitForChild("AutoFire", 20)
	if self.dead then return end
	-- your best going up while you were out on a run: the park will mention it
	task.spawn(function()
		local ls = Players.LocalPlayer:WaitForChild("leaderstats", 60)
		local best = ls and ls:WaitForChild("Best", 30)
		if best and best:IsA("IntValue") and not self.dead then
			local last = best.Value
			table.insert(self.conns, best.Changed:Connect(function(v)
				if v > last and last > 0 then self.newBest = workspace:GetServerTimeNow() end
				last = v
			end))
		end
	end)
	if launched and launched:IsA("RemoteEvent") then
		table.insert(self.conns, launched.OnClientEvent:Connect(function(userId: number, plotIndex: number?)
			if not plotIndex then return end
			self.shots[plotIndex] = workspace:GetServerTimeNow() + 0.6
			self:shotFrom(plotIndex)
			-- the yard's first spectator calls out who's launching
			local plr = Players:GetPlayerByUserId(userId)
			local lead = self.leads[plotIndex]
			if plr and lead then
				task.delay(0.7, function()
					self:say(lead, fill(CHEERS[self.rng:NextInteger(1, #CHEERS)], { p = plr.DisplayName }))
				end)
			end
		end))
	end
	if auto and auto:IsA("RemoteEvent") then
		table.insert(self.conns, auto.OnClientEvent:Connect(function(plotIndex: number?)
			if plotIndex then
				self.shots[plotIndex] = workspace:GetServerTimeNow() + 0.6
				self:shotFrom(plotIndex)
			end
		end))
	end
end

-- a shot from yard `plot`: the people near it look up and follow it, and someone says so
function LobbyPark:shotFrom(plot: number)
	local a = (plot - 1) * math.pi / 4
	local line = Vector3.new(math.cos(a), 0, math.sin(a))
	local from = CENTRE + line * 270
	local t = workspace:GetServerTimeNow() + 0.6
	self.lastShot = { from = from, line = line, t = t }
	if t - self.lastWhoa < 8 then return end
	local near, nd = nil, 260
	for _, g in ipairs(self.talkers) do
		local d = (flat(g.centre) - flat(from)).Magnitude
		if d < nd then near, nd = g, d end
	end
	if near then
		self.lastWhoa = t
		task.delay(1.4, function()
			self:say(near.members[self.rng:NextInteger(1, #near.members)], WHOA[self.rng:NextInteger(1, #WHOA)])
		end)
	end
end

-- where a group member should look while a shot is in the air (nil when there's none near)
function LobbyPark:skyLook(p: Vector3, facing: CFrame, t: number): (number?, number?)
	local shot = self.lastShot
	if not shot then return nil end
	local age = t - shot.t
	if age < 0 or age > 3.4 or (flat(p) - flat(shot.from)).Magnitude > 280 then return nil end
	local sky = shot.from + shot.line * (40 + age * 150) + Vector3.new(0, 30 + age * 70 - age * age * 9, 0)
	local d = sky - p
	local fd = flat(d)
	if fd.Magnitude < 1 then return nil end
	local _, yaw = facing:ToObjectSpace(CFrame.lookAt(p, p + fd.Unit)):ToEulerAnglesYXZ()
	return math.clamp(yaw, -1.2, 1.2), math.clamp(math.atan2(d.Y, fd.Magnitude), 0, 0.95)
end

--==============================================================
function LobbyPark:step(t: number)
	self.frame += 1
	if self.frame % 120 == 0 then self:nightCheck() end
	if not self.folder:IsDescendantOf(workspace) then return end
	local cam = workspace.CurrentCamera
	local camCF = cam and cam.CFrame or CFrame.new(CENTRE)
	local camPos, look = camCF.Position, camCF.LookVector
	-- the same two lists every frame (cleared, not rebuilt)
	local parts, cfs = self.parts, self.cfs
	table.clear(parts)
	table.clear(cfs)
	for _, a in ipairs(self.actors) do
		-- close by: every frame; middle distance: every other frame; far off or behind you: every sixth
		local off = a.centre - camPos
		local d = off.Magnitude
		local every = if d < 160 then 1 elseif d > 420 or off:Dot(look) < -60 then 6 else 2
		if every == 1 or (self.frame + a.phase) % every == 0 then
			a.update(t, parts, cfs)
		end
	end
	if #parts > 0 then workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
	if self.frame % 10 == 0 then self:chatter(t) end
	-- splashes
	for i = #self.fx, 1, -1 do
		local fx = self.fx[i]
		local age = t - fx.t0
		if fx.kind == "ring" then
			local d = 1.2 + age * 9
			fx.part.Size = Vector3.new(0.12, d, d)
			fx.part.Transparency = math.min(1, 0.15 + age * 1.4)
			if age > 0.65 then fx.part:Destroy(); table.remove(self.fx, i) end
		else
			local p = fx.at + fx.v * age + Vector3.new(0, -32 * age * age, 0)
			fx.part.CFrame = CFrame.new(p)
			if age > 0.8 or p.Y < fx.at.Y - 0.3 then fx.part:Destroy(); table.remove(self.fx, i) end
		end
	end
end

function LobbyPark:destroy()
	self.dead = true
	for _, c in ipairs(self.conns or {}) do c:Disconnect() end
	self.folder:Destroy()
end

return LobbyPark
