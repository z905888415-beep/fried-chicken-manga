# Kira（炸鸡腿漫画）v1.1.1 QA 基线与扩展扫描报告

> 检测日期：2026-07-21  
> 仓库根目录：`D:/AI/kira-source`  
> 角色：QA 工程师（严过关）  
> 说明：本报告只做只读分析与冒烟测试，未修改任何源文件。

---

## TL;DR

- **flutter test**：41 项测试，35 通过 / 6 失败。6 项失败中：2 项为**源码 BUG**（`UserManager.animeFeatureEnabled` getter 硬编码返回 `false`），2 项为**测试环境缺 `quickjs_c_bridge.dll`**，2 项为**测试断言与当前 UI 不匹配**（旧测试）。
- **flutter analyze**：正好 16 条 lint/info（无 error），已全部列出。
- **扩展缺陷扫描**：在 `lib/pages` 与 `lib/utils` 非搜索链路中发现 **13 项以上新缺陷/风险**，集中在 `manga_api.dart` 硬类型转换（BUG-02 家族向搜索外扩展）、动漫功能开关硬编码、设置导入数据丢失、收藏页 Tab 无视图、`HttpClient` 未释放等。
- **截图 UI 审查**：`home2.png` 损坏；存在多张重复截图；底部导航栏 Tab 数量不一致（3 个 vs 4 个）。
- **前后端冒烟**：搜索/漫画列表接口可达且结构正常；评论域名在当前环境返回 HTML 错误页，代码对非 JSON 响应无防御。
- **路由建议**：源码缺陷 → 工程师 Alex；测试用例/环境问题 → 在报告中说明，不改源文件。

---

## 一、测试基线

### 1.1 flutter test

```text
00:03 +35 -6: Some tests failed.
```

| 指标 | 数值 |
|------|------|
| 总测试数 | 41 |
| 通过 | 35 |
| 失败 | 6 |

#### 失败明细与根因

| # | 测试文件/用例 | 关键报错 | 根因判断 | 路由 |
|---|---------------|----------|----------|------|
| 1 | `test/models/user_manager_test.dart`：anime feature setting defaults to enabled and persists | `Expected: true\n  Actual: <false>` | **源码 BUG**：`lib/models/user_manager.dart:252` 将 `animeFeatureEnabled` getter 硬编码为 `false`，`_animeFeatureEnabled` 字段、持久化、setter 全部失效 | 工程师 |
| 2 | `test/pages/general_page_test.dart`：anime feature switch updates setting | `Expected: true\n  Actual: <false>` | **源码 BUG**：同上 D13；且 `GeneralPage` 当前没有动漫功能开关 | 工程师 |
| 3 | `test/pages/profile_page_test.dart`：profile page shows general settings entry | `Found 0 widgets with text "通用"` | 测试断言与当前 UI 不符：ProfilePage 已无"通用"入口 | 测试侧/旧用例 |
| 4 | `test/pages/profile_page_test.dart`：switch account sheet shows add account button | `Found 0 widgets with text "切换账号"`（tap 失败） | 测试查找"切换账号"，但当前界面按钮文本为"添加账号" | 测试侧/旧用例 |
| 5 | `test/pages/chapter_comments_sheet_test.dart`：merged compact comments keep one line when avatars are hidden | `Failed to load dynamic library 'quickjs_c_bridge.dll' (error code: 126)` | Windows 测试沙箱缺少 `flutter_js` QuickJS 原生库 | 环境 |
| 6 | `test/pages/chapter_comments_ai_summary_test.dart`：AI summary stays collapsed while generating until user expands | 同上 `quickjs_c_bridge.dll` | 同上 | 环境 |

### 1.2 flutter analyze

**结果：16 issues found**（全为 warning/info，无 error）。

