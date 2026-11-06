class_name SceneReaper
extends Node
## Frees a scene that has already left the tree a little at a time (moon handoff).
## Freeing the port's whole scene in one go took ~330 ms, the longest part of the
## frame a no-fade handoff switched on. Out of the tree nothing in it runs, draws
## or is found any more (its _exit_tree has already run, as a scene change does),
## so its nodes can go a few at a time, leaves first, under `budget_ms` a frame.
##
## Static and lazy, like Sound: the first reap() puts one node under the root,
## where it outlives scene changes.

static var _node: SceneReaper

var budget_ms := 2.0
var _queue: Array[Node] = []
var freed := 0                       ## nodes freed so far (tests, traces)
var slowest := {}                    ## { name, class, ms, frame }: the longest single free (traces)


## Free `scene` (already out of the tree) over the next frames.
static func reap(scene: Node) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	var r := _lib()
	r._queue.append(scene)


static func pending() -> int:
	return _node._queue.size() if is_instance_valid(_node) else 0


## Free everything still queued now (quitting, tests).
static func flush() -> void:
	if not is_instance_valid(_node):
		return
	for n in _node._queue:
		if is_instance_valid(n):
			for t in n.find_children("*", "PlanetTerrain", true, false):
				t.finish_jobs()
			n.free()
	_node._queue.clear()


static func _lib() -> SceneReaper:
	if is_instance_valid(_node):
		return _node
	_node = SceneReaper.new()
	_node.name = "SceneReaper"
	_node.process_mode = Node.PROCESS_MODE_ALWAYS
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child.call_deferred(_node)
	return _node


func _process(_dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var budget := int(budget_ms * 1000.0)
	while not _queue.is_empty():
		var root: Node = _queue.back()
		if not is_instance_valid(root):
			_queue.pop_back()
			continue
		var n := root
		while n.get_child_count() > 0:
			n = n.get_child(n.get_child_count() - 1)
		if n == root:
			_queue.pop_back()
		if n.has_method("jobs_busy") and n.jobs_busy():
			# Issue #574: a terrain whose worker jobs are still running: waiting for
			# them here stalled the frame after a switch (a mid ring is hundreds of ms
			# of worker time). Try again next frame; they finish on their own.
			if n == root:
				_queue.push_back(root)
			break
		var t1 := Time.get_ticks_usec()
		var what := "%s(%s)" % [n.name, n.get_class()]
		if n.has_method("finish_jobs"):
			n.finish_jobs()       # a worker still calling into it would lock it
		n.free()
		var ms := (Time.get_ticks_usec() - t1) / 1000.0
		if ms > float(slowest.get("ms", 0.0)):
			slowest = { "name": what, "ms": ms, "frame": Engine.get_process_frames() }
		if is_instance_valid(n):
			# Could not be freed now: off the tree walk, and gone at the frame's end.
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
		freed += 1
		if Time.get_ticks_usec() - t0 >= budget:
			break


func _exit_tree() -> void:
	flush()
