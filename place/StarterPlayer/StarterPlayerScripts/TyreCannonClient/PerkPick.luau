--!strict
-- TYRE CANNON :: PerkPick
-- After a prestige: three perks on the table, keep one for good (Game.Perks). They stack into a build
-- of your own, so each climb plays a little differently. Each card shows the perk's picture, its
-- name, the level it'd go to and what it does there. Closing without picking leaves the offer
-- standing: it comes back the next time you're in the yard.
--   PerkPick.new(gui, remotes) ; :show(offer, perks, pres) ; :isOpen()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Sound = require(script.Parent.Sound)
local C = Kit.C

local PerkPick = {}
PerkPick.__index = PerkPick

local W, H = 900, 500
local CARD_W, CARD_H = 268, 330

function PerkPick.new(gui: ScreenGui, remotes: Instance)
	local self = setmetatable({}, PerkPick)
	self.gui = gui
	self.R = remotes
	self.box = nil :: Frame?
	self.shownFor = nil :: string?
	return self
end

function PerkPick:isOpen(): boolean
	return self.box ~= nil
end

function PerkPick:close()
	local box = self.box
	if not box then return end
	self.box = nil
	Kit.dim(self.gui, box, false)
	Kit.vanish(box, 0.2, function() box:Destroy() end)
end

function PerkPick:show(offer: { string }, perks: { [string]: number }?, pres: number)
	if self.box or #offer == 0 then return end
	local box = UI.mk("Frame", {
		Name = "PerkPick", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H),
		BackgroundTransparency = 1, ZIndex = 75, Parent = self.gui,
	})
	UI.autoScale(box, 1280, 760)
	self.box = box
	Kit.dim(self.gui, box, true)
	local holder, face = Kit.card(UDim2.fromScale(1, 1), C.cream)
	holder.Parent = box
	Kit.header(face, ("Prestige %d: Pick a Perk"):format(pres), C.gold, 56)
	local close = Kit.close(50)
	close.root.AnchorPoint = Vector2.new(0.5, 0.5)
	close.root.Position = UDim2.new(1, -8, 0, 8)
	close.root.ZIndex = 80
	close.root.Parent = box
	close.onClick = function() self:close() end
	local sub = Kit.text("Yours for good, and they stack: pick one you have and it levels up.", 17, C.muted, 1.5, Kit.Body)
	sub.Position = UDim2.fromOffset(0, 50)
	sub.Size = UDim2.new(1, 0, 0, 22)
	sub.ZIndex = 4
	sub.Parent = face
	local gap = (W - 3 * CARD_W) / 4
	for i, id in ipairs(offer) do
		local pk = Game.PerksById[id]
		if pk then
			local lv = (perks and perks[id]) or 0
			local card = UI.mk("Frame", {
				Position = UDim2.fromOffset(gap + (i - 1) * (CARD_W + gap), 92), Size = UDim2.fromOffset(CARD_W, CARD_H),
				BackgroundTransparency = 1, ZIndex = 5, Parent = face,
			})
			Kit.slot(card, if lv > 0 then C.gold else C.teal, 5)
			UI.mk("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(104, 104),
				BackgroundTransparency = 1, Image = Kit.Icon[pk.icon] or Kit.Icon.medal, ZIndex = 7, Parent = card,
			})
			local name = Kit.text(string.upper(pk.name), 24, C.white, 2)
			name.Position = UDim2.fromOffset(10, 124)
			name.Size = UDim2.new(1, -20, 0, 30)
			Kit.fit(name, 24, 14)
			name.ZIndex = 7
			name.Parent = card
			local level = Kit.text(if lv > 0 then ("LEVEL %d  >  %d  (OF %d)"):format(lv, lv + 1, pk.max) else ("NEW  ·  UP TO LEVEL %d"):format(pk.max), 13,
				if lv > 0 then C.gold else C.teal, 1.5)
			level.Position = UDim2.fromOffset(10, 156)
			level.Size = UDim2.new(1, -20, 0, 18)
			level.ZIndex = 7
			level.Parent = card
			local what = Kit.text(Game.perkText(id, lv + 1), 19, C.text, 1.5, Kit.Body)
			what.Position = UDim2.fromOffset(16, 182)
			what.Size = UDim2.new(1, -32, 0, 70)
			what.TextWrapped = true
			what.TextYAlignment = Enum.TextYAlignment.Top
			what.ZIndex = 7
			what.Parent = card
			local pick = Kit.button("Choose", C.green, UDim2.fromOffset(CARD_W - 40, 52), 22)
			pick.root.AnchorPoint = Vector2.new(0.5, 1)
			pick.root.Position = UDim2.new(0.5, 0, 1, -14)
			pick.root.ZIndex = 8
			pick.root.Parent = card
			pick.onClick = function()
				local ok, res = pcall(function() return (self.R :: any).PickPerk:InvokeServer(id) end)
				if ok and type(res) == "table" and res.ok then
					Sound.play("medal", { volume = 0.7, pitch = 1.05 })
					Kit.callout(self.gui, string.upper(pk.name) .. "!", C.gold, UDim2.fromScale(0.5, 0.24), 40)
					self:close()
				else
					Kit.shake(card, 6, 0.25)
				end
			end
			Kit.appear(card, 0.1 + i * 0.08, 30)
		end
	end
	Kit.pop(box, 0.85, 0.35)
	Sound.play("cheer", { volume = 0.4 })
end

return PerkPick
