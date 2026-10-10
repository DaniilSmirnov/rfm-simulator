extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var game=load("res://tools/cpu_profile_game.gd").new()
 var args = OS.get_cmdline_user_args()
 var requested_stage = clampi(int(args[0]), 0, RallyStage.STAGES.size() - 1) if not args.is_empty() else 0
 game.defer_world = true
 root.add_child(game)
 await process_frame
 game.set_process(false)
 game.select_stage(requested_stage)
 game.rng.seed = 20261008
 await game.start_game()
 if game.stage.variant != requested_stage:
  push_error("CPU profile loaded the wrong stage")
  quit(1)
  return
 if args.size() > 1 and args[1] == "racing":
  game.course.phase = "racing"
  game.spawn_clock = 999.0
  for i in range(8):
   game.spawn_racer("pass")
   var racer = game.racers.back()
   racer.s = 20.0 + i * 70.0
   racer.node.position = game.race_at(racer.s)
   var direction = game.race_direction(racer.s)
   racer.node.rotation.y = atan2(-direction.x, -direction.z)
 if args.has("offroad"):
  game.car.position = game.stage.at(240) + game.stage.side(240) * 35.0
  game.car.position.y = game.stage.ground(game.car.position)
 print("CPU_PROFILE setup racers=",game.racers.size())
 print("CPU_PROFILE setup stage=",game.stage.variant," max_fps=",Engine.max_fps," samples=300 dt=1/60 headless=true")
 for mode in ["driving", "walking"]:
  game.in_car = mode == "driving"
  game.walker = game.car.position + Vector3(2,0,0)
  for i in range(30):
   game._process(1.0/60.0)
   await process_frame
  game.timings.clear()
  var totals=[]
  for i in range(300):
   var t=Time.get_ticks_usec()
   game._process(1.0/60.0)
   totals.append(Time.get_ticks_usec()-t)
   await process_frame
  game.timings["TOTAL"]=totals
  for key in game.timings:
   var samples=game.timings[key]
   samples.sort()
   var sum=0.0
   for sample in samples: sum+=sample
   print("CPU_PROFILE ",mode," ",key," avg_us=",snappedf(sum/samples.size(),0.1)," p95_us=",samples[int(samples.size()*0.95)])
 quit()
