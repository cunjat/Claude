-- TYRE CANNON :: DevNotes  (shared work log for everyone editing this place, people and AIs)
-- Two people (and their Claude sessions) edit this place at the same time through Team Create.
-- RULES
--   1. Before you change a script, read the CLAIMS below. If someone has claimed it, don't edit it;
--      talk to them first.
--   2. Before you start, add a line under CLAIMS: date, who, the scripts/objects you will touch, what for.
--   3. When you finish, move your line to DONE (with a one-line summary) so the other side knows what changed.
--   4. Small, targeted edits only; never rewrite a whole script someone else may be working in.
--   5. Never move or delete Workspace objects (the map is built from them).

local CLAIMS = [[
]]

local DONE = [[
2026-10-24  owner's Claude (cloud session, from edit_yum.rbxl)  FINAL TINKER. Title LAUNCH A TIRE (TyreLoading, Config.GameName,
            Tutorial). BenchPose: no speech bubbles on the tyre-chat pose. LOADING: Preload waits only for THE INTERFACE + YOUR
            YARD (your plot, Stages/Cannons/Machines/Characters/Lobby/Props, World.Decor); Preload.background after TyreReady
            loads the road first, then tyres, sounds, Park/Nature/Vehicles/Prestige, then warms the road's models off-screen;
            Main's second full preload of every asset removed; Sound's bank preload waits for TyreReady; TyreLoading 2 stages,
            never READY before TyreReady; the interface wait gives up after 3 s without progress. WORKBENCH: tabs Tyres +
            Customization; tyre PAINT (SurfaceAppearance TintMask tint, original AlphaMode restored when cleared) and SMOKE
            colour (RunSim dust / tread smoke / landing dust); each sticker a colour tint (col) and repeat (repeatN copies
            round the wheel, StickerCopy attribute); Remove/Clear/Save on one row; server Design keeps smoke + col;
            TyreLook.dress/paint; the tyre in the cannon wears its design. Re-applied the 10-10 review fixes the place was
            missing (sticker outline in bay shares, no drag on the opening click, visible-side picking, one camera glide,
            sticker raycast copy cleanup, 4-col grid, one PERFECT per drop, tuck glow off in 1st person, cannon seat fixes,
            Kit.bob stops with its object, skill-zone band/updraft follow terrain). RUN: WorldView far ring (22 pieces a side
            1850-2700 out: Backroad tree stands, Dunes ridges; wrap forward, rebuilt per zone). HUB: rock pigeon from
            TC_HubProps (Park/Pigeon RockPigeon, or built from the import), on its feet, not darkened; a flock on the plaza's
            rangoli ring. tools/file_assets.luau files the pigeon. GOALS: Stage Trials harder (targets up, 8%/prestige,
            misses ease 4% to 75%; a trial saved before never gets harder). SYSTEMS CHECK: YardEdit (prestige refits the
            layout to stage 1 via Game.yardFit, server + on join; machines go red on decor; held piece follows the pointer
            while the view drifts; footprint clamped to the floor; panels Active; one touch moves things; one save at a
            time; turns never spin the long way; Z / Ctrl+Z undo, 40 steps). Workbench (swatches fit, outline follows the
            grabbed copy, fused-away tyre falls back to launch, paint keeps cut-outs and restores colour, NaN-safe Design,
            stickers capped at MaxPerTyre). Shift lock frees the mouse over any open panel.
2026-10-24  owner's Claude (session 6)  PRE-RELEASE FIXES + HUB PACK 6 FILED. Pack 6 (Import 3D "Scene") filed into
            Assets Park/Nature/Vehicles2 (old ones in ServerStorage.ArchivedAssets.Replaced_2026-10-24); LobbyTraffic LAMPS
            (heights over the axle); LobbyPark pigeon scale 1.15 + wing/tail hinges from the new parts, dog casts shadow.
            Loop: run guard (Begin 3 s throttle, no 120 m head start, <5 s or <100 m isn't a run), prestige resets v.rate,
            luck multiplies the Rare / Epic+ chance by what it says, skill-zone pay (zoneSmashes/zoneBonus), "best" daily
            from this climb. Game: AutoCannon MaxShare 0.75, PassShare 0.56, Mini-Turbo cooldown 5. Heats: key only if you
            beat someone. Profile: cash cap 1e15 on load. RunSim: Q/Select 0.6 s hold to bail, heading re-centres, roll-out
            (<15% top speed 2.5 s), 1st person hides the tyre at start, headwind cue, world:ensure(x, 1). RunPhysics: late
            tuck release costs like a cramp. TyreSkills: Mini-Turbo ground + cooldown, Sandevistan walks only the run world.
            TouchControls: BAIL/VIEW top row, BAIL is a hold, SKILL text fits. HudUI: phone layout (speed top right, chain
            left), new toasts; Studio attribute ForceTouch previews it. Receipt2: card sized and scaled to fit. LaunchTap:
            scored zone matches the painted gold. YardEdit: press twice to discard. HubExtras: Heat card waits for the gate.
            Main: rating card only at home. Kit: no hotkey badges on phones. Crates2 key odds match the server.
2026-10-24  owner's Claude (session 5)  HUB + PLOTS PASS (owner's screenshots). Config: owner's idle/walk/run (77998867839297,
            85424954949535, 73241663791009), UseRobloxAnimations=false; AnimController drops the ground set while seated. NOTE: all
            three ids return "not authorized" in Studio, so they fall back to R6 defaults until the owner's account owns or shares
            them with the experience. BenchPose: a real seated pose (thighs along the seat, hands on knees). LobbyPark: FlowerBed ->
            Roadside/RoadPlanter everywhere (put()), rose garden keeps only its planter, gap 4 pond stub + gap 7 garden T + the walk
            past the big pond's bridge removed, ring path rebuilt (360 slabs cut to chord, parity lift, kerbs per radius + end posts),
            textured pigeons tinted via SurfaceAppearance. LobbyDetail: no wear discs (z-fight/sand splotches), no shrub clusters.
            HubPark: island planter = RoadPlanter, no root shrubs. NEW Assets/Nature/Hedge + Bush (built from the trees' own leaf
            crowns). LobbyVista: chhatris on the open sand before the first dune row, scale 5 (dune collision rides ~50 over the
            crest). DayNight: the cycle is back (EveningHour only pins it when a number), keyframed grade (DayGrade CC, atmosphere,
            ambient, ColorShift_Top, bloom, sun rays); runs get the base light back. PlotStage: the place streams, so Floor/FloorTrim/
            old Fence are re-dressed whenever a part streams in (dress()); free yards sandstone pavers, every yard a sandstone kerb
            trim, old wooden posts/rails hidden. Plot2: old rig hidden as it streams in. LobbyTraffic: new driver (bicycle steering,
            IDM following, corridor look-ahead, ring right of way + give-way lines, suspension, steering front wheels).
            Art waiting on Import 3D: art/export/TC_HubPack6.glb (Park/Bin, Nature/Flowers*, GrassTuft*, Park/Pigeon, Park/Dog HD,
            Vehicles2/hatchback, taxi, lorry, tanker); filing script in the session, LAMPS for those kinds in TC_HubPack6-info.json.
