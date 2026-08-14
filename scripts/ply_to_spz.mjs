#!/usr/bin/env node
/**
 * Convert a Gaussian splat .ply to .spz via Spark transcodeSpz
 * (copied from mine-world-arm web/scripts/ply_to_spz.mjs — docs/33 P0).
 *
 * Prereq: a node env with @sparkjsdev/spark installed (npm i @sparkjsdev/spark).
 * Usage:
 *   node scripts/ply_to_spz.mjs <in.ply> [out.spz]
 * Target: ≤25MB (see docs/33 §4); land output under godot/spike/web/media/splats/.
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { transcodeSpz, SplatFileType } from "@sparkjsdev/spark";

const src = process.argv[2];
const dstArg = process.argv[3];
if (!src) {
  console.error("usage: node scripts/ply_to_spz.mjs <in.ply> [out.spz]");
  process.exit(1);
}

const inPath = resolve(src);
const outPath = resolve(dstArg || inPath.replace(/\.ply$/i, ".spz"));
mkdirSync(dirname(outPath), { recursive: true });

const fileBytes = new Uint8Array(readFileSync(inPath));
console.log(`in  ${inPath} (${(fileBytes.length / 1e6).toFixed(1)} MB)`);

const t0 = Date.now();
const result = await transcodeSpz({
  inputs: [
    {
      fileBytes,
      pathOrUrl: inPath,
      fileType: SplatFileType.PLY,
    },
  ],
  maxSh: 0,
  fractionalBits: 12,
});
const outBytes = result.fileBytes;
const clippedCount = result.clippedCount ?? 0;
writeFileSync(outPath, Buffer.from(outBytes));
const mb = outBytes.byteLength / (1024 * 1024);
console.log(
  `out ${outPath} (${mb.toFixed(2)} MiB, ${Date.now() - t0}ms` +
    (clippedCount ? `, clipped=${clippedCount}` : "") +
    ")"
);
if (mb > 25) {
  console.warn(
    `WARN: ${mb.toFixed(1)} MiB > 25 MiB target (docs/27). Consider opacityThreshold / clip / downsample.`
  );
}