| # | 位置 | 级别 | 内容 |
|---|------|------|------|
| 1 | `lib\api\api_client.dart:43:9` | warning | `_cache` field unused (`unused_field`) |
| 2 | `lib\api\api_client.dart:254:9` | info | Use null-aware marker `?` rather than null check via `if` (`use_null_aware_elements`) |
| 3 | `lib\main.dart:11:8` | warning | Unused import `pages/extension_browse_page.dart` |
| 4 | `lib\pages\appearance_page.dart:169:19` | info | Deprecated `onReorder`; use `onReorderItem` instead (`deprecated_member_use`) |
| 5 | `lib\pages\home_page.dart:10:8` | warning | Unused import `../utils/glass_widgets.dart` |
| 6 | `lib\pages\home_page.dart:26:7` | warning | Unused element `_mangaHomeCardWidth` |
| 7 | `lib\pages\home_page.dart:27:7` | warning | Unused element `_mangaHomeCardSpacing` |
| 8 | `lib\pages\home_page.dart:234:8` | warning | Unused element `_scheduleSearch` |
| 9 | `lib\pages\home_page.dart:485:7` | warning | Unused field `_bannerIndex` |
| 10 | `lib\pages\home_page.dart:962:7` | warning | Unused element `_SearchSheet` |
| 11 | `lib\pages\profile_page.dart:17:8` | warning | Unused import `local_comics_page.dart` |
| 12 | `lib\pages\profile_page.dart:18:8` | warning | Unused import `network_page.dart` |
| 13 | `lib\pages\profile_page.dart:19:8` | warning | Unused import `ai_config_page.dart` |
| 14 | `lib\pages\profile_page.dart:20:8` | warning | Unused import `extension_sources_page.dart` |
| 15 | `lib\pages\profile_page.dart:606:10` | warning | Unused element `_buildUserCard` |
| 16 | `lib\pages\profile_page.dart:1721:7` | warning | Unused element `_SettingIcon` |

---

## 二、新缺陷清单（非搜索链路扩展）

以下缺陷为 BUG_DETECTION_REPORT.md 已列 13 条搜索 bug **之外** 的新发现。

| 编号 | 位置 | 现象 | 严重度 |
|------|------|------|--------|
| **D13** | `lib/models/user_manager.dart:252` | `bool get animeFeatureEnabled => false;` 硬编码返回 `false`；`_animeFeatureEnabled` 字段默认 `true`、有 setter、有持久化，但 getter 完全忽略，动漫功能开关永久失效，并导致 2 项测试失败 | 严重 |
| **D5** | `lib/api/manga/manga_api.dart:71-72` | `getComicList` 中 `data['list'] as List` + `data['total'] as int` 硬类型转换；首页/分类列表接口结构异常即抛 `TypeError` | 高 |
| **D8** | `lib/api/manga/manga_api.dart:98-101` | `getChapterList` 中 `data['list'] as List` + `data['total'] as int` 硬转换；章节列表解析崩溃，影响阅读器"开始阅读" | 高 |
| **D9** | `lib/api/manga/manga_api.dart:175-176` | `getChapterComments` 直接 `resp.data['results'] as Map<String, dynamic>`，且 `results['list'] as List`；评论端返回非 JSON 时抛 `TypeError` | 高 |
| **D10** | `lib/api/manga/manga_api.dart:268-269` | `getComicComments` 同上，硬转换；本次冒烟实测 `api.copy2000.online` 返回 HTML 错误页 | 高 |
| **D11** | `lib/api/manga/manga_api.dart:292-305` | `getBookshelf` 中 `data['list'] as List` + `data['total'] as int` 硬转换；个人书架崩溃 | 高 |
| **D6** | `lib/api/manga/manga_api.dart:50-53` | `getRecommendations` 中 `data['list'] as List` 硬转换，并使用不安全的 `Comic.fromJson`；"为你推荐"区域崩溃 | 中 |
| **D7** | `lib/api/manga/manga_api.dart:36` | `getComicTags` 中 `data['list'] as List` 硬转换；漫画标签页崩溃 | 中 |
| **D1** | `lib/utils/settings_backup.dart:70-76` | `importPlainText` 先清空全部旧偏好，再循环写入新偏好；写入中途抛异常则用户设置已部分/全部丢失，无事务回滚 | 中 |
| **D3** | `lib/pages/favorite_page.dart:31-104` | TabBar 声明 3 个 Tab（最近阅读 / 收藏 / 下载），但页面无 `TabBarView`，只有收藏网格；"最近阅读"、"下载"点击无法切换 | 中 |
| **D12** | `lib/pages/appearance_page.dart:178` | `_navMeta[key]!` 非空断言；若 `navOrder` 包含未列出的 key（如扩展/动漫 Tab），`ReorderableListView` 直接崩溃 | 中 |
| **D2** | `lib/utils/download_manager.dart:37` | `HttpClient _httpClient` 为应用生命周期单例，从未 `close()`；TLS/HTTP 连接持续累积，类似 BUG-12 的 Socket 泄漏 | 低 |

