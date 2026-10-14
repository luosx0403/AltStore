#!/usr/bin/env python3
"""Ad-hoc sign a locally built macOS app, signing nested code first.

No developer certificate, Apple account, or notarization credentials are used.
"""
from pathlib import Path
import subprocess
import sys

app = Path(sys.argv[1]).resolve(strict=True)
if app.suffix != ".app" or not (app / "Contents/Info.plist").is_file():
    raise SystemExit("Expected a macOS .app bundle")

# Framework archives and Finder copies can retain metadata that codesign rejects.
# Clean only the build output passed to this script, before signing nested code.
subprocess.run(["xattr", "-cr", str(app)], check=True)

macho_magic = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
files = []
bundles = []
for path in app.rglob("*"):
    if path.is_symlink():
        continue
    if path.is_file():
        with path.open("rb") as handle:
            if handle.read(4) in macho_magic:
                files.append(path)
    elif path.is_dir() and path.suffix in {".app", ".framework", ".xpc"}:
        bundles.append(path)

for path in sorted(files, key=lambda item: len(item.parts), reverse=True):
    subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(path)], check=True)
for path in sorted(bundles, key=lambda item: len(item.parts), reverse=True) + [app]:
    subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(path)], check=True)
