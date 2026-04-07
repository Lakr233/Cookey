import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  platformPackageDirName,
  platformPackageName,
  rootPackageDirName,
  rootPackageName,
  targets,
} from "./build-targets.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const cliRoot = path.resolve(__dirname, "..");
const distRoot = path.join(cliRoot, "dist", "npm");

const options = parseArgs(process.argv.slice(2));

if (!options.skipBuild) {
  run("node", [path.join(cliRoot, "scripts", "build-npm-package.mjs")], { cwd: cliRoot });
}

for (const target of targets) {
  publishPackage(platformPackageName(target), path.join(distRoot, platformPackageDirName(target)));
}
publishPackage(rootPackageName, path.join(distRoot, rootPackageDirName));

function publishPackage(name, cwd) {
  const args = ["publish", "--access", "public"];
  if (options.dryRun) {
    args.push("--dry-run");
  }
  if (options.tag) {
    args.push("--tag", options.tag);
  }
  if (options.otp) {
    args.push("--otp", options.otp);
  }

  console.log(`Publishing ${name} from ${cwd}`);
  run("npm", args, { cwd });
}

function run(command, args, { cwd }) {
  const result = spawnSync(command, args, {
    cwd,
    stdio: "inherit",
    env: process.env,
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function parseArgs(argv) {
  const options = {
    dryRun: false,
    skipBuild: false,
    tag: "",
    otp: process.env.NPM_OTP ?? "",
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--dry-run") {
      options.dryRun = true;
      continue;
    }
    if (arg === "--skip-build") {
      options.skipBuild = true;
      continue;
    }
    if (arg === "--tag" && index + 1 < argv.length) {
      options.tag = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg === "--otp" && index + 1 < argv.length) {
      options.otp = argv[index + 1];
      index += 1;
      continue;
    }

    throw new Error(`Unknown argument: ${arg}`);
  }

  return options;
}