2026-10-24  owner's Claude (session 4)  OWNER'S REVIEW 3+4. Plot2: every machine on every yard from level 0, unclaimed yards show
            the starter yard; claim pads/prompts hidden for good (auto-claim). LobbyPark: a viewing bay before each yard (fountains
            at yards 1 and 5, roadside centrepieces elsewhere, a bench either side), gap 3 rose garden, merry-go-round top on its base,
            hedge -> Nature/Hedge when imported. NEW BenchKit (Blender bench, sit by prompt or walking on) + NEW BenchPose (3 sitting
            poses in turn: lean back / thinker / talking to your own tyre; V2.BenchPose remote in Loop -> character attribute).
            HubLife: Blender birds that flap (pigeon grey). Config.UseRobloxAnimations=true (AnimController keeps Animate). No cows.
            DayNight: fixed evening 18:05, lamps on. LobbyVista: chhatris on the dune crests. Crates2: a locked crate shows its crate,
            tyres and Legendary as black silhouettes, names ???, no Test Drive (the fog and big ? are gone). Art waiting on import/
            upload: TC_Bushes + TC_BackroadTrees (leaf-carded Shrub/Hedge/Bush), icons Icon_Shop/Icon_Crates, Zone_* pictures.
            (2026-10-21 claim on Assets/Nature trees closed: replaced by the leaf-card trees, TC_HubNature.)
