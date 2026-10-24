--Made by Shea from RTWS on YouTube - If you haven't already, make sure to check out my tutorial on NPC animations--

--Variables--
local set = script.Settings
local sp = set.Speed
local enabled = set.Enabled
local hum = script.Parent:WaitForChild("Humanoid")
if hum then
	print("Success")
else
	print("No Humanoid")
end
local humanim = hum:LoadAnimation(script:FindFirstChildOfClass("Animation"))

--Playing Animation--
if enabled.Value == true then
	humanim:Play()
	humanim.Looped = true
	humanim:AdjustSpeed(sp.Value)
end 
