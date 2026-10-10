--!strict
-- TYRE CANNON :: Server / Store
-- The v3 gamepasses and products (Config.Store). Passes are checked when a player joins and
-- granted the moment one is bought; they live in profile.v2.passes, where the loop reads them
-- (cash2, autolaunch, spares2, lucky, vip). Products are granted through the game's one
-- ProcessReceipt (init.server.luau calls Store.grant for anything in Config.Store.Products).
-- Server Luck doubles luck for everyone here for its minutes (S.serverLuckUntil, which crates
-- read) and shows on the hub through the workspace attribute ServerLuckUntil.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Config"))

local Store = {}

function Store.init(S)
	local function owns(player: Player, passId: number): boolean
		if passId == 0 then return false end
		local ok, yes = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId) end)
		return ok and yes == true
	end

	local function checkPasses(player: Player)
		local t0 = os.clock()
		while not S.profiles[player.UserId] and os.clock() - t0 < 20 and player.Parent do task.wait(0.25) end
		local p = S.profiles[player.UserId]
		if not (p and p.v2) then return end
		local changed = false
		for _, pass in ipairs(Config.Store.Passes) do
			if owns(player, pass.passId) and not p.v2.passes[pass.id] then
				p.v2.passes[pass.id] = true
				changed = true
			end
		end
		if p.v2.passes.vip then player:SetAttribute("VIP", true) end
		if changed then S.push(player) end
	end
	Players.PlayerAdded:Connect(function(pl) task.spawn(checkPasses, pl) end)
	for _, pl in ipairs(Players:GetPlayers()) do task.spawn(checkPasses, pl) end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, bought: boolean)
		if not bought then return end
		local pass = Config.StoreByPassId[passId]
		local p = S.profiles[player.UserId]
		if not (pass and p and p.v2) then return end
		p.v2.passes[pass.id] = true
		if pass.id == "vip" then player:SetAttribute("VIP", true) end
		S.push(player)
		S.Remotes.Notify:FireClient(player, { kind = "toast", text = pass.name .. " is yours. Thank you!" })
	end)

	-- a product from Config.Store.Products: returns the message to show, or nil if it isn't one
	S.storeGrant = function(player: Player, p, productId: number): string?
		local item = Config.StoreByProductId[productId]
		if not item or not p.v2 then return nil end
		if item.keys then
			p.v2.keys = math.min(1e6, p.v2.keys + item.keys)
			return ("+%d keys"):format(item.keys)
		end
		if item.id == "serverluck" then
			local now = os.time()
			S.serverLuckUntil = math.max(S.serverLuckUntil or now, now) + item.minutes * 60
			workspace:SetAttribute("ServerLuckUntil", S.serverLuckUntil)
			workspace:SetAttribute("ServerLuckBy", player.DisplayName)
			if S.V2 and S.V2.Announce then
				S.V2.Announce:FireAllClients({ kind = "luck", name = player.DisplayName, minutes = item.minutes })
			end
			return "Server Luck is on. Everyone here thanks you!"
		end
		return nil
	end
end

return Store
