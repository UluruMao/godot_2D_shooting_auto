class_name AutoDecision
extends RefCounted
## Evidence consumed by the inspector is the same evidence used for control.

var tick := 0
var origin := Vector2.ZERO
var objective := "INITIALIZING"
var reason := ""
var goal := Vector2.ZERO
var target_id := 0
var aim_point := Vector2.ZERO
var endpoint := Vector2.ZERO
var fire := false
var shot_reason := "NO_TARGET"
var path := PackedVector2Array()
var explored := PackedInt32Array()
var path_status := "not_requested"
var path_cost := 0.0
var route_tick := 0
var candidates: Array[Dictionary] = []
var goal_candidates: Array[Dictionary] = []
var selected := -1
var emergency := false
var duration_usec := 0
var enemies: Array = []
var horizon := 0.65
var selection_rule := ""
var tactical_reason := ""
var reachable_cells := 0
var escape_room := 0.0
var spawn_points := PackedVector2Array()
var route_blockaded := false
var stage_usec: Dictionary = {}
