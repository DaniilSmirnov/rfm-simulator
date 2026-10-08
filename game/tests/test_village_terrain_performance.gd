extends SceneTree
const Stage = preload('res://scripts/stage.gd')
var failures = 0
func check(ok: bool, title: String):
 print(('PASS: ' if ok else 'FAIL: ') + title)
 if not ok: failures += 1
func brute(stage, p: Vector3) -> Dictionary:
 var best = INF
 var station = 0.0
 var point = stage.flat(p)
 for i in range(stage.points.size()-1):
  var a = stage.flat(stage.points[i])
  var segment = stage.flat(stage.points[i+1])-a
  var ratio = clampf((point-a).dot(segment)/maxf(segment.length_squared(),0.000001),0,1)
  var distance = point.distance_squared_to(a+segment*ratio)
  if distance < best:
   best = distance
   station = (i+ratio)*stage.STEP
 return {'s':station,'distance':sqrt(best)}
func _initialize():
 call_deferred('run')
func run():
 var stage = Stage.new(2)
 root.add_child(stage)
 var random = RandomNumberGenerator.new()
 random.seed = 20261008
 var exact = true
 for i in range(2000):
  var p = Vector3(random.randf_range(-450,450),0,random.randf_range(-1100,200))
  var expected = brute(stage,p)
  var actual = stage.urban_nearest(p)
  exact = exact and absf(expected.s-actual.s) < 0.001 and absf(expected.distance-actual.distance)<0.001
 check(exact,'bounded route search matches exhaustive projection, including distant points')
 var smooth = true
 var worst = 0.0
 for z in range(-840,1,4):
  for x in range(-160,161,8):
   var p = Vector3(x,0,z)
   var q = p+Vector3(0,0,0.5)
   if stage.road_distance(p)<24 or stage.road_distance(q)<24: continue
   if stage.village_paved_height(p)!=INF or stage.village_paved_height(q)!=INF: continue
   var difference = absf(stage.ground(p)-stage.ground(q))
   worst=maxf(worst,difference)
   smooth = smooth and difference < 0.12
 check(smooth,'distant hills have no nearest-road cliffs (max half-metre rise %.3f m)' % worst)
 var old_cliff = Vector3(144,0,-228)
 check(absf(stage.ground(old_cliff)-stage.ground(old_cliff+Vector3(0,0,0.5)))<0.10,'reported twenty-metre terrain jump is removed')
 stage._build_terrain()
 var tiles = stage.find_children('TerrainTile_*','MeshInstance3D',false,false)
 var triangles = 0
 var local_bounds = true
 for tile in tiles:
  triangles += tile.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()/3
  local_bounds = local_bounds and tile.mesh.get_aabb().size.x<=64.01 and tile.mesh.get_aabb().size.z<=64.01
 check(tiles.size()>80 and local_bounds and triangles==51204,'terrain tiles preserve every triangle with local culling bounds')
 stage.free()
 print('VILLAGE TERRAIN/PERFORMANCE RESULT: %d failures' % failures)
 quit(1 if failures else 0)
