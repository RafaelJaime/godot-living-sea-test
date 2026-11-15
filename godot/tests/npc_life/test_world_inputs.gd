extends GutTest
## NpcWorldInputs: the blackboard the game feeds world facts into (addon code never reads game state itself).

var inputs: NpcWorldInputs

func before_each() -> void:
	inputs = NpcWorldInputs.new()

func test_set_get() -> void:
	inputs.set_value(&"storm", 0.9)
	assert_eq(inputs.get_value(&"storm"), 0.9)
	assert_true(inputs.has_value(&"storm"))

func test_default_value() -> void:
	assert_eq(inputs.get_value(&"missing"), null)
	assert_eq(inputs.get_value(&"missing", 3), 3)
	assert_false(inputs.has_value(&"missing"))

func test_change_logged() -> void:
	inputs.set_value(&"daylight", 0.2)
	inputs.set_value(&"daylight", 0.2)
	inputs.set_value(&"daylight", 0.5)
	var log := inputs.change_log()
	assert_eq(log.size(), 2, "setting an unchanged value logs nothing")
	assert_eq(log[1]["key"], &"daylight")
	assert_eq(log[1]["old"], 0.2)
	assert_eq(log[1]["new"], 0.5)
	assert_gt(log[1]["seq"], log[0]["seq"], "monotonic sequence number, no wall-clock")

func test_change_log_bounded() -> void:
	inputs.max_log = 8
	for i in 50:
		inputs.set_value(&"k", i)
	assert_eq(inputs.change_log().size(), 8)
	assert_eq(inputs.change_log()[7]["new"], 49)

func test_change_signal() -> void:
	watch_signals(inputs)
	inputs.set_value(&"wind", 5.0)
	inputs.set_value(&"wind", 5.0)
	assert_signal_emit_count(inputs, "value_changed", 1)

func test_consulted_keys_recorded() -> void:
	inputs.set_value(&"a", 1)
	inputs.set_value(&"b", 2)
	inputs.begin_consult()
	inputs.get_value(&"a")
	inputs.get_value(&"zzz", 0)
	var used := inputs.end_consult()
	assert_eq(used, PackedStringArray(["a", "zzz"]), "keys read between begin/end, sorted, for the decision log")
