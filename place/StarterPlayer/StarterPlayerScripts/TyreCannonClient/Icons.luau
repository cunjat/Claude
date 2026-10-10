--!strict
-- TYRE CANNON :: Icons
-- The run's own art: the gauge cluster, the pickup token and one glyph per kind of quirk.
-- Glyphs are white with an ink outline, so tint them with ImageColor3.

local Icons = {}

Icons.Hud = {
	dial = "rbxassetid://77349651075252",
	needle = "rbxassetid://140326309905820",
	segment = "rbxassetid://134316744917889",
	shadow = "rbxassetid://105910446149468",
	rail = "rbxassetid://99333372453008",
	tokenFace = "rbxassetid://118475015894275",
	tokenRing = "rbxassetid://116562591057487",
	marker = "rbxassetid://94120057655516",
}

Icons.Glyph = {
	speed = "rbxassetid://109942342891363",
	float = "rbxassetid://107807547074831",
	slick = "rbxassetid://100943218984366",
	up = "rbxassetid://138704755414641",
	coin = "rbxassetid://135223617606758",
	fuel = "rbxassetid://78974414287000",
	spring = "rbxassetid://127404419148793",
	magnet = "rbxassetid://123520501961664",
	wind = "rbxassetid://110545077337539",
	grip = "rbxassetid://123130438696882",
	ghost = "rbxassetid://113879453172285",
}

-- full-colour pickups (icon studio renders): the cash coin, and the three metals as hex nuts
Icons.Coin = {
	credits = "rbxassetid://96897963261358",
	bronze = "rbxassetid://123262345242723",
	silver = "rbxassetid://101063235276625",
	gold = "rbxassetid://110896553272051",
}

-- the loading screen and the receipt
Icons.Load = {
	bg = "rbxassetid://116966973907989",
	tyre = "rbxassetid://80540030931238",
	chequer = "rbxassetid://129387745864115",
}
Icons.Receipt = {
	teeth = "rbxassetid://78026225752254",
	-- drawn at twice its on-screen size (444 x 36): shown stretched, never sliced
	printer = "rbxassetid://140583452719323",
}

-- particle textures. A ParticleEmitter with no Texture falls back to Roblox's star sparkle,
-- which this game doesn't use: give every emitter one of these.
Icons.Particle = {
	dot = "rbxassetid://84291297587243",
	streak = "rbxassetid://93678208400920",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

-- what each quirk mostly does, by the glyph that says it
Icons.PerkGlyph = {
	nitro_roll = "speed", feather_weight = "float", slick_tread = "slick", air_kick = "up",
	credit_chip = "coin", second_wind = "fuel", fuel_tap = "fuel",
	steel_belt = "spring", magnet_coil = "magnet", bounce_master = "spring", tailwind = "wind",
	spin_cycle = "coin", momentum_bank = "speed", grip_wax = "grip",
	ghost_tyre = "ghost", rocket_retread = "speed", double_credits = "coin", skyhook = "up", shockwave = "speed",
	overdrive = "speed", perpetual_motion = "slick", golden_rim = "coin",
	cannonball = "speed", big_bang = "up",
}

function Icons.forPerk(perk): string
	local id = perk and perk.id or ""
	return Icons.Glyph[Icons.PerkGlyph[id] or "speed"]
end

function Icons.all(): { string }
	local list = {}
	for _, id in pairs(Icons.Hud) do table.insert(list, id) end
	for _, id in pairs(Icons.Glyph) do table.insert(list, id) end
	for _, group in ipairs({ Icons.Particle, Icons.Coin, Icons.Load, Icons.Receipt }) do
		for _, id in pairs(group) do table.insert(list, id) end
	end
	return list
end

return Icons
