from __future__ import annotations

import os
import platform
import stat
import subprocess
import sys
from importlib import resources

TARGETS = {
    "darwin-x64": {
        "platform": "darwin",
        "arch": "x64",
        "binary_name": "cookey-darwin-x64",
    },
    "darwin-arm64": {
        "platform": "darwin",
        "arch": "arm64",
        "binary_name": "cookey-darwin-arm64",
    },
    "linux-x64": {
        "platform": "linux",
        "arch": "x64",
        "binary_name": "cookey-linux-x64",
    },
    "linux-arm64": {
        "platform": "linux",
        "arch": "arm64",
        "binary_name": "cookey-linux-arm64",
    },
}


def format_target(runtime_platform: str, runtime_arch: str) -> str:
    return f"{runtime_platform}-{runtime_arch}"


def detect_target() -> dict[str, str]:
    runtime_platform = sys.platform
    machine = platform.machine().lower()

    if runtime_platform == "darwin":
        runtime_arch = "arm64" if machine in {"arm64", "aarch64"} else "x64"
    elif runtime_platform == "linux":
        if machine in {"x86_64", "amd64"}:
            runtime_arch = "x64"
        elif machine in {"aarch64", "arm64"}:
            runtime_arch = "arm64"
        else:
            runtime_arch = machine
    else:
        runtime_arch = machine

    key = format_target(runtime_platform, runtime_arch)
    target = TARGETS.get(key)
    if not target:
        supported = ", ".join(sorted(TARGETS))
        raise RuntimeError(f"Unsupported platform {key}. Supported targets: {supported}")
    return target


def resolve_binary_path() -> str:
    target = detect_target()
    binary = resources.files("cookey_cli").joinpath("bin", target["binary_name"])
    if not binary.is_file():
        raise RuntimeError(
            f"Missing embedded binary {target['binary_name']} for "
            f"{format_target(target['platform'], target['arch'])}."
        )

    path = os.fspath(binary)
    mode = os.stat(path).st_mode
    if not mode & stat.S_IXUSR:
        os.chmod(path, mode | stat.S_IXUSR)
    return path


def main(argv: list[str] | None = None) -> int:
    binary_path = resolve_binary_path()
    completed = subprocess.run([binary_path, *(argv if argv is not None else sys.argv[1:])])
    if completed.returncode < 0:
        os.kill(os.getpid(), -completed.returncode)
    return completed.returncode