2026-10-23  owner's Claude (session 3)  LAUNCH WEEK. Blender Vehicles2 filed (old ones in ArchivedAssets.Vehicles2_gen_2026-10-23);
            traffic: each wheel rolls at its own radius, night lamps sit on the modelled lamps. Lobby skyline: no pylons
            (bare lattice towers), HIGHWAY stones milestone-sized, no THAR stones, khejri in groves, eucalyptus in stands;
            kites lower, strings hide when an end is behind the camera (they drew a stray line). Sounds: lobby music
            (APM "Bouncing", Sound.hubMusic, paused in runs), launch boom (Deep Impacts 7 + Boom Deep Distant), diesel engine.
            Run: controls hint on a dark card; tutorial focus whole-pixel (the seam line); run dim 0.45 -> 0.7; road-edge
            stones / delineators / stakes. New players start with $250 (first Cannon level after any first run); tutorial
            crate opens on Keys. Hub: TOMORROW card with the next daily and a countdown. Coin + Poplar remade in Blender
            (bundles TC_Coin, TC_BackroadTrees, waiting for Import 3D). tools/sort_import now archives what it replaces
            (ArchivedAssets.Replaced). Store art: build/promo (3 thumbnails, 2 icons).
            Later: Safeda remade (in TC_BackroadTrees); Dunes remade (Scenery/dunes/DuneRidge, bundle TC_Dunes2; LobbyVista
            uses it once imported, spheres until then); day/night: daylight 3/4 of the cycle; run tip dim 0.7; label v1.0.
            NOTE: the character animations belong to the owner's account / a group, not the place's owner, so they fall back
            to Roblox's defaults until shared with the experience.
2026-10-22  owner's Claude (session 2)  HUB REBUILT ON A PLAN: shared HubPlan + client HubPark (curved flush walks from forked
            plaza mouths into every yard's way in and through every gap to the park ring; bench bays, lamps, avenues set back,
            groves, verges; replaces PlotPaths' walkway and PlazaLife's gardens). Lost lug nuts (HubHunt server+client, v2.hunt
            in LoopData). Traffic v2 (LobbyTraffic: curves, per-kind pace, following, spinning wheels; Assets/Vehicles2).
            Halloween on one switch (DayNight.halloween). Opening: real-speed run, pop swaps, tight wind (WindFX opts.tight),
            menu titled TYRE CANNON on a new background. New assets: Props/Scarecrow, Gravestone, LugNut, Nature/TreeMango2,
            TreeApple (old ones in ServerStorage.ArchivedAssets). NOT DONE: R6 friend NPCs in LobbyPark.
2026-10-21  owner's Claude  SPECTATE REDONE (owner: "not working... has the old game design"). Spectator v2 watches the
            run the way the runner sees it: the run's own HudUI, RunCamera, light/haze/weather, tyre pose (yaw/pitch/bank),
            stamps and road reactions (coins, keys, smashes) streamed by RunSim:stream; WATCHING card, LEAVE, PREV/NEXT.
            Server: stop never throttled, relay gate 0.1 -> 0.06 s (was dropping ~10% of frames), `done` always relayed.
            Old Spectator kept in ServerStorage.ArchivedAssets.Spectator_v1_2026-10-21. Test it alone in Studio with
            SpecBot (see its header: workspace DebugBot="ok" + SpecBotRecord, one run, then SpecBot=true).
2026-10-21  owner's Claude  PARK OFF THE FOOTPATH (owner: flower areas overlapping the path). LobbyPark: fountain's near
            beds drawn in, big pond 0.85 and out to 511 (rim and bridge clear the kerb), playground pad 517, spurs stop at
            each piece's edge (gap 3 none: its plaza meets the path). LobbyDetail: wear discs 0.04 thick, so no dark rims.
            Checked by measuring every park piece against the path parts, then screenshots.
