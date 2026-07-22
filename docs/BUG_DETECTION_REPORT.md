# Kira (炸鸡腿漫画) — Bug 检测报告

> 检测范围：`kira-source/lib/` 全部源码（只读分析，未修改任何源文件）
> 检测重点：搜索功能链路（搜索框 UI → 搜索逻辑 → API 请求 → 数据解析 → 结果渲染）
> 基准文档：`docs/PROJECT_OVERVIEW.md`
> 检测日期：2026-07-21

---

## 0. 结论摘要

**"搜索框搜不到作品"不是单一 Bug，而是一条根因链**：搜索请求在 API 层/解析层抛出异常（域名死、限速 429、响应结构硬转换失败、模型解析脏数据），异常被页面 `catch` 静默吞掉（仅 `debugPrint`），UI 最终呈现与"无匹配结果"完全相同的状态 —— 用户看到的就是"搜不到"。

共检出 **13 个问题**：严重 3 / 高 3 / 中 3 / 低 4。

| 编号 | 严重度 | 模块 | 一句话描述 |
|------|--------|------|-----------|
| BUG-01 | 严重 | SearchPage | 搜索异常被静默吞掉，失败与"无结果"无法区分 |
| BUG-02 | 严重 | manga_api / anime_api | 搜索响应解析硬类型转换，结构不符即抛异常 |
| BUG-03 | 严重 | Comic 模型 | `Comic.fromJson` 字段解析不防类型错误，单条脏数据毁掉整页 |
| BUG-04 | 高 | HomePage | 耽美搜索索引加载失败后被永久缓存，后续搜索全部必败 |
| BUG-05 | 高 | HomePage | 耽美远程搜索结果与本地索引取交集，非热门作品被过滤 |
| BUG-06 | 高 | SearchPage | 搜索进行中清除/选标签，`_searching` 卡死致永久转圈 |
| BUG-07 | 中 | api_client | 无请求级域名容灾，死域名导致搜索间歇性失败 |
| BUG-08 | 中 | SearchPage | `_loadMore` 无竞态防护，旧分页数据污染新搜索结果 |
| BUG-09 | 中 | api_client | 401 自动重登录重试无次数上限，潜在死循环 |
| BUG-10 | 低 | api_client | GET 请求全局携带语义错误的 `Content-Encoding` 头 |
| BUG-11 | 低 | manga_api | 热门关键词 `keyword as String` 硬转换 |
| BUG-12 | 低 | network_api | 测速 `SecureSocket` 连接未关闭，泄漏 TLS 连接 |
| BUG-13 | 低 | HomePage | 繁简归一化映射不完整且含死代码，部分繁体作品名搜不到 |

---

## 1. 搜索功能完整链路

项目中有**两个独立搜索框**：

### 1.1 全局搜索（SearchPage，`lib/pages/search_page.dart`）

```
SearchBar (onSubmitted)                          ← 仅键盘回车/搜索键触发，无 onChanged、无可见搜索按钮
  └─ _doSearch(query)                            ← search_page.dart:115
       ├─ _api.searchComics(keyword)             ← manga_api.dart:107  (漫画模式)
       │    └─ _get('/api/v3/search/comic', ...) ← api_client.dart:261
       │         └─ _url(path, host) → _nextHost()  ← host 参数被忽略！
       │              └─ _dio.get(url, queryParameters)
       │                   └─ resp.data['results'] → data['list'] / data['total']
       │                        └─ Comic.fromJson(e)   ← 危险解析
       └─ _api.searchAnimes(keyword)             ← anime_api.dart:30  (动漫模式)
            └─ _get('/api/v3/search/cartoon', ...)
       ↓ setState
  _ComicGrid / _AnimeGrid 渲染结果
```

### 1.2 首页耽美搜索（HomePage，`lib/pages/home_page.dart`）

```
SearchBar (onChanged → 450ms debounce → _searchDanmei)   ← home_page.dart:239
  └─ _searchDanmei(query)                                ← home_page.dart:186
       ├─ _ensureDanmeiSearchIndex()                     ← 全量拉取耽美列表建本地索引（失败永久缓存！）
       ├─ 本地匹配 _matchesKeyword（繁简归一化 contains）
       ├─ _api.searchComics(keyword, theme: 'danmei')    ← 远程搜索
       ├─ remoteMatches ∩ 本地索引 pathWord 集合          ← 交集过滤（过滤掉非热门作品！）
       └─ _dedupeComics([...remoteMatches, ...localMatches])
```

