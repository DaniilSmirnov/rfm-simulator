extends SceneTree
func _initialize():
 call_deferred('run')
func run():
 root.size = Vector2i(1280,720)
 var game = load('res://main.tscn').instantiate()
 game.defer_world = true
 root.add_child(game)
 await process_frame
 game.set_process(false)
 game.room.set_process(false)
 game.select_stage(2)
 if OS.get_cmdline_user_args().has("--generated"):
  game.stage.baked_scene_path = "res://generated/missing.scn"
 await game.start_game()
 for panel in game.hud_panels: panel.hide()
 game.title_label.hide()
 game.toast_label.hide()
 game.camera.fov = 65
 var views = [
  ['lavender', Vector3(80,18,-160),Vector3(0,12,-230)],
  ['forest', Vector3(140,8,-435),Vector3(105,4,-470)],
  ['village',Vector3(30,10,-365),Vector3(0,4,-450)],
  ['vineyard',Vector3(50,18,-625),Vector3(20,10,-730)]
 ]
 for view in views:
  game.camera.position = view[1]
  game.camera.look_at(view[2])
  for frame in range(8): await process_frame
  await RenderingServer.frame_post_draw
  print('VILLAGE_RENDER ',view[0],' primitives=',RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),' draws=',RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
  var output = OS.get_environment('RFM_PROFILE_OUTPUT')
  if not output.is_empty(): root.get_texture().get_image().save_png(output+'-'+view[0]+'.png')
 await game._shutdown_audio()
 game.queue_free()
 await process_frame
 quit()
