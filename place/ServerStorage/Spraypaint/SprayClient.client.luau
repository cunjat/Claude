--// Originally created by StickMasterLuke
--// Redone from scratch by @Mark_JavisHack

local ClientConfig = {
	Cooldown = 2.1,
	MaxRange = 10,
	
	ParticlesEnabled = true, --// Additional particles when spraying an image (Client-sided)
}

local Services = {
	Players = game:GetService("Players")
}

local SprayClient = script
local Tool = SprayClient.Parent

local Handle = Tool:WaitForChild("Handle")
local Particles = Handle:WaitForChild("Particles")

local Event = Tool:WaitForChild("RemoteEvent")

Debounce = false
Id = 80373023

idTemp = "rbxthumb://type=Asset&id=%s&w=420&h=420"

-------------------------------------------------------------------------------------

local Player = Services.Players.LocalPlayer
local Character = Player.Character

local Head = Character:WaitForChild("Head")

local Mouse = Player:GetMouse()

local Humanoid = Character:WaitForChild("Humanoid")

local Animation = SprayClient:WaitForChild("SprayPaint")
local SprayGui = SprayClient:WaitForChild("SprayGui")

local MainFrame = SprayGui.Frame

local IdFrame = MainFrame.Frame
local Preview = MainFrame.Preview

local LoadedAnimation = Humanoid:LoadAnimation(Animation)

local Params = RaycastParams.new()
Params.FilterType = Enum.RaycastFilterType.Blacklist
Params.FilterDescendantsInstances = {Character, Tool}

-------------------------------------------------------------------------------------

local function toggleParticles(boolean)
	for Index, Particle in pairs(Particles:GetChildren()) do
		if Particle:IsA("ParticleEmitter") then
			Particle.Enabled = boolean
		end
	end
end

function onActivated()
	
	local Origin = Head.Position
	local End = Mouse.Hit.Position
	
	local Distance = (Origin - End).Magnitude
	local Raycast = workspace:Raycast(Origin, (CFrame.lookAt(Origin, End).LookVector)  * ClientConfig.MaxRange, Params)
	
	if Distance <= ClientConfig.MaxRange and Raycast then
		
		if not Debounce then

			Debounce = true
			
			Event:FireServer({
				Instance = Raycast.Instance,
				Normal = Raycast.Normal,
				Position = Raycast.Position,
				
				Id = Id,
			})
			
			LoadedAnimation:Play()
			
			toggleParticles(true)

			task.wait(ClientConfig.Cooldown)
			
			toggleParticles(false)

			Debounce = false

		end
		
	end
end

function onEquip()
	SprayGui.Parent = Player.PlayerGui
end

function onUnequip()
	SprayGui.Parent = SprayClient
end

Tool.Equipped:Connect(onEquip)
Tool.Unequipped:Connect(onUnequip)

Tool.Activated:Connect(onActivated)

-------------------------------------------------------------------------------------

function updateId()
	if tonumber(Id) then
		local Image = string.format(idTemp, Id)
		Preview.Image = Image
	end
end

IdFrame.TextBox:GetPropertyChangedSignal("Text"):Connect(function()
	Id = tonumber(IdFrame.TextBox.Text)
end)
IdFrame.TextBox.FocusLost:Connect(updateId)

updateId()