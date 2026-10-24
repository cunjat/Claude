local Tool = nil 
local animScript = nil
script.Parent.Equipped:Connect(function()
	Tool = script.Parent
	animScript = Tool.Parent:WaitForChild("Animate")
	animScript:WaitForChild("toolnone"):WaitForChild("ToolNoneAnim")
	animScript.toolnone.ToolNoneAnim.AnimationId = "https://www.roblox.com/asset/?id=15991632082"
	
end)
script.Parent.Unequipped:Connect(function()
	animScript:WaitForChild("toolnone"):WaitForChild("ToolNoneAnim")
	animScript.toolnone.ToolNoneAnim.AnimationId = "https://www.roblox.com/asset/?id=15991632082"
end)