class_name NpcCli
extends RefCounted
## Parses the addon's `--npc-*` user arguments (everything after `--` on the command line); unknown flags are ignored.
##   --npc-seed=N       world seed (default: generated and logged)
##   --npc-log[=path]   decision log on (and mirrored to a file)
##   --npc-debug        overlay on
##   --npc-force=<agent>:<kind>   pin an agent to a job kind (repeatable)
##   --npc-freeze       start with the AI frozen
##   --npc-step=N       run N logical ticks at start (use with --npc-freeze)
##   --npc-minutes=N    quit after N simulated minutes and print the summary
##   --npc-agents=N     number of agents (examples only)

static func parse(args: PackedStringArray) -> Dictionary:
	var o := {"seed": 0, "log": "", "log_enabled": false, "debug": false, "force": [], "freeze": false, "step": 0, "minutes": -1.0, "agents": 0}
	for a in args:
		if not a.begins_with("--npc-"):
			continue
		var key := a.get_slice("=", 0)
		var has_val := a.contains("=")
		var val := a.get_slice("=", 1) if has_val else ""
		match key:
			"--npc-seed":
				o["seed"] = int(val)
			"--npc-log":
				o["log_enabled"] = true
				o["log"] = val
			"--npc-debug":
				o["debug"] = true
			"--npc-force":
				if val.contains(":"):
					o["force"].append([val.get_slice(":", 0), val.get_slice(":", 1)])
			"--npc-freeze":
				o["freeze"] = true
			"--npc-step":
				o["step"] = int(val)
			"--npc-minutes":
				o["minutes"] = float(val)
			"--npc-agents":
				o["agents"] = int(val)
	return o
