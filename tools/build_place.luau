-- Writes place/ scripts back into a .rbxl.
-- Usage: lune run tools/build_place.luau <in.rbxl> <place dir> <out.rbxl>
-- Paths mirror the instance tree (same naming as the dump: unsafe chars -> "_", duplicates get "__N").
-- A file with no matching instance creates a ModuleScript (or Script/LocalScript by extension)
-- under its parent folder path, which must exist.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local process = require("@lune/process")
local inPath, dir, outPath = process.args[1], process.args[2], process.args[3]
local game = roblox.deserializePlace(fs.readFile(inPath))
local Instance = roblox.Instance

local function safe(n) return (string.gsub(n, "[^%w%._%-]", "_")) end
local byPath = {}
local function walk(inst, path)
	byPath[path] = inst
	local seen = {}
	for _, c in inst:GetChildren() do
		local n = safe(c.Name)
		if seen[n] then seen[n] += 1; n = n .. "__" .. seen[n] else seen[n] = 1 end
		walk(c, path .. "/" .. n)
	end
end
for _, svc in game:GetChildren() do walk(svc, safe(svc.Name)) end

local changed, created, bad = 0, 0, 0
local function visit(p)
	for _, name in fs.readDir(p) do
		local full = p .. "/" .. name
		if fs.isDir(full) then visit(full) elseif string.match(name, "%.luau$") then
			local rel = string.sub(full, #dir + 2)
			local base, ext = string.match(rel, "^(.-)(%.server%.luau)$")
			if not base then base, ext = string.match(rel, "^(.-)(%.client%.luau)$") end
			if not base then base, ext = string.match(rel, "^(.-)(%.luau)$") end
			local src = fs.readFile(full)
			local ok, err = pcall(luau.compile, src)
			if not ok then bad += 1; print("SYNTAX " .. rel .. ": " .. tostring(err)) end
			local inst = byPath[base]
			if not inst then
				local parentPath, leaf = string.match(base, "^(.*)/([^/]+)$")
				local parent = byPath[parentPath]
				assert(parent, "no parent for " .. rel)
				local cls = ext == ".server.luau" and "Script" or ext == ".client.luau" and "LocalScript" or "ModuleScript"
				inst = Instance.new(cls)
				inst.Name = leaf
				inst.Parent = parent
				byPath[base] = inst
				created += 1
			end
			if inst.Source ~= src then inst.Source = src; changed += 1 end
		end
	end
end
visit(dir)
if bad > 0 then print("syntax errors: " .. bad); process.exit(1) end
fs.writeFile(outPath, roblox.serializePlace(game))
print(("changed %d, created %d -> %s"):format(changed, created, outPath))