---

## 2. 搜索相关 Bug 明细

### BUG-01【严重】搜索异常被静默吞掉，失败与"无结果"无法区分

- **位置**：`lib/pages/search_page.dart:150-153`（`_doSearch` 的 catch 块）
- **代码**：
  ```dart
  } catch (e) {
    debugPrint('SearchPage search error: $e');
    if (mounted) setState(() => _searching = false);
  }
  ```
- **根因**：搜索链路上任何异常（网络超时、429 限速、域名不可达、JSON 解析 TypeError）都只打印日志，**不设置任何错误状态、不弹 SnackBar**。失败后 UI 状态为 `_searchQuery != null` + 结果列表为空 + `_searching = false`，渲染结果与"没有匹配作品"完全一致（甚至还会重新展示"热门搜索"关键词区）。
- **影响范围**：全局搜索（漫画+动漫）。这是用户报告"搜不到作品"的**最终表现机制**——后面 BUG-02/03/07 抛出的所有异常，都以"搜不到"的形式呈现。
- **修复建议**：增加 `_searchError` 状态，catch 中记录 `NetworkError.message(e)`，在结果区渲染错误提示 + 重试按钮；至少用 SnackBar 提示用户。

### BUG-02【严重】搜索接口响应解析硬类型转换，结构不符即抛异常

- **位置**：
  - `lib/api/manga/manga_api.dart:122-124`（`searchComics`）
  - `lib/api/anime/anime_api.dart:47-50`（`searchAnimes`）
  - `lib/api/api_client.dart:270`（`_get` 的 `return resp.data['results']`）
- **代码**：
  ```dart
  final data = await _get('/api/v3/search/comic', params: params);
  final list = (data['list'] as List).map((e) => Comic.fromJson(e)).toList();
  return (list: list, total: data['total'] as int);
  ```
- **根因**：
  1. `data['list'] as List`：`results` 中缺 `list` 或为 null → TypeError；
  2. `data['total'] as int`：`total` 为 null / String / double → TypeError；
  3. `_get` 直接返回 `resp.data['results']`：服务端返回非预期结构（HTML 错误页、无 results 的 JSON）→ 返回 null 触发 TypeError（返回类型为非空 `Map<String, dynamic>`）。
- **关键证据（代码库自身不一致）**：同一代码库的动漫接口已采用防御式写法——`getAnimeUpdates`/`getAnimeChapters`/`getAnimeBookshelf` 均使用 `data['list'] as List? ?? const []` 和 `data['total'] as int? ?? list.length`（anime_api.dart:27/82/108/125/161），**唯独两个搜索接口用裸硬转换**。说明防御式写法是团队既定约定，搜索接口是遗漏。
- **影响范围**：漫画搜索、动漫搜索。与 BUG-01 叠加 = 静默"搜不到"。
- **修复建议**：对齐项目既有防御式约定：`data['list'] as List? ?? const []`、`data['total'] as int? ?? list.length`；`_get` 对 `results` 做 null 检查并抛出带上下文的业务异常。

### BUG-03【严重】Comic.fromJson 字段解析不防类型错误，单条脏数据毁掉整页结果

- **位置**：`lib/models/comic.dart:152-178`
- **代码**：
  ```dart
  factory Comic.fromJson(Map<String, dynamic> json) => Comic(
    name: json['name'] ?? '',          // name 为数字/Map 时 TypeError
    pathWord: json['path_word'] ?? '', // 同上
    cover: json['cover'] ?? '',        // 同上
    popular: json['popular'] ?? 0,     // popular 为 "123"(String) 或 double 时 TypeError
    authors: (json['author'] as List?)?.map((a) => Author.fromJson(a)).toList() ?? [],
    // author 列表元素若为 String（部分接口作者是字符串）→ Author.fromJson 参数类型不符抛异常
    ...
  );
  ```
