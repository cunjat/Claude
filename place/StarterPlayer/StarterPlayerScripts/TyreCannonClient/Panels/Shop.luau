--!strict
-- TYRE CANNON :: Panels / Shop
-- Buying only. Arming charms lives in the Garage; tyre, rim and trail looks
-- live on the Workbench. FEATURED opens first: three picks that change every day,
-- each turning on its own turntable. Engine and paint cards turn real models too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))
local Progress = require(Root.Modules:WaitForChild("Progress"))
local WheelAssembly = require(Root.Modules:WaitForChild("WheelAssembly"))
local Remotes = Root:WaitForChild("Remotes")
local UI = require(script.Parent.Parent.UI)
local T = UI.Theme

local SUBS = {
	Featured = "Three picks, new every day.",
	Charms = "One-launch boosts. Arm them in the Garage.",
	Boosters = "Paid in metal from the road. Timers only run while you're in the game.",
	Engines = "The machine that fires you. Better engines hit harder and forgive worse timing.",
	Paint = "Paint for the rig in your yard. Looks only.",
	Credits = "Optional. Every credit here can be earned by running.",
}

--==============================================================
-- models for the viewports
--==============================================================
local function strip(model: Instance)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("Light") or d:IsA("ParticleEmitter")
			or d:IsA("Sound") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
end

-- the engine's flywheel, hub and spokes, in the engine's own colours and size
local function flywheelModel(g): Model
	local m = Instance.new("Model")
	local d = 11.4 * (1 + (g.tier - 1) * 0.09)
	local w = 1.6 + (g.tier - 1) * 0.18
	local function cyl(name: string, size: Vector3, color: Color3, mat: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = size
		p.Color = color
		p.Material = mat
		p.Anchored = true
		p.Parent = m
		return p
	end
	local fly = cyl("Flywheel", Vector3.new(w, d, d), g.neon and g.flywheel:Lerp(Color3.new(0, 0, 0), 0.62) or g.flywheel, Enum.Material.Metal)
	cyl("Face", Vector3.new(w + 0.1, d * 0.8, d * 0.8), g.flywheel:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Metal)
	cyl("Hub", Vector3.new(w + 0.6, 3.4, 3.4), g.trim, Enum.Material.Metal)
	for i = 0, 3 do
		local s = Instance.new("Part")
		s.Name = "Spoke"
		s.Size = Vector3.new(w + 0.22, d * 0.8, 0.9)
		s.CFrame = CFrame.Angles(math.rad(45 * i), 0, 0)
		s.Color = g.flywheel:Lerp(Color3.new(1, 1, 1), 0.15)
		s.Material = g.neon and Enum.Material.Neon or Enum.Material.Metal
		s.Anchored = true
		s.Parent = m
	end
	-- a band of the engine's body colour round the rim, so the tiers read apart
	cyl("Band", Vector3.new(w * 0.4, d + 0.14, d + 0.14), g.body, Enum.Material.SmoothPlastic)
	m.PrimaryPart = fly
	m:PivotTo(CFrame.Angles(0, math.rad(90), 0))
	return m
end

-- a tin of paint: steel can, the colour on its label and a lick down the side
local function paintTin(r): Model
	local m = Instance.new("Model")
	local tint = r.tint or Color3.fromRGB(24, 122, 92)
	local function part(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.Anchored = true
		p.Parent = m
		return p
	end
	local up = CFrame.Angles(0, 0, math.rad(90))
	part("Can", Enum.PartType.Cylinder, Vector3.new(5, 4.4, 4.4), up, Color3.fromRGB(168, 172, 178), Enum.Material.Metal)
	part("Label", Enum.PartType.Cylinder, Vector3.new(3, 4.46, 4.46), up * CFrame.new(-0.2, 0, 0), tint, r.metal and Enum.Material.Metal or Enum.Material.SmoothPlastic)
	part("Lid", Enum.PartType.Cylinder, Vector3.new(0.3, 4.6, 4.6), CFrame.new(0, 2.6, 0) * up, Color3.fromRGB(120, 124, 130), Enum.Material.Metal)
	part("Paint", Enum.PartType.Cylinder, Vector3.new(0.1, 3.8, 3.8), CFrame.new(0, 2.78, 0) * up, tint, r.glow and Enum.Material.Neon or Enum.Material.SmoothPlastic)
	part("Drip", Enum.PartType.Block, Vector3.new(0.5, 1.6, 0.12), CFrame.new(1.2, 1.9, -2.22), tint, Enum.Material.SmoothPlastic)
	part("Handle", Enum.PartType.Block, Vector3.new(4.6, 0.14, 0.14), CFrame.new(0, 3.1, 0), Color3.fromRGB(90, 94, 100), Enum.Material.Metal)
	return m
end

local function wheelModel(kind: string, id: string, profile): Model
	local m = WheelAssembly.build(nil, {
		diameter = 6,
		skin = kind == "skin" and id or (profile and profile.skin or "stock"),
		rim = kind == "rim" and id or (profile and profile.rim or "steel"),
	})
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Light") then d:Destroy() end
	end
	return m
end

-- a turning model in a viewport; the whole list turns while the shop is open
local spinners: { any } = {}
local function viewport(parent: Instance, model: Model, size: UDim2, pos: UDim2, distance: number, turntable: boolean)
	local vpf = UI.mk("ViewportFrame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = pos, Size = size, BackgroundTransparency = 1, ZIndex = 13,
		Ambient = Color3.fromRGB(120, 116, 112), LightColor = Color3.fromRGB(255, 238, 220), LightDirection = Vector3.new(-0.4, -0.7, -1),
		Parent = parent,
	})
	local cam = Instance.new("Camera")
	cam.FieldOfView = 32
	cam.Parent = vpf
	vpf.CurrentCamera = cam
	strip(model)
	local cf, box = model:GetBoundingBox()
	local holder = Instance.new("Model")
	model.Parent = holder
	local offset = cf.Position
	local radius = math.max(box.X, box.Y, box.Z) / 2
	if turntable then
		local disc = Instance.new("Part")
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.5, radius * 2.4, radius * 2.4)
		disc.CFrame = CFrame.new(offset.X, offset.Y - box.Y / 2 - 0.3, offset.Z) * CFrame.Angles(0, 0, math.rad(90))
		disc.Color = Color3.fromRGB(46, 48, 52)
		disc.Material = Enum.Material.DiamondPlate
		disc.Anchored = true
		disc.Parent = holder
	end
	holder.Parent = vpf
	local dist = (distance or 2.9) * radius
	cam.CFrame = CFrame.lookAt(offset + Vector3.new(0, radius * 0.55, dist), offset + Vector3.new(0, -radius * 0.05, 0))
	table.insert(spinners, { holder = holder, centre = offset, angle = math.random() * 6.28, base = holder:GetPivot() })
	return vpf
