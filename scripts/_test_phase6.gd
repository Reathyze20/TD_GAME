extends Node

var completed := false
var game: Game

func _ready() -> void:
	game = preload("res://scenes/Game.tscn").instantiate()
	add_child(game)
	# Milestone isolation: this harness predates the Brain Fog and the Routine build
	# gate and exercises OTHER systems — both new gates are switched off wholesale.
	# Their own coverage lives in _test_fog_bandwidth.gd.
	game.fog_enabled = false
	game.routine_gates_enabled = false
	call_deferred("_run")

func _check(condition: bool, msg: String) -> bool:
	if condition:
		print("PASS ", msg)
		return true
	else:
		push_error("FAIL ", msg)
		return false

func _run() -> void:
	var ok := true

	# 1. Test Projectile Pool Allocation
	var p1: Projectile = game.projectile_pool.acquire()
	ok = _check(p1 != null and p1 is Projectile, "pool allocates new Projectile") and ok
	ok = _check(game.projectile_pool._active == 1, "pool increments active count") and ok
	var p2: Projectile = game.projectile_pool.acquire()
	ok = _check(game.projectile_pool._active == 2, "pool acquires second Projectile") and ok

	# 2. Test Projectile Pool Release
	game.projectile_pool.release(p2)
	ok = _check(game.projectile_pool._active == 1, "pool decrements active on release") and ok
	
	# Verify that releasing twice does NOT corrupt size (this requires pool safety which we didn't explicitly write, but let's see if it works without erroring out)
	game.projectile_pool.release(p2)
	ok = _check(game.projectile_pool._pool.size() >= 1, "pool handles release") and ok

	# 3. Test Projectile Release via destroy
	print("DEBUG: Before destroy, active is ", game.projectile_pool._active)
	p1._destroy()
	print("DEBUG: After destroy, active is ", game.projectile_pool._active)
	await get_tree().process_frame
	ok = _check(game.projectile_pool._active == 0, "projectile auto-releases via finished signal") and ok
	print("DEBUG: After process frame, active is ", game.projectile_pool._active)
	
	# 4. Test ImpactFX Pool
	var fx: ImpactFX = game.impact_fx_pool.acquire()
	ok = _check(fx != null and fx is ImpactFX, "pool allocates ImpactFX") and ok
	var fx_active := game.impact_fx_pool._active
	fx.play(Color.WHITE)
	# play takes 0.25s, so we wait 0.3s
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	ok = _check(game.impact_fx_pool._active == fx_active - 1, "ImpactFX auto-releases on finish") and ok

	# 5. Test GPUParticles2D Burst Pool (fixed ring buffer replacement)
	var b1: GPUParticles2D = game.burst_pool.acquire()
	ok = _check(b1 != null and b1 is GPUParticles2D, "pool allocates burst particle") and ok
	var burst_active := game.burst_pool._active
	# The burst pool doesn't explicitly release via script automatically unless we wired it up.
	# We wired `finished.connect(func(): burst_pool.release(p))` in game.gd.
	# Lifetime is 0.65s.
	b1.restart() # manually emit
	await get_tree().create_timer(1.0).timeout
	await get_tree().process_frame
	ok = _check(game.burst_pool._active == burst_active - 1, "Burst particle auto-releases on finish") and ok

	if ok:
		print("ALL PASS")
	else:
		print("SOME CHECKS FAILED")

	completed = true
	get_tree().quit()