- **根因**：`??` 只防 null 不防类型错误。搜索结果列表用单个 `map()` 整体解析，**列表中任何一条脏数据都会使整页解析抛异常**，全部结果作废（all-or-nothing），异常再被 BUG-01 吞掉。
- **关键证据（代码库自身不一致）**：`Anime.fromJson`（anime.dart:68-102）全部字段使用 `?.toString() ?? ''`、`as int? ?? 0` 防御式解析；`MangaBanner.fromJson`（comic.dart:26-33）同样使用 `?.toString() ?? ''`。**`Comic.fromJson` 是唯一的非安全解析**，而它恰恰是漫画搜索的解析入口。
- **影响范围**：漫画搜索、漫画列表、首页、排行榜、书架等所有使用 `Comic.fromJson` 的链路。
- **修复建议**：与 `Anime.fromJson` 对齐：`name: json['name']?.toString() ?? ''`、`popular: json['popular'] as int? ?? 0`（或 `int.tryParse`）；`Author.fromJson` 前加 `whereType<Map>()`。

### BUG-04【高】耽美搜索索引加载失败被永久缓存，后续搜索全部必败

- **位置**：`lib/pages/home_page.dart:151-184`
- **代码**：
  ```dart
  Future<List<Comic>> _ensureDanmeiSearchIndex() {
    final existing = _danmeiSearchIndex;
    if (existing != null) return Future.value(existing);
    return _danmeiSearchIndexFuture ??= _loadDanmeiSearchIndex();
  }
  ```
- **根因**：`_loadDanmeiSearchIndex()` 抛异常后，**失败的 Future 被 `??=` 永久缓存**，不会重试。此后每次 `_searchDanmei` 都 await 同一个已失败的 Future → catch → 显示错误。HomePage 是常驻 Tab，该状态持续整个应用会话，**一次失败 = 耽美搜索永久瘫痪**（需杀进程重启）。
- **触发条件很容易满足**：`_loadDanmeiSearchIndex` 用 `Future.wait` **并发拉取全部分页**（`total/50` 个并发请求）。耽美作品若有上千部，瞬间发出几十个并发请求 → 触发服务端 429 限速（项目专门实现了 `rateLimitInterceptor`，证明服务端确有限速）→ `Future.wait` 整体失败。
- **影响范围**：首页耽美搜索全功能。
- **修复建议**：失败时清空 `_danmeiSearchIndexFuture = null` 允许下次重试；分页改为串行分批（如每批 5 页、批间间隔）或限制并发数，避免触发限速。

### BUG-05【高】耽美远程搜索结果与本地索引取交集，非热门作品被过滤

- **位置**：`lib/pages/home_page.dart:200-213`
- **代码**：
  ```dart
  final indexPathWords = index.map((comic) => comic.pathWord).toSet();
  ...
  final remoteMatches = remoteResult.list
      .where((comic) => indexPathWords.contains(comic.pathWord))
      .toList();
  ```
- **根因**：远程搜索已经用 `theme: danmeiThemePathWord` 限定了耽美分类，返回的就是合法耽美结果；但代码又要求远程结果的 `pathWord` 必须存在于本地索引中。本地索引按 `-popular`（热度序）拉取，**新上架/冷门作品不在索引中 → 服务端明明搜到了却被丢弃** → 用户看到"没有找到耽美漫画"。此外索引加载部分失败时（配合 BUG-04 的降级场景），交集过滤会误杀更多结果。
- **影响范围**：首页耽美搜索——冷门、新上架耽美作品永远搜不到。
- **修复建议**：删除交集过滤，远程结果直接参与合并（`_dedupeComics` 已按 pathWord 去重，不会重复）。

### BUG-06【高】搜索进行中清除/选标签，_searching 卡死致永久转圈

- **位置**：`lib/pages/search_page.dart:115-154`（`_doSearch`）、`264-273`（`_clearSearch`）、`246-262`（`_selectTag`）
- **根因**：`_doSearch` 成功后有守卫 `if (!mounted || _mode != mode || _searchQuery != keyword) return;`——守卫命中时**直接 return，不恢复 `_searching = false`**；而 `_clearSearch` / `_selectTag` 把 `_searchQuery` 置 null 时也**不重置 `_searching`**。
- **复现步骤**：
  1. 输入关键词提交搜索（`_searching = true`）；
  2. 响应返回前点击搜索框右侧 X 清除（`_searchQuery = null`，`_searching` 仍为 true）；
  3. 响应到达，守卫 `_searchQuery != keyword` 命中 → 提前 return；
  4. `_searching` 永久为 true → `SliverFillRemaining(CircularProgressIndicator)` 永久渲染；"全部标签"区（要求 `!_searching`）和"热门搜索"区同时消失，页面只剩搜索框 + 永久转圈。
