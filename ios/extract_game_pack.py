#!/usr/bin/env python3
"""Extract the original 2.560 Godot pack from a local Windows ZIP."""
import argparse
import hashlib
from pathlib import Path
import struct
import zipfile

OUTPUT = Path(__file__).resolve().parent.parent / "local-data/Bawang.pck"
MAGIC = b"GDPC"
ORIGINAL_PACK_SHA256 = "2e6aa2198c0f94ae4da6a8a7aa4da855c24aadd1550fd9f7680d3dea5247a317"


def read_main_scene(project):
    if project[:4] != b"ECFG":
        raise ValueError("原版项目配置缺少 ECFG 标识。")

    count, = struct.unpack_from("<I", project, 4)
    cursor = 8
    for _ in range(count):
        key_size, = struct.unpack_from("<I", project, cursor)
        cursor += 4
        key = project[cursor:cursor + key_size]
        cursor += key_size
        value_size, = struct.unpack_from("<I", project, cursor)
        cursor += 4
        value = project[cursor:cursor + value_size]
        cursor += value_size
        if key == b"application/run/main_scene":
            kind, length = struct.unpack_from("<II", value)
            if kind != 4 or len(value) != 8 + ((length + 3) & ~3):
                raise ValueError("原版启动场景设置的格式不正确。")
            return value[8:8 + length].decode("utf-8")
    raise ValueError("原版项目没有设置启动场景。")


def original_pack(source):
    with zipfile.ZipFile(source) as archive:
        members = [
            member for member in archive.infolist()
            if not member.is_dir() and member.filename.lower().endswith(".exe")
        ]
        if len(members) != 1 or not 12 <= members[0].file_size <= 200_000_000:
            raise ValueError("原始压缩包应包含一个游戏程序。")
        executable = archive.read(members[0])

    length, footer = struct.unpack_from("<Q4s", executable, len(executable) - 12)
    start = len(executable) - 12 - length
    if not executable.startswith(b"MZ") or footer != MAGIC or start < 2 or length < 88:
        raise ValueError("找不到内嵌的 Godot 游戏包。")

    pack = bytearray(executable[start:-12])
    if struct.unpack_from("<4s4I", pack) != (MAGIC, 1, 3, 5, 3):
        raise ValueError("此项目需要 Godot 3.5.3 格式的原始游戏包。")

    count, = struct.unpack_from("<I", pack, 84)
    cursor = 88
    entries = []
    for _ in range(count):
        path_size, = struct.unpack_from("<I", pack, cursor)
        cursor += 4
        path = pack[cursor:cursor + path_size].rstrip(b"\0")
        cursor += path_size
        absolute_offset, size, checksum = struct.unpack_from("<QQ16s", pack, cursor)
        entries.append((cursor, path, absolute_offset - start, size, checksum))
        cursor += 32

    project = None
    for index, path, offset, size, checksum in entries:
        if offset < cursor or offset + size > len(pack):
            raise ValueError(f"游戏包内的文件超出范围（{path!r}）。")
        if hashlib.md5(memoryview(pack)[offset:offset + size]).digest() != checksum:
            raise ValueError(f"原始游戏文件校验失败（{path!r}）。")
        if path == b"res://project.binary":
            project = bytes(pack[offset:offset + size])
        # Godot 3 uses absolute offsets in a Windows export and relative offsets here.
        struct.pack_into("<Q", pack, index, offset)

    if hashlib.sha256(pack).hexdigest() != ORIGINAL_PACK_SHA256:
        raise ValueError("游戏包与已核验的 2.560 原版不同。")
    if project is None:
        raise ValueError("原始游戏缺少项目配置。")
    main_scene = read_main_scene(project)
    if not any(path == main_scene.encode("utf-8") for _, path, _, _, _ in entries):
        raise ValueError(f"原版游戏包缺少启动场景 {main_scene}。")
    return pack, count, main_scene


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="原版 2.560 Windows ZIP 的路径")
    args = parser.parse_args()
    try:
        pack, count, _ = original_pack(args.source)
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_bytes(pack)
        print(f"已核验 {count} 个文件并写入 {OUTPUT}")
    except (OSError, ValueError, struct.error, zipfile.BadZipFile) as error:
        parser.exit(1, f"提取失败：{error}\n")
