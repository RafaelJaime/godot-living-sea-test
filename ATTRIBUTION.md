# Attribution

- **Pirate ship (Rigged)** by TIG, licensed CC BY 4.0 — https://sketchfab.com/3d-models/pirate-ship-rigged-f78e4e29b78c422b8db540459882e601
  Based on **Ship Pinnace** by Poly Haven (CC0, https://polyhaven.com/a/ship_pinnace).
  Converted FBX -> glTF with `export_pinnace.py` (deployed-sail meshes re-positioned, materials rebuilt from the 1k textures);
  sails, flag, rudder and hull-water masking are implemented in Godot (`godot/scripts/pinnace_rig.gd`, `flag.gd`, `godot/shaders/sail_cloth.gdshader`).
- **GodotOceanWaves** by Ethan Truong (2Retr0), MIT — https://github.com/2Retr0/GodotOceanWaves (vendored FFT pipeline in `godot/addons/ocean_fft`, see its LICENSE).