> **补充说明（同类别低危，未单独编号）**：`app_update.dart:93`、`reading_history.dart:63`、`download_manager.dart:218/744`、`comix_source_adapter.dart` 多处、`dandanplay_api.dart:345/349/353/500`、`ai_api.dart:398/480/938` 等位置也存在 `as List` / `as Map` / `as int` 硬转换或 `jsonDecode(...) as List` 等模式，异常响应下会抛 `TypeError`。建议统一对齐项目内 `anime_api` 的防御式写法：`as List? ?? const []`、`as int? ?? 0/length`、`resp.data is Map ? ... : null`。

---

## 三、截图 UI 审查

| 截图 | 观察 |
|------|------|
| `v2_home.png` / `v3_home.png` | 启动/闪屏页，仅显示炸鸡腿吉祥物 logo，布局正常 |
| `v3_back.png` / `v4_home.png` / `v4_s3.png` / `v4_s4.png` | 首页：顶部标题栏 + Banner + 可滚动分类标签 + "为你推荐" + 底部导航栏；**底部导航只有 3 个 Tab（耽美 / 收藏 / 我的）** |
| `home3.png` | 首页同构，但**底部导航显示 4 个 Tab（耽美 / 扩展 / 收藏 / 我的）**；与上述截图不一致，可能受扩展/动漫功能开关影响 |
| `v3_loaded.png` | 分类列表页 "都市 耽美漫画"，顶部信息卡 + 排序按钮 + 2 列网格，布局正常 |
| `v4_s5.png` / `v4_search_default.png` | 搜索默认页：热门搜索 + 耽美分类标签，正常 |
| `v4_s6.png` / `v4_search2.png` | 搜索结果页 "五棱镜"，网格展示 41 条结果，正常 |
| `scr_school.png` | 漫画详情页（五號公寓）：封面、信息、操作按钮、分组选择器、章节网格、悬浮"继续阅读"按钮，布局正常 |
| `check_home.png` | 模拟器桌面，仅用于确认应用图标存在 |
| `home2.png` | **损坏/无效**：截图内容不是应用 UI，而是 base64/文本占位块，疑似保存失败或渲染异常 |
| `ui.xml` | 900x1600 虚拟设备布局 dump，信息完整但过长，未单独分析 |

### UI 问题汇总

1. **`home2.png` 损坏**：无法用于回归对比。
2. **截图重复**：`v4_s3`/`v4_s4` 与 `v4_home` 重复；`v4_s5` 与 `v4_search_default` 重复；`v4_s6` 与 `v4_search2` 重复。建议精简去重。
3. **底部 Tab 数量不一致**：同一版本首页截图出现 3 Tab 与 4 Tab 两种状态，需确认"扩展" Tab 的显示逻辑（是否依赖扩展源开关或动漫功能开关）。
4. 其余页面未发现明显溢出、错位或留白异常。

---

## 四、前后端接口冒烟测试

> 测试方法：curl + Python 解析，headers 对齐 `api_client.dart` 的 `onRequest` 拦截器。

### 4.1 可达端点

| 端点 | Host | 结果 | 说明 |
|------|------|------|------|
| `GET /api/v3/search/comic?q=海贼王&limit=3&offset=0&free_type=1` | `mapi.hotmangasg.com` | HTTP 200，JSON 正常 | 需携带 `platform/3`、`webp/1`、`version`、`X-Requested-With` 等头 |
| `GET /api/v3/comics?free_type=1&limit=2&offset=0&ordering=-popular` | `mapi.hotmangasg.com` | HTTP 200，JSON 正常 | 漫画列表接口 |
| `GET /api/v3/comments?comic_id=haizeiwang&limit=5&offset=0&platform=3` | `api.copy2000.online` | 返回 HTML 错误页 | 非 JSON，代码硬转换会抛异常 |

### 4.2 响应结构判断

**搜索/列表接口**（`search/comic`、`/comics`）：

```json
{
  "code": 200,
  "message": "请求成功",
  "results": {
    "list": [...],
    "total": <int>
  }
}
```

