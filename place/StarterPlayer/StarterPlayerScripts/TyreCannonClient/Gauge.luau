--!strict
-- TYRE CANNON :: Gauge
-- The segment gauge both dials share (art/ui/hud_gauges.py): a round housing image with 30 unlit
-- slanted segments painted on, and one lit segment image placed over each, turned to its angle.
-- The lit ones are the needle: a gauge lights from the first segment up to a fraction.
--   Gauge.new(parent, diameter, face, z) -> gauge     face "speedo" | "revs"
--   gauge:set(frac, colourOf)    light segments up to frac (0..1); colourOf(i, N) -> Color3
--   gauge.root / gauge.housing / gauge.segs
-- Geometry matches the art: image 1024 square, centre 512, segment centres at radius 388,
-- segment i centred at A0 + (i + 0.5) / N * SWEEP degrees (0 = up, clockwise).

local UI = require(script.Parent.UI)

local Gauge = {}
Gauge.__index = Gauge

Gauge.Art = {
	speedo = "rbxassetid://110520778133358",
	revs = "rbxassetid://120593864890287",
	seg = "rbxassetid://116559574450603",
	lamp = "rbxassetid://116138971105257",
	pip = "rbxassetid://114023012440982",
}
Gauge.N = 30
Gauge.A0, Gauge.SWEEP = -120, 240
local SEG_R, SEG_IMG, ART = 388, 165, 1024

-- where the art puts things, as fractions of the housing (the readout plate's middle, its size)
Gauge.Plate = { y = 0.568, w = 0.30, h = 0.118 }

function Gauge.angle(i: number): number
	return Gauge.A0 + (i + 0.5) * Gauge.SWEEP / Gauge.N
end

function Gauge.new(parent: Instance, diameter: number, face: string, z: number?)
	local self = setmetatable({}, Gauge)
	local zz = z or 2
	local f = diameter / ART
	self.d = diameter
	self.root = UI.mk("Frame", {
		Name = "Gauge", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(diameter, diameter),
		BackgroundTransparency = 1, Parent = parent,
	})
	self.housing = UI.mk("ImageLabel", {
		Name = "Housing", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Image = Gauge.Art[face] or Gauge.Art.speedo, ZIndex = zz, Parent = self.root,
	})
	self.segs = {}
	for i = 0, Gauge.N - 1 do
		local a = math.rad(Gauge.angle(i))
		local s = UI.mk("ImageLabel", {
			Name = "Seg" .. i, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.sin(a) * SEG_R / ART, 0.5 - math.cos(a) * SEG_R / ART),
			Size = UDim2.fromOffset(SEG_IMG * f, SEG_IMG * f), Rotation = Gauge.angle(i),
			BackgroundTransparency = 1, Image = Gauge.Art.seg, ImageTransparency = 1, ZIndex = zz + 1, Parent = self.root,
		})
		self.segs[i] = s
	end
	self.lit = -1
	return self
end

-- light segments 0 .. frac*N (the last one partly), each in colourOf(i)
function Gauge:set(frac: number, colourOf: (number, number) -> Color3)
	local n = math.clamp(frac, 0, 1) * Gauge.N
	for i = 0, Gauge.N - 1 do
		local on = math.clamp(n - i, 0, 1)
		local s = self.segs[i]
		s.ImageTransparency = 1 - on
		if on > 0 then s.ImageColor3 = colourOf(i, Gauge.N) end
	end
end

-- the speedo's colour run: green, yellow, orange, red into the redline
local RAMP = {
	{ 0, Color3.fromRGB(70, 230, 110) }, { 0.5, Color3.fromRGB(255, 214, 50) },
	{ 0.8, Color3.fromRGB(255, 128, 30) }, { 1, Color3.fromRGB(245, 50, 50) },
}
function Gauge.ramp(i: number, n: number): Color3
	local t = i / math.max(1, n - 1)
	for k = 1, #RAMP - 1 do
		local a, b = RAMP[k], RAMP[k + 1]
		if t <= b[1] then return a[2]:Lerp(b[2], (t - a[1]) / (b[1] - a[1])) end
	end
	return RAMP[#RAMP][2]
end

return Gauge
