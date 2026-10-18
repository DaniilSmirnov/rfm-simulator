extends RefCounted
# The road surface cut into pieces along the route. One mesh for the whole stage
# is never culled: every frame, and in every sun-shadow cascade, the GPU drew
# the full kilometre of finely cut road (a hundred thousand triangles) although
# only a few hundred metres of it are ever in view. Pieces of CHUNK stations
# each have their own bounds, so what is behind the camera or beyond the shadow
# range is skipped.
#
# The pieces are cut out of one finished mesh, after its normals were smoothed
# across the whole road, so the lighting has no seams where two pieces meet.
const CHUNK = 64
const LoadPacer = preload("res://scripts/core/load_pacer.gd")

# The drawn pieces of one kind of road surface of `stage`, in route order.
static func meshes(stage: Node, kind: String = "default") -> Array:
	var holder = stage.get_node_or_null(holder_name(kind))
	return [] if holder == null else holder.get_children()

static func holder_name(kind: String) -> String:
	return "StageRoadSurface" if kind == "default" else "StageRoadSurface_" + kind

# Opens a new piece of `part` ({block, marks, count}) when station i enters one.
static func mark(part: Dictionary, station: int) -> void:
	var block = floori(station / float(CHUNK))
	if part.block != block:
		part.block = block
		part.marks.append(part.count)

# `marks` holds, per piece, the number of non-indexed vertices the builder had
# received when the piece began (as the road was laid, in order). `arrays` are
# the arrays of the indexed mesh built from them. Returns one ArrayMesh per piece.
static func split(arrays: Array, marks: Array, tree: SceneTree = null) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var pieces: Array = []
	for piece in range(marks.size()):
		if tree != null:
			await LoadPacer.tick(tree)
		var first: int = marks[piece]
		var last: int = marks[piece + 1] if piece + 1 < marks.size() else indices.size()
		if last <= first:
			continue
		var remap: Dictionary = {}
		var out_vertices = PackedVector3Array()
		var out_normals = PackedVector3Array()
		var out_colors = PackedColorArray()
		var out_uvs = PackedVector2Array()
		var out_indices = PackedInt32Array()
		out_indices.resize(last - first)
		for i in range(first, last):
			var old: int = indices[i]
			if not remap.has(old):
				remap[old] = out_vertices.size()
				out_vertices.append(vertices[old])
				out_normals.append(normals[old])
				out_colors.append(colors[old])
				out_uvs.append(uvs[old])
			out_indices[i - first] = remap[old]
		var piece_arrays: Array = []
		piece_arrays.resize(Mesh.ARRAY_MAX)
		piece_arrays[Mesh.ARRAY_VERTEX] = out_vertices
		piece_arrays[Mesh.ARRAY_NORMAL] = out_normals
		piece_arrays[Mesh.ARRAY_COLOR] = out_colors
		piece_arrays[Mesh.ARRAY_TEX_UV] = out_uvs
		piece_arrays[Mesh.ARRAY_INDEX] = out_indices
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, piece_arrays)
		pieces.append(mesh)
	return pieces

# Adds the pieces of surface `kind` under a holder; a null material gets the
# plain vertex-coloured one. `cooperative` lets frames draw while it cuts.
static func build(stage: Node3D, kind: String, material: Material, arrays: Array, marks: Array, cooperative: bool = false) -> void:
	if material == null:
		var plain = RallyProps.material(Color.WHITE)
		plain.vertex_color_use_as_albedo = true
		plain.vertex_color_is_srgb = true
		plain.cull_mode = BaseMaterial3D.CULL_DISABLED
		material = plain
	var holder = Node3D.new()
	holder.name = holder_name(kind)
	stage.add_child(holder)
	var pieces = await split(arrays, marks, stage.get_tree() if cooperative else null)
	for piece in range(pieces.size()):
		var n = MeshInstance3D.new()
		n.name = "Part_%d" % piece
		n.mesh = pieces[piece]
		n.material_override = material
		holder.add_child(n)
