#!/usr/bin/env python3
"""Rearchive legacy iPhone object files for the modern Apple linker.

Only the personal arm64 build uses these outputs. Object code is preserved;
libtool regenerates the symbol table and aligns each Mach-O archive member.
"""

import argparse
import hashlib
from pathlib import Path
import struct
import subprocess
import tempfile


def arm64_archive(path):
    data = path.read_bytes()
    if data.startswith(b"!<arch>\n"):
        return data
    # New lipo also rejects the old member alignment. Read the universal
    # container directly; only its arm64 slice is needed for this build.
    if data[:4] not in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        raise ValueError(f"Unknown universal archive: {path}")
    count = struct.unpack_from(">I", data, 4)[0]
    fat64 = data[:4] == b"\xca\xfe\xba\xbf"
    width = 32 if fat64 else 20
    slices = []
    for index in range(count):
        fields = struct.unpack_from(">IIQQII" if fat64 else ">IIIII", data, 8 + index * width)
        cpu, subtype, offset, size = fields[:4]
        if cpu == 0x0100000C and subtype & 0xFFFFFF == 0:
            if offset + size > len(data):
                raise ValueError("Truncated arm64 slice")
            slices.append(data[offset:offset + size])
    if len(slices) != 1:
        raise ValueError("Expected exactly one arm64 slice")
    return slices[0]


def members(data):
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("Not a thin archive")
    result = {}
    offset = 8
    while offset < len(data):
        header = data[offset:offset + 60]
        if len(header) != 60 or header[58:60] != b"`\n":
            raise ValueError(f"Invalid archive header at {offset}")
        size = int(header[48:58])
        start = offset + 60
        end = start + size
        if end > len(data):
            raise ValueError("Truncated archive member")
        name = header[:16].decode("ascii").strip()
        if name.startswith("#1/"):
            length = int(name[3:])
            name = data[start:start + length].rstrip(b"\0").decode("ascii")
            start += length
        else:
            name = name.rstrip("/")
        if name.endswith(".o"):
            if Path(name).name != name or name in result:
                raise ValueError(f"Unsafe or duplicate object name: {name}")
            payload = data[start:end]
            if payload[:4] != b"\xcf\xfa\xed\xfe":
                raise ValueError(f"Expected 64-bit Mach-O object: {name}")
            if struct.unpack_from("<I", payload, 4)[0] != 0x0100000C:
                raise ValueError(f"Expected arm64 object: {name}")
            result[name] = (payload, start)
        elif not name.startswith("__.SYMDEF"):
            raise ValueError(f"Unexpected archive member: {name}")
        offset = end + size % 2
    if not result:
        raise ValueError("Archive has no objects")
    return result


def normalize(path):
    original = members(arm64_archive(path))
    with tempfile.TemporaryDirectory(prefix="altstore-archive-", dir=path.parent) as directory:
        scratch = Path(directory)
        objects = []
        for name, (payload, _) in original.items():
            obj = scratch / name
            obj.write_bytes(payload)
            objects.append(str(obj))
        output = scratch / "aligned.a"
        subprocess.run(["xcrun", "libtool", "-static", "-o", str(output), *objects], check=True)
        rebuilt = members(output.read_bytes())
        if original.keys() != rebuilt.keys():
            raise ValueError("Object membership changed")
        for name, (payload, offset) in rebuilt.items():
            if payload != original[name][0] or offset % 8:
                raise ValueError(f"Object changed or unaligned: {name}")
        arch = subprocess.check_output(["xcrun", "lipo", "-archs", str(output)], text=True).strip()
        if arch != "arm64":
            raise ValueError(f"Unexpected output architecture: {arch}")
        output.chmod(path.stat().st_mode & 0o777)
        output.replace(path)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        print(f"{path.name}: {len(rebuilt)} unchanged arm64 objects, 8-byte aligned, SHA256 {digest}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    for relative in ("Dependencies/libcurl/libcurl.a", "Dependencies/fragmentzip/libfragmentzip.a"):
        normalize((args.repo / relative).resolve())
