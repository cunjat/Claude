--!strict
-- TYRE CANNON :: Prefs
-- The player's settings on this side. They start from the saved profile, change
-- instantly when a control moves, and save through SetPref a moment later.
--   Prefs.get(key)            the current value
--   Prefs.watch(key, fn)      fn(value) now and on every change
--   Prefs.set(key, value)     change it (saves after a short pause)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = Root:WaitForChild("Remotes")

local Prefs = {}

local values: { [string]: any } = table.clone(Config.PrefDefaults)
local watchers: { [string]: { (any) -> () } } = {}
local dirty: { [string]: number } = {}
Prefs.onError = nil :: ((string) -> ())?

local function fire(key: string)
	for _, fn in ipairs(watchers[key] or {}) do
		task.spawn(fn, values[key])
	end
end

function Prefs.get(key: string): any
	return values[key]
end

function Prefs.watch(key: string, fn: (any) -> ())
	watchers[key] = watchers[key] or {}
	table.insert(watchers[key], fn)
	task.spawn(fn, values[key])
end

-- the server's copy wins, except for anything changed here that hasn't saved yet
function Prefs.load(profile: any)
	local saved = profile and profile.prefs
	if type(saved) ~= "table" then return end
	for key in pairs(Config.PrefDefaults) do
		local v = saved[key]
		if v ~= nil and dirty[key] == nil and values[key] ~= v then
			values[key] = v
			fire(key)
		end
	end
end

function Prefs.set(key: string, value: any, now: boolean?)
	if (Config.PrefDefaults :: any)[key] == nil then return end
	if values[key] ~= value then
		values[key] = value
		fire(key)
	end
	local stamp = os.clock()
	dirty[key] = stamp
	local function save()
		if dirty[key] ~= stamp then return end
		local r = Remotes:FindFirstChild("SetPref") :: RemoteFunction?
		if not r then return end
		local ok, res = pcall(function() return (r :: RemoteFunction):InvokeServer(key, value) end)
		if dirty[key] == stamp then dirty[key] = nil end
		if ok and type(res) == "table" then
			if res.ok and res.value ~= nil and res.value ~= values[key] then
				values[key] = res.value
				fire(key)
			elseif res.ok == false and res.err and Prefs.onError then
				Prefs.onError(res.err)
			end
		end
	end
	if now then task.spawn(save) else task.delay(0.45, save) end
end

return Prefs
