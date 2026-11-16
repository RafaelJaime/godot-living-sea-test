extends GutTest
## Licence guard: the Tomazod Ultimate Animation Library forbids redistributing its files and anything derived from them, so no `tz_*` clip may enter the
## committed crew clip library and its folder must stay git-ignored (see README, "Optional Tomazod").

const LIBRARY := "res://assets/anim/crew_clips.res"
const TOMAZOD_DIR := "assets/anim_src/tomazod/"

func test_committed_clip_library_has_no_tomazod_clip() -> void:
	var lib := load(LIBRARY) as AnimationLibrary
	assert_not_null(lib, "the crew clip library loads")
	for n in lib.get_animation_list():
		assert_false(String(n).begins_with("tz_"), "clip %s must not come from the restricted Tomazod pack" % n)

func test_committed_clip_library_has_no_track_copy_of_a_tomazod_bake() -> void:
	# a bake in assets/anim_src/tomazod/ is named baked_<name>.res; none of its names may appear as a library clip
	var lib := load(LIBRARY) as AnimationLibrary
	var dir := DirAccess.open("res://" + TOMAZOD_DIR)
	if dir == null:
		pass_test("no Tomazod folder in this checkout: nothing to compare")
		return
	for f in dir.get_files():
		if f.begins_with("baked_") and f.ends_with(".res"):
			var clip := f.trim_prefix("baked_").trim_suffix(".res")
			assert_false(lib.has_animation(clip), "library clip %s has the name of a Tomazod bake" % clip)

func test_tomazod_folder_is_git_ignored() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../.gitignore")
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, ".gitignore is readable at %s" % path)
	if f == null:
		return
	var text := f.get_as_text()
	assert_true(text.contains("godot/" + TOMAZOD_DIR), ".gitignore lists godot/%s" % TOMAZOD_DIR)
