class_name AutoProfile
extends Resource
## Tuning changes policy, never the player's physical or weapon capabilities.

@export_range(0.2, 1.5, 0.05) var prediction_horizon := 0.65
@export_range(8, 32, 1) var sampled_directions := 16
@export_range(0.0, 30.0, 1.0) var route_clearance_margin := 8.0
@export_range(0.1, 1.0, 0.05) var goal_interval := 0.25
@export_range(40.0, 140.0, 1.0) var preferred_firing_range := 85.0
@export_range(0.0, 300.0, 1.0) var fresh_pickup_value := 160.0
@export_range(0.0, 100.0, 1.0) var refresh_pickup_value := 30.0
@export_range(24.0, 80.0, 1.0) var spawn_safety_radius := 48.0
@export_range(30.0, 120.0, 1.0) var escape_trigger_distance := 70.0
@export_range(0.65, 1.5, 0.05) var escape_horizon := 1.0
@export_range(0.25, 2.0, 0.05) var escape_commit_time := 0.8
