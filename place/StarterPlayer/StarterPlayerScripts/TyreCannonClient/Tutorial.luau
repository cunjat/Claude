--!strict
-- TYRE CANNON :: Tutorial
-- The first session, taught on the job (tutorial-ideas-2026-10-11, idea 1). No screens of text, no
-- Next buttons, nothing blocked: one short plate at a time, shown the moment it's needed and gone the
-- moment you do the thing. Plates are the kit's dark panel with a ring in the move's colour and, for
-- a control, a key-cap like the run's TUCK / FLOAT / DIVE tiles. Under the call, one short line says
-- what the thing does.
--   first         a newcomer chooses: PLAY TUTORIAL or SKIP (skipped, it's done for good). The daily
--                 reward waits for the choice, then it's the first step: CLAIM under its Claim button
--   in the yard   PRESS LAUNCH over Launch; after the first run SPEND IT over Upgrade (or the Plot
--                 tile), BUY CANNON on the Cannon's buy button; then OPEN A CRATE on the Crates tile
--                 (a new tyre to go with it) and LAUNCH AGAIN (2026-10-16: players went straight
--                 from the cannon to the yard, so the crate comes first and the launch is asked for)
--   the launch    the first Rev & Shift runs slower (Main asks :launchSlow()), SHIFT IN THE GOLD over it
--   the run       HOLD FOR NITRO; TUCK NOW the first time the tyre glows gold before a drop or a
--                 speed bump; TUCK TO LAND before a hard landing; with the new cannon HOLD TO FLOAT,
--                 then HOLD TO DIVE. The first time each one comes up it's a focus: the world drops
--                 into slow motion and stays there until you use the control, and the screen dims
--                 everywhere but a window round the key-cap (or the phone's pad) you need, outlined
--                 in the move's colour
--   the yard      the same dim and window, lighter and without the slow motion, round the button a
--                 plate points at
--   the payout    after the first run with the new Cannon: how much further it went
-- A step that's shown but not done comes back next run; after two runs it counts as taught, so the
-- tutorial never stalls. Each step is saved on the server (profile.tutStep: leave and you pick up
-- where you were) and logged as the onboarding funnel (Game.TutorialSteps). Once it's done
-- (profile.tutorial) it never shows again.
--   Tutorial.new(gui, ctx) ; :setProfile(p) ; :launchSlow() -> number ; :launching()
--   :runStart(sim, prevBestMetres) ; :runTick(s) ; :runEvent(e) ; :runEnd(summary, payout) ; :restart()
--   :holdDaily() -> boolean (HubExtras waits on it) ; :isChoosing() -> boolean (no launch behind it)
--   ctx = { remotes, hud, touch, hub2 = () -> Hub2, plot2, crates2, receipt (Receipt2),
--           idle = () -> boolean, state = () -> string, hubX = () -> HubExtras, showDaily = () -> () }
-- The yard tour (2026-10-15): once the tutorial's done (or skipped) and there's been a run, plates
-- walk through making the yard yours: MAKE IT YOURS on the Plot tile, EDIT YARD in the panel, then
-- in the editor PICK SOME DECOR, DRAG IT AROUND, A NEW FLOOR & FENCE and SAVE WITH DONE. Each waits
-- for the thing to be done (YardEdit.stats); it's saved as the yardTour pref when the yard's saved.
-- Plates in the yard carry the game's own icons (Kit.Icon) in the key-cap.
-- Every plate has a small grey SKIP on its top-right corner (2026-10-15): in the first session it
-- ends the tutorial for good (logged as a skip, like the start's Skip); on a yard-tour plate it ends
-- the tour.
--   tutorial.yardEdit = YardEdit (Main sets it)

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("Game"))
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local Prefs = require(script.Parent.Prefs)
local Checklist = require(script.Parent.Checklist)
local C = Kit.C

local Tutorial = {}
Tutorial.__index = Tutorial

local STEP: { [string]: number } = {}
for i, n in ipairs(Game.TutorialSteps) do STEP[n] = i end
-- the steps taught during a run: shown in two runs without being done, they count as taught
local IN_RUN = { STEP.Nitro, STEP.Tuck, STEP.Land, STEP.Float, STEP.Dive }

local ITALIC = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local PLATE_H = 56
local PLATE_HD = 84          -- with the line that says what it does
-- (2026-10-18: up in the sky under the distance bar; at the bottom -152 the plate sat right over the tyre)
local RUN_POS, SHIFT_POS = UDim2.new(0.5, 0, 0.34, 0), UDim2.fromScale(0.5, 0.7)
local FOCUS_SLOW = 0.12      -- the world's speed while a control is in focus
local FOCUS_MAX = 8          -- seconds (real) before a focus lets go on its own
local DIM_RUN, DIM_YARD = 0.7, 0.62    -- how dark the dim gets (the sheets' transparency; 2026-10-23: the run's was 0.45, which
-- darkened half the first run behind each tip)
-- the checklist on the right while the tutorial's on: what's left to do, ticked off as it's done
-- (the in-run moves are taught on the road and aren't on it)
local TUT_LIST = {
	{ id = "Launch", text = "Launch your tyre" },
	{ id = "First run", text = "Finish your first run" },
	{ id = "Spend it", text = "Spend your cash in the yard" },
	{ id = "Cannon bought", text = "Buy the Cannon" },
	{ id = "Crate", text = "Open a crate for a new tyre" },
	{ id = "Second run", text = "Launch with your new cannon" },
	-- (2026-10-16: the daily reward is the tutorial's last step, not its first)
	{ id = "Daily", text = "Claim your daily reward" },
}
-- the yard tour's checklist, in the editor
local TOUR_LIST = {
	{ id = "added", text = "Place a decor piece" },
	{ id = "moved", text = "Drag something to a new spot" },
	{ id = "skins", text = "Pick a new floor or fence" },
	{ id = "saved", text = "Save it with DONE" },
}

local function touchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- whether a button is really on screen (it and everything above it visible)
local function onScreen(g: GuiObject?): boolean
	if not g or not g.Parent then return false end
	local o: Instance? = g
	while o and not o:IsA("LayerCollector") do
		if o:IsA("GuiObject") and not o.Visible then return false end
		o = o.Parent
	end
	return g.AbsoluteSize.X > 4
end

--==============================================================
-- the focus (2026-10-16): the screen dims, with a soft round light on the button that matters (no
-- hard box round it), and soft rings pulse out from the button in the move's colour. The light is
-- a texture with a feathered hole (art/ui/spotlight.py); past its edges four plain sheets carry the
-- same dark to the screen's edges.
--==============================================================
local SPOT, RIPPLE = "rbxassetid://100130452693655", "rbxassetid://139891404137989"
local function newFocus(gui: ScreenGui)
	local f = {}
	local holder = UI.mk("Frame", { Name = "TutorialFocus", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 55, Parent = gui })
	local sheets = {}
	for i = 1, 4 do
		sheets[i] = UI.mk("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 55, Parent = holder })
	end
	local spot = UI.mk("ImageLabel", { BackgroundTransparency = 1, Image = SPOT, ImageTransparency = 1, ZIndex = 55, Parent = holder })
	local ripples = {}
	for i = 1, 2 do
		ripples[i] = UI.mk("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Image = RIPPLE, ImageTransparency = 1, ZIndex = 56, Parent = holder })
	end
	f.alpha = 0
	f.target = nil :: GuiObject?
	f.color = C.accent
	f.dark = DIM_RUN
	f.rect = nil :: { Vector2 }?
	function f:to(target: GuiObject?, color: Color3, dark: number)
		self.target, self.color, self.dark = target, color, dark
	end
	function f:off()
		self.target = nil
	end
	function f:step(dt: number, origin: Vector2)
		local t = self.target
		local want = if t and onScreen(t) then 1 else 0
		self.alpha += (want - self.alpha) * math.min(1, dt * 8)
		if self.alpha < 0.01 then
			holder.Visible = false
			self.rect = nil
			return
		end
		holder.Visible = true
		if t and want > 0 then
			self.rect = { t.AbsolutePosition - origin, t.AbsoluteSize }
		end
		local r = self.rect
		if not r then return end
		local p, s = r[1], r[2]
		local mid = p + s / 2
		-- the light: its hole a quarter of the texture across, a little wider than the button
		-- (2026-10-23: whole pixels. At fractional offsets the texture's right edge and the sheet beside it
		-- left a one-pixel seam, the "stray vertical line" down the run while TUCK NOW was up)
		local d = math.floor(math.max(s.X, s.Y) + 40)
		local size = d * 4
		local sp = Vector2.new(math.floor(mid.X - size / 2), math.floor(mid.Y - size / 2))
		spot.Position, spot.Size = UDim2.fromOffset(sp.X, sp.Y), UDim2.fromOffset(size, size)
		-- the sheets beyond the texture's square
		sheets[1].Position, sheets[1].Size = UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, math.max(0, sp.Y))
		sheets[2].Position, sheets[2].Size = UDim2.fromOffset(0, sp.Y + size), UDim2.new(1, 0, 1, -(sp.Y + size))
		sheets[3].Position, sheets[3].Size = UDim2.fromOffset(0, sp.Y), UDim2.fromOffset(math.max(0, sp.X), size)
		sheets[4].Position, sheets[4].Size = UDim2.fromOffset(sp.X + size, sp.Y), UDim2.new(1, -(sp.X + size), 0, size)
		local tr = 1 - (1 - self.dark) * self.alpha
		for _, sh in ipairs(sheets) do sh.BackgroundTransparency = tr end
		spot.ImageTransparency = tr
		-- the rings running out from the button
		for i, rp in ipairs(ripples) do
			local k = ((os.clock() / 1.3) + (i - 1) * 0.5) % 1
			local rd = (math.max(s.X, s.Y) + 10) * (1 + 0.55 * k)
			rp.Position, rp.Size = UDim2.fromOffset(mid.X, mid.Y), UDim2.fromOffset(rd, rd)
			rp.ImageColor3 = self.color
			rp.ImageTransparency = 1 - (1 - k) * 0.8 * self.alpha
		end
	end
	return f
end

--==============================================================
-- the plate
--==============================================================
local function newPlate(gui: ScreenGui)
	local plate = {}
	-- outer: placed and scaled to the screen; inner: the kit's appear / vanish
	local root = UI.mk("Frame", {
		Name = "TutorialPlate", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(300, PLATE_H),
		BackgroundTransparency = 1, ZIndex = 60, Parent = gui,
	})
	UI.autoScale(root, 1280, 760)
	local body = UI.mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 60, Parent = root })
	Kit.slice("panel_body", nil, body, 60, 0.32)
	local ring = Kit.slice("panel_ring", C.accent, body, 61, 0.32)
	local key = UI.mk("Frame", { Name = "Key", Position = UDim2.fromOffset(9, 8), Size = UDim2.fromOffset(70, PLATE_H - 16), BackgroundTransparency = 1, ZIndex = 62, Parent = body })
	local keyFace = Kit.slice("tile", C.accent, key, 62, 0.26)
	local keyText = Kit.text("", 15, C.white, 1.5, Kit.Body)
	keyText.Size = UDim2.new(1, -8, 1, 0)
	keyText.Position = UDim2.fromOffset(4, 0)
	keyText.ZIndex = 63
	Kit.fit(keyText, 15, 8)
	keyText.Parent = key
	-- (or one of the game's icons in the key-cap, breaking out of it a little)
	local keyIcon = UI.mk("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(52, 52),
		BackgroundTransparency = 1, Visible = false, ZIndex = 64, Parent = key,
	})
	local label = Kit.text("", 22, C.white, 2, ITALIC)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 63
	label.Parent = body
	local descL = Kit.text("", 15, C.text, 1.5, Kit.Body)
	descL.TextXAlignment = Enum.TextXAlignment.Left
	descL.ZIndex = 63
	descL.Visible = false
	descL.Parent = body
	-- SKIP, on the top-right corner (straddling the plate's edge so it never covers the call)
	local skip = Kit.button("Skip", C.grey, UDim2.fromOffset(66, 28), 14)
	skip.root.Name = "Skip"
	skip.root.AnchorPoint = Vector2.new(1, 0.5)
	skip.root.Position = UDim2.new(1, 6, 0, -2)
	skip.root.ZIndex = 66
	skip.root.Parent = body

	plate.root, plate.body, plate.id = root, body, nil :: string?
	plate.onSkip = nil :: ((id: string?) -> ())?
	skip.onClick = function()
		if plate.onSkip then plate.onSkip(plate.id) end
	end
	plate.anchor = nil :: GuiObject?
	plate.t0 = os.clock()

	-- set what it says and how big it is; the key-cap only when there's a key, the second line (what
	-- the thing does) only when there's a description
	function plate:set(text: string, keyName: string?, color: Color3, desc: string?, icon: string?)
		self.color = color
		label.Text = text
		ring.ImageColor3 = color
		keyFace.ImageColor3 = color
		key.Visible = keyName ~= nil or icon ~= nil
		keyText.Text = keyName or ""
		keyIcon.Visible = icon ~= nil
		keyIcon.Image = icon or ""
		if icon then keyName = "" end
		descL.Text = desc or ""
		descL.Visible = desc ~= nil
		local h = if desc then PLATE_HD else PLATE_H
		local w = math.max(120, #text * 15 + 36)
		if desc then w = math.clamp(math.max(w, #desc * 8 + 36), 120, 560) end
		local left = if keyName then 88 else 20
		key.Position = UDim2.fromOffset(9, (h - (PLATE_H - 16)) / 2)
		if desc then
			label.Position = UDim2.fromOffset(left, 8)
			label.Size = UDim2.new(1, -(left + 16), 0, 36)
			descL.Position = UDim2.fromOffset(left, 46)
			descL.Size = UDim2.new(1, -(left + 16), 0, 26)
			Kit.fit(descL, 15, 10)
		else
			label.Position = UDim2.fromOffset(left, 0)
			label.Size = UDim2.new(1, -(left + 16), 1, 0)
		end
		Kit.fit(label, 22, 12)
		root.Size = UDim2.fromOffset(left + w, h)
	end

	-- (a plate going away switches itself off when its vanish ends: one shown straight after waits for
	-- that, or the vanish would hide it)
	function plate:show(id: string)
		self.id = id
		self.t0 = os.clock()
		skip.root.Visible = self.canSkip == nil or self.canSkip(id)
		local function go()
			body.Visible = false
			body.Position = UDim2.new()
			Kit.appear(body, 0, 18)
		end
		local wait = (self.goneAt or 0) - os.clock()
		if wait > 0 then
			task.delay(wait + 0.03, function() if self.id == id then go() end end)
		else
			go()
		end
	end

	function plate:hide()
		if not self.id then return end
		self.id = nil
		self.text = nil
		self.anchor = nil
		if body.Visible then
			self.goneAt = os.clock() + 0.16
			Kit.vanish(body, 0.16)
		end
	end

	return plate
end

--==============================================================
function Tutorial.new(gui: ScreenGui, ctx)
	local self = setmetatable({}, Tutorial)
	self.gui = gui
	self.ctx = ctx
	self.R = ctx.remotes
	self.active = false
	self.started = false
	self.profile = nil
	self.done = {} :: { [number]: boolean }
	self.reported = 0
	self.tries = {} :: { [number]: number }     -- runs a step was shown in without being done
	self.shownThisRun = {} :: { [number]: boolean }
	self.held = {} :: { [string]: number }     -- seconds a control has been held, this run
	self.focused = {} :: { [number]: boolean }  -- steps that have had their focus
	self.focusStep = nil :: number?
	self.needChoice = false     -- a newcomer hasn't picked tutorial or skip yet
	self.choiceBox = nil :: Frame?
	self.sawDaily = false       -- the daily reward's been up during the tutorial
	self.focus = newFocus(gui)
	self.hubPlate = newPlate(gui)
	self.runPlate = newPlate(gui)
	self.runPlate.root.Position = RUN_POS
	self.hubPlate.onSkip = function(id) self:skip(id) end
	self.runPlate.onSkip = function(id) self:skip(id) end
	-- (2026-10-16) once you've chosen the tutorial, it can only be skipped after the first run
	local function canSkip(id: string?): boolean
		if id and string.sub(id, 1, 2) == "t_" then return true end
		return self.replaying == true or self:is("First run")
	end
	self.hubPlate.canSkip = canSkip
	self.runPlate.canSkip = canSkip
	self.conn = RunService.RenderStepped:Connect(function(dt) self:frame(dt) end)
	return self
end

-- the profile: start (or resume) for a player who hasn't finished it; stop for one who has
function Tutorial:setProfile(p)
	self.profile = p
	if not p then return end
	-- (2026-10-18: the field was `replay`, the same name as the method, so before anything set it it
	-- read as the function, which is truthy: everyone who'd finished the tutorial got it again every session)
	if p.tutorial and not self.replaying then
		if self.active then self:stop() end
		return
	end
	if not self.started then
		self.started = true
		self.active = true
		local at = math.floor(tonumber(p.tutStep) or 0)
		for i = 1, at do self.done[i] = true end
		self.preDone = table.clone(self.done)
		self.reported = at
		-- a newcomer chooses first: the tutorial, or skip it
		if at <= STEP.Joined then self.needChoice = true end
		self:complete(STEP.Joined)
	end
	-- already did it the long way round
	local v = p.v2
	if v and (v.mach.cannon or 0) >= 1 and self.done[STEP["First run"]] then
		self:complete(STEP["Spend it"])
		self:complete(STEP["Cannon bought"])
	end
end

function Tutorial:stop()
	self:release()
	self.active = false
	self.replaying = false
	self.hubPlate:hide()
	self.runPlate:hide()
end

-- the debug menu's Play Tutorial: everything from the top (the server only logs a first time)
function Tutorial:restart()
	self.done, self.tries, self.reported = {}, {}, 0
	self.preDone = {}
	if self.list then
		self.list:destroy()
		self.list = nil
	end
	self.started, self.active = true, true
	self.focused = {}
	self.sawDaily = false
	self.needChoice = true
	self:complete(STEP.Joined)
end

-- Settings > Help > Replay the tutorial: from the first launch (no choice, the daily reward last
-- as always), skippable at any point
function Tutorial:replay()
	self.done, self.tries = {}, {}
	self.done[STEP.Joined] = true
	self.preDone = table.clone(self.done)
	self.reported = #Game.TutorialSteps
	if self.list then
		self.list:destroy()
		self.list = nil
	end
	self.replaying = true
	self.started, self.active = true, true
	self.focused = {}
	self.sawDaily = false
	self.needChoice = false
end

-- a step's done: tell the server about every step that's now done in order (the funnel stays in
-- order), and finish on the last
function Tutorial:complete(i: number)
	if not self.active or self.done[i] then return end
	self.done[i] = true
	while self.done[self.reported + 1] do
		self.reported += 1
		local n = self.reported
		pcall(function() self.R.TutorialStep:FireServer(n) end)
	end
	if self.done[STEP.Crate] and self.done[STEP["Second run"]] and self.done[STEP.Dive] and self.done[STEP.Daily] and not self.done[STEP.Done] then
		self.done[STEP.Done] = true
		if not self.replaying then pcall(function() self.R.TutorialDone:FireServer() end) end
		task.delay(1.5, function() self:stop() end)
	end
end

function Tutorial:is(name: string): boolean
	return self.done[STEP[name]] == true
end

--==============================================================
-- the start: tutorial or skip
--==============================================================
-- the daily reward waits until a newcomer's chosen (HubExtras asks)
function Tutorial:holdDaily(): boolean
	if not self.profile then return true end
	if self.needChoice or self.choiceBox ~= nil then return true end
	-- (the daily reward comes at the end of the tutorial, after the last move's taught)
	return self.active == true and not self:is("Dive")
end

-- the choice is up: nothing launches behind it
function Tutorial:isChoosing(): boolean
	return self.choiceBox ~= nil
end

function Tutorial:showChoice()
	local box = UI.mk("Frame", { Name = "TutorialChoice", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(600, 300), BackgroundTransparency = 1, ZIndex = 70, Parent = self.gui })
	UI.autoScale(box, 1280, 760)
	self.choiceBox = box
	Kit.dim(self.gui, box, true)
	local holder, face = Kit.card(UDim2.fromOffset(600, 290), C.cream)
	holder.Parent = box
	Kit.header(face, "Welcome", C.accent, 56)
	local title = Kit.text("NEW TO TYRE CANNON?", 28, C.white, 2.5, ITALIC)
	title.Position = UDim2.fromOffset(0, 70)
	title.Size = UDim2.new(1, 0, 0, 34)
	title.ZIndex = 5
	title.Parent = face
	local sub = Kit.text("A quick tutorial walks you through launching, riding and upgrading over your first few runs.", 16, C.muted, 1.5, Kit.Body)
	sub.TextWrapped = true
	sub.Position = UDim2.fromOffset(40, 110)
	sub.Size = UDim2.new(1, -80, 0, 46)
	sub.ZIndex = 5
	sub.Parent = face
	local skip = Kit.button("Skip", C.grey, UDim2.fromOffset(240, 56), 22)
	skip.root.AnchorPoint = Vector2.new(1, 1)
	skip.root.Position = UDim2.new(0.5, -8, 1, -18)
	skip.root.ZIndex = 6
	skip.root.Parent = face
	local play = Kit.button("Play Tutorial", C.green, UDim2.fromOffset(240, 56), 22)
	play.root.AnchorPoint = Vector2.new(0, 1)
	play.root.Position = UDim2.new(0.5, 8, 1, -18)
	play.root.ZIndex = 6
	play.root.Parent = face
	Kit.pop(box, 0.6, 0.35)
	play.onClick = function() self:choose(true) end
	skip.onClick = function() self:choose(false) end
end

function Tutorial:choose(play: boolean)
	local box = self.choiceBox
	if not box then return end
	self.choiceBox = nil
	self.needChoice = false
	Kit.dim(self.gui, box, false)
	Kit.vanish(box, 0.18, function() box:Destroy() end)
	if not play then
		-- skipped: done for good (the server logs it as a skip, not a finish)
		pcall(function() self.R.TutorialDone:FireServer("skip") end)
		self:stop()
	end
end

-- a plate's SKIP: a yard-tour plate ends the tour; anything else ends the tutorial for good
function Tutorial:skip(id: string?)
	if id and string.sub(id, 1, 2) == "t_" then
		Prefs.set("yardTour", true, true)
		self.hubPlate:hide()
		self.focus:off()
		return
	end
	if not self.active then return end
	if not self.replaying then pcall(function() self.R.TutorialDone:FireServer("skip") end) end
	self:stop()
	self.focus:off()
end

--==============================================================
-- the launch
--==============================================================
-- the first Rev & Shift runs slower, so the gold is easy to hit
function Tutorial:launchSlow(): number
	if self.active and not self:is("Shift") then return 1.6 end
	return 1
end

function Tutorial:launching()
	self.hubPlate:hide()
	self:complete(STEP.Launch)
end

--==============================================================
-- the run
--==============================================================
function Tutorial:runStart(sim, prevBest: number?)
	self.sim = sim
	self.prevBest = prevBest or 0
	self.shownThisRun = {}
	self.held = {}
	if self.runPlate.id == "shift" then self.runPlate:hide() end
	self:complete(STEP.Shift)
end

local function keyFor(move: string): string?
	if touchOnly() then
		if move == "nitro" then return "BOOST" end
		if move == "tuck" then return "TUCK" end
		return nil
	end
	if move == "nitro" then return "SPACE" end
	if move == "tuck" then return "SHIFT" end
	if move == "float" then return "W" end
	if move == "dive" then return "S" end
	return nil
end

-- the button a move is pressed on: the HUD's key-cap (or the nitro bar), or the phone's pad
function Tutorial:targetFor(move: string): GuiObject?
	local touch = self.ctx.touch
	if touchOnly() then
		if move == "nitro" then return touch and touch.boostPad end
		if move == "tuck" then return touch and touch.tuckPad end
		return nil -- float and dive are the stick: nothing to point at
	end
	local hud = self.ctx.hud
	if not hud then return nil end
	if move == "nitro" then return hud.nitroText and hud.nitroText.Parent :: GuiObject? end
	local t = hud.moveTiles and hud.moveTiles[move]
	return t and t.root
end

-- put a run plate up (a time-critical one replaces whatever's there). The first time a step comes
-- up it's a focus: slow motion until the control's used, the screen dimmed round its button
function Tutorial:runShow(id: string, step: number, text: string, keyName: string?, color: Color3, move: string, desc: string?)
	local p = self.runPlate
	if p.id == id then return end
	p.root.Position = RUN_POS
	p:set(text, keyName, color, desc)
	p:show(id)
	self.shownThisRun[step] = true
	if not self.focused[step] then
		self.focused[step] = true
		self.focusStep = step
		self.focusT0 = os.clock()
		self.focusTarget = self:targetFor(move)
		self.focusColor = color
		local sim = self.sim
		if sim then
			sim.timeScale = FOCUS_SLOW
			sim.slowUntil = math.huge
		end
	end
end

-- the focus is over: the world eases back up to speed (RunSim ramps it), the dim lifts
function Tutorial:release()
	if not self.focusStep then return end
	self.focusStep = nil
	self.focusTarget = nil
	local sim = self.sim
	if sim then sim.slowUntil = os.clock() end
end

function Tutorial:runTick(s)
	if not self.active then return end
	local now = os.clock()
	local dt = math.min(0.1, now - (self.lastTick or now))
	self.lastTick = now
	local p = self.runPlate
	local cue = s.tuckCue
	-- (for testing: what the tutorial thinks, on the gui's TutorialState attribute)
	local list = {}
	for i = 1, #Game.TutorialSteps do if self.done[i] then table.insert(list, tostring(i)) end end
	self.gui:SetAttribute("TutorialState", ("done %s | plate %s | focus %s | cue %s | boost %s | grounded %s"):format(
		table.concat(list, ","), tostring(p.id), tostring(self.focusStep), tostring(cue), tostring(s.boosting), tostring(s.grounded)))
	-- count how long a control's been held
	local function hold(key: string, on: boolean): number
		self.held[key] = if on then (self.held[key] or 0) + dt else 0
		return self.held[key]
	end
	local boostT = hold("boost", s.boosting == true)
	local floatT = hold("float", s.floating == true)
	local diveT = hold("dive", s.diving == true)

	-- a control used counts whenever it's used (not only while its own plate is up)
	if boostT > 0.4 then self:complete(STEP.Nitro) end
	if floatT > 0.3 and self:is("Cannon bought") then self:complete(STEP.Float) end
	if diveT > 0.3 and self:is("Float") then self:complete(STEP.Dive) end
	if (p.id == "nitro" and self:is("Nitro")) or (p.id == "float" and self:is("Float")) or (p.id == "dive" and self:is("Dive")) then
		if self.focusStep then self:release() end
		p:hide()
	end

	-- a focus: wait for the control (or let go after FOCUS_MAX)
	local st = self.focusStep
	if st then
		local over = self.done[st] or (st == STEP.Land and s.grounded) or os.clock() - (self.focusT0 or 0) > FOCUS_MAX
		if over then
			self:release()
			p:hide()
		end
		return
	end

	-- TUCK NOW: the tyre's glowing gold before a drop or a speed bump
	if not self:is("Tuck") and cue == "perfect" then
		self:runShow("tuck", STEP.Tuck, if touchOnly() then "TAP TUCK NOW" else "TUCK NOW", keyFor("tuck"), C.teal, "tuck",
			"Tuck over drops and bumps to keep your speed.")
		return
	end
	if p.id == "tuck" and cue ~= "perfect" and os.clock() - p.t0 > 1.2 then p:hide() end

	-- TUCK TO LAND: a hard landing coming
	if self:is("Tuck") and not self:is("Land") and cue == "land" then
		self:runShow("land", STEP.Land, "TUCK TO LAND", keyFor("tuck"), C.teal, "tuck",
			"Tucked as you touch down, you land smooth and roll on.")
		return
	end
	if p.id == "land" and s.grounded and os.clock() - p.t0 > 0.6 then p:hide() end

	-- FLOAT and DIVE, from the first run with the new cannon
	if self:is("Cannon bought") and not s.grounded and (s.altitude or 0) > 25 then
		if not self:is("Float") then
			self:runShow("float", STEP.Float, if touchOnly() then "DRAG UP TO FLOAT" else "HOLD TO FLOAT", keyFor("float"), C.blue, "float",
				"Lifts the nose to glide further through the air.")
			if floatT > 0.3 then
				self:complete(STEP.Float)
				p:hide()
			end
			return
		elseif not self:is("Dive") and (s.pitch or 0) < -0.1 then
			self:runShow("dive", STEP.Dive, if touchOnly() then "DRAG DOWN TO DIVE" else "HOLD TO DIVE", keyFor("dive"), C.orange, "dive",
				"Drops the nose to come down faster and gain speed.")
			if diveT > 0.3 then
				self:complete(STEP.Dive)
				p:hide()
			end
			return
		end
	end
	if (p.id == "float" or p.id == "dive") and s.grounded then p:hide() end

	-- NITRO: rolling on the ground a couple of seconds in
	if not self:is("Nitro") and s.grounded and (s.runTime or 0) > 2 and p.id == nil then
		self:runShow("nitro", STEP.Nitro, "HOLD FOR NITRO", keyFor("nitro"), C.blue, "nitro",
			"Burns your nitro tank for a burst of speed.")
	end
	if p.id == "nitro" and boostT > 0.4 then
		self:complete(STEP.Nitro)
		p:hide()
	end
end

function Tutorial:runEvent(e)
	if not self.active then return end
	if e.kind == "tuck" and (e.what == "perfect" or e.what == "tuck") and self.runPlate.id == "tuck" then
		self:complete(STEP.Tuck)
		self:release()
		self.runPlate:hide()
	elseif e.kind == "tuck" and e.what == "perfect" then
		self:complete(STEP.Tuck)
	elseif e.kind == "braced" then
		if self:is("Tuck") then self:complete(STEP.Land) end
		if self.runPlate.id == "land" then
			self:release()
			self.runPlate:hide()
		end
	end
end

function Tutorial:runEnd(_summary, payout)
	self:release()
	self.sim = nil
	self.runPlate:hide()
	if not self.active then return end
	-- a step shown in two runs and not done counts as taught
	for _, i in ipairs(IN_RUN) do
		if not self.done[i] and self.shownThisRun[i] then
			self.tries[i] = (self.tries[i] or 0) + 1
			if self.tries[i] >= 2 then self:complete(i) end
		end
	end
	local firstRun = not self:is("First run")
	self:complete(STEP["First run"])
	-- the first run with the new cannon: how much further it went
	if not firstRun and self:is("Cannon bought") and not self:is("Second run") then
		self:complete(STEP["Second run"])
		local metres = tonumber(payout and payout.metres) or 0
		local gain = metres - (self.prevBest or 0)
		self.further = {
			text = if gain > 1 then ("+%s FURTHER"):format(Game.metres(gain)) else "SO CLOSE. AGAIN!",
			until_ = os.clock() + 6,
		}
	end
end

--==============================================================
-- the yard: plates over buttons, following them
--==============================================================
-- (below: under the button instead of over it, above the modal it's on)
-- the x a plate is centred on, kept clear of the screen's edges (a tile at the edge, like PLOT)
local function onScreenX(p, x: number, gui: ScreenGui): number
	local half = p.root.AbsoluteSize.X / 2
	local w = gui.AbsoluteSize.X
	if half * 2 + 16 >= w then return w / 2 end
	return math.clamp(x, half + 8, w - half - 8)
end

-- (2026-10-16) a plate never leaves the screen: after it's placed, its box is pulled back inside
-- (plates over the top row of buttons used to run off the top)
local function keepOnScreen(p, gui: ScreenGui)
	local r = p.root
	local w, h = r.AbsoluteSize.X, r.AbsoluteSize.Y
	local W, H = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	if w <= 0 or W <= 0 then return end
	local a = r.AnchorPoint
	local x, y = r.Position.X.Offset - a.X * w, r.Position.Y.Offset - a.Y * h
	x = math.clamp(x, 8, math.max(8, W - w - 8))
	y = math.clamp(y, 8, math.max(8, H - h - 8))
	r.Position = UDim2.fromOffset(x + a.X * w, y + a.Y * h)
end

function Tutorial:hubShow(id: string, text: string, anchor: GuiObject, color: Color3, desc: string?, below: boolean?, icon: string?, beside: boolean?)
	local p = self.hubPlate
	p.anchor = anchor
	p.below = below == true
	-- (2026-10-23: beside its button, so it never covers the number it's about (the payout total, the yard's tabs))
	p.beside = beside == true
	if p.id ~= id or p.text ~= text then
		p:set(text, nil, color, desc, icon)
		p.text = text
		p:show(id)
	end
end

--==============================================================
-- the yard tour: making the yard yours, once the first session's over
--==============================================================
-- returns true when it's showing something (frame leaves the plate to it)
-- In the editor a checklist sits on the left: place a decor piece, drag something, a new floor or
-- fence, then save. Each ticks the moment it's done (and stays ticked if you leave and come back);
-- saving only counts once the other three are done. A plate points at the next one.
function Tutorial:tourFrame(dt: number, origin: Vector2): boolean
	local prof = self.profile
	local ye = self.yardEdit
	local t = self.tour
	-- (finished: the card plays out its flourish wherever you are)
	if t and t.finished then
		if self.tourList and not t.flourished then
			t.flourished = true
			local L = self.tourList
			L:show(true)
			L:set("saved", true)
			L:focus(nil)
			task.delay(0.5, function()
				L:finish(function()
					L:destroy()
					if self.tourList == L then self.tourList = nil end
				end)
			end)
			Kit.callout(self.gui, "YOUR YARD, YOUR WAY", C.gold, UDim2.fromScale(0.5, 0.22), 36)
		end
		return false
	end
	if self.active or not prof or Prefs.get("yardTour") == true then
		-- (skipped, or done on another visit: the card goes)
		if self.tourList then
			self.tourList:destroy()
			self.tourList = nil
		end
		return false
	end
	local v = prof.v2
	if not (prof.tutorial and v and (v.runs or 0) >= 1) then return false end
	if not ye then return false end
	local st = self.ctx.state()
	local p = self.hubPlate
	local s = ye.stats
	if not t then
		t = { base = { added = s.added, moved = s.moved, skins = s.skins }, lastSaved = s.saved, got = {} }
		self.tour = t
	end
	for _, k in ipairs({ "added", "moved", "skins" }) do
		if s[k] > t.base[k] then t.got[k] = true end
	end
	-- a save counts once the rest are done (an early save just moves the mark on)
	if s.saved > t.lastSaved then
		t.lastSaved = s.saved
		if t.got.added and t.got.moved and t.got.skins then
			t.finished = true
			Prefs.set("yardTour", true, true)
			p:hide()
			self.focus:off()
			self.focus:step(dt, origin)
			return true
		end
	end
	local editing = st == "yard" and ye:isOpen()
	-- the checklist, in the editor
	if editing and not self.tourList then
		self.tourList = Checklist.new(self.gui, { title = "Make it yours", color = C.teal, items = TOUR_LIST, side = "left", y = 0.33 })
	end
	local L = self.tourList
	if L then
		L:show(editing)
		if editing then
			for _, k in ipairs({ "added", "moved", "skins" }) do
				if t.got[k] and not L.rows[k].done then L:set(k, true) end
			end
		end
	end
	local show, dim = nil, true
	if editing then
		local tab = ye.tab
		if not t.got.added then
			if L then L:focus("added") end
			show = { "t_decor", "PICK SOME DECOR", ye.shelf, C.teal, "Tap a card, then click where it goes. It snaps clear of everything else.", false, Kit.Icon.bench }
		elseif not t.got.moved then
			if L then L:focus("moved") end
			show = { "t_drag", "DRAG IT AROUND", ye.hint, C.blue, if UserInputService.KeyboardEnabled then "Press on anything in your yard and drag it. R turns it." else "Press on anything in your yard and drag it. The turn button spins it.", true, Kit.Icon.plot }
			dim = false
		elseif not t.got.skins then
			if L then L:focus("skins") end
			if tab == "floor" or tab == "fence" then
				show = { "t_skin", "PICK A NEW " .. string.upper(tab), ye.shelf, C.purple, "Changes the whole yard. More unlock as your yard grows.", false, Kit.Icon.plot }
			else
				local tb = ye.tabs and ye.tabs.floor
				if tb then show = { "t_floor", "NEW FLOOR & FENCE", tb.root, C.purple, "Floors and fences make the yard look like yours.", false, Kit.Icon.plot } end
			end
		elseif ye.doneBtn then
			if L then L:focus("saved") end
			show = { "t_done", "SAVE WITH DONE", ye.doneBtn.root, C.green, "Everyone in the server sees your yard.", false, Kit.Icon.medal }
		end
	elseif st == "hub" then
		local plot2 = self.ctx.plot2
		local hub2 = self.ctx.hub2()
		-- (in the hub it only nudges for a while each time you're back, then lets you be)
		if self.ctx.idle() or (plot2 and plot2:isOpen()) then
			self.tourIdle = (self.tourIdle or 0) + dt
		else
			self.tourIdle = 0
		end
		if self.tourIdle < 25 then
			if plot2 and plot2:isOpen() and plot2.editBtn and onScreen(plot2.editBtn.root) then
				show = { "t_edit", "EDIT YARD", plot2.editBtn.root, C.blue, "Move your machines and decorate your yard.", true, Kit.Icon.plot }
			elseif self.ctx.idle() and hub2 and hub2.dock and hub2.dock.PLOT and onScreen(hub2.dock.PLOT.root) then
				show = { "t_plot", "MAKE IT YOURS", hub2.dock.PLOT.root, C.accent, "Decor, floors and fences for your yard.", false, Kit.Icon.plot }
			end
		end
	end
	if not show then
		if p.id and string.sub(p.id, 1, 2) == "t_" then p:hide() end
		return false
	end
	self:hubShow(show[1], show[2], show[3], show[4], show[5], show[6], show[7])
	if dim then self.focus:to(p.anchor, p.color or C.accent, DIM_YARD) else self.focus:off() end
	self.focus:step(dt, origin)
	local a = p.anchor
	if a then
		local pos = a.AbsolutePosition - origin
		local size = a.AbsoluteSize
		local bob = math.sin(os.clock() * 3) * 4
		-- (2026-10-18) the plate goes on whichever side of the button has room: pushed back on screen it
		-- used to sit right over the button it points at (the yard editor's Done in the top bar; Upgrade on
		-- the run results, at the bottom)
		local ph = p.root.AbsoluteSize.Y
		local roomAbove = pos.Y - 6 - ph >= 8
		local roomBelow = pos.Y + size.Y + 10 + ph <= self.gui.AbsoluteSize.Y - 8
		if (p.below and (roomBelow or not roomAbove)) or (not p.below and not roomAbove and roomBelow) then
			p.root.AnchorPoint = Vector2.new(0.5, 0)
			p.root.ZIndex = 90
			p.root.Position = UDim2.fromOffset(onScreenX(p, pos.X + size.X / 2, self.gui), pos.Y + size.Y + 10 + bob)
		else
			p.root.AnchorPoint = Vector2.new(0.5, 1)
			p.root.ZIndex = 90
			p.root.Position = UDim2.fromOffset(onScreenX(p, pos.X + size.X / 2, self.gui), pos.Y - 6 + bob)
		end
		keepOnScreen(p, self.gui)
	end
	return true
end

-- the tutorial's checklist: on the right in the yard while it's on (and while nothing's open over the
-- yard); a step done while it's tucked away ticks when you're back, so you see it go
function Tutorial:listFrame()
	local L = self.list
	local finishing = L ~= nil and not L.finished and self:is("Crate") and self:is("Second run") and self:is("Daily")
	local live = self.profile ~= nil and (self.active or finishing)
	local want = live and not self.needChoice and self.choiceBox == nil and self.ctx.state() == "hub" and self.ctx.idle()
	if want and not L then
		L = Checklist.new(self.gui, { title = "Getting started", color = C.accent, items = TUT_LIST, side = "right", y = 0.5 })
		self.list = L
	end
	if not L then return end
	if not want then
		L:show(false)
		-- (skipped: it goes)
		if not self.active and not finishing then
			L:destroy()
			self.list = nil
		end
		return
	end
	L:show(true)
	local nextUp, all = nil, true
	for _, it in ipairs(TUT_LIST) do
		if self:is(it.id) then
			if not L.rows[it.id].done then L:set(it.id, true, (self.preDone or {})[STEP[it.id]] == true) end
		else
			all = false
			nextUp = nextUp or it.id
		end
	end
	L:focus(nextUp)
	if all and not L.finished then
		L.finished = true
		task.delay(0.6, function()
			L:finish(function()
				L:destroy()
				if self.list == L then self.list = nil end
			end)
		end)
	end
end

function Tutorial:frame(dt: number)
	local p = self.hubPlate
	local origin = self.gui.AbsolutePosition
	self:listFrame()
	if self:tourFrame(dt, origin) then return end
	if not self.active or self.ctx.state() ~= "hub" or not self.profile then
		p:hide()
		-- the launch: what a shift does, over the rev gauge, the first time
		local rp = self.runPlate
		if self.active and self.ctx.state() == "launch" and not self:is("Shift") and self.gui:FindFirstChild("LaunchTap") then
			if rp.id == nil then
				rp.root.Position = SHIFT_POS
				rp:set("SHIFT IN THE GOLD", nil, C.yellow, "Clean shifts fire the tyre faster. Three golds: PERFECT LAUNCH.")
				rp:show("shift")
			end
		elseif rp.id == "shift" then
			rp:hide()
		end
		-- a run's focus (or nothing)
		if self.active and self.focusStep and self.focusTarget then
			self.focus:to(self.focusTarget, self.focusColor or C.accent, DIM_RUN)
		else
			self.focus:off()
		end
		self.focus:step(dt, origin)
		return
	end
	if self.runPlate.id == "shift" then self.runPlate:hide() end
	-- a newcomer: tutorial or skip, once they're standing in the yard
	if self.needChoice then
		p:hide()
		self.focus:off()
		self.focus:step(dt, origin)
		if not self.choiceBox and self.ctx.idle() then self:showChoice() end
		return
	end
	local want = false
	local v = self.profile.v2
	local hub2 = self.ctx.hub2()
	local plot2, crates2, receipt = self.ctx.plot2, self.ctx.crates2, self.ctx.receipt
	local btns = receipt.buttons
	local credits = self.profile.credits or 0
	local cannonLv = v and (v.mach.cannon or 0) or 0
	local tier = v and v.tier or 1
	local price = Game.machinePrice("cannon", cannonLv, tier, v)

	if cannonLv >= 1 and self:is("First run") then
		self:complete(STEP["Spend it"])
		self:complete(STEP["Cannon bought"])
	end
	if plot2:isOpen() and self:is("First run") then self:complete(STEP["Spend it"]) end
	if self:is("Cannon bought") and (crates2:isOpen() or (crates2.stage and crates2.stage.Visible)) then self:complete(STEP.Crate) end

	local hx = self.ctx.hubX and self.ctx.hubX()
	-- (2026-10-18) a reward already claimed today counts at once, whichever button it was claimed from:
	-- the checklist's last row used to stay unticked until the hidden FLOAT and DIVE steps were done
	if not self:is("Daily") and v ~= nil and v.daily ~= nil and v.daily.last == Game.utcDay(math.floor(workspace:GetServerTimeNow())) then
		self:complete(STEP.Daily)
	end
	if self:is("Dive") and not self:is("Daily") then
		-- the daily reward, the first thing (it waited for the choice): CLAIM under its button
		local today = Game.utcDay(math.floor(workspace:GetServerTimeNow()))
		local claimable = v ~= nil and v.daily ~= nil and v.daily.last ~= today
		if hx and hx:isDailyOpen() then
			self.sawDaily = true
			if hx.dailyClaim and onScreen(hx.dailyClaim) then
				self:hubShow("daily", "CLAIM YOUR DAILY REWARD", hx.dailyClaim, C.yellow,
					"Free cash and keys every day. Miss a day and the streak starts over.", true)
				want = true
			end
		elseif self.sawDaily or not claimable then
			self:complete(STEP.Daily)
		elseif hx and hx.dailyDone and self.ctx.idle() and self.ctx.showDaily then
			-- (HubExtras already had its go this session: bring it up here)
			self.ctx.showDaily()
		end
	elseif receipt.active and btns and onScreen(btns.upgrade) then
		-- on the payout: SPEND IT over Upgrade, or how much further the new cannon went
		if self.further and os.clock() < self.further.until_ then
			self:hubShow("further", self.further.text, btns.again, C.gold, "The bigger cannon fires your tyre faster.", true)
			want = true
		elseif self:is("First run") and not self:is("Spend it") and credits >= price then
			self:hubShow("spend", "SPEND IT", btns.upgrade, C.blue, "Upgrades make every launch go further.", true, nil, true)
			want = true
		end
	elseif plot2:isOpen() then
		if self:is("Spend it") and not self:is("Cannon bought") then
			local row = plot2.rows and plot2.rows.cannon
			if row and onScreen(row.buy.root) then
				if credits >= price then
					self:hubShow("cannon", "BUY CANNON", row.buy.root, C.green, "A stronger cannon fires the tyre faster: more distance, more cash.", nil, nil, true)
				else
					self:hubShow("cannon", "NOT YET. ONE MORE RUN", row.buy.root, C.green, "Every run pays cash. Come back when you can afford it.")
				end
				want = true
			end
		end
	elseif self.ctx.idle() and hub2 then
		local launch = hub2.launchBtn and hub2.launchBtn.root
		if not self:is("Launch") and onScreen(launch) then
			self:hubShow("launch", "PRESS LAUNCH", launch, C.accent, "Fires your tyre out of the cannon. The further it goes, the more cash.")
			want = true
		elseif self:is("First run") and not self:is("Cannon bought") then
			if credits >= price and hub2.dock.PLOT and onScreen(hub2.dock.PLOT.root) then
				self:hubShow("plot", "UPGRADE YOUR CANNON", hub2.dock.PLOT.root, C.accent, "Your yard's machines. Upgrades here make every run go further.")
				want = true
			elseif onScreen(launch) then
				self:hubShow("again", "ONE MORE RUN", launch, C.accent, "Every run pays cash. Save up for your first upgrade.")
				want = true
			end
		elseif self:is("Cannon bought") and not self:is("Crate") and v and (v.keys or 0) >= 1 and hub2.dock.CRATES and onScreen(hub2.dock.CRATES.root) then
			-- (right after the cannon: a new tyre to go with it, before the next launch)
			self:hubShow("crate", "OPEN A CRATE", hub2.dock.CRATES.root, C.purple, "Your key opens a crate: a new tyre. Better tyres earn more cash.")
			crates2.preferKeys = true
			want = true
		elseif self:is("Cannon bought") and not self:is("Second run") and onScreen(launch) then
			self:hubShow("again", "LAUNCH AGAIN", launch, C.accent, "Your new cannon fires harder. See how much further you go.")
			want = true
		elseif self:is("Second run") and not self.autoTaught and hub2.auto and onScreen(hub2.auto.card) then
			-- (2026-10-16) the auto-cannon, once: it earns while you're here, far less while you're away
			self.autoT0 = self.autoT0 or os.clock()
			self:hubShow("auto", "YOUR YARD EARNS TOO", hub2.auto.card, C.gold, "Tap it: it fires on its own while you're here. Away, it pays far less.")
			want = true
			if hub2.autoBox or os.clock() - self.autoT0 > 10 then self.autoTaught = true end
		end
	end
	if not want then
		p:hide()
		self.focus:off()
		self.focus:step(dt, origin)
		return
	end
	-- the yard's focus: a lighter dim round the button the plate's over (not on the daily reward:
	-- its own dim's already behind it)
	if p.id == "daily" then self.focus:off() else self.focus:to(p.anchor, p.color or C.accent, DIM_YARD) end
	self.focus:step(dt, origin)
	-- sit just over the button, bobbing a little
	local a = p.anchor
	if a then
		-- (measured from the screen gui itself: it ignores the top bar's inset, AbsolutePosition doesn't)
		local pos = a.AbsolutePosition - origin
		local size = a.AbsoluteSize
		local bob = math.sin(os.clock() * 3) * 4
		-- (2026-10-18) the plate goes on whichever side of the button has room: pushed back on screen it
		-- used to sit right over the button it points at (the yard editor's Done in the top bar; Upgrade on
		-- the run results, at the bottom)
		local ph = p.root.AbsoluteSize.Y
		local pw = p.root.AbsoluteSize.X
		local W = self.gui.AbsoluteSize.X
		local roomAbove = pos.Y - 6 - ph >= 8
		local roomBelow = pos.Y + size.Y + 10 + ph <= self.gui.AbsoluteSize.Y - 8
		local roomRight = pos.X + size.X + 16 + pw <= W - 8
		local roomLeft = pos.X - 16 - pw >= 8
		if p.beside and (roomRight or roomLeft) then
			p.root.AnchorPoint = Vector2.new(if roomRight then 0 else 1, 0.5)
			p.root.ZIndex = 90
			p.root.Position = UDim2.fromOffset(if roomRight then pos.X + size.X + 16 + bob else pos.X - 16 - bob, pos.Y + size.Y / 2)
		elseif (p.below and (roomBelow or not roomAbove)) or (not p.below and not roomAbove and roomBelow) then
			p.root.AnchorPoint = Vector2.new(0.5, 0)
			p.root.ZIndex = 90
			p.root.Position = UDim2.fromOffset(onScreenX(p, pos.X + size.X / 2, self.gui), pos.Y + size.Y + 10 + bob)
		elseif pos.X + size.X / 2 < self.gui.AbsoluteSize.X * 0.22 then
			-- (a tile in the left-hand column: beside it, not over the tiles above it, and past the tile
			-- next to it too: on CRATES it used to cover ZONES, 2026-10-18)
			p.root.AnchorPoint = Vector2.new(0, 0.5)
			p.root.ZIndex = 60
			local past = if pos.X + size.X / 2 < self.gui.AbsoluteSize.X * 0.11 then size.X + 18 else 0
			p.root.Position = UDim2.fromOffset(pos.X + size.X + past + 14 + bob, pos.Y + size.Y / 2)
		else
			p.root.AnchorPoint = Vector2.new(0.5, 1)
			p.root.ZIndex = 60
			p.root.Position = UDim2.fromOffset(onScreenX(p, pos.X + size.X / 2, self.gui), pos.Y - 6 + bob)
		end
		keepOnScreen(p, self.gui)
	end
end

return Tutorial
