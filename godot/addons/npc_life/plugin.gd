@tool
extends EditorPlugin
## NPC Life editor plugin. Registers editor tooling only (gizmos and inspector helpers arrive with the debug/editor slices).
## It adds no autoload and writes no project settings: enabling or disabling it only toggles the editor entry.

func _enter_tree() -> void:
	pass

func _exit_tree() -> void:
	pass
