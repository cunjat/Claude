local Configuration = {
	Size = 5,
	Lifetime = 120,
	
	Blacklist = {} --// Blacklisted image IDs
}

Debris = game:GetService("Debris")

idTemp = "rbxthumb://type=Asset&id=%s&w=420&h=420"
InfoTemp = "@%s (%s)<br/>(%s)"

local ServerScript = script
local Tool = ServerScript.Parent

local Handle = Tool:WaitForChild("Handle")
local Event = Tool:WaitForChild("RemoteEvent")

-----------------------------------------------------------------------------

local SprayTemplate = ServerScript:WaitForChild("SprayTemplate")

--------------------------------------------

local TemplatePart = Instance.new("Part")

TemplatePart.CanCollide = false
TemplatePart.CanQuery = false
TemplatePart.CanTouch = false

TemplatePart.Massless = true

TemplatePart.Size = Vector3.new(Configuration.Size, Configuration.Size, 0)

TemplatePart.Transparency = 1

-----------------------------------------------------------------------------

Event.OnServerEvent:Connect(function(Requester, Data)
	if Requester ~= nil and Data ~= nil then
		
		if Data.Position and Data.Id then
			
			local Position, Part, Normal, Id = Data.Position, Data.Instance, Data.Normal, Data.Id
			
			local SprayPart = TemplatePart:Clone()
			
			SprayPart.Position = Position
			SprayPart.CFrame = CFrame.lookAt(Position, Position + Normal)
			
			-----------------------------------------------------------------------------
			
			if table.find(Configuration.Blacklist, Id) then
				Id = 6255412420 --// Replacement ID
			end
			
			local ImageGUI = SprayTemplate:Clone()
			
			ImageGUI.Image.Image = string.format(idTemp, Id)
			ImageGUI.Info.Text = string.format(InfoTemp, Requester.Name, tostring(Requester.UserId), Id)
			
			ImageGUI.Parent = SprayPart
			
			-----------------------------------------------------------------------------
			
			local Weld = Instance.new("WeldConstraint")
			
			Weld.Part0 = Part
			Weld.Part1 = SprayPart
			
			Weld.Parent = SprayPart
			
			-----------------------------------------------------------------------------
			
			Debris:AddItem(SprayPart, Configuration.Lifetime or 30)
			SprayPart.Parent = workspace
			
			Handle.Spray:Play()
			
		end
		
	end
end)