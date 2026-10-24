-- Files imported art into ReplicatedStorage.TyreCannon.Assets inside a built place (after build_place).
-- Usage: lune run tools/file_assets.luau <in.rbxl> <out.rbxl>
-- Workspace imports are copied, never moved (the map is built from Workspace). Whatever a filed model
-- replaces goes to ServerStorage.ArchivedAssets.Replaced_<date>.
--   TC_HubProps Pigeon__Body / __WingL / __WingR  ->  Assets/Park/Pigeon (Body, WingL, WingR; RockPigeon = true)
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local Instance = roblox.Instance
local inPath, outPath = process.args[1], process.args[2]
local game = roblox.deserializePlace(fs.readFile(inPath))
local ws = game:GetService("Workspace")
local assets = game:GetService("ReplicatedStorage").TyreCannon.Assets
local DATE = "2026-10-24"

local function archive(old)
	local ss = game:GetService("ServerStorage")
	local arch = ss:FindFirstChild("ArchivedAssets") or Instance.new("Folder")
	arch.Name = "ArchivedAssets"
	arch.Parent = ss
	local name = "Replaced_" .. DATE
	local box = arch:FindFirstChild(name) or Instance.new("Folder")
	box.Name = name
	box.Parent = arch
	old.Parent = box
end

local props = ws:FindFirstChild("TC_HubProps")
local park = assets:FindFirstChild("Park")
if props and park and props:FindFirstChild("Pigeon__Body") then
	local old = park:FindFirstChild("Pigeon")
	if old and old:GetAttribute("RockPigeon") then
		print("Park/Pigeon is already the rock pigeon")
	else
		local m = Instance.new("Model")
		m.Name = "Pigeon"
		for _, n in { "Body", "WingL", "WingR" } do
			local src = props:FindFirstChild("Pigeon__" .. n)
			if src then
				local c = src:Clone()
				c.Name = n
				c.Anchored = true
				c.Parent = m
			end
		end
		m:SetAttribute("RockPigeon", true)
		if old then archive(old) end
		m.Parent = park
		print("filed Park/Pigeon (rock pigeon)")
	end
else
	print("no TC_HubProps pigeon to file")
end

fs.writeFile(outPath, roblox.serializePlace(game))
print("-> " .. outPath)