2026-10-21  owner's Claude  LOBBY RINGS OUT FOR STAGE-5 YARDS (owner: max-level yard ran over the park path). Stage-5 yards reach
            r 317 (the 10-18 shrink assumed 280). LobbyVista + LobbyTraffic S 0.6 -> 0.66 (canal 384 -> 422, road ring 502),
            LobbyDetail lawn 328-400, LobbyPark REMAP +38 (path ring 300 -> 338). Checked at stages 1-5 + reviewer agent.
2026-10-18  owner's Claude  PARK ART, TEXTURED (owner: "too low poly and not textured"). New PBR pieces (smooth meshes with
            SurfaceAppearance Color/Normal/Roughness, art/blender/tc_pbr.py, imported as TC_HDPack1/2.glb):
            Nature/TreeNeem, TreeMango, TreeGulmohar, TreeAshoka, TreeBanyan, Shrub; Park/Bench, Bin, Picnic, Hedge,
            FlowerBed, ParkLamp, Fountain, PondBig, PondSmall. NPCs on R6 (Park/Person: collar, placket, pocket,
            sleeves, belt, trainers, modelled face); LobbyPark tints them through SurfaceAppearance TintMask.
            Still low-poly: playground set, bridge, fish/ducks/kites/cricket, pigeons/dog, grass/flowers/rocks/reeds.
2026-10-18  owner's Claude  LOBBY 40% SMALLER (owner's call: the park pulled in, the yards and plaza unchanged). LobbyVista:
            every ring past the yards x0.6 (canal 640 -> 384, fields, Grand Trunk, scrub, dunes, caravan; widths and
            heights kept, terraces rise at the same height). LobbyTraffic: ring road 456, spokes to 1196. LobbyDetail:
            lawn 290-362. LobbyPark: layout kept in its design radii and mapped into the band by gp() (path ring 300,
            set pieces ~320-340), set pieces a size down, inward spurs and ashoka avenue removed, stall moved along.
2026-10-18  owner's Claude  FULL GAME REVIEW FIXES (report: Projects/personal-projects/tyre-cannon/review-2026-10-18.md).
            Loop: PERFECTs + chain no longer capped by retired bounce targets (PERFECTs stage trial was impossible);
            ranked/heats/trials/boards use the road a run covered (Start Here exploit); quest cash no double prestige.
            LoopData: MAX_SPARES 4 -> 7 (rack + pass slots were cut on rejoin). Game: Monsoon no longer blocks
            Chrome/Rainbow. TyreCannonServer: weekly board rolls over on long servers. Tutorial: `replay` field
            renamed `replaying` (finished players got the tutorial again every session); plates pick the side with
            room (Done, Upgrade); run plates up off the tyre; daily step ticks once claimed; CRATES plate clears ZONES.
            WorldView: verge decor added to chunks first built out of range. RunSim: V after the chat check.
            ShiftLock: Ctrl ignored while not allowed. Feedback: rating card bottom left. Receipt2: chain row label.
            Plot2: "Typical run". HubExtras: "N RUNS' CASH".
2026-10-18  owner's Claude  PARK PACK 3 filed (owner imported): new weeping ashoka (Assets/Nature/TreeAshoka), sandstone
            pond rims (Assets/Park/PondBig + PondSmall). Owner said "do what you think is right": Lobby.Ground.Land colour
            128,136,84 -> 94,128,64 (fresher green to match the low-poly trees; the original is saved in its
            OriginalColor attribute; note its TC_Dirt variant never applied: base Ground vs Grass). LobbyVista: canal
            poplars ~18% missing at random, spacing and heights varied (own Random, fields unchanged). LobbyPark: scatter
            and shrubs kept off the paved spurs (onPath).
