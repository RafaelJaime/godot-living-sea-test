# Attribution

- **Pirate ship (Rigged)** by TIG, licensed CC BY 4.0 — https://sketchfab.com/3d-models/pirate-ship-rigged-f78e4e29b78c422b8db540459882e601
  Based on **Ship Pinnace** by Poly Haven (CC0, https://polyhaven.com/a/ship_pinnace).
  Converted FBX -> glTF with `export_pinnace.py` (deployed-sail meshes re-positioned, materials rebuilt from the 1k textures);
  sails, flag, rudder and hull-water masking are implemented in Godot (`godot/scripts/pinnace_rig.gd`, `flag.gd`, `godot/shaders/sail_cloth.gdshader`).
- **GodotOceanWaves** by Ethan Truong (2Retr0), MIT — https://github.com/2Retr0/GodotOceanWaves (vendored FFT pipeline in `godot/addons/ocean_fft`, see its LICENSE).
- **Dolphin** by Alex_Pfe, licensed CC BY 4.0 — https://sketchfab.com/3d-models/dolphin-c24dc835a6aa4d3c827450513525cdb8
  Converted FBX -> glTF with `export_dolphin.py` (bubble cubes removed, material rebuilt from 1k textures, swim loop kept); scaled to about 2.5 m in `godot/scripts/ambient/ambient_life.gd`.
- **Sunshine Clouds 2** by David House, MIT — vendored in `godot/addons/SunshineClouds2` (see its LICENSE). Local patch: sky pixels keep the sky shader colour (`SunshineCloudsPostCompute.comp`).
- **Dark Wooden Planks** texture by Amal Kumar (Poly Haven), CC0 — https://polyhaven.com/a/dark_wooden_planks (1k diffuse, normal and roughness in `godot/assets/ambient/flotsam/`), used by the flotsam planks and barrel.
- **Fishing Rod** (`rod_q1`) by Quaternius, CC0 1.0 — https://poly.pizza/m/0YAR0Lg58p (`godot/assets/props/fishing_rod/`), hand prop.
- **Wooden Hammer 01**, **Handsaw Wood** and **Wooden Lantern 01** by Poly Haven, CC0 — https://polyhaven.com/a/wooden_hammer_01, https://polyhaven.com/a/handsaw_wood, https://polyhaven.com/a/wooden_lantern_01 (1k glTF in `godot/assets/props/`), hand props.
- Spyglass, swab and the ratline climb / spyglass look / deck swab animations are generated in this repo (CC0).

## Crew animation clips

- **Universal Animation Library 1 and 2 (Standard)** by Quaternius, CC0 1.0 — https://quaternius.com/packs/universalanimationlibrary.html and https://quaternius.com/packs/universalanimationlibrary2.html (downloaded 2026-11-15). Clips used: Walk_Carry, Idle_Lantern, Idle_Rail, Idle_Talking, Fixing_Kneeling, ClimbUp_1m. Retargeted onto the crew rig by `godot/assets/anim_src/spike/bake_spike.gd`; the source GLBs are not committed. Baked into `godot/assets/anim/crew_clips.res` by `godot/tools/crew_anim_bake.gd` as walk_carry, idle_lantern, idle_rail, idle_talking, fixing_kneeling, climb_up_1m.
- **KayKit Character Animations 1.1** by Kay Lousberg, CC0 1.0 — https://kaylousberg.itch.io/kaykit-character-animations (downloaded 2026-11-15). Clips used: Hammering, Sawing, Fishing_Idle, Fishing_Cast, Fishing_Reeling. Retargeted by `bake_spike.gd` and baked into `crew_clips.res` as hammering, sawing, fishing_idle, fishing_cast, fishing_reeling.

## Ambient audio

- **Ambient audio clips** (CC0, no attribution required; listed for traceability; converted to OGG by `prepare_audio.sh` into `godot/assets/audio/`), all from OpenGameArt:
  sea bed "Sea and river wave sounds" (Vistula) by Snabisch https://opengameart.org/content/sea-and-river-wave-sounds;
  waves "Beach Ocean Waves" (jasinski, freesound 18363, packed by qubodup) https://opengameart.org/content/beach-ocean-waves;
  wind "wind1" (wind1-5) by qubodup https://opengameart.org/content/wind1;
  gulls "Solo Seagull Sound Effects" by Rango Mango https://opengameart.org/content/solo-seagull-sound-effects;
  creaks and bell "Various Sound Effects" https://opengameart.org/content/various-sound-effects and wood, rain and thunder "100 CC0 SFX #2" / "30 CC0 SFX loops" https://opengameart.org/content/100-cc0-sfx-2 https://opengameart.org/content/30-cc0-sfx-loops;
  rumble "Rumbling Sound Effects" https://opengameart.org/content/rumbling-sound-effects.
  Crew hooks (CC0): footsteps from "100 CC0 SFX #2", hammer from "Fast Hammer SFX" and "68 Workshop Sounds" by HaelDB (credit appreciated: https://opengameart.org/content/68-workshop-sounds, https://opengameart.org/content/fast-hammer-sfx), violin placeholder = "Medieval: Minstrel Dance" by Ivan Voirol (CC0, credits appreciated: https://opengameart.org/content/medieval-minstrel-dance); candidates "Medieval: King's Feast" (Snabisch) and "Medieval: The Old Tower Inn" (AntumDeluge), both CC0.
  Splashes: "40 CC0 water / splash / slime SFX" by rockseller (CC0) https://opengameart.org/content/40-cc0-water-splash-slime-sfx; wood hits from "100 CC0 SFX #2". Fire crackle, rain on wood, flag flutter and the lighthouse hum are generated in code (no recordings).
  Splashes: "40 CC0 water / splash / slime SFX" by rockseller (CC0) https://opengameart.org/content/40-cc0-water-splash-slime-sfx; wood hits from "100 CC0 SFX #2". Fire crackle, rain on wood, flag flutter and the lighthouse hum are generated in code (no recordings).

## Own assets (CC0 1.0)

The following models and textures are own models, released by the author under
[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/). They were generated with Meshy and then rigged, retargeted and edited in this project.

- The four crew characters (`godot/assets/characters/`: `papi_fuego`, `papi_diagnostica`, `el_salchipapa`, `don_omar`) and their base animations (`godot/assets/anim_src/walk.glb`, `talk.glb`, `climb_stairs.glb`).
- `godot/assets/ship/barco.glb` (placeholder ship) and `godot/assets/ship/ship_wheel.glb`.
- The other textures and clips authored in this repository.

## Project code

The project's own code is under the MIT licence, see [LICENSE](LICENSE). It was written with AI assistance (Claude Code). Vendored third-party code keeps its own licence in each addon folder.
