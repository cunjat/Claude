--!strict
-- TYRE CANNON :: Server / Career
-- Levels and titles (2026-10-12).
--   levels  XP for playing (Game.Levels.XP), taken from the moments S.growth already hears about (a run,
--           crates, an upgrade, a stage-up, a prestige, a Heat, the daily). Every level pays keys
--           (Game.levelKeys) and a banner. Level and XP live in v2.career
--   titles  Config.Titles unlock the moment Game.titleProgress says they're earned (checked after every
--           moment, quietly on join). V2.EquipTitle wears one: the server sets the player's "Title"
--           attribute and TitleTags draws it over the head and in chat. A live title (a board place) is
--           yours while you hold the place
--   Career.init(S)   (after Growth: it chains onto S.growth)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)
local Game = require(Modules.Game)
local Analytics = require(script.Parent.Analytics)

local Career = {}
local XP = Game.Levels.XP
local BANNER_GAP = 3.7      -- seconds between two of one player's banners (each shows for about 3.5 s)

function Career.init(S)
	local folder = S.V2.Daily.Parent
	local equip = folder:FindFirstChild("EquipTitle") or Instance.new("RemoteFunction")
	equip.Name = "EquipTitle"
	equip.Parent = folder

	local function data(player: Player)
		local p = S.profiles[player.UserId]
		return p, p and p.v2
	end

	local function owns(p, t): boolean
		if t.live then return (Game.titleProgress(p, t)) >= 1 end
		return p.v2.career.titles[t.id] == true
	end

	-- one banner at a time per player, queued
	local nextBanner: { [number]: number } = {}
	local function banner(player: Player, payload)
		local now = os.clock()
		local at = math.max(now, nextBanner[player.UserId] or 0)
		nextBanner[player.UserId] = at + BANNER_GAP
		task.delay(at - now, function()
			if player.Parent then pcall(function() S.V2.Reward:FireClient(player, payload) end) end
		end)
	end

	-- the equipped title, if it's still yours (a live one can be lost), as the player's attribute
	S.applyTitle = function(player: Player)
		local p = S.profiles[player.UserId]
		local id = p and p.title or ""
		if p and p.v2 and id ~= "" then
			local t = Config.TitlesById[id]
			if not (t and owns(p, t)) then
				p.title = ""
				id = ""
			end
		end
		player:SetAttribute("Title", id)
	end

	-- unlock every title the save has earned by now (a banner each, unless quiet)
	local function checkTitles(player: Player, quiet: boolean?)
		local p, v = data(player)
		if not p or not v then return end
		for _, t in ipairs(Config.Titles) do
			if not t.live and not v.career.titles[t.id] then
				local have, goal = Game.titleProgress(p, t)
				if have >= goal then
					v.career.titles[t.id] = true
					Analytics.custom(player, "TitleUnlocked", 1, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = t.id })
					if not quiet then banner(player, { kind = "title", id = t.id, name = t.name, sub = t.desc, text = "Title unlocked: " .. t.name }) end
				end
			end
		end
	end

	local function addXP(player: Player, n: number)
		local p, v = data(player)
		if not p or not v or n <= 0 then return end
		local cr = v.career
		cr.xp += math.floor(n)
		while cr.level < Game.Levels.Max and cr.xp >= Game.xpToNext(cr.level) do
			cr.xp -= Game.xpToNext(cr.level)
			cr.level += 1
			local keys = Game.levelKeys(cr.level)
			if keys > 0 then
				v.keys = math.min(1e6, v.keys + keys)
				Analytics.earn(player, "Keys", keys, v.keys, "Gameplay", "Level")
			end
			Analytics.custom(player, "LevelUp", cr.level)
			banner(player, { kind = "level", level = cr.level, name = Game.levelBand(cr.level).name, text = ("Level %d  ·  %s"):format(cr.level, Game.levelBand(cr.level).name), keys = if keys > 0 then keys else nil })
		end
	end

	-- the moments (Loop, Heats, Economy call S.growth; this rides along)
	local function onMoment(player: Player, event: string, d: any)
		local p, v = data(player)
		if not p or not v then return end
		local cr = v.career
		local gain = 0
		if event == "run" then
			local zone = tonumber(d and d.zone) or 1
			gain = XP.run + XP.zone * math.max(0, zone - 1) + (if d and d.best then XP.best else 0)
			cr.perfects += math.max(0, math.floor(tonumber(d and d.perfects) or 0))
		elseif event == "tyres" then
			local n = if type(d) == "table" then #d else 1
			cr.crates += n
			gain = XP.crate * n
		elseif event == "upgrade" then
			cr.upgrades += 1
			gain = XP.upgrade
		elseif event == "stage" then
			cr.maxStage = math.max(cr.maxStage, math.floor(tonumber(d) or 1))
			gain = XP.stage
		elseif event == "prestige" then
			gain = XP.prestige
		elseif event == "heat" then
			gain = XP.heat
			if d and tonumber(d.place) == 1 then
				cr.heatWins += 1
				gain += XP.heatWin
			end
		elseif event == "daily" then
			gain = XP.daily
		end
		addXP(player, gain)
		checkTitles(player)
		-- (every other moment is pushed by its caller straight after)
		if event == "heat" then S.push(player) end
	end
	local prev = S.growth
	S.growth = function(player: Player, event: string, d: any)
		if prev then prev(player, event, d) end
		onMoment(player, event, d)
	end

	equip.OnServerInvoke = function(player: Player, id: any)
		if S.throttled(player, 0.3, "equipTitle") then return { ok = false, err = "Easy." } end
		local p = data(player)
		if not p then return { ok = false } end
		if id == nil or id == "" then
			p.title = ""
		else
			local t = type(id) == "string" and Config.TitlesById[id]
			if not t then return { ok = false, err = "No such title." } end
			if not owns(p, t) then return { ok = false, err = "You haven't earned that one yet." } end
			p.title = id
		end
		S.applyTitle(player)
		S.push(player)
		return { ok = true, title = p.title }
	end

	local function onJoin(player: Player)
		local t0 = os.clock()
		while not S.profiles[player.UserId] and player.Parent and os.clock() - t0 < 30 do task.wait(0.25) end
		if not S.profiles[player.UserId] then return end
		checkTitles(player, true)
		S.applyTitle(player)
		S.push(player)
	end
	Players.PlayerAdded:Connect(function(pl) task.spawn(onJoin, pl) end)
	for _, pl in ipairs(Players:GetPlayers()) do task.spawn(onJoin, pl) end
	Players.PlayerRemoving:Connect(function(pl) nextBanner[pl.UserId] = nil end)
end

return Career
