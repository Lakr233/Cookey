#!/usr/bin/env node

const { spawn } = require("node:child_process");
const path = require("node:path");
const { resolveBinaryPath, formatTarget } = require("../lib/platform");

const packageRoot = path.resolve(__dirname, "..");

let binaryPath;
try {
  binaryPath = resolveBinaryPath(packageRoot);
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`cookey launcher error: ${message}`);
  process.exit(1);
}

if (process.platform !== "win32") {
  try {
    const mode = require("node:fs").statSync(binaryPath).mode & 0o777;
    if ((mode & 0o111) === 0) {
      require("node:fs").chmodSync(binaryPath, mode | 0o111);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`Failed to fix executable mode on ${binaryPath}: ${message}`);
    process.exit(1);
  }
}

const child = spawn(binaryPath, process.argv.slice(2), {
  stdio: "inherit",
});

child.on("error", (error) => {
  console.error(
    `Failed to start cookey binary for ${formatTarget(process.platform, process.arch)}: ${error.message}`,
  );
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 1);
});
