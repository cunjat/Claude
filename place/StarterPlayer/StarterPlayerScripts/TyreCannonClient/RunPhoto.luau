--!strict
-- TYRE CANNON :: RunPhoto
-- Rebuilds the top of a run's biggest jump as a still: the same stretch of road from
-- the run's own seed, the tyre in the air at the angle it had, its shadow on the
-- ground and a few speed lines. No filters, no stickers, no captions shouting at you:
-- just where it was, how far and how high.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)
local TrackGen = require(Modules.TrackGen)
local WheelAssembly = require(Modules.WheelAssembly)

local RunPhoto = {}
local WorldView = require(script.Parent:WaitForChild("WorldView"))

local R = Config.Physics.TyreRadius

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, transparency: number?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

-- builds the scene into a ViewportFrame sized by the caller
function RunPhoto.render(vpf: ViewportFrame, photo)
	local cfg = Config.TracksById[photo.track]
	if not cfg then return end
	local track = TrackGen.get(photo.track)
	local tier = Config.TierAt(photo.x or 0)
	local band = Config.BandFor(cfg, tier)

	-- sample the ground under this run's seed, then hand the track its old seed back
	local oldSeed, oldLuck, oldRate = track.runSeed, track.luck, track.toolboxRate
	track:setRun(photo.seed or cfg.seed)
	local x0 = photo.x or 0
	local groundAt = track:heightAt(math.max(0, x0))
	local alt0 = math.max(0, (photo.y or groundAt) - groundAt)
	-- the higher the jump, the more road the shot needs
	local reach = math.max(320, alt0 * 2.6)
	local step = reach / 22
	local heights = {}
	for i = -22, 14 do
		local x = x0 + i * step
		heights[i] = track:heightAt(math.max(0, x))
	end
	if oldSeed then track:setRun(oldSeed, oldLuck, oldRate) end

	-- the sky behind it: deeper overhead, fading to the haze at the horizon
	vpf.BackgroundColor3 = band.fog
	local holder = vpf.Parent
	if holder and not holder:FindFirstChild("PhotoSky") then
		local sky = Instance.new("Frame")
		sky.Name = "PhotoSky"
		sky.BorderSizePixel = 0
		sky.BackgroundColor3 = Color3.new(1, 1, 1)
		sky.AnchorPoint = vpf.AnchorPoint
		sky.Position = vpf.Position
		sky.Size = vpf.Size
		sky.ZIndex = math.max(vpf.ZIndex - 1, 0)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, band.fog:Lerp(Color3.fromRGB(78, 132, 196), 0.62)),
			ColorSequenceKeypoint.new(0.55, band.fog:Lerp(Color3.fromRGB(150, 186, 222), 0.3)),
			ColorSequenceKeypoint.new(1, band.fog),
		})
		g.Parent = sky
		sky.Parent = holder
		vpf.BackgroundTransparency = 1
	end
	vpf.Ambient = cfg.ambient or Color3.fromRGB(130, 126, 118)
	vpf.LightColor = Color3.fromRGB(255, 240, 220)
	vpf.LightDirection = Vector3.new(0.35, -0.8, -0.45)
	local world = Instance.new("WorldModel")
	world.Parent = vpf

	-- the real road around the moment, built from the run's own seed: ground, verges, props,
	-- trees and obstacles, as they were
	local built = pcall(function()
		track:setRun(photo.seed or cfg.seed)
		local view = WorldView.new(photo.track, world, { scenery = true })
		view:buildRange(x0 + (-22) * step, x0 + 14 * step)
	end)
	if oldSeed then track:setRun(oldSeed, oldLuck, oldRate) end
	-- the land carries on past what was built, out to the horizon
	local lowest = groundAt
	for _, h in pairs(heights) do lowest = math.min(lowest, h) end
	part(world, Vector3.new(9000, 2, 9000), CFrame.new(x0, lowest - 7, 0), band.ground:Lerp(band.fog, 0.4), Enum.Material.SmoothPlastic)
	if not built then
		-- fall back to plain slabs
		for i = -22, 13 do
			local xa, xb = x0 + i * step, x0 + (i + 1) * step
			local ya, yb = heights[i], heights[i + 1]
			local a, b = Vector3.new(xa, ya, 0), Vector3.new(xb, yb, 0)
			local mid = (a + b) / 2
			local len = (b - a).Magnitude + 0.4
			local cf = CFrame.lookAt(mid, b) * CFrame.new(0, -3, 0)
			part(world, Vector3.new(math.max(260, reach * 1.4), 6, len), cf, band.ground, cfg.groundMaterial or Enum.Material.Ground)
		end
	end

	-- the tyre, rolled to the angle it had
	local pos = Vector3.new(x0, photo.y or (groundAt + 40), photo.z or 0)
	local wheel = WheelAssembly.build(nil, { diameter = R * 2, skin = photo.skin or "stock", rim = photo.rim or "steel", detail = "low" })
	for _, d in ipairs(wheel:GetDescendants()) do
		if d:IsA("Light") then d:Destroy() end
	end
	wheel.Parent = world
	local vx, vy = photo.vx or 400, photo.vy or 0
	local yaw = 0
	wheel:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, -(photo.roll or 0)))

	-- its shadow, softer the higher it was
	local alt = pos.Y - groundAt
	local spread = R * 2 * (1 + math.clamp(alt / 120, 0, 1.2))
	part(world, Vector3.new(0.2, spread, spread), CFrame.new(x0, groundAt + 0.2, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, math.clamp(0.55 + alt / 300, 0.55, 0.85)).Shape = Enum.PartType.Cylinder

	-- speed lines trailing back along the way it was travelling
	local dir = Vector3.new(vx, vy, 0)
	if dir.Magnitude > 1 then
		dir = dir.Unit
		local speed = math.sqrt(vx * vx + vy * vy)
		local length = math.clamp(speed / 14, 12, 90)
		for i, off in ipairs({ R * 0.8, -R * 0.2, -R * 0.9 }) do
			local side = Vector3.new(-dir.Y, dir.X, 0) * off
			local startP = pos + side - dir * (R * 1.3)
			local endP = startP - dir * (length * (1 - i * 0.18))
			part(world, Vector3.new(0.35, 0.35, (endP - startP).Magnitude), CFrame.lookAt((startP + endP) / 2, endP),
				Color3.fromRGB(245, 245, 240), Enum.Material.SmoothPlastic, 0.45 + i * 0.1)
		end
	end

	-- shot the way a trackside photographer would catch it: close enough that the tyre is the
	-- subject, a little below it so it sits against the sky, the land falling away underneath
	local cam = Instance.new("Camera")
	cam.FieldOfView = 56
	local distance = R * 5.4 + math.clamp(alt, 0, 120) * 0.1
	local lift = math.clamp(alt * 0.1, 2, 10)
	local eye = pos + Vector3.new(-0.5, 0, 0.86).Unit * distance - Vector3.new(0, lift, 0)
	eye = Vector3.new(eye.X, math.max(eye.Y, groundAt + R * 0.7), eye.Z)
	local look = pos + Vector3.new(R * 1.8, -math.clamp(alt * 0.1, R * 0.3, R * 1.6), 0)
	cam.CFrame = CFrame.lookAt(eye, look)
	cam.Parent = vpf
	vpf.CurrentCamera = cam
end

-- the caption: plain facts
function RunPhoto.caption(photo): (string, string)
	local cfg = Config.TracksById[photo.track]
	local top = ("%s M  ·  %s"):format(tostring(math.floor(photo.metres or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""), string.upper(cfg and cfg.name or "THE ROAD"))
	local bottom = ("%.1f S IN THE AIR  ·  %d STUDS/S"):format(photo.air or 0, math.floor(photo.speed or 0))
	return top, bottom
end

return RunPhoto
