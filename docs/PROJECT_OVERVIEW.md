# Kira (炸鸡腿漫画) — 项目概览报告

## 1. 项目简介

Kira 是一个基于 hotmanga 平台的第三方漫画/动漫客户端，应用名为"炸鸡腿漫画"。支持漫画阅读、动漫播放（含弹幕）、评论、收藏、下载、阅读历史等功能。

- **仓库来源**: github.com/caolib/kira
- **版本**: 1.1.1
- **许可证**: 见 LICENSE 文件

---

## 2. 目录树摘要

```
kira-source/
├── lib/                    # 应用主代码 (79 个 Dart 文件)
│   ├── main.dart           # 入口文件
│   ├── api/                # 网络请求层
│   │   ├── api_client.dart # 核心 HTTP 客户端 (Dio, 多域名容灾)
│   │   ├── ai_api.dart     # AI 相关接口
│   │   ├── dandanplay_api.dart  # 弹弹play弹幕服务接口
│   │   ├── anime/          # 动漫 API (part of api_client)
│   │   ├── manga/          # 漫画 API (part of api_client)
│   │   ├── network/        # 网络检测 API (part of api_client)
│   │   └── user/           # 用户 API (part of api_client)
│   ├── models/             # 数据模型 & 状态管理
│   │   ├── user_manager.dart    # 用户状态单例 (登录/设置/主题)
│   │   ├── comic.dart           # 漫画模型
│   │   ├── chapter.dart         # 章节模型
│   │   ├── anime.dart           # 动漫模型
│   │   ├── app_theme_option.dart # 主题选项
│   │   ├── chapter_comment.dart  # 章节评论
│   │   └── comic_comment.dart    # 漫画评论
│   ├── pages/              # UI 页面 (26 个顶层页面 + 子目录)
│   │   ├── home_page.dart       # 首页(耽美/推荐/排行)
│   │   ├── favorite_page.dart   # 收藏页
│   │   ├── profile_page.dart    # 个人中心
│   │   ├── reader_page.dart     # 漫画阅读器
│   │   ├── anime_player_page.dart # 动漫播放器
│   │   ├── comic_detail_page.dart # 漫画详情
│   │   ├── anime_detail_page.dart # 动漫详情
│   │   ├── search_page.dart     # 搜索
│   │   ├── ranking_page.dart    # 排行榜
│   │   ├── bookshelf_page.dart  # 书架
│   │   ├── download_center_page.dart # 下载中心
│   │   ├── reader/              # 阅读器子组件
│   │   ├── anime_player/        # 播放器子组件
│   │   ├── anime_detail/        # 动漫详情子组件
│   │   └── chapter_comments/    # 评论子组件
│   └── utils/              # 工具类 (18 个文件)
│       ├── download_manager.dart     # 漫画下载管理
│       ├── anime_download_manager.dart # 动漫下载管理
│       ├── data_cache.dart           # 数据缓存
│       ├── reading_history.dart      # 阅读历史
│       ├── local_favorites.dart      # 本地收藏
│       ├── app_update.dart           # 应用更新检测
│       ├── chinese_converter.dart    # 繁简转换
│       ├── dandanplay_*.dart         # 弹幕绑定相关
│       └── ...
├── android/                # Android 平台代码
├── ios/                    # iOS 平台代码
├── windows/                # Windows 平台代码
├── macos/                  # macOS 平台代码
├── linux/                  # Linux 平台代码
├── web/                    # Web 平台代码
├── assets/                 # 静态资源 (图标、吉祥物图片)
├── docs/                   # 文档 (CHANGELOG.md, TODO.md)
├── scripts/                # 构建脚本 (PowerShell)
├── test/                   # 测试目录
├── pubspec.yaml            # 依赖配置
├── analysis_options.yaml   # 静态分析规则
├── AGENTS.md / CLAUDE.md   # AI 辅助开发指南
└── README.md               # 项目说明
```

---

## 3. 技术栈

| 维度 | 技术选型 |
|------|----------|
| 语言 | Dart (SDK ^3.11.0) |
| 框架 | Flutter (Material Design 3) |
| 网络请求 | Dio ^5.8.0 |
| 图片加载 | cached_network_image + flutter_cache_manager |
| 视频播放 | media_kit + media_kit_video |
| 弹幕渲染 | canvas_danmaku |
| 本地存储 | shared_preferences |
| 加密 | crypto (dart-lang) |
| 状态管理 | ChangeNotifier (UserManager 单例) |
| 构建工具 | Flutter CLI + PowerShell 脚本 |
| 依赖管理 | pub (pubspec.yaml / pubspec.lock) |
| 静态分析 | flutter_lints ^6.0.0 |
| 目标平台 | Android (arm64), iOS, Windows, macOS, Linux, Web |

---

## 4. 入口与配置

| 文件 | 作用 |
|------|------|
| `lib/main.dart` | 应用入口，初始化 MediaKit、UserManager、主题、主页面 |
| `pubspec.yaml` | 依赖声明、资源注册、启动图标配置 |
| `analysis_options.yaml` | Dart 静态分析规则 |
| `.env` (运行时) | 弹弹play appId/appSecret (通过 --dart-define-from-file 注入) |
| `scripts/*.ps1` | 构建 APK/Windows 发布包的 PowerShell 脚本 |

