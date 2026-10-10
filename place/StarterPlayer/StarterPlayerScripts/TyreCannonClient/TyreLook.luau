--!strict
-- TYRE CANNON :: TyreLook
-- The model for one of the 43 collectable tyres: its Blender model once imported
-- (Assets/Tyres/Tyre_<id>, art/blender/tyres3.py), the stock wheel until then. Every tyre is built
-- 8 studs across with its axle along Z and the wheel centre 4 studs up, so the returned model's
-- pivot is the wheel centre and it rolls about its Z axis, the same as the stock wheel.
--   TyreLook.model(tyreId, diameter, name?, design?) -> Model (unparented); a design's stickers are laid on it

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
		if design and design.stickers then TyreSticker.apply(m, design.stickers) end
		return m
	end
	return WheelAssembly.build(nil, { diameter = diameter, skin = "stock", rim = "steel", detail = "high", name = name or "Tyre" })
end

return TyreLook