- **影响范围**：全局搜索页。用户需再次提交一次成功搜索才能解除卡死状态。
- **修复建议**：守卫提前返回前补 `setState(() => _searching = false)`；或 `_clearSearch`/`_selectTag` 中主动重置 `_searching = false`。

### BUG-07【中】API 层无请求级域名容灾，死域名导致搜索间歇性失败

- **位置**：`lib/api/api_client.dart:202-231`（`_nextHost`/`_url`）、`261-271`（`_get`）；权重更新在 `lib/api/network/network_api.dart:30-36`
- **代码**：
  ```dart
  String _url(String path, [String? _]) => 'https://${_nextHost()}$path';
  ```
- **根因**：
  1. **host 参数被静默丢弃**：`_get(..., host: _hostSd)` 传入的 host 被 `_url` 的匿名参数 `_` 忽略（仅 `_hostMangaHome` 例外）。调用方以为指定了域名，实际无效——误导维护，且一旦某端点必须走特定域名就会出错。
  2. **无失败重试切换**：`_nextHost()` 按权重随机选域名，请求失败后**不会换域名重试**（onError 拦截器只处理 401 重登录）。权重仅在用户手动执行"线路测速"时更新，默认全部 1.0。
  3. 后果：线路组中任一域名死亡且用户未测速时，约 1/3 的搜索请求直接超时失败 → 被 BUG-01 吞掉 → **间歇性"搜不到"**（多试几次又能搜到，与用户报告的模糊症状高度吻合）。所谓"多域名容灾"实际只有负载均衡，没有容灾。
- **影响范围**：全部经 `_get` 的接口（搜索、列表、详情、章节等）。
- **修复建议**：`_get` 失败（超时/连接错误/5xx）时自动切换 `_nextHost()` 重试 1-2 次；请求失败时主动衰减对应域名权重；明确 host 参数语义（要么生效、要么删除参数）。

### BUG-08【中】_loadMore 无竞态防护，旧分页数据污染新搜索结果

- **位置**：`lib/pages/search_page.dart:188-226`
- **根因**：`_loadMore` 在 `await` 之后直接 `_comics.addAll(result.list)`，**不校验 `_searchQuery` / `_mode` 是否已变化**。用户在"加载更多"请求在途时提交新搜索或清除搜索，旧关键词的分页结果会被追加进新列表（或使已清空的列表"复活"旧数据），`_offset` 也随之错乱，后续分页继续错位。
- **对比**：`_doSearch` 至少有 `_searchQuery != keyword` 守卫（虽然引发了 BUG-06），`_loadMore` 完全没有。
- **影响范围**：搜索结果翻页场景，表现为结果列表混入无关作品。
- **修复建议**：请求前记录 `query = _searchQuery; mode = _mode`，`await` 后校验一致再 setState。

### BUG-09【中】401 自动重登录重试无次数上限，潜在死循环

- **位置**：`lib/api/api_client.dart:150-195`（onError 拦截器）
- **根因**：401 → 自动登录成功 → `_dio.fetch(opts)` 重试原请求。重试会**再次走完整拦截器链**；若服务端 token 异常导致重试仍 401，将再次触发登录 + 重试，**没有重试计数/上限**。只要登录接口本身成功（返回任意 token），就会无限循环。
- **影响范围**：所有携带 Authorization 的请求（含登录态下的搜索）。
- **修复建议**：在 requestOptions.extra 中记录重试次数，超过 1 次不再重登录。

---

## 3. 其他模块 Bug

### BUG-10【低】GET 请求全局携带语义错误的 Content-Encoding 头

- **位置**：`lib/api/api_client.dart:81`
- **代码**：`'Content-Encoding': 'gzip, compress, br'`（onRequest 拦截器全局注入）
- **根因**：`Content-Encoding` 描述**请求体**的编码方式，GET 无请求体；协商响应压缩应使用 `Accept-Encoding`（Dio 已自动添加）。严格 CDN/代理可能因该头拒绝请求或行为异常，不同域名网关处理不一致——可能是个别域名搜索失败的诱因之一。
- **修复建议**：删除该行，或改为确认各端点确实需要。

