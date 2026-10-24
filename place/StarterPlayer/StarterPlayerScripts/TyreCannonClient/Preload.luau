--!strict
-- TYRE CANNON :: Preload
-- What the loading screen waits for, and what loads after it.
--   blocking (the bar shows these):  the interface (every screen's art, every icon, one label per
--                                     font) and your yard (your plot as it stands, the yard stages,
--                                     cannons and machines it's built from, the characters)
--   background (once you're in):     the road first (a run is usually the next thing you do: its
--                                     obstacles, roadside props, zone scenery, run pieces, skills,
--                                     effects), then the tyres, the sounds, the rest of the hub (park,
--                                     nature, vehicles, prestige kits), and last a quiet warm-up that
--                                     draws the road's models once off-screen so the first run doesn't
--                                     hitch on them
-- (2026-10-24, the owner: the loading screen used to wait for every tyre, every zone's scenery,
-- every sound and a pass drawing every model; now it waits for the menus and your yard)
--   Preload.run(gui, report, opts?)   blocks until the blocking part is done; report(stageIndex,
--                                     stageName, kInsideStage, n?, of?); opts.plot: () -> Instance?
--   Preload.background()              the rest, a small batch at a time (call once you're in)
--   Preload.Stages                    the blocking stage names, in order

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local Preload = {}

Preload.Stages = { "THE INTERFACE", "YOUR YARD" }

-- sound ids that only ever appear in code
local CODE_SOUNDS = {
	"rbxassetid://122316613819334", "rbxassetid://71949512559141", "rbxassetid://9125402735", "rbxassetid://9114036511",
	"rbxassetid://5540424854", "rbxassetid://9114065998", "rbxassetid://9120386436", "rbxassetid://9112854440", "rbxassetid://9118823101",
}
-- images that only ever appear in code (pack effect sheets)
local CODE_IMAGES = {
	"rbxassetid://11858203067", "rbxassetid://11844017484", "rbxassetid://13743483729", "rbxassetid://13726321388",
	"rbxassetid://12356442287", "rbxassetid://13953700240", "rbxasset://textures/particles/smoke_main.dds",
}

local CONTENT = {
	"MeshPart", "SpecialMesh", "Decal", "Texture", "Sound", "ParticleEmitter", "Beam", "Trail",
	"SurfaceAppearance", "Animation", "Sky", "PartOperation", "ImageLabel", "ImageButton",
}

local STAGE_CAP = 30 -- seconds; a stage that can't finish in this long moves on rather than hanging

local function contentOf(folder: Instance?, into: { any })
	if not folder then return end
	for _, d in ipairs(folder:GetDescendants()) do
		for _, class in ipairs(CONTENT) do
			if d:IsA(class) then
				table.insert(into, d)
				break
			end
		end
	end
end

local function child(parent: Instance?, name: string): Instance?
	return parent and parent:FindFirstChild(name) or nil
end

-- preload a list in small batches, reporting how far through it is (and how many of how many)
local function load(list: { any }, onK: (number, number, number) -> ())
	local total = #list
	if total == 0 then
		onK(1, 0, 0)
		return
	end
	local started = os.clock()
	local BATCH = 12
	for i = 1, total, BATCH do
		local last = math.min(i + BATCH - 1, total)
		pcall(function() ContentProvider:PreloadAsync(table.move(list, i, last, 1, {})) end)
		onK(last / total, last, total)
		if os.clock() - started > STAGE_CAP then break end
	end
	onK(1, total, total)
end

-- every model in these folders drawn once (meshes and textures sent to the graphics card), a few at
-- a time, in a small, all-but-invisible window in the corner (a ViewportFrame), so nothing in front
-- of the real camera is ever seen
local function warmUp(groups: { Instance }, onK: (number, number, number) -> ())
	local sources = {}
	for _, group in ipairs(groups) do
		local items = group:GetChildren()
		-- World is grouped one level deeper (Decor, Obstacles, Props)
		if group.Name == "World" then
			items = {}
			for _, sub in ipairs(group:GetChildren()) do
				for _, m in ipairs(sub:GetChildren()) do table.insert(items, m) end
			end
		end
		for _, m in ipairs(items) do
			if m:IsA("Model") or m:IsA("BasePart") then table.insert(sources, m) end
		end
	end
	local total = #sources
	if total == 0 then
		onK(1, 0, 0)
		return
	end
	local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local sg = Instance.new("ScreenGui")
	sg.Name = "_WarmUp"
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 5990
	sg.ResetOnSpawn = false
	local vp = Instance.new("ViewportFrame")
	vp.AnchorPoint = Vector2.new(1, 1)
	vp.Position = UDim2.fromScale(1, 1)
	vp.Size = UDim2.fromOffset(96, 96)
	vp.BackgroundTransparency = 1
	vp.ImageTransparency = 0.985
	vp.Parent = sg
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 70
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 40, 160), Vector3.new(0, 0, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	sg.Parent = pg
	local BATCH = 10
	local started = os.clock()
	for i = 1, total, BATCH do
		local batch = {}
		for j = i, math.min(i + BATCH - 1, total) do
			local ok, copy = pcall(function() return sources[j]:Clone() end)
			if ok and copy then
				for _, d in ipairs(copy:GetDescendants()) do
					if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("Light") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
					end
				end
				if copy:IsA("BasePart") then
					copy.Anchored = true
					copy.CanCollide = false
				end
				-- a row across the little window's view
				local k = j - i
				pcall(function() (copy :: any):PivotTo(CFrame.new((k - BATCH / 2) * 24, 0, 0)) end)
				copy.Parent = world
				table.insert(batch, copy)
			end
		end
		-- let them draw a few frames, then clear the row
		for _ = 1, 3 do RunService.RenderStepped:Wait() end
		for _, c in ipairs(batch) do c:Destroy() end
		local done = math.min(i + BATCH - 1, total)
		onK(done / total, done, total)
		if os.clock() - started > STAGE_CAP then break end
	end
	sg:Destroy()
	onK(1, total, total)
end

function Preload.run(gui: Instance, report: (number, string, number, number?, number?) -> (), opts: { plot: (() -> Instance?)? }?)
	local parent = script.Parent
	local root = ReplicatedStorage:FindFirstChild("TyreCannon")
	local assets = child(root, "Assets")
	local world = child(assets, "World")
	local Icons = (select(2, pcall(require, parent:WaitForChild("Icons"))) :: any)
	local PackFX = (select(2, pcall(require, parent:WaitForChild("PackFX"))) :: any)
	local Sound = (select(2, pcall(require, parent:WaitForChild("Sound"))) :: any)

	local seen: { [any]: boolean } = {}
	local function adder(list: { any })
		return function(x: any)
			if x == nil or x == "" or seen[x] then return end
			seen[x] = true
			table.insert(list, x)
		end
	end
	local function addAll(list: { any }, from: { any })
		local add = adder(list)
		for _, x in ipairs(from) do add(x) end
	end

	-- 1 the interface: every icon, every image already in the UI, one label per font face
	local ui = {}
	local addUi = adder(ui)
	if type(Icons) == "table" and Icons.all then
		for _, id in ipairs(Icons.all()) do addUi(id) end
	end
	local Kit = (select(2, pcall(require, parent:WaitForChild("Kit"))) :: any)
	if type(Kit) == "table" and Kit.Art then
		for _, a in pairs(Kit.Art) do addUi(if type(a) == "table" then a.id else a) end
		for _, id in pairs(Kit.Icon or {}) do addUi(id) end
	end
	-- the gauges: the speedo and the launch's rev gauge share one housing and the lit segment
	local Gauge = (select(2, pcall(require, parent:WaitForChild("Gauge"))) :: any)
	if type(Gauge) == "table" and Gauge.Art then
		for _, id in pairs(Gauge.Art) do addUi(id) end
	end
	-- every id the scripts name in code (zone pictures, stage cards, the crate shutter, the logo...)
	local okIds, ids = pcall(require, parent:WaitForChild("PreloadIds", 5))
	if okIds and type(ids) == "table" then
		for _, id in ipairs(ids) do addUi(id) end
	end
	local faces: { [string]: boolean } = {}
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			local key = tostring((d :: any).FontFace)
			if not faces[key] then
				faces[key] = true
				table.insert(ui, d)
			end
		elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
			addUi((d :: any).Image)
		end
	end

	-- 2 your yard: your plot as it stands now, and what yards are built from
	local yard = {}
	local mine = opts and opts.plot and opts.plot()
	local tmp = {}
	contentOf(mine, tmp)
	for _, name in ipairs({ "Stages", "Cannons", "Machines", "Characters", "Lobby", "Props" }) do
		contentOf(child(assets, name), tmp)
	end
	contentOf(child(world, "Decor"), tmp)
	addAll(yard, tmp)

	-- the background, in order: the road, the tyres, the sounds, the rest of the hub
	local road = {}
	tmp = {}
	contentOf(child(world, "Obstacles"), tmp)
	contentOf(child(world, "Props"), tmp)
	for _, name in ipairs({ "Scenery", "Run", "VFX", "Skills", "Roadside" }) do
		contentOf(child(assets, name), tmp)
	end
	addAll(road, tmp)
	local tyres = {}
	local addTyre = adder(tyres)
	tmp = {}
	contentOf(child(assets, "Wheel"), tmp)
	contentOf(child(assets, "Tyres"), tmp)
	for _, x in ipairs(tmp) do addTyre(x) end
	if type(PackFX) == "table" and PackFX.Sheet then
		for _, id in pairs(PackFX.Sheet) do addTyre(id) end
	end
	if type(Icons) == "table" and Icons.Particle then
		for _, id in pairs(Icons.Particle) do addTyre(id) end
	end
	for _, id in ipairs(CODE_IMAGES) do addTyre(id) end
	local TyreShow = (select(2, pcall(require, parent:WaitForChild("TyreShow"))) :: any)
	if type(TyreShow) == "table" and TyreShow.Icons then
		for _, id in pairs(TyreShow.Icons) do addTyre(id) end
	end
	local sounds = {}
	local addSound = adder(sounds)
	if type(Sound) == "table" and Sound.Bank then
		for _, def in pairs(Sound.Bank) do addSound(def.id) end
	end
	for _, id in ipairs(CODE_SOUNDS) do addSound(id) end
	local hub = {}
	tmp = {}
	for _, name in ipairs({ "Park", "Nature", "Vehicles", "Vehicles2", "Prestige" }) do
		contentOf(child(assets, name), tmp)
	end
	addAll(hub, tmp)
	Preload.pending = { road, tyres, sounds, hub }
	Preload.warm = assets

	local blocking = { { ui, "THE INTERFACE" }, { yard, "YOUR YARD" } }
	for i, b in ipairs(blocking) do
		local list = b[1]
		report(i, b[2], 0, 0, #list)
		load(list, function(k, n, of) report(i, b[2], k, n, of) end)
		report(i, b[2], 1, #list, #list)
	end
end

-- after the loading screen: the rest, a small batch at a time with a breath between, so the hub
-- never stutters while it arrives; then the road's models drawn once, quietly, off-screen
function Preload.background()
	local lists = Preload.pending or {}
	Preload.pending = nil
	for _, list in ipairs(lists) do
		for i = 1, #list, 8 do
			pcall(function() ContentProvider:PreloadAsync(table.move(list, i, math.min(i + 7, #list), 1, {})) end)
			task.wait(0.05)
		end
	end
	local assets = Preload.warm
	Preload.warm = nil
	if assets then
		local picks = {}
		for _, name in ipairs({ "World", "Run", "Scenery" }) do
			local f = assets:FindFirstChild(name)
			if f then table.insert(picks, f) end
		end
		warmUp(picks, function() task.wait(0.1) end)
	end
end

return Preload