2026-10-18  owner's Claude  PARK VISUAL PASS (reviewer vs Lodhi Garden + park design guides). LobbyPark: paths in from the
            plaza in every gap (kerbed, ring kerb opened at junctions), set pieces pulled ~25 studs in, lamps paired per
            gap (none in a line of fire), benches on paved pads facing the view, fountain x1.5 on a round paved plaza,
            chai stall beside the path (dog in its shade), banyan x1.6 with the picnic in its shade, playground sand
            kerbed + bigger swings + shade trees, canal tree belt in clumps, ashoka avenue lining the inward paths.
            LobbyDetail: worn patches only where people gather (lawn's own material), tufts/flowers normal size at
            edges, shrubs at tree bases, rocks at pond rims. Waiting on art/export/TC_ParkPack3.fbx (weeping ashoka,
            sandstone pond rims).
2026-10-18  owner's Claude  PARK PACK 2 imported (owner) and filed: 13 casual hairstyles into Assets/Park/Person (HairLong
            removed; turbans now ~2%), Assets/Park/Pigeon + Dog. Pigeon flocks (fountain, big pond, banyan) scatter when
            you walk up and land away from you; a dog sleeps by the chai stall, tail thumping faster as you come close.
2026-10-17  owner's Claude  LOBBY PARK ROUND 2 + REFINEMENT. LobbyPark: props solid (Physical + trunk/chabutra colliders;
            Assets/Park CollisionFidelity baked), standing people solid but moving ones (strollers, kids, cricket) not, so
            they never shove you; natural walk cycle; casual hairstyles (turbans rare); bubble-chat conversations incl. real
            players' bests/prestige, greetings, Chat prompt (E), cheers for whoever launches. Refinement: launches now
            heard (fixed: remotes are in Remotes.V2) -> spectators film, nearby groups look up + "Whoa!"; new-best
            greetings; kite fights ("Bo kata!"); ducklings; koi gather round you at the pond edge; tiered per-frame
            updates by distance/view; merry-go-round angle fix; bubbles only within 170 studs. Pigeons + dog code waits for
            art/export/TC_ParkPack2.fbx. LobbyDetail: phones on Automatic get the light park. LobbyTraffic: night lamps.
2026-10-17  owner's Claude  LOBBY PARK. NEW LobbyPark (client): the lawn as a park (ponds with koi that jump + ducks + a
            footbridge, playground with kids on swings/see-saw/merry-go-round/slide, fountain + chai stall, banyans with
            picnics and kite flyers, gully cricket, hedged garden + tag, sandstone footpath ring with lamps (lit at night)
            and bins, ashoka avenue, tree belt, strollers/joggers/chatting groups, spectators who film each yard's launches
            via Remotes.Launched/AutoFire). LobbyDetail builds it first and keeps its scatter off it; LobbyVista steps it.
            NEW Assets/Park (27 models from TC_ParkPack.fbx). All moving parts go through one BulkMoveTo.
2026-10-17  owner's Claude  LOBBY DETAIL + VEHICLE MODELS. NEW LobbyDetail (lawn grass patches, tufts, wildflowers,
            shrubs, rocks, a grove per gap between the lines of fire, 2 banyans; canal reeds; earth bunds round every
            field, trees along them, haystacks + shade trees by villages; seeded, less on low graphics;
            workspace attribute LobbyDetail=false turns it off). LobbyVista: one new step (detail, after traffic).
            LobbyTraffic: uses Assets/Vehicles/<kind> Blender models (Paint/Detail/Shirt meshes) when present.
            NEW Assets/Nature (5 trees + 9 small pieces) and Assets/Vehicles (9 kinds), imported from TC_LobbyPack.fbx.
2026-10-17  owner's Claude  NEON PACK LIGHTS. The owner lifted the no-neon/no-glow rule. Touched: Game (NeonTubes = true,
            so every tube in NeonDecor / YardLook / PrestigeLook is real Neon), NeonDecor (glow(): one PointLight per built
            piece in its biggest tube's colour, a downward SpotLight on neonlamp), YardLook (edge() returns its parts; lamp():
            Midnight Garage lights on the 4 outer edges, 3 hex sides, the tyre towers = 10 lights). Shadows off on all.
            Also new Blender art (not imported yet): 5 lobby trees + 4 update-1 cannons, FBX in the owner's art/export folder.
