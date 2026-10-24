--!strict
-- TYRE CANNON :: HudUI (v3, the bounce run)
-- What you read while you bounce, in the kit4 look (art/ui/kit4.py):
--   top centre     how far, the zone rail to the next zone, and your best
--   top left       which zone and its rate, coins picked up, who's watching
--   right          the CHAIN: the multiplier you're carrying, big, and how many bounces in a row
--   bottom right   the speed on a slanted bar, the boost charges as pips beside it
--   bottom centre  the slam cue: lights green when a slam now would be a PERFECT
--   the middle     PERFECT / GOOD stamps, CHAIN LOST, keys, smashes
-- HudUI.new(gui) · :setTrack(zone, best) · :show() · :hide() · :update(tick) · :event(e) · :setWatchers(n)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules")
local Config = require(Modules.Config)
local Game = require(Modules.Game)
local UI = require(script.Parent.UI)
local Icons = require(script.Parent.Icons)
local Kit = require(script.Parent.Kit)
local C = Kit.C
local P = Config.Physics
local B = Config.Run
-- the zone lines, in studs (the rail runs zone to zone; Config's checkpoints are difficulty only)
local GATES = {}
for i = 2, #Game.Zones do GATES[i - 1] = Game.Zones[i].start / Game.StudsToMetres end

local HudUI = {}
HudUI.__index = HudUI

local RAIL_W = 540
local RAIL_INNER = RAIL_W - 12
local CENTRE = Enum.TextXAlignment.Center
local ITALIC = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local SPEED_MAX = 1100      -- studs/s at a full bar
local PERFECT = Color3.fromRGB(255, 214, 72)
local GOOD = Color3.fromRGB(118, 236, 120)

local function corner(parent: Instance, anchor: Vector2, pos: UDim2, size: Vector2): Frame
	local f = UI.mk("Frame", {
		AnchorPoint = anchor, Position = pos, Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1, Parent = parent,
	})
	UI.autoScale(f)
	return f
end

-- the zone-to-zone stretch a distance (studs) sits on: where it starts, where it ends (-1 past the
-- last), and the number of the zone it's heading for
local function stretchAt(x: number): (number, number, number)
	local from, to, n = 0, GATES[1], 1
	for i, d in ipairs(GATES) do
		if x >= d then
			from = d
			to = GATES[i + 1] or -1
			n = i + 1
		end
	end
	return from, to, n
end

local function stroke(l: TextLabel, t: number, trans: number?)
	local s = l:FindFirstChildOfClass("UIStroke") or UI.mk("UIStroke", { Color = C.ink, LineJoinMode = Enum.LineJoinMode.Round, Parent = l })
	s.Thickness = t
	s.Transparency = trans or 0.05
end

function HudUI.new(parent: ScreenGui)
	local self = setmetatable({}, HudUI)
	self.onDraftPick = nil
	self.bestValue = 0
	self.beaten = false
	self.lastClock = os.clock()
	self.shownChain = 0
	self.speedShown = 0

	local root = UI.mk("Frame", { Name = "HUD", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = parent })
	self.root = root
	self.slides = {}
	local function slide(f: Frame, from: UDim2)
		table.insert(self.slides, { frame = f, rest = f.Position, from = f.Position + from })
	end

	-- (2026-10-24) on a phone the right thumb's pads (TouchControls) fill the bottom right, so the speed
	-- moves up under BAIL / VIEW and the chain goes to the left, beside the altimeter
	local touchLayout = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
		or (game:GetService("RunService"):IsStudio() and workspace:GetAttribute("ForceTouch") == true)
	---------------------------------------------------------------
	-- top centre: distance and the zone rail
	---------------------------------------------------------------
	local tc = corner(root, Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 8), Vector2.new(RAIL_W + 80, 130))
	slide(tc, UDim2.fromOffset(0, -170))
	self.dist = Kit.text("0", 58, C.white, 3, ITALIC)
	self.dist.AnchorPoint = Vector2.new(0.5, 0)
	self.dist.Position = UDim2.fromScale(0.5, 0)
	self.dist.Size = UDim2.new(1, 0, 0, 62)
	self.dist.Parent = tc
	local rail = UI.mk("Frame", {
		Name = "Rail", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 68), Size = UDim2.fromOffset(RAIL_W, 24),
		BackgroundTransparency = 1, Parent = tc,
	})
	Kit.slice("track", nil, rail, 1, 0.5)
	local fill = UI.mk("Frame", {
		Position = UDim2.fromOffset(6, 6), Size = UDim2.new(0, 0, 1, -12), BackgroundTransparency = 1, ClipsDescendants = true,
		BorderSizePixel = 0, ZIndex = 2, Parent = rail,
	})
	local strip = UI.mk("Frame", { Size = UDim2.fromOffset(RAIL_INNER, 12), BackgroundTransparency = 1, ZIndex = 2, Parent = fill })
	Kit.slice("fill", C.accent, strip, 2, 12 / Kit.Art.fill.h)
	self.railFill = fill
	self.marker = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1, Image = Icons.Hud.marker, ZIndex = 4, Parent = rail,
	})
	self.bestTick = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.fromOffset(4, 32),
		BackgroundColor3 = C.gold, BorderSizePixel = 0, ZIndex = 3, Visible = false, Parent = rail,
	})
	UI.stroke(Color3.new(0, 0, 0), 1.5, 0.2).Parent = self.bestTick
	local function under(x: number, anchorX: number, align: Enum.TextXAlignment, color: Color3): TextLabel
		local l = Kit.text("", 13, color, 1.5, Kit.Body)
		l.AnchorPoint = Vector2.new(anchorX, 0)
		l.Position = UDim2.new(0.5, x, 0, 96)
		l.Size = UDim2.fromOffset(240, 16)
		l.TextXAlignment = align
		l.Parent = tc
		return l
	end
	self.fromLabel = under(-RAIL_W / 2 + 4, 0, Enum.TextXAlignment.Left, C.muted)
	self.toLabel = under(RAIL_W / 2 - 4, 1, Enum.TextXAlignment.Right, C.text)
	self.bestLabel = under(0, 0.5, CENTRE, C.gold)

	---------------------------------------------------------------
	-- top left: zone, coins, watchers
	---------------------------------------------------------------
	local tl = corner(root, Vector2.new(0, 0), UDim2.fromOffset(24, 70), Vector2.new(320, 110))
	slide(tl, UDim2.fromOffset(-380, 0))
	self.road = Kit.text("", 22, C.white, 2)
	self.road.TextXAlignment = Enum.TextXAlignment.Left
	self.road.Size = UDim2.fromOffset(320, 26)
	self.road.Parent = tl
	self.roadSub = Kit.text("", 13, C.gold, 1.5, Kit.Body)
	self.roadSub.TextXAlignment = Enum.TextXAlignment.Left
	self.roadSub.Position = UDim2.fromOffset(0, 26)
	self.roadSub.Size = UDim2.fromOffset(320, 16)
	self.roadSub.Parent = tl
	self.metalRow = UI.mk("Frame", {
		Position = UDim2.fromOffset(0, 50), Size = UDim2.fromOffset(320, 22), BackgroundTransparency = 1, Parent = tl,
	}, { UI.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	self.metalCells = {}
	for i, def in ipairs(Config.Metals) do
		local cell = UI.mk("Frame", {
			Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = i,
			Visible = false, Parent = self.metalRow,
		}, { UI.list(Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
		UI.mk("ImageLabel", { Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Image = (Icons.Coin :: any)[def.id], LayoutOrder = 1, Parent = cell })
		local n = Kit.text("0", 16, C.white, 1.5)
		n.Size = UDim2.fromOffset(0, 20)
		n.AutomaticSize = Enum.AutomaticSize.X
		n.LayoutOrder = 2
		n.Parent = cell
		self.metalCells[def.id] = { cell = cell, count = n, shown = 0 }
	end
	self.watch = Kit.text("", 13, C.green, 1.5, Kit.Body)
	self.watch.TextXAlignment = Enum.TextXAlignment.Left
	self.watch.Position = UDim2.fromOffset(0, 78)
	self.watch.Size = UDim2.fromOffset(320, 16)
	self.watch.Visible = false
	self.watch.Parent = tl

	---------------------------------------------------------------
	-- right: the chain
	---------------------------------------------------------------
	local cr = if touchLayout
		then corner(root, Vector2.new(0, 0.5), UDim2.new(0, 96, 0.56, 0), Vector2.new(230, 150))
		else corner(root, Vector2.new(1, 0.5), UDim2.new(1, -28, 0.36, 0), Vector2.new(230, 150))
	slide(cr, UDim2.fromOffset(if touchLayout then -420 else 300, 0))
	local chainBox = UI.mk("Frame", { Size = UDim2.fromOffset(230, 132), BackgroundTransparency = 1, Parent = cr })
	Kit.slice("panel_body", nil, chainBox, 1, 0.4)
	self.chainRing = Kit.slice("panel_ring", C.accent, chainBox, 2, 0.4)
	self.chainBox = chainBox
	local chainCap = Kit.text("CHAIN", 14, C.muted, 1.5, Kit.Body)
	chainCap.Position = UDim2.fromOffset(0, 10)
	chainCap.Size = UDim2.new(1, 0, 0, 16)
	chainCap.ZIndex = 4
	chainCap.Parent = chainBox
	self.mult = Kit.text("x1", 54, C.white, 3, ITALIC)
	self.mult.Position = UDim2.fromOffset(0, 26)
	self.mult.Size = UDim2.new(1, 0, 0, 60)
	self.mult.ZIndex = 4
	self.mult.Parent = chainBox
	self.multScale = UI.mk("UIScale", { Parent = self.mult })
	self.chainCount = Kit.text("", 15, C.gold, 1.5, Kit.Body)
	self.chainCount.Position = UDim2.fromOffset(0, 86)
	self.chainCount.Size = UDim2.new(1, 0, 0, 18)
	self.chainCount.ZIndex = 4
	self.chainCount.Parent = chainBox
	-- ten pips: the multiplier's way to x10
	self.chainPips = {}
	for i = 1, 12 do
		local pip = UI.mk("Frame", {
			Position = UDim2.fromOffset(19 + (i - 1) * 16, 110), Size = UDim2.fromOffset(12, 8), BackgroundColor3 = C.well,
			BorderSizePixel = 0, ZIndex = 4, Parent = chainBox,
		}, { UI.corner(3) })
		self.chainPips[i] = pip
	end

	---------------------------------------------------------------
	-- bottom right: speed on a slanted bar, boost charges as pips
	---------------------------------------------------------------
	local br = if touchLayout
		then corner(root, Vector2.new(1, 0), UDim2.new(1, -24, 0, 80), Vector2.new(400, 150))
		else corner(root, Vector2.new(1, 1), UDim2.new(1, -24, 1, -22), Vector2.new(400, 150))
	slide(br, UDim2.fromOffset(if touchLayout then 460 else 0, if touchLayout then 0 else 220))
	local tilt = UI.mk("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -6), Size = UDim2.fromOffset(370, 36), BackgroundTransparency = 1, Rotation = -7, Parent = br })
	local track, speedFill = Kit.bar(370, 36, C.accent, "off")
	track.Parent = tilt
	self.speedFill = speedFill
	self.speed = Kit.text("0", 52, C.white, 3, ITALIC)
	self.speed.AnchorPoint = Vector2.new(1, 1)
	self.speed.Position = UDim2.new(1, -78, 1, -40)
	self.speed.Size = UDim2.fromOffset(220, 56)
	self.speed.TextXAlignment = Enum.TextXAlignment.Right
	self.speed.Rotation = -7
	self.speed.Parent = br
	local unit = Kit.text("KM/H", 16, C.muted, 1.5, ITALIC)
	unit.AnchorPoint = Vector2.new(1, 1)
	unit.Position = UDim2.new(1, -14, 1, -50)
	unit.Size = UDim2.fromOffset(64, 20)
	unit.TextXAlignment = Enum.TextXAlignment.Left
	unit.Rotation = -7
	unit.Parent = br
	---------------------------------------------------------------
	-- bottom centre: the nitro bar
	---------------------------------------------------------------
	local bc = corner(root, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -26), Vector2.new(420, 70))
	slide(bc, UDim2.fromOffset(0, 140))
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local nitro = UI.mk("Frame", { Name = "Nitro", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(380, 32), BackgroundTransparency = 1, Parent = bc })
	local ntrack, nfill = Kit.bar(380, 32, C.blue, "off")
	ntrack.Parent = nitro
	self.nitroFill = nfill
	self.nitroTrack = ntrack
	-- its name on the left, inside the bar; its key on the right, inside the bar
	self.nitroText = Kit.text("NITRO", 17, C.white, 2.5, ITALIC)
	self.nitroText.AnchorPoint = Vector2.new(0, 0.5)
	self.nitroText.TextXAlignment = Enum.TextXAlignment.Left
	self.nitroText.Position = UDim2.new(0, 14, 0.5, 0)
	self.nitroText.Size = UDim2.fromOffset(170, 22)
	self.nitroText.ZIndex = 6
	self.nitroText.Parent = nitro
	self.nitroKey = Kit.text(touchOnly and "BOOST" or "SPACE", 13, Color3.fromRGB(220, 224, 236), 2, Kit.Body)
	self.nitroKey.AnchorPoint = Vector2.new(1, 0.5)
	self.nitroKey.TextXAlignment = Enum.TextXAlignment.Right
	self.nitroKey.Position = UDim2.new(1, -14, 0.5, 0)
	self.nitroKey.Size = UDim2.fromOffset(100, 18)
	self.nitroKey.ZIndex = 6
	self.nitroKey.Parent = nitro
	-- the moves: a key tile each above the nitro (TUCK, FLOAT, DIVE, and the tyre's skill), lit while
	-- it's working, filled while it's cooling. TUCK lights teal like the tyre does while it's tucked
	local moves = corner(root, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -66), Vector2.new(460, 64))
	slide(moves, UDim2.fromOffset(0, 160))
	self.moves = moves
	self.moveTiles = {}
	local function tile(id: string, label: string, key: string, color: Color3, x: number, w: number)
		local t = UI.mk("Frame", { Name = id, Position = UDim2.fromOffset(x, 4), Size = UDim2.fromOffset(w, 56), BackgroundTransparency = 1, Parent = moves })
		local face = Kit.slice("tile", Color3.fromRGB(70, 72, 80), t, 2, 0.32)
		local glow = UI.mk("ImageLabel", {
			Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BackgroundTransparency = 1, Image = Kit.Art.glow,
			ImageColor3 = color, ImageTransparency = 1, ZIndex = 3, Parent = t,
		}, { UI.corner(8) })
		-- the cooldown: a dark sheet over the tile that shrinks as it comes back
		local cool = UI.mk("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 4, 1, -4), Size = UDim2.new(1, -8, 0, 0), BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 6, Parent = t,
		}, { UI.corner(8) })
		local cap = Kit.text(key, 13, C.white, 1.5, Kit.Body)
		cap.AnchorPoint = Vector2.new(0.5, 0)
		cap.Position = UDim2.new(0.5, 0, 0, 6)
		cap.Size = UDim2.new(1, -10, 0, 16)
		Kit.fit(cap, 13, 8)
		cap.TextColor3 = C.muted
		cap.ZIndex = 7
		cap.Parent = t
		local name = Kit.text(label, 17, C.white, 2, ITALIC)
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -6)
		name.Size = UDim2.new(1, -10, 0, 22)
		Kit.fit(name, 17, 9)
		name.ZIndex = 7
		name.Parent = t
		local rec = { root = t, face = face, glow = glow, cool = cool, cap = cap, name = name, color = color, lit = false }
		self.moveTiles[id] = rec
		return rec
	end
	tile("tuck", "TUCK", touchOnly and "" or "SHIFT", C.teal, 8, 84)
	tile("float", "FLOAT", touchOnly and "" or "W", C.blue, 100, 84)
	tile("dive", "DIVE", touchOnly and "" or "S", C.orange, 192, 84)
	tile("skill", "SKILL", touchOnly and "" or "E", PERFECT, 284, 168)
	self.moveTiles.skill.root.Visible = false

	---------------------------------------------------------------
	-- over the world: where you're heading
	---------------------------------------------------------------
	-- the altimeter, down the left edge under the zone
	local altBox = corner(root, Vector2.new(0, 0.5), UDim2.new(0, 24, 0.55, 0), Vector2.new(96, 220))
	slide(altBox, UDim2.fromOffset(-160, 0))
	local atrack = UI.mk("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(12, 200), BackgroundColor3 = Color3.fromRGB(10, 10, 12), BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = altBox }, { UI.corner(6) })
	UI.stroke(C.ink, 2, 0.1).Parent = atrack
	self.altFill = UI.mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.1), BackgroundColor3 = C.teal, BorderSizePixel = 0, Parent = atrack }, { UI.corner(6) })
	self.altText = Kit.text("0 M", 20, C.white, 2, ITALIC)
	self.altText.TextXAlignment = Enum.TextXAlignment.Left
	self.altText.AnchorPoint = Vector2.new(0, 0.5)
	self.altText.Position = UDim2.new(0, 22, 0.5, -10)
	self.altText.Size = UDim2.fromOffset(74, 24)
	self.altText.Parent = altBox
	local altCap = Kit.text("UP", 12, C.muted, 1.5, Kit.Body)
	altCap.TextXAlignment = Enum.TextXAlignment.Left
	altCap.AnchorPoint = Vector2.new(0, 0.5)
	altCap.Position = UDim2.new(0, 22, 0.5, 10)
	altCap.Size = UDim2.fromOffset(60, 14)
	altCap.Parent = altBox

	-- the first runs: what the controls do
	-- (2026-10-23: on a dark card in three set lines; it wrapped mid-list in faint outlined text over the road)
	local bl = corner(root, Vector2.new(0, 1), UDim2.new(0, 24, 1, -24), Vector2.new(400, 78))
	self.hint = Kit.text(UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		and "Drag to steer  ·  BOOST for nitro  ·  hills are your speed"
		or "<b>MOUSE / A D</b> steer    <b>SPACE</b> nitro    <b>SHIFT</b> tuck\n<b>W</b> float    <b>S</b> dive    <b>E</b> skill\n<font transparency=\"0.3\">Downhill is speed: tuck when your tyre glows gold.</font>", 15, C.text, 0, Kit.Body)
	self.hint.TextXAlignment = Enum.TextXAlignment.Left
	self.hint.TextWrapped = true
	self.hint.LineHeight = 1.15
	self.hint.Size = UDim2.fromOffset(400, 78)
	self.hint.TextYAlignment = Enum.TextYAlignment.Center
	self.hint.BackgroundColor3 = C.ink
	self.hint.BackgroundTransparency = 0.4
	UI.mk("UICorner", { CornerRadius = UDim.new(0, 10), Parent = self.hint })
	UI.mk("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 10), Parent = self.hint })
	self.hint.Parent = bl

	self.warn = Kit.text("", 26, C.red, 2.5)
	self.warn.AnchorPoint = Vector2.new(0.5, 1)
	self.warn.Position = UDim2.new(0.5, 0, 1, -150)
	self.warn.Size = UDim2.fromOffset(520, 32)
	self.warn.Visible = false
	self.warn.Parent = root

	-- stamps and toasts in the middle
	self.toasts = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(640, 260),
		BackgroundTransparency = 1, ZIndex = 20, Parent = root,
	})
	UI.autoScale(self.toasts)
	-- a draft panel no longer exists in the bounce run; kept so older callers don't trip
	self.draft = UI.mk("Frame", { Visible = false, Size = UDim2.fromOffset(1, 1), BackgroundTransparency = 1, Parent = root })
	return self
