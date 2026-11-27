#!/usr/bin/env python3
"""Run native Godot integration checks in a unique, isolated user-data directory."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import uuid


def isolate_pack(path, name):
    pack = bytearray(path.read_bytes())
    cursor = 88
    for _ in range(struct.unpack_from("<I", pack, 84)[0]):
        size, = struct.unpack_from("<I", pack, cursor)
        resource = bytes(pack[cursor + 4:cursor + 4 + size]).rstrip(b"\0")
        cursor += 4 + size
        entry = cursor
        offset, size, _ = struct.unpack_from("<QQ16s", pack, cursor)
        cursor += 32
        if resource != b"res://project.binary":
            continue
        project = bytes(pack[offset:offset + size])
        setting_cursor = 8
        rewritten = bytearray(project[:8])
        for _ in range(struct.unpack_from("<I", project, 4)[0]):
            start = setting_cursor
            key_size, = struct.unpack_from("<I", project, setting_cursor)
            key = project[setting_cursor + 4:setting_cursor + 4 + key_size]
            setting_cursor += 4 + key_size
            header = project[start:setting_cursor]
            value_size, = struct.unpack_from("<I", project, setting_cursor)
            value = project[setting_cursor + 4:setting_cursor + 4 + value_size]
            setting_cursor += 4 + value_size
            if key == b"application/config/name":
                encoded = name.encode()
                value = struct.pack("<II", 4, len(encoded)) + encoded + bytes(-len(encoded) % 4)
            elif key in [b"display/window/size/width", b"display/window/size/test_width"]:
                value = struct.pack("<II", 2, 1024)
            elif key in [b"display/window/size/height", b"display/window/size/test_height"]:
                value = struct.pack("<II", 2, 600)
            rewritten.extend(header + struct.pack("<I", len(value)) + value)
        pack.extend(bytes(-len(pack) % 16))
        struct.pack_into("<QQ16s", pack, entry, len(pack), len(rewritten), hashlib.md5(rewritten).digest())
        pack.extend(rewritten)
        path.write_bytes(pack)
        return
    raise RuntimeError("Missing project.binary")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path, help="Godot 3.5.3 executable")
    parser.add_argument("--save", required=True, type=Path, help="Existing 2.560 campaign fixture; read only")
    parser.add_argument("--pack", type=Path, help="Original Mac Bawang.pck")
    parser.add_argument("--suite", choices=["2572", "2573", "2574", "2575", "all"], default="all")
    args = parser.parse_args()
    ios = Path(__file__).resolve().parents[1]
    source = args.pack or ios.parent / "local-data/Bawang.pck"
    fixture = args.save.resolve(strict=True)
    original_hash = hashlib.sha256(fixture.read_bytes()).hexdigest()
    spec = importlib.util.spec_from_file_location("prepare_qa", ios / "prepare_game_pack.py")
    prepare = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(prepare)
    name = "BawangFeatureQA-" + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="bawang-feature-qa-") as directory:
        output = Path(directory) / "Bawang.pck"
        prepare.prepare_game_pack(source, output)
        isolate_pack(output, name)
        environment = os.environ.copy()
        environment["BAWANG_QA_SAVE"] = str(fixture)
        environment["BAWANG_QA_NAME"] = name
        suites = ["2572", "2573", "2574", "2575"] if args.suite == "all" else [args.suite]
        for suite in suites:
            try:
                result = subprocess.run([
                    str(args.godot.resolve(strict=True)), "--no-window", "--main-pack", str(output),
                    "--script", str(ios / f"tests/features_{suite}.gd"),
                ], env=environment, capture_output=True, text=True, timeout=120)
            finally:
                assert hashlib.sha256(fixture.read_bytes()).hexdigest() == original_hash, "Fixture changed"
            log = result.stdout + result.stderr
            for line in log.splitlines():
                if "FEATURE_CHECK" in line or "FEATURE_RESULT" in line or "SCRIPT ERROR" in line or "Parse Error" in line:
                    print(line)
            if result.returncode or "FEATURE_RESULT" not in log or "SCRIPT ERROR" in log or "Parse Error" in log:
                print(log)
                raise SystemExit(result.returncode or 1)
        print("Read-only fixture unchanged; QA user data: " + name)


if __name__ == "__main__":
    main()
