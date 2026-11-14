# Realism techniques research (2026-11-14)

Read-only web research (11 searches; slides/PDFs not opened — only snippets). [V] verified in source,
[S] assumption / common practice without an opened source.

## 1. Seamless clipmap ocean + infinite horizon
- [V] Crest: concentric power-of-2 rings; vertex shader samples current and next LOD and blends with lodAlpha
  (displacement geomorphing); vertices snapped to the grid; an extra edge strip extends to the horizon.
  https://crest.readthedocs.io/en/4.17/user/system-notes.html
- [S] Our black cracks: T-junctions between rings + different cascade sampling at both sides. Recipe: snap each
  ring to its own cell size; geomorph the outer band of each ring toward the coarse LOD position; 2–5 m vertical
  skirt under each ring edge; overlap rings by one cell; fade the 20 m cascade with distance. Final ring to
  ~20–50 km with horizon fog sampling the sky colour. Anti-tiling: non-commensurable cascade periods (e.g.
  200/77/19) or blend two rotations of the large cascade.

## 2. Physically based water shading
- [V] GodotOceanWaves already uses Atlas-style GGX lighting, bicubic/bilinear normal/foam sampling, Jacobian foam
  with grow/decay, spray via GPUParticles3D culled by foam. https://github.com/sebbasim/GodotOceanWaves
- [V] Atlas GDC 2019: https://gpuopen.com/gdc-presentations/2019/gdc-2019-agtd6-interactive-water-simulation-in-atlas.pdf
  Toksvig (CoD WWII): https://www.advances.realtimerendering.com/s2018/MaterialAdvancesInWWII.pdf
  Tessendorf: https://jtessen.people.clemson.edu/reports/papers_files/simdoc.pdf
  Sea of Thieves (SIGGRAPH 2018 talk, not GDC): https://history.siggraph.org/wp-content/uploads/2022/09/2018-Talks-Ang_The-Technical-Art-of-Sea-of-Thieves.pdf
- [S] White crest streaks = normal/specular aliasing: Toksvig/LEAN roughness from normal variance (mip |N|),
  trilinear+anisotropic mips, fade high-frequency cascade with distance, min roughness 0.02–0.05, specular only
  from analytic sun/moon + sky reflection via Schlick (F0 = 0.02), slope-masked sun sparkle.
- [S] Grey-metallic at dusk: reflection from low-saturation IBL. Sample the real sky in the reflection direction;
  own water colour (absorption deep ≈ (0.0, 0.03, 0.08), turquoise shallows) independent of IBL; crest SSS term
  ≈ max(0, dot(V, -L + N·distort))^p · wave height · teal.

## 3. Wake / spray
- [V partial] Atlas wakes: https://gdcvault.com/play/1025819/Advanced-Graphics-Techniques-Tutorial-Wakes
- [S] Ping-pong wake texture (~1024², world-space window following the ship) stamped each frame at the waterline
  (bow wave, stern turbulence, two divergent Kelvin arms ~19.47°), exponential decay + slight diffusion,
  modulated by lacy FBM noise and smoothstep thresholds; bow-wave height also as vertex displacement. Spray:
  GPUParticles3D at the bow, emission ∝ speed² and slamming.

## 4. Ship physics
- [V] Kerner (Just Cause 3) water interaction model — viscous resistance, pressure drag, slamming, linear damping,
  ~1 ms/boat: https://gamedeveloper.com/programming/water-interaction-model-for-boats-in-video-games ,
  part 2: https://www.gamedeveloper.com/programming/water-interaction-model-for-boats-in-video-games-part-2 ,
  UE4 impl: https://github.com/gauravnba/WaterInteractionModel_UE4 ,
  Habrador (cut hull at waterline, per-triangle buoyancy): https://blog.habrador.com/2016/05/making-realistic-boat-in-unity-part-2.html
- [V] Godot 4 addons: FloatableBody (MIT, galleon demo) https://godotengine.org/asset-library/asset/2345 ,
  WaterBox (MIT), Bounded Buoyancy, Hydro (sinking reports), Ocean3D. None model sails.
- [S] 12–24 hull samples, ρ·g·V per sample, viscous+pressure drag vs relative water velocity, large lateral drag
  (keel), sail lift/drag with CL ≈ 2π·sin α up to ~15° then stall at the centre of effort, rudder lift ∝ v²·angle,
  low centre of mass / righting moment, Jolt with 120 Hz substeps.

## 5. Cloth (sails, flags)
- [V] Per-triangle aero force (drag + lift from normal·relative wind): https://core.ac.uk/download/295549185.pdf ,
  Disney OmniAD: https://la.disneyresearch.com/wp-content/uploads/OmniAD-Data-driven-Omni-directional-Aerodynamics-Paper.pdf ,
  PBD example (10 iterations): https://people.engr.tamu.edu/sueda/courses/CSCE450/2025S/projects/Kyle_Palermo/index.html
- [S] Custom Verlet/XPBD (not SoftBody3D). Flag 16×10, pinned at the TWO hoist corners only, distance + shear +
  light bending, real gravity, wind = base + low-frequency noise + turbulence, two-sided aero, 1–2 % damping,
  8–10 iterations, 2–3 substeps. "Doesn't hang" usually = weak gravity, wind never zero, over-stiff, bad pins.
  Sails: same solver, pinned to yards/sheets, apparent wind, pressure billow.

## 6. Sky / weather / addons / watchability
- [V] Sunshine Clouds 2 (MIT per asset library, Godot 4.5+, compositor): https://github.com/Bonkahe/SunshineClouds2 —
  4.7 compatibility and M-series cost unverified (budget 2–3 ms or lower resolution).
- [V] TCA_Weather_System (MIT, Rayleigh+Mie sky, storm/rain, Godot 4.6+): https://godotengine.org/asset-library/asset/4960 ;
  Matias Lavik WeatherSystem (MIT): https://github.com/mlavik1/GodotWeatherSystem
- [S] Watchability: gull/albatross boids, dolphins at the bow, distant whale, passing ships with night lights,
  lighthouse with rotating beam, night bioluminescence in the wake, cat's paws (wind gusts modulating the small
  cascade), flotsam/seaweed, wet deck in rain, bigger storm seas (wind/fetch), rainbow after storms, morning fog.

## Top 10 (impact on realism + watchability)
1. Seams: geomorph + skirts + per-ring snap.
2. Normal/roughness filtering (Toksvig) + distance fade of the 20 m cascade.
3. Own water colour (absorption + crest SSS) + Fresnel sky reflection from the real sky.
4. Lacy foam modulated by accumulated Jacobian, slower decay in storms.
5. Advected ping-pong wake with bow wave + Kelvin arms + lacy noise (replaces ribbons).
6. Horizon fog / aerial perspective coherent with the sky + far ring to the horizon.
7. XPBD sails/flags with apparent wind (2-corner flag pins, gravity, turbulence).
8. Point buoyancy + Kerner drag + sail lift/drag + keel/rudder.
9. Weather coupled to sea (wind/fetch), rain, lightning, volumetric clouds (if 4.7 + budget allow).
10. Ambient life: birds, dolphins, distant ships, lighthouse, bioluminescence, cat's paws.
