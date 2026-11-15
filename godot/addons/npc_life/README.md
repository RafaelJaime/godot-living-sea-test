# NPC Life (status: 0.1.0, under construction)

Game-agnostic "smart objects + job board + utility AI" for Godot 4.7: stations that characters claim, a job board that world-driven
sources post to, agents that decide with seeded softmax over utility scores (so crews behave in varied, reproducible ways), platform-local
navigation on a typed-edge waypoint graph (works on rolling ships and rotating rafts), and abstract animation and IK adapters.

- Pure GDScript, MIT. No autoload, no project settings, no dependency on any game code. Every global class is prefixed `Npc`.
- Dev-only tests (GUT) live outside this folder, in the host project's `tests/npc_life/`.
- Full documentation lands with the packaging slice; see `openspec/changes/npc-crew-jobs/` in the host project for the design.
