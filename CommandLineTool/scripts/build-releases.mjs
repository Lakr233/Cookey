import { createHash } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  buildBinary,
  readVersion,
  releaseAssetName,
  targets,
} from "./build-targets.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const cliRoot = path.resolve(__dirname, "..");
const version = await readVersion(cliRoot);
const releaseDir = path.join(cliRoot, "dist", "releases", `v${version}`);

await rm(releaseDir, { recursive: true, force: true });
await mkdir(releaseDir, { recursive: true });

const checksums = [];

for (const target of targets) {
  const asset = releaseAssetName(version, target);
  const output = path.join(releaseDir, asset);
  buildBinary({ cliRoot, output, target, version });

  const hash = createHash("sha256")
    .update(await readFile(output))
    .digest("hex");
  checksums.push(`${hash}  ${asset}`);
}

await writeFile(
  path.join(releaseDir, "SHASUMS256.txt"),
  `${checksums.join("\n")}\n`,
);
console.log(`Built cookey release artifacts in ${releaseDir}`);
