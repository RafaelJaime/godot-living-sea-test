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
