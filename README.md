<h1 align="center">🍗 炸鸡腿漫画</h1>

<p align="center">
  <strong>基于 Flutter 的耽美 / BL 漫画阅读器</strong><br/>
  毛玻璃 UI · 分类筛选 · 离线下载 · AI 章节总结
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.44+-02569B?logo=flutter&logoColor=white"/>
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart&logoColor=white"/>
  <img alt="Platform" src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white"/>
  <img alt="License" src="https://img.shields.io/github/license/caolib/kira"/>
  <img alt="Stars" src="https://img.shields.io/github/stars/caolib/kira"/>
</p>

---

## 📖 简介

**炸鸡腿漫画**是一款专注于 **耽美 / BL** 题材的第三方漫画阅读器，基于开源项目 [kira](https://github.com/caolib/kira) 深度定制开发。

应用采用 **毛玻璃（Glassmorphism）** 设计风格，提供流畅的漫画浏览与阅读体验。数据来源于 [拷贝漫画](https://www.mangacopy.com/)，所有分类均严格限定在耽美 / BL 范围内。

## ✨ 功能特性

### 📚 漫画浏览
- **12 个耽美子分类**：全部、校园、都市、娱乐圈、ABO、重生、穿越、甜宠、虐恋、年下、黑道、高H
- **最热 / 最新排序**：服务端排序 + 本地关键词过滤，确保分类与排序同时生效
- **无限滚动加载**：下滑自动加载下一页，直到分类读完
- **毛玻璃搜索框**：点击即跳转全局搜索

### 📖 阅读器
- **双模式**：纵向滚动 / 横向翻页，自由切换
- **手势控制**：音量键翻页、点击切换工具栏
- **进度记忆**：自动保存阅读进度，下次打开继续阅读
- **章节评论**：在线阅读时查看和发表评论

### 🤖 AI 功能
- **章节 AI 总结**：接入任意 OpenAI 兼容接口，一键生成章节摘要
- **思考过程展示**：支持显示 AI 推理过程

### 💾 书架管理
- **最近阅读**：放大卡片 + 列表，一眼看到上次阅读进度
- **本地收藏**：收藏漫画显示实际阅读章节
- **离线下载**：缓存漫画章节，无网也能看

### 🎨 界面与体验
- **毛玻璃 UI**：全局 Glassmorphism 设计风格
- **深色 / 浅色主题**：跟随系统或手动切换
- **自定义主题色**：支持取色器自定义
- **多线路切换**：内置 2 条 API 线路，支持延迟测试自动择优
- **启动恢复**：记住上次浏览的页面

## 📸 截图

| 首页 | 书架 |
|:---:|:---:|
| 分类筛选 + 毛玻璃搜索框 | 最近阅读 + 收藏 + 下载 |
| 最热/最新一键切换 | 阅读进度实时同步 |

| 阅读器 | 我的 |
|:---:|:---:|
| 滚动/翻页双模式 | 网络节点 + 主题设置 |
| AI 章节总结 | 浏览历史 + 下载管理 |

## 🚀 快速开始

### 环境要求

- **Flutter** ≥ 3.44
- **Dart** ≥ 3.12
- **Java** 17+
- **Android SDK** 36+

### 克隆与运行

```bash
git clone https://github.com/youfengknight/Android-Code-Skills.git
cd kira-source

# 拉取依赖
flutter pub get

# 查看可用设备
flutter devices

# 运行（选择 Android 设备或模拟器）
flutter run -d <设备ID>
```

### 构建 APK

```bash
flutter build apk --release --target-platform android-arm64
```

构建产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

### AI 功能配置（可选）

如需使用 AI 章节总结功能，在项目根目录创建 `.env` 文件：

```env
# 参考 .env.example
```

在应用内「我的 → 主题设置」中配置 AI 接口地址和 API Key。

## 🏗️ 项目结构

```
lib/
├── api/                    # 网络层
│   ├── api_client.dart     # API 客户端（多线路 + 自动重试）
│   ├── copymanga_source_adapter.dart  # 耽美分类排序适配器
│   ├── manga/              # 漫画 API
│   ├── network/            # 网络诊断 API
│   └── user/               # 用户 API
├── models/                 # 数据模型
│   ├── comic.dart          # 漫画模型
│   ├── chapter.dart        # 章节模型
│   ├── category_config.dart # 耽美分类配置
│   └── user_manager.dart   # 用户状态管理
├── pages/                  # 页面
│   ├── home_page.dart      # 首页（分类筛选 + 漫画网格）
│   ├── favorite_page.dart  # 书架（最近阅读/收藏/下载）
│   ├── profile_page.dart   # 我的（设置入口）
│   ├── reader_page.dart    # 阅读器
│   ├── comic_detail_page.dart # 漫画详情
│   ├── search_page.dart    # 搜索
│   └── ...
├── utils/                  # 工具类
│   ├── reading_history.dart # 阅读记录管理
│   ├── local_favorites.dart # 本地收藏管理
│   ├── download_manager.dart # 下载管理
│   ├── glass_widgets.dart  # 毛玻璃组件库
│   └── theme_tokens.dart   # 主题常量
└── widgets/                # 通用组件
    ├── comic_cover_card.dart
    ├── comic_list_tile.dart
    └── kira_app_bar.dart
```

## 🙏 致谢

### 上游项目

本项目基于以下优秀开源项目深度定制：

| 项目 | 说明 |
|------|------|
| [**kira**](https://github.com/caolib/kira) by **孤独的Lonely** | 原始项目，提供了完整的漫画阅读器框架、多线路架构、阅读器引擎、AI 总结等核心功能。炸鸡腿漫画在此基础上进行了耽美向定制、UI 重构和多项 Bug 修复 |

### 数据与服务

| 服务 | 说明 |
|------|------|
| [**拷贝漫画**](https://www.mangacopy.com/) (CopyManga) | 漫画数据源，提供漫画列表、搜索、详情、章节等 API |
| [**弹弹play**](https://www.dandanplay.com/) | 弹幕服务支持（原版功能） |
| [**繁化姬**](https://zhconvert.org/) | 简繁体转换服务 |

### 开源依赖

本项目使用了以下优秀的开源库，均遵循各自的开源许可证：

| 库 | 用途 |
|----|------|
| [dio](https://github.com/cfug/dio) | 网络请求 |
| [cached_network_image](https://github.com/Baseflow/flutter_cached_network_image) | 图片缓存加载 |
| [flutter_js](https://github.com/abner/flutter_js) | JavaScript 引擎（数据源解析） |
| [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview) | 内嵌 WebView |
| [scrollable_positioned_list](https://github.com/google/flutter.widgets) | 漫画翻页定位 |
| [shared_preferences](https://github.com/flutter/packages) | 本地偏好存储 |
| [flex_color_picker](https://github.com/rydmike/flex_color_picker) | 主题取色器 |
| [flutter_svg](https://github.com/dnfield/flutter_svg) | SVG 图标 |
| [flutter_markdown_plus](https://github.com/flutter/packages) | Markdown 渲染（AI 总结） |
| [screen_brightness](https://github.com/aaassseee/screen_brightness) | 屏幕亮度控制 |
| [wakelock_plus](https://github.com/solid-software/wakelock_plus) | 防息屏 |
| [crypto](https://github.com/dart-lang/core) | 加密工具 |
| [package_info_plus](https://github.com/fluttercommunity/plus_plugins) | 应用信息 |
| [path_provider](https://github.com/flutter/packages) | 文件路径 |
| [url_launcher](https://github.com/flutter/packages) | 外部链接跳转 |

## ⚠️ 免责声明

> **请在使用本应用前仔细阅读以下声明：**
>
> - 本应用为**非官方第三方客户端**，仅基于第三方平台提供的接口或公开可访问资源进行内容展示与访问。
> - 本应用不生产、上传、编辑、修改或预先审查具体展示内容，相关内容均来源于第三方返回结果，开发者无法对其进行完全控制。
> - 本应用展示的内容中，可能包含成人内容或其他不适宜未成年人浏览的信息；如您未满 18 周岁，或您所在地法律法规禁止访问相关内容，请立即停止使用本应用。
> - 用户应自行判断相关内容是否适合浏览，并确保其使用行为符合所在地法律法规。
> - 如第三方内容存在侵权、违法、违规或其他不当情形，相关责任原则上由内容提供方承担；开发者将在收到有效通知后，根据实际情况采取必要处理措施。
>
> ✅ **继续使用本应用，即表示您已阅读、理解并同意上述说明；如您不同意，请立即停止使用并卸载本应用。**

## 📄 许可证

本项目基于 [MIT License](LICENSE) 开源。

---

<p align="center">
  <sub>🍗 Made with ❤️ and Flutter</sub>
</p>