# Minimal web release template for Rally Vegetable demo (Godot 4.4.1).
platform = "web"
target = "template_release"
threads = False
dlink_enabled = False
optimize = "size"
lto = "thin"
debug_symbols = False
javascript_eval = False
disable_advanced_gui = True
modules_enabled_by_default = False
module_gdscript_enabled = True
module_freetype_enabled = True
module_text_server_fb_enabled = True
module_webp_enabled = True
# Keep default 3D and GLES3 renderer. Engine physics stays on dummy backend:
# the demo's movement and collisions are calculated in GDScript.
# Limit ThinLTO optimization memory and linker concurrency.
linkflags = "-Wl,--threads=2,--thinlto-jobs=1"
