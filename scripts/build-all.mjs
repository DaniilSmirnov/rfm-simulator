import { cp, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { root, run } from './godot.mjs';

// Both platform shells keep their own adapter and use the same room API.
run(process.execPath, ['scripts/build-web.mjs', '--target=standalone']);
run(process.execPath, ['scripts/build-web.mjs', '--target=vk']);
await cp(join(root, 'dist-vk'), join(root, 'dist/vk'), { recursive: true });
const headers = await readFile(join(root, 'dist/_headers'), 'utf8');
const vkHeaders = (await readFile(join(root, 'dist-vk/_headers'), 'utf8')).replace(/^\//gm, '/vk/');
await writeFile(join(root, 'dist/_headers'), headers.trimEnd() + '\n\n' + vkHeaders);
console.log('Combined Worker artifact ready: / standalone, /vk/ VK, shared /api/rooms.');
