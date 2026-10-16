import assert from 'node:assert/strict';
import { open, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const executables = [
  { name: 'Rally_Fans_Simulator_x86.exe', machine: 0x014c, magic: 0x010b },
  { name: 'Rally_Fans_Simulator_x64.exe', machine: 0x8664, magic: 0x020b },
];

// Inspect the actual exported bytes, rather than trusting the preset or file extension.
export async function verifyWindowsBuild(directory) {
  const files = (await readdir(directory)).sort();
  assert.deepEqual(files, executables.map(exe => exe.name).sort(), 'Windows output must contain exactly the two standalone exe files');
  for (const exe of executables) {
    const file = await open(join(directory, exe.name), 'r');
    try {
      const { size } = await file.stat();
      const read = async (offset, length) => {
        assert(offset >= 0 && offset + length <= size, `${exe.name}: invalid file offset`);
        const buffer = Buffer.alloc(length);
        const { bytesRead } = await file.read(buffer, 0, length, offset);
        assert.equal(bytesRead, length, `${exe.name}: truncated executable`);
        return buffer;
      };
      const dos = await read(0, 64);
      assert.equal(dos.toString('ascii', 0, 2), 'MZ', `${exe.name}: missing DOS header`);
      const peOffset = dos.readUInt32LE(0x3c);
      const pe = await read(peOffset, 96);
      assert.equal(pe.readUInt32LE(0), 0x4550, `${exe.name}: missing PE header`);
      assert.equal(pe.readUInt16LE(4), exe.machine, `${exe.name}: wrong CPU architecture`);
      assert.equal(pe.readUInt16LE(24), exe.magic, `${exe.name}: wrong PE format`);
      assert.equal(pe.readUInt16LE(92), 2, `${exe.name}: expected GUI executable`);

      // Godot 4.4 appends uint64 PCK size + GDPC magic after the embedded pack.
      const footer = await read(size - 12, 12);
      assert.equal(footer.toString('ascii', 8), 'GDPC', `${exe.name}: missing embedded PCK footer`);
      const pckSize = Number(footer.readBigUInt64LE(0));
      const pckStart = size - 12 - pckSize;
      assert(pckSize > 1024 * 1024 && pckStart > peOffset + 96, `${exe.name}: invalid embedded PCK size`);
      const pck = await read(pckStart, 100);
      assert.equal(pck.toString('ascii', 0, 4), 'GDPC', `${exe.name}: missing embedded PCK header`);
      assert.equal(pck.readUInt32LE(4), 2, `${exe.name}: unsupported PCK format`);
      assert.equal(pck.readUInt32LE(8), 4, `${exe.name}: expected Godot 4 resources`);
      assert(pck.readUInt32LE(96) > 0, `${exe.name}: empty resource directory`);
      console.log(`PASS: ${exe.name}: correct PE architecture, embedded PCK (${(pckSize / 1048576).toFixed(1)} MiB), no sidecar files`);
    } finally {
      await file.close();
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  await verifyWindowsBuild(resolve(process.argv[2] ?? 'dist-windows'));
}