- `results` 为 Map ✅
- `list` 为 List ✅
- `total` 为 int ✅
- 列表元素字段类型正常：`name`(str)、`path_word`(str)、`cover`(str)、`popular`(int) ✅

**与 BUG-02/03 一致性**：当前正常响应满足 BUG-02/03 假设的 `list/total` 结构。但 `_extractResults` 只保证 `results` 是 Map，**不保证内部 `list`/`total` 存在且类型正确**；`manga_api` 中大量 `data['list'] as List` / `data['total'] as int` 仍是风险点。

### 4.3 网络限制说明

- 本沙箱**可以访问** `mapi.hotmangasg.com` 和 `mapi.hotmangasd.com`（HTTP 200）。
- 未携带应用 headers 时，上游返回 `b'error'`，说明代码必须依赖 Dio 拦截器注入的 headers；这也解释了 why 外层 `_extractResults` 已做 `results` 存在性校验的必要性。
- `api.copy2000.online` 在当前环境返回 HTML 错误页，不确定是 CDN 拦截、路径/参数缺失 token，还是服务本身异常；**需在用户本机真实设备上复验**。

---

## 五、LDPlayer 手动验证清单

> 环境：LDPlayer 14（`D:\leidian\LDPlayer14\dnplayer.exe`），APK 源码 `D:\AI\kira-source`。本沙箱无法启动 GUI，以下清单供用户本机逐项验证。

| 功能点 | 操作步骤 | 验收标准 |
|--------|----------|----------|
| 安装与启动 | 1. 在 LDPlayer 中安装 build/app/outputs/flutter-apk/app-release.apk<br>2. 点击桌面"炸鸡腿漫画"图标启动 | 应用正常打开，闪屏显示炸鸡腿 logo，进入首页无崩溃 |
| 全局搜索（漫画） | 首页或搜索页输入"海贼王"，点击搜索 | 结果页展示漫画网格，`total` 字段与列表一致；无"搜不到"静默失败（验证 BUG-01 修复：失败时能看到错误提示或重试按钮） |
| 全局搜索（动漫） | 切换搜索模式为动漫，输入关键词搜索 | 若能进入动漫搜索，结果正常展示；若功能灰显，记录是否与 D13 硬编码 false 相关 |
| 首页耽美搜索 | 在首页顶部搜索框输入"五號公寓"或"五棱镜"，等待 debounce | 搜索结果与远程结果一致；不出现"没有找到耽美漫画"的误杀（验证 BUG-05 修复） |
| 首页分类入口 | 点击首页标签行"都市"/"校园"/"古风"等 | 进入 `CategoryComicsPage`，顶部显示"找到 N 部作品"，网格加载正常 |
| 漫画阅读器 - 翻页模式 | 进入任意章节，设置页切换为"翻页模式"，左右/点击翻页 | 可正常翻页、跳转上下章、显示页码进度条；退出后阅读进度被保存 |
| 漫画阅读器 - 滚动模式 | 切换为"滚动模式"，上下滑动 | 滚动流畅，到底后显示"下一章"入口；进度条与当前页同步 |
| 阅读器亮度/夜间 | 在阅读器设置中调节亮度遮罩、切换深色模式 | 屏幕亮度/遮罩实时变化，深色模式覆盖层正常 |
| 动漫播放器 + 弹幕 | 找到支持动漫的入口（若 D13 未修复可能无法进入），播放一集 | 播放器可播放、暂停、拖动进度；弹幕开关/字号/透明度/屏蔽设置生效；86 秒跳过功能正常 |
| 章节评论 | 在阅读器或详情页点击"评论" | 评论列表加载；发送评论字数限制 3-200；AI 总结（若启用）不阻塞阅读 |
| 漫画评论 | 在漫画详情页点击"评论" | 漫画/回复评论列表加载；注意 `api.copy2000.online` 在本环境返回 HTML，需确认真机是否同样失败 |
| 下载中心 | 进入漫画详情页 → 选择章节 → 下载；再进入"下载中心" | 下载任务开始并显示进度；下载完成后可在"本地漫画"中离线阅读；批量删除正常 |
| 收藏/书架 | 漫画详情页点击"收藏"；进入"书架/收藏" Tab | 收藏列表出现该漫画；取消收藏后移除；"继续阅读"卡片显示最近阅读进度 |
| 设置 - 外观 | 设置 → 外观：切换主题模式、主题色、导航栏顺序、字体（桌面端） | 主题色实时生效；导航栏顺序可拖拽；底部导航显示/隐藏文字生效 |
| 设置 - 通用 | 设置 → 通用：开关自动登录、Banner 显示；导出/导入设置；重置应用 | 导出 JSON 可正常复制；导入覆盖后设置生效；重置应用后本地数据清空（不删下载文件） |
| 设置 - 网络诊断 | 设置 → 网络：切换线路 1/2，点击"测试线路延迟" | 两线路均返回延迟；切换线路后搜索/列表能刷新 |
| 各 Tab 切换 | 反复点击底部导航各 Tab | 切换流畅，无 setState after dispose 异常；收藏页 3 个装饰 Tab 至少不崩溃（D3 功能缺失可后续评估） |
| 横竖屏/大屏适配 | 旋转模拟器为横屏，或在大屏分辨率下运行 | 首页网格、阅读器、详情页布局不发生严重错位或溢出；阅读器横屏时翻页/滚动方向正确 |
| 错误态可见性（BUG-01） | 关闭网络或切换到死域名线路，执行搜索 | 页面显示可识别的错误提示（非空列表伪装成"无结果"），并提供重试入口 |

