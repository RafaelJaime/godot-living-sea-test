# Living Sea: a Godot 4.7 pirate-ship wallpaper

An infinite, animated living wallpaper: a three-masted ship sails forever through a simulated ocean while the
weather, wind and time of day change around it. There is no gameplay, just a scene you can leave running.

It is also an experiment: the whole project was built by [Claude Code](https://claude.com/claude-code) agents
working in parallel on branches, steered by a human, with specs written first ([OpenSpec](https://github.com/Fission-AI/OpenSpec))
and screenshots and logs kept as evidence for each change.

![Living Sea hero](docs/hero.gif)

Higher quality video: [docs/hero.mp4](docs/hero.mp4).

![Day](docs/screenshots/01_day.jpg)

## Gallery

| | |
|---|---|
| ![Sunset](docs/screenshots/03_sunset.jpg) | ![Sunset silhouette](docs/screenshots/02_sunset_silhouette.jpg) |
| ![Storm and lightning](docs/screenshots/04_storm_lightning.jpg) | ![Storm](docs/screenshots/05_storm.jpg) |
| ![Night, lit lanterns and wake](docs/screenshots/06_night_lanterns_wake.jpg) | ![Night](docs/screenshots/07_night.jpg) |
| ![Dolphins](docs/screenshots/08_dolphins.jpg) | ![Calm sea, hanging flag](docs/screenshots/13_calm_flag.jpg) |
| ![Crew at the helm](docs/screenshots/09_crew_helm.jpg) | ![Crew](docs/screenshots/10_crew_papi_fuego.jpg) |
| ![Violin](docs/screenshots/11_crew_violin.jpg) | ![Island](docs/screenshots/12_island.jpg) |

All screenshots are 1920x1080 at the `final` quality preset, captured with the project's own `--capture` mode.

## Features

- **FFT ocean** (three cascades) with **Jacobian-based foam**, **crest subsurface scattering** and **caustics**.
- **Advected wake field with a Kelvin pattern** behind the ship, with a bioluminescent glow at night.
- **Cat's paws**: gust patterns on the water driven by the wind model.
- **Volumetric clouds** (Sunshine Clouds 2), day/night cycle and weather plan (clear, cloudy, storm, lightning, rain).
- **Wind model with regimes** (calm to storm) and travelling gusts that drive everything that reacts to air.
- **XPBD cloth** for sails and flags, with real aerodynamics from the apparent wind.
- **Ship with buoyancy physics** and an autopilot that sails between islands and tacks upwind.
- **Lanterns and cabin windows** that light up at dusk.
- **Ambient life**: dolphins, gulls, flotsam and passing ships.
- **Autonomous crew** driven by the reusable [`npc_life`](godot/addons/npc_life) addon.
- A **cinematic auto camera** with 22 preset shots plus a free-fly debug camera.

Optional visual effects from Vefects are not included. If you want them, download them separately from their author
and add them to the project yourself.

## Requirements

- Godot **4.7.x** (developed on 4.7.2), Forward+ renderer, a GPU with Vulkan or Metal.
- [git-lfs](https://git-lfs.com): models and images are stored in LFS.

## How to install

1. Install git-lfs and run `git lfs install` once.
2. Clone the repository: `git clone <this repository>`.
3. Open the `godot/` folder in Godot 4.7 and let it import (or run `godot --headless --path godot --import`).
4. Run the project (`F5`) or launch it from the command line:

```
godot --path godot                         # light "dev" preset
godot --path godot -- --quality=final      # full quality
```

## Performance

Measured on an Apple M5 (Mac17,2) at 1920x1080 during development: the `final` preset averages about 84 fps with 1 % lows
around 62 to 68 fps; `dev` is capped at a fixed 30 fps. These numbers come from the development branches and are not
included in the evidence kept in this repository (see `odd/tasks/living-sea-wallpaper.md` for the earlier QA runs).

## Controls

| Key | Action |
|---|---|
| `1` to `7` | Jump to a camera preset (3/4 bow, side low, high wide, captain, deck crew, "Canto", silhouette) |
| `C` | Toggle the free-fly debug camera |
| `W` `A` `S` `D`, `Q` `E`, `Shift` | Free-fly: move, down/up, fast |
| Mouse | Free-fly: look |
| `Esc` | Release the mouse |

Without input the camera blends to the next preset every 20 seconds. Presets 8 to 22 (crew close-ups, wake, storm,
island, flags) are not bound to keys; select them with `--shots=<index>` together with `--capture`.

## Command-line flags

Pass them after `--`. The full list, with every test flag, is in [godot/README.md](godot/README.md).

| Flag | Meaning |
|---|---|
| `--quality=dev\|final` | Quality preset (default `dev`) |
| `--uncap` | Remove the fps cap and vsync |
| `--capture` | Save screenshots to `godot/_shots/` and quit |
| `--shots=0,2,18` | Camera presets to capture |
| `--start-phase=0..1` | Time of day (0 midnight, 0.5 noon) |
| `--weather=clear\|cloudy\|storm` | Hold a weather state |
| `--sea=0..1` | Force the sea state |
| `--wind=<deg>\|calm\|light\|moderate\|fresh\|strong\|storm` | Wind direction or regime |
| `--no-day` | Freeze the day/night cycle |
| `--auto-light[=s]` | Light the lanterns after dusk |
| `--ambient-now` | Trigger every ambient event (dolphins, ships) within seconds |
| `--lightning` | Force lightning in a capture |

Example, a stormy capture:

```
godot --path godot -- --capture --quality=final --start-phase=0.55 --weather=storm --sea=0.9 --lightning --shots=18,0
```

## Project structure

```
godot/                  Godot project (open this folder)
  addons/npc_life/      reusable NPC life addon (MIT)
  addons/ocean_fft/     vendored FFT ocean pipeline (MIT)
  addons/SunshineClouds2/  vendored volumetric clouds (MIT)
  addons/gut/           unit-test framework (MIT)
  scripts/, shaders/    ocean, wind, cloth, camera, weather, ambient life
  ship/, crew/, assets/ ship scene, crew definitions, models and textures
  tests/                GUT tests
odd/                    task lists and research notes written by the agents
openspec/               specs and designs written before the larger changes
*.py, *.blend           Blender scripts used to prepare the ship, the dolphin and placeholders
docs/                   hero animation and screenshots
```

## npc_life: a reusable addon

[`godot/addons/npc_life`](godot/addons/npc_life) is a game-agnostic "smart objects + job board + utility AI" addon:
stations that characters claim, a job board fed by world facts, agents that choose with seeded softmax over utility
scores, platform-local navigation (it works on a rolling ship) and animation and IK adapters. Pure GDScript, MIT, with no
dependency on this game. Copy the folder into any Godot 4.7 project; see its README.

## How it was made

Claude Code agents did the implementation. A human set the goals and made the product decisions. Larger changes started
as an OpenSpec proposal, spec and design (`openspec/`), then became a task list with evidence per task (`odd/`). Each agent
worked on its own git branch and recorded the screenshots, logs and measurements that justified checking a task off.
The code was generated with AI assistance, so review it before relying on it.

## Credits and licences

- Project code: [MIT](LICENSE).
- Own models and textures (the crew, the placeholder ship, the ship's wheel and others): CC0 1.0, released by the author.
- Third-party assets and addons keep their own licences: see [ATTRIBUTION.md](ATTRIBUTION.md) and each addon's `LICENSE`.