### BUG-11【低】热门关键词解析硬转换

- **位置**：`lib/api/manga/manga_api.dart:24`
- **代码**：`(data['list'] as List).map((e) => e['keyword'] as String).toList()`
- **根因**：`keyword` 为 null 或非字符串时抛异常，整个热门关键词区消失（被 `_loadInit` catch 降级，不致命，但搜索页推荐功能失效）。
- **修复建议**：`e['keyword']?.toString()` + `whereType`/null 过滤。

### BUG-12【低】线路测速 SecureSocket 连接未关闭

- **位置**：`lib/api/network/network_api.dart:17-23`
- **根因**：`await SecureSocket.connect(host, 443, ...)` 成功后未调用 `socket.destroy()/close()`，每次测速泄漏 3 个 TLS 连接。
- **修复建议**：`final socket = await SecureSocket.connect(...); socket.destroy();`。

### BUG-13【低】繁简归一化映射不完整且含死代码

- **位置**：`lib/pages/home_page.dart:262-307`（`_normalizeSearchText`）
- **根因**：
  1. 映射表中 `'漫畫': '漫画'` 排在 `'畫': '画'` 之后，执行到它时 `漫畫` 早已变成 `漫画`，**该条永远不生效**（死代码，结果不受影响）；
  2. 映射仅覆盖约 30 个繁体字，作品名含其他繁体字（如 說/劍/俠/鬥）时，用简体搜索无法命中本地索引；
  3. 项目已有 `utils/chinese_converter.dart`（繁化姬 API）可作完整繁简转换，但本地搜索匹配未使用。
- **影响范围**：首页耽美搜索的本地匹配召回率。
- **修复建议**：删除死代码条目；对作品名和关键词做完整繁→简转换后再匹配（可离线内置映射表，避免依赖网络 API）。

---

## 4. "搜索框搜不到作品"根因链总结

```
用户输入关键词并提交
      │
      ▼
_doSearch / _searchDanmei
      │
      ├──(a) _nextHost 选中死域名 → 连接超时          ┐
      ├──(b) 服务端 429 限速（索引并发拉取诱发）        │  全部异常
      ├──(c) results/list/total 结构不符 → TypeError  ├─ 被 catch 静默吞掉
      ├──(d) Comic.fromJson 遇脏数据 → TypeError      │  (仅 debugPrint)
      └──(e) 耽美交集过滤丢弃冷门作品 (BUG-05)         ┘
      │
      ▼
UI 状态 = _searchQuery 非空 + 结果列表空 + 无错误提示
      │
      ▼
用户看到："搜不到作品"（与真正无匹配无法区分）
```

**修复优先级建议**：
1. **P0**：BUG-01（错误可见化）+ BUG-02/BUG-03（解析防御化）——三者联合修复后，"搜不到"要么消失，要么变成可读的错误提示，问题可定位、可复现；
2. **P1**：BUG-04/BUG-05（耽美搜索可用性）+ BUG-06（状态卡死）；
3. **P2**：BUG-07（请求级容灾重试）+ BUG-08/BUG-09（竞态与重试上限）；
4. **P3**：BUG-10 ~ BUG-13。

---

## 5. 检测方法说明

- 逐文件阅读搜索链路全部源码：`search_page.dart`、`home_page.dart`、`api_client.dart`、`manga_api.dart`、`anime_api.dart`、`network_api.dart`、`comic.dart`、`anime.dart`、`data_cache.dart`、`network_error.dart`、`user_manager.dart`（token/apiRoute 相关段落）；
- 以代码库自身的防御式解析约定（anime_api 各接口、Anime.fromJson）为对照基准，识别不一致的危险写法；
- 对状态机做时序推演（搜索在途 + 清除/切换模式/加载更多等交叉操作）定位竞态与状态卡死；
- 本报告为纯静态代码分析结论，未运行应用、未修改任何源文件。BUG-02/03 是否被线上数据实际触发，取决于服务端当前响应结构，建议后续用真实抓包或集成测试验证。
