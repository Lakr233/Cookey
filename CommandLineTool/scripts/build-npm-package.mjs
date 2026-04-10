import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  binaryName,
  buildBinary,
  formatTarget,
  platformPackageDirName,
  platformPackageName,
  readVersion,
  rootPackageDirName,
  rootPackageName,
  targets,
} from "./build-targets.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const cliRoot = path.resolve(__dirname, "..");
const version = await readVersion(cliRoot);

const sourceDir = path.join(cliRoot, "npm");
const distRoot = path.join(cliRoot, "dist", "npm");
const rootOutDir = path.join(distRoot, rootPackageDirName);
const repository = {
  type: "git",
  url: "git+https://github.com/Lakr233/Cookey.git",
};
const publishConfig = {
  access: "public",
};

await rm(distRoot, { recursive: true, force: true });
await mkdir(distRoot, { recursive: true });

await buildRootPackage();
for (const target of targets) {
  await buildPlatformPackage(target);
}

console.log(`Prepared npm packages in ${distRoot}`);

async function buildRootPackage() {
  await cp(sourceDir, rootOutDir, { recursive: true });

  const pkgPath = path.join(rootOutDir, "package.json");
  const pkg = JSON.parse(await readFile(pkgPath, "utf8"));
  pkg.name = rootPackageName;
  pkg.version = version;
  pkg.publishConfig = publishConfig;
  pkg.repository = repository;
  pkg.optionalDependencies = Object.fromEntries(
    targets.map((target) => [platformPackageName(target), version]),
  );

  await writeFile(pkgPath, `${JSON.stringify(pkg, null, 2)}\n`);
}

async function buildPlatformPackage(target) {
  const outDir = path.join(distRoot, platformPackageDirName(target));
  const binDir = path.join(outDir, "bin");
  const output = path.join(binDir, binaryName(target));

  await mkdir(binDir, { recursive: true });
  buildBinary({ cliRoot, output, target, version });

  const pkg = {
    name: platformPackageName(target),
    version,
    description: `Prebuilt cookey CLI binary for ${formatTarget(target)}`,
    license: "MIT",
    publishConfig,
    repository,
    os: [target.platform],
    cpu: [target.arch],
    files: ["bin", "README.md"],
    keywords: ["cookey", "cli", "binary", target.platform, target.arch],
  };

  const readme = [
    `# ${platformPackageName(target)}`,
    "",
    `Prebuilt ${formatTarget(target)} binary for \`${rootPackageName}\`.`,
    "",
    "This package is usually installed automatically as an optional dependency.",
    "",
  ].join("\n");

  await writeFile(
    path.join(outDir, "package.json"),
    `${JSON.stringify(pkg, null, 2)}\n`,
  );
  await writeFile(path.join(outDir, "README.md"), readme);
}
