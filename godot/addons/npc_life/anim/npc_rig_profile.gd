class_name NpcRigProfile
extends Resource
## Bone names of a rig for the IK adapter (and a retarget name map for game-side clip baking). Defaults follow Godot's humanoid profile names;
## a game ships its own profile for its rig. Pole offsets are elbow hints in the AGENT's local space (down and outward).

## IK chain name -> [root, middle, end] bone names.
@export var chains: Dictionary[StringName, PackedStringArray] = {
	&"hand_l": PackedStringArray(["LeftUpperArm", "LeftLowerArm", "LeftHand"]),
	&"hand_r": PackedStringArray(["RightUpperArm", "RightLowerArm", "RightHand"]),
}
@export var pole_offsets: Dictionary[StringName, Vector3] = {&"hand_l": Vector3(-0.75, 1.0, 0.25), &"hand_r": Vector3(0.75, 1.0, 0.25)}
@export var look_bone: StringName = &"Head"
@export var hips_bone: StringName = &"Hips"
## Prop socket name -> bone it attaches to.
@export var sockets: Dictionary[StringName, StringName] = {&"hand_r": &"RightHand", &"hand_l": &"LeftHand"}
## Source bone name -> this rig's bone name (used by the game's clip bake, kept here so a rig is described in one resource).
@export var retarget_map: Dictionary[StringName, StringName] = {}
