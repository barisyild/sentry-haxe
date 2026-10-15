#!/usr/bin/env python3
"""Build a self-contained desktop watchdog. Only pinned, hash-verified Node archives are used."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NODE_VERSION = "22.23.3"
# https://nodejs.org/dist/v22.23.3/SHASUMS256.txt
ARCHIVES = {
    "win-x64.zip": "2b0ff57b049cda1bbcea2240eec20467018713c1efe1f7360c2681859b90ed71",
    "darwin-arm64.tar.gz": "23b25245dcfb9af7262f8ff142e9e2e0af025368117329e7a7458a51e5922f53",
    "darwin-x64.tar.gz": "8a677b0219178efd6eb0e475457c4afb452b521a92f6e67845a73bd85727f2a8",
}

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def archive(suffix, cache):
    name = f"node-v{NODE_VERSION}-{suffix}"
    target = cache / name
    if not target.exists() or digest(target) != ARCHIVES[suffix]:
        print(f"Downloading {name}", flush=True)
        temporary = target.with_suffix(target.suffix + ".partial")
        try:
            with urllib.request.urlopen(f"https://nodejs.org/dist/v{NODE_VERSION}/{name}", timeout=60) as source, temporary.open("wb") as dest:
                shutil.copyfileobj(source, dest)
            if digest(temporary) != ARCHIVES[suffix]:
                raise RuntimeError(f"SHA-256 mismatch: {name}")
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    return target


def extract_runtime(suffix, output, cache):
    path = archive(suffix, cache)
    if suffix.endswith(".zip"):
        prefix = f"node-v{NODE_VERSION}-win-x64/"
        with zipfile.ZipFile(path) as package:
            (output / "node.exe").write_bytes(package.read(prefix + "node.exe"))
            (output / "NODE-LICENSE.txt").write_bytes(package.read(prefix + "LICENSE"))
    else:
        arch = suffix.removesuffix(".tar.gz")
        prefix = f"node-v{NODE_VERSION}-{arch}/"
        # Extract exactly these regular files, never arbitrary archive paths or symlinks.
        with tarfile.open(path, "r:gz") as package:
            for name, dest in [("bin/node", "node-" + arch.split("-")[1]), ("LICENSE", "NODE-LICENSE.txt")]:
                member = package.getmember(prefix + name)
                if not member.isfile():
                    raise RuntimeError(f"Unexpected archive entry: {member.name}")
                with package.extractfile(member) as stream, (output / dest).open("wb") as target:
                    shutil.copyfileobj(stream, target)
        (output / ("node-" + arch.split("-")[1])).chmod(0o755)


def verify(output, platform):
    manifest = json.loads((output / "manifest.json").read_text())
    expected = {"sentry-watchdog.cjs", "SENTRY-HAXE-LICENSE.txt", "NODE-LICENSE.txt"}
    expected.update(["node.exe"] if platform == "windows" else ["node-arm64", "node-x64"])
    if manifest["platform"] != platform or manifest["nodeVersion"] != NODE_VERSION or set(manifest["sha256"]) != expected:
        raise RuntimeError("Watchdog manifest does not match this build")
    for name in expected:
        file = output / name
        if not file.is_file() or digest(file) != manifest["sha256"][name]:
            raise RuntimeError(f"Missing or modified watchdog file: {name}")
        if platform == "macos" and name.startswith("node-") and not os.access(file, os.X_OK):
            raise RuntimeError(f"Watchdog runtime is not executable: {name}")
    print(f"Verified {platform} watchdog ({len(expected)} files, Node {NODE_VERSION})", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=["windows", "macos"])
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cache", type=Path, default=ROOT / "build/node-cache")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    if args.verify:
        verify(output, args.platform)
        return
    args.cache.mkdir(parents=True, exist_ok=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".watchdog-", dir=output.parent) as directory:
        staged = Path(directory)
        subprocess.run(["haxe", "-cp", str(ROOT / "src"), "-cp", str(ROOT / "tools/watchdog"), "-main", "Watchdog", "-js", str(staged / "sentry-watchdog.cjs"), "-D", "nodejs"], check=True)
        runtimes = ["win-x64.zip"] if args.platform == "windows" else ["darwin-arm64.tar.gz", "darwin-x64.tar.gz"]
        for runtime in runtimes:
            extract_runtime(runtime, staged, args.cache)
        shutil.copyfile(ROOT / "LICENSE", staged / "SENTRY-HAXE-LICENSE.txt")
        manifest = {"protocolVersion": 1, "nodeVersion": NODE_VERSION, "platform": args.platform,
                    "sha256": {file.name: digest(file) for file in sorted(staged.iterdir())}}
        (staged / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        verify(staged, args.platform)
        # Only replace our own generated watchdog directory, after the new package verifies.
        output.mkdir(parents=True, exist_ok=True)
        for file in staged.iterdir():
            shutil.copy2(file, output / file.name)
        for file in output.iterdir():
            if file.is_file() and file.name not in {*manifest["sha256"], "manifest.json"}:
                file.unlink()
    verify(output, args.platform)

if __name__ == "__main__":
    main()
