--[[
TYRE CANNON :: README
A map of the code for whoever picks this up. Nothing requires this module; it's notes.

WHERE THINGS LIVE
  ReplicatedStorage.TyreCannon
    Modules.Config        every number and list in the game: physics, heat, tracks, quirks, shop,
                          garage trophies, launch timing. Change balance here first.
    Modules.TrackGen      the endless road: heights, ramps, obstacles, pickups, all from a seed
    Modules.WheelAssembly builds a tyre model (skin, rim, stickers) for any screen
    Assets                models the code clones: Workshop (toolboxes, shelves), Garage (door,
                          trophy, frame, corkboard, stamp, tarp, stop sign, medal), World (decor,
                          obstacles, props), Props, VFX
  ServerScriptService.TyreCannonServer
    Profile               the save: defaults and the sanitiser. New saved fields go in both.
    Runs                  BeginRun and SubmitRun: payouts, records, ghosts, photos
    Economy, Garage, Debug
  StarterPlayer.StarterPlayerScripts.TyreCannonClient
    Main                  the state machine: yard, launch, run, receipt, workbench, garage
    RunSim                the run itself: a hand-rolled sim, the chase camera, the ghost, tyre
                          tracks, hit-stop, draft slow-mo
    WorldView             everything you see on the road: land, hills, ramps, milestones, gates,
                          quirk tokens, toolboxes, the best-run line
    HudUI                 the run HUD: dial, lamps, gate rail, quirk chips, draft cards, callouts
    HubUI, MenuUI         yard menus, the credits plate, the receipt (RUN IT BACK lives here)
    LaunchUI, LaunchShow  the two timed presses and the rig/camera that acts them out
    Workshop (+children)  the workbench: stations, forge (Retread), stickers, parts wall
    Garage                the garage room: fixed camera shots, trophies, photos, guestbook
    Icons                 every run-art image id (dial, needle, lamps, rail, token, quirk glyphs)
    PackFX                particle presets from the VFX packs (boost flame, smoke, dust)
    Sound                 the licensed sound bank, by name
    RunPhoto              rebuilds a run's best jump as a still for the garage and career

HOW TO
  Swap a sound            Sound.Bank in TyreCannonClient.Sound: change the id there. Keep sound
                          effects cut to the action and short (see Workshop:doorSound for how
                          the door clip is trimmed to the animation).
  Swap an icon            Icons.Glyph / Icons.Hud. Glyphs are white with an ink outline; the code
                          tints them. Icons.PerkGlyph says which glyph each quirk uses.
  Add a quirk             Config.Perks, then give it a glyph in Icons.PerkGlyph.
  Change a road's look    Config.Tracks (sun time, fog colours) and LANDS in WorldView (field
                          colours, hills, road markings).
  Debug menu              press the build tag (bottom-right) or backquote, type the code, UNLOCK.
                          RUN tab: LAUNCH (AUTO), START AT CP n. GAME tab: GARAGE DEMO DATA.

RULES THE GAME KEEPS (from the owner's feedback)
  No music. No coloured glows, tint pulses, light rays or sparkle bursts: particles and models.
  No decor props in the lobby: that's for the builder. Builder Sans on screen.
  Menus fade fully out before the next fades in. Cameras never clip, whip or flip.
  Everything preloads before it's shown.
]]

return {}

-- Scripts are edited in the Rojo project at Documents/TyreCannon (src/), not in Studio.
