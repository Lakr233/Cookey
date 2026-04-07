const fs = require("node:fs");
const path = require("node:path");

const TARGETS = {
  "darwin-x64": {
    platform: "darwin",
    arch: "x64",
    binaryName: "cookey",
    packageName: "@cookey/cookey-darwin-x64",
    packageDirName: "cookey-darwin-x64",
  },
  "darwin-arm64": {
    platform: "darwin",
    arch: "arm64",
    binaryName: "cookey",
    packageName: "@cookey/cookey-darwin-arm64",
    packageDirName: "cookey-darwin-arm64",
  },
  "linux-x64": {
    platform: "linux",
    arch: "x64",
    binaryName: "cookey",
    packageName: "@cookey/cookey-linux-x64",
    packageDirName: "cookey-linux-x64",
  },
  "linux-arm64": {
    platform: "linux",
    arch: "arm64",
    binaryName: "cookey",
    packageName: "@cookey/cookey-linux-arm64",
    packageDirName: "cookey-linux-arm64",
  },
};

function formatTarget(platform = process.platform, arch = process.arch) {
  return `${platform}-${arch}`;
}

function resolveTarget(platform = process.platform, arch = process.arch) {
  const key = formatTarget(platform, arch);
  const target = TARGETS[key];
  if (!target) {
    throw new Error(
      `Unsupported platform ${key}. Supported targets: ${Object.keys(TARGETS).join(", ")}`,
    );
  }
  return target;
}

function packageDirs(rootDir, target = resolveTarget()) {
  return [
    path.join(rootDir, "node_modules", "@cookey", target.packageDirName),
    path.resolve(rootDir, "..", target.packageDirName),
  ];
}

function resolveBinaryPath(rootDir, target = resolveTarget()) {
  for (const packageDir of packageDirs(rootDir, target)) {
    const candidate = path.join(packageDir, "bin", target.binaryName);
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }

  throw new Error(
    `Missing platform package ${target.packageName}. Reinstall @cookey/cookey for ${formatTarget(target.platform, target.arch)}.`,
  );
}

module.exports = {
  formatTarget,
  packageDirs,
  resolveBinaryPath,
  resolveTarget,
  TARGETS,
};
