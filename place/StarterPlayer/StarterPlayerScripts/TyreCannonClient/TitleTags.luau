--!strict
-- TYRE CANNON :: TitleTags
-- Your title over your head for everyone, and in front of your name in chat.
-- The server only sets a "Title" attribute on the player; every client draws
-- the effect itself so the gradients animate locally.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Config"))
local UI = require(script.Parent.UI)

local TitleTags = {}

local holder: Folder? = nil

local function hex(c: Color3): string
	return UI.hex(c)
end

-- chat can't draw gradients, so each letter gets its own colour
function TitleTags.chatPrefix(titleId: string): string?
	local t = Config.TitlesById[titleId]
	if not t then return nil end
	local tier = Config.TitleTiers[t.tier]
	local text = "[" .. string.upper(t.name) .. "]"
	if tier.style == "solid" then
		return ('<font color="%s">%s</font>'):format(hex(tier.colors[1]), text)
	end
	local out = {}
	local n = #text
	local colors = tier.colors
	for i = 1, n do
		local u = (n > 1) and (i - 1) / (n - 1) or 0
		local c
		if tier.style == "gradient" then
			c = colors[1]:Lerp(colors[2], u)
		else
			local f = u * (#colors - 1)
			local k = math.floor(f)
			c = colors[math.min(#colors, k + 1)]:Lerp(colors[math.min(#colors, k + 2)], f - k)
		end
		table.insert(out, ('<font color="%s">%s</font>'):format(hex(c), text:sub(i, i)))
	end
	return table.concat(out)
end

local function tagFor(player: Player)
	local function build(char: Model)
		local head = char:WaitForChild("Head", 10)
		if not head or not holder then return end
		local old = holder:FindFirstChild("Title_" .. player.UserId)
		if old then old:Destroy() end

		local bb = Instance.new("BillboardGui")
		bb.Name = "Title_" .. player.UserId
		bb.Adornee = head :: BasePart
		bb.Size = UDim2.fromOffset(320, 30)
		bb.StudsOffset = Vector3.new(0, 3.3, 0)
		bb.MaxDistance = 140
		bb.LightInfluence = 0
		bb.ResetOnSpawn = false
		bb.Parent = holder

		local label = UI.titleLabel(nil, 24)
		label.Size = UDim2.fromScale(1, 1)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextStrokeTransparency = 0.35
		label.Parent = bb

		local function apply()
			local id = player:GetAttribute("Title")
			UI.applyTitle(label, (type(id) == "string" and id ~= "") and id or nil)
			label.TextStrokeTransparency = 0.35
			bb.Enabled = label.Visible
		end
		apply()
		player:GetAttributeChangedSignal("Title"):Connect(apply)
	end
	if player.Character then task.spawn(build, player.Character) end
	player.CharacterAdded:Connect(build)
end

function TitleTags.start(playerGui: PlayerGui)
	local f = Instance.new("Folder")
	f.Name = "TitleTags"
	f.Parent = playerGui
	holder = f

	for _, pl in ipairs(Players:GetPlayers()) do tagFor(pl) end
	Players.PlayerAdded:Connect(tagFor)
	Players.PlayerRemoving:Connect(function(pl)
		local old = f:FindFirstChild("Title_" .. pl.UserId)
		if old then old:Destroy() end
	end)

	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local pl = Players:GetPlayerByUserId(source.UserId)
			local id = pl and pl:GetAttribute("Title")
			if type(id) == "string" and id ~= "" then
				local prefix = TitleTags.chatPrefix(id)
				if prefix then props.PrefixText = prefix .. " " .. message.PrefixText end
			end
		end
		return props
	end
end

return TitleTags
