# Copilot Workspace Instructions

These workspace agents live under `.github/agents/`. Each agent file includes a `name` and a concise scope for VS Code/GitHub Copilot to specialize responses.

Agents
- rendering-shaders — shader migration and sampling
- build-env — project/export configuration
- debugging-troubleshooter — root cause and fixes
- performance-profiler — budgets and tuning
- logging-telemetry — concise, actionable logs
- physics-safety — overlap probes, ground projection
- test-qa-scenarios — test matrices and repros

Guidelines
- Keep logs minimal; enable probes only when requested
- Prefer deferred calls when adding nodes to the scene tree
- Gate authority-sensitive code appropriately

# AI coding guide for Godot 4 projects

Big picture
- This project uses specialized Copilot workspace agents under `.github/agents/` to help with specific domains of game development.
- Each agent has a focused scope (shaders, physics, debugging, etc.) and can hand off to other agents when needed.

Avoiding common physics & scripting pitfalls
-----------------------------------------
- RayCast-based grounding: prefer a short downward `RayCast3D` with appropriate `cast_to`. Always call `force_raycast_update()` at `_ready()` and before using results in `_physics_process()` so the first physics frame has reliable data.
- Jump reliability: add a short jump grace (`jump_grace_frames`) to suppress re-snapping immediately after jump input so jumps are not swallowed by probe logic.
- Slope handling: compute floor angle via collision normal and compare with a tunable `floor_max_angle_deg`. Reproject horizontal velocity onto the floor plane when grounded so players walk along slopes naturally.
- Probe distance & tolerance: avoid exact Vector3 equality when comparing positions. Use a small distance tolerance (e.g., 0.01) for removals and checks.
- Imported mesh collisions: large GLB/scene imports often include concave, dense collision meshes that cause unstable normals. Prefer exporting simplified convex collisions or add a separate `StaticBody3D` with simplified `CollisionShape3D` approximations for gameplay surfaces.
- Performance & probes: keep physics probe `max_tries` conservative (e.g., 8) to avoid long probe loops.
- Logging & debug: wrap high-frequency prints behind a `DEBUG_LOGS` flag and prefer concise, structured lines for telemetry. Enable probes only when troubleshooting.
- GDScript typing & expressions:
	- Explicitly type variables when the initializer is a `Variant` (avoid `var x := something` where `something` is a Variant). Use `var x: float = ...` to silence warnings/errors in strict mode.
	- Use GDScript ternary form `a if cond else b` and make sure both branches produce the same type (or cast them to the same type) to avoid incompatible ternary errors.

Add these checks to PR reviews for any branch that touches physics, imported assets, or player movement logic.
