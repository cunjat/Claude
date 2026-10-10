--!strict
-- TYRE CANNON :: Receipt2
-- The payout, short and loud: the distance, then each thing that paid stacks up with a pop and a
-- tick, the total counts up, keys and newly unlocked zones pop in, NEW BEST slams down, and two
-- big buttons: LAUNCH AGAIN (the default) and UPGRADE.
--   Receipt2.show(gui, summary, payout, onAgain, onUpgrade)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local C = Kit.C

local Receipt2 = {}

local function tick()
	pcall(function()
		local Sound = require(script.Parent.Sound) :: any
		Sound.play("tick", { volume = 0.25 })
	end)
end

function Receipt2.show(gui: ScreenGui, summary, payout, onAgain: () -> (), onUpgrade: () -> ())
	local dim = UI.mk("Frame", {
		Name = "Receipt2", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
		ZIndex = 40, Parent = gui,
	})
	Kit.tween(dim, 0.25, { BackgroundTransparency = 0.45 })
	local box = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 560),
		BackgroundTransparency = 1, ZIndex = 41, Parent = dim,
	})
	UI.autoScale(box, 1280, 760)
	local holder, face = Kit.card(UDim2.fromOffset(520, 470), C.cream, 20, 9)
	holder.Parent = box
	Kit.header(face, payout.blowout and "Blowout!" or "Run Complete", if payout.blowout then C.red else C.accent, 56)
	Kit.pop(holder, 0.6, 0.35)

	local dist = Kit.text(Game.metres(payout.metres or summary.metres), 68, C.white, 2.5)
	dist.AnchorPoint = Vector2.new(0.5, 0)
	dist.Position = UDim2.new(0.5, 0, 0, 52)
	dist.Size = UDim2.fromOffset(480, 80)
	dist.ZIndex = 4
	dist.Parent = face
	local zone = Game.Zones[payout.zone or 1]
	local where = Kit.text("in the " .. zone.name, 18, C.muted, 1.5, Kit.Body)
	where.AnchorPoint = Vector2.new(0.5, 0)
	where.Position = UDim2.new(0.5, 0, 0, 124)
	where.Size = UDim2.fromOffset(480, 22)
	where.ZIndex = 4
	where.Parent = face

	-- the lines that paid, one by one
	local rows = {}
	local b = payout.breakdown or {}
	local parts = b.parts or {}
	local function row(label: string, value: string, color: Color3?)
		table.insert(rows, { label = label, value = value, color = color or C.gold })
	end
	row("Distance", "$" .. Game.short(b.base or 0))
	if (b.combo or 1) > 1.001 then row(("Chain  ·  %d bounces"):format(payout.bounces or 0), ("x%s"):format(Game.multText(b.combo)), C.yellow) end
	if (b.smash or 0) > 0 then row(("Smashes x%d"):format(payout.smashes or 0), "$" .. Game.short(b.smash)) end
	if (b.coins or 0) > 0 then row("Coins", "$" .. Game.short(b.coins)) end
	if (b.tricks or 0) > 0 then row("Perfects and air", "$" .. Game.short(b.tricks)) end
	if (parts.tyres or 1) > 1.001 then row("Tyres", ("x%.2f"):format(parts.tyres), C.purple) end
	if (parts.overhaul or 1) > 1.001 then row("Overhauls", ("x%.1f"):format(parts.overhaul), C.orange) end
	if (parts.bought or 1) > 1.001 then row("Boosts", ("x%g"):format(parts.bought), C.green) end
	if (parts.friends or 1) > 1.001 then row("Friends", ("x%.1f"):format(parts.friends), C.blue) end
	if (b.showboat or 1) > 1.001 then row("Showboat", "x1.25", C.yellow) end
	Kit.section(face, "Paid Out", UDim2.fromOffset(30, 152), UDim2.fromOffset(460, 28), 4)
	local y = 190
	for i, r in ipairs(rows) do
		local line = UI.mk("Frame", { Position = UDim2.fromOffset(30, y + (i - 1) * 34), Size = UDim2.fromOffset(460, 30), BackgroundTransparency = 1, ZIndex = 4, Parent = face })
		local l = Kit.text(r.label, 21, C.text, 1.5, Kit.Body)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Size = UDim2.fromScale(0.6, 1)
		l.ZIndex = 4
		l.Parent = line
		local v = Kit.text(r.value, 22, r.color, 1.5)
		v.AnchorPoint = Vector2.new(1, 0)
		v.Position = UDim2.fromScale(1, 0)
		v.TextXAlignment = Enum.TextXAlignment.Right
		v.Size = UDim2.fromScale(0.4, 1)
		v.ZIndex = 4
		v.Parent = line
		line.Visible = false
		task.delay(0.35 + i * 0.16, function()
			Kit.appear(line, 0, 12)
			tick()
		end)
	end
	-- the total
	local totalY = y + #rows * 34 + 14
	Kit.divider(face, UDim2.new(0.5, 0, 0, totalY), UDim.new(0, 460), 4)
	local total = Kit.text("$0", 52, C.gold, 2.5)
	total.AnchorPoint = Vector2.new(0.5, 0)
	total.Position = UDim2.new(0.5, 0, 0, totalY + 10)
	total.Size = UDim2.fromOffset(460, 60)
	total.ZIndex = 4
	total.Parent = face
	total.Visible = false
	local tStart = 0.45 + #rows * 0.16
	task.delay(tStart, function()
		total.Visible = true
		Kit.countUp(total, 0, payout.cash or 0, 0.9, function(v) return "+$" .. Game.short(v) end, tick)
	end)
	holder.Size = UDim2.fromOffset(520, totalY + 90)

	-- keys, new zones, best, overhaul: badges under the card
	local badges = {}
	local keys = (payout.keys or 0) + (payout.streakKey or 0)
	if keys > 0 then table.insert(badges, { ("+%d Key%s"):format(keys, keys == 1 and "" or "s"), C.yellow }) end
	for _, id in ipairs(payout.newZones or {}) do
		table.insert(badges, { Game.ZonesById[id].name .. " unlocked: new crate and a new start", C.teal })
	end
	if payout.canOverhaul then table.insert(badges, { "Plot upgrade affordable", C.accent }) end
	for i, bdg in ipairs(badges) do
		local l = Kit.text(bdg[1], 24, bdg[2], 2.5)
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, 0, totalY + 96 + (i - 1) * 34)
		l.Size = UDim2.fromOffset(500, 30)
		l.ZIndex = 45
		l.Visible = false
		l.Parent = box
		task.delay(tStart + 1.0 + i * 0.2, function()
			l.Visible = true
			Kit.pop(l, 0.4, 0.3)
		end)
	end
	if payout.best then
		-- a red chip that slams onto the card's corner
		local stamp = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -78, 0, 70), Size = UDim2.fromOffset(170, 44), Rotation = 0,
			BackgroundTransparency = 1, ZIndex = 46, Visible = false, Parent = box,
		})
		Kit.slice("pill", C.red, stamp, 46, 0.6)
		local st = Kit.text("New Best!", 26, C.white, 2)
		st.Size = UDim2.fromScale(1, 1)
		st.ZIndex = 47
		st.Parent = stamp
		task.delay(tStart + 0.9, function()
			stamp.Visible = true
			Kit.pop(stamp, 2.4, 0.18)
			Kit.shake(holder, 8, 0.25)
		end)
	end

	-- the buttons
	local btnY = totalY + 96 + #badges * 34 + 10
	-- two buttons the same width, either side of the card's centre line
	local again = Kit.button("Launch Again", C.accent, UDim2.fromOffset(238, 64), 24)
	again.root.AnchorPoint = Vector2.new(1, 0)
	again.root.Position = UDim2.new(0.5, -7, 0, btnY)
	again.root.ZIndex = 45
	again.root.Visible = false
	again.root.Parent = box
	local upgrade = Kit.button("Upgrade", C.blue, UDim2.fromOffset(238, 64), 24)
	upgrade.root.Position = UDim2.new(0.5, 7, 0, btnY)
	upgrade.root.ZIndex = 45
	upgrade.root.Visible = false
	upgrade.root.Parent = box
	-- the X: close the receipt and stay home (no upgrade, no second launch)
	local xBtn = Kit.close(48)
	xBtn.root.AnchorPoint = Vector2.new(0.5, 0.5)
	xBtn.root.Position = UDim2.new(1, -4, 0, 4)
	xBtn.root.ZIndex = 50
	xBtn.root.Parent = box
	local closed = false
	local conn: RBXScriptConnection? = nil
	local function close(after: () -> ())
		if closed then return end
		closed = true
		if conn then conn:Disconnect() end
		Receipt2.active = nil
		if Receipt2.onShown then Receipt2.onShown(false) end
		Kit.vanish(box, 0.18)
		Kit.tween(dim, 0.25, { BackgroundTransparency = 1 })
		task.delay(0.26, function()
			dim:Destroy()
			after()
		end)
	end
	xBtn.onClick = function() close(function() end) end
	again.onClick = function() close(onAgain) end
	upgrade.onClick = function() close(onUpgrade) end
	-- anything else that wants the screen (a dock panel) closes the receipt first and waits for it
	Receipt2.active = close
	-- the hub's own Launch steps aside while the receipt offers Launch Again
	if Receipt2.onShown then Receipt2.onShown(true) end
	task.delay(tStart + 1.1, function()
		Kit.appear(again.root, 0, 20)
		Kit.appear(upgrade.root, 0.08, 20)
	end)
	-- keyboard: R or Enter launches again
	conn = UserInputService.InputBegan:Connect(function(io, processed)
		if processed or closed then return end
		if io.KeyCode == Enum.KeyCode.R or io.KeyCode == Enum.KeyCode.Return or io.KeyCode == Enum.KeyCode.ButtonA then
			if again.root.Visible then
				close(onAgain)
			end
		elseif io.KeyCode == Enum.KeyCode.Escape or io.KeyCode == Enum.KeyCode.ButtonB then
			close(function() end)
		end
	end)
end

return Receipt2
