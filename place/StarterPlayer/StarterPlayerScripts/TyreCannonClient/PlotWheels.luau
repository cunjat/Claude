--!strict
-- TYRE CANNON :: PlotWheels
-- Every plot shows its owner's real wheel: tyre, hub, rim and stickers. Also
-- repaints the rig for the owner's engine and paint, and matches the lever
-- grip to the tyre.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)
local WheelAssembly = require(Modules:WaitForChild("WheelAssembly"))

local PlotWheels = {}
PlotWheels.__index = PlotWheels

local TYRE_LOCAL = Vector3.new(19.5, 6.2, 0)
local DIAMETER = 7.8
PlotWheels.TyreLocal = TYRE_LOCAL
PlotWheels.Diameter = DIAMETER

function PlotWheels.new(plots: Instance)
	local self = setmetatable({}, PlotWheels)
	self.plots = plots
	self.state = {}
	self.wheels = {}
	self.paused = false
	for _, plot in ipairs(plots:GetChildren()) do
		local i = plot:GetAttribute("Index")
		if i then self:rebuild(plot, i, {}) end
	end
	return self
end

function PlotWheels:rebuild(plot: Instance, index: number, info)
	local holder = plot:FindFirstChild("LaunchTyre")
	local base = plot:GetAttribute("BaseCFrame")
	if not holder or not base then return end
	for _, c in ipairs(holder:GetChildren()) do c:Destroy() end
	-- (2026-10-24, the owner) a yard nobody has holds no tyre: everyone's given a yard as they join
	if not info.userId then
		self.wheels[index] = nil
		return nil
	end
	local wheel = WheelAssembly.build(holder, {
		diameter = DIAMETER,
		skin = info.skin or "stock",
		rim = info.rim or "steel",
		stickers = info.stickers,
	})
	wheel:PivotTo(base * CFrame.new(TYRE_LOCAL))
	self.wheels[index] = wheel
	return wheel
end

-- the lever grip wears the tyre's rubber
function PlotWheels:dressLever(plot: Instance, skinId: string)
	local lc = plot:FindFirstChild("LaunchControl")
	local lever = lc and lc:FindFirstChild("Lever")
	local grip = lever and lever:FindFirstChild("Lever") :: BasePart?
	if not grip then return end
	local skin = Config.SkinsById[skinId] or Config.SkinsById.stock
	pcall(function() (grip :: any).UsePartColor = true end)
	grip.Color = skin.tyre
	grip.Material = skin.material
	grip.Reflectance = skin.reflect or 0
end

function PlotWheels:dressRig(plot: Instance, generatorId: string, rigSkinId: string)
	local rig = plot:FindFirstChild("LauncherRig")
	if not rig then return end
	local gen = Config.GeneratorsById[generatorId] or Config.GeneratorsById.field
	local fin = Config.RigSkinsById[rigSkinId] or Config.RigSkinsById.works
	local body = gen.body
	if fin.tint and (fin.tintStrength or 0) > 0 then body = body:Lerp(fin.tint, fin.tintStrength) end
	for _, p in ipairs(rig:GetDescendants()) do
		if p:IsA("BasePart") then
			local n = p.Name
			if n == "EngineBase" or n == "EngineBlock" or n == "Head" then
				p.Color = body
				p.Material = fin.glow and Enum.Material.Neon or Enum.Material.Metal
			elseif n == "RockerCover" or n == "Hopper" then
				p.Color = body:Lerp(Color3.new(0, 0, 0), 0.22)
			elseif n == "FuelTank" then
				p.Color = gen.trim
			elseif n == "Flywheel" then
				p.Color = gen.neon and gen.flywheel:Lerp(Color3.new(0, 0, 0), 0.62) or gen.flywheel
				p.Material = Enum.Material.Metal
			elseif n == "FlyHub" or n == "Spoke" then
				p.Color = (n == "Spoke") and gen.flywheel:Lerp(Color3.new(1, 1, 1), 0.15) or gen.flywheel
				p.Material = gen.neon and Enum.Material.Neon or Enum.Material.Metal
			end
		end
	end
	-- the engine model: parts tagged Paint = body / trim / glow take the engine's colours
	for _, p in ipairs(rig:GetDescendants()) do
		if p:IsA("BasePart") then
			local paint = p:GetAttribute("Paint")
			if paint == "body" then
				p.Color = body
			elseif paint == "trim" then
				p.Color = gen.trim
			elseif paint == "glow" then
				p.Color = gen.trim
				p.Material = gen.neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
			end
		end
	end
	local fly = rig:FindFirstChild("Flywheel") :: BasePart?
	if fly then
		local d = 11.4 * (1 + (gen.tier - 1) * 0.09)
		fly.Size = Vector3.new(1.6 + (gen.tier - 1) * 0.18, d, d)
	end
end

function PlotWheels:apply(snapshot)
	-- no rebuilding the yard wheels while the workbench is open (every sticker save
	-- would rebuild your yard tyre's meshes behind the scenes)
	if self.paused then
		self.pendingSnapshot = snapshot
		return
	end
	for _, plot in ipairs(self.plots:GetChildren()) do
		local i = plot:GetAttribute("Index")
		if i then
			local info = snapshot and snapshot[i]
			if type(info) ~= "table" then info = {} end
			local stickerKey = ""
			if type(info.stickers) == "table" and #info.stickers > 0 then
				local ok, json = pcall(function() return HttpService:JSONEncode(info.stickers) end)
				stickerKey = ok and json or ""
			end
			local key = table.concat({ tostring(info.userId), info.skin or "stock", info.rim or "steel", info.generator or "field", info.rigSkin or "works", stickerKey }, "|")
			if self.state[i] ~= key then
				self.state[i] = key
				self:rebuild(plot, i, info)
				self:dressRig(plot, info.generator or "field", info.rigSkin or "works")
				self:dressLever(plot, info.skin or "stock")
			end
		end
	end
end

function PlotWheels:setPaused(on: boolean)
	self.paused = on
	if not on and self.pendingSnapshot then
		local s = self.pendingSnapshot
		self.pendingSnapshot = nil
		self:apply(s)
	end
end

function PlotWheels:wheelFor(index: number)
	return self.wheels[index]
end

return PlotWheels