end

--==============================================================
function HudUI:setTrack(track, best: number)
	self.road.Text = string.upper(track.name)
	self.roadSub.Text = ("x%g CASH A METRE"):format(track.creditMult)
	self.shownZone = nil
	self.bestValue = best or 0
	self.beaten = false
	self.shownChain = 0
	self.bestLabel.TextColor3 = C.gold
	self.bestLabel.Text = (best and best > 0) and ("BEST  %s M"):format(UI.comma(best * P.StudsToMetres)) or "NO RECORD YET"
	-- (2026-10-23, the review: the hint paragraph every run was clutter) only while you're new (a best
	-- under 1,500 m) and only the first two runs of a session
	self.hintRuns = (self.hintRuns or 0) + 1
	local newish = (best or 0) * P.StudsToMetres < 1500
	-- (2026-10-24, the owner: "why is there a shift tuck gold crap in the bottom left during gameplay, remove
	-- that") never shown: the tutorial teaches the controls, and the HUD's own buttons name them
	self.hint.Visible = false
	local _ = newish
	self.hint.TextTransparency = 0
	self.hint.BackgroundTransparency = 0.4
	self:setChain(0, 1)
end

function HudUI:show()
	self.root.Visible = true
	self.lastClock = os.clock()
	for i, s in ipairs(self.slides or {}) do
		s.frame.Position = s.from
		task.delay(0.05 * (i - 1), function()
			UI.tween(s.frame, 0.42, { Position = s.rest }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		end)
	end
end

function HudUI:hide()
	self.root.Visible = false
end

function HudUI:setWatchers(n: number)
	n = math.max(0, math.floor(n or 0))
	self.watch.Visible = n > 0
	if n > 0 then self.watch.Text = ("%d WATCHING"):format(n) end
end

-- the chain panel: the multiplier, the bounce count, the pips; it colours up as it grows
function HudUI:setChain(chain: number, mult: number)
	local hot = math.clamp(chain / 12, 0, 1)
	local col = C.accent:Lerp(PERFECT, hot)
	if chain >= 20 then col = Color3.fromRGB(255, 96, 220) end
	self.mult.Text = "x" .. Game.multText(mult)
	self.mult.TextColor3 = chain > 0 and C.white:Lerp(col, 0.35) or C.muted
	self.chainRing.ImageColor3 = chain > 0 and col or C.grey
	self.chainCount.Text = chain > 0 and ("%d IN A ROW"):format(chain) or "LAND SMOOTH. SMASH."
	self.chainCount.TextColor3 = chain > 0 and C.gold or C.muted
	local lit = math.clamp(math.floor((mult - 1) / B.ComboStep + 0.5), 0, #self.chainPips)
	for i, pip in ipairs(self.chainPips) do
		pip.BackgroundColor3 = i <= lit and col or C.well
	end
end

--==============================================================
function HudUI:update(s)
	local now = os.clock()
	local dt = math.clamp(now - self.lastClock, 0, 0.1)
	self.lastClock = now
	local M = P.StudsToMetres

	self.dist.Text = UI.comma(s.metres) .. '<font size="30" color="#C8BEB0"> M</font>'
	local from, to, n = stretchAt(s.distance)
	local frac = 1
	local here = Game.Zones[math.clamp(n, 1, #Game.Zones)]
	local nextZone = Game.Zones[n + 1]
	if to < 0 or not nextZone then
		self.fromLabel.Text = string.upper(Game.Zones[#Game.Zones].name)
		self.toLabel.Text = "THE LAST ZONE"
	else
		frac = math.clamp((s.distance - from) / (to - from), 0, 1)
		self.fromLabel.Text = string.upper(here.name)
		self.toLabel.Text = ("%s  ·  %s M"):format(string.upper(nextZone.name), UI.comma((to - s.distance) * M))
	end
	if s.zone and s.zone ~= self.shownZone then
		self.shownZone = s.zone
		local z = Game.Zones[s.zone]
		if z then
			self.road.Text = string.upper(z.name)
			self.roadSub.Text = ("x%g CASH A METRE"):format(z.rate)
		end
	end
	local w = RAIL_INNER * frac
	self.railFill.Size = UDim2.new(0, w, 1, -12)
	self.marker.Position = UDim2.fromOffset(6 + w, 4)

	local best = self.bestValue
	if best > 0 and not self.beaten and to > 0 and best >= from and best <= to then
		self.bestTick.Visible = true
		self.bestTick.Position = UDim2.new(0, 6 + RAIL_INNER * (best - from) / (to - from), 0.5, 0)
	else
		self.bestTick.Visible = false
	end
	if best > 0 and not self.beaten and s.distance > best then
		self.beaten = true
		self.bestLabel.Text = "NEW RECORD"
		self.bestLabel.TextColor3 = C.green
		self:stamp("NEW RECORD", C.green, 40, 0)
	elseif s.ghostX and not self.beaten then
		local gap = (s.distance - s.ghostX) * M
		if math.abs(gap) < 5 then
			self.bestLabel.Text = "LEVEL WITH YOUR BEST"
			self.bestLabel.TextColor3 = C.gold
		elseif gap > 0 then
			self.bestLabel.Text = ("%s M AHEAD OF YOUR BEST"):format(UI.comma(gap))
			self.bestLabel.TextColor3 = C.green
		else
			self.bestLabel.Text = ("%s M BEHIND YOUR BEST"):format(UI.comma(-gap))
			self.bestLabel.TextColor3 = C.red
		end
	end

	-- the chain (set on events too; this catches the ground resetting it)
	local chain = s.chain or 0
	if chain ~= self.shownChain then
		self.shownChain = chain
		self:setChain(chain, s.combo or 1)
	end

	-- speed: the bar eases after the number
	local kmh = s.speed * M * 3.6
	self.speed.Text = UI.comma(math.floor(kmh + 0.5))
	self.speedShown += (math.clamp(s.speed / SPEED_MAX, 0, 1) - self.speedShown) * (1 - math.exp(-dt * 10))
	self.speedFill.Size = UDim2.fromScale(math.max(0.04, self.speedShown), 1)
	self.speedFill.BackgroundColor3 = C.accent:Lerp(Color3.fromRGB(255, 80, 60), math.clamp((self.speedShown - 0.6) / 0.4, 0, 1))

	-- the moves
	self:updateMoves(s, now)
	local nf = math.clamp(s.nitroFrac or 0, 0, 1)
	self.nitroFill.Size = UDim2.fromScale(math.max(0.02, nf), 1)
	local low = nf < 0.15
	if s.nitroDry then
		-- empty: locked until it's refilled to 30%
		self.nitroFill.BackgroundColor3 = Color3.fromRGB(120, 124, 136)
		self.nitroText.Text = "NITRO  ·  RECHARGING"
		self.nitroText.TextColor3 = Color3.fromRGB(200, 204, 214)
	else
		self.nitroFill.BackgroundColor3 = s.nitroOn and C.yellow or (low and C.red or C.blue)
		self.nitroText.Text = s.nitroOn and "NITRO!" or (low and "NITRO  ·  LOW" or "NITRO")
		self.nitroText.TextColor3 = C.white
	end

	-- the altimeter
	local altM = s.altitude * M
	self.altText.Text = ("%d M"):format(math.floor(altM + 0.5))
	self.altFill.Size = UDim2.fromScale(1, math.clamp(s.altitude / 300, 0.02, 1))
	self.altFill.BackgroundColor3 = s.altitude < 14 and C.red or (s.altitude < 40 and C.yellow or C.teal)

	local m = s.metals or {}
	for _, def in ipairs(Config.Metals) do
		local c = self.metalCells[def.id]
		local have2 = m[def.id] or 0
		if c and have2 ~= c.shown then
			c.shown = have2
			c.cell.Visible = have2 > 0
			c.count.Text = tostring(have2)
		end
	end

	if s.stopping then
		self.warn.Text = "LOSING IT"
		self.warn.TextTransparency = 0.05 + math.abs(math.sin(now * 8)) * 0.5
		self.warn.Visible = true
	else
		self.warn.Visible = false
	end

	if s.runTime > 12 and self.hint.TextTransparency < 1 then
		self.hint.TextTransparency = math.min(1, self.hint.TextTransparency + 0.02)
		self.hint.BackgroundTransparency = 0.4 + 0.6 * self.hint.TextTransparency
		local st = self.hint:FindFirstChildOfClass("UIStroke")
		if st then st.Transparency = math.max(st.Transparency, self.hint.TextTransparency) end
	end
end

--==============================================================
-- the moves
--==============================================================
local function lightTile(t, on: boolean, color: Color3?)
	local col = color or t.color
	if on ~= t.lit or (on and t.litCol ~= col) then
		t.lit = on
		t.litCol = col
		t.face.ImageColor3 = if on then col else Color3.fromRGB(70, 72, 80)
		t.glow.ImageColor3 = col
		t.glow.ImageTransparency = if on then 0.2 else 1
		t.cap.TextColor3 = if on then C.white else C.muted
		if on then Kit.pop(t.root, 0.85, 0.2) end
	end
end

function HudUI:updateMoves(s, now: number)
	local T = self.moveTiles
	-- TUCK: lit while tucked; when the legs cramp it's dark until it's ready again
	lightTile(T.tuck, s.tucking == true)
	T.tuck.cool.Size = if s.tuckCool then UDim2.new(1, -8, 1, -8) else UDim2.new(1, -8, 0, 0)
	-- FLOAT and DIVE: lit while you hold them in the air
	lightTile(T.float, s.floating == true)
	lightTile(T.dive, s.diving == true)
	-- the skill: its name, its cooldown sheet and seconds, lit while it runs
	local sk = T.skill
	if s.skillName then
		if not sk.root.Visible then
			sk.root.Visible = true
			sk.cap.Text = if s.skillKey and sk.cap.Text ~= "" then s.skillKey else sk.cap.Text
		end
		local cd = math.clamp(s.skillCd or 0, 0, 1)
		sk.cool.Size = UDim2.new(1, -8, cd, -8 * cd)
		local ready = cd <= 0
		if ready and self.skillWasCooling then
			self.skillWasCooling = false
			Kit.pop(sk.root, 1.25, 0.25)
		elseif not ready then
			self.skillWasCooling = true
		end
		local charge = s.skillCharge or 0
		if charge > 0 then
			local turbo = { Color3.fromRGB(70, 150, 255), Color3.fromRGB(255, 150, 40), Color3.fromRGB(190, 90, 255) }
			lightTile(sk, true, turbo[math.clamp(charge, 1, 3)])
		else
			lightTile(sk, s.skillActive == true)
		end
		sk.name.Text = if ready then string.upper(s.skillName) else ("%s  %ds"):format(string.upper(s.skillName), math.ceil(s.skillLeft or 0))
		sk.name.TextTransparency = if ready then 0 else 0.25
	else
		sk.root.Visible = false
	end
end

--==============================================================
-- stamps and toasts
--==============================================================
-- a big word that slams in tilted, holds and lifts away
function HudUI:stamp(text: string, color: Color3, size: number, rot: number?, sub: string?)
	local holder = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -10), Size = UDim2.fromOffset(640, size + 30),
		BackgroundTransparency = 1, ZIndex = 21, Rotation = rot or 0, Parent = self.toasts,
	})
	local l = Kit.text(text, size, color, 3.5, ITALIC)
	l.Size = UDim2.new(1, 0, 0, size + 6)
	l.ZIndex = 22
	l.Parent = holder
	if sub then
		local s2 = Kit.text(sub, math.floor(size * 0.42), C.white, 2, Kit.Body)
		s2.Position = UDim2.fromOffset(0, size + 2)
		s2.Size = UDim2.new(1, 0, 0, math.floor(size * 0.42) + 6)
		s2.ZIndex = 22
		s2.Parent = holder
	end
	Kit.pop(holder, 1.8, 0.16)
	task.delay(0.42, function()
		if not holder.Parent then return end
		Kit.tween(holder, 0.4, { Position = UDim2.new(0.5, 0, 0.5, -70) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("TextLabel") then Kit.tween(d, 0.4, { TextTransparency = 1 }) end
			if d:IsA("UIStroke") then Kit.tween(d, 0.4, { Transparency = 1 }) end
		end
		task.delay(0.42, function() holder:Destroy() end)
	end)
end

function HudUI:toast(text: string, color: Color3, size: number?)
	local l = Kit.text(text, size or 24, color, 2.5)
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.new(0.5, 0, 1, -30)
	l.Size = UDim2.fromOffset(620, (size or 24) + 8)
	l.ZIndex = 21
	l.Parent = self.toasts
	Kit.pop(l, 1.4, 0.16)
	task.delay(0.5, function()
		if not l.Parent then return end
		Kit.tween(l, 0.45, { Position = UDim2.new(0.5, 0, 1, -80), TextTransparency = 1 })
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then Kit.tween(st, 0.45, { Transparency = 1 }) end
	end)
	task.delay(1, function() l:Destroy() end)
end

function HudUI:gateBanner(_tier: number, metres: number?, _split: number?, _bestSplit: number?, zoneName: string?)
	local holder = UI.mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.6, 0.62), Size = UDim2.fromOffset(560, 80),
		BackgroundTransparency = 1, Rotation = 0, ZIndex = 30, Parent = self.root,
	})
	UI.autoScale(holder)
	Kit.slice("banner", C.accent, holder, 30, 0.5)
	local title = Kit.text(zoneName and string.upper(zoneName) or "NEW ZONE", 40, C.white, 3, ITALIC)
	title.Size = UDim2.new(1, 0, 0, 46)
	title.Position = UDim2.fromOffset(0, 4)
	title.ZIndex = 32
	title.Parent = holder
	local z = zoneName and nil
	local _ = z
	local sub = Kit.text(("NEW ZONE  ·  %s M"):format(UI.comma(math.floor(metres or 0))), 15, C.gold, 1.5, Kit.Body)
	sub.Position = UDim2.fromOffset(0, 50)
	sub.Size = UDim2.new(1, 0, 0, 18)
	sub.ZIndex = 32
	sub.Parent = holder
	Kit.tween(holder, 0.24, { Position = UDim2.fromScale(0.5, 0.62) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	task.delay(1.3, function()
		if not holder.Parent then return end
		Kit.tween(holder, 0.26, { Position = UDim2.fromScale(1.6, 0.62) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		task.delay(0.3, function() holder:Destroy() end)
	end)
end

function HudUI:event(e)
	local k = e.kind
	if k == "bounce" then
		self.shownChain = e.chain
		self:setChain(e.chain, e.combo)
		self.multScale.Scale = 1.3
		Kit.tween(self.multScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		self:stamp(e.perfect and "DIVE BOMB" or "BOUNCE", e.perfect and PERFECT or GOOD, e.perfect and 46 or 36, 0, ("x%s"):format(Game.multText(e.combo)))
	elseif k == "tuck" then
		if e.what == "perfect" then
			self.shownChain = e.chain
			self:setChain(e.chain, e.combo)
			self:stamp("PERFECT TUCK", PERFECT, 44, 0, ("x%s"):format(Game.multText(e.combo)))
		elseif e.what == "cramp" then
			self:toast("CRAMP", C.muted, 22)
		end
	elseif k == "skillzone" then
		if e.what == "ahead" then
			self:toast(if e.ready then "SKILL ZONE AHEAD · " .. (e.name or "SKILL") else "SKILL ZONE AHEAD", PERFECT, 26)
		elseif e.what == "bonus" then
			self.shownChain = e.chain
			self:setChain(e.chain, e.combo)
			self:stamp("SKILL ZONE", PERFECT, 44, 0, e.name)
		end
	elseif k == "smooth" then
		self.shownChain = e.chain
		self:setChain(e.chain, e.combo)
		self:stamp("SMOOTH LANDING", PERFECT, 40, 0, ("x%s"):format(Game.multText(e.combo)))
	elseif k == "skim" then
		self.shownChain = e.chain
		self:setChain(e.chain, e.combo)
		self:toast("SKIM  +NITRO", C.teal, 24)
	elseif k == "chainlost" then
		self:stamp("CHAIN LOST", C.muted, 32, 0, ("%d in a row"):format(e.chain or 0))
		self:setChain(0, 1)
		self.shownChain = 0
	elseif k == "braced" then
		self.shownChain = e.chain
		self:setChain(e.chain, e.combo)
		self:stamp("CLEAN LANDING", GOOD, 38, 0, ("x%s"):format(Game.multText(e.combo)))
	elseif k == "rough" then
		self:toast("ROUGH LANDING  ·  TUCK TO BRACE", C.muted, 22)
	elseif k == "bump" then
		if not e.tucked then self:toast("SPEED BUMP  ·  TUCK TO KEEP SPEED", C.muted, 22) end
	elseif k == "crash" then
		self:toast("CRASH", C.red, 30)
	elseif k == "hit" then
		self:toast("CLIPPED", C.red, 26)
	elseif k == "view" then
		self:toast(e.view == "first" and "FIRST PERSON" or "CHASE VIEW", C.white, 20)
	elseif k == "smash" then
		self:toast("SMASH", C.accent, 26)
	elseif k == "pad" then
		self:toast("PAD", Color3.fromRGB(90, 250, 255), 24)
	elseif k == "dustdevil" then
		self:toast("UPDRAFT", C.yellow, 26)
	-- (2026-10-24) the hold-to-bail, the roll-out warning and the fatigue cue
	elseif k == "bailhold" then
		self:toast(if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "HOLD BAIL TO BAIL OUT" else "KEEP HOLDING TO BAIL OUT", C.muted, 22)
	elseif k == "rollout" then
		self:toast("ROLLING OUT  ·  BOOST TO KEEP GOING", C.yellow, 24)
	elseif k == "headwind" then
		self:toast("HEADWIND  ·  THE RUN IS TIRING", C.muted, 22)
	elseif k == "metal" then
		-- coins tick up in the corner; no toast each
	elseif k == "checkpoint" then
		self:gateBanner(e.tier, e.metres, e.split, e.bestSplit, e.zoneName)
	elseif k == "skill" then
		self:stamp(string.upper(e.name), Color3.fromRGB(255, 196, 64), 40, 0)
	elseif k == "key" then
		self:stamp("+1 KEY", Color3.fromRGB(255, 200, 52), 46, 0)
	end
end

function HudUI:destroy()
	self.root:Destroy()
end

return HudUI
