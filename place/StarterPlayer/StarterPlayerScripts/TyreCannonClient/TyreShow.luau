--!strict
-- TYRE CANNON :: TyreShow
-- How a tyre is shown in the UI.
--   TyreShow.stand(parent, size)   the display bay: a dark item well (its edge the tyre's rarity)
--                                  with a soft floor shadow, the tyre's 3D model standing on it and
--                                  turning slowly.
--                                  -> { root, set(tyreId), setTurning(on), setRarity(c), destroy() }
--   TyreShow.thumb(parent, tyreId, known, size, pos)
--                                  a card's still picture of the tyre, three-quarter on, upright;
--                                  a tyre not yet found is a dark silhouette.
--                                  -> (ViewportFrame, Model?)
--   TyreShow.pose(model, yaw)      stands a thumb's tyre at a turn (for a selected card's slow turn)

local RunService = game:GetService("RunService")
local UI = require(script.Parent.UI)
local Kit = require(script.Parent.Kit)
local TyreLook = require(script.Parent.TyreLook)

local TyreShow = {}

local D = 6 -- the tyre's diameter in the views
local THUMB_YAW = math.rad(-28)
local SPOT = "rbxassetid://119243950784301" -- art/ui/kit3/spot.svg

-- upright, its tread on the ground, turned `yaw` about the vertical
function TyreShow.pose(model: Model, yaw: number)
	model:PivotTo(CFrame.new(0, D / 2, 0) * CFrame.Angles(0, yaw, 0))
end

local function lights(vp: ViewportFrame)
	vp.Ambient = Color3.fromRGB(128, 124, 120)
	vp.LightColor = Color3.fromRGB(255, 240, 222)
	vp.LightDirection = Vector3.new(-0.35, -1, -0.55)
end

function TyreShow.stand(parent: Instance, size: UDim2): any
	-- a dark item well (its edge in the tyre's rarity) with a soft patch of floor and a contact
	-- shadow where the tyre stands
	local root = UI.mk("Frame", { Name = "TyreStand", Size = size, BackgroundTransparency = 1, Parent = parent })
	local well = Kit.slot(root, Color3.fromRGB(150, 152, 160), (root.ZIndex or 1))
	local rarity = (well:FindFirstChild("Edge") :: Frame):FindFirstChild("Rarity") :: UIStroke
	local spot = UI.mk("ImageLabel", {
		Name = "Spot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.775), Size = UDim2.fromScale(0.86, 0.3),
		BackgroundTransparency = 1, Image = SPOT, ZIndex = (root.ZIndex or 1) + 1, Parent = root,
	})
	local vp = UI.mk("ViewportFrame", {
		Name = "View", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = (root.ZIndex or 1) + 1, Parent = root,
	})
	lights(vp)
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local cam = Instance.new("Camera")
	-- framed so the tyre's tread lands on the floor shadow (77% down the well)
	cam.FieldOfView = 30
	local CAM_SHOW = CFrame.lookAt(Vector3.new(0, 4.2, 22), Vector3.new(0, 3.1, 0))
	-- the sticker view: straight onto the sidewall, the hub in the middle, as close as the frame's
	-- shape lets the whole wheel fit (worked out when the view opens, for the size it's opening to)
	local function camEdit(aspect: number): CFrame
		local t = math.tan(math.rad(cam.FieldOfView / 2))
		local dist = (D / 2) * 1.12 / (t * math.min(1, aspect))
		return CFrame.lookAt(Vector3.new(0, D / 2, dist), Vector3.new(0, D / 2, 0))
	end
	cam.CFrame = CAM_SHOW
	cam.Parent = vp
	vp.CurrentCamera = cam
	-- a tyre not found yet: a coloured backlight behind it and a fog over its foot
	local backlight = UI.mk("ImageLabel", {
		Name = "Backlight", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.85, 0.75),
		BackgroundTransparency = 1, Image = Kit.Art.glow, ImageColor3 = Color3.new(1, 1, 1), ImageTransparency = 0.3, Visible = false,
		ZIndex = (root.ZIndex or 1) + 1, Parent = root,
	})
	local fog = UI.mk("ImageLabel", {
		Name = "Fog", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.95, 0.85),
		BackgroundTransparency = 1, Image = Kit.Art.glow, ImageColor3 = Color3.fromRGB(205, 212, 228), ImageTransparency = 0.35, Visible = false,
		ZIndex = (root.ZIndex or 1) + 3, Parent = root,
	})
	UI.mk("UIGradient", {
		Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.55, 0.45), NumberSequenceKeypoint.new(1, 0.1) }), Parent = fog,
	})
	local model: Model? = nil
	local yaw = THUMB_YAW
	local turning = true
	local editing = false
	local held = 0      -- a drag turned it by hand: the slow turn waits this long to pick up again
	local conn = RunService.RenderStepped:Connect(function(dt)
		held = math.max(0, held - dt)
		if model and turning and held <= 0 and root.Visible then
			yaw += dt * 0.55
			TyreShow.pose(model, yaw)
		end
	end)
	local api = {}
	api.root = root
	function api.set(tyreId: string?, known: boolean?)
		if model then model:Destroy() end
		model = TyreLook.model(tyreId, D, "Shown")
		if known == false then
			-- not found yet: the tyre as a ghost in the bay, faint and misted over
			for _, d in ipairs((model :: Model):GetDescendants()) do
				if d:IsA("BasePart") then d.Transparency = math.max(d.Transparency, 0.5) end
			end
		end
		backlight.Visible = known == false
		fog.Visible = known == false
		;(model :: Model).Parent = world
		TyreShow.pose(model :: Model, if editing then 0 else yaw)
	end
	function api.setTurning(on: boolean) turning = on end
	-- turned by hand (a drag across the bay): pixels across become a turn, and it holds there a moment
	function api.spin(dx: number)
		if editing or not model then return end
		yaw += dx * 0.012
		held = 1.6
		TyreShow.pose(model, yaw)
	end
	-- the sticker view: the tyre stops, turns its face to you and the camera closes in on it. `aspect`
	-- is the width over the height of the frame it will have (it may be growing as this starts)
	function api.setEdit(on: boolean, aspect: number?)
		if on == editing then return end
		editing = on
		turning = not on
		spot.Visible = not on
		if on then
			yaw = 0
			if model then TyreShow.pose(model, 0) end
		end
		local size = root.AbsoluteSize
		local CAM_EDIT = camEdit(aspect or (if size.Y > 0 then size.X / size.Y else 1))
		local cv = Instance.new("CFrameValue")
		cv.Value = cam.CFrame
		cv.Changed:Connect(function(v) cam.CFrame = v end)
		local tw = game:GetService("TweenService"):Create(cv, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Value = if on then CAM_EDIT else CAM_SHOW })
		tw.Completed:Connect(function() cv:Destroy() end)
		tw:Play()
	end
	function api.isEditing(): boolean return editing end
	-- the bay's camera (the Workbench projects the stickers through it to find them on screen)
	function api.camera(): Camera return cam end
	-- the tyre standing in the bay now (the Workbench lays stickers on it)
	function api.model(): Model? return model end
	function api.setRarity(c: Color3, back: Color3?)
		rarity.Color = c
		backlight.ImageColor3 = back or c
	end
	function api.destroy()
		conn:Disconnect()
		root:Destroy()
	end
	root.Destroying:Connect(function() conn:Disconnect() end)
	-- the well, shadow and view keep their order above whatever ZIndex the root is given
	local base: { [GuiObject]: number } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") then base[d] = d.ZIndex - root.ZIndex end
	end
	root:GetPropertyChangedSignal("ZIndex"):Connect(function()
		for d, off in pairs(base) do d.ZIndex = root.ZIndex + off end
	end)
	return api
