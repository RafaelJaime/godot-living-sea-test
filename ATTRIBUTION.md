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

## Own assets (CC0 1.0)

The following models and textures are own models, released by the author under
[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/). They were generated with Meshy and then rigged, retargeted and edited in this project.

- The four crew characters (`godot/assets/characters/`: `papi_fuego`, `papi_diagnostica`, `el_salchipapa`, `don_omar`) and their base animations (`godot/assets/anim_src/walk.glb`, `talk.glb`, `climb_stairs.glb`).
- `godot/assets/ship/barco.glb` (placeholder ship) and `godot/assets/ship/ship_wheel.glb`.
- The other textures and clips authored in this repository.

## Project code

The project's own code is under the MIT licence, see [LICENSE](LICENSE). It was written with AI assistance (Claude Code). Vendored third-party code keeps its own licence in each addon folder.
