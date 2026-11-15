extends Node3D
## Grip-ready hand prop. Add the scene as a child of a BoneAttachment3D on the RIGHT hand bone ("RightHand" of the 24-bone Meshy rig): the root node sits on the
## palm grip point and the Model child is rotated/scaled so the prop lies in the hand like in the captures. Data was solved by build_hand_props.gd.
## Units: the Skeleton3D lives under an Armature with scale 0.01, so bone-local offsets are in cm and the model scale carries a factor 100.
## upright = true (lanterns): the prop hangs from the grip point and keeps its world orientation (only the grip follows the hand).
@export var scale_m: float = 1.0                  # model scale so that the prop has its real length
@export var grip_model: Vector3 = Vector3.ZERO    # grip point in model space (model units)
@export var grip_rotation: Basis = Basis.IDENTITY # model axes -> hand-bone local axes
@export var palm_cm: Vector3 = Vector3.ZERO       # grip point in hand-bone local space (cm)
@export var upright: bool = false

@onready var model: Node3D = $Model

func _ready() -> void:
	if upright:
		top_level = true
		model.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_m), -scale_m * grip_model)
	else:
		transform = Transform3D(Basis.IDENTITY, palm_cm)
		var b := grip_rotation.scaled(Vector3.ONE * scale_m * 100.0)
		model.transform = Transform3D(b, -(b * grip_model))
	set_process(upright)

func _process(_delta: float) -> void:
	var p := get_parent() as Node3D
	if p:
		global_transform = Transform3D(Basis.IDENTITY, p.global_transform * palm_cm)
