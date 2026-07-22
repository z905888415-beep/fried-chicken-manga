# Kira APK 构建与 LDPlayer 装机指引

> 本指引针对本机（Windows）操作。沙箱环境无 Android SDK / 无法启动 LDPlayer GUI，故构建与装机需在你本机完成。
> 仓库：`D:\AI\kira-source`
> 模拟器：`D:\leidian\LDPlayer14\dnplayer.exe`

## 0. 前置检查

- 已安装 Flutter SDK（本机通常在 `C:\Users\1\flutter`，请确认 `flutter --version` 可用；若不在 PATH，先 `set PATH=%PATH%;C:\Users\1\flutter\bin`）。
- 已安装 Android SDK 且 `adb` 可用（LDPlayer 自带 `adb.exe`，见第 3 步，无需单独装）。
- 仓库依赖已装：`cd D:\AI\kira-source && flutter pub get`。

## 1. 构建 Release APK

```bat
cd /d D:\AI\kira-source
flutter build apk --release --target-platform android-arm64
```

- 产物路径：`D:\AI\kira-source\build\app\outputs\flutter-apk\app-release.apk`
- 如需按 ABI 拆分（体积更小、推荐）：`flutter build apk --release --split-per-abi`
  - 产物：`app-armeabi-v7a-release.apk` / `app-arm64-v8a-release.apk` / `app-x86_64-release.apk`
  - 真机/模拟器多为 arm64-v8a，装 `app-arm64-v8a-release.apk` 即可。

## 2. 启动 LDPlayer 模拟器

双击 `D:\leidian\LDPlayer14\dnplayer.exe` 启动（默认实例 0）。
首次使用建议在「多开器」里确认实例已创建并运行。

## 3. 通过 LDPlayer 自带 adb 装机

LDPlayer 自带 `adb.exe`，位于模拟器目录下，免去单独配置：

```bat
cd /d D:\leidian\LDPlayer14
:: 连接模拟器（默认实例端口 5555；多开实例通常为 5555 + 序号）
adb connect 127.0.0.1:5555
:: 确认设备在线
adb devices
:: 安装 APK
adb install "D:\AI\kira-source\build\app\outputs\flutter-apk\app-release.apk"
```

- 若 `adb connect` 失败：在 LDPlayer「设置 → 关于本机/高级」查看 ADB 调试端口，或用多开器查看实例端口（常见 5555 / 5557 / 5559…）。
- 覆盖安装加 `-r`：`adb install -r "...app-release.apk"`。
- 装完后模拟器桌面会出现 Kira 图标，点击启动。

## 4. 真机验收清单（建议逐项核对）

本轮交付重点：UI 统一 + 防御式解析（BUG-01 闭环）。建议验收：

1. **首页 / 排行 / 推荐**：列表正常加载；下拉/上拉加载更多时若网络异常，应出现 SnackBar 错误提示 + 重试，而非静默空白。
2. **畸形接口（核心）**：若某个漫画源返回畸形主数据（非列表），页面应显示 `ErrorView` 错误态并可重试，而非崩溃或空白（BUG-01 已闭环）。
3. **浏览历史 / 书架**：`getBrowseHistory` 现在对畸形响应会显错而非静默清空。
4. **UI 一致性**：卡片圆角统一为 22、内容区最大宽度 900 居中、间距/图标按钮尺寸统一（见 `lib/utils/theme_tokens.dart`、`layout.dart`、`format.dart`）。
5. **评论接口**：`api.copy2000.online` 评论接口沙箱返回 HTML，需在真机复验；T04 已确保该路径畸形时显错而非崩溃。

## 5. 常用命令速查

```bat
:: 重新构建并安装
cd /d D:\AI\kira-source && flutter build apk --release --split-per-abi
adb connect 127.0.0.1:5555
adb install -r "D:\AI\kira-source\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"

:: 清缓存重装（调试用）
adb uninstall kira
adb install "D:\AI\kira-source\build\app\outputs\flutter-apk\app-release.apk"

:: 看运行日志
adb logcat -s flutter
```
