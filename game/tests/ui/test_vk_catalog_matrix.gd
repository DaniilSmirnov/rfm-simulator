extends "res://tests/harness.gd"

const Service = preload("res://scripts/platform/platform_service.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var service = Service.new()
	root.add_child(service)
	var products = JSON.parse_string(FileAccess.get_file_as_string("res://data/store_catalog.json"))
	var stage_count = RallyStage.STAGES.size()
	var car_count = RallyProps.PLAYER_MODELS.size()
	var looks = preload("res://scripts/people/character_profiles.gd").playable()
	check(products is Array and products.size() == stage_count + car_count + looks.size(), "every stage, vehicle and playable character has a VK catalog entry")
	if not products is Array:
		quit(1)
		return
	service.catalog = products
	service.entitlements = {"mode":"restricted", "skus":[]}
	for kind in ["stage", "car"]:
		var count = stage_count if kind == "stage" else car_count
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
				check(int(entry.get("price", -1)) == (20 if kind == "stage" or idx == 11 else 3),
					"%s %d has the production VK price" % [kind,idx])
				service.entitlements.skus = [str(entry.get("sku", ""))]
				check(service.can_use(kind, idx), "%s %d unlocks after its SKU purchase" % [kind,idx])
				if kind == "stage":
					for other in range(stage_count):
						if other != idx and other != 0:
							check(not service.can_use(kind, other), "stage %d purchase does not unlock stage %d" % [idx,other])
				service.entitlements.skus = []
			if kind == "stage":
				check(service.can_use(kind, idx, true),
					"guest can enter a host-owned stage %d without own purchase" % idx)
	# Characters are free for everyone for now; a spectator-only look is not sold.
	for look in range(RallyProps.SPECTATOR_MODELS.size()):
		var entry = service.product("character", look)
		check(entry.is_empty() != (look in looks), "character %d is in the catalog only if playable" % look)
		check(service.can_use("character", look) == (look in looks) and not entry.get("purchase_enabled", false), "character %d is free in VK" % look)
	service.entitlements = {"mode":"unrestricted","skus":[]}
	for stage in range(stage_count):
		check(service.can_use("stage",stage),"standalone stage %d remains freely accessible" % stage)
	for car in range(car_count):
		check(service.can_use("car",car),"standalone vehicle %d remains accessible" % car)
	service.queue_free()
	await process_frame
	print("VK CATALOG MATRIX RESULT: %d failures" % failures)
	finish()
