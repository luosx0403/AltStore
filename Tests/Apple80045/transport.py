#!/usr/bin/env python3
"""Exercise the production Objective-C model's copy and serialization paths offline."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
model = root / "Dependencies/AltSign/AltSign/Model/Apple API"
with tempfile.TemporaryDirectory(prefix="altstore-anisette-transport-") as directory:
    binary = Path(directory) / "transport"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-framework", "Foundation", "-I", str(model),
                    str(model / "ALTAnisetteData.m"), str(Path(__file__).with_name("AnisetteTransport.m")), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
