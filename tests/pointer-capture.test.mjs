import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const source = readFileSync(new URL('../game/scripts/game.gd', import.meta.url), 'utf8');
const roomSource = readFileSync(new URL('../game/scripts/room.gd', import.meta.url), 'utf8');

test('desktop start requests pointer capture before asynchronous world preparation', () => {
  const start = source.slice(source.indexOf('func start_game()'), source.indexOf('func _show_stage_safety_gate()'));
  const request = start.indexOf('_request_game_mouse_capture()');
  const prepare = start.indexOf('await prepare_world()');
  assert.ok(request >= 0 && prepare >= 0 && request < prepare);
});

test('create and join buttons capture before sending the asynchronous room request', () => {
  const connect = roomSource.slice(roomSource.indexOf('func connect_room('), roomSource.indexOf('func room_endpoint('));
  const request = connect.indexOf('_request_game_mouse_capture()');
  const send = connect.indexOf('transport.request(');
  assert.ok(request >= 0 && send >= 0 && request < send);
});

test('web gameplay no longer forces the mouse visible after starting', () => {
  const start = source.slice(source.indexOf('func start_game()'), source.indexOf('func _show_stage_safety_gate()'));
  assert.doesNotMatch(start, /room\.connected\s+and\s+OS\.has_feature\("web"\)/);
  assert.match(start, /_request_game_mouse_capture\(\)/);
});

test('a click can retry pointer capture after a browser denial', () => {
  const input = source.slice(source.indexOf('func _unhandled_input('));
  assert.match(input, /event is InputEventMouseButton and event\.pressed and not mobile_mode and Input\.mouse_mode != Input\.MOUSE_MODE_CAPTURED/);
  assert.match(input, /Input\.mouse_mode = Input\.MOUSE_MODE_CAPTURED/);
});

test('mouse look turns the camera only while the pointer is locked', () => {
  const input = source.slice(source.indexOf('func _unhandled_input('));
  assert.match(input, /event is InputEventMouseMotion and not mobile_mode and pointer\.captured\(\)/);
});

test('a pointer lock lost during play pauses the game', () => {
  const pointer = readFileSync(new URL('../game/scripts/pointer_capture.gd', import.meta.url), 'utf8');
  assert.match(pointer, /if was_captured and not is_captured and wanted\(\):\n\t\tgame\._set_paused\(true\)/);
  assert.match(source, /func _process\(delta: float\) -> void:\n\tpointer\.update\(\)/);
});
