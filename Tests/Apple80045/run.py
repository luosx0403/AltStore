#!/usr/bin/env python3
"""Run the real authentication Swift source against offline protocol/crypto fixtures.

Only CAltSign imports and URLSession's ephemeral configuration are substituted.
The SRP/decryption and account-service fixtures do not test cryptography or Apple.
No credentials are used, and no network requests leave the process.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = root / "Dependencies/AltSign/AltSign/Sources/ALTAppleAPI+Authentication.swift"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, default=source, help="Alternative source for a regression control")
parser.add_argument("--client-platform", choices=["macos", "ios"], default="macos", help="Disable macOS-only fallback to exercise the iOS routing path on a Mac")
args = parser.parse_args()
source = args.source
implementation = source.read_text().replace("@_exported import CAltSign\n", "").replace("import CAltSign.Private\n", "")
implementation = implementation.replace("URLSessionConfiguration.ephemeral", "fixtureConfiguration()")
if args.client_platform == "ios":
    implementation = implementation.replace("#if os(macOS)", "#if false")
fixtures = Path(__file__).with_name("Fixtures.swift").read_text()
with tempfile.TemporaryDirectory(prefix="altstore-80045-") as directory:
    main = Path(directory) / "main.swift"
    binary = Path(directory) / "regression"
    main.write_text('let fixtureClientPlatform = "' + args.client_platform + '"\n' + fixtures + "\n" + implementation + "\nrunRegressionTests()\n")
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
