--!strict
-- TYRE CANNON :: WindFX
-- Speed lines from the wind pack (Assets.VFX.WindLight / WindSmall / WindSharp).
-- Each layer is a pair of crossed beams either side of the tyre, copied from
-- the pack's own beam settings. Faster tiers switch more layers on and the
-- texture scrolls with your speed. Tier thresholds: Config.Wind.Tiers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))
local Assets = Root:WaitForChild("Assets")
local VFX = require(script.Parent.VFX)

local WindFX = {}
WindFX.__index = WindFX

-- ahead/behind along travel, height above the hub, distance out to the side
local LAYERS = {
	{ tier = 1, style = "WindLight", ahead = 5, behind = 28, y = 1.0, z = 6.5, width = 0.35 },
	{ tier = 2, style = "WindSmall", ahead = 3, behind = 32, y = 5.5, z = 4.0, width = 1.1 },
	{ tier = 3, style = "WindSharp", ahead = 9, behind = 40, y = 3.0, z = 8.5, width = 0.6 },
	{ tier = 4, style = "WindLight", ahead = 12, behind = 46, y = 8.0, z = 11.0, width = 0.5 },
}

local function styleBeam(name: string): Beam?
	local vfx = Assets:FindFirstChild("VFX")
	local src = vfx and vfx:FindFirstChild(name)
	return src and src:FindFirstChildWhichIsA("Beam", true) :: Beam?
end

function WindFX.new(folder: Instance)
	local self = setmetatable({}, WindFX)
	self.folder = folder
	self.tier = 0
	self.layers = {}

	local anchor = Instance.new("Part")
	anchor.Name = "WindAnchor"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = folder
	self.anchor = anchor

	for _, layer in ipairs(LAYERS) do
		local src = styleBeam(layer.style)
		if src then
			local beams = {}
			for _, side in ipairs({ -1, 1 }) do
				for _, twist in ipairs({ 0, math.pi / 2 }) do
					local a0 = Instance.new("Attachment")
					a0.CFrame = CFrame.new(layer.ahead, layer.y, side * layer.z) * CFrame.Angles(twist, 0, 0)
					a0.Parent = anchor
					local a1 = Instance.new("Attachment")
					a1.CFrame = CFrame.new(-layer.behind, layer.y * 0.6, side * layer.z * 1.3) * CFrame.Angles(twist, 0, 0)
					a1.Parent = anchor
					local b = src:Clone()
					b.Attachment0 = a0
					b.Attachment1 = a1
					b.Width0 *= layer.width
					b.Width1 *= layer.width
					b.CurveSize0 *= side
					b.Enabled = false
					b.Parent = anchor
					table.insert(beams, { beam = b, speed = src.TextureSpeed })
				end
			end
			table.insert(self.layers, { tier = layer.tier, beams = beams })
		end
	end
	return self
end

-- returns the current tier (0..4)
function WindFX:update(position: Vector3, yaw: number, speed: number): number
	self.anchor.CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local tier = 0
	for i, v in ipairs(Config.Wind.Tiers) do
		if speed >= v then tier = i end
	end
	if tier == 4 and self.tier < 4 then
		VFX.emit("CheckpointShock", CFrame.new(position), { scale = 0.6 })
	end
	self.tier = tier
	local scroll = math.clamp(speed / 600, 0.4, 3)
	for _, layer in ipairs(self.layers) do
		local on = tier >= layer.tier
		for _, b in ipairs(layer.beams) do
			b.beam.Enabled = on
			b.beam.TextureSpeed = b.speed * scroll
		end
	end
	return tier
end

function WindFX:destroy()
	if self.anchor then self.anchor:Destroy() end
	self.anchor = nil
end

return WindFX
