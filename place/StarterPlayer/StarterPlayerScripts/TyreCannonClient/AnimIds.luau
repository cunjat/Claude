--!strict
-- TYRE CANNON :: AnimIds
-- The id to play for each Config.Animations slot. An uploaded animation only plays in
-- experiences its owner owns or has shared it with; until a slot's upload loads here, the
-- slot plays Roblox's own R6 default instead (Roblox owns those, so they work anywhere),
-- and the character never stands stiff. Checked once per session. Once the uploads are
-- shared with the game they load and take over by themselves, with no change here.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Config"))

local AnimIds = {}

-- the classic R6 Animate set
local FALLBACK: { [string]: string } = {
	idle = "rbxassetid://180435571",
	idle2 = "rbxassetid://180435792",	-- the look-around
	walk = "rbxassetid://180426354",
	run = "rbxassetid://180426354",
	sprint = "rbxassetid://180426354",
	jump = "rbxassetid://125750702",
	jumpFall = "rbxassetid://180436148",
	fall = "rbxassetid://180436148",
	victory = "rbxassetid://129423030",	-- cheer
	sadSit = "rbxassetid://178130996",
	-- land has no R6 default; without its upload the landing just blends back to the ground set
}

local loaded: { [string]: boolean } = {}	-- [asset number] = loaded ok
local done = false
local finished = Instance.new("BindableEvent")

local function num(id: string): string
	return id:match("%d+") or id
end

task.spawn(function()
	local list = {}
	for _, id in pairs(Config.Animations or {}) do
		if type(id) == "string" and id ~= "" then
			local a = Instance.new("Animation")
			a.AnimationId = id
			table.insert(list, a)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list, function(contentId: string, status: Enum.AssetFetchStatus)
			loaded[num(contentId)] = status == Enum.AssetFetchStatus.Success
		end)
	end)
	done = true
	finished:Fire()
end)

-- waits (up to timeout seconds) for the check, so the first spawn already gets the right ids
function AnimIds.wait(timeout: number?)
	if done then return end
	local t = task.delay(timeout or 8, function() finished:Fire() end)
	finished.Event:Wait()
	pcall(task.cancel, t)
end

-- the id to load for a Config.Animations slot: the upload, unless it failed to load
function AnimIds.get(key: string): string?
	local id = (Config.Animations :: any)[key]
	if type(id) == "string" and id ~= "" and loaded[num(id)] ~= false then return id end
	return FALLBACK[key]
end

-- true when the slot is playing Roblox's default because its upload is blocked
function AnimIds.isFallback(key: string): boolean
	local id = (Config.Animations :: any)[key]
	return not (type(id) == "string" and id ~= "" and loaded[num(id)] ~= false)
end

return AnimIds
