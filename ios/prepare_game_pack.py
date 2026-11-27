#!/usr/bin/env python3
"""Adapt the local Godot 3.5.3 game pack for the iPhone app."""

import hashlib
from pathlib import Path
import re
import struct
import sys


DATA_MANAGER = b"res://script/Data_Manager.gdc"
ORIGINAL_SCRIPT_MD5 = bytes.fromhex("825e12aca51ae176f3870c6d0d9620d3")
PROJECT_SETTINGS = b"res://project.binary"
VIRTUAL_KEYS = b"res://windows/virtukey.tscn"
DIRECTION_PAD = b"res://ios_direction_pad.gd"
OFFICER_EDITOR = b"res://scene/scene_title/Diy_Actor_Skill.tscn"
OFFICER_PICKER = b"res://ios_officer_picker.gd"
CHEAT_ACTOR = b"res://cheat/actor.tscn"
CHEAT_ACTOR_SCRIPT = b"res://ios_cheat_actor.gd"
EDITED_SKILLS = b"res://ios_edited_skills.gd"
OTHERS_MENU = b"res://windows/menu/pnlOthers.tscn"
CHEAT_PANEL = b"res://cheat/cheater.tscn"
SCENE_MANAGER = b"res://scene/manager/Scene_Manager.tscn"
FORMATION_MENU = b"res://windows/lsc_image_menu.tscn"


def use_ios_skill_helper(settings):
    if settings[:4] != b"ECFG":
        raise ValueError("游戏包中的项目设置格式不符。")

    def encode_string(value):
        return struct.pack("<II", 4, len(value)) + value + bytes(-len(value) % 4)

    count, = struct.unpack_from("<I", settings, 4)
    cursor = 8
    for _ in range(count):
        key_size, = struct.unpack_from("<I", settings, cursor)
        key = settings[cursor + 4:cursor + 4 + key_size]
        length_offset = cursor + 4 + key_size
        value_size, = struct.unpack_from("<I", settings, length_offset)
        value_offset = length_offset + 4
        cursor = value_offset + value_size
        if key != b"autoload/SkillHelper":
            continue
        if settings[value_offset:cursor] != encode_string(b"*res://script/skill_system/Skill_Helper.gd"):
            raise ValueError("游戏包中的 SkillHelper 自加载脚本与 2.560 版不符。")
        replacement = encode_string(b"*" + EDITED_SKILLS)
        return settings[:length_offset] + struct.pack("<I", len(replacement)) + replacement + settings[cursor:]
    raise ValueError("游戏包缺少 SkillHelper 自加载设置。")


def replace_string_setting(settings, target, value):
    cursor = 8
    for _ in range(struct.unpack_from("<I", settings, 4)[0]):
        key_size, = struct.unpack_from("<I", settings, cursor)
        key = settings[cursor + 4:cursor + 4 + key_size]
        length_offset = cursor + 4 + key_size
        value_size, = struct.unpack_from("<I", settings, length_offset)
        value_offset = length_offset + 4
        cursor = value_offset + value_size
        if key == target:
            encoded = struct.pack("<II", 4, len(value)) + value + bytes(-len(value) % 4)
            return settings[:length_offset] + struct.pack("<I", len(encoded)) + encoded + settings[cursor:]
    raise ValueError(f"游戏包缺少设置 {target.decode()}。")


def use_ios_autoloads(settings):
    settings = use_ios_skill_helper(settings)
    settings = replace_string_setting(settings, b"autoload/DataManager", b"*res://ios_data_manager.gd")
    settings = replace_string_setting(settings, b"autoload/Global", b"*res://ios_global.gd")
    for key, value in [
        (b"autoload/MobileSkillRatings", b"*res://ios_skill_ratings.gd"),
        (b"autoload/TrialSession", b"*res://ios_trial_session.gd"),
        (b"autoload/PrisonViewState", b"*res://ios_prison_view_state.gd"),
        (b"autoload/MobileKeyboard", b"*res://ios_keyboard_manager.gd"),
        (b"autoload/RulerPersonalities", b"*res://ios_ruler_personalities.gd"),
    ]:
        encoded = struct.pack("<II", 4, len(value)) + value + bytes(-len(value) % 4)
        count, = struct.unpack_from("<I", settings, 4)
        settings = (
            settings[:4] + struct.pack("<I", count + 1) + settings[8:]
            + struct.pack("<I", len(key)) + key + struct.pack("<I", len(encoded)) + encoded
        )
    return settings


