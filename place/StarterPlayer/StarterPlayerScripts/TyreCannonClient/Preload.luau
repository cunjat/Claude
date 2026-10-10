--!strict
-- TYRE CANNON :: Preload
-- Loads everything the game can show before the loading screen lifts, one stage at a time, so the
-- bar moves per thing being readied rather than per file:
--   the yard, the workshop, the garage, the road, the tyres, the sounds, the interface, warm-up
-- The last stage draws every model and fires every effect once, off-camera and behind the loading
-- screen, so nothing hitches the first time it's actually seen.
--   Preload.run(gui, report)   blocks until done; report(stageIndex, stageName, kInsideStage)
--   Preload.Stages             the stage names, in order

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local Preload = {}

Preload.Stages = {
	"THE YARD", "THE ROAD", "THE TYRES", "THE SOUNDS", "THE INTERFACE", "WARMING UP",
}

-- sound ids that only ever appear in code
local CODE_SOUNDS = {
	"rbxassetid://122316613819334", "rbxassetid://9112854440", "rbxassetid://9125402735", "rbxassetid://9118823101",
	"rbxassetid://5540424854", "rbxassetid://9114065998", "rbxassetid://9120386436",
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

local STAGE_CAP = 15 -- seconds; a stage that can't finish in this long moves on rather than hanging

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

-- preload a list in small batches, reporting how far through it is
local function load(list: { any }, onK: (number) -> ())
	local total = #list
	if total == 0 then
		onK(1)
		return
	end
	local started = os.clock()
	local BATCH = 16
	for i = 1, total, BATCH do
		local last = math.min(i + BATCH - 1, total)
		pcall(function() ContentProvider:PreloadAsync(table.move(list, i, last, 1, {})) end)
		onK(last / total)
		if os.clock() - started > STAGE_CAP then break end
	end
	onK(1)
end

-- every model drawn once in front of the camera (the loading screen covers it), a few at a time
local function warmUp(assets: Instance?, onK: (number) -> ())
	if not assets then
		onK(1)
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
		onK(1)
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "_WarmUp"
	holder.Parent = workspace
	local cam = workspace.CurrentCamera
	local BATCH = 12
	local started = os.clock()
	for i = 1, total, BATCH do
		local batch = {}
		for j = i, math.min(i + BATCH - 1, total) do
			local ok, copy = pcall(function() return sources[j]:Clone() end)
			if ok and copy then
				for _, d in ipairs(copy:GetDescendants()) do
					if d:IsA("LuaSourceContainer") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
					elseif d:IsA("Sound") then
						d.Playing = false
						d.Volume = 0
					end
				end
				if copy:IsA("BasePart") then
					copy.Anchored = true
					copy.CanCollide = false
				end
				-- a row in front of the lens, far enough to be in view and drawn
				local k = j - i
				local where = cam.CFrame * CFrame.new((k - BATCH / 2) * 14, 0, -90)
				pcall(function() (copy :: any):PivotTo(where) end)
				copy.Parent = holder
				for _, d in ipairs(copy:GetDescendants()) do
					if d:IsA("ParticleEmitter") then
						d.Enabled = false
						pcall(function() d:Emit(2) end)
					end
				end
				table.insert(batch, copy)
			end
		end
		-- let them render a few frames, then clear the row
		for _ = 1, 3 do RunService.RenderStepped:Wait() end
		for _, c in ipairs(batch) do c:Destroy() end
		onK(math.min(i + BATCH - 1, total) / total)
		if os.clock() - started > STAGE_CAP then break end
	end
	holder:Destroy()
	onK(1)
end

function Preload.run(gui: Instance, report: (number, string, number) -> ())
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

	-- 1 the yard
	local yard = {}
	contentOf(child(assets, "Props"), yard)
	contentOf(child(assets, "Characters"), yard)
	contentOf(child(world, "Decor"), yard)
	for _, x in ipairs(yard) do add(1, x) end
	-- 2 the road: obstacles, roadside props, every effect
	local list = {}
	contentOf(child(world, "Obstacles"), list)
	contentOf(child(world, "Props"), list)
	contentOf(child(assets, "VFX"), list)
	for _, x in ipairs(list) do add(2, x) end
	-- 3 the tyres: wheel parts, effect sheets, particle textures
	list = {}
	contentOf(child(assets, "Wheel"), list)
	for _, x in ipairs(list) do add(3, x) end
	if type(PackFX) == "table" and PackFX.Sheet then
		for _, id in pairs(PackFX.Sheet) do add(3, id) end
	end
	if type(Icons) == "table" and Icons.Particle then
		for _, id in pairs(Icons.Particle) do add(3, id) end
	end
	for _, id in ipairs(CODE_IMAGES) do add(3, id) end
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

	for i, name in ipairs(Preload.Stages) do
		report(i, name, 0)
		if i == #Preload.Stages then
			warmUp(assets, function(k) report(i, name, k) end)
		else
			load(stages[i], function(k) report(i, name, k) end)
		end
		report(i, name, 1)
	end
end

return Preload
