local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local sound = handle:WaitForChild("Sound")

local debounce = false

tool.Activated:Connect(function()
	if not debounce then
		debounce = true
		sound:Play()
		wait(2,5) -- change to whatever you want
		debounce = false
	end
end)