extends GutTest
## Another player's floating name (RemotePlayer.tag, fixed_size) keeps its size
## on screen when you zoom in: its pixel_size shrinks with the fov.

const RemotePlayer := preload("res://src/systems/net/remote_player.gd")


func test_unzoomed_keeps_name_px() -> void:
	assert_almost_eq(RemotePlayer.zoomed_px(0.0011, 75.0, 75.0), 0.0011, 1e-9)


func test_zoom_shrinks_by_the_magnification() -> void:
	# A 2.5x scope: the lens's half-angle tangent is 2.5 times smaller.
	var fov := rad_to_deg(2.0 * atan(tan(deg_to_rad(37.5)) / 2.5))
	assert_almost_eq(RemotePlayer.zoomed_px(0.0011, 75.0, fov), 0.0011 / 2.5, 1e-9)


func test_bad_fov_leaves_it_alone() -> void:
	assert_eq(RemotePlayer.zoomed_px(0.0011, 0.0, 30.0), 0.0011)
	assert_eq(RemotePlayer.zoomed_px(0.0011, 75.0, 0.0), 0.0011)


## In the game: a friend's name under the on-foot camera, then through a 2.5x scope.
func test_tag_through_the_rig_camera() -> void:
	var CameraRigNode = load("res://src/systems/camera/camera_rig_node.gd")
	var rig: Node3D = CameraRigNode.new()
	add_child_autofree(rig)
	var cam: Camera3D = rig.camera()
	var them := RemotePlayer.new()
	them.setup(7, "Kiki", {})
	add_child_autofree(them)
	them.visible = true
	var px := NetSession.n("name_px", 0.0011)
	them._process(0.016)
	assert_almost_eq(them.tag.pixel_size, px, 1e-9, "unzoomed: name_px")
	cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(rig.base_fov * 0.5)) / 2.5))
	them._process(0.016)
	assert_almost_eq(them.tag.pixel_size, px / 2.5, 1e-9, "2.5x: a 2.5th")
