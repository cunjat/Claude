--!strict
-- TYRE CANNON :: Preload
-- Loads everything the game can show before the loading screen lifts, one stage at a time, so the
-- bar moves per thing being readied rather than per file:
--   the yard, the road, the tyres, the sounds, the interface, warm-up
-- The last stage draws every model and fires every effect once, off-camera and behind the loading
-- screen, so nothing hitches the first time it's actually seen.
--   Preload.run(gui, report)   blocks until done; report(stageIndex, stageName, kInsideStage)
--   Preload.Stages             the stage names, in order

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local Preload = {}

-- what the loading screen waits for: all of it. The interface (every screen's art, the crate
-- pictures among it), the tyres (every tyre's picture and model), the yard you spawn in, the road
-- and everything on it, every sound, and then a warm-up that draws every model once, so nothing in
-- the game is fetched or built the first time it's seen. The loading scene plays over all of it,
-- so the wait is spent watching the game.
Preload.Stages = {
	"THE INTERFACE", "THE TYRES", "THE YARD", "THE ROAD", "THE SOUNDS", "WARMING UP",
}

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

-- every model drawn once (meshes and textures sent to the graphics card), a few at a time. They're
-- drawn in a small, all-but-invisible window in the corner (a ViewportFrame): the loading scene
-- shows the real world, and anything put in front of its camera would be seen.
local function warmUp(assets: Instance?, onK: (number, number, number) -> ())
	if not assets then
		onK(1, 0, 0)
		return
	end
	local sources = {}
	for _, group in ipairs(assets:GetChildren()) do
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

function Preload.run(gui: Instance, report: (number, string, number, number?, number?) -> ())
	local parent = script.Parent
	local root = ReplicatedStorage:FindFirstChild("TyreCannon")
	local assets = child(root, "Assets")
	local world = child(assets, "World")
	local Icons = (select(2, pcall(require, parent:WaitForChild("Icons"))) :: any)
	local PackFX = (select(2, pcall(require, parent:WaitForChild("PackFX"))) :: any)
	local Sound = (select(2, pcall(require, parent:WaitForChild("Sound"))) :: any)

	local stages: { { any } } = {}
	for i = 1, #Preload.Stages do stages[i] = {} end
	local seen: { [any]: boolean } = {}
	local function add(i: number, x: any)
		if x == nil or x == "" or seen[x] then return end
		seen[x] = true
		table.insert(stages[i], x)
	end

	-- 1 the yard: every stage of every yard, its machines and cannons, the lobby, the props and the
	-- people (the Workshop and Garage asset folders stay in Assets but nothing in play uses them now)
	local yard = {}
	for _, name in ipairs({ "Props", "Characters", "Stages", "Lobby", "Cannons", "Machines" }) do
		contentOf(child(assets, name), yard)
	end
	contentOf(child(world, "Decor"), yard)
	for _, x in ipairs(yard) do add(1, x) end
	-- 2 the road: obstacles, roadside props, every zone's scenery, the run's pieces, skills, effects
	local list = {}
	contentOf(child(world, "Obstacles"), list)
	contentOf(child(world, "Props"), list)
	for _, name in ipairs({ "VFX", "Scenery", "Run", "Skills" }) do
		contentOf(child(assets, name), list)
	end
	for _, x in ipairs(list) do add(2, x) end
	-- 3 the tyres: every collectable tyre's model (the index, the crates and the workbench show
	-- them all), the stock wheel, effect sheets, particle textures
	list = {}
	contentOf(child(assets, "Wheel"), list)
	contentOf(child(assets, "Tyres"), list)
	for _, x in ipairs(list) do add(3, x) end
	if type(PackFX) == "table" and PackFX.Sheet then
		for _, id in pairs(PackFX.Sheet) do add(3, id) end
	end
	if type(Icons) == "table" and Icons.Particle then
		for _, id in pairs(Icons.Particle) do add(3, id) end
	end
	for _, id in ipairs(CODE_IMAGES) do add(3, id) end
	-- every tyre's studio render (the grids show these)
	local TyreShow = (select(2, pcall(require, parent:WaitForChild("TyreShow"))) :: any)
	if type(TyreShow) == "table" and TyreShow.Icons then
		for _, id in pairs(TyreShow.Icons) do add(3, id) end
	end
	-- 6 the sounds
	if type(Sound) == "table" and Sound.Bank then
		for _, def in pairs(Sound.Bank) do add(4, def.id) end
	end
	for _, id in ipairs(CODE_SOUNDS) do add(4, id) end
	-- 7 the interface: every icon, every image already in the UI, one label per font face
	if type(Icons) == "table" and Icons.all then
		for _, id in ipairs(Icons.all()) do add(5, id) end
	end
	local Kit = (select(2, pcall(require, parent:WaitForChild("Kit"))) :: any)
	if type(Kit) == "table" and Kit.Art then
		for _, a in pairs(Kit.Art) do add(5, if type(a) == "table" then a.id else a) end
		for _, id in pairs(Kit.Icon or {}) do add(5, id) end
	end
	-- the gauges: the speedo and the launch's rev gauge share one housing and the lit segment
	local Gauge = (select(2, pcall(require, parent:WaitForChild("Gauge"))) :: any)
	if type(Gauge) == "table" and Gauge.Art then
		for _, id in pairs(Gauge.Art) do add(5, id) end
	end
	-- every id the scripts name in code (zone pictures, stage cards, the crate shutter, the logo...)
	local okIds, ids = pcall(require, parent:WaitForChild("PreloadIds", 5))
	if okIds and type(ids) == "table" then
		for _, id in ipairs(ids) do add(5, id) end
	end
	local faces: { [string]: boolean } = {}
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			local key = tostring((d :: any).FontFace)
			if not faces[key] then
				faces[key] = true
				table.insert(stages[5], d)
			end
		elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
			add(5, (d :: any).Image)
		end
	end

	local blocking = { { 5, "THE INTERFACE" }, { 3, "THE TYRES" }, { 1, "THE YARD" }, { 2, "THE ROAD" }, { 4, "THE SOUNDS" } }
	for i, b in ipairs(blocking) do
		report(i, b[2], 0, 0, #stages[b[1]])
		load(stages[b[1]], function(k, n, of) report(i, b[2], k, n, of) end)
		report(i, b[2], 1, #stages[b[1]], #stages[b[1]])
	end
	local w = #blocking + 1
	report(w, "WARMING UP", 0)
	warmUp(assets, function(k, n, of) report(w, "WARMING UP", k, n, of) end)
	report(w, "WARMING UP", 1)
	Preload.pending = {}
end

-- after the loading screen: anything still pending, a small batch at a time, so the hub never
-- stutters while it arrives (everything loads behind the loading screen now, so it's usually nothing)
function Preload.background()
	local lists = Preload.pending or {}
	Preload.pending = nil
	for _, list in ipairs(lists) do
		for i = 1, #list, 8 do
			pcall(function() ContentProvider:PreloadAsync(table.move(list, i, math.min(i + 7, #list), 1, {})) end)
			task.wait(0.05)
		end
	end
end

return Preload
