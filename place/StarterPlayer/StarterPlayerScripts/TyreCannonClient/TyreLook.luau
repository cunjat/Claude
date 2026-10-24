--!strict
-- TYRE CANNON :: TyreLook
-- The model for one of the 43 collectable tyres: its Blender model once imported
-- (Assets/Tyres/Tyre_<id>, art/blender/tyres3.py), the stock wheel until then. Every tyre is built
-- 8 studs across with its axle along Z and the wheel centre 4 studs up, so the returned model's
-- pivot is the wheel centre and it rolls about its Z axis, the same as the stock wheel.
--   TyreLook.model(tyreId, diameter, name?, design?) -> Model (unparented), dressed in the design
--   TyreLook.dress(model, design?)   a design on a built tyre: its paint and its stickers
--   TyreLook.paint(model, color?)    the paint alone (nil: the tyre's own colours)
-- The paint is a tint through the tyre's SurfaceAppearance (TintMask): it multiplies the baked
-- texture, so black rubber stays black while the rims, whitewalls and chrome take the colour.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WheelAssembly = require(ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Modules"):WaitForChild("WheelAssembly"))
local Models = require(script.Parent:WaitForChild("Models"))
local TyreSticker = require(script.Parent:WaitForChild("TyreSticker"))

local TyreLook = {}

local BUILT = 8 -- studs across, as built

function TyreLook.has(tyreId: string?): boolean
	return tyreId ~= nil and Models.get("Tyres/Tyre_" .. tyreId) ~= nil
end

function TyreLook.model(tyreId: string?, diameter: number, name: string?, design: any?): Model
	local tpl = tyreId and Models.get("Tyres/Tyre_" .. tyreId)
	if tpl then
		local s = diameter / BUILT
		local m = Models.place(tpl, nil :: any, CFrame.new(), s)
		Models.turn(m, CFrame.new(0, BUILT / 2 * s, 0))
		m.Name = name or m.Name
		m.Parent = nil
		if design then TyreLook.dress(m, design) end
		return m
	end
	local m = WheelAssembly.build(nil, { diameter = diameter, skin = "stock", rim = "steel", detail = "high", name = name or "Tyre" })
	if design then TyreLook.dress(m, design) end
	return m
end

function TyreLook.paint(model: Model, color: Color3?)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("SurfaceAppearance") and not (d.Parent and d.Parent.Name == "Sticker") then
			-- (only touched while painted: its own alpha mode and colour come back unpainted, and a
			-- surface with cut-outs (Transparency) keeps them: it's only tinted)
			if color then
				if d:GetAttribute("BaseAlphaMode") == nil then
					d:SetAttribute("BaseAlphaMode", d.AlphaMode.Name)
					d:SetAttribute("BaseColor", d.Color)
				end
				if d.AlphaMode ~= Enum.AlphaMode.Transparency then
					pcall(function() d.AlphaMode = Enum.AlphaMode.TintMask end)
				end
				pcall(function() d.Color = color end)
			elseif d:GetAttribute("BaseAlphaMode") ~= nil then
				pcall(function() d.AlphaMode = (Enum.AlphaMode :: any)[d:GetAttribute("BaseAlphaMode")] end)
				local base = d:GetAttribute("BaseColor")
				pcall(function() d.Color = if typeof(base) == "Color3" then base else Color3.new(1, 1, 1) end)
				d:SetAttribute("BaseAlphaMode", nil)
				d:SetAttribute("BaseColor", nil)
			end
		end
	end
end

function TyreLook.dress(model: Model, design: any?)
	local d = if type(design) == "table" then design else {}
	local paint = type(d.paint) == "table" and TyreSticker.color(d.paint.RimPrimary) or nil
	TyreLook.paint(model, paint)
	TyreSticker.apply(model, d.stickers)
end

return TyreLook