end

return function(hub)
	local m = hub:modal("Shop", "SHOP", "", 1010, 660)
	local tab = "Featured"
	local refresh
	local _, setTab = hub:tabs(m.body, { "Featured", "Charms", "Boosters", "Engines", "Paint", "Credits" }, 132, function(n)
		tab = n
		refresh()
	end)
	local layout = UI.grid(226, 176, 12)
	local grid = hub:scroll(m.body, UDim2.fromOffset(0, 48), UDim2.new(1, 0, 1, -48), layout)

	RunService.RenderStepped:Connect(function(dt)
		if not m.frame.Visible then return end
		for i = #spinners, 1, -1 do
			local s = spinners[i]
			if not s.holder.Parent or not s.holder.Parent.Parent then
				table.remove(spinners, i)
			else
				s.angle += dt * 0.7
				s.holder:PivotTo(CFrame.new(s.centre) * CFrame.Angles(0, s.angle, 0) * CFrame.new(-s.centre) * s.base)
			end
		end
	end)

	local function held(p, cat: string, id: string): boolean
		return (p[cat] and p[cat][id] == true) or (p.permanent and p.permanent[cat] and p.permanent[cat][id] == true)
	end
	local function button(card: Instance, text: string, style: any)
		local b = UI.button(text, style, 196, 36)
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, 0, 1, -12)
		b.TextSize = 15
		b.ZIndex = 13
		b.Parent = card
		return b
	end

	-- today's three: one tyre or rim, one engine or paint, one more of either, never owned
	local function featured(p)
		local pool = {}
		local function add(kind: string, cat: string, item)
			if item.default or item.robux or item.locked or (item.cost or 0) <= 0 then return end
			if held(p, cat, item.id) then return end
			table.insert(pool, { kind = kind, cat = cat, item = item })
		end
		for _, s in ipairs(Config.Skins) do add("skin", "skins", s) end
		for _, r in ipairs(Config.Rims) do add("rim", "rims", r) end
		for _, g in ipairs(Config.Generators) do add("generator", "generators", g) end
		for _, r in ipairs(Config.RigSkins) do add("rig", "rigs", r) end
		local rng = Random.new(Progress.today() * 7919 + 17)
		local picks, used = {}, {}
		for _ = 1, 40 do
			if #picks >= 3 or #pool == 0 then break end
			local i = rng:NextInteger(1, #pool)
			local e = pool[i]
			if not used[e.item.id] then
				used[e.item.id] = true
				table.insert(picks, e)
			end
		end
		return picks
	end

	local STAMP_SUB = { skin = "TYRE  ·  FITTED ON YOUR WHEEL", rim = "RIM  ·  FITTED ON YOUR WHEEL", generator = "ENGINE  ·  INSTALLED ON YOUR RIG", rig = "PAINT  ·  ON YOUR RIG" }

	refresh = function()
		setTab(tab)
		m.sub.Text = SUBS[tab] or ""
		local p = hub.profile
		if not p then return end
		hub:clear(grid)

		if tab == "Featured" then
			layout.CellSize = UDim2.fromOffset(296, 440)
			local picks = featured(p)
			if #picks == 0 then
				layout.CellSize = UDim2.fromOffset(900, 80)
				local c = hub:card(grid, 0, 0, 1)
				hub:line(c, "YOU OWN EVERYTHING WE'D FEATURE. RESPECT.", 18, "display", T.good, 28, 24)
			end
			for i, e in ipairs(picks) do
				local item = e.item
				local tier = Config.CosmeticTier(item)
				local color = Config.TierColor(tier)
				local card = hub:card(grid, 0, 0, i, color)
				local model
				if e.kind == "skin" or e.kind == "rim" then
					model = wheelModel(e.kind, item.id, p)
				elseif e.kind == "generator" then
					model = flywheelModel(item)
				else
					model = paintTin(item)
				end
				viewport(card, model, UDim2.fromOffset(276, 250), UDim2.new(0.5, 0, 0, 14), 4.6, true)
				hub:line(card, string.upper(tier), 12, "monoBold", color, 272, 16)
				hub:line(card, string.upper(item.name), 22, "display", T.text, 290, 28)
				hub:line(card, item.desc or "", 13, "body", T.dim, 322, 36)
				local afford = p.credits >= item.cost
				local b = button(card, "BUY  " .. UI.comma(item.cost) .. " CR", afford and "primary" or "off")
				b.Size = UDim2.fromOffset(250, 42)
				b.Activated:Connect(function()
					local res = hub:call("BuyItem", e.kind, item.id)
					if res and res.ok then UI.stamp(hub.gui, item.name, color, STAMP_SUB[e.kind] or "BOUGHT") end
				end)
			end

		elseif tab == "Charms" then
			layout.CellSize = UDim2.fromOffset(226, 170)
			for i, c in ipairs(Config.Charms) do
				local card = hub:card(grid, 0, 0, i)
				hub:line(card, string.upper(c.name), 18, "display", c.fx, 12, 22)
				hub:line(card, c.desc, 13, "body", T.dim, 38, 48)
				hub:line(card, ("CARRYING %d"):format(p.charms[c.id] or 0), 12, "monoBold", T.faint, 92, 16)
				button(card, UI.comma(c.cost) .. " CR", p.credits >= c.cost and "primary" or "off").Activated:Connect(function()
					local res = hub:call("BuyItem", "charm", c.id)
					if res and res.ok then UI.stamp(hub.gui, "+1 " .. c.name, c.fx, "CHARM  ·  ARM IT IN THE GARAGE") end
				end)
			end

		elseif tab == "Boosters" then
			layout.CellSize = UDim2.fromOffset(226, 196)
			for i, b in ipairs(Config.Boosters) do
				local left = (p.boosters and p.boosters[b.id]) or 0
				local card = hub:card(grid, 0, 0, i, left > 0 and b.color or nil)
				hub:line(card, string.upper(b.name), 18, "display", b.color, 12, 22)
				hub:line(card, b.desc, 13, "body", T.dim, 38, 56)
				hub:line(card, left > 0 and (b.kind == "timed" and ("RUNNING  " .. UI.clock(left)) or (left .. " LAUNCHES LEFT")) or "NOT RUNNING", 12, "monoBold", left > 0 and T.good or T.faint, 98, 16)
				hub:line(card, UI.money(b.cost), 13, "monoBold", T.text, 118, 16)
				button(card, left > 0 and "ADD MORE" or "BUY", Progress.canAfford(p, b.cost) and "primary" or "off").Activated:Connect(function()
					local res = hub:call("BuyBooster", b.id)
					if res and res.ok then UI.stamp(hub.gui, b.name, b.color, b.kind == "timed" and "BOOSTER  ·  RUNNING NOW" or "BOOSTER  ·  CHARGES ADDED") end
				end)
			end

		elseif tab == "Engines" then
			layout.CellSize = UDim2.fromOffset(300, 360)
			for i, g in ipairs(Config.Generators) do
				local owned = held(p, "generators", g.id)
				local on = (p.generator or "field") == g.id
				local card = hub:card(grid, 0, 0, i, on and T.accent or nil)
				viewport(card, flywheelModel(g), UDim2.fromOffset(280, 150), UDim2.new(0.5, 0, 0, 8), 3.8, false)
				local y = 150
				hub:line(card, "TIER " .. g.tier, 12, "monoBold", g.trim, y + 8, 16)
				hub:line(card, string.upper(g.name), 19, "display", T.text, y + 26, 24)
				hub:line(card, g.desc, 13, "body", T.dim, y + 52, 36)
				local e = g.effect
				hub:line(card, ("LAUNCH +%d%%   WINDOW +%d%%   FUEL +%d"):format(
					math.floor((e.launchMult - 1) * 100 + 0.5), math.floor((e.windowMult - 1) * 100 + 0.5), e.fuelAdd), 12, "monoBold", g.trim, y + 96, 16)
				local b
				if on then
					b = button(card, "INSTALLED", "off")
				elseif owned then
					b = button(card, "INSTALL", "primary")
					b.Activated:Connect(function() hub:call("EquipCosmetic", "generator", g.id) end)
				else
					b = button(card, "BUY  " .. UI.comma(g.cost) .. " CR", p.credits >= g.cost and "good" or "off")
					b.Activated:Connect(function()
						local res = hub:call("BuyItem", "generator", g.id)
						if res and res.ok then UI.stamp(hub.gui, g.name, g.trim, "ENGINE  ·  INSTALLED ON YOUR RIG") end
					end)
				end
				b.Size = UDim2.fromOffset(260, 38)
			end

		elseif tab == "Paint" then
			layout.CellSize = UDim2.fromOffset(226, 250)
			for i, r in ipairs(Config.RigSkins) do
				local owned = held(p, "rigs", r.id)
				local on = (p.rigSkin or "works") == r.id
				local card = hub:card(grid, 0, 0, i, on and T.accent or nil)
				viewport(card, paintTin(r), UDim2.fromOffset(206, 110), UDim2.new(0.5, 0, 0, 8), 3.6, false)
				hub:line(card, string.upper(r.name), 17, "display", T.text, 126, 22)
				hub:line(card, r.desc or "", 13, "body", T.dim, 150, 32)
				local b
				if on then
					b = button(card, "ON THE RIG", "off")
				elseif owned then
					b = button(card, "PAINT IT", "primary")
					b.Activated:Connect(function() hub:call("EquipCosmetic", "rig", r.id) end)
				elseif r.locked then
					b = button(card, "EARNED ONLY", "off")
				else
					b = button(card, UI.comma(r.cost) .. " CR", p.credits >= r.cost and "good" or "off")
					b.Activated:Connect(function()
						local res = hub:call("BuyItem", "rig", r.id)
						if res and res.ok then UI.stamp(hub.gui, r.name, r.tint or T.accent, "PAINT  ·  ON YOUR RIG") end
					end)
				end
			end

		else
			layout.CellSize = UDim2.fromOffset(226, 176)
			for i, pk in ipairs(Config.CreditPacks) do
				local live = pk.devProductId ~= 0
				local card = hub:card(grid, 0, 0, i, pk.tag and T.accent or nil)
				if pk.tag then
					local tg = UI.chip(pk.tag, T.accent)
					tg.AnchorPoint = Vector2.new(0.5, 0)
					tg.Position = UDim2.new(0.5, 0, 0, 10)
					tg.ZIndex = 13
					tg.Parent = card
				end
				hub:line(card, UI.comma(pk.credits), 32, "display", T.accent, 34, 38)
				hub:line(card, "CREDITS  ·  " .. string.upper(pk.name), 12, "monoBold", T.faint, 76, 16)
				button(card, "R$ " .. pk.robux, live and "good" or "off").Activated:Connect(function()
					if not live then
						hub:toast("Not on sale yet.", T.bad)
						return
					end
					Remotes.BuyCreditPack:FireServer(pk.id)
				end)
			end
		end
	end

	hub:register("Shop", { frame = m.frame, refresh = refresh })
end
