--!strict
-- TrophySpin: turns the top of the lobby's Trophy Pillar (the chrome tyre, laurels and crown) slowly round,
-- on this client only. The server builds the pillar (TyreCannonServer.TrophyPillar) and never moves it.
local RunService = game:GetService("RunService")

local PERIOD = 40 -- seconds per turn
local NEAR = 900 -- studs: stop turning when the camera is further than this

local top: Model? = nil
local rest: CFrame? = nil

local function find()
	local lobby = workspace:FindFirstChild("Lobby")
	local pillar = lobby and lobby:FindFirstChild("TrophyPillar")
	local m = pillar and pillar:FindFirstChild("Top")
	if m and m:IsA("Model") and m.PrimaryPart then
		top = m
		rest = m:GetPivot()
	end
end

local t0 = os.clock()
RunService.RenderStepped:Connect(function()
	if not top or not top.Parent or not top.PrimaryPart then
		top = nil
		if os.clock() - t0 > 2 then
			t0 = os.clock()
			find()
		end
		return
	end
	local base = rest :: CFrame
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - base.Position).Magnitude > NEAR then return end
	local yaw = (os.clock() % PERIOD) / PERIOD * math.pi * 2
	top:PivotTo(CFrame.new(base.Position) * CFrame.Angles(0, yaw, 0) * base.Rotation)
end)
