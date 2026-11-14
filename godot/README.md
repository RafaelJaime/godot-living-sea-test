# Pirate Ship Wallpaper (Godot 4.7)

Infinite, animated living wallpaper: a galleon sails forever through procedural Gerstner waves with
four crew members aboard and low-poly tropical islands drifting by. No gameplay.

## Run
```
godot --path /Users/rafael/Documents/workspace/autonomo/el-terraria-blender/godot
```
First time (or after dropping new GLBs): `godot --headless --path <project> --import`
(not strictly needed: GLBs without an import file are parsed at runtime as a fallback).

Screenshots + quit: `godot --path <project> -- --capture` writes `_shots/shot_01..07.png`.

## Controls
- `C` toggle free-fly debug camera (WASD, Q/E down/up, mouse look, Shift fast, Esc frees the mouse)
- `1`-`5` jump to camera shots (3/4 bow, side low, high wide, captain, deck crew)
- Auto camera blends to the next shot every 20 s with drift and handheld noise.

## Where to drop final assets
- Ship: `res://assets/ship/barco.glb`
- Crew: `res://assets/characters/{papi_fuego,papi_diagnostica,el_salchipapa,don_omar}.glb`
If the file exists it is used, otherwise `res://assets/placeholder/*.glb` (exported from the Blender blockout
by `../export_placeholders.py`).

Ship normalization (`scripts/ship_loader.gd`): AABB -> long axis -> bow detected as the narrower end -> rotated so the
bow points to -Z -> scaled to `target_length` (22 m) -> waterline at 35% of an estimated hull depth.
Fix a wrong guess with `ship_yaw_offset_deg`, `force_bow_sign`, `ship_scale_override`, `waterline_offset`, `hull_depth_ratio`.
Crew: height normalized per slot (`target_height`), first/"idle" animation looped with a random start.

## Tweaking (all exports, editable in the editor)
- Crew markers: `Ship/Pivot/CrewMarkers/<name>`: `norm_u` (0 stern .. 1 bow), `norm_v` (-1 port .. 1 starboard),
  `deck_height_frac`, `snap_to_deck` (raycast, tolerance `snap_tolerance`), `facing_deg`, `target_height`,
  `final_model_yaw_deg` (model's native front), `barrel_height`.
- Waves: ONE place, `scripts/waves.gd` (`wave_defs`, `sea_state`); pushed to the shader and mirrored on CPU (`height_at`).
- Ship motion: `Ship` -> `speed`, `heave/pitch/roll gains`, `wind_heel_deg`, `yaw_wander_deg`.
- Sky: `Sky` -> `sun_azimuth_deg`, `sun_elevation_deg`, `fog_density`, `day_cycle` (off by default).
- Islands: `Islands` -> `island_count`, lateral/ahead distances, `seed_base`.

## Infinite sailing
The ship moves along -Z; every 1024 m everything in group `rebase` is shifted back to the origin and the shift is folded into the
wave phase in double precision (`Waves.add_world_shift`), so there is no jitter after hours. Test: `-- --rebase-test=50`.

## Running automated captures / tests without stealing focus (macOS)
```
open -g -n -W -a /Applications/Godot.app --args --path <project> --position 20,40 --resolution 1280x720 \
     --log-file <project>/_shots/godot.log -- --capture
```
`-g` keeps the current app frontmost, `-W` waits for exit; output goes to the log file. In `--capture` and `--jitter-test`
modes `capture.gd` also sets `WINDOW_FLAG_NO_FOCUS`. Other flags: `--jitter-test [--jitter-shot=N]`, `--rebase-test=<m>`, `--debug-deck`.
Ocean: `Waves.sea_state` (0 calm .. 1 storm); FFT pipeline vendored in `addons/ocean_fft` (MIT, see its README).