---

## 路由决策

- **发给工程师 Alex**：
  - D13：`user_manager.dart:252` `animeFeatureEnabled` getter 硬编码 `false`，需改为返回 `_animeFeatureEnabled`。
  - D5/D6/D7/D8/D9/D10/D11：`manga_api.dart` 多处 `data['list'] as List` / `data['total'] as int` / `resp.data['results'] as Map` 硬转换，需对齐项目内 `anime_api` 的防御式写法。
  - D12：`appearance_page.dart:178` `_navMeta[key]!` 非空断言风险。
  - D2：`download_manager.dart` `_httpClient` 资源释放。
- **测试侧/旧用例**：profile_page_test 两项失败（"通用"入口、"切换账号"按钮文本）需要同步测试断言；`anime feature` 相关用例在 D13 修复后应重新跑通。
- **环境/CI**：Windows 测试 runner 缺少 `quickjs_c_bridge.dll`，需补充 `flutter_js` 原生库或调整 CI。
- **本机复验**：`api.copy2000.online` 评论接口在当前环境返回 HTML，需在用户本机/真机验证实际行为。

---

## 更新记录（2026-07-21 后续协作）

工程师修复 D13（`animeFeatureEnabled` getter 返回真实值）及 `JsSourceManager` 原生库回归后，QA 复核并重跑基线，结论更新如下：

### 测试基线（重跑）
- `flutter test`：**41 项全部通过**（+41，原 38 通过 / 3 失败）。
- 原 3 个失败均为「陈旧测试 vs 已演进 UI」的不匹配，非源码回归。QA 已更新测试断言（**仅改 `test/`，未动 `lib/` 源文件**）：
  - `test/pages/general_page_test.dart`：`anime feature switch updates setting` → 重命名为 `anime feature getter reflects enabled default`，移除已删除的「动漫功能」UI 开关断言，仅保留模型层 getter 校验（D13 修复后 getter 正确返回 `true`）。
  - `test/pages/profile_page_test.dart`：`switch account sheet shows add account button` → 新交互需先点「编辑」展开操作区（`_userActionsExpanded`）才出现「切换账号」按钮，补一步 `tap(find.text('编辑'))`。
  - `test/pages/profile_page_test.dart`：`profile page shows general settings entry` → 「通用」入口已重设计为「主题设置」（trailing 显示当前主题模式「跟随系统」），断言同步更新。
- `flutter analyze`：**No issues found!（0 issues）**。基线报告中原列的 16 条 lint/info 现已全部清除（analyze 基线数字失效，以本次重跑为准）。

### 路由更新
- **D13 已由工程师修复并验证**（getter 测试通过）。
- 原路由给工程师的 **D5–D11**（manga_api 硬转换）、**D12**（非空断言）、**D2**（Socket 泄漏）维持不变，待 **T04**（统一防御式解析 helper）落地。
- 3 个陈旧测试已由 QA 侧更新并验证通过，无需再路由。

---

## 最终回归（交付前质量关卡 · T04 收口后）

