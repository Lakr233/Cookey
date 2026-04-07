import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildBinary, readVersion, targets } from "./build-targets.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const cliRoot = path.resolve(__dirname, "..");
const version = await readVersion(cliRoot);

const sourceDir = path.join(cliRoot, "pip");
const distRoot = path.join(cliRoot, "dist", "pip");
const packageOutDir = path.join(distRoot, "package");
const binOutDir = path.join(packageOutDir, "cookey_cli", "bin");

await rm(distRoot, { recursive: true, force: true });
await cp(sourceDir, packageOutDir, { recursive: true });
await mkdir(binOutDir, { recursive: true });

await writeFile(
  path.join(packageOutDir, "cookey_cli", "_version.py"),
  `__version__ = "${version}"\n`,
);

const pyprojectPath = path.join(packageOutDir, "pyproject.toml");
const pyproject = await readFile(pyprojectPath, "utf8");
await writeFile(pyprojectPath, pyproject.replace('version = "0.0.0-dev"', `version = "${version}"`));

for (const target of targets) {
  const output = path.join(
    binOutDir,
    `cookey-${target.platform}-${target.arch}${target.exe ? ".exe" : ""}`,
  );
  buildBinary({ cliRoot, output, target, version });
}

console.log(`Prepared pip package source in ${packageOutDir}`);
