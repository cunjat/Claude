--!strict
-- TYRE CANNON :: Plot2
-- Your plot's machines: the menu that upgrades them, and the machines themselves standing on the
-- yard, which change in front of you when you buy (each purchase plays an install: the part drops
-- in on a cable, lands with a bounce and a puff of dust, the machine's level sign flips).
-- Machines are the Blender models once imported (Assets/Cannons and Assets/Machines, see
-- Models.luau) and chunky stand-ins until then.
--   Plot2.new(gui, remotes) -> plot
--   plot:setProfile(p)      keeps the menu and the yard in step with the save
--   plot:attach(plotModel)  builds the machines on your yard
--   plot:open() / plot:close()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local Goals = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Goals"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Models = require(script.Parent.Models)
-- prestige trims, the neon decor pack and the yard looks (the Prestige & Neon set, 2026-10-12)
local PrestigeLook = require(script.Parent.PrestigeLook)
local NeonDecor = require(script.Parent.NeonDecor)
local YardLook = require(script.Parent.YardLook)
local C = Kit.C

local Plot2 = {}
Plot2.__index = Plot2

-- the imported machine for each id; the cannon's model follows its build (Junk Pipe .. Mag Rail)
local MACHINE_MODEL = { fuel = "Machines/FuelTank", cooling = "Machines/CoolingTower",
	compressor = "Machines/Compressor", rack = "Machines/SpareRack" }
-- the racing yard (art/blender/racing.py), used once imported: each machine is one model whose
-- meshes are its upgrade ladder (Body, L1..L6, Barrel*, Fan, Rotor; the cannon's L0Wheels go at 5)
local RACING_MODEL = { cannon = "Racing/RallyCannon", fuel = "Racing/NitroStation",
	cooling = "Racing/Radiator", compressor = "Racing/Turbo", rack = "Racing/TyreWall" }

-- a machine's level on the 0..6 look ladder (machines with other level counts spread over it)
function Plot2.lookStep(id: string, level: number): number
	local max = Game.maxLevel(id)
	if max == 6 then return math.clamp(level, 0, 6) end
	return math.clamp(math.ceil(level * 6 / max), 0, 6)
end

-- keep only the meshes the look step has reached
function Plot2.trimToLevel(model: Instance, step: number)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local n = tonumber(p.Name:match("^L(%d)") or p.Name:match("^BarrelL(%d)"))
			if p.Name == "L0Wheels" then
				if step >= 5 then p:Destroy() end
			elseif n and n > step then
				p:Destroy()
			end
		end
	end
end

local COLORS = {
	cannon = C.red, ramp = C.yellow, fuel = C.orange, cooling = C.blue, compressor = C.teal, rack = C.purple,
}

-- what it does now, and (greyed) what the next level adds
local function effectText(id: string, level: number, tier: number): string
	local now = Game.machineEffect(id, level, tier)
	if level >= Game.maxLevel(id) then return now end
	return ('%s  <font color="#9A948C">next %s</font>'):format(now, Game.machineNext(id, level, tier))
end

-- the yard's stages as the Plot screen shows them: a picture of each (art/blender/stage_cards.py)
-- and what the next one brings
local STAGE_ART = {
	"rbxassetid://100549850252972", "rbxassetid://134768103011664", "rbxassetid://86284466277916",
	"rbxassetid://123545622265306", "rbxassetid://76545214432490",
}
local STAGE_BRINGS = {
	[2] = { "Gravel yard, chain-link fence", "A rusted shed on the street", "The Steel Mortar cannon" },
	[3] = { "Concrete yard and street lamps", "Your own garage, name over the door", "The Air Cannon" },
	[4] = { "Painted lanes, green palisade", "A gantry hoist and tyre racks", "The Howitzer" },
	[5] = { "A hazard-marked launch lane", "Floodlight masts", "The Mag Rail" },
}
local PAST, NOW, LATER = Color3.fromRGB(96, 132, 88), Color3.fromRGB(246, 156, 38), Color3.fromRGB(70, 70, 76)

function Plot2.new(gui: ScreenGui, remotes: Instance)
	local self = setmetatable({}, Plot2)
	self.gui = gui
	self.R = remotes
	self.profile = nil
	self.yards = {} :: { [Instance]: any }
	task.spawn(function() self:watchYards() end)

	local root = UI.mk("Frame", {
		Name = "Plot2", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(940, 600),
		BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	self.root = root
	local holder, face = Kit.card(UDim2.fromOffset(940, 590), C.cream)
	holder.Parent = root
	self.header = Kit.header(face, "Your Yard", C.accent, 60)
	local close = Kit.close(54)
	close.root.AnchorPoint = Vector2.new(0.5, 0.5)
	close.root.Position = UDim2.new(1, -8, 0, 8)
	close.root.ZIndex = 40
	close.root.Parent = root
	close.onClick = function() self:close() end

	-- the five stages in a row, yours lit
	self.stagePlates = {}
	for i, t in ipairs(Game.Tiers) do
		local plate, label = Kit.plate(face, t.name, LATER, UDim2.fromOffset(26 + (i - 1) * 112, 46), UDim2.fromOffset(106, 26), 6)
		-- one size for every stage name (the longest sets it)
		label.Size = UDim2.new(1, -10, 1, -4)
		Kit.fit(label, 11, 9)
		self.stagePlates[i] = { plate = plate, label = label }
	end

	-- the machines
	self.rows = {}
	for i, m in ipairs(Game.Machines) do
		local y = 86 + (i - 1) * 72
		local row = UI.mk("Frame", { Name = m.id, Position = UDim2.fromOffset(24, y), Size = UDim2.fromOffset(560, 64), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
		Kit.slot(row, Color3.fromRGB(70, 70, 76), 4)
		-- the level in an enamel square of the machine's colour
		-- the machine itself (its icon-studio render), breaking out of the row, its level on a plate
		local chip = UI.mk("ImageLabel", {
			Position = UDim2.fromOffset(-2, -10), Size = UDim2.fromOffset(74, 74), BackgroundTransparency = 1,
			Image = Kit.Icon[m.id] or "", ZIndex = 6, Parent = row,
		})
		local _, lvl = Kit.plate(chip, "0", COLORS[m.id], UDim2.fromOffset(34, 52), UDim2.fromOffset(40, 22), 8)
		lvl.Name = "Level"
		local name = Kit.text(m.name, 20, C.text, 2)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(80, 7)
		name.Size = UDim2.fromOffset(200, 24)
		name.ZIndex = 6
		name.Parent = row
		local eff = Kit.text("", 15, C.gold, 1.5, Kit.Body)
		eff.TextXAlignment = Enum.TextXAlignment.Left
		eff.Position = UDim2.fromOffset(80, 33)
		eff.Size = UDim2.fromOffset(206, 20)
		Kit.fit(eff, 15, 10)
		eff.ZIndex = 6
		eff.Parent = row
		-- a pip for every level this tier allows, filled as you buy them
		local pips = {}
		local max = Game.maxLevel(m.id)
		for k = 1, max do
			local pip = UI.mk("Frame", {
				AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 290 + (k - 1) * math.min(15, 100 / max), 0.5, 0),
				Size = UDim2.fromOffset(math.min(11, 90 / max), 20), BackgroundColor3 = Color3.fromRGB(26, 26, 28), BorderSizePixel = 0, ZIndex = 6, Parent = row,
			}, { UI.corner(3), UI.mk("UIStroke", { Color = Color3.fromRGB(12, 12, 14), Thickness = 1.5 }) })
			table.insert(pips, pip)
		end
		local buy = Kit.button("$0", C.green, UDim2.fromOffset(150, 46), 20)
		buy.root.AnchorPoint = Vector2.new(1, 0.5)
		buy.root.Position = UDim2.new(1, -10, 0.5, 0)
		buy.root.ZIndex = 7
		buy.root.Parent = row
		buy.onClick = function() self:buy(m.id) end
		self.rows[m.id] = { row = row, chip = chip, lvl = lvl, eff = eff, buy = buy, pips = pips, color = COLORS[m.id] }
	end

	-- the next stage: its picture, what it brings, what it costs
	local nx = 604
	self.nextTitle = Kit.section(face, "Next Stage", UDim2.fromOffset(nx, 84), UDim2.fromOffset(312, 30), 5)
	local pic = UI.mk("Frame", { Position = UDim2.fromOffset(nx, 122), Size = UDim2.fromOffset(312, 190), BackgroundTransparency = 1, ZIndex = 5, Parent = face })
	Kit.slot(pic, Color3.fromRGB(70, 70, 76), 5)
	local bay = UI.mk("ImageLabel", {
		Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12), BackgroundTransparency = 1, Image = "",
		ZIndex = 6, Parent = pic,
	}, { UI.corner(6) })
	-- a soft floor shadow under the stage (art/ui/kit3/spot.svg)
	UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromScale(0.95, 0.34), BackgroundTransparency = 1,
		Image = "rbxassetid://119243950784301", ZIndex = 6, Parent = bay,
	})
	self.stagePic = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(1.04, 1.04), BackgroundTransparency = 1,
		Image = STAGE_ART[2], ScaleType = Enum.ScaleType.Fit, ZIndex = 7, Parent = bay,
	})
	self.brings = Kit.text("", 15, C.text, 1.5, Kit.Body)
	self.brings.Position = UDim2.fromOffset(nx + 8, 320)
	self.brings.Size = UDim2.fromOffset(300, 64)
	self.brings.TextXAlignment = Enum.TextXAlignment.Left
	self.brings.TextYAlignment = Enum.TextYAlignment.Top
	self.brings.ZIndex = 6
	self.brings.Parent = face
	self.reachText = Kit.text("", 17, C.text, 1.5)
	self.reachText.TextXAlignment = Enum.TextXAlignment.Left
	self.reachText.Position = UDim2.fromOffset(nx + 8, 388)
	self.reachText.Size = UDim2.fromOffset(300, 22)
	self.reachText.ZIndex = 6
	self.reachText.Parent = face
	local otrack, ofill = Kit.bar(312, 22, C.accent)
	otrack.Position = UDim2.fromOffset(nx, 414)
	otrack.ZIndex = 6
	otrack.Parent = face
	self.overFill = ofill
	self.overText = Kit.text("", 14, C.muted, 1.5, Kit.Body)
	self.overText.TextXAlignment = Enum.TextXAlignment.Left
	self.overText.Position = UDim2.fromOffset(nx + 8, 440)
	self.overText.Size = UDim2.fromOffset(304, 34)
	self.overText.TextWrapped = true
	self.overText.ZIndex = 6
	self.overText.Parent = face
	local over = Kit.button("Upgrade", C.accent, UDim2.fromOffset(312, 50), 22)
	over.root.Position = UDim2.fromOffset(nx, 476)
	over.root.ZIndex = 7
	over.root.Parent = face
	over.onClick = function() self:overhaul() end
	self.overBtn = over
	local edit = Kit.button("Edit Yard", C.blue, UDim2.fromOffset(312, 40), 18)
	edit.root.Position = UDim2.fromOffset(nx, 532)
	edit.root.ZIndex = 7
	edit.root.Parent = face
	edit.onClick = function() if self.onEditYard then self.onEditYard() end end
	self.editBtn = edit

	-- the stage's trial (Goals): one challenge on a run, needed with the cash to move up a stage
	local card = UI.mk("Frame", { Name = "Trial", Position = UDim2.fromOffset(24, 452), Size = UDim2.fromOffset(560, 112), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
	Kit.slot(card, C.gold, 4)
	UI.mk("ImageLabel", {
		Position = UDim2.fromOffset(6, 10), Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1, Image = Kit.Icon.medal, ZIndex = 6, Parent = card,
	})
	local tag = Kit.text("STAGE TRIAL", 13, C.gold, 1.5)
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.Position = UDim2.fromOffset(98, 10)
	tag.Size = UDim2.fromOffset(200, 16)
	tag.ZIndex = 6
	tag.Parent = card
	local what = Kit.text("", 21, C.text, 2)
	what.TextXAlignment = Enum.TextXAlignment.Left
	what.Position = UDim2.fromOffset(98, 28)
	what.Size = UDim2.fromOffset(330, 26)
	Kit.fit(what, 21, 12)
	what.ZIndex = 6
	what.Parent = card
	local ttrack, tfill = Kit.bar(330, 16, C.gold)
	ttrack.Position = UDim2.fromOffset(98, 60)
	ttrack.ZIndex = 6
	ttrack.Parent = card
	local best = Kit.text("", 13, C.muted, 1.5, Kit.Body)
	best.TextXAlignment = Enum.TextXAlignment.Left
	best.Position = UDim2.fromOffset(98, 80)
	best.Size = UDim2.fromOffset(330, 18)
	Kit.fit(best, 14, 9)
	best.ZIndex = 6
	best.Parent = card
	local chip, chipText = Kit.plate(card, "EVERY RUN COUNTS", C.grey, UDim2.fromOffset(440, 38), UDim2.fromOffset(110, 34), 6)
	Kit.fit(chipText, 13, 8)
	self.trial = { card = card, what = what, fill = tfill, best = best, chip = chip, chipText = chipText }
	return self
end

function Plot2:setProfile(p)
	self.profile = p
	if not p or not p.v2 then return end
	local v = p.v2
	for i, sp in ipairs(self.stagePlates) do
		local img = sp.plate:FindFirstChildWhichIsA("ImageLabel")
		if img then img.ImageColor3 = if i < v.tier then PAST elseif i == v.tier then NOW else LATER end
		sp.label.TextTransparency = if i > v.tier then 0.35 else 0
	end
	for _, m in ipairs(Game.Machines) do
		local r = self.rows[m.id]
		local level = v.mach[m.id] or 0
		local max = Game.maxLevel(m.id)
		if r.lvl.Text ~= tostring(level) and r.lvl.Text ~= "0" then Kit.pop(r.chip, 0.6, 0.3) end
		r.lvl.Text = tostring(level)
		r.eff.Text = effectText(m.id, level, v.tier)
		for k, pip in ipairs(r.pips) do
			local on = k <= level
			pip.BackgroundColor3 = if on then r.color else Color3.fromRGB(26, 26, 28)
		end
		if level >= max then
			r.buy.setText("Max")
			r.buy.setEnabled(false)
		else
			local price = Game.machinePrice(m.id, level, v.tier, v)
			r.buy.setText("$" .. Game.short(price))
			r.buy.setEnabled(p.credits >= price)
		end
	end
	-- the next stage, or the top one if you're there
	local nextTier = math.min(v.tier + 1, #Game.Tiers)
	local top = v.tier >= #Game.Tiers
	;(self.nextTitle:FindFirstChild("Label") :: TextLabel).Text = if top then "Top Stage" else "Next: " .. Game.Tiers[nextTier].name
	self.stagePic.Image = STAGE_ART[nextTier]
	local lines = STAGE_BRINGS[nextTier] or {}
	local text = {}
	for _, l in ipairs(lines) do table.insert(text, "·  " .. l) end
	if not top then
		table.insert(text, ("·  Cash x%d for good"):format(math.floor(Game.stageCash(v.overhauls + 1) + 0.5)))
	end
	self.brings.Text = if top then "Your yard is a launch complex." else table.concat(text, "\n")
	local reach = Game.reachMetres(v.mach, v.tier)
	-- (2026-10-18: an estimate of an average run, so it says so; "your reach" read as wrong next to a better best)
	self.reachText.Text = "Typical run  <font color=\"#ECC478\">" .. Game.metres(reach) .. "</font>"
	local cost = if top then Game.prestigeCost(v) else Game.plotUpgradeCost(v.tier, v)
	self.overFill.Size = UDim2.fromScale(math.clamp(p.credits / cost, 0, 1), 1)
	local maxed = Game.machinesMaxed(v)
	-- the trial
	local tr = v.trial
	local trialOk = Game.trialDone(v)
	if tr and tr.k then
		local g = { k = tr.k, t = tr.t }
		self.trial.what.Text = Goals.text(g)
		self.trial.fill.Size = UDim2.fromScale(if tr.done then 1 else math.clamp((tr.best or 0) / math.max(tr.t, 1e-6), 0, 1), 1)
		-- (short: the one line it has stays readable; the Stage Trials tip explains the rest)
		self.trial.best.Text = if tr.done then "Done: this stage's trial is behind you."
			else ("Your best %s  ·  every miss makes it easier"):format(Goals.progressText(g, tr.best or 0))
		self.trial.chipText.Text = if tr.done then "DONE" else "EVERY RUN COUNTS"
		local img = self.trial.chip:FindFirstChildWhichIsA("ImageLabel")
		if img then img.ImageColor3 = if tr.done then C.green else C.grey end
	end
	-- at the top stage the same button prestiges (Game.Prestige): back to the Dirt Lot for good bonuses
	local level = p.prestige or 0
	local topPrestige = level >= Game.Prestige.Max
	if top then
		self.overText.Text = if topPrestige then ("Prestige %d: the very top. Nothing left to build."):format(level)
			elseif not maxed then ("Max the Cannon, Fuel Tank and Cooling to prestige: all cash x%s for good."):format(("%g"):format(Game.prestigeMult(level + 1)))
			else ("Prestige: start again from the Dirt Lot with nothing, for all cash x%s for good, %d keys and a perk you choose. Tyres, keys, decor and perks stay."):format(
				("%g"):format(Game.prestigeMult(level + 1)), Game.Prestige.Keys + Game.Prestige.KeysPer * (level + 1))
	else
		self.overText.Text = if not maxed then "Max the Cannon, Fuel Tank and Cooling to upgrade the yard."
			else ("Upgrade the yard: all cash x%d for good. Machines start again at level 0; your tyres stay."):format(math.floor(Game.Overhaul.Mult + 0.5))
	end
	if self.confirmPrestige then
		self.overBtn.setText("Tap again to prestige")
	elseif top then
		self.overBtn.setText(if topPrestige then "Top Prestige" elseif not maxed then "Max Machines First" elseif not trialOk then "Finish the Trial" else ("Prestige  $" .. Game.short(cost)))
	else
		self.overBtn.setText(if not maxed then "Max Machines First" elseif not trialOk then "Finish the Trial" else ("Upgrade  $" .. Game.short(cost)))
	end
	self.overBtn.setEnabled(maxed and trialOk and p.credits >= cost and not (top and topPrestige))
end

function Plot2:open()
	Kit.dim(self.gui or self.root.Parent, self, true)
	Kit.open(self.root)
	local list = {}
	for _, m in ipairs(Game.Machines) do table.insert(list, self.rows[m.id].row) end
	Kit.cascade(list, 0.035)
end

function Plot2:close()
	Kit.dim(self.gui or self.root.Parent, self, false)
	if not self.root.Visible then return end
	Kit.close_(self.root)
end

function Plot2:isOpen(): boolean
	return self.root.Visible
end

function Plot2:buy(id: string)
	local ok, res = pcall(function() return (self.R :: any).Buy:InvokeServer(id) end)
	if ok and type(res) == "table" and res.ok then
		local r = self.rows[id]
		Kit.pop(r.row, 0.85, 0.25)
		Kit.callout(self.gui, ("%s LV %d"):format(string.upper(Game.MachinesById[id].name), res.level), COLORS[id], UDim2.fromScale(0.5, 0.18), 40)
	elseif ok and type(res) == "table" then
		Kit.shake(self.rows[id].buy.root, 6, 0.25)
		if res.short then
			Kit.callout(self.gui, "Need $" .. Game.short(res.short) .. " more", C.red, UDim2.fromScale(0.5, 0.18), 34)
		end
	end
end

-- the top stage's button: prestige, after a second tap within 4 s (it starts the yard again)
function Plot2:prestige()
	if not self.confirmPrestige then
		self.confirmPrestige = true
		if self.profile then self:setProfile(self.profile) end
		task.delay(4, function()
			self.confirmPrestige = nil
			if self.profile then self:setProfile(self.profile) end
		end)
		return
	end
	self.confirmPrestige = nil
	local ok, res = pcall(function() return (self.R :: any).Prestige:InvokeServer() end)
	if ok and type(res) == "table" and res.ok then
		self:close()
		Kit.callout(self.gui, "PRESTIGE " .. tostring(res.level) .. "!", C.accent, UDim2.fromScale(0.5, 0.35), 80)
		task.delay(0.5, function()
			Kit.callout(self.gui, ("ALL CASH x%s  ·  +%d KEYS"):format(("%g"):format(res.mult), res.keys), C.white, UDim2.fromScale(0.5, 0.45), 44)
		end)
	elseif ok and type(res) == "table" and res.err then
		Kit.callout(self.gui, string.upper(res.err), C.red, UDim2.fromScale(0.5, 0.18), 30)
	end
end

function Plot2:overhaul()
	local pv = self.profile and self.profile.v2
	if pv and pv.tier >= #Game.Tiers then
		self:prestige()
		return
	end
	-- the upgrade is a scene (StageUp): it starts the purchase itself once the camera is moving
	if self.upgradeScene then
		self:close()
		self.upgradeScene(function() return (self.R :: any).Overhaul:InvokeServer() end)
		return
	end
	local ok, res = pcall(function() return (self.R :: any).Overhaul:InvokeServer() end)
	if ok and type(res) == "table" and res.ok then
		self:close()
		Kit.callout(self.gui, "Stage Up!", C.accent, UDim2.fromScale(0.5, 0.35), 80)
		task.delay(0.5, function()
			Kit.callout(self.gui, string.upper(Game.Tiers[res.tier].name), C.white, UDim2.fromScale(0.5, 0.45), 56)
		end)
		if self.onOverhaul then self.onOverhaul(res) end
	elseif ok and type(res) == "table" and res.err then
		Kit.callout(self.gui, string.upper(res.err), C.red, UDim2.fromScale(0.5, 0.18), 30)
	end
end

--==============================================================
-- the yards
-- Every claimed plot shows its owner's machines: the server puts the levels on the plot as
-- attributes (V2_<machine>, V2_Tier) and every client builds from them. Laid out for the real
-- plot, in its own frame (BaseCFrame): +X runs out from the plaza down the launch lane, the floor
-- is x -34..74, z -39..39, its top at y 2. The cannon heads the lane and fires out over the ramp;
-- the four helpers stand on pads either side, clear of the workbench (4, -28), the garage door
-- (-22, -33), the claim pad (-26, 8) and the owner spawn (-16, 14).
--==============================================================
local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

local function cyl(parent: Instance, length: number, dia: number, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	return part(parent, Vector3.new(length, dia, dia), cf, color, mat, Enum.PartType.Cylinder)
end

local STEEL, DARK = Color3.fromRGB(150, 156, 166), Color3.fromRGB(52, 54, 62)
local CONCRETE = Color3.fromRGB(176, 170, 160)

-- Stand-ins until the Blender machines are imported: the footprint and silhouette of the model
-- that replaces them, sized for this plot (the launch tyre is 8 studs across), facing the lane
-- along their local +Z.
local BUILD = {
	cannon = function(m: Model, at: CFrame, level: number)
		local elev = math.rad(26)
		local len = 16 + level * 0.35
		part(m, Vector3.new(14, 1.6, 12), at * CFrame.new(0, 0.8, 0), DARK, Enum.Material.Metal)
		for _, z in ipairs({ -6.2, 6.2 }) do
			part(m, Vector3.new(5, 7.5, 1.4), at * CFrame.new(-1, 5.3, z), STEEL, Enum.Material.Metal)
		end
		local pivot = at * CFrame.new(-1, 9, 0) * CFrame.Angles(0, 0, elev)
		local barrel = cyl(m, len, 10.5, pivot * CFrame.new(len / 2 - 4, 0, 0), C.red, Enum.Material.SmoothPlastic)
		barrel.Name = "Barrel"
		for i, x in ipairs({ -2.5, len * 0.45, len - 4.6 }) do
			local band = cyl(m, i == 3 and 1.8 or 1.1, 11.4, pivot * CFrame.new(x, 0, 0), DARK, Enum.Material.Metal)
			band.Name = "BarrelBand"
		end
		local cap = cyl(m, 1.2, 11, pivot * CFrame.new(-4.6, 0, 0), DARK, Enum.Material.Metal)
		cap.Name = "BarrelCap"
	end,
	fuel = function(m: Model, at: CFrame, level: number)
		part(m, Vector3.new(10, 0.8, 9.6), at * CFrame.new(0, 0.4, 0), CONCRETE, Enum.Material.Concrete)
		for _, x in ipairs({ -2.2, 2.2 }) do
			for _, z in ipairs({ -2.2, 2.2 }) do
				part(m, Vector3.new(1, 2.4, 1), at * CFrame.new(x, 2, z), DARK, Enum.Material.Metal)
			end
		end
		cyl(m, 7.6, 7.2, at * CFrame.new(0, 7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 64, 46), Enum.Material.SmoothPlastic)
		part(m, Vector3.new(7.2, 3, 7.2), at * CFrame.new(0, 10.8, 0), Color3.fromRGB(190, 58, 42), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		for _, y in ipairs({ 4.6, 9.2 }) do
			cyl(m, 0.7, 7.6, at * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), DARK, Enum.Material.Metal)
		end
		cyl(m, 0.5, 1.8, at * CFrame.new(-1.4, 7.4, 3.65) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(240, 238, 230))
	end,
	cooling = function(m: Model, at: CFrame, level: number)
		part(m, Vector3.new(10.4, 0.8, 10.4), at * CFrame.new(0, 0.4, 0), CONCRETE, Enum.Material.Concrete)
		part(m, Vector3.new(7.6, 5.6, 7.6), at * CFrame.new(0, 3.8, 0), Color3.fromRGB(96, 160, 236), Enum.Material.SmoothPlastic)
		for i = 0, 4 do
			part(m, Vector3.new(6.4, 0.3, 0.3), at * CFrame.new(0, 1.9 + i * 0.95, 3.9), Color3.fromRGB(236, 240, 244))
		end
		part(m, Vector3.new(8, 0.6, 8), at * CFrame.new(0, 6.9, 0), Color3.fromRGB(236, 240, 244))
		cyl(m, 1.6, 6.6, at * CFrame.new(0, 8, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(236, 240, 244))
		cyl(m, 0.3, 5.6, at * CFrame.new(0, 8.85, 0) * CFrame.Angles(0, 0, math.rad(90)), DARK, Enum.Material.Metal)
	end,
	compressor = function(m: Model, at: CFrame, level: number)
		local teal = Color3.fromRGB(32, 174, 184)
		cyl(m, 9, 4.4, at * CFrame.new(0, 3.6, 0), teal)
		for _, x in ipairs({ -4.5, 4.5 }) do
			part(m, Vector3.new(2.2, 4.4, 4.4), at * CFrame.new(x, 3.6, 0), teal, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		end
		part(m, Vector3.new(6, 0.4, 3.6), at * CFrame.new(0, 6, 0), STEEL, Enum.Material.Metal)
		cyl(m, 3, 2.4, at * CFrame.new(-1.6, 7.4, 0), Color3.fromRGB(214, 60, 48))
		part(m, Vector3.new(2, 2.4, 2.2), at * CFrame.new(1.8, 7.4, 0), DARK, Enum.Material.Metal)
		for _, z in ipairs({ -2.6, 2.6 }) do
			cyl(m, 0.8, 2.6, at * CFrame.new(-4, 1.3, z) * CFrame.Angles(0, math.rad(90), 0), DARK, Enum.Material.Metal)
		end
	end,
	rack = function(m: Model, at: CFrame, level: number)
		local purple = Color3.fromRGB(150, 96, 240)
		for _, x in ipairs({ -9.5, 9.5 }) do
			for _, z in ipairs({ -2.6, 2.6 }) do
				part(m, Vector3.new(0.7, 10, 0.7), at * CFrame.new(x, 5, z), purple, Enum.Material.Metal)
			end
		end
		part(m, Vector3.new(20, 0.8, 0.8), at * CFrame.new(0, 10.2, 0), purple, Enum.Material.Metal)
		for _, z in ipairs({ -1.8, 1.8 }) do
			cyl(m, 19, 0.6, at * CFrame.new(0, 1.4, z), STEEL, Enum.Material.Metal)
		end
		part(m, Vector3.new(21, 0.5, 6.4), at * CFrame.new(0, 0.25, 0), DARK, Enum.Material.Metal)
	end,
}

-- per machine: how big the imported model is drawn and where its level plate goes; where it stands
-- comes from the yard's layout (Game.Yard, moved in YardEdit)
-- the machines (art/blender/props3.py, proof.py) are built at their in-game size; the cannons
-- (cannons2.py) are drawn at two thirds
Plot2.ModelScale = { cannon = 0.667, ramp = 1, fuel = 1, cooling = 1, compressor = 1, rack = 1 }
local PLATE = {
	cannon = Vector3.new(6, 0, 9),
	ramp = Vector3.new(-1, 0, 10),
	fuel = Vector3.new(7.4, 0, 7),
	cooling = Vector3.new(8.3, 0, 8.3),
	compressor = Vector3.new(5.6, 0, 5.6),
	rack = Vector3.new(10.8, 0, 4.8),
}
local OLD_RIG = { "LauncherRig", "Cradle", "Operator", "LaunchControl", "LaunchTyre", "Ramp" }
-- block stand-ins for machines whose models aren't imported yet: off, so the yard never shows
-- placeholder art; a machine appears when its model does (the level plate is there either way)
local SHOW_STANDINS = false

-- a small level plate on a post at the machine's corner nearest the lane
local function levelPlate(m: Model, at: CFrame, id: string, level: number)
	local off = PLATE[id] or Vector3.new(5, 0, 5)
	part(m, Vector3.new(0.35, 3.2, 0.35), at * CFrame.new(off + Vector3.new(0, 1.6, 0)), DARK, Enum.Material.Metal).Name = "PlatePost"
	local plate = part(m, Vector3.new(3, 1.5, 0.25), at * CFrame.new(off + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, math.pi, 0), COLORS[id])
	plate.Name = "LevelPlate"
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 60
	sg.LightInfluence = 0.4
	sg.Parent = plate
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.BuilderSansExtraBold
	t.Text = ("LV %d"):format(level)
	t.TextScaled = true
	t.TextColor3 = C.white
	t.Parent = sg
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = t
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = C.ink
	stroke.Parent = t
end

local function hideOldRig(plot: Instance)
	for _, name in ipairs(OLD_RIG) do
		local m = plot:FindFirstChild(name)
		if m then
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
					(d :: any).LocalTransparencyModifier = 1
				end
				if d:IsA("BasePart") then d.CanCollide = false end
				if d:IsA("ParticleEmitter") or d:IsA("Light") then (d :: any).Enabled = false end
			end
		end
	end
end

function Plot2:watchYards()
	local lobby = workspace:WaitForChild("Lobby", 30)
	local plots = lobby and lobby:WaitForChild("Plots", 30)
	if not plots then return end
	for _, plot in ipairs(plots:GetChildren()) do self:watchYard(plot) end
	plots.ChildAdded:Connect(function(plot) self:watchYard(plot) end)
	-- the old launcher rig stands until the new cannons are imported; then it's retired and kept
	-- hidden (other systems may touch parts of it)
	task.spawn(function()
		while not Models.get("Cannons/Cannon1") do task.wait(3) end
		-- (2026-10-24: the place streams, so a rig part that streams back in shows until the next sweep;
		-- hide it as it arrives too)
		for _, plot in ipairs(plots:GetChildren()) do
			local queued = false
			plot.DescendantAdded:Connect(function(d)
				if queued or not d:IsA("BasePart") then return end
				queued = true
				task.defer(function()
					queued = false
					hideOldRig(plot)
				end)
			end)
		end
		while true do
			for _, plot in ipairs(plots:GetChildren()) do hideOldRig(plot) end
			task.wait(3)
		end
	end)
end

function Plot2:watchYard(plot: Instance)
	if self.yards[plot] then return end
	self.yards[plot] = { machines = {}, levels = {}, at = {}, loc = {} }
	local function refresh() self:buildYard(plot) end
	for _, mdef in ipairs(Game.Machines) do
		plot:GetAttributeChangedSignal("V2_" .. mdef.id):Connect(refresh)
	end
	plot:GetAttributeChangedSignal("V2_Tier"):Connect(refresh)
	plot:GetAttributeChangedSignal("V2_Layout"):Connect(refresh)
	plot:GetAttributeChangedSignal("V2_Prestige"):Connect(refresh)
	plot:GetAttributeChangedSignal("V2_Look"):Connect(refresh)
	plot:GetAttributeChangedSignal("V2_Showcase"):Connect(refresh)
	refresh()
end

-- the yard's layout as the server last published it (the default until it has)
function Plot2:layoutOf(plot: Instance): Game.YardLayout
	return Game.yardDecode(plot:GetAttribute("V2_Layout") :: string?)
end

-- stands a unit's machines where `layout` puts it; `lift` raises (and tips) it, for the yard editor
function Plot2:placeUnit(plot: Instance, layout: Game.YardLayout, unitId: string, lift: CFrame?)
	local y = self.yards[plot]
	local base = plot:GetAttribute("BaseCFrame") :: CFrame?
	local u = Game.YardUnits[unitId]
	if not (y and base and u) then return end
	for _, md in ipairs(u.machines) do
		local m = y.machines[md.id]
		local loc = y.loc[md.id]
		if m and loc then
			local at = base * Game.yardSpot(layout, md.id)
			if lift then
				-- lifted about the unit's own point, so a long launcher tips as one piece
				local s = layout[unitId]
				local origin = base * CFrame.new(s.x, 2, s.z)
				at = origin * lift * origin:Inverse() * at
			end
			m:PivotTo(at * loc)
			y.at[md.id] = at
		end
	end
end

-- the decor on a yard: the game's own models, each seated by its bounding box so its bottom centre
-- lands on its spot. Pieces are kept and moved where the list allows, so dragging one doesn't
-- rebuild the rest. `lifts` raises (and tips) pieces by index, for the yard editor.
function Plot2:renderDecor(plot: Instance, decor: { Game.DecorSpot }, lifts: { [number]: CFrame }?)
	local y = self.yards[plot]
	local base = plot:GetAttribute("BaseCFrame") :: CFrame?
	if not (y and base) then return end
	local folder = plot:FindFirstChild("Decor2")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Decor2"
		folder.Parent = plot
	end
	y.decor = y.decor or {}
	for i, d in ipairs(decor) do
		local e = y.decor[i]
		local kind = Game.YardDecorById[d.k]
		local tint = if kind and kind.build then NeonDecor.optsFor(plot) else nil
		local tintKey = if tint then table.concat({ tostring(tint.color), tostring(tint.a), tostring(tint.level), tostring(tint.showcase) }, "|") else nil
		if e and (e.k ~= d.k or e.tint ~= tintKey) then
			e.model:Destroy()
			e = nil
			y.decor[i] = nil
		end
		if not e then
			local tpl = kind and not kind.build and Models.get(kind.path)
			local built = kind and kind.build and NeonDecor.build(kind.id, tint)
			if built then built.Parent = folder end
			if tpl or built then
				local m = built or Models.place(tpl, folder, CFrame.new(), 1, true)
				local cf, size = m:GetBoundingBox()
				local seat = m:GetPivot():PointToObjectSpace(cf.Position - Vector3.new(0, size.Y / 2, 0))
				e = { k = d.k, model = m, seat = seat, tint = tintKey }
				y.decor[i] = e
			end
		end
		if e then
			-- (`a` may be fractional while the editor eases it round)
			local steps = if type(d.a) == "number" then d.a else (d.r % 4) * 6
			local at = base * CFrame.new(d.x, 2, d.z) * CFrame.Angles(0, math.rad(steps * 15), 0)
			if lifts and lifts[i] then at = at * lifts[i] end
			e.model:PivotTo(at * CFrame.new(-e.seat))
		end
	end
	for i = #decor + 1, #y.decor do
		if y.decor[i] then y.decor[i].model:Destroy() end
		y.decor[i] = nil
	end
end

-- the machine models making up a unit on a yard
function Plot2:unitModels(plot: Instance, unitId: string): { Model }
	local y = self.yards[plot]
	local u = Game.YardUnits[unitId]
	local out = {}
	if not (y and u) then return out end
	for _, md in ipairs(u.machines) do
		if y.machines[md.id] then table.insert(out, y.machines[md.id]) end
	end
	return out
end

function Plot2:buildYard(plot: Instance)
	local y = self.yards[plot]
	local base = plot:GetAttribute("BaseCFrame") :: CFrame?
	if not (y and base) then return end
	local owned = plot:GetAttribute("V2_Tier") ~= nil
	local folder = plot:FindFirstChild("Machines2")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Machines2"
		folder.Parent = plot
	end
	-- the lobby's old launch ramp stays out of sight: the cannon fires from its own barrel now
	local oldRamp = plot:FindFirstChild("Ramp")
	if oldRamp then
		for _, d in ipairs(oldRamp:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 end
		end
	end
	local layout = self:layoutOf(plot)
	for _, mdef in ipairs(Game.Machines) do
		local id = mdef.id
		-- (2026-10-23, the owner: "the plot should have all the fuel tank cooling etc. before they're level
		-- one ... the unclaimed plots ... look terrible") every machine stands on every yard from level 0,
		-- and a yard nobody has yet shows the starter yard, not a bare slab
		-- (2026-10-24, the owner: an unclaimed yard shows no launch gear at all, just its sandy ground and
		-- its fence: you're given a yard as you join, so a free one is plainly free)
		local level = if owned then (plot:GetAttribute("V2_" .. id) or 0) else nil
		-- a machine that's already standing just moves if the layout changed (unless it's being edited)
		local spot = base * Game.yardSpot(layout, id)
		local standing = y.machines[id]
		if standing and level == y.levels[id] and y.at[id] and not y.editing then
			if (y.at[id].Position - spot.Position).Magnitude > 0.05 or y.at[id].LookVector:Dot(spot.LookVector) < 0.999 then
				standing:PivotTo(spot * y.loc[id])
				y.at[id] = spot
			end
		end
		local tierNow = (plot:GetAttribute("V2_Tier") :: number?) or 1
		if level ~= y.levels[id] or (id == "cannon" and y.cannonTier ~= tierNow) then
			if id == "cannon" then y.cannonTier = tierNow; y.trimLevel = nil end
			if y.machines[id] then y.machines[id]:Destroy() end
			y.machines[id] = nil
			local had = y.levels[id]
			y.levels[id] = level
			-- a machine stands on the yard once it's bought (the cannon from the start)
			if level then
				local m = Instance.new("Model")
				m.Name = id
				local at = spot
				local racing = Models.get(RACING_MODEL[id])
				local path = if id == "cannon" then ("Cannons/Cannon" .. Game.cannonBuild((plot:GetAttribute("V2_Tier") :: number?) or 1)) else MACHINE_MODEL[id]
				local tpl = racing or (path and Models.get(path))
				if tpl then
					local placed = Models.place(tpl, m, at, Plot2.ModelScale[id] or 1, true)
					if racing then
						Plot2.trimToLevel(placed, Plot2.lookStep(id, level))
						Plot2.paintStage(placed, tierNow)
					else
						for _, p in ipairs(Models.parts(placed)) do
							if p.Name:find("Barrel") then p.Name = "Barrel" end
						end
					end

				elseif BUILD[id] and SHOW_STANDINS then
					BUILD[id](m, at, level)
				end
				if owned then levelPlate(m, at, id, level) end
				m.Parent = folder
				y.machines[id] = m
				y.at[id] = at
				y.loc[id] = at:Inverse() * m:GetPivot()
				-- a level bought since the last look gets the install animation (on your own yard)
				if plot == self.plot and had ~= nil and level > had then self:install(m) end
			end
		end
	end
	-- the cannon's prestige trim (PrestigeLook), redone when the cannon is rebuilt or the level moves
	local prestige = if owned then ((plot:GetAttribute("V2_Prestige") :: number?) or 0) else 0
	if y.machines.cannon and y.trimLevel ~= prestige then
		y.trimLevel = prestige
		PrestigeLook.trimCannon(y.machines.cannon, prestige, Plot2.ModelScale.cannon)
	end
	-- the decor (the yard editor draws it itself while it's open) and the yard's look
	if not y.editing then
		self:renderDecor(plot, if owned then (layout.decor or {}) else {})
		YardLook.apply(plot, layout)
	end
end

function Plot2.paintStage(model: Instance, tier: number)
	local looks = model:FindFirstChild("StageLooks")
	local look = looks and looks:FindFirstChild("T" .. tier)
	if looks then looks:Destroy() end
	if not (look and look:IsA("SurfaceAppearance")) then return end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("MeshPart") then
			local old = p:FindFirstChildWhichIsA("SurfaceAppearance")
			if old then old:Destroy() end
			look:Clone().Parent = p
		end
	end
end

function Plot2:attach(plot: Instance?)
	self.plot = plot
end

-- the cannon standing on a yard, for the launch
function Plot2:cannonOf(plot: Instance?): Model?
	local y = plot and self.yards[plot]
	return y and y.machines.cannon or nil
end

-- the install: the machine drops in from above, lands with a bounce and a ring of dust
function Plot2:install(m: Model)
	local pivot = m:GetPivot()
	m:PivotTo(pivot * CFrame.new(0, 26, 0))
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - t0) / 0.55, 0, 1)
		local y = 26 * (1 - t) ^ 2
		if t >= 1 then
			local bt = os.clock() - t0 - 0.55
			y = math.max(0, math.sin(bt * 14) * 2.2 * math.exp(-bt * 7))
			if bt > 0.6 then
				conn:Disconnect()
				if m.Parent then m:PivotTo(pivot) end
				return
			end
		end
		if m.Parent then m:PivotTo(pivot * CFrame.new(0, y, 0)) end
	end)
	task.delay(0.55, function()
		pcall(function()
			local PackFX = require(script.Parent.PackFX) :: any
			PackFX.burst("dustRing", pivot, 16, nil, 1.2)
		end)
	end)
end

return Plot2
