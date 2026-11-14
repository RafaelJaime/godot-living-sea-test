extends Node
## Child of the WindField autoload, processed LAST in the frame: starts the parallel cloth step (see ClothSolver.launch).

func _process(delta: float) -> void:
	ClothSolver.launch(delta)
