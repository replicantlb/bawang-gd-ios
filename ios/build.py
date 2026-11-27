#!/usr/bin/env python3
"""Prepare and build the local iPhone port with Godot 3.6.3's device template."""

import argparse
from contextlib import contextmanager
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from zipfile import BadZipFile, ZipFile


HERE = Path(__file__).resolve().parent
PROJECT = HERE / "BawangIOS.xcodeproj"
TEMPLATE = Path.home() / "Library/Application Support/Godot/templates/3.6.3.stable/iphone.zip"
LIBRARY = "libgodot.iphone.release.xcframework"
PLUGINS = "void godot_ios_plugins_initialize() {}\nvoid godot_ios_plugins_deinitialize() {}"


@contextmanager
def open_ios_template(path):
    with ZipFile(path) as archive:
        if path.suffix.lower() == ".tpz":
            with (
                archive.open("templates/iphone.zip") as member,
                tempfile.TemporaryFile() as extracted,
            ):
                shutil.copyfileobj(member, extracted)
                with ZipFile(extracted) as template:
                    yield template
        else:
            yield archive


def install_engine(path):
    generated = HERE / "Generated"
    generated.mkdir(exist_ok=True)
    with open_ios_template(path) as template:
        members = {name.removeprefix("iphone/"): name for name in template.namelist()}
        framework = plistlib.loads(template.read(members[f"{LIBRARY}/Info.plist"]))
        device = next((
            entry for entry in framework["AvailableLibraries"]
            if entry["SupportedPlatform"] == "ios"
            and "SupportedPlatformVariant" not in entry
            and "arm64" in entry["SupportedArchitectures"]
        ), None)
        if device is None:
            raise ValueError("Godot 模板缺少 iPhone 真机所需的 ARM64 引擎。")
        library_member = f'{LIBRARY}/{device["LibraryIdentifier"]}/{device["LibraryPath"]}'
        source = template.read(members["godot_ios/dummy.cpp"]).decode("utf-8")
        if "$cpp_code" not in source:
            raise ValueError("iOS 模板启动文件格式不符，请使用 Godot 3.6.3 的官方导出模板。")
        with tempfile.TemporaryDirectory(dir=generated) as temp:
            staging = Path(temp)
            with template.open(members[library_member]) as library, (staging / "libgodot.a").open("wb") as output:
                shutil.copyfileobj(library, output)
            (staging / "EngineEntry.inc").write_text(source.replace("$cpp_code", PLUGINS), encoding="utf-8")
            # Godot 3.6.3 records its system frameworks in the archive's linker options.
            (staging / "Link.xcconfig").write_text(
                'OTHER_LDFLAGS = $(inherited) -ObjC -lc++ "$(SRCROOT)/Generated/libgodot.a"\n',
                encoding="utf-8",
            )
            for file in ("libgodot.a", "EngineEntry.inc", "Link.xcconfig"):
                (staging / file).replace(generated / file)


def require_ios_sdk():
    result = subprocess.run(
        ["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], capture_output=True, text=True,
    )
    major = result.stdout.strip().split(".")[0]
    if result.returncode or not major.isdecimal() or int(major) < 27:
        raise ValueError("需要完整的 Xcode 27 和 iOS 27 SDK。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", type=Path, help="Godot 3.6.3 的官方导出模板 .tpz 或 iphone.zip")
    parser.add_argument("--project-only", action="store_true", help="只生成工程并安装已提供的引擎")
    args = parser.parse_args()
    try:
        if not PROJECT.is_dir():
            subprocess.run(["xcodegen", "generate"], cwd=HERE, check=True)
        print(f"Xcode 工程已保存到 {PROJECT}", flush=True)

        if not args.project_only:
            require_ios_sdk()
        engine_files = ("libgodot.a", "EngineEntry.inc", "Link.xcconfig")
        engine_ready = all((HERE / "Generated" / name).is_file() for name in engine_files)
        if args.template is not None or (not args.project_only and not engine_ready):
            template = args.template or TEMPLATE
            if not template.is_file():
                raise ValueError("找不到 Godot 3.6.3 导出模板，请用 --template 指定 .tpz 或 iphone.zip。")
            install_engine(template)
            print("Godot iPhone 引擎已就绪。", flush=True)
        if not args.project_only:
            subprocess.run([
                "xcodebuild", "-project", str(PROJECT), "-scheme", "BawangIOS",
                "-configuration", "Debug", "-destination", "generic/platform=iOS",
                "-derivedDataPath", str(HERE.parent / "dist" / "iOS"),
                "CODE_SIGNING_ALLOWED=NO", "build",
            ], check=True)
    except (OSError, KeyError, ValueError, BadZipFile, subprocess.CalledProcessError) as error:
        parser.exit(1, f"iOS 构建失败：{error}\n")


if __name__ == "__main__":
    main()
