--!strict
-- TYRE CANNON :: DoorArt
-- Your garage door, drawn the same way everywhere it shows up: the workbench
-- shutter, the door preview on the rack, your yard's door and the loading screen.
--   DoorArt.paint(container, opts)
-- opts: paint (DoorPaints id), stencil (DoorStencils id), stickers ({ id } list),
--       number (yard number), name (rig name), seed (sticker scatter), image (bool:
--       draw the door picture itself), stickerScale (1 = full screen size)
-- Everything is sized in scale, so the same call works on a 2D frame or a SurfaceGui.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("TyreCannon")
local Config = require(Root:WaitForChild("Modules"):WaitForChild("Config"))

local DoorArt = {}

local STENCIL_INK = Color3.fromRGB(236, 232, 222)
local HAZARD_YELLOW = Color3.fromRGB(242, 190, 40)
local HAZARD_BLACK = Color3.fromRGB(22, 22, 24)
local RED = Color3.fromRGB(214, 34, 44)

local function mk(class: string, props: { [string]: any }): any
	local o = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then (o :: any)[k] = v end
	end
	o.Parent = props.Parent
	return o
end

local STENCIL_FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

-- stencilled letters: sprayed ink with a soft, uneven edge
local function stencilText(parent: Instance, text: string, pos: UDim2, size: UDim2, z: number)
	local l = mk("TextLabel", {
		Name = "Stencil", AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = size, BackgroundTransparency = 1,
		Text = text, FontFace = STENCIL_FONT, TextScaled = true, TextColor3 = STENCIL_INK, TextTransparency = 0.12,
		ZIndex = z, Parent = parent,
	})
	mk("UIGradient", {
		Rotation = 8,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.3, 0.05),
			NumberSequenceKeypoint.new(0.62, 0.2), NumberSequenceKeypoint.new(1, 0.08),
		}),
		Parent = l,
	})
	return l
end

function DoorArt.clear(container: Instance)
	for _, c in ipairs(container:GetChildren()) do
		if c:GetAttribute("DoorArt") then c:Destroy() end
	end
end

function DoorArt.paint(container: GuiObject, opts: { [string]: any })
	DoorArt.clear(container)
	local z = (opts.zIndex or container.ZIndex) + 1
	local layer = mk("Frame", {
		Name = "DoorArt", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = z, Parent = container,
	})
	layer:SetAttribute("DoorArt", true)

	local paint = Config.DoorPaintsById[opts.paint or "steel"] or Config.DoorPaints[1]
	if opts.image ~= false then
		local img = (Config.Workshop and Config.Workshop.DoorImage) or ""
		if img ~= "" then
			mk("ImageLabel", {
				Name = "Door", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = img,
				ScaleType = Enum.ScaleType.Crop, ImageColor3 = paint.tint, ZIndex = z, Parent = layer,
			})
		else
			mk("Frame", { Name = "Door", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 122, 126):Lerp(paint.tint, 0.5), BorderSizePixel = 0, ZIndex = z, Parent = layer })
		end
	end

	-- the stencil
	local st = opts.stencil or "none"
	if st == "number" then
		stencilText(layer, ("%02d"):format(math.clamp(tonumber(opts.number) or 0, 0, 99)), UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.5, 0.42), z + 1)
	elseif st == "name" then
		local name = tostring(opts.name or "")
		if name == "" then name = "NO NAME YET" end
		stencilText(layer, string.upper(name), UDim2.fromScale(0.5, 0.45), UDim2.fromScale(0.82, 0.2), z + 1)
	elseif st == "stripe" then
		for i, spec in ipairs({ { y = 0.47, h = 0.13, c = RED }, { y = 0.565, h = 0.028, c = STENCIL_INK } }) do
			local band = mk("Frame", {
				Name = "Stripe" .. i, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, spec.y), Size = UDim2.fromScale(1, spec.h),
				BackgroundColor3 = spec.c, BackgroundTransparency = 0.08, BorderSizePixel = 0, ZIndex = z + 1, Parent = layer,
			})
			mk("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.4, 0), NumberSequenceKeypoint.new(0.75, 0.15), NumberSequenceKeypoint.new(1, 0.35),
				}),
				Parent = band,
			})
		end
	elseif st == "hazard" then
		-- a CanvasGroup, because rotated stripes ignore ClipsDescendants
		local band = mk("CanvasGroup", {
			Name = "Hazard", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 0.97), Size = UDim2.fromScale(1, 0.14),
			BackgroundColor3 = HAZARD_YELLOW, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = z + 1, Parent = layer,
		})
		for i = -2, 26 do
			mk("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(i / 22, 0.5), Size = UDim2.new(0.022, 0, 3, 0),
				Rotation = 35, BackgroundColor3 = HAZARD_BLACK, BorderSizePixel = 0, ZIndex = z + 2, Parent = band,
			})
		end
		mk("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.15) }),
			Parent = band,
		})
	end

	-- stickers, slapped on at a slight angle; the seed keeps them in the same places
	local cat = opts.catalogue
	local stickers = opts.stickers or {}
	if cat and #stickers > 0 then
		local ids, seen = {}, {}
		for _, s in ipairs(stickers) do
			local id = type(s) == "table" and s.id or s
			if cat.byId[id] and not seen[id] then
				seen[id] = true
				table.insert(ids, id)
			end
		end
		local max = (Config.Workshop and Config.Workshop.DoorStickers) or 7
		local n = math.min(#ids, max)
		local rng = Random.new(tonumber(opts.seed) or 7)
		local k = opts.stickerScale or 1
		for i = 1, n do
			local e = cat.byId[ids[i]]
			local col = (i - 0.5) / n
			local size = rng:NextNumber(0.12, 0.18) * k
			local img = mk("ImageLabel", {
				Name = "Sticker", AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(math.clamp(col + rng:NextNumber(-0.3, 0.3) / n, 0.06, 0.94), rng:NextNumber(0.18, 0.78)),
				Size = UDim2.fromScale(size, size), Rotation = rng:NextNumber(-18, 18),
				BackgroundTransparency = 1, Image = e.texture, ScaleType = Enum.ScaleType.Fit, ZIndex = z + 3, Parent = layer,
			})
			mk("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = img })
		end
	end
	return layer
end

return DoorArt