> 触发：team-lead 在 T04（统一防御式解析 helper）与 ranking/recommend `_loadMore` 去 `catch (_)` 完成后，启动 task #12 最终回归。

### 1. 全量回归
- `flutter analyze lib`：**No issues found!（0 issues）** ✅
- `flutter test`：**70/70 全过** ✅（原 41 项保留全绿 + 新增 `test/api/api_helpers_test.dart` 29 项）。
- 此前修复的 3 个陈旧测试（general_page / profile_page）保持改后状态，未回退。

### 2. 新增 `test/api/api_helpers_test.dart`（29 项，BUG-01 单元证据）
覆盖 `safeRawList<T>` / `safeInt` / `safeMap` / `safeResults` / `ApiParseException` 四类行为，每组含 正常 / null / 错类型 / 边界 子用例，并专设 **BUG-01 闭环** 组：
- `safeRawList<Map>(resp['list'], required:true)` 当 `resp['list']` 为 `'broken'`（非 List）**抛 `ApiParseException`** —— 正是「畸形响应不再静默降级为空列表」的 API 层行为证明。
- 经 `safeResults` 取出的畸形 `list` 同样抛 `ApiParseException`。
- `total` 为字符串等次级字段经 `safeInt(required:false)` 降级为 `fallback` 而非崩溃（分层防御）。
- `ApiParseException` 携带 `message` 与可选 `raw`，`toString` 可读。

### 3. BUG-01 闭环实证（grep + 代码审查）
| 校验项 | 命令 / 位置 | 结果 |
|--------|-------------|------|
| `lib/api/` 内无 `as List? ?? const []` 残留 | `grep -rn "as List? ?? const \[\]" lib/api/` | **0 匹配** ✅ |
| 端点全量迁移 | `grep safeRawList lib/api/` | manga_api(20/52/124/156/195/318)、user_api(106/217)、dandanplay_api、comix_source_adapter、ai_api 均已用 `safe*` + `required` 模式 ✅ |
| ranking `_loadMore` 不再 `catch (_)` | `lib/pages/ranking_page.dart:64-87` | `catch (e)` → `SnackBar(NetworkError.message(e), 重试→_loadMore)` ✅ |
| recommend `_loadMore` 不再 `catch (_)` | `lib/pages/recommend_page.dart:59-82` | 同上 `catch (e)` → `SnackBar` + 重试 ✅ |
| 主数据畸形 → 页面显错 | ranking 149 / recommend 114 | `_load` 的 `catch (e)` 置 `_error` → `ErrorView(message:_error, onRetry:_load)`；因 `getComicList` 现调 `safeRawList(required:true)`，畸形 `list` 抛 `ApiParseException` 经此链路显错 |

**承接链路**：上游畸形 `list` → `getComicList` 内 `safeRawList<Map>(data['list'], required:true)` 抛 `ApiParseException` → 页面 `_load` 的 `catch (e)` 捕获 → `_error = NetworkError.message(e)` → `ErrorView` 显错（或 `_loadMore` 的 `SnackBar` + 重试）。**错误态可见，不再伪装成空列表（BUG-01 根因消除）。**

### 4. 已知残留（均不阻塞交付）
- `lib/pages/ai_config_page.dart:158`：`catch (_) {}` 包裹本地 JSON 配置读取，失败仅静默——本地配置非网络主数据，风险低，已记录待后续评估。
- `lib/pages/app_update.dart:104`：`catch (_)` 包裹 GitHub assets 探测，静默降级——非主数据显示路径。
- 模型层裸 `as`：经核查 `comic.dart:158` 等已为防御式写法，无需改动。
- `api.copy2000.online` 评论接口在本沙箱返回 HTML（见上文「前后端冒烟」），需在真机复验；T04 的 `safeMap/safeResults(required:true)` 已确保该路径畸形时显错而非崩。
- 其余 `lib/pages` 中 `catch (_)`（favorite/search/profile/comic_detail/reader/network 等）均为非主数据局部容错，不属 BUG-01 主数据显错范畴。

### 路由结论
- 源码：本轮无新源码 bug，全部 70 项测试通过、analyze 0。T04 相关 D5–D11/D12 已由工程师收口，D13 已修。
- 测试：本轮新增 29 项 `api_helpers` 测试，全部通过（自身无 bug）。
- **交付判定：通过** ✅。
