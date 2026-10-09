extends SceneTree

const Service = preload("res://scripts/platform_service.gd")
var failed := 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok:
		failed += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var service = Service.new()
	root.add_child(service)
	var products = JSON.parse_string(FileAccess.get_file_as_string("res://data/store_catalog.json"))
	check(products is Array and products.size() == 14, "four VK stages and ten vehicles in catalog")
	if not products is Array:
		quit(1)
		return
	service.catalog = products
	service.entitlements = {"mode":"restricted", "skus":[]}
	for kind in ["stage", "car"]:
		var count = 4 if kind == "stage" else 10
		for idx in range(count):
			var entry = service.product(kind, idx)
			var is_free = idx == 0 if kind == "stage" else idx < 3
			check(not entry.is_empty(), "%s %d is in VK catalog" % [kind,idx])
			check(bool(entry.get("free", not is_free)) == is_free,
				"%s %d has expected free/paid classification" % [kind,idx])
			check(service.can_use(kind, idx) == is_free,
				"%s %d is not accessible without an entitlement" % [kind,idx])
			check(bool(entry.get("purchase_enabled", not is_free)) == not is_free,
				"%s %d exposes payment only when locked" % [kind,idx])
			if not is_free:
				check(int(entry.get("price", -1)) == (20 if kind == "stage" else 3),
					"%s %d has the production VK price" % [kind,idx])
				service.entitlements.skus = [str(entry.get("sku", ""))]
				check(service.can_use(kind, idx), "%s %d unlocks after its SKU purchase" % [kind,idx])
				if kind == "stage":
					for other in range(4):
						if other != idx and other != 0:
							check(not service.can_use(kind, other), "stage %d purchase does not unlock stage %d" % [idx,other])
				service.entitlements.skus = []
			if kind == "stage":
				check(service.can_use(kind, idx, true),
					"guest can enter a host-owned stage %d without own purchase" % idx)
	service.entitlements = {"mode":"unrestricted","skus":[]}
	for stage in range(4):
		check(service.can_use("stage",stage),"standalone stage %d remains freely accessible" % stage)
	for car in range(10):
		check(service.can_use("car",car),"standalone vehicle %d remains accessible" % car)
	service.queue_free()
	await process_frame
	print("VK CATALOG MATRIX RESULT: %d failures" % failed)
	quit(1 if failed else 0)