def use_writable_data_path(script):
    if hashlib.md5(script).digest() != ORIGINAL_SCRIPT_MD5:
        raise ValueError("游戏包中的存档脚本与 2.560 版不符。")

    # GDScript v13 identifier, line table and function body offsets for this exact script.
    identifier_offset = 7832
    identifier_size = 20
    line_table_offset = 16212
    body_start, body_end = 53190, 53378
    first_body_token, body_end_token = 8788, 8865

    # The original entry is get_executable_path, used only by get_common_path.
    identifier = b"get_user_data_dir".ljust(identifier_size, b"\0")
    script[identifier_offset:identifier_offset + identifier_size] = bytes(
        byte ^ 0xB6 for byte in identifier
    )

    def token_with_value(token, value):
        return struct.pack("<I", (value << 8) | 0x80 | token)

    # Replace get_common_path's body with:
    #     return OS.get_user_data_dir() + "/sgz/"
    body = b"".join([
        token_with_value(89, 1),  # newline, one indent
        bytes([46]),              # return
        token_with_value(1, 442),  # OS
        bytes([84]),              # .
        token_with_value(1, 444),  # get_user_data_dir
        bytes([80, 81, 16]),      # () +
        token_with_value(2, 201),  # "/sgz/"
    ])
    body_token_count = 9
    token_delta = body_token_count - (body_end_token - first_body_token)

    # Retain the first body line and shift every later line to its new token index.
    line_count, token_count = struct.unpack_from("<II", script, 16)
    lines = bytearray()
    for index in range(line_count):
        token, source_line = struct.unpack_from("<II", script, line_table_offset + index * 8)
        if first_body_token < token < body_end_token:
            continue
        if token >= body_end_token:
            token += token_delta
        lines += struct.pack("<II", token, source_line)

    struct.pack_into("<II", script, 16, len(lines) // 8, token_count + token_delta)
    tokens_offset = line_table_offset + line_count * 8
    return script[:line_table_offset] + lines + script[tokens_offset:body_start] + body + script[body_end:]


def use_ios_direction_pad(scene):
    old_path = b'path="res://windows/virtukey.gd"'
    if scene.count(old_path) != 1:
        raise ValueError("无法定位游戏包中的虚拟按键脚本。")
    scene = scene.replace(old_path, b'path="' + DIRECTION_PAD + b'"', 1)
    # Keep the existing hit shapes and layout. The iOS script owns the directional actions.
    scene, removed = re.subn(
        rb'(?m)^\[connection signal="(?:pressed|released)" from="VirtualKey/con_analog/'
        rb'btn(?:Up|Down|(?:Left|Right)(?:Up|Down)?)"[^\n]*\]\n',
        b"", scene,
    )
    if removed != 16:
        raise ValueError("游戏包中的方向键连接与 2.560 版不符。")
    scene, removed = re.subn(
        rb'(?m)^\[connection signal="(?:pressed|released)" from="VirtualKey/con_btnemu_'
        rb'(?:A|B|X|Y|select|start)/btnemu_(?:A|B|X|Y|select|start)"[^\n]*\]\n',
        b"", scene,
    )
    if removed != 12:
        raise ValueError("游戏包中的功能键连接与 2.560 版不符。")
    resource_id = max(int(value) for value in re.findall(rb'\[ext_resource [^\n]* id=(\d+)\]', scene)) + 1
    external = b'[ext_resource path="res://ios_battle_hints.gd" type="Script" id=%d]\n' % resource_id
    last_external = list(re.finditer(rb'\[ext_resource [^\n]*\]\n', scene))[-1].end()
    scene = scene[:last_external] + external + scene[last_external:]
    scene = re.sub(rb'load_steps=(\d+)', lambda match: b'load_steps=%d' % (int(match[1]) + 1), scene, count=1)
    node = b'\n[node name="BattleHints" type="Control" parent="."]\nmouse_filter = 2\nscript = ExtResource( %d )\n\n' % resource_id
    connection = scene.find(b"[connection ")
    scene = scene[:connection] + node + scene[connection:] if connection >= 0 else scene + node
    return scene


def append_resource(pack, entry, content):
    pack.extend(bytes(-len(pack) % 16))
    struct.pack_into("<QQ16s", pack, entry, len(pack), len(content), hashlib.md5(content).digest())
    pack.extend(content)


def replace_scene_script(scene, original, replacement):
    old_path = b'path="' + original + b'"'
    if scene.count(old_path) != 1:
        raise ValueError(f"无法定位游戏包中的场景脚本 {original.decode()}。")
    return scene.replace(old_path, b'path="' + replacement + b'"', 1)


def prepare_game_pack(source, destination):
    pack = bytearray(source.read_bytes())
    if struct.unpack_from("<4s4I", pack) != (b"GDPC", 1, 3, 5, 3):
        raise ValueError("需要本机 Mac 版的 Godot 3.5.3 游戏包。")

    file_count, = struct.unpack_from("<I", pack, 84)
    cursor = 88
    index = {}
    for _ in range(file_count):
        name_size, = struct.unpack_from("<I", pack, cursor)
        name_start = cursor + 4
        index_entry = name_start + name_size
        name = bytes(pack[name_start:index_entry]).rstrip(b"\0")
        cursor = index_entry + 32
        index[name] = index_entry

    local_scripts = {
        DIRECTION_PAD: "DirectionPad.gd",
        OFFICER_PICKER: "OfficerPicker.gd",
        CHEAT_ACTOR_SCRIPT: "CheatActor.gd",
        EDITED_SKILLS: "EditedSkills.gd",
        b"res://ios_picker_panel.gd": "PickerPanel.gd",
        b"res://ios_skill_picker.gd": "SkillPicker.gd",
        b"res://ios_skill_catalog.gd": "SkillCatalog.gd",
        b"res://ios_others_menu.gd": "OthersMenu.gd",
        b"res://ios_storage_service.gd": "StorageService.gd",
        b"res://ios_storage_manager.gd": "StorageManager.gd",
        b"res://ios_battle_hints.gd": "BattleHints.gd",
        b"res://ios_cheat_panel.gd": "CheatPanel.gd",
        b"res://ios_mobile_layout.gd": "MobileLayout.gd",
        b"res://ios_skill_ratings.gd": "SkillRatings.gd",
        b"res://ios_rating_badge.gd": "RatingBadge.gd",
        b"res://ios_skill_ratings.json": "SkillRatings.json",
        b"res://ios_skill_defaults.gd": "SkillDefaults.gd",
        b"res://ios_data_manager.gd": "DataManager.gd",
        b"res://ios_cheat_skill_picker.gd": "CheatSkillPicker.gd",
        b"res://ios_equipment_skill_inspector.gd": "EquipmentSkillInspector.gd",
        b"res://ios_global.gd": "Global.gd",
        b"res://ios_scene_manager.gd": "SceneManager.gd",
        b"res://ios_trial_session.gd": "TrialSession.gd",
        b"res://ios_trial_arena.gd": "TrialArena.gd",
        b"res://ios_prison_roster.gd": "PrisonRoster.gd",
        b"res://ios_prison_view_state.gd": "PrisonViewState.gd",
        b"res://ios_keyboard_manager.gd": "KeyboardManager.gd",
        b"res://ios_personality_ai_patches.gd": "PersonalityAIPatches.gd",
        b"res://ios_ruler_personalities.gd": "RulerPersonalities.gd",
        b"res://ios_ruler_personalities.json": "RulerPersonalities.json",
        b"res://ios_ruler_personality_panel.gd": "RulerPersonalityPanel.gd",
        b"res://ios_solo_attack.gd": "SoloAttack.gd",
        b"res://ios_solo_crazy_attack.gd": "SoloCrazyAttack.gd",
        b"res://ios_formation_menu.gd": "FormationMenu.gd",
    }
    required_resources = {DATA_MANAGER, PROJECT_SETTINGS, VIRTUAL_KEYS, OFFICER_EDITOR, CHEAT_ACTOR, OTHERS_MENU, CHEAT_PANEL, SCENE_MANAGER, FORMATION_MENU}
    if not required_resources <= index.keys() or index.keys() & local_scripts.keys():
        raise ValueError("原始游戏包中的 iOS 适配资源与 2.560 版不符。")

    def read_resource(name):
        offset, size, checksum = struct.unpack_from("<QQ16s", pack, index[name])
        content = pack[offset:offset + size]
        if len(content) != size or hashlib.md5(content).digest() != checksum:
            raise ValueError(f"无法校验游戏资源 {name.decode()}。")
        return content

    replacements = {
        DATA_MANAGER: use_writable_data_path(read_resource(DATA_MANAGER)),
        PROJECT_SETTINGS: use_ios_autoloads(read_resource(PROJECT_SETTINGS)),
        VIRTUAL_KEYS: use_ios_direction_pad(read_resource(VIRTUAL_KEYS)),
        OFFICER_EDITOR: replace_scene_script(
            read_resource(OFFICER_EDITOR), b"res://scene/scene_title/Diy_Actor_Skill.gd", OFFICER_PICKER,
        ),
        CHEAT_ACTOR: replace_scene_script(
            read_resource(CHEAT_ACTOR), b"res://cheat/actor.gd", CHEAT_ACTOR_SCRIPT,
        ),
        OTHERS_MENU: replace_scene_script(
            read_resource(OTHERS_MENU), b"res://windows/menu/pnlOthers.gd", b"res://ios_others_menu.gd",
        ),
        CHEAT_PANEL: replace_scene_script(
            read_resource(CHEAT_PANEL), b"res://cheat/cheater.gd", b"res://ios_cheat_panel.gd",
        ),
        SCENE_MANAGER: replace_scene_script(
            read_resource(SCENE_MANAGER), b"res://scene/manager/Scene_Manager.gd", b"res://ios_scene_manager.gd",
        ),
        FORMATION_MENU: replace_scene_script(
            read_resource(FORMATION_MENU), b"res://windows/lsc_image_menu.gd", b"res://ios_formation_menu.gd",
        ),
    }
    for path, filename in local_scripts.items():
        replacements[path] = Path(__file__).with_name(filename).read_bytes()

    # Godot 3 pack entries store absolute offsets. Grow the directory by a 16-byte multiple
    # so every existing payload keeps its alignment.
    new_entries = bytearray()
    added = {}
    for name in local_scripts:
        path = name + bytes(-len(name) % 4)
        new_entries.extend(struct.pack("<I", len(path)) + path)
        added[name] = cursor + len(new_entries)
        new_entries.extend(bytes(32))
    new_entries.extend(bytes(-len(new_entries) % 16))
    for entry in index.values():
        offset, = struct.unpack_from("<Q", pack, entry)
        struct.pack_into("<Q", pack, entry, offset + len(new_entries))
    pack[cursor:cursor] = new_entries
    index.update(added)
    struct.pack_into("<I", pack, 84, file_count + len(added))

    for name, content in replacements.items():
        append_resource(pack, index[name], content)
    destination.write_bytes(pack)


if __name__ == "__main__":
    try:
        prepare_game_pack(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError, struct.error) as error:
        sys.exit(f"error: 生成 iOS 游戏包失败：{error}")
