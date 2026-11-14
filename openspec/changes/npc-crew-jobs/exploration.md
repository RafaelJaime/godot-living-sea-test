# Exploration: npc-crew-jobs

Executed by the user's NPC session (owns crew/NPC code). Our side adds ship-side hooks only.

## Current state
- 4 static CrewSlot markers under Ship/Pivot/CrewMarkers (crew_slot.gd), deck raycast placement; no locomotion,
  navigation or scheduler. Roles hardcoded by slot in crew_rig.gd (Fuego helm IK, Omar seated violin IK, others idle).
- Animation plumbing: change_clip() 0.35 s crossfade; CrewAnim.install() shares crew_shared.res (walk, climb_stairs,
  talk) with hip-ratio fix; CrewPoseModifier counter-lean; clamped IK at 93 % reach; 1.2 s ramp-in.
- Pivot-local space is roll-proof. Deck levels ≈ stern/helm y 6.5, waist 1.85, forecastle 3.5 (stairs needed).
- Ship hooks today: ShipLights (proto work-station: interaction_point, facing_deg, lit, lighting_needed/
  extinguish_suggested), Ship roll/pitch/rates/rudder/yaw, WorldState daylight/storm/wind/thunder,
  get_sail_forces() per-sail state, Autopilot.tacking (no signal). pinnace_rig furls all sails via one global scalar
  at storm > 0.86; yards braced at runtime (rigging anchors move).
- Unknown: whether the pinnace GLB has ratlines, crow's nest, cabin door, stairs between levels.

## Recommended architecture (option 1)
Smart objects / work stations + world-generated job board + utility AI with softmax pick (randomness) + recency
penalty + hard overrides (watch roster keeps helm staffed and rotates; captain takes the helm in storms; storm =
all hands reef/secure) + social layer (violin → listen ring; helmsman chat offers). Navigation: baked pivot-local
waypoint graph with typed edges (walk/stairs/ladder/shroud), not NavigationServer. Two-layer animation: full-body
clips from free packs + procedural station IK for the upper body (proven by helm/violin).
Rejected: behaviour trees per character (coordination ad hoc), GOAP (overkill), timeline schedule (predictable).

## Ship-side hooks needed (ours)
ShipStations autoload (get_stations/claim/release, job_posted/job_cleared; kinds helm, lantern, spyglass_post,
crows_nest, ratline_path, reef_yard, chart_table, fishing_rail, repair_spot, mop_zone, violin_seat, listen_spot,
boat_check, social_spot; pivot-local anchors, approach point, facing, level, slots, anim_tag, IK targets,
constraints, occupied_by); lanterns registered as stations; per-sail crew furl request_furl(idx,t) + reef stations
(auto furl at 0.86 kept as fallback); Autopilot.maneuver_started signal; wobble + sail_state (roadmap M1-b);
deck wetness (M4c-2); lashed_boat.state() (M5-2); pivot-local waypoint graph export; README docs. Sequence after
roadmap M1-b (shared files).

## Animation sourcing (user: free online or hand-made in Blender, not paid)
- Verified: Quaternius Universal Animation Library 1+2, CC0 (https://quaternius.com/packs/universalanimationlibrary.html,
  https://quaternius.com/packs/universalanimationlibrary2.html, https://quaternius.itch.io/universal-animation-library);
  free Standard tier; UAL2 lists fishing/farming/parkour; specific ladder/rope/hammer/carry clips not confirmed —
  open the zip. Rig "compatible with Mixamo".
- Mixamo: free, commercial use, no credit, but no redistribution of raw files / no ML training (Adobe community FAQ
  https://community.adobe.com/t5/mixamo-discussions/mixamo-faq-licensing-royalties-ownership-eula-and-tos/m-p/13234775;
  official helpx page returned 403 — re-check). Has ladder climb (rung spacing mismatch) and standing fishing.
- Meshy rigs follow Mixamo naming (https://docs.meshy.ai/api/rigging) — exact 24 names unverified.
- Godot 4.7 retargeting: BoneMap + SkeletonProfileHumanoid, Rest Fixer/Overwrite Axis/Normalize/Fix Silhouette;
  assumes T-pose, A-pose sources distort (https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/retargeting_3d_skeletons.html).
- Avoid: CMU mocap (license conflicts; 4TU FBX is CC BY-NC), paid MoCap Online; KayKit CC0 unverified for us.

## Signature clips (source)
Shared: walk/climb_stairs/talk/idle/sit (existing); wave/clap/laugh/listen/look (UAL or Mixamo or small Blender
edits); lantern reach (procedural IK). Fuego: helm (existing IK), spyglass (procedural), pointing orders (pack or
Blender). Diagnóstica: hammer (procedural/Blender loop), climb rigging (Mixamo ladder + hand IK to ratlines), carry
(walk + two-hand IK on crate). Salchipapa: crow's-nest lookout (procedural), rope climb (Mixamo/Blender), fishing
(UAL2 or Mixamo), comic fall (ragdoll blend or UAL stumble). Omar: violin (existing), chart table (Blender/IK),
star gazing (procedural), sit (existing).

## Risks
Retarget quality (rest pose/roll unverified; no finger bones), rigging/rope IK on braced moving yards, IK/modifier
cost, determinism vs randomness (seeded RNG + force-job flag for QA), walking on a rolling deck without foot IK,
shared-file sequencing with roadmap M1/M5, Mixamo redistribution if the repo goes public (repo is local, no
remote), hand-made Blender effort for gaps.

## Open questions
1. Does the pinnace have ratlines, crow's nest, cabin door, stairs? If not, who adds markers/geometry?
2. Sails furl only when the crew does it, or hybrid fallback?
3. Job pace: storm frenzy vs calm slow?
4. Repo public/private (Mixamo redistribution)?
5. Mixamo account + one-time manual import OK?
6. Which UAL Standard clips are usable/retarget cleanly (1 h spike)?
7. Watch rotation fair or skill-weighted (Fuego prefers helm)?
