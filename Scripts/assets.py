#!/usr/bin/env python3
"""Download or verify the pinned engine and model without third-party packages."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["download", "verify"])
    args = parser.parse_args()
    assets = json.loads((ROOT / "Scripts/assets.json").read_text())
    for asset in assets:
        target = ROOT / asset["path"]
        if target.is_file() and digest(target) == asset["sha256"]:
            print(f"Verified {asset['path']}")
            continue
        if args.command == "verify":
            parser.exit(1, f"Missing or modified asset: {asset['path']}. Run make download.\n")
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as output:
                temporary = Path(output.name)
                with urllib.request.urlopen(asset["url"], timeout=60) as response:
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
            if digest(temporary) != asset["sha256"]:
                raise ValueError(f"Checksum mismatch: {asset['path']}")
            temporary.chmod(0o644)
            temporary.replace(target)
            print(f"Downloaded {asset['path']}")
        except Exception as error:
            parser.exit(1, f"Download failed for {asset['path']}: {error}\n")
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
