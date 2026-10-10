--!strict
-- TYRE CANNON :: VFX
-- Fires the effects picked into ReplicatedStorage.TyreCannon.Assets.VFX.
--   VFX.emit(name, cframe, opts)      one-shot burst, cleans itself up
--   VFX.attach(name, part, offset)     emitters riding a part, you switch them
-- opts: scale, color, count (fallback when an emitter has no EmitCount),
--       countMult, parent, keepBeams

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Assets = ReplicatedStorage:WaitForChild("TyreCannon"):WaitForChild("Assets")
local Prefs = require(script.Parent.Prefs)

-- the Particles setting: every burst and every attached emitter scales by it
local function density(): number
	return math.clamp(tonumber(Prefs.get("particles")) or 1, 0.2, 1)
end

local VFX = {}

local function folder(): Instance?
	return Assets:FindFirstChild("VFX")
end

local function scaleSeq(seq: NumberSequence, s: number): NumberSequence
	local keys = {}
	for _, k in ipairs(seq.Keypoints) do
		table.insert(keys, NumberSequenceKeypoint.new(k.Time, k.Value * s, k.Envelope * s))
	end
	return NumberSequence.new(keys)
end

function VFX.scaleEmitter(e: ParticleEmitter, s: number)
	if math.abs(s - 1) < 1e-3 then return end
	e.Size = scaleSeq(e.Size, s)
	e.Speed = NumberRange.new(e.Speed.Min * s, e.Speed.Max * s)
	e.Acceleration *= s
end

local function emittersOf(inst: Instance): { ParticleEmitter }
	local list = {}
	if inst:IsA("ParticleEmitter") then table.insert(list, inst) end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("ParticleEmitter") then table.insert(list, d) end
	end
	return list
end

local function hide(inst: Instance)
	local parts = inst:GetDescendants()
	table.insert(parts, inst)
	for _, p in ipairs(parts) do
		if p:IsA("BasePart") then
			p.Transparency = 1
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
		elseif p:IsA("Decal") then
			p.Transparency = 1
		end
	end
end

VFX.density = density

function VFX.has(name: string): boolean
	local f = folder()
	return f ~= nil and f:FindFirstChild(name) ~= nil
end

function VFX.emit(name: string, cf: CFrame, opts: { [string]: any }?): Instance?
	local o = opts or {}
	local f = folder()
	local tpl = f and f:FindFirstChild(name)
	if not tpl then return nil end
	local inst = tpl:Clone()
	hide(inst)
	if inst:IsA("BasePart") then
		inst.CFrame = cf
	elseif inst:IsA("Model") then
		inst:PivotTo(cf)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("Beam") and not o.keepBeams then d.Enabled = false end
		if d:IsA("Sound") then d:Destroy() end
		if d:IsA("Light") then d.Enabled = false end
	end
	local list = emittersOf(inst)
	local longest = 0
	for _, e in ipairs(list) do
		if o.scale then VFX.scaleEmitter(e, o.scale) end
		if o.color then e.Color = ColorSequence.new(o.color) end
		e.Enabled = false
		longest = math.max(longest, e.Lifetime.Max)
	end
	inst.Parent = o.parent or workspace
	for _, e in ipairs(list) do
		local n = tonumber(e:GetAttribute("EmitCount")) or o.count or 8
		e:Emit(math.max(1, math.floor(n * (o.countMult or 1) * density())))
	end
	Debris:AddItem(inst, longest + 0.6)
	return inst
end

-- emitters moved onto an Attachment on `part`; nothing emits until set() is called
function VFX.attach(name: string, part: BasePart, offset: CFrame?, scale: number?)
	local f = folder()
	local tpl = f and f:FindFirstChild(name)
	if not tpl then return nil end
	local inst = tpl:Clone()
	local att = Instance.new("Attachment")
	att.Name = "VFX_" .. name
	att.CFrame = offset or CFrame.new()
	att.Parent = part
	local handle = { attachment = att, emitters = {}, rates = {} }
	for _, e in ipairs(emittersOf(inst)) do
		if scale then VFX.scaleEmitter(e, scale) end
		e.Enabled = false
		e.Parent = att
		table.insert(handle.emitters, e)
		handle.rates[e] = e.Rate
	end
	inst:Destroy()
	function handle.set(on: boolean, rateMult: number?)
		for _, e in ipairs(handle.emitters) do
			e.Enabled = on
			e.Rate = handle.rates[e] * (rateMult or 1) * density()
		end
	end
	function handle.burst(mult: number?)
		for _, e in ipairs(handle.emitters) do
			e:Emit(math.max(1, math.floor((tonumber(e:GetAttribute("EmitCount")) or 8) * (mult or 1) * density())))
		end
	end
	function handle.destroy()
		att:Destroy()
	end
	return handle
end

return VFX
