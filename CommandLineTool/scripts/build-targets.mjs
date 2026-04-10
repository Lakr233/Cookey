import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";

export const packageScope = "@cookey";
export const rootPackageName = `${packageScope}/cli`;
export const rootPackageDirName = "cli";

export const targets = [
  {
    goos: "darwin",
    goarch: "amd64",
    platform: "darwin",
    arch: "x64",
    exe: false,
  },
  {
    goos: "darwin",
    goarch: "arm64",
    platform: "darwin",
    arch: "arm64",
    exe: false,
  },
  {
    goos: "linux",
    goarch: "amd64",
    platform: "linux",
    arch: "x64",
    exe: false,
  },
  {
    goos: "linux",
    goarch: "arm64",
    platform: "linux",
    arch: "arm64",
    exe: false,
  },
];

export function formatTarget(target) {
  return `${target.platform}-${target.arch}`;
}

export function binaryName(target) {
  return target.exe ? "cookey.exe" : "cookey";
}

export function releaseAssetName(version, target) {
  return `cookey-v${version}-${target.platform}-${target.arch}${target.exe ? ".exe" : ""}`;
}

export function platformPackageDirName(target) {
  return `cli-${target.platform}-${target.arch}`;
}

export function platformPackageName(target) {
  return `${packageScope}/${platformPackageDirName(target)}`;
}

export async function readVersion(cliRoot) {
  const source = await readFile(
    path.join(cliRoot, "internal", "cli", "version.go"),
    "utf8",
  );
  const match = source.match(/Version = "([^"]+)"/);
  if (!match) {
    throw new Error("Unable to read CLI version from internal/cli/version.go");
  }
  return match[1];
}

export function buildBinary({ cliRoot, output, target, version }) {
  const ldflags = `-s -w -X cookey/internal/cli.Version=${version}`;
  const result = spawnSync(
    "go",
    ["build", "-trimpath", "-ldflags", ldflags, "-o", output, "."],
    {
      cwd: cliRoot,
      env: {
        ...process.env,
        CGO_ENABLED: "0",
        GOOS: target.goos,
        GOARCH: target.goarch,
      },
      stdio: "inherit",
    },
  );

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}
