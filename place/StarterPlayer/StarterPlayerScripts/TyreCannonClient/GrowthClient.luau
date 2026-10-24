--!strict
-- TYRE CANNON :: GrowthClient
-- Roblox's own prompts that bring friends in and players back, each at a natural moment and never on top
-- of anything: only while you're standing in your yard with nothing open, after the tutorial, one at a time
-- and at most once a session each (Server/Growth pays the rewards):
--   notifications  the opt-in prompt, the first time you're idle after claiming a daily reward (Roblox
--                  itself shows it at most once in 30 days)
--   invite         the invite prompt after a new best, from your second run of the session; the launch
--                  data carries your id so the friend's keys and yours get paid
--   group          the join-group prompt after a few runs, once Config.Growth.GroupId is set and you
--                  haven't had the group reward; then the server checks and pays
--   GrowthClient.start({ profile = () -> profile?, idle = () -> boolean, v2 = V2 remotes folder })

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)
local Game = require(Modules.Game)

local GrowthClient = {}
local G = Config.Growth
local GAP = 120          -- seconds between two growth prompts

function GrowthClient.start(ctx)
	local me = Players.LocalPlayer
	local startBest, startRuns = nil, nil
	local asked = { notify = false, invite = false, group = false }
	local lastPrompt = -math.huge

	local function invite(): boolean
		local okCan, can = pcall(function() return SocialService:CanSendGameInviteAsync(me) end)
		if not okCan or not can then return false end
		local opts = Instance.new("ExperienceInviteOptions")
		opts.PromptMessage = "That flew! Invite friends to ride along."
		opts.LaunchData = HttpService:JSONEncode({ ref = me.UserId })
		if G.InviteMessageId ~= "" then opts.InviteMessageId = G.InviteMessageId end
		return pcall(function() SocialService:PromptGameInvite(me, opts) end)
	end

	local function notify(): boolean
		local ok, ens = pcall(function() return game:GetService("ExperienceNotificationService") end)
		if not ok then return false end
		local okCan, can = pcall(function() return ens:CanPromptOptInAsync() end)
		if not okCan or not can then return false end
		return pcall(function() ens:PromptOptIn() end)
	end

	local function group(): boolean
		local ok = pcall(function() game:GetService("GroupService"):PromptJoinAsync(G.GroupId) end)
		-- whatever they chose, the server checks membership and pays once
		local check = ctx.v2:FindFirstChild("GroupCheck")
		if check then pcall(function() (check :: RemoteFunction):InvokeServer() end) end
		return ok
	end

	task.spawn(function()
		while true do
			task.wait(2)
			local p = ctx.profile()
			local v = p and p.v2
			if v then
				startBest = startBest or v.bestEver
				startRuns = startRuns or v.runs
				if p.tutorial and ctx.idle() and os.clock() - lastPrompt > GAP then
					local today = Game.utcDay(math.floor(workspace:GetServerTimeNow()))
					if not asked.notify and v.daily and v.daily.last == today then
						asked.notify = true
						if notify() then lastPrompt = os.clock() end
					elseif not asked.invite and v.bestEver > startBest and v.runs - startRuns >= 2 then
						asked.invite = true
						if invite() then lastPrompt = os.clock() end
					elseif not asked.group and G.GroupId ~= 0 and not (p.growth and p.growth.group) and v.runs - startRuns >= 3 then
						asked.group = true
						if group() then lastPrompt = os.clock() end
					end
				end
			end
		end
	end)
end

return GrowthClient
