--!strict
-- TYRE CANNON :: HubHunt (server)
-- Lost lug nuts (2026-10-22, the owner: the hub needs "some sort of incentive for looking around").
-- Every UTC day six golden lug nuts are tucked into new spots round the hub, from HubPlan.spots: the
-- islands in the forks, the pinches by the yards' fences, the roots of the avenues, the far ends by the
-- park's ring (so finding them walks you through all of it). Each find pays a couple of minutes of your
-- run cash; the sixth pays a key and ten minutes more. Everyone sees the same spots; each player finds
-- their own. Each find is checked here: today's spot, not found yet, the player standing by it.
--   V2.HuntState ()  -> { day, spots = { Vector3 }, found = { [i] = true } }
--   V2.HuntFind (i)  -> { ok, found, of } (and the pay as a Reward banner)
-- Saved on the profile as v2.hunt = { day, mask } (LoopData.sanitize keeps it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Game = require(Modules.Game)
local HubPlan = require(Modules:WaitForChild("HubPlan"))
local okA, Analytics = pcall(require, script.Parent:WaitForChild("Analytics"))

local HubHunt = {}

local PER_DAY = 6
local NUT_MINUTES = 2
local SET_MINUTES = 10
local SET_KEYS = 1
local REACH = 14            -- how near a find has to be made (studs, flat; latency allowance)

-- today's spots: one in each of six different gaps, a different six each day
local spotCache: { day: number, list: { Vector3 } }? = nil
function HubHunt.today(): (number, { Vector3 })
	local day = Game.utcDay()
	if spotCache and spotCache.day == day then return day, spotCache.list end
	local byGap: { { Vector3 } } = {}
	for i, s in ipairs(HubPlan.spots()) do
		local k = (i - 1) // 5 + 1
		byGap[k] = byGap[k] or {}
		if HubPlan.free(s.p, 1.2) then table.insert(byGap[k], s.p) end
	end
	local rng = Random.new(day * 7919 + 13)
	local gaps = {}
	for k = 1, #byGap do table.insert(gaps, k) end
	for i = #gaps, 2, -1 do
		local j = rng:NextInteger(1, i)
		gaps[i], gaps[j] = gaps[j], gaps[i]
	end
	local list = {}
	for _, k in ipairs(gaps) do
		local opts = byGap[k]
		if opts and #opts > 0 then table.insert(list, opts[rng:NextInteger(1, #opts)]) end
		if #list >= PER_DAY then break end
	end
	spotCache = { day = day, list = list }
	return day, list
end

local function bit(i: number): number return 2 ^ (i - 1) end
local function has(mask: number, i: number): boolean return math.floor(mask / bit(i)) % 2 == 1 end

function HubHunt.init(S)
	local folder = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Remotes"):WaitForChild("V2")
	local function remote(class: string, name: string): any
		local r = folder:FindFirstChild(name)
		if not r then
			r = Instance.new(class)
			r.Name = name
			r.Parent = folder
		end
		return r
	end
	local State = remote("RemoteFunction", "HuntState")
	local Find = remote("RemoteFunction", "HuntFind")
	local R = S.V2

	local function hunt(player: Player): (any, any, any)
		local p = S.profiles[player.UserId]
		local v = p and p.v2
		if not v then return nil, nil, nil end
		local day = Game.utcDay()
		if type(v.hunt) ~= "table" or v.hunt.day ~= day then v.hunt = { day = day, mask = 0 } end
		return p, v, v.hunt
	end

	State.OnServerInvoke = function(player: Player)
		local day, list = HubHunt.today()
		local _, _, h = hunt(player)
		local found = {}
		for i = 1, #list do
			if h and has(h.mask, i) then found[i] = true end
		end
		return { day = day, spots = list, found = found }
	end

	local lastAt: { [number]: number } = {}
	Find.OnServerInvoke = function(player: Player, i: any)
		local now = os.clock()
		if (lastAt[player.UserId] or 0) > now then return { ok = false } end
		lastAt[player.UserId] = now + 0.25
		local _, list = HubHunt.today()
		if type(i) ~= "number" or i ~= math.floor(i) or i < 1 or i > #list then return { ok = false } end
		local p, v, h = hunt(player)
		if not (p and v and h) or has(h.mask, i) then return { ok = false } end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return { ok = false } end
		local d = Vector3.new(root.Position.X - list[i].X, 0, root.Position.Z - list[i].Z).Magnitude
		if d > REACH then return { ok = false } end
		h.mask += bit(i)
		local found = 0
		for j = 1, #list do
			if has(h.mask, j) then found += 1 end
		end
		local rate = v.rate or 0
		local cash = math.max(25, math.floor(rate * NUT_MINUTES))
		local keys = 0
		if found >= #list then
			cash += math.floor(rate * SET_MINUTES)
			keys = SET_KEYS
			v.keys = math.min(1e6, v.keys + keys)
			if okA then (Analytics :: any).earn(player, "Keys", keys, v.keys, "Gameplay", "LugNuts") end
		end
		p.credits = math.min(1e15, p.credits + cash)
		if okA then (Analytics :: any).count("ev:LugNut") end
		R.Reward:FireClient(player, {
			kind = "hunt",
			text = if found >= #list then "All the lost lug nuts found!" else ("Lost lug nut %d of %d"):format(found, #list),
			keys = if keys > 0 then keys else nil,
			bonus = "+$" .. Game.short(cash),
		})
		S.push(player)
		return { ok = true, found = found, of = #list }
	end
	Players.PlayerRemoving:Connect(function(pl) lastAt[pl.UserId] = nil end)
end

return HubHunt