2026-10-16  cjtrxn's Claude  HUB DRESSING (client-side, nothing in Workspace moved). Touched: PlazaLife (plaza floor recoloured to
            sandstone pavers + terracotta trim; NightLamps hidden locally and Props/Lantern posts stand in their places, bunting runs to
            them; rangoli is one painted decal now; planters/benches jittered; seeded clusters on the lawn between the paths),
            TrackGen (roadside density wave + per-zone landmarks: village / truck stop / camel camp), Hub2 HUD layout, Crates2 (own
            Legendary per crate, locked-crate veil), Game.banner(now, zoneId).
2026-10-16  cjtrxn's Claude  PLAZA MODELS + SOLID. Touched: PlazaLife (decor(): planters, chai cart, charpai, matka, tyre swing,
            tyre pyramid and toran use the Blender models in Assets/Roadside when present, solid via Models.place; RoadDecor stays
            the fallback; RoadDecor pieces and benches now CanCollide). Also: Tips, Analytics playtest log, Debug Playtest tab,
            phone layout (UI.autoScale hud boost, Hub2 side column, Checklist), ZoneMap pictures, shop icons, settings cog.
2026-10-15  owner's Claude  ROUNDABOUT + TRAFFIC + PLAZA LIFE. Touched: LobbyVista (traffic + plaza steps; HIGHWAY milestone
            beside the road), NEW LobbyTraffic (ring road r760 past the poplars, 8 roads out along the lines of fire, 9 vehicle kinds,
            3 detail levels by graphics setting), NEW PlazaLife (rangoli ring, planters, benches, bunting, chai corner). Client-built.
            Off switches: workspace attributes LobbyTraffic=false, PlazaLife=false.
2026-10-15  owner's Claude  TROPHY PILLAR. Touched: TyreCannonServer (leaderboard section: new prestige board, store
            tc_lb_prestige_v1; paintBoards fills the pillar instead of RunBoards), NEW TyreCannonServer.TrophyPillar (server-built
            black+gold pillar, 4 boards: Longest Run / This Week / Richest / Top Prestige, chrome tyre + laurels + crown on top),
            NEW StarterPlayerScripts.TrophySpin (turns the top, client only). It encloses the statue plinth; nothing moved.
            workspace:SetAttribute("TrophyPillar", false) brings back the old RunBoards.
2026-10-15  owner's Claude  PRESTIGE PER CANNON/TYRE + TUTORIAL SKIP. Touched: PrestigeLook (each cannon build has its own
            kit, KIT; each tyre its own look, TYRE), Tutorial (grey SKIP on every plate: ends the tutorial, or the yard tour).
            Saw your loading-screen changes (WorldView, Main, Preload, Hub2, Kit, LoadScene, TyreLoading); didn't touch them.
2026-10-15  owner's Claude  NEON STAGE + DECOR PACK 2. Touched: YardLook (YardLook.build), HubExtras (shop: NEON STAGE banner
            with a turning preview + colourway chips; Midnight left the pass row), DebugMenu + Debug (Neon pass on/off, Look: stage/
            prestige/Midnight/Sunset/Toxic, Prestige +/-1, Open shop), Main (DebugPanel "shop"), NEW RoadDecor (12 built pieces),
            NeonDecor (falls back to RoadDecor), Game (12 YardDecor entries + categories)
2026-10-15  owner's Claude  YARD + LOBBY (checklist of 2026-10-15). Scripts touched:
            Game (25 new decor kinds, DecorCats, YardFloors, YardFences, layout keeps floor/fence, "skin=" in V2_Layout)
            Config (pref yardTour), PlotStage (draws the chosen floor/fence, PlotStage.preview), Plot2 (self.editBtn)
            YardEdit (drawer tabs incl. FLOOR/FENCE, magnet placement 'settle', smallest-thing picking, stats, TC_Editing attr)
            Loop (AfkReport remote + AFK shot log), Hub2 (afkReport card), Tutorial (yard tour + icon plates + on-screen clamp)
            Main (PlotPaths.new, tutorial.yardEdit), NEW PlotPaths (walkways plaza->gate, yard path gate->cannon; client-built,
            workspace attribute PlotPaths=false turns it off while building the map)
2026-10-15  owner's Claude  created this log
]]

return { claims = CLAIMS, done = DONE }
