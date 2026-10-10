--!strict
-- TYRE CANNON :: Rivals (v3)
-- The other racers in a Heat, drawn into your run: each one a tyre on its own line just beyond
-- yours (further from the camera), riding the same seeded road at the distance and height the
-- server last heard from them, eased between updates, with their name over it. Your own position
-- goes up four times a second so they can see you.
--   local r = Rivals.start(sim, remotes) ... r:stop()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Game = require(Modules.Game)
local TyreLook = require(script.Parent.TyreLook)

local Rivals = {}
Rivals.__index = Rivals

local R = Game.TyreRadius

function Rivals.start(sim, remotes: Instance)
	local self = setmetatable({}, Rivals)
	self.sim = sim
	self.nodes = {} :: { [string]: any }
	self.lane = 0
	local me = tostring(Players.LocalPlayer.UserId)
	local pos = remotes:FindFirstChild("HeatPos") :: UnreliableRemoteEvent?
	local riv = remotes:FindFirstChild("HeatRivals") :: UnreliableRemoteEvent?
	if riv then
		self.conn = riv.OnClientEvent:Connect(function(snap)
			if type(snap) ~= "table" then return end
			for uid, e in pairs(snap) do
				if uid ~= me and type(e) == "table" then self:seen(uid, tonumber(e[1]) or 0, tonumber(e[2]) or 0, tostring(e[3] or "")) end
			end
		end)
	end
	local acc = 0
	self.step = RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if pos and acc >= 0.25 and not sim.finished then
			acc = 0
			pos:FireServer(sim.x * Game.StudsToMetres, sim.y - sim.track:heightAt(sim.x) - R)
		end
		for _, n in pairs(self.nodes) do
			-- ease toward where they were heard, and keep rolling forward between updates
			n.x += (n.tx - n.x) * math.min(1, dt * 6)
			n.a += (n.ta - n.a) * math.min(1, dt * 8)
			local y = sim.track:heightAt(n.x) + R + math.max(0, n.a)
			n.roll -= dt * 9
			n.model:PivotTo(CFrame.new(n.x, y, n.z) * CFrame.Angles(0, 0, n.roll))
		end
	end)
	return self
end

function Rivals:seen(uid: string, metres: number, alt: number, name: string)
	local n = self.nodes[uid]
	local x = metres / Game.StudsToMetres
	if not n then
		self.lane += 1
		local model = TyreLook.model("baldspare", R * 2, "Rival_" .. uid)
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
			end
		end
		model.Parent = self.sim.folder
		local hl = Instance.new("Highlight")
		hl.FillColor = Color3.fromRGB(120, 200, 255)
		hl.FillTransparency = 0.75
		hl.OutlineColor = Color3.fromRGB(200, 236, 255)
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
		local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if root then
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(150, 26)
			bb.StudsOffsetWorldSpace = Vector3.new(0, R + 3, 0)
			bb.AlwaysOnTop = true
			bb.LightInfluence = 0
			bb.MaxDistance = 1200
			bb.Parent = root
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
			l.TextScaled = true
			l.TextColor3 = Color3.fromRGB(200, 236, 255)
			l.Text = name
			l.Parent = bb
			local s = Instance.new("UIStroke")
			s.Thickness = 2
			s.Parent = l
		end
		-- each rival on its own line beyond yours
		n = { model = model, x = x, tx = x, a = alt, ta = alt, roll = 0, z = -14 - (self.lane - 1) * 11 }
		self.nodes[uid] = n
	end
	n.tx, n.ta = x, alt
end

function Rivals:stop()
	if self.conn then self.conn:Disconnect() end
	if self.step then self.step:Disconnect() end
	for _, n in pairs(self.nodes) do n.model:Destroy() end
	self.nodes = {}
end

return Rivals