---

## 5. 核心模块说明

### 5.1 API 层 (`lib/api/`)

- **api_client.dart**: 核心 HTTP 客户端，基于 Dio，实现多域名容灾切换（_routes 数组）、Cookie 管理、401 自动重登录、请求签名。使用 Dart `part` 指令将子 API 拆分到独立文件。
- **manga_api.dart**: 漫画列表、详情、章节图片、搜索、排行等接口。
- **anime_api.dart**: 动漫列表、详情、播放链接等接口。
- **user_api.dart**: 用户登录、注册、收藏同步等接口。
- **network_api.dart**: 网络连通性检测。
- **dandanplay_api.dart**: 弹弹play 弹幕匹配与获取。
- **ai_api.dart**: AI 功能接口（章节摘要等）。

### 5.2 数据模型层 (`lib/models/`)

- **user_manager.dart**: 全局单例，管理登录态、用户偏好（主题、字体、阅读设置）、凭据持久化。继承 ChangeNotifier 驱动 UI 更新。
- **comic.dart / chapter.dart / anime.dart**: 领域数据模型，对应 API 返回的 JSON 结构。
- **app_theme_option.dart**: 主题配色选项模型。
- **chapter_comment.dart / comic_comment.dart**: 评论数据模型。

### 5.3 页面层 (`lib/pages/`)

按功能划分为三大 Tab：
1. **首页 (HomePage)**: 包含推荐、排行榜、搜索入口
2. **收藏 (FavoritePage)**: 书架、收藏列表
3. **我的 (ProfilePage)**: 设置、下载中心、历史、外观、网络诊断

核心功能页面：
- **reader_page.dart + reader/**: 漫画阅读器（翻页/滚动模式、亮度调节、图片缓存）
- **anime_player_page.dart + anime_player/**: 动漫播放器（media_kit、弹幕叠加、章节选择）
- **comic_detail_page.dart / anime_detail_page.dart**: 详情页（章节列表、评论）

### 5.4 工具层 (`lib/utils/`)

- **download_manager.dart / anime_download_manager.dart**: 离线下载管理
- **data_cache.dart**: 通用数据缓存
- **reading_history.dart / anime_playback_history.dart**: 阅读/播放历史
- **local_favorites.dart**: 本地收藏存储
- **app_update.dart**: GitHub Release 更新检测
- **chinese_converter.dart**: 繁简转换（调用繁化姬 API）
- **dandanplay_*.dart**: 弹幕服务绑定逻辑

---

## 6. 模块间关系

```
┌─────────────────────────────────────────────────┐
│                  lib/main.dart                   │
│         (入口: 初始化 → MaterialApp → MainPage)  │
└───────────────────────┬─────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
   HomePage       FavoritePage     ProfilePage
        │               │               │
        ▼               ▼               ▼
┌─────────────────────────────────────────────────┐
│              lib/pages/ (功能页面)                │
│  reader_page ← comic_detail ← search/ranking    │
│  anime_player ← anime_detail ← anime_home       │
└───────────────────────┬─────────────────────────┘
                        │ 调用
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  lib/api/    │ │ lib/models/  │ │  lib/utils/  │
│  (网络请求)   │ │ (数据/状态)  │ │  (工具服务)   │
│              │ │              │ │              │
│ api_client   │←│ user_manager │ │ download_mgr │
│ manga_api    │ │ comic/chapter│ │ data_cache   │
│ anime_api    │ │ anime        │ │ history      │
│ user_api     │ │ comments     │ │ favorites    │
│ dandanplay   │ │ theme_option │ │ app_update   │
│ ai_api       │ │              │ │ chn_convert  │
└──────────────┘ └──────────────┘ └──────────────┘
```

**数据流向**:
1. Pages 通过 API 层发起网络请求获取数据
2. API 层使用 models 中的类进行 JSON 反序列化
3. UserManager 单例贯穿所有层，提供登录态和用户偏好
4. Utils 提供横切关注点（缓存、下载、历史）供 Pages 和 API 共用

---

## 7. 构建与运行

```sh
# 安装依赖
flutter pub get

# 运行（需要 .env 文件提供弹幕密钥，可选）
flutter run -d <设备ID> --dart-define-from-file=.env

# 构建 APK
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=.env

# 静态分析
flutter analyze

# 测试
flutter test
```

---

## 8. 关键设计特点

1. **多域名容灾**: API 客户端内置多组域名，请求失败自动切换
2. **Dart part 指令**: API 子模块使用 `part of` 拆分文件但共享私有成员
3. **ChangeNotifier 状态管理**: 轻量级方案，UserManager 作为全局状态中心
4. **Material Design 3 动态主题**: 支持多种 DynamicSchemeVariant，自定义炸鸡腿配色
5. **桌面端适配**: 自定义 ScrollBehavior 支持鼠标拖拽，系统字体加载
6. **弹幕集成**: 通过弹弹play API 实现动漫弹幕功能
