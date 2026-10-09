// Registry for the authoritative functional Godot tests.
// Any new test_*.gd must be classified; the runner rejects forgotten tests.
// Keep file ownership/categories explicit so CI failures identify their subsystem.
export const groups = Object.freeze({
 core: [
  "test_character_asset.gd", "test_player_handling.gd", "test_rolling_wheels.gd",
  "test_vehicle_contract.gd", "test_cargo_selection_order.gd", "test_trunk.gd",
  "test_niva_integration.gd", "test_packing.gd", "test_demo.gd", "test_mobile.gd",
  "test_stage_safety_gate.gd", "test_party.gd", "test_selection.gd",
  "test_vk_access.gd", "test_vk_catalog_matrix.gd", "test_vk_invite_ui.gd",
  "test_lobby_ui.gd", "test_room_origin.gd", "test_minimap.gd",
  "test_resource_cache.gd", "test_draw_distance.gd", "test_world_loading.gd",
  "test_furniture.gd", "test_interaction.gd", "test_soundscape.gd",
 ],
 simulation: [
  "test_camp_cooking.gd", "test_course_schedule.gd", "test_rally_handling.gd",
  "test_rally_rejoin.gd", "test_rally_smoothness.gd", "test_rally_tracks.gd", "test_rally_traffic.gd", "test_room.gd",
  "test_physics.gd", "test_food_fleet.gd", "test_foraging.gd",
  "test_poison_mushrooms.gd", "test_network_motion.gd", "test_tow_recovery.gd",
  "test_crew_limit.gd", "test_drive_prediction.gd",
 ],
 world: [
  "test_baked_village.gd", "test_village_landmarks.gd", "test_navigation_budget.gd",
  "test_crowd_navigation.gd", "test_run_jump_npc.gd", "test_course_officials.gd",
  "test_city_physics.gd", "test_vineyard.gd",
  "test_village_terrain_performance.gd", "test_village_viewpoints.gd",
  "test_spectators.gd", "test_rocks.gd", "test_woodland.gd",
  "test_terrain_seams.gd", "test_road_surface.gd",
  "test_gravel_relief.gd", "test_canyon.gd",
 ],
});
export const nodeSuites = Object.freeze({
 core: [
  ["--test", "tests/platform.test.mjs", "tests/auth-vk.test.mjs", "tests/payments-vk.test.mjs",
   "tests/store.test.mjs", "tests/deploy-cloudflare.test.mjs", "tests/fullscreen.test.mjs",
   "tests/mobile-viewport.test.mjs", "tests/mobile-host-pause.test.mjs",
   "tests/test-catalog.test.mjs",
   "tests/rate-limits.test.mjs"],
  ["--test", "tests/branding.test.mjs", "tests/boot-diagnostics.test.mjs",
   "tests/audio-recovery.test.mjs"],
  ["scripts/test-device.mjs"],
 ],
 simulation: [["--test", "tests/room-core.test.mjs", "tests/room-session.test.mjs"]],
 world: [],
});
export const groupDescriptions = Object.freeze({
 core: "UI, VK entitlement, controls, assets, player car and inventory",
 simulation: "rally timing/physics, NPC interaction, networking and food",
 world: "all stages, terrain, scenery, route topology and performance",
});
export const slowTests = new Set([
 "test_village_terrain_performance.gd", "test_canyon.gd",
 "test_selection.gd", "test_world_loading.gd", "test_baked_village.gd",
]);
export function verifyRegistry(files) {
 const seen = new Map();
 for (const [group,tests] of Object.entries(groups)) {
  for (const file of tests) {
   if (!/^test_[a-z0-9_]+\.gd$/.test(file)) throw Error("Invalid registered test filename: "+file);
   if (seen.has(file)) throw Error("Test "+file+" registered twice ("+seen.get(file)+", "+group+")");
   seen.set(file,group);
  }
 }
 const actual=new Set(files.filter(f=>/^test_[a-z0-9_]+\.gd$/.test(f)));
 const missing=[...actual].filter(f=>!seen.has(f));
 const stale=[...seen.keys()].filter(f=>!actual.has(f));
 if (missing.length||stale.length) throw Error("Godot test registry drift: unclassified="+missing.join(",")+" missing_files="+stale.join(","));
 return {count:seen.size,groups:Object.fromEntries(Object.entries(groups).map(([k,v])=>[k,v.length]))};
}
