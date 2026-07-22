#!/usr/bin/env node

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const [sourcePath, outputPath] = process.argv.slice(2);

if (!sourcePath || !outputPath) {
  console.error('usage: create-icns.js /path/to/AppIcon-1024.png /path/to/App.icns');
  process.exit(1);
}

const representations = [
  { type: 'icp4', filename: 'icon_16x16.png', size: 16 },
  { type: 'icp5', filename: 'icon_32x32.png', size: 32 },
  { type: 'icp6', filename: 'icon_32x32@2x.png', size: 64 },
  { type: 'ic07', filename: 'icon_128x128.png', size: 128 },
  { type: 'ic08', filename: 'icon_256x256.png', size: 256 },
  { type: 'ic09', filename: 'icon_512x512.png', size: 512 },
  { type: 'ic10', filename: 'icon_512x512@2x.png', size: 1024 },
];

function pngSize(data, filename) {
  const signature = data.subarray(0, 8).toString('hex');
  if (signature !== '89504e470d0a1a0a' || data.subarray(12, 16).toString('ascii') !== 'IHDR') {
    throw new Error(`${filename} is not a PNG file`);
  }

  return {
    width: data.readUInt32BE(16),
    height: data.readUInt32BE(20),
  };
}

const sourceData = fs.readFileSync(sourcePath);
const sourceDimensions = pngSize(sourceData, sourcePath);
if (sourceDimensions.width !== 1024 || sourceDimensions.height !== 1024) {
  throw new Error(
    `Source icon must be 1024x1024, got ${sourceDimensions.width}x${sourceDimensions.height}`,
  );
}

const iconsetDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'TickTime-iconset-'));

try {
  const chunks = representations.map(({ type, filename, size }) => {
    const inputPath = path.join(iconsetDirectory, filename);
    execFileSync(
      '/usr/bin/sips',
      ['--resampleHeightWidth', String(size), String(size), sourcePath, '--out', inputPath],
      { stdio: 'ignore' },
    );

    const data = fs.readFileSync(inputPath);
    const dimensions = pngSize(data, filename);

    if (dimensions.width !== size || dimensions.height !== size) {
      throw new Error(
        `${filename} must be ${size}x${size}, got ${dimensions.width}x${dimensions.height}`,
      );
    }

    const chunk = Buffer.allocUnsafe(8 + data.length);
    chunk.write(type, 0, 4, 'ascii');
    chunk.writeUInt32BE(chunk.length, 4);
    data.copy(chunk, 8);
    return chunk;
  });

  const totalSize = 8 + chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const header = Buffer.allocUnsafe(8);
  header.write('icns', 0, 4, 'ascii');
  header.writeUInt32BE(totalSize, 4);

  fs.writeFileSync(outputPath, Buffer.concat([header, ...chunks], totalSize));
} finally {
  fs.rmSync(iconsetDirectory, { recursive: true, force: true });
}
