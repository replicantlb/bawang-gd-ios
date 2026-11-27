# 霸王的大陆 GD · iPhone 版

《霸王的大陆 GD》2.560 的横屏 iPhone 移植，当前构建号为 **2575**。游戏沿用电脑版的剧本、武将和战斗数据。左侧虚拟方向键移动，触屏上的 A 键确认。

## iPhone 版能做什么

- **自建和编辑武将** — 在「菜单 → 其他 → 内置修改 → 武将」调整技能，按内政、战场、白刃战或单挑等用途筛选。确定选择后在武将页点「保存」，再保存游戏进度。
- **试演一场战斗** — 在单机内政大地图的选城界面进入「菜单 → 其他 → 战斗试炼场」，指定双方武将、技能和装备。退出试炼即可回到原战役。
- **管理战役** — 在「其他」菜单集中查看俘虏及关押城，或查看、调整君主性格。性格影响 AI 的内政、外交与出征决策。
- **备份和迁移进度** — 在「其他 → 存档与补丁」导出存档或完整备份，然后在 iPhone「文件」中的游戏目录取出。导入前会保留备份。

技能评级、双面技能、阵型预览和存档恢复的具体操作见[玩法手册](docs/玩法.md)。

## 从源码构建

在 Mac 上准备 Python 3.10 或更新版本、完整的 Xcode 27 和 iOS 27 SDK。目标设备为安装 iOS 27 或更高版本的 iPhone。引擎使用 Godot 3.6.3 的官方 iOS 导出模板。[下载 Godot 3.6.3 Export Templates](https://godotengine.org/download/archive/3.6.3-stable/)

1. 准备自己持有的《霸王的大陆 GD 电脑版 2.560》原版 ZIP，在仓库根目录运行以下命令。路径替换为实际文件位置。脚本校验压缩包中的游戏数据，并将原始 Godot 包写入本地的 `local-data/Bawang.pck`。

   ```sh
   python3 ios/extract_game_pack.py "/path/to/霸王的大陆GD电脑版 2.560.zip"
   ```

2. 从导出模板读取 iPhone 的 arm64 引擎并构建应用。首次运行时指定下载的 `.tpz` 文件或模板内的 `iphone.zip`。

   ```sh
   python3 ios/build.py --template "/path/to/Godot_v3.6.3-stable_export_templates.tpz"
   ```

   该命令生成未签名应用 `dist/iOS/Build/Products/Debug-iphoneos/BawangIOS.app`。后续构建可直接运行 `python3 ios/build.py`。

3. 在 Xcode 打开 `ios/BawangIOS.xcodeproj`，选中 **BawangIOS → Signing & Capabilities**，选择自己的 Team。首次安装如遇标识已被占用，请填写自己可用的 Bundle Identifier。连接 iPhone，选择该设备并点击 **Run**。覆盖已有安装时须沿用原签名团队和 Bundle Identifier，建议先在游戏内导出备份。

原版游戏数据由持有人从自己的副本提供，限个人使用。仓库提供适配源码、Xcode 工程、测试和数据准备脚本。

## 回归检查

完成数据准备后，可用 macOS 版 Godot 3.5.3 和一份自备的 2.560 战役存档运行四组回归检查。测试脚本为每次运行创建独立游戏数据目录，并核对输入存档的 SHA-256。

```sh
python3 ios/tests/run_qa.py \
  --godot "/path/to/Godot.app/Contents/MacOS/Godot" \
  --save "/path/to/campaign.sav"
```

## English

This landscape iPhone port of *Bawang Dalu GD* 2.560 (build 2575) adds touch controls, officer and skill editing, battle trials, prisoner management, ruler personalities, and save import/export. Open the **Other** menu on the campaign map to access these features. Skill changes take effect after confirming them on the officer screen and saving the campaign.

To build, use macOS, Python 3.10+, Xcode 27 with the iOS 27 SDK, and the Godot 3.6.3 export templates. From the repository root, run the two commands above with your own original Windows 2.560 ZIP and the Godot template archive. Open `ios/BawangIOS.xcodeproj`, select your signing team and iPhone, and choose **Run**. The original game data is for personal use and must be supplied separately.