end

-- a thumb's model is built (scaled, stickers laid) once per tyre and cloned after that: a clone is
-- far cheaper than building and scaling it again for every card
local thumbCache: { [string]: Model } = {}
local function thumbModel(tyreId: string): Model
	local tpl = thumbCache[tyreId]
	if not tpl or tpl.Parent ~= nil then
		tpl = TyreLook.model(tyreId, D, "Thumb")
		thumbCache[tyreId] = tpl
	end
	return tpl:Clone()
end

-- every tyre's studio render (art/blender/icon_studio.py tyre_<id>): grids show these pictures,
-- which cost nothing to draw; a tyre without one falls back to a live 3D view
TyreShow.Icons = {
	baldspare = "rbxassetid://136498267595316",
	balloon = "rbxassetid://71290514512823",
	beadlock = "rbxassetid://120183719021150",
	cartwheel = "rbxassetid://93723252883476",
	donut = "rbxassetid://120161526403521",
	drill = "rbxassetid://92301601688586",
	dumper = "rbxassetid://125832722307604",
	gyro = "rbxassetid://102594471111874",
	hubcap = "rbxassetid://127933641180269",
	monster = "rbxassetid://132599889547439",
	orbital = "rbxassetid://113140551734132",
	original = "rbxassetid://118681656843198",
	paddle = "rbxassetid://97577214358586",
	scarab = "rbxassetid://115826208263269",
	slick = "rbxassetid://87605540069066",
	spinner = "rbxassetid://138523306390721",
	splitfive = "rbxassetid://134602378066147",
	square = "rbxassetid://94015933704812",
	steelie = "rbxassetid://119594875115996",
	tractorlug = "rbxassetid://84303211371613",
	turbofan = "rbxassetid://76666931173494",
	wheelbarrow = "rbxassetid://118105516246395",
	whitewall = "rbxassetid://88149881920511",
} :: { [string]: string }

function TyreShow.thumb(parent: Instance, tyreId: string, known: boolean, size: UDim2, pos: UDim2): (GuiObject, Model?)
	local icon = TyreShow.Icons[tyreId]
	if icon then
		-- found: the render as it is; not found yet: its dark silhouette
		local img = UI.mk("ImageLabel", {
			Name = "Thumb", AnchorPoint = Vector2.new(0.5, 0), Position = pos, Size = size, BackgroundTransparency = 1,
			Image = icon, ScaleType = Enum.ScaleType.Fit,
			ImageColor3 = if known then Color3.new(1, 1, 1) else Color3.fromRGB(26, 28, 36),
			ImageTransparency = if known then 0 else 0.1, ZIndex = 8, Parent = parent,
		})
		return img, nil
	end
	local vp = UI.mk("ViewportFrame", {
		Name = "Thumb", AnchorPoint = Vector2.new(0.5, 0), Position = pos, Size = size, BackgroundTransparency = 1,
		ImageColor3 = if known then Color3.new(1, 1, 1) else Color3.fromRGB(150, 158, 178),
		ImageTransparency = if known then 0 else 0.45, ZIndex = 8, Parent = parent,
	})
	lights(vp)
	local m = thumbModel(tyreId)
	m.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 4.6, 15.5), Vector3.new(0, 3.0, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	TyreShow.pose(m, THUMB_YAW)
	return vp, m
end

TyreShow.THUMB_YAW = THUMB_YAW

return TyreShow
